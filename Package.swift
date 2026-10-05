// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "SimMan",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(url: "https://github.com/lfroms/fluid-menu-bar-extra", from: "1.2.0")
  ],
  targets: [
    .executableTarget(
      name: "SimMan",
      dependencies: [.product(name: "FluidMenuBarExtra", package: "fluid-menu-bar-extra")])
  ]
)
