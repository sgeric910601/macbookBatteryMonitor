// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "macbookBatteryMonitor",
    platforms: [.macOS(.v12)],
    targets: [
        .target(name: "CPUPowerShared", path: "Sources/CPUPowerShared"),
        .executableTarget(name: "CPUPowerHelper", dependencies: ["CPUPowerShared"], path: "Sources/CPUPowerHelper",
                          linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(
            name: "macbookBatteryMonitor",
            dependencies: ["CPUPowerShared"],
            path: "Sources/macbookBatteryMonitor",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("DiskArbitration"),
            ]
        )
    ]
)
