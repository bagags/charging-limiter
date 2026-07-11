import Foundation

public struct LimiterConfiguration: Codable, Equatable, Sendable {
    public static let allowedLimits = 50...100
    public static let `default` = LimiterConfiguration(uncheckedLimitPercent: 80, isEnabled: true)

    public let limitPercent: Int
    public let isEnabled: Bool

    public init(limitPercent: Int, isEnabled: Bool) throws {
        guard Self.allowedLimits.contains(limitPercent) else {
            throw LimiterError.invalidLimit(limitPercent)
        }
        self.limitPercent = limitPercent
        self.isEnabled = isEnabled
    }

    private init(uncheckedLimitPercent: Int, isEnabled: Bool) {
        limitPercent = uncheckedLimitPercent
        self.isEnabled = isEnabled
    }

    public func settingLimit(_ newLimit: Int) throws -> Self {
        try Self(limitPercent: newLimit, isEnabled: isEnabled)
    }

    public func settingEnabled(_ enabled: Bool) -> Self {
        Self(uncheckedLimitPercent: limitPercent, isEnabled: enabled)
    }
}

public enum LimiterError: LocalizedError, Equatable, Sendable {
    case invalidLimit(Int)
    case unsupportedHardware
    case hardwareFailure(String)
    case configurationFailure(String)

    public var errorDescription: String? {
        switch self {
        case .invalidLimit(let value):
            "The charge limit must be between 50% and 100% (received \(value)%)."
        case .unsupportedHardware:
            "This Mac does not expose the required Apple Silicon charging controls."
        case .hardwareFailure(let message):
            "Charging control failed: \(message)"
        case .configurationFailure(let message):
            "Configuration could not be saved: \(message)"
        }
    }
}
