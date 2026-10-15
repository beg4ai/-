// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DongShaoCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "DongShaoCore", targets: ["DongShaoCore"])],
    targets: [
        .target(name: "DongShaoCore", resources: [.copy("Resources")]),
        .testTarget(name: "DongShaoCoreTests", dependencies: ["DongShaoCore"], resources: [.copy("Resources")])
    ]
)
