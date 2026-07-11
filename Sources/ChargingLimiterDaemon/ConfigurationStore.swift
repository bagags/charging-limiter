import ChargingLimiterCore
import Darwin
import Foundation

final class ConfigurationStore: @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder = PropertyListEncoder()
    private let decoder = PropertyListDecoder()

    init(
        fileURL: URL = URL(fileURLWithPath: "/Library/Application Support/ChargingLimiter/config.plist"),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        encoder.outputFormat = .binary
    }

    func load() throws -> LimiterConfiguration {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            try save(.default)
            return .default
        }
        do {
            return try decoder.decode(LimiterConfiguration.self, from: Data(contentsOf: fileURL))
        } catch {
            throw LimiterError.configurationFailure(error.localizedDescription)
        }
    }

    func save(_ configuration: LimiterConfiguration) throws {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try encoder.encode(configuration).write(to: fileURL, options: .atomic)
            guard chmod(fileURL.path, 0o600) == 0 else {
                throw POSIXError(.EACCES)
            }
        } catch {
            throw LimiterError.configurationFailure(error.localizedDescription)
        }
    }
}
