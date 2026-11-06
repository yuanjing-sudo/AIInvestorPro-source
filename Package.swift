// swift-tools-version: 5.9
import Foundation
import PackageDescription

// The legacy `AIInvestorPro` app target is a SwiftUI executable. Set
// `INVESTORKIT_ONLY=1` to build and test only the dependency-free
// `InvestorKit` library on Linux or CI without Apple frameworks.
//
//   INVESTORKIT_ONLY=1 swift build
//   INVESTORKIT_ONLY=1 swift test
//
// The default behaviour is unchanged: the app target is still included.
let investorKitOnly = ProcessInfo.processInfo.environment["INVESTORKIT_ONLY"] == "1"

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
    targets.insert(
        .executableTarget(
            name: "AIInvestorPro",
            path: "Sources/AIInvestorPro"
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
    targets: targets
)
