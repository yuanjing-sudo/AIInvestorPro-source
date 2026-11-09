# InvestorKit Pro — Cloudflare Worker

This directory turns InvestorKit Pro from a purely static PWA into an optional
dynamic, server-side deployment on **Cloudflare Workers**. One Worker serves the
existing `web/` app shell through Cloudflare's static-assets binding and exposes
a small JSON API for live market data, macro proxies, server-side forecasts and
generative AI analysis through the free Cloudflare Workers AI binding.

The static GitHub Pages deployment still works unchanged. The browser calls
`/api/health` on boot; if it is unavailable, every view keeps using the
deterministic local feed.

## What is dynamic

| Endpoint | Purpose | Cache |
| --- | --- | --- |
| `GET /api/health` | Runtime/version probe used by the client | 30s |
| `GET /api/sources` | Provider catalog: active, optional and unavailable sources | 1h |
| `GET /api/search?q=apple` | Yahoo Finance symbol search for equities, ETFs, indices, futures, FX and crypto | 5m |
| `GET /api/universe` | The 26-asset default research universe | 1h |
| `GET /api/market?symbols=SPY,QQQ&range=2y` | Snapshot of candles, quotes, fundamentals, news, quality and macro | 60s |
| `GET /api/quote/SPY?range=2y` | One asset with OHLCV, profile, fundamentals, sentiment and quality | 60s |
| `GET /api/forecast/SPY?horizon=21&simulations=2000&seed=7` | Runs the shared forecast ensemble on the server | 120s |
| `GET /api/macro` | FRED yields/CPI/unemployment/GDP plus VIX, dollar, oil and gold proxies | 300s |
| `GET /api/ai/status` | AI provider, model registry and binding status | 60s |
| `POST /api/ai/chat` | Grounded chat with the selected asset context | none |
| `POST /api/ai/analysis/:symbol` | Generative structured research brief for one asset | none |
| `POST /api/ai/insights/:symbol` | 12 technical indicators, trend/levels/sentiment, 21-day simulation and generative interpretation | none |

The Worker imports the same `web/js/core/forecast.js`, `marketdata.js`,
`indicators.js` and related modules used by the browser. There is no second
implementation of the numerical engine.

### Data flow

1. The Worker validates the symbol's character set and accepts arbitrary Yahoo
   Finance tickers. The 26-asset list is only the default snapshot universe; a
   symbol loaded from `/api/search` is resolved on demand.
2. Equities and ETFs request Yahoo Finance's public chart endpoint. Crypto
   symbols try Coinbase first, then CoinGecko, DefiLlama, Yahoo and finally the
   deterministic feed. Macro requests use FRED CSV series plus Yahoo proxies.
3. If a provider is unavailable or rate-limits the request, the next provider in
   the chain is tried. A symbol only becomes `source: "synthetic"` after every
   provider fails; responses report `source: "live"`, `"mixed"` or `"synthetic"`
   plus per-symbol warnings.
4. The browser hydrates its shared market objects, re-renders every view and
   shows a **Live · N sources** badge with the provider names in the sidebar.
   The service worker never caches `/api/*`.
5. The **AI Analyst** tab calls the Worker's AI routes. The Worker builds a
   compact context from the same symbol payload and sends it to Cloudflare
   Workers AI. The technical scan also computes 12 deterministic indicators and
   a 21-day simulation before asking the model to interpret them. The browser
   never receives an API key or calls a model directly.

No API key is required for the default chain. Yahoo is an unofficial endpoint:
it may be delayed, rate-limited or changed by Yahoo. Coinbase, CoinGecko,
DefiLlama and FRED are public endpoints with their own rate limits. Do not use
any of this data for trading decisions.

### Data sources

| Provider | Used for | Status | Notes |
| --- | --- | --- | --- |
| Coinbase Exchange | Crypto OHLCV | Active, primary | Public candles; long ranges use 300-candle chunks |
| CoinGecko | Crypto closes/volume | Active, fallback | Free public API limited to 365 days per request |
| DefiLlama | Crypto closes, DeFi coverage | Active, fallback | Up to 500 daily points per request |
| FRED (St. Louis Fed) | Treasury yields, CPI, unemployment, real GDP | Active, primary | Public CSV endpoint; no key |
| Yahoo Finance | Equities, ETFs, crypto and macro proxies | Active, primary/fallback | Unofficial public chart endpoint |
| CoinCap | Crypto | Optional | Public v2 host is retired; v3 needs `COINCAP_API_KEY` |
| CoinMarketCap | Crypto | Optional | Historical OHLCV needs `COINMARKETCAP_API_KEY` |
| Bloomberg | All | Not integrated | Requires a licensed Terminal/API subscription |
| Investing.com | All | Not integrated | No official public API; scraping is blocked by their terms |
| Traders Union | Broker data | Not integrated | Broker-review directory, not a market-data API |
| Stooq | Equities/ETFs | Not integrated | CSV endpoint sits behind a JavaScript browser challenge |

The live catalog is also returned by `GET /api/sources`, including the reason a
provider is optional or unavailable. `providerBreakdown` in `/api/market` shows
how many symbols each provider served.

### Generative AI provider

| Provider | Used for | Status | Notes |
| --- | --- | --- | --- |
| Cloudflare Workers AI | Grounded research briefs and chat | Active | Native `AI` binding; free daily allocation; no browser API key |
| `@cf/meta/llama-3.3-70b-instruct-fp8-fast` | Primary generative model | Active | 70B open-weights model; 24k-token context |
| `@cf/meta/llama-3.1-8b-instruct-fp8-fast` | Fallback | Active | Used automatically if the primary model fails |
| `@cf/qwen/qwen3-30b-a3b-fp8` | Last-resort fallback | Active | Smaller/faster model for degraded service |

The AI layer is in [`src/ai.js`](src/ai.js). It:

* validates and caps chat messages (16 messages, 4,000 characters each);
* builds analysis/chat/insight prompts from a compact server-side market context;
* computes RSI, MACD, ATR, Bollinger, stochastic, Williams %R, ROC, VWAP, OBV,
  Aroon, volume ratio and realized volatility for `/api/ai/insights/:symbol`;
* asks the model for JSON and normalizes/validates the response;
* tries the primary, fallback and fast models in order;
* returns provider/model metadata and keeps all model calls server-side.

The free Workers AI allocation is 10,000 Neurons/day on the Free plan. A typical
analysis or chat turn uses a small fraction of that. The free allocation can
change; check the Cloudflare dashboard. AI output is educational, can be wrong
and is not personalized investment advice.

## Local development

```bash
cd worker
npm install
npx wrangler dev
```

`wrangler dev` runs the Worker, API and static assets locally, usually at
`http://localhost:8787/`. The first request to a symbol may take a few seconds
while upstream providers are queried; subsequent requests are edge-cached.

Run the Worker unit tests without Wrangler:

```bash
cd worker
npm test
```

They cover symbol validation, Yahoo search parsing, Yahoo/Coinbase/CoinGecko/
DefiLlama/FRED parsing, optional keyed providers, routing, the asset binding
fallback, provider selection, the deterministic fallback when upstream is
unreachable, AI status/chat/analysis/insights, JSON parsing, model fallback and
message validation.

## Deploy

### Manual

```bash
cd worker
npx wrangler login
npx wrangler deploy
```

Wrangler prints the `*.workers.dev` URL. Put a custom domain on the Worker from
the Cloudflare dashboard if desired. The default sources need no environment
variables. Optional keyed providers can be enabled with Wrangler secrets:

```bash
npx wrangler secret put COINCAP_API_KEY
npx wrangler secret put COINMARKETCAP_API_KEY
```

### GitHub Actions

The workflow at `.github/workflows/cloudflare.yml` validates every push to
`main` and deploys when these repository secrets exist:

| Secret | Permission needed |
| --- | --- |
| `CLOUDFLARE_API_TOKEN` | Account → Workers Scripts → Edit |
| `CLOUDFLARE_ACCOUNT_ID` | Found on the Cloudflare dashboard overview |

Add them under **Settings → Secrets and variables → Actions**. Until they are
configured, the workflow runs the tests and skips the deploy step with a notice;
the existing GitHub Pages deployment remains live.

### Configuration

`wrangler.jsonc`:

```jsonc
{
  "name": "investor-kit-pro",
  "main": "src/index.js",
  "compatibility_date": "2026-11-01",
  "assets": {
    "directory": "../web",
    "binding": "ASSETS",
    "not_found_handling": "single-page-application",
    "run_worker_first": ["/api/*"]
  },
  "ai": {
    "binding": "AI"
  }
}
```

The `ai` binding is what makes Workers AI free and keyless inside the Worker.
The account must have Workers AI available; no extra secret is required. The
deploy token needs normal Workers Scripts edit permission, and the Cloudflare
account must be allowed to use Workers AI.

`run_worker_first: ["/api/*"]` sends API requests through the Worker before the
SPA fallback, while ordinary asset requests are served directly by Cloudflare
without a Worker invocation. Non-API requests that reach the Worker are passed
to `env.ASSETS.fetch(request)`.

Optional secrets:

| Secret | Effect |
| --- | --- |
| `COINCAP_API_KEY` | Enables the CoinCap v3 fallback for crypto |
| `COINMARKETCAP_API_KEY` | Enables the CoinMarketCap historical OHLCV fallback |

## Operational notes

- The full 26-symbol, two-year snapshot is about 2 MB of JSON uncompressed.
  Cloudflare compresses responses on the wire. Use `range=1y` or request fewer
  symbols if you need a smaller payload.
- A free Workers plan allows 50 subrequests per invocation. The full 26-symbol
  snapshot uses 25 Yahoo fetches plus two Coinbase chunks for BTC-USD at the
  default two-year range (27 total) and deliberately bypasses the per-symbol
  edge-cache calls, which also count toward that budget. Individual quote,
  forecast and macro requests still use the edge cache.
- Crypto forecast requests can use up to four Coinbase chunks for a three-year
  range. That is still well inside the free-plan budget for one symbol.
- `GET /api/sources` reports which market-data providers are active, optional or
  unavailable. Bloomberg, Investing.com and Traders Union are intentionally not
  scraped.
- `GET /api/ai/status` reports whether the Workers AI binding is configured.
  The AI routes are stateless: conversations are not stored by the Worker. The
  client keeps the current chat in memory only.
- Workers AI has a free daily Neuron allocation. If it is exhausted or the
  binding is missing, AI routes return a clear error and the rest of the app
  continues to work with deterministic analytics.
- Market endpoints accept `GET`; AI chat/analysis accept `POST`; `OPTIONS` is
  handled for CORS. CORS is open for read-only market use and stateless AI calls;
  add authentication and per-user rate limiting before exposing private data,
  storing conversations or adding write operations.
- The API is read-only and holds no user portfolio data. Portfolio, alerts and
  theme remain in the browser's `localStorage`.
- Yahoo is unofficial. For production, put a licensed data provider behind the
  same `buildSnapshot` / `buildSymbol` boundary. CoinGecko/DefiLlama windows are
  shorter than Yahoo's, so long crypto forecasts may use fewer bars.
- `web/.assetsignore` keeps tests, scripts and package metadata out of the public
  asset set. Wrangler publishes only the app shell and static modules.
