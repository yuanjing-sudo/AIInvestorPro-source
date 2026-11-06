// MARK: - AIInvestorPro App
import SwiftUI

@main
public struct AIInvestorProApp: App {
    // MARK: - State Properties
    @StateObject private var portfolio = Portfolio()
    @StateObject private var alertStore = AlertStore()
    @State private var selectedTab = 0

    public init() {}

    // MARK: - Body
    public var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(portfolio)
                .environmentObject(alertStore)
        }
    }
}

// MARK: - Content View
public struct ContentView: View {
    @EnvironmentObject var portfolio: Portfolio
    @EnvironmentObject var alertStore: AlertStore
    
    public var body: some View {
        TabView {
            AIInvestorProView()
                .tabItem {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text("Dashboard")
                }
            
            PortfolioView()
                .tabItem {
                    Image(systemName: "bag.fill")
                    Text("Portfolio")
                }
            
            AnalysisView()
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("Analysis")
                }
            
            AlertsView()
                .tabItem {
                    Image(systemName: "bell.fill")
                    Text("Alerts")
                }
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
        }
    }
}

// MARK: - Portfolio View
public struct PortfolioView: View {
    @EnvironmentObject var portfolio: Portfolio
    
    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Portfolio Summary")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    PortfolioSummaryView()
                        .environmentObject(portfolio)
                    
                    HStack {
                        Text("Holdings")
                            .font(.headline)
                        Spacer()
                        Text("\(portfolio.holdings.count) positions")
                            .foregroundColor(.secondary)
                    }
                    
                    if !portfolio.holdings.isEmpty {
                        ForEach(portfolio.holdings) { holding in
                            HStack {
                                Text(holding.symbol)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(String(format: "%.2f", holding.quantity)) shares")
                                    .font(.subheadline)
                                Text("$\(String(format: "%.2f", holding.currentValue))")
                                    .font(.subheadline)
                                .foregroundColor(holding.unrealizedPnL >= 0 ? .green : .red)
                            }
                            .padding(.vertical, 4)
                        }
                    } else {
                        Text("No holdings")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding()
                .navigationTitle("Portfolio")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Add") { /* add holding */ }
                    }
                }
            }
        }
    }
}

// MARK: - Analysis View
public struct AnalysisView: View {
    @State private var selectedSymbol: String = "AAPL"
    @State private var showingAnalysis = false
    
    public var body: some View {
        NavigationView {
            VStack {
                HStack {
                    TextField("Symbol", text: $selectedSymbol)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                    
                    Button("Analyze") {
                        showingAnalysis = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                
                if showingAnalysis {
                    AnalysisDetailView(symbol: selectedSymbol)
                }
            }
            .navigationTitle("Stock Analysis")
        }
    }
}

// MARK: - Analysis Detail View
struct AnalysisDetailView: View {
    let symbol: String
    @State private var analysis: AnalysisResult?
    
    var body: some View {
        Group {
            if let analysis = analysis {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("\(symbol) Analysis")
                            .font(.largeTitle)
                        
                        Text(ReportRenderer.render(analysis))
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.gray.opacity(0.08))
                            .cornerRadius(10)
                        
                        Button("New Analysis") {
                            // Trigger new analysis
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                }
            } else {
                Text("Select a symbol to analyze")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}


// MARK: - Settings View
public struct SettingsView: View {
    @AppStorage("useDarkMode") private var useDarkMode = false

    public init() {}

    public var body: some View {
        NavigationView {
            Form {
                Section("Appearance") {
                    Toggle("Dark Mode", isOn: $useDarkMode)
                }
                Section("About") {
                    Text("AIInvestorPro")
                    Text("Analytics are for educational purposes only and are not investment advice.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
