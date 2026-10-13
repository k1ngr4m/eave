// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "EaveNetworkStats", defaultLocalization: "en", platforms: [.macOS(.v14)],
    products: [.library(name: "EaveNetworkStats", targets: ["EaveNetworkStats"])],
    targets: [.target(name: "CStatsDisk"),
              .target(name: "CStatsSensors", cSettings: [.unsafeFlags(["-fobjc-arc"])], linkerSettings: [.linkedFramework("IOKit")]),
              .target(name: "EaveNetworkStats", dependencies: ["CStatsDisk", "CStatsSensors"], resources: [.process("Resources")]),
              .testTarget(name: "EaveNetworkStatsTests", dependencies: ["EaveNetworkStats"])],
    swiftLanguageVersions: [.v5]
)
