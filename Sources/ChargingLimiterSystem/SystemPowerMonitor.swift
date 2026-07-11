import CoreFoundation
import Foundation
import IOKit
import IOKit.pwr_mgt

// These are IOKit message IDs from IOMessage.h / IOPM.h. Swift cannot import
// the macros because they expand through Mach error bitfield helpers.
private let clMessageCanSystemSleep: UInt32 = 0xE000_0270
private let clMessageSystemWillSleep: UInt32 = 0xE000_0280
private let clMessageSystemHasPoweredOn: UInt32 = 0xE000_0300
private let clMessageClamshellStateChange: UInt32 = 0xE003_4100

public enum SystemPowerEvent: Sendable {
    case willSleep
    case didWake
    case clamshellChanged
}

private func chargingLimiterSystemPowerChanged(
    _ context: UnsafeMutableRawPointer?,
    _ service: io_service_t,
    _ messageType: UInt32,
    _ messageArgument: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let monitor = Unmanaged<SystemPowerMonitor>.fromOpaque(context).takeUnretainedValue()
    monitor.handle(messageType: messageType, argument: messageArgument)
}

public final class SystemPowerMonitor: @unchecked Sendable {
    public typealias Handler = @Sendable (SystemPowerEvent) -> Void

    private let handler: Handler
    private var notificationPort: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private var rootPort: io_connect_t = 0

    public private(set) var isAwake = true

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    public var isLidOpen: Bool {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard service != IO_OBJECT_NULL else { return true }
        defer { IOObjectRelease(service) }
        guard let property = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return true
        }
        return !(property as? Bool ?? false)
    }

    public func start() {
        guard rootPort == 0 else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(
            context,
            &notificationPort,
            chargingLimiterSystemPowerChanged,
            &notifier
        )
        guard rootPort != 0, let notificationPort else { return }
        let source = IONotificationPortGetRunLoopSource(notificationPort).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    public func stop() {
        if notifier != 0 {
            IODeregisterForSystemPower(&notifier)
            notifier = 0
        }
        if let notificationPort {
            IONotificationPortDestroy(notificationPort)
            self.notificationPort = nil
        }
        if rootPort != 0 {
            IOServiceClose(rootPort)
            rootPort = 0
        }
    }

    deinit {
        stop()
    }

    fileprivate func handle(messageType: UInt32, argument: UnsafeMutableRawPointer?) {
        switch messageType {
        case clMessageCanSystemSleep:
            acknowledge(argument)
        case clMessageSystemWillSleep:
            isAwake = false
            handler(.willSleep)
            acknowledge(argument)
        case clMessageSystemHasPoweredOn:
            isAwake = true
            handler(.didWake)
        case clMessageClamshellStateChange:
            handler(.clamshellChanged)
        default:
            break
        }
    }

    private func acknowledge(_ argument: UnsafeMutableRawPointer?) {
        let notificationID = Int(bitPattern: argument)
        IOAllowPowerChange(rootPort, notificationID)
    }
}
