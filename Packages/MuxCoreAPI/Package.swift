// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MuxCoreAPI",
    platforms: [
        .tvOS(.v17),
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "MuxCoreAPI", targets: ["MuxCoreAPI"]),
    ],
    targets: [
        .target(name: "MuxCoreAPI"),
        .testTarget(
            name: "MuxCoreAPITests",
            dependencies: ["MuxCoreAPI"]
        ),
    ]
)
