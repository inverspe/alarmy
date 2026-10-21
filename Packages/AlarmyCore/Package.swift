// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AlarmyCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "AlarmyCore", targets: ["AlarmyCore"]),
    ],
    targets: [
        .target(name: "AlarmyCore"),
        .testTarget(name: "AlarmyCoreTests", dependencies: ["AlarmyCore"]),
    ]
)
