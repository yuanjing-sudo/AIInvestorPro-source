// MARK: - Report Renderer
import Foundation

public struct ReportRenderer {
    /// Render a comprehensive analysis report
    public static func render(_ analysis: AnalysisResult) -> String {
        var report = ""
        report += "=== Stock Analysis Report ===\n\n"
        report += "Symbol: \(analysis.symbol)\n"
        report += "Current Price: \(String(format: "$%.2f", analysis.currentPrice))\n\n"
        
        report += "Performance:\n"
        report += "  Total Return: \(String(format: "%.2f%", analysis.totalReturn * 100) %)\n"
        report += "  Recent Return (20 days): \(String(format: "%.2f%", analysis.recentReturn * 100) %)\n\n"
        
        report += "Risk Metrics:\n"
        report += "  Annualized Volatility: \(String(format: "%.2f%", analysis.annualizedVolatility) %)\n\n"
        
        report += "Technical Indicators:\n"
        report += "  SMA 20: \(String(format: "$%.2f", analysis.sma20))\n"
        report += "  SMA 50: \(String(format: "$%.2f", analysis.sma50))\n"
        report += "  EMA 12: \(String(format: "$%.2f", analysis.ema12))\n"
        report += "  EMA 26: \(String(format: "$%.2f", analysis.ema26))\n"
        report += "  MACD: \(String(format: "%.4f", analysis.macd))\n"
        report += "  MACD Signal: \(String(format: "%.4f", analysis.macdSignal))\n"
        report += "  RSI: \(String(format: "%.1f", analysis.rsi))\n\n"
        
        report += "Support/Resistance:\n"
        report += "  Support: \(String(format: "$%.2f", analysis.supportLevel))\n"
        report += "  Resistance: \(String(format: "$%.2f", analysis.resistanceLevel))\n\n"
        
        report += "Technical Signal:\n"
        report += "  RSI: \(String(format: "%.1f", analysis.technical.rsi)) (\(analysis.technical.rsi > 70 ? "Overbought" : analysis.technical.rsi < 30 ? "Oversold" : "Neutral"))\n"
        report += "  MACD: \(analysis.technical.macd > 0 ? "Bullish" : "Bearish")\n"
        report += "  Above SMA 20: \(analysis.technical.aboveSMA20 ? "Yes" : "No")\n"
        report += "Above SMA 50: \(analysis.technical.aboveSMA50 ? "Yes" : "No")\n\n"
        
        report += "Regime: \(analysis.regime.rawValue)\n"
        report += "\(analysis.symbol): \(analysis.symbol) is trading at \(String(format: "$%.2f", analysis.currentPrice))."
        
        return report
    }
}
