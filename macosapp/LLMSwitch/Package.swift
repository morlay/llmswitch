// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "LLMSwitchApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "LLMSwitchApp",
            targets: ["LLMSwitchApp"]
        )
    ],
    dependencies: [
        .package(path: "../../swiftpkg/LLMGateway")
    ],
    targets: [
        .executableTarget(
            name: "LLMSwitchApp",
            dependencies: [
                .product(name: "LLMGateway", package: "LLMGateway")
            ],
            path: "Sources/LLMSwitch",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
