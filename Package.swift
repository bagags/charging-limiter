// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ChargingLimiter",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ChargingLimiterCore", targets: ["ChargingLimiterCore"]),
        .library(name: "ChargingLimiterSystem", targets: ["ChargingLimiterSystem"]),
        .library(name: "ChargingLimiterHardware", targets: ["ChargingLimiterHardware"]),
        .executable(name: "ChargingLimiterDaemon", targets: ["ChargingLimiterDaemon"]),
        .executable(name: "ChargingLimiter", targets: ["ChargingLimiterApp"]),
    ],
    targets: [
        .target(name: "ChargingLimiterCore"),
        .target(
            name: "SMCLowLevel",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .target(
            name: "ChargingLimiterSystem",
            dependencies: ["ChargingLimiterCore"],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
            ]
        ),
        .target(
            name: "ChargingLimiterHardware",
            dependencies: ["ChargingLimiterCore", "SMCLowLevel"],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "ChargingLimiterDaemon",
            dependencies: [
                "ChargingLimiterCore",
                "ChargingLimiterSystem",
                "ChargingLimiterHardware",
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(
            name: "ChargingLimiterApp",
            dependencies: ["ChargingLimiterCore", "ChargingLimiterSystem"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UserNotifications"),
            ]
        ),
        .testTarget(name: "ChargingLimiterCoreTests", dependencies: ["ChargingLimiterCore"]),
        .testTarget(
            name: "ChargingLimiterHardwareTests",
            dependencies: ["ChargingLimiterCore", "ChargingLimiterHardware"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
