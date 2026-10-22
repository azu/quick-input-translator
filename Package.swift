// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuickTranslateInput",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "QuickTranslateInput", targets: ["QuickTranslateInput"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "TranslationCore"),
        .executableTarget(name: "QuickTranslateInput", dependencies: [
            "TranslationCore", .product(name: "Sparkle", package: "Sparkle")
        ], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "TranslationCoreTests", dependencies: ["TranslationCore"]),
        .testTarget(name: "PlatformTests", dependencies: ["QuickTranslateInput"])
    ]
)
