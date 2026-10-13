// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "EaveNetworkStats", defaultLocalization: "en", platforms: [.macOS(.v14)],
    products: [.library(name: "EaveNetworkStats", targets: ["EaveNetworkStats"])],
    targets: [.target(name: "EaveNetworkStats", resources: [.process("Resources")]),
              .testTarget(name: "EaveNetworkStatsTests", dependencies: ["EaveNetworkStats"])],
    swiftLanguageVersions: [.v5]
)
