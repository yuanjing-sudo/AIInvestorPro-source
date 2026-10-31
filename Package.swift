// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "AIInvestorPro",
    platforms: [.iOS(.v17), .macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.31.0"),
    ],
    targets: [
        .systemLibrary(
            name: "CXGBoost",
            pkgConfig: "xgboost",
            providers: [.brew(["xgboost"])]
        ),
        .executableTarget(
            name: "AIInvestorPro",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXOptimizers", package: "mlx-swift"),
                .target(name: "CXGBoost", condition: .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "AIInvestorProTests",
            dependencies: ["AIInvestorPro"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
