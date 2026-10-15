// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "DongShaoWorkflows", platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "DongShaoWorkflows", targets: ["DongShaoWorkflows"]),
               .executable(name: "dongshao", targets: ["DongShaoCLI"])],
    dependencies: [.package(path: "../DongShaoCore"), .package(path: "../DongShaoMocks"), .package(path: "../DongShaoProviders")],
    targets: [.target(name: "DongShaoWorkflows", dependencies: ["DongShaoCore"]),
        .executableTarget(name: "DongShaoCLI", dependencies: ["DongShaoCore", "DongShaoWorkflows", "DongShaoMocks", "DongShaoProviders"]),
        .testTarget(name: "DongShaoWorkflowsTests", dependencies: ["DongShaoWorkflows", "DongShaoMocks", "DongShaoProviders"])])
