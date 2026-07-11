import ChargingLimiterCore
@testable import ChargingLimiterHardware
import Foundation
import Testing

@Suite struct SMCHardwareControllerTests {
    @Test func tahoeKeyFamilyAndSafeOrdering() throws {
        let transport = FakeSMCTransport(values: [
            "CHTE": Data([1, 0, 0, 0]),
            "CHIE": Data([8]),
            "CH0J": Data([1]),
        ])
        let controller = try SMCHardwareController(transport: transport)

        try controller.restoreSafely()

        #expect(transport.writes.map(\.key) == ["CHIE", "CHTE"])
        #expect(transport.writes.map(\.data) == [Data([0]), Data([0, 0, 0, 0])])
    }

    @Test func legacyChargingWritesBothKeys() throws {
        let transport = FakeSMCTransport(values: [
            "CH0B": Data([0]),
            "CH0C": Data([0]),
            "CH0I": Data([0]),
        ])
        let controller = try SMCHardwareController(transport: transport)

        try controller.execute(.disableCharging)

        #expect(transport.writes.map(\.key) == ["CH0B", "CH0C"])
        #expect(transport.writes.map(\.data) == [Data([2]), Data([2])])
    }

    @Test func adapterKeyPriorityIsCHIEThenCH0JThenCH0I() throws {
        let transport = FakeSMCTransport(values: [
            "CHTE": Data([0, 0, 0, 0]),
            "CHIE": Data([0]),
            "CH0J": Data([0]),
            "CH0I": Data([0]),
        ])
        let controller = try SMCHardwareController(transport: transport)

        try controller.execute(.disableAdapter)

        #expect(transport.writes == [.init(key: "CHIE", data: Data([8]))])
    }

    @Test func writeReadbackMismatchFailsVerification() throws {
        let transport = FakeSMCTransport(values: [
            "CHTE": Data([0, 0, 0, 0]),
            "CHIE": Data([0]),
        ])
        transport.ignoreWrites = true
        let controller = try SMCHardwareController(transport: transport)

        do {
            try controller.execute(.disableAdapter)
            Issue.record("Expected verification failure")
        } catch {
            guard case SMCHardwareError.verificationFailed(let key, _, _) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(key == "CHIE")
        }
    }

    @Test func unsupportedAdapterKeysAreRejected() {
        let transport = FakeSMCTransport(values: ["CHTE": Data([0, 0, 0, 0])])
        do {
            _ = try SMCHardwareController(transport: transport)
            Issue.record("Expected unsupported adapter error")
        } catch {
            #expect(error as? SMCHardwareError == .unsupportedAdapterKeys)
        }
    }
}

private final class FakeSMCTransport: SMCTransport {
    struct Write: Equatable {
        let key: String
        let data: Data
    }

    var values: [String: Data]
    var writes: [Write] = []
    var ignoreWrites = false

    init(values: [String: Data]) {
        self.values = values
    }

    func read(key: String) throws -> Data {
        guard let value = values[key] else { throw SMCTransportError.readFailed(key, -1) }
        return value
    }

    func write(key: String, bytes: Data) throws {
        guard values[key] != nil else { throw SMCTransportError.writeFailed(key, -1) }
        writes.append(.init(key: key, data: bytes))
        if !ignoreWrites { values[key] = bytes }
    }
}
