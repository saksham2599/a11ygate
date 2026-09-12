// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "A11yGate",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .executable(name: "a11ygate", targets: ["A11yGateCLI"]),
        .library(name: "A11yGateCore", targets: ["A11yGateCore"]),
        .library(name: "A11yGateAgent", targets: ["A11yGateAgent"])
    ],
    targets: [
        .target(name: "A11yGateCore"),
        .target(name: "A11yGateAgent", dependencies: ["A11yGateCore"]),
        .executableTarget(name: "A11yGateCLI", dependencies: ["A11yGateCore", "A11yGateAgent"]),
        .testTarget(name: "A11yGateCoreTests", dependencies: ["A11yGateCore", "A11yGateAgent"])
    ]
)
