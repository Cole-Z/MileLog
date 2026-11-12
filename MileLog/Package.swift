// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "MileLogCore", platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "MileLogCore", targets: ["MileLogCore"])],
    targets: [
        .target(name: "MileLogCore", path: ".", exclude: ["App", "Features", "Services", "Tests", "Resources/Assets.xcassets", "Resources/Info.plist", "Resources/PrivacyInfo.xcprivacy"], sources: ["Core", "Persistence"], resources: [.copy("Resources/SeedRates.json")]),
        .testTarget(name: "MileLogCoreTests", dependencies: ["MileLogCore"], path: "Tests/MileLogCoreTests")
    ]
)
