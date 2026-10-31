// MARK: - SwiftUI Views (multiplatform: iOS 17+ / macOS 14+)
import SwiftUI
import Charts

public struct ContentView: View {
    @StateObject private var market = MarketStore()
    @StateObject private var portfolio = PortfolioStore()
    @StateObject private var alerts = AlertStore()
    @StateObject private var setups = SetupStore()
    @StateObject private var settings = AppSettings.shared
    
    public var body: some View {
        TabView {
            MarketsTab(market: market, alerts: alerts)
                .tabItem { Label("Markets", systemImage: "chart.line.uptrend.xyaxis") }
            ScanTab(market: market, portfolio: portfolio, setups: setups)
                .tabItem { Label("Scan", systemImage: "magnifyingglass") }
            PortfolioTab(market: market, portfolio: portfolio)
                .tabItem { Label("Portfolio", systemImage: "briefcase") }
            BacktestTab(market: market)
                .tabItem { Label("Backtest", systemImage: "clock.arrow.circlepath") }
            AnalyzeTab(market: market)
                .tabItem { Label("Analyze", systemImage: "brain") }
            SettingsTab()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .environmentObject(settings)
    }
}
