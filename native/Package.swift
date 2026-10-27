// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "EpsonDirectScan", platforms: [.macOS(.v13)],
    products: [.library(name: "DirectScanCore", targets: ["DirectScanCore"]),
               .executable(name: "EpsonDirectScan", targets: ["EpsonDirectScan"])],
    targets: [.target(name: "DirectScanCore"),
              .target(name: "EpsonImageProcessing", publicHeadersPath: "include", cSettings: [.unsafeFlags(["-fobjc-arc"])], linkerSettings: [.linkedFramework("Foundation"), .linkedFramework("ImageIO"), .linkedFramework("CoreGraphics")]),
              .executableTarget(name: "EpsonDirectScan", dependencies: ["DirectScanCore"]),
              .testTarget(name: "DirectScanCoreTests", dependencies: ["DirectScanCore", "EpsonDirectScan", "EpsonImageProcessing"])])
