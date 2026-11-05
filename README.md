# AIInvestorPro

AIInvestorPro is a Swift/SwiftUI playground for AI-assisted investment analysis: technical
indicators, risk analytics, backtesting, portfolio construction, screening, alerts, and
local portfolio persistence.

> **Project status**
>
> The original `AIInvestorPro` app target (under `Sources/AIInvestorPro`) is **not
> currently buildable**. It contains a large amount of generated-looking code with
> missing imports, undeclared symbols, duplicate types, and syntax errors. See
> [`docs/AUDIT.md`](docs/AUDIT.md) for the full prioritized list.
>
> A new, dependency-free analytics library — **InvestorKit** — has been added so the
> quantitative core can be built, tested, and reused independently while the legacy
> app target is repaired. Nothing from the original target was removed.

## InvestorKit

`InvestorKit` is a Swift 6 library that depends only on Foundation. It is UI-independent,
`Sendable`-friendly, and designed to be testable and deterministic.

| Area | What is included |
| --- | --- |
| Market data | `MarketDataProvider` protocol, actor-based `YahooFinanceProvider` (throttling, retry with backoff, short-lived cache), deterministic `MockMarketDataProvider` |
| Indicators | SMA, EMA, Wilder RMA, RSI, MACD, true range/ATR, ADX/DI, stochastic, Williams %R, CCI, ROC, Bollinger Bands, Keltner Channels, Donchian Channels, VWAP, OBV, MFI, Supertrend, Aroon, Ichimoku |
| Performance | Total return, CAGR, annualized volatility, Sharpe, Sortino, Calmar, max drawdown, Ulcer index, historical VaR/CVaR, skewness, excess kurtosis, beta, alpha, information ratio |
| Risk | Covariance/correlation matrices, portfolio variance and volatility, risk contributions, diversification ratio, parametric and historical VaR/CVaR, Monte Carlo simulation, stress scenarios, concentration (HHI) |
| Optimization | Equal weight, inverse volatility, minimum variance, maximum Sharpe, risk parity, with min/max weight and fully-invested constraints |
| Backtesting | Next-bar-open execution (no look-ahead), commission and slippage, per-bar equity curve, fills, configurable constraints, strategy catalog, composite strategies |
| Tax lots | FIFO, LIFO, highest-cost, and lowest-cost lot selection; realized sales and unrealized P&L |
| Alerts | Edge-triggered rules, crossings, percent-change rules, cooldowns, one-shot rules |
| Screener | Price/volume/market-cap/sector/metric filters, human-readable rejection reasons, transparent composite score |
| Persistence | Actor-isolated atomic JSON store with backup, plus weighted-average-cost transaction application |
| Export | CSV (RFC 4180-style escaping), Markdown reports, JSON |

### Build and test

The legacy app target is excluded from the build when `INVESTORKIT_ONLY=1` is set:

```bash
git clone https://github.com/yuanjing-sudo/AIInvestorPro-source.git
cd AIInvestorPro-source

# Build and test only the new library (works while the app target is broken)
INVESTORKIT_ONLY=1 swift build
INVESTORKIT_ONLY=1 swift test
INVESTORKIT_ONLY=1 swift run InvestorKitDemo
```

The demo runs a strategy comparison, a max-Sharpe optimization, a Monte Carlo simulation,
tax-lot accounting, alerts, and a screener against synthetic data. It writes
`demo-backtest.md` in the working directory.

Without the environment variable, the manifest behaves as before and also includes the
legacy `AIInvestorPro` executable target (which currently fails to compile).

> The new code was written without a local Swift toolchain (Termux/Android). Run the
> commands above on macOS or Linux with Swift 6 before merging. The audit distinguishes
> static findings from verified build results.

### Layout

```
Sources/AIInvestorPro/     Legacy SwiftUI app target (broken; see docs/AUDIT.md)
Sources/InvestorKit/       New dependency-free analytics library
Sources/InvestorKitDemo/   Runnable command-line demo
Tests/InvestorKitTests/    XCTest coverage for indicators, analytics, risk, trading,
                           screener, persistence, and export
docs/AUDIT.md              Prioritized audit of the legacy target
```

## Using the library

```swift
import InvestorKit

let provider = MockMarketDataProvider(seed: 7)
let candles = try await provider.candles(symbol: "AAPL", range: .twoYears, interval: .oneDay)

let result = BacktestEngine().run(
    strategy: SMACrossoverStrategy(fastPeriod: 20, slowPeriod: 50),
    candles: candles,
    symbol: "AAPL"
)

if let report = result?.report {
    print(report.summary)
}
```

## Roadmap

1. **Repair the app target** in small, reviewable PRs (imports, declarations, then
   correctness; see the remediation order in `docs/AUDIT.md`).
2. **Wire InvestorKit into SwiftUI** behind observable, `@MainActor` view models.
3. **Add CI** (`swift build`, `swift test`, and a macOS SwiftUI build) plus SwiftLint or
   swift-format.
4. **Replace heuristics** with production-grade components:
   - a real QP solver for the optimizer,
   - a portfolio-level (multi-asset) backtester,
   - split/dividend aware tax-lot accounting and wash-sale handling,
   - provider adapters for a licensed market-data feed.
5. **Harden the Yahoo client**: response validation, cancellation propagation, metrics,
   and a documented fallback when the unofficial endpoint changes.

## Disclaimer

This project is for education and research. It is not investment advice. Market data from
the Yahoo Finance endpoint is unofficial, may be delayed or inaccurate, and is not suitable
for live trading without a licensed feed and independent validation.
