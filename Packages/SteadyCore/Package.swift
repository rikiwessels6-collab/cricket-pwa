// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SteadyCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SteadyCore", targets: ["SteadyCore"])],
    targets: [
        .target(name: "SteadyCore"),
        .testTarget(name: "SteadyCoreTests", dependencies: ["SteadyCore"]),
    ]
)
