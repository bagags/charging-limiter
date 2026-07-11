import Foundation

public struct LimiterStateMachine: Sendable {
    public let hysteresisPercent: Int

    public init(hysteresisPercent: Int = 5) {
        self.hysteresisPercent = max(1, hysteresisPercent)
    }

    public func decide(
        configuration: LimiterConfiguration,
        snapshot: BatterySnapshot
    ) -> LimiterDecision {
        if !configuration.isEnabled || configuration.limitPercent == 100 {
            return LimiterDecision(
                state: .normal,
                commands: restoreNormalCommands(for: snapshot)
            )
        }

        if !snapshot.onAC {
            return LimiterDecision(
                state: .normal,
                commands: restoreNormalCommands(for: snapshot)
            )
        }

        if !snapshot.awake || !snapshot.lidOpen {
            var commands: [HardwareCommand] = []
            if !snapshot.adapterEnabled { commands.append(.enableAdapter) }
            if snapshot.charging { commands.append(.disableCharging) }
            return LimiterDecision(state: .pausedForSleep, commands: commands)
        }

        let limit = configuration.limitPercent
        let lowerBound = max(0, limit - hysteresisPercent)

        if snapshot.percent > limit {
            var commands: [HardwareCommand] = []
            if snapshot.charging { commands.append(.disableCharging) }
            if snapshot.adapterEnabled { commands.append(.disableAdapter) }
            return LimiterDecision(state: .dischargingToLimit, commands: commands)
        }

        if snapshot.percent == limit {
            var commands: [HardwareCommand] = []
            if !snapshot.adapterEnabled { commands.append(.enableAdapter) }
            if snapshot.charging { commands.append(.disableCharging) }
            return LimiterDecision(state: .holdingAtLimit, commands: commands)
        }

        if snapshot.percent < lowerBound {
            var commands: [HardwareCommand] = []
            if !snapshot.adapterEnabled { commands.append(.enableAdapter) }
            if !snapshot.charging { commands.append(.enableCharging) }
            return LimiterDecision(state: .chargingToLimit, commands: commands, holdIdleSleep: true)
        }

        // In the hysteresis band, stop any stale forced-discharge state but retain
        // the existing charging state to avoid rapid cycling.
        var commands: [HardwareCommand] = []
        if !snapshot.adapterEnabled { commands.append(.enableAdapter) }
        return LimiterDecision(
            state: snapshot.charging ? .chargingToLimit : .holdingAtLimit,
            commands: commands,
            holdIdleSleep: snapshot.charging
        )
    }

    private func restoreNormalCommands(for snapshot: BatterySnapshot) -> [HardwareCommand] {
        var commands: [HardwareCommand] = []
        if !snapshot.adapterEnabled { commands.append(.enableAdapter) }
        if !snapshot.charging { commands.append(.enableCharging) }
        return commands
    }
}
