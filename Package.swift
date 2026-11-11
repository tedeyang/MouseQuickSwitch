// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mouseQuick",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "mouseQuick", targets: ["mouseQuick"])],
    targets: [.executableTarget(name: "mouseQuick")],
    swiftLanguageModes: [.v5]
)
