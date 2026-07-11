import Foundation
import SMCLowLevel

public protocol SMCTransport: AnyObject {
    func read(key: String) throws -> Data
    func write(key: String, bytes: Data) throws
}

public enum SMCTransportError: LocalizedError, Equatable {
    case invalidKey(String)
    case openFailed(Int32)
    case readFailed(String, Int32)
    case writeFailed(String, Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidKey(let key): "Invalid four-character SMC key: \(key)"
        case .openFailed(let code): "AppleSMC could not be opened (IOKit \(code))."
        case .readFailed(let key, let code): "SMC key \(key) could not be read (IOKit \(code))."
        case .writeFailed(let key, let code): "SMC key \(key) could not be written (IOKit \(code))."
        }
    }
}

public final class AppleSMCTransport: SMCTransport, @unchecked Sendable {
    private var connection: CLSMCConnectionRef = 0

    public init() throws {
        let result = CLSMCOpen(&connection)
        guard result == 0 else { throw SMCTransportError.openFailed(result) }
    }

    deinit {
        CLSMCClose(connection)
    }

    public func read(key: String) throws -> Data {
        let keyBytes = try validatedKeyBytes(key)
        var output = [UInt8](repeating: 0, count: 32)
        var length = output.count
        let result = keyBytes.withUnsafeBufferPointer { keyBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                CLSMCReadKey(connection, keyBuffer.baseAddress, outputBuffer.baseAddress, &length)
            }
        }
        guard result == 0 else { throw SMCTransportError.readFailed(key, result) }
        return Data(output.prefix(length))
    }

    public func write(key: String, bytes: Data) throws {
        let keyBytes = try validatedKeyBytes(key)
        let result = keyBytes.withUnsafeBufferPointer { keyBuffer in
            bytes.withUnsafeBytes { dataBuffer in
                CLSMCWriteKey(
                    connection,
                    keyBuffer.baseAddress,
                    dataBuffer.bindMemory(to: UInt8.self).baseAddress,
                    bytes.count
                )
            }
        }
        guard result == 0 else { throw SMCTransportError.writeFailed(key, result) }
    }

    private func validatedKeyBytes(_ key: String) throws -> [CChar] {
        let bytes = Array(key.utf8)
        guard bytes.count == 4, bytes.allSatisfy({ $0 < 128 }) else {
            throw SMCTransportError.invalidKey(key)
        }
        return bytes.map { CChar(bitPattern: $0) }
    }
}
