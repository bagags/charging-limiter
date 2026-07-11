import ChargingLimiterCore
import Foundation

public struct BatteryHardwareState: Equatable, Sendable {
    public let chargingEnabled: Bool
    public let adapterEnabled: Bool
}

public enum SMCHardwareError: LocalizedError, Equatable {
    case unsupportedChargingKeys
    case unsupportedAdapterKeys
    case verificationFailed(key: String, expected: Data, actual: Data)

    public var errorDescription: String? {
        switch self {
        case .unsupportedChargingKeys:
            "No supported Apple Silicon charging SMC keys were found."
        case .unsupportedAdapterKeys:
            "No supported Apple Silicon adapter-control SMC key was found."
        case .verificationFailed(let key, let expected, let actual):
            "SMC write verification failed for \(key): expected \(expected.hex), read \(actual.hex)."
        }
    }
}

public final class SMCHardwareController: @unchecked Sendable {
    private enum ChargingFamily {
        case legacy
        case tahoe
    }

    private let transport: SMCTransport
    private let chargingFamily: ChargingFamily
    private let adapterKey: String

    public init(transport: SMCTransport) throws {
        self.transport = transport

        if (try? transport.read(key: "CHTE")) != nil {
            chargingFamily = .tahoe
        } else if (try? transport.read(key: "CH0B")) != nil,
                  (try? transport.read(key: "CH0C")) != nil {
            chargingFamily = .legacy
        } else {
            throw SMCHardwareError.unsupportedChargingKeys
        }

        if (try? transport.read(key: "CHIE")) != nil {
            adapterKey = "CHIE"
        } else if (try? transport.read(key: "CH0J")) != nil {
            adapterKey = "CH0J"
        } else if (try? transport.read(key: "CH0I")) != nil {
            adapterKey = "CH0I"
        } else {
            throw SMCHardwareError.unsupportedAdapterKeys
        }
    }

    public func readState() throws -> BatteryHardwareState {
        let chargingData: Data
        switch chargingFamily {
        case .legacy: chargingData = try transport.read(key: "CH0B")
        case .tahoe: chargingData = try transport.read(key: "CHTE")
        }
        let adapterData = try transport.read(key: adapterKey)
        return BatteryHardwareState(
            chargingEnabled: chargingData.allSatisfy { $0 == 0 },
            adapterEnabled: adapterData.allSatisfy { $0 == 0 }
        )
    }

    public func execute(_ command: HardwareCommand) throws {
        switch command {
        case .enableAdapter: try setAdapter(enabled: true)
        case .disableAdapter: try setAdapter(enabled: false)
        case .enableCharging: try setCharging(enabled: true)
        case .disableCharging: try setCharging(enabled: false)
        }
    }

    public func restoreSafely() throws {
        // Adapter input must be restored before battery charging is re-enabled.
        try setAdapter(enabled: true)
        try setCharging(enabled: true)
    }

    private func setCharging(enabled: Bool) throws {
        switch chargingFamily {
        case .legacy:
            let data = Data([enabled ? 0x00 : 0x02])
            try writeAndVerify(key: "CH0B", data: data)
            try writeAndVerify(key: "CH0C", data: data)
        case .tahoe:
            try writeAndVerify(
                key: "CHTE",
                data: Data(enabled ? [0x00, 0x00, 0x00, 0x00] : [0x01, 0x00, 0x00, 0x00])
            )
        }
    }

    private func setAdapter(enabled: Bool) throws {
        let disabledByte: UInt8 = adapterKey == "CHIE" ? 0x08 : 0x01
        try writeAndVerify(key: adapterKey, data: Data([enabled ? 0x00 : disabledByte]))
    }

    private func writeAndVerify(key: String, data: Data) throws {
        try transport.write(key: key, bytes: data)
        let actual = try transport.read(key: key)
        guard actual == data else {
            throw SMCHardwareError.verificationFailed(key: key, expected: data, actual: actual)
        }
    }
}

private extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
