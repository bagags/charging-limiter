import ChargingLimiterCore
import Foundation

final class DaemonXPCService: NSObject, ChargingLimiterDaemonXPC {
    private let controller: DaemonController

    init(controller: DaemonController) {
        self.controller = controller
    }

    func getStatus(withReply reply: @escaping (Data?, NSError?) -> Void) {
        do {
            reply(try DaemonStatusCodec.encode(controller.status()), nil)
        } catch {
            reply(nil, error.asNSError)
        }
    }

    func setLimit(_ limitPercent: Int, withReply reply: @escaping (Data?, NSError?) -> Void) {
        do {
            reply(try DaemonStatusCodec.encode(controller.setLimit(limitPercent)), nil)
        } catch {
            reply(nil, error.asNSError)
        }
    }

    func setEnabled(_ enabled: Bool, withReply reply: @escaping (Data?, NSError?) -> Void) {
        do {
            reply(try DaemonStatusCodec.encode(controller.setEnabled(enabled)), nil)
        } catch {
            reply(nil, error.asNSError)
        }
    }

    func restoreHardware(withReply reply: @escaping (NSError?) -> Void) {
        do {
            try controller.restoreHardware()
            reply(nil)
        } catch {
            reply(error.asNSError)
        }
    }

}

private extension Error {
    var asNSError: NSError {
        NSError(
            domain: ChargingLimiterIdentifiers.daemonBundle,
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: localizedDescription]
        )
    }
}
