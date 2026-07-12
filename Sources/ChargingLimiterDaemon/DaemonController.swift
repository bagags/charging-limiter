import ChargingLimiterCore
import ChargingLimiterHardware
import ChargingLimiterSystem
import Foundation
import OSLog

final class DaemonController: @unchecked Sendable {
    private let logger = Logger(subsystem: ChargingLimiterIdentifiers.daemonBundle, category: "controller")
    private let queue = DispatchQueue(label: "com.yangyi.ChargingLimiter.daemon.controller")
    private let store: ConfigurationStore
    private let hardware: SMCHardwareController
    private let powerReader: PowerSourceReader
    private let stateMachine: LimiterStateMachine
    private let idleSleepAssertion = IdleSleepAssertion()

    private var configuration: LimiterConfiguration
    private var currentStatus: DaemonStatus
    private var timer: DispatchSourceTimer?
    private var powerSourceMonitor: PowerSourceMonitor?
    private var systemPowerMonitor: SystemPowerMonitor?
    private var faulted = false

    init(
        store: ConfigurationStore = ConfigurationStore(),
        hardware: SMCHardwareController,
        powerReader: PowerSourceReader = PowerSourceReader(),
        stateMachine: LimiterStateMachine = LimiterStateMachine()
    ) throws {
        self.store = store
        self.hardware = hardware
        self.powerReader = powerReader
        self.stateMachine = stateMachine
        configuration = try store.load()
        currentStatus = DaemonStatus(
            configuration: configuration,
            snapshot: nil,
            state: .normal
        )
    }

    func start() {
        let sourceMonitor = PowerSourceMonitor { [weak self] _ in
            self?.requestEnforcement(clearFault: true)
        }
        powerSourceMonitor = sourceMonitor
        sourceMonitor.start()

        let systemMonitor = SystemPowerMonitor { [weak self] event in
            switch event {
            case .willSleep:
                self?.enforcePowerEventSynchronously()
            case .clamshellChanged:
                self?.requestEnforcement(clearFault: true)
            case .didWake:
                guard let controller = self else { return }
                controller.queue.asyncAfter(deadline: .now() + 5) { [weak controller] in
                    controller?.requestEnforcement(clearFault: true)
                }
            }
        }
        systemPowerMonitor = systemMonitor
        systemMonitor.start()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 10, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in self?.enforce(clearFault: false) }
        self.timer = timer
        timer.resume()
    }

    func status() -> DaemonStatus {
        queue.sync { currentStatus }
    }

    func setLimit(_ limitPercent: Int) throws -> DaemonStatus {
        try queue.sync {
            configuration = try configuration.settingLimit(limitPercent)
            try store.save(configuration)
            faulted = false
            enforceLocked()
            return currentStatus
        }
    }

    func setEnabled(_ enabled: Bool) throws -> DaemonStatus {
        try queue.sync {
            configuration = configuration.settingEnabled(enabled)
            try store.save(configuration)
            faulted = false
            enforceLocked()
            return currentStatus
        }
    }

    func restoreHardware() throws {
        try queue.sync {
            idleSleepAssertion.setHeld(false)
            try hardware.restoreSafely()
            let reading = try? powerReader.read()
            let hardwareState = try? hardware.readState()
            currentStatus = DaemonStatus(
                configuration: configuration,
                snapshot: makeSnapshot(reading: reading, hardwareState: hardwareState),
                state: .normal
            )
        }
    }

    func shutdown() {
        timer?.cancel()
        timer = nil
        powerSourceMonitor?.stop()
        systemPowerMonitor?.stop()
        do {
            try restoreHardware()
        } catch {
            logger.error("Safe restoration during shutdown failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func requestEnforcement(clearFault: Bool) {
        queue.async { [weak self] in self?.enforce(clearFault: clearFault) }
    }

    private func enforcePowerEventSynchronously() {
        queue.sync {
            faulted = false
            enforceLocked()
        }
    }

    private func enforce(clearFault: Bool) {
        if clearFault { faulted = false }
        guard !faulted else { return }
        enforceLocked()
    }

    private func enforceLocked() {
        do {
            let reading = try powerReader.read()
            let hardwareState = try hardware.readState()
            let snapshot = BatterySnapshot(
                percent: reading.percent,
                onAC: reading.onAC,
                charging: hardwareState.chargingControlAvailable
                    ? hardwareState.chargingEnabled
                    : reading.charging,
                adapterEnabled: hardwareState.adapterEnabled,
                chargingControlAvailable: hardwareState.chargingControlAvailable,
                awake: systemPowerMonitor?.isAwake ?? true,
                lidOpen: systemPowerMonitor?.isLidOpen ?? true
            )
            let decision = stateMachine.decide(configuration: configuration, snapshot: snapshot)

            for command in decision.commands {
                try hardware.execute(command)
            }
            idleSleepAssertion.setHeld(decision.holdIdleSleep)

            let verifiedHardwareState = try hardware.readState()
            let verifiedSnapshot = BatterySnapshot(
                percent: reading.percent,
                onAC: reading.onAC,
                charging: verifiedHardwareState.chargingControlAvailable
                    ? verifiedHardwareState.chargingEnabled
                    : reading.charging,
                adapterEnabled: verifiedHardwareState.adapterEnabled,
                chargingControlAvailable: verifiedHardwareState.chargingControlAvailable,
                awake: snapshot.awake,
                lidOpen: snapshot.lidOpen
            )
            currentStatus = DaemonStatus(
                configuration: configuration,
                snapshot: verifiedSnapshot,
                state: decision.state
            )
        } catch {
            handleFault(error)
        }
    }

    private func handleFault(_ error: Error) {
        idleSleepAssertion.setHeld(false)
        do {
            try hardware.restoreSafely()
        } catch {
            logger.error("Safe restoration after fault failed: \(error.localizedDescription, privacy: .public)")
        }
        faulted = true
        currentStatus = DaemonStatus(
            configuration: configuration,
            snapshot: nil,
            state: .faulted,
            faultMessage: error.localizedDescription
        )
        logger.error("Limiter faulted: \(error.localizedDescription, privacy: .public)")
    }

    private func makeSnapshot(
        reading: PowerSourceReading?,
        hardwareState: BatteryHardwareState?
    ) -> BatterySnapshot? {
        guard let reading, let hardwareState else { return nil }
        return BatterySnapshot(
            percent: reading.percent,
            onAC: reading.onAC,
            charging: hardwareState.chargingControlAvailable
                ? hardwareState.chargingEnabled
                : reading.charging,
            adapterEnabled: hardwareState.adapterEnabled,
            chargingControlAvailable: hardwareState.chargingControlAvailable,
            awake: systemPowerMonitor?.isAwake ?? true,
            lidOpen: systemPowerMonitor?.isLidOpen ?? true
        )
    }
}
