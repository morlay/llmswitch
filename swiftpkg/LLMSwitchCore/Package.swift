// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "LLMSwitchCore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "LLMSwitchCore",
            targets: ["LLMSwitchCore"]
        ),
    ],
    targets: [
        .target(
            name: "LLMSwitchCore"
        ),
        .testTarget(
            name: "LLMSwitchCoreTests",
            dependencies: ["LLMSwitchCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
