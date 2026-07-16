// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AgentUsageMonitor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AgentUsageCore",
            targets: ["AgentUsageCore"]
        ),
        .executable(
            name: "AgentUsageMonitor",
            targets: ["AgentUsageMonitor"]
        )
    ],
    targets: [
        .target(
            name: "AgentUsageCore"
        ),
        .executableTarget(
            name: "AgentUsageMonitor",
            dependencies: ["AgentUsageCore"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("WebKit")
            ]
        ),
        .testTarget(
            name: "AgentUsageCoreTests",
            dependencies: ["AgentUsageCore"]
        ),
        .testTarget(
            name: "AgentUsageMonitorTests",
            dependencies: ["AgentUsageMonitor", "AgentUsageCore"]
        )
    ]
)
