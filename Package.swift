// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacStatus",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MacStatus", targets: ["MacStatus"])
    ],
    targets: [
        .target(name: "MacSystemMetrics"),
        .executableTarget(
            name: "MacStatus",
            dependencies: ["MacSystemMetrics"]
        ),
        .testTarget(
            name: "MacSystemMetricsTests",
            dependencies: ["MacSystemMetrics"]
        ),
        .testTarget(
            name: "MacStatusTests",
            dependencies: ["MacStatus", "MacSystemMetrics"]
        )
    ]
)
