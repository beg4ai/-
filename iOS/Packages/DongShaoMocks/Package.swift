// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "DongShaoMocks", platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "DongShaoMocks", targets: ["DongShaoMocks"])],
    dependencies: [.package(path: "../DongShaoCore")],
    targets: [.target(name: "DongShaoMocks", dependencies: ["DongShaoCore"]),
              .testTarget(name: "DongShaoMocksTests", dependencies: ["DongShaoMocks"])])
