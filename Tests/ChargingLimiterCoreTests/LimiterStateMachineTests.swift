import ChargingLimiterCore
import Testing

@Suite struct LimiterStateMachineTests {
    private let machine = LimiterStateMachine()
    private let enabled80 = try! LimiterConfiguration(limitPercent: 80, isEnabled: true)

    @Test func aboveLimitDisablesChargingBeforeAdapter() {
        let decision = machine.decide(
            configuration: enabled80,
            snapshot: snapshot(percent: 81, charging: true, adapter: true)
        )
        #expect(decision.state == .dischargingToLimit)
        #expect(decision.commands == [.disableCharging, .disableAdapter])
        #expect(!decision.holdIdleSleep)
    }

    @Test func atLimitRestoresAdapterBeforeInhibitingCharging() {
        let decision = machine.decide(
            configuration: enabled80,
            snapshot: snapshot(percent: 80, charging: true, adapter: false)
        )
        #expect(decision.state == .holdingAtLimit)
        #expect(decision.commands == [.enableAdapter, .disableCharging])
    }

    @Test func belowHysteresisChargesAndHoldsIdleSleep() {
        let decision = machine.decide(
            configuration: enabled80,
            snapshot: snapshot(percent: 74, charging: false, adapter: false)
        )
        #expect(decision.state == .chargingToLimit)
        #expect(decision.commands == [.enableAdapter, .enableCharging])
        #expect(decision.holdIdleSleep)
    }

    @Test func hysteresisBandRetainsDisabledCharging() {
        let decision = machine.decide(
            configuration: enabled80,
            snapshot: snapshot(percent: 77, charging: false, adapter: true)
        )
        #expect(decision.state == .holdingAtLimit)
        #expect(decision.commands == [])
    }

    @Test func hysteresisBandRetainsEnabledCharging() {
        let decision = machine.decide(
            configuration: enabled80,
            snapshot: snapshot(percent: 77, charging: true, adapter: true)
        )
        #expect(decision.state == .chargingToLimit)
        #expect(decision.holdIdleSleep)
    }

    @Test func sleepRestoresAdapterAndInhibitsCharging() {
        let decision = machine.decide(
            configuration: enabled80,
            snapshot: snapshot(percent: 90, charging: true, adapter: false, awake: false)
        )
        #expect(decision.state == .pausedForSleep)
        #expect(decision.commands == [.enableAdapter, .disableCharging])
    }

    @Test func closedLidUsesSleepFallback() {
        let decision = machine.decide(
            configuration: enabled80,
            snapshot: snapshot(percent: 90, charging: false, adapter: true, lidOpen: false)
        )
        #expect(decision.state == .pausedForSleep)
        #expect(decision.commands == [])
    }

    @Test func disabledLimiterRestoresNormalHardwareOrder() {
        let configuration = try! LimiterConfiguration(limitPercent: 80, isEnabled: false)
        let decision = machine.decide(
            configuration: configuration,
            snapshot: snapshot(percent: 90, charging: false, adapter: false)
        )
        #expect(decision.state == .normal)
        #expect(decision.commands == [.enableAdapter, .enableCharging])
    }

    @Test func oneHundredPercentRestoresNormalCharging() {
        let configuration = try! LimiterConfiguration(limitPercent: 100, isEnabled: true)
        let decision = machine.decide(
            configuration: configuration,
            snapshot: snapshot(percent: 99, charging: false, adapter: false)
        )
        #expect(decision.commands == [.enableAdapter, .enableCharging])
    }

    @Test func unpluggedRestoresStickySMCState() {
        let decision = machine.decide(
            configuration: enabled80,
            snapshot: snapshot(percent: 90, onAC: false, charging: false, adapter: false)
        )
        #expect(decision.state == .normal)
        #expect(decision.commands == [.enableAdapter, .enableCharging])
    }

    @Test func fiftyPercentBoundaryUsesFortyFiveAsLowerThreshold() {
        let configuration = try! LimiterConfiguration(limitPercent: 50, isEnabled: true)
        #expect(
            machine.decide(
                configuration: configuration,
                snapshot: snapshot(percent: 45, charging: false, adapter: true)
            ).commands == []
        )
        #expect(
            machine.decide(
                configuration: configuration,
                snapshot: snapshot(percent: 44, charging: false, adapter: true)
            ).commands == [.enableCharging]
        )
    }

    @Test func configurationRejectsOutOfRangeLimits() {
        #expect(throws: LimiterError.invalidLimit(49)) {
            try LimiterConfiguration(limitPercent: 49, isEnabled: true)
        }
        #expect(throws: LimiterError.invalidLimit(101)) {
            try LimiterConfiguration(limitPercent: 101, isEnabled: true)
        }
    }

    private func snapshot(
        percent: Int,
        onAC: Bool = true,
        charging: Bool,
        adapter: Bool,
        awake: Bool = true,
        lidOpen: Bool = true
    ) -> BatterySnapshot {
        BatterySnapshot(
            percent: percent,
            onAC: onAC,
            charging: charging,
            adapterEnabled: adapter,
            awake: awake,
            lidOpen: lidOpen
        )
    }
}
