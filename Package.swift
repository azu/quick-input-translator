// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuickTranslateInput",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "QuickTranslateInput", targets: ["QuickTranslateInput"])],
    targets: [
        .target(name: "TranslationCore"),
        .executableTarget(name: "QuickTranslateInput", dependencies: ["TranslationCore"]),
        .testTarget(name: "TranslationCoreTests", dependencies: ["TranslationCore"]),
        .testTarget(name: "PlatformTests", dependencies: ["QuickTranslateInput"])
    ]
)
