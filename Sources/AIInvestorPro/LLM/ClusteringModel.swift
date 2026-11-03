// MARK: - Market Clustering
import Foundation

public enum MarketRegimeCluster: String, CaseIterable {
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

public struct MarketFeatureSet: Equatable {
    public let volatility: Double
    public let momentum: Double
    public let value: Double      // e.g., P/E ratio inverse or other value metric
    public let quality: Double    // e.g., ROE, profit margins
    public let size: Double       // market cap normalized
    public let liquidity: Double  // average daily volume
    
    public static func == (lhs: MarketFeatureSet, rhs: MarketFeatureSet) -> Bool {
        abs(lhs.volatility - rhs.volatility) < 0.01 &&
        abs(lhs.momentum - rhs.momentum) < 0.01 &&
        abs(lhs.value - rhs.value) < 0.01 &&
        abs(lhs.quality - rhs.quality) < 0.01 &&
        abs(lhs.size - rhs.size) < 0.01 &&
        abs(lhs.liquidity - rhs.liquidity) < 0.01
    }
}

public struct ClusterAssignment: Equatable {
    public let symbol: String
    public let cluster: MarketRegimeCluster
    public let confidence: Double // 0.0 - 1.0
    public let featureSet: MarketFeatureSet
    public assignedAt: Date
    
    public init(symbol: String, cluster: MarketRegimeCluster, confidence: Double, featureSet: MarketFeatureSet) {
        self.symbol = symbol
        self.cluster = cluster
        self.confidence = confidence
        self.featureSet = featureSet
        self.assignedAt = Date()
    }
}

// MARK: - K-Means Lite Clustering
public final class MarketClusterer {
    // Simple k-means implementation for market segmentation
    private let k: Int
    private var centroids: [MarketFeatureSet] = []
    private var assignments: [String: ClusterAssignment] = [:]
    private var iterationCount = 0
    
    public init(k: Int = 5) {
        self.k = max(2, min(k, 10))
    }
    
    // Feature extraction from market data
    public func extractFeatures(from snapshots: [MarketSnapshot]) -> [MarketFeatureSet] {
        var features: [MarketFeatureSet] = []
        
        for snapshot in snapshots {
            let vol = snapshot.volatility / 100.0 // Normalize
            let mom = snapshot.technical.rsi / 100.0 // Normalized RSI
            let val = 1.0 / max(1.0, snapshot.rsi / 100.0) // Value proxy
            let qual = 0.5 // Placeholder for quality metrics
            let size = log10(max(1, snapshot.currentPrice)) // Size proxy
            let liquidity = min(snapshot.volatility / 1000000, 1.0) // Liquidity proxy
            
            features.append(MarketFeatureSet(
                volatility: vol,
                momentum: mom,
                value: val,
                quality: qual,
                size: size,
                liquidity: liquidity
            ))
        }
        
        return features
    }
    
    // Run k-means clustering
    public func cluster(_ features: [MarketFeatureSet]) -> [ClusterAssignment] {
        guard !features.isEmpty, k > 0 else { return [] }
        
        // Initialize centroids randomly
        centroids = initializeCentroids(features)
        iterationCount = 0
        
        // Run for fixed iterations
        let maxIterations = 10
        
        for _ in 0..<maxIterations {
            // Assign points to nearest centroid
            assignments.removeAll()
            
            for featureSet in features {
                let closestIdx = nearestCentroidIndex(featureSet)
                let cluster = MarketRegimeCluster.allCases[closestIdx % MarketRegimeCluster.allCases.count]
                let confidence = calculateConfidence(featureSet, centroid: centroids[closestIdx])
                assignments[featureSet.symbol] = ClusterAssignment(
                    symbol: featureSet.symbol, // Would need symbol from features
                    cluster: cluster,
                    confidence: confidence,
                    featureSet: featureSet
                )
            }
            
            // Update centroids
            updateCentroids(features)
            iterationCount += 1
        }
        
        return Array(assignments.values)
    }
    
    private func initializeCentroids(_ features: [MarketFeatureSet]) -> [MarketFeatureSet] {
        var centroids: [MarketFeatureSet] = []
        let sorted = features.sorted { $0.volatility < $1.volatility }
        
        // Take evenly spread points
        let step = max(1, sorted.count / k)
        for i in stride(from: 0, to: sorted.count, by: step) {
            let idx = min(i, sorted.count - 1)
            centroids.append(sorted[idx])
        }
        
        // Pad if needed
        while centroids.count < k {
            centroids.append(MarketFeatureSet(
                volatility: 0.5, currency: "$", ratio: "ratio", price: "$/share", volatility: "%/year", sharpe: "ratio", drawdown: "%", returnPerTrade: "$", winRate: "%", sampleSize: "count"
            ))
        }
        
        return centroids
    }
    
    private func nearestCentroidIndex(_ featureSet: MarketFeatureSet) -> Int {
        var minDistance = Double.infinity
        var closestIdx = 0
        
        for (idx, centroid) in centroids.enumerated() {
            let distance = sqrt(
                pow(featureSet.volatility - centroid.volatility, 2) +
                pow(featureSet.momentum - centroid.momentum, 2) +
                pow(featureSet.value - centroid.value, 2) +
                pow(featureSet.quality - centroid.quality, 2)
            )
            
            if distance < minDistance {
                minDistance = distance
                closestIdx = idx
            }
        }
        
        return closestIdx
    }
    
    private func calculateConfidence(_ featureSet: MarketFeatureSet, centroid: MarketFeatureSet) -> Double {
        // Simple confidence based on how close the feature set is to centroid
        let distance = sqrt(
            pow(featureSet.volatility - centroid.volatility, 2) +
            pow(featureSet.momentum - centroid.momentum, 2)
        )
        return max(0.01, 1.0 - distance)
    }
    
    private func updateCentroids(_ features: [MarketFeatureSet]) {
        // Recalculate centroids as mean of assigned points
        // Simplified - in full implementation would track assigned points per cluster
        for i in 0..<k {
            centroids[i] = MarketFeatureSet(
                volatility: Double.random(in: 0.3...0.8),
                momentum: Double.random.in(-0.5...0.5),
                value: Double.random.in(0.5...1.5),
                quality: Double.random.in(0.5...1.5),
                size: Double.random.in(10...20),
                liquidity: Double.random.in(0.5...1.5)
            )
        }
    }
}

// MARK: - Model Registry Integration
public final class ClusteringRegistry: ObservableObject {
    @Published public var clusters: [ClusterAssignment] = []
    @Published public var modelInfo: String = "No clustering model loaded"
    
    private var clusterer: MarketClusterer?
    
    public func setData(_ snapshots: [MarketSnapshot]) {
        let features = clusterer?.extractFeatures(from: snapshots) ?? []
        let assignments = clusterer?.cluster(features) ?? []
        clusters = assignments
        modelInfo = "Clustered \(clusters.count) symbols into \(clusterer?.k ?? 5) groups"
    }
    
    public func updateClusterCount(_ k: Int) {
        clusterer = MarketClusterer(k: k)
    }
}
