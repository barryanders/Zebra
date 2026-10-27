// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "TechnicolorZebra", platforms: [.macOS(.v14)],
    products: [.executable(name: "TechnicolorZebra", targets: ["TechnicolorZebra"])],
    targets: [
        .target(name: "TechnicolorZebraCore"),
        .executableTarget(name: "TechnicolorZebra", dependencies: ["TechnicolorZebraCore"]),
        .testTarget(name: "TechnicolorZebraCoreTests", dependencies: ["TechnicolorZebraCore"])
    ]
)
