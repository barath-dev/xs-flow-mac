// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MouseDriver",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FlowCore", targets: ["FlowCore"]),
        .executable(name: "flowctl", targets: ["flowctl"]),
        .executable(name: "MouseDriver", targets: ["MouseDriverApp"]),
    ],
    targets: [
        .target(
            name: "FlowCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AppKit"),
            ]
        ),
        .executableTarget(name: "flowctl", dependencies: ["FlowCore"]),
        .executableTarget(name: "MouseDriverApp", dependencies: ["FlowCore"]),
        .testTarget(name: "FlowCoreTests", dependencies: ["FlowCore"]),
    ],
    swiftLanguageModes: [.v5]
)
