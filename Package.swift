// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SerbianEIDKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "SerbianEIDKit", targets: ["SerbianEIDKit"]),
    ],
    targets: [
        .target(name: "SerbianEIDKit"),
        .testTarget(
            name: "SerbianEIDKitTests",
            dependencies: ["SerbianEIDKit"]
        ),
    ]
)
