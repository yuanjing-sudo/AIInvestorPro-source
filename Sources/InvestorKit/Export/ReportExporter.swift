import Foundation

// MARK: - CSV

public enum CSV {
    /// RFC 4180-style CSV with quoted fields when needed.
    public static func encode(headers: [String], rows: [[String]]) -> String {
        var lines = [headers.map(escape).joined(separator: ",")]
        lines.reserveCapacity(rows.count + 1)
        for row in rows {
            lines.append(row.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"")
            || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}

// MARK: - Exporter

public enum ReportExporter {

    // MARK: Trades

    public static func tradesCSV(_ fills: [TradeFill]) -> String {
        let formatter = ISO8601DateFormatter()
        let headers = [
            "date", "symbol", "side", "quantity", "price",
            "notional", "commission", "slippage_cost", "target_exposure",
        ]
        let rows = fills.map { fill in
            [
                formatter.string(from: fill.date),
                fill.symbol,
                fill.side.rawValue,
                String(format: "%.6f", fill.quantity),
                String(format: "%.6f", fill.price),
                String(format: "%.2f", fill.notional),
                String(format: "%.4f", fill.commission),
                String(format: "%.4f", fill.slippageCost),
                String(format: "%.4f", fill.targetExposure),
            ]
        }
        return CSV.encode(headers: headers, rows: rows)
    }

    // MARK: Equity

    public static func equityCSV(_ points: [EquityPoint]) -> String {
        let formatter = ISO8601DateFormatter()
        let headers = ["date", "equity", "cash", "position_value", "exposure"]
        let rows = points.map { point in
            [
                formatter.string(from: point.date),
                String(format: "%.2f", point.equity),
                String(format: "%.2f", point.cash),
                String(format: "%.2f", point.positionValue),
                String(format: "%.6f", point.exposure),
            ]
        }
        return CSV.encode(headers: headers, rows: rows)
    }

    // MARK: Markdown

    public static func markdown(_ result: BacktestResult, tradeLimit: Int = 25) -> String {
        var lines: [String] = []
        lines.append("# Backtest Report — \(result.strategyName)")
        lines.append("")
        lines.append("- Symbol: **\(result.symbol)**")
        lines.append("- Bars: \(result.equityCurve.count)")
        lines.append("- Initial equity: \(result.config.initialCash.formattedCurrency())")
        lines.append("- Final equity: \(result.finalEquity.formattedCurrency())")
        lines.append("- Total commission: \(result.totalCommission.formattedCurrency())")
        lines.append("- Total turnover: \(result.totalTurnover.formattedCurrency())")
        lines.append("- Trades: \(result.numberOfTrades)")
        lines.append("")

        if let report = result.report {
            lines.append("## Performance")
            lines.append("")
            lines.append("| Metric | Value |")
            lines.append("| --- | ---: |")
            lines.append("| Total return | \(report.totalReturn.formattedPercent()) |")
            lines.append("| CAGR | \(report.cagr.formattedPercent()) |")
            lines.append("| Annualized volatility | \(report.annualizedVolatility.formattedPercent()) |")
            lines.append("| Sharpe ratio | \(String(format: "%.2f", report.sharpeRatio)) |")
            lines.append("| Sortino ratio | \(String(format: "%.2f", report.sortinoRatio)) |")
            lines.append("| Calmar ratio | \(String(format: "%.2f", report.calmarRatio)) |")
            lines.append("| Max drawdown | \(report.maxDrawdown.formattedPercent()) |")
            lines.append("| Ulcer index | \(report.ulcerIndex.formattedPercent()) |")
            lines.append("| VaR 95% | \(report.valueAtRisk95.formattedPercent()) |")
            lines.append("| CVaR 95% | \(report.conditionalValueAtRisk95.formattedPercent()) |")
            lines.append("| Win rate | \(report.winRate.formattedPercent()) |")
            lines.append("| Profit factor | \(String(format: "%.2f", report.profitFactor)) |")
            if let beta = report.beta {
                lines.append("| Beta | \(String(format: "%.2f", beta)) |")
            }
            if let alpha = report.alpha {
                lines.append("| Alpha (annualized) | \(alpha.formattedPercent()) |")
            }
            lines.append("")
        }

        if !result.fills.isEmpty {
            lines.append("## Trades")
            lines.append("")
            lines.append("| Date | Side | Quantity | Price | Notional | Commission |")
            lines.append("| --- | --- | ---: | ---: | ---: | ---: |")
            let formatter = ISO8601DateFormatter()
            for fill in result.fills.prefix(tradeLimit) {
                lines.append(
                    "| \(formatter.string(from: fill.date)) | \(fill.side.rawValue) | "
                        + "\(String(format: "%.2f", fill.quantity)) | "
                        + "\(fill.price.formattedCurrency()) | "
                        + "\(fill.notional.formattedCurrency()) | "
                        + "\(fill.commission.formattedCurrency()) |"
                )
            }
            if result.fills.count > tradeLimit {
                lines.append("")
                lines.append("_Showing \(tradeLimit) of \(result.fills.count) trades._")
            }
            lines.append("")
        }

        lines.append("_Generated \(ISO8601DateFormatter().string(from: Date()))_")
        return lines.joined(separator: "\n")
    }

    public static func markdown(
        report: PerformanceReport,
        title: String,
        generatedAt: Date = Date()
    ) -> String {
        var lines: [String] = ["# \(title)", ""]
        lines.append("| Metric | Value |")
        lines.append("| --- | ---: |")
        lines.append("| Periods | \(report.periodCount) |")
        lines.append("| Start value | \(report.startValue.formattedCurrency()) |")
        lines.append("| End value | \(report.endValue.formattedCurrency()) |")
        lines.append("| Total return | \(report.totalReturn.formattedPercent()) |")
        lines.append("| CAGR | \(report.cagr.formattedPercent()) |")
        lines.append("| Annualized volatility | \(report.annualizedVolatility.formattedPercent()) |")
        lines.append("| Sharpe | \(String(format: "%.2f", report.sharpeRatio)) |")
        lines.append("| Sortino | \(String(format: "%.2f", report.sortinoRatio)) |")
        lines.append("| Max drawdown | \(report.maxDrawdown.formattedPercent()) |")
        lines.append("| VaR 95% | \(report.valueAtRisk95.formattedPercent()) |")
        lines.append("| CVaR 95% | \(report.conditionalValueAtRisk95.formattedPercent()) |")
        lines.append("")
        lines.append("_Generated \(ISO8601DateFormatter().string(from: generatedAt))_")
        return lines.joined(separator: "\n")
    }

    // MARK: JSON

    public static func jsonString<T: Encodable>(
        _ value: T,
        prettyPrinted: Bool = true
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var formatting: JSONEncoder.OutputFormatting = [.sortedKeys]
        if prettyPrinted { formatting.insert(.prettyPrinted) }
        encoder.outputFormatting = formatting
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw PortfolioStoreError.encoding("Result is not valid UTF-8")
        }
        return string
    }

    // MARK: Files

    public static func write(_ text: String, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let data = text.data(using: .utf8) else {
                throw PortfolioStoreError.encoding("Text is not valid UTF-8")
            }
            try data.write(to: url, options: .atomic)
        } catch let error as PortfolioStoreError {
            throw error
        } catch {
            throw PortfolioStoreError.io(error.localizedDescription)
        }
    }
}
