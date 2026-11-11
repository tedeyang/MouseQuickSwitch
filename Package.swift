// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MouseQuickSwitch",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MouseQuickSwitch", targets: ["MouseQuickSwitch"])],
    targets: [.executableTarget(name: "MouseQuickSwitch")],
    swiftLanguageModes: [.v5]
)
