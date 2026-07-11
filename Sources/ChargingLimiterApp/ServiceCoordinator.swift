import ChargingLimiterCore
import Foundation
import ServiceManagement

enum HelperServiceState: Equatable {
    case loading
    case enabled
    case requiresApproval
    case notRegistered
    case unavailable

    var message: String? {
        switch self {
        case .loading: "Checking background helper…"
        case .enabled: nil
        case .requiresApproval: "Approve Charging Limiter under Allow in Background."
        case .notRegistered: "The charging helper is not registered."
        case .unavailable: "The charging helper is missing from this app build."
        }
    }
}

@MainActor
final class ServiceCoordinator {
    private let daemonService = SMAppService.daemon(plistName: ChargingLimiterIdentifiers.daemonPlist)
    private let loginService = SMAppService.mainApp

    func registerRequiredServices() -> HelperServiceState {
        do {
            if loginService.status == .notRegistered { try loginService.register() }
            if daemonService.status == .notRegistered { try daemonService.register() }
        } catch {
            // Status below gives the UI a recoverable action for expected approval errors.
        }
        return helperState
    }

    var helperState: HelperServiceState {
        switch daemonService.status {
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
