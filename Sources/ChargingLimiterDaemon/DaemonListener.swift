import ChargingLimiterCore
import Foundation
import OSLog

final class DaemonListener: NSObject, NSXPCListenerDelegate {
    private let logger = Logger(subsystem: ChargingLimiterIdentifiers.daemonBundle, category: "xpc")
    private let service: DaemonXPCService
    private let clientRequirement: String

    init(service: DaemonXPCService) {
        self.service = service
        clientRequirement = ProcessInfo.processInfo.environment["CHARGING_LIMITER_CLIENT_REQUIREMENT"]
            ?? "identifier \"\(ChargingLimiterIdentifiers.appBundle)\""
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: ChargingLimiterDaemonXPC.self)
        connection.exportedObject = service
        connection.invalidationHandler = { [logger] in logger.debug("XPC client disconnected") }
        connection.resume()
        return true
    }
}
