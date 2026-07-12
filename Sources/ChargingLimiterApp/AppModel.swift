import AppKit
import ChargingLimiterCore
import ChargingLimiterSystem
import Foundation

@MainActor
final class AppModel: ObservableObject {
    private enum Keys {
        static let limit = "configuration.limitPercent"
        static let enabled = "configuration.isEnabled"
        static let didShowBatteryAdvice = "onboarding.didShowBatteryAdvice"
    }

    @Published private(set) var limitPercent: Int
    @Published private(set) var limiterEnabled: Bool
    @Published private(set) var batteryPercent: Int?
    @Published private(set) var onAC = false
    @Published private(set) var limiterState: LimiterState = .normal
    @Published private(set) var helperState: HelperServiceState = .loading
    @Published private(set) var chargingControlAvailable = true
    @Published private(set) var notificationPermission: NotificationPermission = .unknown
    @Published private(set) var faultMessage: String?
    @Published private(set) var showBatterySettingsAdvice: Bool

    private let defaults: UserDefaults
    private let daemonClient = DaemonClient()
    private let services = ServiceCoordinator()
    private let notifications: NotificationCoordinator
    private var powerMonitor: PowerSourceMonitor?
    private var pollTask: Task<Void, Never>?
    private var configurationTask: Task<Void, Never>?
    private var started = false
    private var hasSynchronizedConfiguration = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedLimit = defaults.object(forKey: Keys.limit) as? Int ?? 80
        limitPercent = min(max(storedLimit, 50), 100)
        limiterEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        showBatterySettingsAdvice = !defaults.bool(forKey: Keys.didShowBatteryAdvice)
        notifications = NotificationCoordinator(defaults: defaults)
    }

    var statusText: String {
        if let faultMessage, !faultMessage.isEmpty { return faultMessage }
        if !limiterEnabled { return "Limiter off · notifications on" }
        if !onAC { return "Running on battery" }
        return limiterState.displayName
    }

    var menuBarSymbol: String {
        faultMessage == nil ? "battery.100" : "battery.0"
    }

    var usesAdapterOnlyControl: Bool { !chargingControlAvailable }

    func start() {
        guard !started else { return }
        started = true
        helperState = services.registerRequiredServices()

        let monitor = PowerSourceMonitor { [weak self] result in
            Task { @MainActor in self?.handlePowerResult(result) }
        }
        powerMonitor = monitor
        monitor.start()

        pollTask = Task { [weak self] in
            guard let self else { return }
            notificationPermission = await notifications.requestPermission()
            while !Task.isCancelled {
                await refreshDaemonStatus()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func setLimit(_ value: Int) {
        let value = min(max(value, 50), 100)
        guard value != limitPercent else { return }
        limitPercent = value
        defaults.set(value, forKey: Keys.limit)
        if let batteryPercent {
            Task { await notifications.process(percent: batteryPercent, limit: value) }
        }
        scheduleConfigurationUpdate { client in try await client.setLimit(value) }
    }

    func setLimiterEnabled(_ enabled: Bool) {
        guard enabled != limiterEnabled else { return }
        limiterEnabled = enabled
        defaults.set(enabled, forKey: Keys.enabled)
        configurationTask?.cancel()
        configurationTask = Task { [weak self] in
            guard let self else { return }
            do {
                apply(status: try await daemonClient.setEnabled(enabled))
            } catch {
                faultMessage = error.localizedDescription
                helperState = services.helperState
            }
        }
    }

    func approveHelper() {
        services.openLoginItems()
    }

    func openNotificationSettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.Notifications-Settings.extension")
    }

    func openBatterySettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.Battery-Settings.extension")
    }

    func dismissBatteryAdvice() {
        showBatterySettingsAdvice = false
        defaults.set(true, forKey: Keys.didShowBatteryAdvice)
    }

    func removeHelper() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await daemonClient.restoreHardware()
                try await services.unregisterDaemon()
                daemonClient.invalidate()
                hasSynchronizedConfiguration = false
                helperState = services.helperState
                limiterState = .normal
            } catch {
                faultMessage = "Could not remove helper: \(error.localizedDescription)"
            }
        }
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func handlePowerResult(_ result: Result<PowerSourceReading, Error>) {
        switch result {
        case .success(let reading):
            batteryPercent = reading.percent
            onAC = reading.onAC
            Task { await notifications.process(percent: reading.percent, limit: limitPercent) }
        case .failure(let error):
            faultMessage = error.localizedDescription
        }
    }

    private func refreshDaemonStatus() async {
        helperState = services.helperState
        guard helperState == .enabled else { return }
        do {
            var status = try await daemonClient.getStatus()
            if !hasSynchronizedConfiguration {
                if status.configuration.limitPercent != limitPercent {
                    status = try await daemonClient.setLimit(limitPercent)
                }
                if status.configuration.isEnabled != limiterEnabled {
                    status = try await daemonClient.setEnabled(limiterEnabled)
                }
                hasSynchronizedConfiguration = true
            }
            apply(status: status)
        } catch {
            faultMessage = error.localizedDescription
        }
        notificationPermission = await notifications.permissionState()
    }

    private func apply(status: DaemonStatus) {
        limitPercent = status.configuration.limitPercent
        limiterEnabled = status.configuration.isEnabled
        defaults.set(limitPercent, forKey: Keys.limit)
        defaults.set(limiterEnabled, forKey: Keys.enabled)
        limiterState = status.state
        faultMessage = status.faultMessage
        if let snapshot = status.snapshot {
            batteryPercent = snapshot.percent
            onAC = snapshot.onAC
            chargingControlAvailable = snapshot.chargingControlAvailable
        }
    }

    private func scheduleConfigurationUpdate(
        operation: @escaping @Sendable (DaemonClient) async throws -> DaemonStatus
    ) {
        configurationTask?.cancel()
        configurationTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            do {
                apply(status: try await operation(daemonClient))
            } catch {
                faultMessage = error.localizedDescription
                helperState = services.helperState
            }
        }
    }

    private func openSystemSettings(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
