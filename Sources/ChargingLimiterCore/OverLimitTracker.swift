import Foundation

public struct OverLimitTracker: Codable, Equatable, Sendable {
    public private(set) var wasOverLimit: Bool
    public private(set) var previousLimit: Int

    public init(wasOverLimit: Bool = false, previousLimit: Int = 80) {
        self.wasOverLimit = wasOverLimit
        self.previousLimit = previousLimit
    }

    /// Returns true exactly once for each transition into an over-limit episode.
    public mutating func update(percent: Int, limit: Int) -> Bool {
        let isOverLimit = percent > limit
        let shouldNotify = isOverLimit && !wasOverLimit
        wasOverLimit = isOverLimit
        previousLimit = limit
        return shouldNotify
    }
}
