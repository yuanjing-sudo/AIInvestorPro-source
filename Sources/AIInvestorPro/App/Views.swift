// MARK: - Views
import SwiftUI

// MARK: - Main Views
public struct AIInvestorProView: View {
    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("AIInvestorPro")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.bottom, 20)
                    
                    // Portfolio Section
                    PortfolioSummaryView()
                    
                    // Market Analysis
                    MarketAnalysisView()
                    
                    // Trade Ideas
                    TradeIdeasView()
                    
                    // Alerts
                    AlertsView()
                    
                    Spacer()
                }
                .padding()
                .navigationTitle("AI Investor Pro")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu("Actions") {
                            Button("Refresh") { /* refresh data */ }
                            Button("Settings") { /* open settings */ }
                            Button("About") { /* show about */ }
                        }
                    }
                }
            }
        }
    }
}

public struct PortfolioSummaryView: View {
    @EnvironmentObject var portfolio: Portfolio
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Portfolio")
                .font(.headline)
            
            HStack {
                Text("Total Value")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(portfolio.totalValue.formattedCurrency)
            }
            
            HStack {
                Text("Cash")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("$\(String(format: "%.2f", portfolio.cash))")
            }
            
            HStack {
                Text("Total Return")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(String(format: "%.2f", portfolio.totalReturn()))%")
                    .foregroundColor(portfolio.totalReturn() >= 0 ? .green : .red)
            }
            
            if !portfolio.holdings.isEmpty {
                HStack {
                    Text("Holdings")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(portfolio.holdings.count)")
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .cornerRadius(10)
    }
}

public struct MarketAnalysisView: View {
    @State private var selectedRegime: MarketRegime = .unknown
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Market Regime")
                .font(.headline)
            
            Picker("Regime", selection: $selectedRegime) {
                ForEach(MarketRegime.allCases) { regime in
                    HStack {
                        Text(regime.uiColor)
                        Text(regime.rawValue.capitalized)
                    }.tag(regime)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            
            Text("Currently analyzing market conditions...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .cornerRadius(10)
    }
}

public struct TradeIdeasView: View {
    @State private var tradeIdeas: [TradeIdea] = []
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Trade Ideas")
                .font(.headline)
            
            if tradeIdeas.isEmpty {
                Text("No trade ideas available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(tradeIdeas) { idea in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(idea.symbol)
                                .font(.subheadline)
                            Spacer()
                            Text(idea.direction.rawValue)
                                .font(.caption)
                                .padding(4)
                                .background(idea.direction == .buy ? Color.green : Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                        
                        HStack {
                            Text("Entry: \(String(format: "$%.2f", idea.entryPrice))")
                            Spacer()
                            Text("Target: \(String(format: "$%.2f", idea.targetPrice))")
                        }
                        
                        HStack {
                            Text("Stop: \(String(format: "$%.2f", idea.stopLoss))")
                            Spacer()
                            Text("Confidence: \(String(format: "%.0f", idea.confidence * 100))%")
                        }
                        
                        Divider()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .cornerRadius(10)
    }
}

public struct AlertsView: View {
    @StateObject private var alertStore = AlertStore()
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Price Alerts")
                .font(.headline)
            
            HStack {
                TextField("Symbol (e.g., AAPL)", text: .constant(""))
                    .textFieldStyle(.roundedBorder)
                Button("Add Alert") { /* add alert */ }
            }
            
            if alertStore.alerts.isEmpty {
                Text("No alerts set")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(alertStore.alerts) { alert in
                    HStack {
                        Text("\(alert.symbol) \(alert.alertType.rawValue) \(String(format: "$%.2f", alert.targetPrice))")
                        Spacer()
                        if alert.isTriggered {
                            Text("TRIGGERED")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            
            Button("Clear Triggered") {
                alertStore.clearTriggered()
            }
            .font(.caption)
            .foregroundColor(.blue)
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .cornerRadius(10)
    }
}

// MARK: - View Extensions
public extension View {
    func placeholder<Content: View>(when shouldShow: Bool, alignment: Alignment = .center, @ViewBuilder placeholder: () -> Content) -> some View {
        ZStack(alignment: alignment) {
            if shouldShow {
                placeholder()
            } else {
                self
            }
        }
    }
}
