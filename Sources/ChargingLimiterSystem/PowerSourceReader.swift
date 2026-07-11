import ChargingLimiterCore
import Foundation
import IOKit.ps

public struct PowerSourceReading: Equatable, Sendable {
    public let percent: Int
    public let onAC: Bool
    public let charging: Bool

    public init(percent: Int, onAC: Bool, charging: Bool) {
        self.percent = min(max(percent, 0), 100)
        self.onAC = onAC
        self.charging = charging
    }
}

public enum PowerSourceError: LocalizedError {
    case noSnapshot
    case noInternalBattery

    public var errorDescription: String? {
        switch self {
        case .noSnapshot: "macOS did not return a power-source snapshot."
        case .noInternalBattery: "No internal Mac battery was found."
        }
    }
}

public struct PowerSourceReader: Sendable {
    public init() {}

    public func read() throws -> PowerSourceReading {
        guard let infoHandle = IOPSCopyPowerSourcesInfo() else {
            throw PowerSourceError.noSnapshot
        }
        let info = infoHandle.takeRetainedValue()
        // Use physical adapter presence rather than only the currently providing
        // source. Forced discharge deliberately makes the battery the provider
        // while the cable remains attached.
        let externalAdapterConnected: Bool
        if let adapterHandle = IOPSCopyExternalPowerAdapterDetails() {
            _ = adapterHandle.takeRetainedValue()
            externalAdapterConnected = true
        } else {
            externalAdapterConnected = false
        }
        guard let listHandle = IOPSCopyPowerSourcesList(info) else {
            throw PowerSourceError.noInternalBattery
        }
        let sources = listHandle.takeRetainedValue() as Array

        for source in sources {
            guard let descriptionHandle = IOPSGetPowerSourceDescription(info, source) else { continue }
            let description = descriptionHandle.takeUnretainedValue() as NSDictionary
            let type = description["Type"] as? String
            guard type == "InternalBattery" else { continue }

            let current = description["Current Capacity"] as? Int ?? 0
            let maximum = max(description["Max Capacity"] as? Int ?? 100, 1)
            let percentage = Int((Double(current) / Double(maximum) * 100).rounded())
            let sourceState = description["Power Source State"] as? String
            return PowerSourceReading(
                percent: percentage,
                onAC: externalAdapterConnected || sourceState == "AC Power",
                charging: description["Is Charging"] as? Bool ?? false
            )
        }

        throw PowerSourceError.noInternalBattery
    }
}
