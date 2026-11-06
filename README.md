# AIInvestorPro

AIInvestorPro is a Swift/SwiftUI playground for AI-assisted investment analysis: technical
indicators, risk analytics, backtesting, portfolio construction, screening, alerts, and
local portfolio persistence.

> **Project status**
>
> The original `AIInvestorPro` SwiftUI target has been repaired against every finding in
> [`docs/AUDIT.md`](docs/AUDIT.md): imports, duplicate types, immutable-value mutation,
> indicator math, portfolio cost basis, backtest P&L, deterministic market data and
> `@MainActor` UI updates. The repair was performed without a local Swift toolchain, so
> `swift build` still needs verification on macOS/Linux; see the `Swift` workflow.
>
> Two independent deliverables now live in the repository:
>
> * **InvestorKit** — a dependency-free, tested Swift analytics library.
> * **InvestorKit Web** — an installable, offline-first PWA under [`web/`](web/README.md)
>   that runs the same kind of analytics on Android, iPhone, iPad, Windows, macOS,
>   Linux, ChromeOS and any modern browser.
>
> Nothing from the original target was removed.

## InvestorKit

`InvestorKit` is a Swift 5.9+ library that depends only on Foundation. It is
UI-independent, `Sendable`-friendly, and designed to be testable and deterministic.

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

# Build and test only the new library (no SwiftUI/Apple frameworks required)
INVESTORKIT_ONLY=1 swift build
INVESTORKIT_ONLY=1 swift test
INVESTORKIT_ONLY=1 swift run InvestorKitDemo
```

The demo runs a strategy comparison, a max-Sharpe optimization, a Monte Carlo simulation,
tax-lot accounting, alerts, and a screener against synthetic data. It writes
`demo-backtest.md` in the working directory.

Without the environment variable, the manifest also includes the legacy
`AIInvestorPro` SwiftUI executable target. That target requires macOS or an Apple
platform toolchain; CI builds it on `macos-14`.

> The repair was written without a local Swift toolchain (Termux/Android). Run the
> commands above on macOS or Linux with Swift 5.9+ before merging. The audit distinguishes
> static findings from verified build results.

## Cross-platform web app (Android included)

SwiftUI does not run on Android, so the same analytics are also available as a
dependency-free, installable PWA in [`web/`](web/README.md).

```bash
cd web
node server.mjs          # http://localhost:8080/
npm install              # only for the JSDOM smoke test
npm test                 # 82 numerical/unit tests
npm run test:ui          # drives every tab in a DOM
npm run test:all
```

The app works offline, needs no account, server, API key or network, and installs to an
Android home screen (Chrome/Edge/Samsung Internet), an iPhone/iPad home screen (Safari
Share → Add to Home Screen), or a desktop. Portfolio, alerts and theme are stored locally.

GitHub Pages deployment is automated by
[`.github/workflows/pages.yml`](.github/workflows/pages.yml). Expected URL after enabling
Pages with **GitHub Actions** as the source:

```text
https://yuanjing-sudo.github.io/AIInvestorPro-source/
```

Features: dashboard, price/chart indicators, 9-strategy backtester, constrained portfolio
optimizer with efficient frontier, correlated Monte Carlo risk lab, screener, portfolio
ledger with FIFO/LIFO/HIFO/LOFO tax-lot comparison, and price/RSI/volume alerts.

### Layout

```
Sources/AIInvestorPro/     Repaired SwiftUI app target
Sources/InvestorKit/       Dependency-free analytics library
Sources/InvestorKitDemo/   Runnable command-line demo
Tests/InvestorKitTests/    XCTest coverage for indicators, analytics, risk, trading,
                           screener, persistence, and export
web/                       Installable cross-platform PWA and its tests
docs/AUDIT.md              Prioritized audit and remediation record
.github/workflows/         Swift CI and GitHub Pages deployment
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

1. **Verify the app target** with `swift build` on macOS and fix any remaining
   compiler diagnostics surfaced by CI.
2. **Wire InvestorKit into SwiftUI** behind observable, `@MainActor` view models.
3. **Expand CI** with a macOS SwiftUI build, SwiftLint or swift-format, and web tests.
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
