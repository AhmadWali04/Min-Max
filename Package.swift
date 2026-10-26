// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MinMax",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MinMaxCore",
            targets: ["MinMaxCore"]
        ),
        .executable(
            name: "MinMaxGameClient",
            targets: ["MinMaxGameClient"]
        ),
        .executable(
            name: "MinMaxEchoServer",
            targets: ["MinMaxEchoServer"]
        )
    ],
    targets: [
        .target(
            name: "MinMaxCore"
        ),
        .executableTarget(
            name: "MinMaxGameClient",
            dependencies: ["MinMaxCore"]
        ),
        .executableTarget(
            name: "MinMaxEchoServer",
            dependencies: ["MinMaxCore"]
        ),
        .testTarget(
            name: "MinMaxCoreTests",
            dependencies: ["MinMaxCore"]
        )
    ]
)
