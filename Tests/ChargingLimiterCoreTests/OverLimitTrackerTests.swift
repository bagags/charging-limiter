import ChargingLimiterCore
import Testing

@Suite struct OverLimitTrackerTests {
    @Test func notifiesOnlyOncePerCrossing() {
        var tracker = OverLimitTracker(previousLimit: 80)
        let atLimit = tracker.update(percent: 80, limit: 80)
        let firstCrossing = tracker.update(percent: 81, limit: 80)
        let sameEpisode = tracker.update(percent: 82, limit: 80)
        let rearmed = tracker.update(percent: 80, limit: 80)
        let secondCrossing = tracker.update(percent: 81, limit: 80)

        #expect(!atLimit)
        #expect(firstCrossing)
        #expect(!sameEpisode)
        #expect(!rearmed)
        #expect(secondCrossing)
    }

    @Test func loweringLimitBelowCurrentChargeCreatesCrossing() {
        var tracker = OverLimitTracker(previousLimit: 80)
        let belowOriginalLimit = tracker.update(percent: 75, limit: 80)
        let belowLoweredLimit = tracker.update(percent: 75, limit: 70)

        #expect(!belowOriginalLimit)
        #expect(belowLoweredLimit)
    }

    @Test func raisingLimitRearmsTracker() {
        var tracker = OverLimitTracker(previousLimit: 80)
        let originalCrossing = tracker.update(percent: 85, limit: 80)
        let raisedLimit = tracker.update(percent: 85, limit: 90)
        let raisedLimitCrossing = tracker.update(percent: 91, limit: 90)

        #expect(originalCrossing)
        #expect(!raisedLimit)
        #expect(raisedLimitCrossing)
    }
}
