import Foundation

public enum ChargingLimiterIdentifiers {
    public static let appBundle = "com.yangyi.ChargingLimiter"
    public static let daemonBundle = "com.yangyi.ChargingLimiter.daemon"
    public static let daemonMachService = "com.yangyi.ChargingLimiter.daemon"
    public static let daemonPlist = "com.yangyi.ChargingLimiter.daemon.plist"
}

@objc public protocol ChargingLimiterDaemonXPC {
    func getStatus(withReply reply: @escaping (Data?, NSError?) -> Void)
    func setLimit(_ limitPercent: Int, withReply reply: @escaping (Data?, NSError?) -> Void)
    func setEnabled(_ enabled: Bool, withReply reply: @escaping (Data?, NSError?) -> Void)
    func restoreHardware(withReply reply: @escaping (NSError?) -> Void)
}

public enum DaemonStatusCodec {
    public static func encode(_ status: DaemonStatus) throws -> Data {
        try PropertyListEncoder().encode(status)
    }

    public static func decode(_ data: Data) throws -> DaemonStatus {
        try PropertyListDecoder().decode(DaemonStatus.self, from: data)
    }
}
