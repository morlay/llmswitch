// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "LLMGateway",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "LLMGateway",
            targets: ["LLMGateway"]
        )
    ],
    targets: [
        .target(
            name: "LLMGateway",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "LLMGatewayTests",
            dependencies: ["LLMGateway"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
