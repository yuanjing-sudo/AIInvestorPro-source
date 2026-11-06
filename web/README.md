# InvestorKit Web

A dependency-free, installable progressive web app (PWA) for portfolio analytics.
It runs the same numerical core as the Swift `InvestorKit` library and is designed
to work on Android, iPhone, iPad, Windows, macOS, Linux, ChromeOS and any modern
browser.

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
npm test                 # 82 numerical/unit tests
npm run test:ui          # drives every tab in a JSDOM browser smoke test
npm run test:all         # both
```

The suite covers indicators, performance statistics, covariance/risk
contributions, Monte Carlo determinism, optimizers, backtesting (including a
no-lookahead check), screening, tax lots, alerts and the precache manifest.

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

Enable **Settings → Pages → Build and deployment → GitHub Actions** if the
repository has not enabled Pages yet.

Any static host works as well: Netlify, Cloudflare Pages, Vercel, S3, nginx or a
USB stick. Upload the contents of `web/` (excluding `tests/`, `scripts/` and
`node_modules/`).

## Features

| Tab | What it does |
| --- | --- |
| Dashboard | Portfolio value/P&L, market table, price chart with SMA 20/50, signal board |
| Backtest | 9 strategies, next-open execution, commission/slippage, equity/drawdown charts, trade log |
| Optimize | Max Sharpe, min variance, risk parity, max diversification, weight cap, efficient frontier |
| Risk | Correlated Monte Carlo with percentile bands, VaR/CVaR, risk decomposition, five stress scenarios |
| Screener | Trend, momentum, RSI, liquidity filters and composite ranking |
| Portfolio | Average cost, unrealized/realized P&L, buy/sell ledger, FIFO/LIFO/HIFO/LOFO tax-lot comparison |
| Alerts | Price, daily change, RSI and volume rules, cooldown, local trigger history |
| Platform | Installation instructions and architecture notes |

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
    marketdata.js          Deterministic synthetic OHLCV; replace for live data
    risk.js                Covariance, contributions, Monte Carlo, stress tests
    optimizer.js           Projected-gradient constrained optimizers
    strategies.js          Long/flat signal generators
    backtest.js            Next-open event-driven engine
    screener.js            Cross-sectional ranking and filters
    taxlots.js             Lot ledger and disposal methods
    alerts.js              Rule creation and evaluation
  js/ui/
    shared.js              State, formatting, persistence, chart registry
    charts.js              Canvas line/band/scatter chart with tooltips
    dashboard.js           Dashboard view
    backtest-view.js       Backtest form and output
    optimize-view.js       Optimizer and frontier
    risk-view.js           Risk lab
    screener-view.js       Screener table
    portfolio-view.js      Ledger and tax lots
    alerts-view.js         Alert rules/history
    app.js                 Navigation, theme, install prompt, boot
  tests/                   82 unit tests + JSDOM smoke test
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

- Bundled prices are synthetic and deterministic. They are not live quotes.
- Tax-lot comparison is illustrative and ignores jurisdiction-specific rules,
  wash sales and short/long-term rates.
- Stress scenarios are static, illustrative sector shocks.
- Backtests use one position at a time and do not model borrow, dividends,
  corporate actions or market impact.
- Nothing here is investment advice.
