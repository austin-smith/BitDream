// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TailscaleCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "TailscaleCore", targets: ["TailscaleCore"])],
    targets: [.binaryTarget(name: "TailscaleCore", path: "TailscaleCore.xcframework")]
)
