import CoreFoundation
import Foundation
import IOKit.ps

private func chargingLimiterPowerSourceChanged(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue()
    monitor.deliverCurrentReading()
}

public final class PowerSourceMonitor: @unchecked Sendable {
    public typealias Handler = @Sendable (Result<PowerSourceReading, Error>) -> Void

    private let reader: PowerSourceReader
    private let handler: Handler
    private var runLoopSource: CFRunLoopSource?

    public init(reader: PowerSourceReader = PowerSourceReader(), handler: @escaping Handler) {
        self.reader = reader
        self.handler = handler
    }

    public func start(on runLoop: CFRunLoop = CFRunLoopGetMain()) {
        guard runLoopSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let sourceHandle = IOPSNotificationCreateRunLoopSource(
            chargingLimiterPowerSourceChanged,
            context
        ) else {
            handler(.failure(PowerSourceError.noSnapshot))
            return
        }
        let source = sourceHandle.takeRetainedValue()
        runLoopSource = source
        CFRunLoopAddSource(runLoop, source, .commonModes)
        deliverCurrentReading()
    }

    public func stop() {
        guard let source = runLoopSource else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = nil
    }

    deinit {
        stop()
    }

    fileprivate func deliverCurrentReading() {
        do {
            handler(.success(try reader.read()))
        } catch {
            handler(.failure(error))
        }
    }
}
