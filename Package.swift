// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MousePlus",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MousePlus", targets: ["MousePlus"])],
    targets: [.executableTarget(name: "MousePlus")],
    swiftLanguageModes: [.v5]
)
