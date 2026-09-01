// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchRail",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NotchRail", targets: ["NotchRail"]),
        .library(name: "NotchRailKit", targets: ["NotchRailKit"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "NotchRailKit",
            path: "Sources/NotchRailKit"
        ),
        .executableTarget(
            name: "NotchRail",
            dependencies: ["NotchRailKit"],
            path: "Sources/NotchRail"
        ),
        .testTarget(
            name: "NotchRailTests",
            dependencies: ["NotchRailKit"],
            path: "Tests/NotchRailTests"
        )
    ]
)
