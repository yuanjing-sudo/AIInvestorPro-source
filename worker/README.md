# InvestorKit Pro — Cloudflare Worker

This directory turns InvestorKit Pro from a purely static PWA into an optional
dynamic, server-side deployment on **Cloudflare Workers**. One Worker serves the
existing `web/` app shell through Cloudflare's static-assets binding and exposes
a small JSON API for live market data, macro proxies and server-side forecasts.

The static GitHub Pages deployment still works unchanged. The browser calls
`/api/health` on boot; if it is unavailable, every view keeps using the
deterministic local feed.

## What is dynamic

| Endpoint | Purpose | Cache |
| --- | --- | --- |
| `GET /api/health` | Runtime/version probe used by the client | 30s |
| `GET /api/universe` | The 26-asset research universe | 1h |
| `GET /api/market?symbols=SPY,QQQ&range=2y` | Snapshot of candles, quotes, fundamentals, news, quality and macro | 60s |
| `GET /api/quote/SPY?range=2y` | One asset with OHLCV, profile, fundamentals, sentiment and quality | 60s |
| `GET /api/forecast/SPY?horizon=21&simulations=2000&seed=7` | Runs the shared forecast ensemble on the server | 120s |
| `GET /api/macro` | VIX, 10y/13-week yields, curve, dollar index, oil and gold proxies | 300s |

The Worker imports the same `web/js/core/forecast.js`, `marketdata.js`,
`indicators.js` and related modules used by the browser. There is no second
implementation of the numerical engine.

### Data flow

1. The Worker validates the symbol against the 26-asset allowlist.
2. It requests Yahoo Finance's public chart endpoint server-side, with a
   five-minute edge cache.
3. If Yahoo is unavailable or rate-limits the request, that symbol falls back to
   the deterministic synthetic feed and the response reports
   `source: "mixed"` or `"synthetic"` plus per-symbol warnings.
4. The browser hydrates its shared market objects, re-renders every view and
   shows a **Live · Yahoo** badge. The service worker never caches `/api/*`.

No API key or account is required for the Yahoo chart endpoint. It is an
unofficial endpoint: it may be delayed, rate-limited or changed by Yahoo. Do not
use it for trading decisions.

## Local development

```bash
cd worker
npm install
npx wrangler dev
```

`wrangler dev` runs the Worker, API and static assets locally, usually at
`http://localhost:8787/`. The first request to a symbol may take a few seconds
while Yahoo is queried; subsequent requests are edge-cached.

Run the Worker unit tests without Wrangler:

```bash
cd worker
npm test
```

They cover symbol validation, chart parsing, routing, the asset binding fallback
and the deterministic fallback when upstream is unreachable.

## Deploy

### Manual

```bash
cd worker
npx wrangler login
npx wrangler deploy
```

Wrangler prints the `*.workers.dev` URL. Put a custom domain on the Worker from
the Cloudflare dashboard if desired. No environment variables are required.

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
  }
}
```

`run_worker_first: ["/api/*"]` sends API requests through the Worker before the
SPA fallback, while ordinary asset requests are served directly by Cloudflare
without a Worker invocation. Non-API requests that reach the Worker are passed
to `env.ASSETS.fetch(request)`.

## Operational notes

- The full 26-symbol, two-year snapshot is about 2 MB of JSON uncompressed.
  Cloudflare compresses responses on the wire. Use `range=1y` or request fewer
  symbols if you need a smaller payload.
- A free Workers plan allows 50 subrequests per invocation. The full snapshot
  uses 26 Yahoo chart subrequests. `/api/macro` uses 7.
- `GET` and `OPTIONS` are the only accepted methods. CORS is open for read-only
  use; add authentication before exposing private data or write operations.
- The API is read-only and holds no user portfolio data. Portfolio, alerts and
  theme remain in the browser's `localStorage`.
- Yahoo is unofficial. For production, put a licensed data provider behind the
  same `buildSnapshot` / `buildSymbol` boundary.
- `web/.assetsignore` keeps tests, scripts and package metadata out of the public
  asset set. Wrangler publishes only the app shell and static modules.
