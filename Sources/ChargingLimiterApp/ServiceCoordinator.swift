import ChargingLimiterCore
import Foundation
import OSLog
import ServiceManagement

enum HelperServiceState: Equatable {
    case loading
    case enabled
    case requiresApproval
    case notRegistered
    case unavailable
    case registrationFailed(String)

    var message: String? {
        switch self {
        case .loading: "Checking background helper…"
        case .enabled: nil
        case .requiresApproval: "Approve Charging Limiter under Allow in Background."
        case .notRegistered: "The charging helper is not registered."
        case .unavailable: "macOS could not locate the bundled charging helper."
        case .registrationFailed(let reason): "Could not register the charging helper: \(reason)"
        }
    }
}

@MainActor
final class ServiceCoordinator {
    private let logger = Logger(
        subsystem: ChargingLimiterIdentifiers.appBundle,
        category: "service-management"
    )
    private let daemonService = SMAppService.daemon(plistName: ChargingLimiterIdentifiers.daemonPlist)
    private let loginService = SMAppService.mainApp
    private var daemonRegistrationFailure: String?

    func registerRequiredServices() -> HelperServiceState {
        daemonRegistrationFailure = nil

        do {
            if daemonService.status == .notRegistered || daemonService.status == .notFound {
                try daemonService.register()
            }
        } catch {
            daemonRegistrationFailure = error.localizedDescription
            logger.error("Could not register charging daemon: \(error.localizedDescription, privacy: .public)")
        }

        do {
            if loginService.status == .notRegistered { try loginService.register() }
        } catch {
            // Launch-at-login is convenient but must never prevent the required daemon registration.
            logger.error("Could not register launch-at-login service: \(error.localizedDescription, privacy: .public)")
        }

        return helperState
    }

    var helperState: HelperServiceState {
        if let daemonRegistrationFailure,
           daemonService.status != .enabled,
           daemonService.status != .requiresApproval {
            return .registrationFailed(daemonRegistrationFailure)
        }

        return switch daemonService.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered: .notRegistered
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func unregisterDaemon() async throws {
        try await daemonService.unregister()
    }
}
