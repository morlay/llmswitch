// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "LLMSwitchCLI",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "llmswitch",
            targets: ["LLMSwitchCLI"]
        ),
    ],
    dependencies: [
        .package(path: "../../swiftpkg/LLMSwitchCore"),
    ],
    targets: [
        .executableTarget(
            name: "LLMSwitchCLI",
            dependencies: [
                .product(name: "LLMSwitchCore", package: "llmswitchcore"),
            ]
        ),
        .testTarget(
            name: "LLMSwitchCLITests",
            dependencies: ["LLMSwitchCLI"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
