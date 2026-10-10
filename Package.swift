// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DegenerateAge",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DegenerateAge", targets: ["GameApp"])],
    targets: [
        .target(name: "GameCore", path: "GameApp/Core"),
        .target(name: "GameData", dependencies: ["GameCore"], path: "GameApp/Data", resources: [.process("Resources")]),
        .target(name: "GamePersistence", dependencies: ["GameCore"], path: "GameApp/Persistence"),
        .executableTarget(name: "GameApp", dependencies: ["GameCore", "GameData", "GamePersistence"], path: "GameApp", exclude: ["Core", "Data", "Persistence"]),
        .executableTarget(name: "RuleChecks", dependencies: ["GameCore", "GameData", "GamePersistence"], path: "Tests")
    ]
)
