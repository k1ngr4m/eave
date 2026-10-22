// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EaveStatus",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.library(name: "EaveStatus", targets: ["EaveStatus"]),
               .executable(name: "EavePowerHelper", targets: ["EavePowerHelper"])],
    dependencies: [.package(path: "../EaveNetworkStats")],
    targets: [
        .target(name: "DDCPrivateAPI", publicHeadersPath: "include"),
        .target(name: "PowerHelperProtocol"),
        .executableTarget(name: "EavePowerHelper", dependencies: ["PowerHelperProtocol"]),
        .target(name: "EaveStatus", dependencies: ["DDCPrivateAPI", "PowerHelperProtocol", "EaveNetworkStats"], resources: [.process("Resources")]),
        .testTarget(name: "EavePowerHelperTests", dependencies: ["EavePowerHelper", "PowerHelperProtocol"]),
        .testTarget(name: "EaveStatusTests", dependencies: ["EaveStatus", "PowerHelperProtocol"])
    ]
)
