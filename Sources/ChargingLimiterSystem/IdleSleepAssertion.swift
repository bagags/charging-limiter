import Foundation
import IOKit.pwr_mgt

public final class IdleSleepAssertion: @unchecked Sendable {
    private var assertionID: IOPMAssertionID = 0

    public init() {}

    public var isHeld: Bool { assertionID != 0 }

    public func setHeld(_ held: Bool) {
        if held, assertionID == 0 {
            var newID: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Charging battery to configured limit" as CFString,
                &newID
            )
            if result == kIOReturnSuccess { assertionID = newID }
        } else if !held, assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
    }

    deinit {
        setHeld(false)
    }
}
