// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EaveStatus",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.library(name: "EaveStatus", targets: ["EaveStatus"])],
    targets: [
        .target(name: "DDCPrivateAPI", publicHeadersPath: "include"),
        .target(name: "EaveStatus", dependencies: ["DDCPrivateAPI"], resources: [.process("Resources")]),
        .testTarget(name: "EaveStatusTests", dependencies: ["EaveStatus"])
    ]
)
