// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacStatus",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MacStatus", targets: ["MacStatus"])
    ],
    targets: [
        .target(name: "MacStatusCore"),
        .target(name: "MacSystemMetrics", dependencies: ["MacStatusCore"]),
        .executableTarget(
            name: "MacStatus",
            dependencies: ["MacStatusCore", "MacSystemMetrics"]
        ),
        .testTarget(
            name: "MacStatusCoreTests",
            dependencies: ["MacStatusCore"]
        ),
        .testTarget(
            name: "MacSystemMetricsTests",
            dependencies: ["MacSystemMetrics", "MacStatusCore"]
        ),
        .testTarget(
            name: "MacStatusTests",
            dependencies: ["MacStatus", "MacStatusCore"]
        )
    ]
)
