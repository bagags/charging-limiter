import Foundation

public struct BatterySnapshot: Codable, Equatable, Sendable {
    public let percent: Int
    public let onAC: Bool
    public let charging: Bool
    public let adapterEnabled: Bool
    public let awake: Bool
    public let lidOpen: Bool

    public init(
        percent: Int,
        onAC: Bool,
        charging: Bool,
        adapterEnabled: Bool,
        awake: Bool,
        lidOpen: Bool
    ) {
        self.percent = min(max(percent, 0), 100)
        self.onAC = onAC
        self.charging = charging
        self.adapterEnabled = adapterEnabled
        self.awake = awake
        self.lidOpen = lidOpen
    }
}

public enum LimiterState: String, Codable, CaseIterable, Sendable {
    case normal
    case chargingToLimit
    case dischargingToLimit
    case holdingAtLimit
    case pausedForSleep
    case faulted

    public var displayName: String {
        switch self {
        case .normal: "Normal charging"
        case .chargingToLimit: "Charging to limit"
        case .dischargingToLimit: "Discharging to limit"
        case .holdingAtLimit: "Holding at limit"
        case .pausedForSleep: "Paused while sleeping"
        case .faulted: "Charging control unavailable"
        }
    }
}

public enum HardwareCommand: String, Codable, Equatable, Sendable {
    case enableAdapter
    case disableAdapter
    case enableCharging
    case disableCharging
}

public struct LimiterDecision: Equatable, Sendable {
    public let state: LimiterState
    public let commands: [HardwareCommand]
    public let holdIdleSleep: Bool

    public init(state: LimiterState, commands: [HardwareCommand], holdIdleSleep: Bool = false) {
        self.state = state
        self.commands = commands
        self.holdIdleSleep = holdIdleSleep
    }
}

public struct DaemonStatus: Codable, Equatable, Sendable {
    public let configuration: LimiterConfiguration
    public let snapshot: BatterySnapshot?
    public let state: LimiterState
    public let faultMessage: String?

    public init(
        configuration: LimiterConfiguration,
        snapshot: BatterySnapshot?,
        state: LimiterState,
        faultMessage: String? = nil
    ) {
        self.configuration = configuration
        self.snapshot = snapshot
        self.state = state
        self.faultMessage = faultMessage
    }
}
