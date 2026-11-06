# InvestorKit Web

A dependency-free, installable progressive web app (PWA) for portfolio
analytics, research and probabilistic forecasting. It runs the same numerical
core as the Swift `InvestorKit` library and is designed to work on Android,
iPhone, iPad, Windows, macOS, Linux, ChromeOS and any modern browser.

## Why a web app?

The native target is SwiftUI, which does not run on Android. This PWA provides
feature parity for the analytics that do not need Apple frameworks, without an
app store, account, server or API key. Once loaded it works offline and can be
installed to the home screen or desktop.

## Run locally

```bash
cd web
node server.mjs          # http://localhost:8080/
```

The server binds to `0.0.0.0` and prints a LAN URL. Open that URL on a phone or
tablet connected to the same network to test the same build on Android or iOS.
No `npm install` is required to run the app itself.

## Test

```bash
cd web
npm install              # only needed for the JSDOM smoke test
npm test                 # 100 numerical/unit tests
npm run test:ui          # drives every tab in a JSDOM browser smoke test
npm run test:all         # both
```

The suite covers indicators, performance statistics, covariance/risk
contributions, Monte Carlo determinism, optimizers, backtesting (including a
no-lookahead check), screening, tax lots, alerts, the forecast ensemble and
walk-forward diagnostics, market data/fundamentals/sentiment generation, and the
precache manifest.

## Install on a device

### Android

1. Open the deployed URL in Chrome, Edge or Samsung Internet.
2. Use **Install app** / **Add to Home screen**.
3. Launch it from the home screen. It opens standalone and works offline.

### iPhone / iPad

1. Open the URL in Safari.
2. Tap **Share → Add to Home Screen**.
3. Launch from the home screen.

### Desktop

Chrome and Edge show an install icon in the address bar. A header install button
appears when the browser fires `beforeinstallprompt`.

## Deploy

`.github/workflows/pages.yml` tests the app and publishes the static files from
`web/` to GitHub Pages on every push to `main` that touches `web/`.

Expected URL:

```text
https://yuanjing-sudo.github.io/AIInvestorPro-source/
```

Pages is enabled with **GitHub Actions** as the source; the workflow tests the
web app before publishing only the static `web/` assets.

Any static host works as well: Netlify, Cloudflare Pages, Vercel, S3, nginx or a
USB stick. Upload the contents of `web/` (excluding `tests/`, `scripts/` and
`node_modules/`).

## Features

| Tab | What it does |
| --- | --- |
| Dashboard | Portfolio value/P&L, 26-asset market board, price chart with SMA 20/50, signal board, market ribbon |
| Research | Multi-horizon scorecard, relative strength, drawdown, fundamentals, macro, correlation heatmap, news sentiment, data-quality audit, JSON export |
| Forecast | Drift + Holt + ridge-factor ensemble, Monte Carlo cones (50/80/95%), scenario matrix, terminal distribution, walk-forward diagnostics, feature attribution |
| Backtest | 9 strategies, next-open execution, commission/slippage, equity/drawdown charts, trade log |
| Optimize | Max Sharpe, min variance, risk parity, max diversification, weight cap, efficient frontier |
| Risk | Correlated Monte Carlo with percentile bands, VaR/CVaR, risk decomposition, five stress scenarios |
| Screener | Trend, momentum, RSI, liquidity filters and composite ranking |
| Portfolio | Average cost, unrealized/realized P&L, buy/sell ledger, FIFO/LIFO/HIFO/LOFO tax-lot comparison |
| Alerts | Price, daily change, RSI and volume rules, cooldown, local trigger history |
| Platform | Installation instructions and architecture notes |

A command palette (`Ctrl/Cmd+K` or `/`) jumps to any page or asset. The layout
uses a desktop sidebar, a sticky market ribbon, a global search field, keyboard
shortcuts and a five-item mobile navigation bar.

The data foundation includes 26 assets across equities, ETFs, fixed income,
commodities, digital assets and international exposure; three years of
deterministic OHLCV; company/ETF fundamentals; a macro backdrop; and seeded news
sentiment. Every line is generated locally and feeds the research terminal or the
forecast model's context tilt.

Everything is computed locally. Portfolio, alerts and theme are stored in
`localStorage`; clearing site data resets them.

## Architecture

```text
web/
  index.html               App shell and all tab markup
  styles.css               Responsive dark/light theme
  manifest.webmanifest     PWA metadata and icons
  sw.js                    Offline precache (all modules)
  js/core/                 Pure, testable modules (usable in Node)
    math.js                Statistics, PRNG, Cholesky, simplex projection
    indicators.js          SMA/EMA/RMA/RSI/MACD/ATR/Bollinger/Donchian/…
    analytics.js           CAGR, Sharpe, Sortino, drawdown, VaR, trade stats
    marketdata.js          Deterministic OHLCV, fundamentals, macro, news, quality
    risk.js                Covariance, contributions, Monte Carlo, stress tests
    optimizer.js           Projected-gradient constrained optimizers
    strategies.js          Long/flat signal generators
    backtest.js            Next-open event-driven engine
    screener.js            Cross-sectional ranking and filters
    taxlots.js             Lot ledger and disposal methods
    alerts.js              Rule creation and evaluation
    forecast.js            Feature matrix, ridge/Holt/drift ensemble, walk-forward
  js/ui/
    shared.js              State, formatting, persistence, chart registry
    charts.js              Canvas line/band/scatter chart with tooltips
    dashboard.js           Dashboard view
    research-view.js       Research terminal and data-quality audit
    forecast-view.js       Forecast studio and diagnostics
    backtest-view.js       Backtest form and output
    optimize-view.js       Optimizer and frontier
    risk-view.js           Risk lab
    screener-view.js       Screener table
    portfolio-view.js      Ledger and tax lots
    alerts-view.js         Alert rules/history
    app.js                 Navigation, command palette, ticker, theme, boot
  tests/                   100 unit tests + JSDOM smoke test
```

## Using real market data

Replace `generateCandles` / `marketSnapshot` in `js/core/marketdata.js` with a
provider such as Polygon, Finnhub, Alpha Vantage, Yahoo Finance or your own
backend. Keep the candle shape:

```js
{ date: Date, dateString: 'YYYY-MM-DD', open, high, low, close, volume }
```

The rest of the app consumes that shape and does not require changes. For
production, add a server-side proxy so API keys never reach the browser.

## Limitations

- Bundled prices, fundamentals, macro values and headlines are synthetic and
  deterministic. They are not live quotes or real research.
- Forecast intervals are model-based and assume the recent return distribution
  is informative. They cannot anticipate regime breaks, gaps or corporate events.
- Tax-lot comparison is illustrative and ignores jurisdiction-specific rules,
  wash sales and short/long-term rates.
- Stress scenarios are static, illustrative sector shocks.
- Backtests use one position at a time and do not model borrow, dividends,
  corporate actions or market impact.
- Nothing here is investment advice.
