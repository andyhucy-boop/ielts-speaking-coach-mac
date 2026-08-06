// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IELTSCoach",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "IELTSCoachCore", targets: ["IELTSCoachCore"]),
        .library(name: "ChatGPTBridge", targets: ["ChatGPTBridge"]),
        .library(name: "IELTSCoachAudio", targets: ["IELTSCoachAudio"]),
        .library(name: "IELTSCoachUI", targets: ["IELTSCoachUI"]),
        .executable(name: "axprobe", targets: ["axprobe"]),
        .executable(name: "coach", targets: ["coach"]),
        .executable(name: "IELTSCoachApp", targets: ["IELTSCoachApp"])
    ],
    targets: [
        .target(name: "IELTSCoachCore"),
        .target(name: "ChatGPTBridge", dependencies: ["IELTSCoachCore"]),
        // 全工程唯一依赖 AVFoundation 的 target。刻意不让它依赖 ChatGPTBridge：
        // 录音与驱动 ChatGPT 是两件互不相干的事，混在一起会让任何一边的故障
        // 都变成「不知道断在哪」。
        .target(name: "IELTSCoachAudio", dependencies: ["IELTSCoachCore"]),
        .target(name: "IELTSCoachUI",
                dependencies: ["IELTSCoachCore", "ChatGPTBridge", "IELTSCoachAudio"]),
        .executableTarget(name: "axprobe", dependencies: ["ChatGPTBridge"]),
        .executableTarget(name: "coach", dependencies: ["IELTSCoachCore", "ChatGPTBridge"]),
        .executableTarget(name: "IELTSCoachApp", dependencies: ["IELTSCoachUI"]),
        .testTarget(name: "IELTSCoachCoreTests", dependencies: ["IELTSCoachCore"]),
        .testTarget(name: "ChatGPTBridgeTests", dependencies: ["ChatGPTBridge"]),
        .testTarget(name: "IELTSCoachAudioTests", dependencies: ["IELTSCoachAudio"]),
        .testTarget(name: "IELTSCoachUITests", dependencies: ["IELTSCoachUI"])
    ]
)
