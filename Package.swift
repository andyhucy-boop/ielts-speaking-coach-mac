// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IELTSCoach",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "IELTSCoachCore", targets: ["IELTSCoachCore"]),
        .library(name: "ChatGPTBridge", targets: ["ChatGPTBridge"]),
        .library(name: "IELTSCoachUI", targets: ["IELTSCoachUI"]),
        .executable(name: "axprobe", targets: ["axprobe"]),
        .executable(name: "coach", targets: ["coach"]),
        .executable(name: "IELTSCoachApp", targets: ["IELTSCoachApp"])
    ],
    targets: [
        .target(name: "IELTSCoachCore"),
        .target(name: "ChatGPTBridge", dependencies: ["IELTSCoachCore"]),
        .target(name: "IELTSCoachUI", dependencies: ["IELTSCoachCore", "ChatGPTBridge"]),
        .executableTarget(name: "axprobe", dependencies: ["ChatGPTBridge"]),
        .executableTarget(name: "coach", dependencies: ["IELTSCoachCore", "ChatGPTBridge"]),
        .executableTarget(name: "IELTSCoachApp", dependencies: ["IELTSCoachUI"]),
        .testTarget(name: "IELTSCoachCoreTests", dependencies: ["IELTSCoachCore"]),
        .testTarget(name: "ChatGPTBridgeTests", dependencies: ["ChatGPTBridge"]),
        .testTarget(name: "IELTSCoachUITests", dependencies: ["IELTSCoachUI"])
    ]
)
