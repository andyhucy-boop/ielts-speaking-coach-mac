// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IELTSCoach",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "IELTSCoachCore", targets: ["IELTSCoachCore"]),
        .executable(name: "axprobe", targets: ["axprobe"])
    ],
    targets: [
        .target(name: "IELTSCoachCore"),
        .executableTarget(name: "axprobe"),
        .testTarget(name: "IELTSCoachCoreTests", dependencies: ["IELTSCoachCore"])
    ]
)
