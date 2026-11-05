// swift-tools-version:6.0
import PackageDescription
let package = Package(
  name: "offload",
  platforms: [.macOS("27.0")],
  targets: [
    .executableTarget(name: "offload", path: "Sources/offload", swiftSettings: [.swiftLanguageMode(.v5)]),
  ]
)
