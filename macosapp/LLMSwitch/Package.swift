// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "LLMSwitchApp",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "LLMSwitchApp",
            targets: ["LLMSwitchApp"]
        ),
    ],
    dependencies: [
        .package(path: "../../swiftpkg/LLMSwitchCore"),
    ],
    targets: [
        .executableTarget(
            name: "LLMSwitchApp",
            dependencies: [
                .product(name: "LLMSwitchCore", package: "llmswitchcore"),
            ],
            path: "Sources/LLMSwitch"
        ),
    ],
    swiftLanguageModes: [.v6]
)
