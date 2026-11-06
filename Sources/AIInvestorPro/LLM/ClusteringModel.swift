// MARK: - Market Clustering
import Foundation
import Combine

public enum MarketRegimeCluster: String, CaseIterable, Sendable, Equatable {
    case growth = "growth"
    case value = "value"
    case momentum = "momentum"
    case quality = "quality"
    case defensive = "defensive"
    case cyclical = "cyclical"

    public var description: String {
        rawValue.capitalized
    }
}

public struct MarketFeatureSet: Equatable, Sendable {
    public let symbol: String
    public let volatility: Double
    public let momentum: Double
    public let value: Double
    public let quality: Double
    public let size: Double
    public let liquidity: Double

    public init(
        symbol: String = "",
        volatility: Double,
        momentum: Double,
        value: Double,
        quality: Double,
        size: Double,
        liquidity: Double
    ) {
        self.symbol = symbol
        self.volatility = volatility
        self.momentum = momentum
        self.value = value
        self.quality = quality
        self.size = size
        self.liquidity = liquidity
    }

    public static func == (lhs: MarketFeatureSet, rhs: MarketFeatureSet) -> Bool {
        lhs.symbol == rhs.symbol &&
        abs(lhs.volatility - rhs.volatility) < 0.01 &&
        abs(lhs.momentum - rhs.momentum) < 0.01 &&
        abs(lhs.value - rhs.value) < 0.01 &&
        abs(lhs.quality - rhs.quality) < 0.01 &&
        abs(lhs.size - rhs.size) < 0.01 &&
        abs(lhs.liquidity - rhs.liquidity) < 0.01
    }
}

public struct ClusterAssignment: Identifiable, Equatable, Sendable {
    public var id: String { symbol }
    public let symbol: String
    public let cluster: MarketRegimeCluster
    public let confidence: Double
    public let featureSet: MarketFeatureSet
    public var assignedAt: Date

    public init(
        symbol: String,
        cluster: MarketRegimeCluster,
        confidence: Double,
        featureSet: MarketFeatureSet
    ) {
        self.symbol = symbol
        self.cluster = cluster
        self.confidence = confidence
        self.featureSet = featureSet
        self.assignedAt = Date()
    }
}

// MARK: - K-Means Lite Clustering
public final class MarketClusterer {
    public let k: Int
    private var centroids: [MarketFeatureSet] = []
    private(set) var iterationCount = 0

    public init(k: Int = 5) {
        self.k = max(2, min(k, 10))
    }

    public func extractFeatures(from snapshots: [MarketSnapshot]) -> [MarketFeatureSet] {
        snapshots.map { snapshot in
            let closes = snapshot.closes
            let returns = zip(closes.dropFirst(), closes.dropLast()).map { $0.0 / $0.1 - 1 }
            let volatility = sqrt(max(0, returns.map { $0 * $0 }.reduce(0, +) / Double(max(1, returns.count)))) * sqrt(252)
            let momentum: Double
            if closes.count > 10, closes[closes.count - 11] != 0 {
                momentum = (closes.last ?? 0) / closes[closes.count - 11] - 1
            } else {
                momentum = 0
            }
            let averageVolume = snapshot.volumes.mean
            let normalizedVolume = min(1, averageVolume / 20_000_000)
            let price = max(1, snapshot.currentPrice)

            return MarketFeatureSet(
                symbol: snapshot.symbol,
                volatility: min(1, volatility),
                momentum: clamp(momentum, -0.5, 0.5),
                value: 1 / price,
                quality: 0.5,
                size: log10(price),
                liquidity: normalizedVolume
            )
        }
    }

    public func cluster(_ features: [MarketFeatureSet]) -> [ClusterAssignment] {
        guard !features.isEmpty else { return [] }

        centroids = initializeCentroids(features)
        iterationCount = 0

        for _ in 0..<10 {
            var groups: [[MarketFeatureSet]] = Array(repeating: [], count: centroids.count)
            for feature in features {
                let index = nearestCentroidIndex(feature)
                groups[index].append(feature)
            }
            for index in centroids.indices where !groups[index].isEmpty {
                centroids[index] = average(groups[index], symbol: "centroid-\(index)")
            }
            iterationCount += 1
        }

        var assignmentsBySymbol: [String: ClusterAssignment] = [:]
        for feature in features {
            let index = nearestCentroidIndex(feature)
            let cluster = MarketRegimeCluster.allCases[index % MarketRegimeCluster.allCases.count]
            let confidence = calculateConfidence(feature, centroid: centroids[index])
            assignmentsBySymbol[feature.symbol] = ClusterAssignment(
                symbol: feature.symbol,
                cluster: cluster,
                confidence: confidence,
                featureSet: feature
            )
        }
        return Array(assignmentsBySymbol.values)
    }

    private func initializeCentroids(_ features: [MarketFeatureSet]) -> [MarketFeatureSet] {
        let sorted = features.sorted { $0.volatility < $1.volatility }
        var centroids: [MarketFeatureSet] = []
        let step = max(1, sorted.count / max(1, k))

        for index in stride(from: 0, to: sorted.count, by: step) {
            if centroids.count == k { break }
            centroids.append(sorted[index])
        }

        while centroids.count < k {
            centroids.append(MarketFeatureSet(
                symbol: "centroid-\(centroids.count)",
                volatility: 0.5,
                momentum: 0,
                value: 0.5,
                quality: 0.5,
                size: 10,
                liquidity: 0.5
            ))
        }
        return centroids
    }

    private func nearestCentroidIndex(_ feature: MarketFeatureSet) -> Int {
        guard !centroids.isEmpty else { return 0 }
        var minimumDistance = Double.infinity
        var closestIndex = 0

        for (index, centroid) in centroids.enumerated() {
            let distance = squaredDistance(feature, centroid)
            if distance < minimumDistance {
                minimumDistance = distance
                closestIndex = index
            }
        }
        return closestIndex
    }

    private func squaredDistance(_ lhs: MarketFeatureSet, _ rhs: MarketFeatureSet) -> Double {
        pow(lhs.volatility - rhs.volatility, 2) +
        pow(lhs.momentum - rhs.momentum, 2) +
        pow(lhs.value - rhs.value, 2) +
        pow(lhs.quality - rhs.quality, 2) +
        pow(lhs.size - rhs.size, 2) +
        pow(lhs.liquidity - rhs.liquidity, 2)
    }

    private func calculateConfidence(_ feature: MarketFeatureSet, centroid: MarketFeatureSet) -> Double {
        1.0 / (1.0 + sqrt( squaredDistance(feature, centroid) ))
    }

    private func average(_ features: [MarketFeatureSet], symbol: String) -> MarketFeatureSet {
        guard !features.isEmpty else {
            return MarketFeatureSet(
                symbol: symbol,
                volatility: 0.5,
                momentum: 0,
                value: 0.5,
                quality: 0.5,
                size: 10,
                liquidity: 0.5
            )
        }
        let count = Double(features.count)
        return MarketFeatureSet(
            symbol: symbol,
            volatility: features.reduce(0) { $0 + $1.volatility } / count,
            momentum: features.reduce(0) { $0 + $1.momentum } / count,
            value: features.reduce(0) { $0 + $1.value } / count,
            quality: features.reduce(0) { $0 + $1.quality } / count,
            size: features.reduce(0) { $0 + $1.size } / count,
            liquidity: features.reduce(0) { $0 + $1.liquidity } / count
        )
    }
}

// MARK: - Clustering Registry
public final class ClusteringRegistry: ObservableObject {
    @Published public var clusters: [ClusterAssignment] = []
    @Published public var modelInfo: String = "No clustering model loaded"

    private var clusterer: MarketClusterer?

    public init() {}

    public func setData(_ snapshots: [MarketSnapshot]) {
        if clusterer == nil {
            clusterer = MarketClusterer()
        }
        guard let clusterer else { return }
        let features = clusterer.extractFeatures(from: snapshots)
        clusters = clusterer.cluster(features)
        modelInfo = "Clustered \(clusters.count) symbols into \(clusterer.k) groups"
    }

    public func updateClusterCount(_ k: Int) {
        clusterer = MarketClusterer(k: k)
    }
}
