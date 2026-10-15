// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "DongShaoProviders", platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "DongShaoProviders", targets: ["DongShaoProviders"])],
    dependencies: [.package(path: "../DongShaoCore")],
    targets: [.target(name: "DongShaoProviders", dependencies: ["DongShaoCore"]),
              .testTarget(name: "DongShaoProvidersTests", dependencies: ["DongShaoProviders"])])
