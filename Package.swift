// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "SimMan",
  platforms: [.macOS(.v14)],
  targets: [
    .executableTarget(name: "SimMan")
  ]
)
