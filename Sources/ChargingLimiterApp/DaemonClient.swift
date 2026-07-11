import ChargingLimiterCore
import Foundation

final class DaemonClient: @unchecked Sendable {
    private var connection: NSXPCConnection?
    private let lock = NSLock()

    func getStatus() async throws -> DaemonStatus {
        try await call { proxy, reply in proxy.getStatus(withReply: reply) }
    }

    func setLimit(_ limitPercent: Int) async throws -> DaemonStatus {
        try await call { proxy, reply in proxy.setLimit(limitPercent, withReply: reply) }
    }

    func setEnabled(_ enabled: Bool) async throws -> DaemonStatus {
        try await call { proxy, reply in proxy.setEnabled(enabled, withReply: reply) }
    }

    func restoreHardware() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let proxy = try remoteProxy { error in
                    continuation.resume(throwing: error)
                }
                proxy.restoreHardware { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: ()) }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func invalidate() {
        lock.lock()
        let oldConnection = connection
        connection = nil
        lock.unlock()
        oldConnection?.invalidate()
    }

    private func call(
        _ operation: @escaping (
            ChargingLimiterDaemonXPC,
            @escaping (Data?, NSError?) -> Void
        ) -> Void
    ) async throws -> DaemonStatus {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<DaemonStatus, Error>) in
            do {
                let proxy = try remoteProxy { error in
                    continuation.resume(throwing: error)
                }
                operation(proxy) { data, error in
                    do {
                        if let error { throw error }
                        guard let data else { throw DaemonClientError.emptyReply }
                        continuation.resume(returning: try DaemonStatusCodec.decode(data))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func remoteProxy(
        errorHandler: @escaping @Sendable (Error) -> Void
    ) throws -> ChargingLimiterDaemonXPC {
        let connection = activeConnection()
        guard let proxy = connection.remoteObjectProxyWithErrorHandler(errorHandler)
            as? ChargingLimiterDaemonXPC else {
            throw DaemonClientError.invalidProxy
        }
        return proxy
    }

    private func activeConnection() -> NSXPCConnection {
        lock.lock()
        defer { lock.unlock() }
        if let connection { return connection }

        let newConnection = NSXPCConnection(
            machServiceName: ChargingLimiterIdentifiers.daemonMachService,
            options: .privileged
        )
        newConnection.remoteObjectInterface = NSXPCInterface(with: ChargingLimiterDaemonXPC.self)
        newConnection.invalidationHandler = { [weak self] in
            self?.lock.lock()
            self?.connection = nil
            self?.lock.unlock()
        }
        newConnection.resume()
        connection = newConnection
        return newConnection
    }
}

enum DaemonClientError: LocalizedError {
    case invalidProxy
    case emptyReply

    var errorDescription: String? {
        switch self {
        case .invalidProxy: "The charging daemon returned an invalid XPC connection."
        case .emptyReply: "The charging daemon returned an empty response."
        }
    }
}
