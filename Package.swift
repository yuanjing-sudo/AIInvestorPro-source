// swift-tools-version: 6.3
import Foundation
import PackageDescription

let swiftLanguageModes: [SwiftLanguageMode] = [.v6]

// The legacy `AIInvestorPro` app target does not currently compile (see
// docs/AUDIT.md). Set `INVESTORKIT_ONLY=1` to build and test the new,
// dependency-free `InvestorKit` library without pulling in MLX or trying to
// compile the legacy target.
//
//   INVESTORKIT_ONLY=1 swift build
//   INVESTORKIT_ONLY=1 swift test
//
// The default behaviour is unchanged: the app target is still included.
let investorKitOnly = ProcessInfo.processInfo.environment["INVESTORKIT_ONLY"] == "1"

var dependencies: [Package.Dependency] = []
var targets: [Target] = [
    // InvestorKit is a dependency-free analytics library. It is intentionally
    // not coupled to the app target so it can be built and tested on its own.
    .target(
        name: "InvestorKit",
        path: "Sources/InvestorKit"
    ),
    .executableTarget(
        name: "InvestorKitDemo",
        dependencies: ["InvestorKit"],
        path: "Sources/InvestorKitDemo"
    ),
    .testTarget(
        name: "InvestorKitTests",
        dependencies: ["InvestorKit"],
        path: "Tests/InvestorKitTests"
    ),
]

if !investorKitOnly {
    dependencies.append(.package(url: "https://github.com/ml-explore/mlx-swift", from: "0.31.0"))
    targets.insert(
        .executableTarget(
            name: "AIInvestorPro",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXOptimizers", package: "mlx-swift"),
            ]
        ),
        at: 0
    )
}

let package = Package(
    name: "AIInvestorPro",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "InvestorKit", targets: ["InvestorKit"]),
    ],
    dependencies: dependencies,
    targets: targets
)
