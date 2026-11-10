# AIInvestorPro

AIInvestorPro is a Swift/SwiftUI playground for AI-assisted investment analysis: technical
indicators, risk analytics, backtesting, portfolio construction, screening, alerts, and
local portfolio persistence.

> **Project status**
>
> The original `AIInvestorPro` SwiftUI target has been repaired against every finding in
> [`docs/AUDIT.md`](docs/AUDIT.md): imports, duplicate types, immutable-value mutation,
> indicator math, portfolio cost basis, backtest P&L, deterministic market data and
> `@MainActor` UI updates. The repair is now compiler-verified: the `Swift` workflow builds
> the legacy target on macOS and passes all 41 `InvestorKit` tests on Linux and macOS.
>
> Two independent deliverables now live in the repository:
>
> * **InvestorKit** — a dependency-free, tested Swift analytics library.
> * **InvestorKit Web** — an installable, offline-first PWA under [`web/`](web/README.md)
>   that runs the same kind of analytics on Android, iPhone, iPad, Windows, macOS,
>   Linux, ChromeOS and any modern browser.
> * **InvestorKit Worker** — an optional Cloudflare Workers backend under
>   [`worker/`](worker/README.md) that serves the PWA and exposes live, server-side
>   market snapshots, macro proxies, forecast execution and generative AI analysis
>   through Cloudflare Workers AI.
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
platform toolchain; CI builds it on `macos-15`.

> CI is green: `InvestorKit` builds and passes 41 tests on Linux (Swift 5.10), and the
> legacy target builds and passes the `InvestorKitTests` filter on macOS.

## Cross-platform web app (Android included)

SwiftUI does not run on Android, so the same analytics are also available as a
dependency-free, installable PWA in [`web/`](web/README.md).

```bash
cd web
node server.mjs          # http://localhost:8080/
npm install              # only for the JSDOM smoke test
npm test                 # 104 numerical/unit tests
npm run test:ui          # drives every tab in a DOM
npm run test:live        # simulates the Worker API and verifies hydration
npm run test:all
```

The app works offline, needs no account, API key or network for the static build, and
installs to an Android home screen (Chrome/Edge/Samsung Internet), an iPhone/iPad home
screen (Safari Share → Add to Home Screen), or a desktop. Portfolio, alerts and theme
are stored locally.

An optional Cloudflare Worker deployment adds a real server side: the Worker serves the
same PWA and exposes `/api/market`, `/api/quote/:symbol`, `/api/forecast/:symbol`,
`/api/macro`, `/api/sources`, `/api/search?q=` and generative AI endpoints
(`/api/ai/status`, `/api/ai/chat`, `/api/ai/analysis/:symbol`,
`/api/ai/insights/:symbol`). In that mode the browser hydrates a multi-source live feed
(Yahoo Finance for equities/ETFs and news, Coinbase/CoinGecko/DefiLlama for crypto, FRED
for macro and SEC EDGAR for reported US company facts), searches any Yahoo-listed ticker,
requests forecasts from the server and adds an **AI Analyst** tab with grounded research
briefs, chat and a technical/sentiment scan. The Research terminal adds a price chart
with SMA20/SMA50, saved click annotations, 23 explained indicators and an SEC
fundamentals/filings panel.
If the API is unavailable it silently falls back to the deterministic local feed; the
static build stays offline-first and does not pretend to have an LLM. See
[`worker/README.md`](worker/README.md).

GitHub Pages deployment is automated by
[`.github/workflows/pages.yml`](.github/workflows/pages.yml), using **GitHub Actions** as
the Pages source:

```text
https://yuanjing-sudo.github.io/AIInvestorPro-source/
```

### Cloudflare Workers (dynamic / server-side)

```bash
cd worker
npm install
npx wrangler login
npx wrangler deploy
```

The Worker uses Cloudflare's static-assets binding for `web/` and runs the API on the
same origin. For automatic deployment, add `CLOUDFLARE_API_TOKEN` (Workers Scripts: Edit)
and `CLOUDFLARE_ACCOUNT_ID` to the repository's Actions secrets. The
[`cloudflare.yml`](.github/workflows/cloudflare.yml) workflow tests the Worker on every
push and deploys when those secrets are configured. Without them it skips the deploy and
the static Pages site remains available.

### Generative AI (free provider)

The Worker includes an **AI Analyst** tab and a small AI framework layer in
[`worker/src/ai.js`](worker/src/ai.js). It uses **Cloudflare Workers AI** through the
native `AI` binding, so there is no API key in the browser and no separate LLM account.
The default model is `@cf/meta/llama-3.3-70b-instruct-fp8-fast` (Llama 3.3 70B), with
automatic fallback to Llama 3.1 8B and Qwen 3 30B if the primary model is unavailable.

* `POST /api/ai/analysis/:symbol` builds a grounded context from the Worker's live quote,
  performance, volatility, synthetic fundamentals, SEC reported facts, macro, sentiment,
  live or synthetic headlines and data-quality data, then asks the model for a structured
  JSON research brief.
* `POST /api/ai/insights/:symbol` computes 23 deterministic technical indicators with
  plain-English summaries, key support/resistance levels, sentiment, SEC facts and a
  21-day Monte Carlo forecast, then asks the model to interpret the trend, signals, risks
  and forecast uncertainty.
* `POST /api/ai/chat` answers questions about the selected asset using the same context.
  The client sends only the conversation and a symbol; the model call stays server-side.
* `GET /api/ai/status` reports whether the binding is configured and which models are
  available.

Workers AI includes a free daily allocation (10,000 Neurons/day on the Free plan), which
is enough for interactive research and demos. Prompts explicitly require the model to
use only supplied context, separate facts from inference and avoid personalized advice.
Generative output can still be wrong; the app labels it as educational and asks users to
verify data independently.

Features: dashboard, price/chart indicators, 9-strategy backtester, constrained portfolio
optimizer with efficient frontier, correlated Monte Carlo risk lab, screener, portfolio
ledger with FIFO/LIFO/HIFO/LOFO tax-lot comparison, price/RSI/volume alerts, a research
terminal (multi-horizon scorecard, multi-asset normalized comparison, relative strength,
synthetic fundamentals, SEC facts and filings, macro, selected-asset correlation, live or
synthetic news sentiment and data-quality audit) and a forecast studio (drift/Holt/ridge ensemble,
50/80/95% simulation cones, scenario matrix, walk-forward diagnostics and feature
attribution). Searched assets are added to the in-memory universe and appear in the
Research comparison, Screener, Optimize and Risk pickers without a reload. A command
palette, market ribbon, responsive sidebar and mobile navigation make the same build
usable on phones, tablets and desktops. On Cloudflare Workers the same UI gains live data
and server-side forecasts, with an explicit source badge.

### Layout

```
Sources/AIInvestorPro/     Repaired SwiftUI app target
Sources/InvestorKit/       Dependency-free analytics library
Sources/InvestorKitDemo/   Runnable command-line demo
Tests/InvestorKitTests/    XCTest coverage for indicators, analytics, risk, trading,
                           screener, persistence, and export
web/                       Installable cross-platform PWA and its tests
worker/                    Optional Cloudflare Worker: static hosting + live API
docs/AUDIT.md              Prioritized audit and remediation record
.github/workflows/          Swift CI, GitHub Pages and Cloudflare deployment
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

1. ~~**Verify the app target** with `swift build` on macOS and fix any remaining
   compiler diagnostics surfaced by CI.~~ Done: Swift CI is green on Linux and macOS.
2. **Wire InvestorKit into SwiftUI** behind observable, `@MainActor` view models.
3. **Expand CI** with a macOS SwiftUI build, SwiftLint or swift-format, and web tests.
4. **Replace heuristics** with production-grade components:
   - a real QP solver for the optimizer,
   - a portfolio-level (multi-asset) backtester,
   - split/dividend aware tax-lot accounting and wash-sale handling,
   - provider adapters for a licensed market-data feed (the Cloudflare Worker
     currently adapts Yahoo, Coinbase, CoinGecko, DefiLlama and FRED, with optional
     CoinCap and CoinMarketCap keys).
5. **Harden the Yahoo client**: response validation, cancellation propagation, metrics,
   and a documented fallback when the unofficial endpoint changes.

## Disclaimer

This project is for education and research. It is not investment advice. Market data from
the Yahoo Finance endpoint is unofficial, may be delayed or inaccurate, and is not suitable
for live trading without a licensed feed and independent validation.
