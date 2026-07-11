import ChargingLimiterCore
import Testing

@Suite struct OverLimitTrackerTests {
    @Test func notifiesOnlyOncePerCrossing() {
        var tracker = OverLimitTracker(previousLimit: 80)
        #expect(!tracker.update(percent: 80, limit: 80))
        #expect(tracker.update(percent: 81, limit: 80))
        #expect(!tracker.update(percent: 82, limit: 80))
        #expect(!tracker.update(percent: 80, limit: 80))
        #expect(tracker.update(percent: 81, limit: 80))
    }

    @Test func loweringLimitBelowCurrentChargeCreatesCrossing() {
        var tracker = OverLimitTracker(previousLimit: 80)
        #expect(!tracker.update(percent: 75, limit: 80))
        #expect(tracker.update(percent: 75, limit: 70))
    }

    @Test func raisingLimitRearmsTracker() {
        var tracker = OverLimitTracker(previousLimit: 80)
        #expect(tracker.update(percent: 85, limit: 80))
        #expect(!tracker.update(percent: 85, limit: 90))
        #expect(tracker.update(percent: 91, limit: 90))
    }
}
