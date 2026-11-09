import test from 'node:test';
import assert from 'node:assert/strict';
import worker, { handleApi } from '../src/index.js';
import { buildForecastPayload, buildSnapshot, buildSymbol, resolveSymbols } from '../src/market.js';

test('health endpoint reports a live Worker runtime', async () => {
  const request = new Request('https://investor-kit.example/api/health');
  const response = await handleApi(request, {}, new URL(request.url));
  assert.equal(response.status, 200);
  const payload = await response.json();
  assert.equal(payload.ok, true);
  assert.equal(payload.live, true);
  assert.equal(payload.runtime, 'cloudflare-workers');
  assert.ok(payload.assets >= 24);
  assert.ok(payload.providers.includes('coinbase'));
  assert.ok(payload.providers.includes('fred'));
});

test('sources endpoint lists active, optional and unavailable providers', async () => {
  const request = new Request('https://investor-kit.example/api/sources');
  const response = await handleApi(request, {}, new URL(request.url));
  assert.equal(response.status, 200);
  const payload = await response.json();
  const ids = payload.providers.map((provider) => provider.id);
  assert.ok(ids.includes('coinbase'));
  assert.ok(ids.includes('coingecko'));
  assert.ok(ids.includes('defillama'));
  assert.ok(ids.includes('fred'));
  assert.ok(ids.includes('yahoo'));
  assert.ok(ids.includes('bloomberg'));
  assert.ok(ids.includes('investing'));
  assert.ok(ids.includes('tradersunion'));
  assert.equal(payload.providers.find((provider) => provider.id === 'bloomberg').status, 'unavailable');
});

test('universe endpoint returns the tradable demo universe', async () => {
  const request = new Request('https://investor-kit.example/api/universe');
  const response = await handleApi(request, {}, new URL(request.url));
  assert.equal(response.status, 200);
  const payload = await response.json();
  assert.ok(payload.symbols.includes('SPY'));
  assert.ok(payload.symbols.includes('BTC-USD'));
  assert.equal(payload.assets.length, payload.symbols.length);
});

test('worker routes unsupported methods and missing assets safely', async () => {
  const post = new Request('https://investor-kit.example/api/health', { method: 'POST' });
  const postResponse = await handleApi(post, {}, new URL(post.url));
  assert.equal(postResponse.status, 405);

  const unknown = new Request('https://investor-kit.example/api/nope');
  const unknownResponse = await handleApi(unknown, {}, new URL(unknown.url));
  assert.equal(unknownResponse.status, 404);

  const staticResponse = await worker.fetch(new Request('https://investor-kit.example/'), {});
  assert.equal(staticResponse.status, 500);
  assert.match(await staticResponse.text(), /assets binding/i);
});

test('symbol resolution accepts arbitrary tickers, deduplicates and rejects unsafe values', () => {
  const symbols = resolveSymbols('spy,SPY,AAPL,NOT_A_REAL_TICKER,bad symbol,ETH-USD,^GSPC');
  assert.deepEqual(symbols, ['SPY', 'AAPL', 'NOT_A_REAL_TICKER', 'ETH-USD', '^GSPC']);
});

test('snapshot bypasses per-symbol cache calls to stay under the free subrequest limit', async () => {
  const originalFetch = globalThis.fetch;
  const originalCaches = globalThis.caches;
  let cacheCalls = 0;
  let fetchCalls = 0;
  const timestamps = [1_700_000_000, 1_700_086_400, 1_700_172_800];
  const payload = {
    chart: { result: [{
      meta: { symbol: 'SPY', currency: 'USD', regularMarketPrice: 103 },
      timestamp: timestamps,
      indicators: { quote: [{ open: [100, 101, 102], high: [102, 104, 105], low: [99, 100, 101], close: [101, 103, 104], volume: [1, 2, 3] }] },
    }] },
  };
  globalThis.caches = {
    default: {
      match: async () => { cacheCalls += 1; return undefined; },
      put: async () => { cacheCalls += 1; },
    },
  };
  globalThis.fetch = async () => {
    fetchCalls += 1;
    return new Response(JSON.stringify(payload), { status: 200, headers: { 'content-type': 'application/json' } });
  };
  try {
    const snapshot = await buildSnapshot(['SPY', 'QQQ'], { range: '1mo' });
    assert.equal(snapshot.ok, true);
    assert.equal(fetchCalls, 2);
    assert.equal(cacheCalls, 0);
  } finally {
    globalThis.fetch = originalFetch;
    globalThis.caches = originalCaches;
  }
});

test('crypto symbols prefer Coinbase and fall back to CoinGecko', async () => {
  const originalFetch = globalThis.fetch;
  const rows = [
    [1_700_172_800, 102, 106, 103, 105, 1200],
    [1_700_086_400, 100, 104, 101, 103, 1000],
  ];
  globalThis.fetch = async (input) => {
    const url = String(input);
    if (url.includes('api.exchange.coinbase.com')) {
      return new Response(JSON.stringify(rows), { status: 200, headers: { 'content-type': 'application/json' } });
    }
    if (url.includes('api.coingecko.com')) {
      return new Response(JSON.stringify({
        prices: [[1_700_000_000_000, 100], [1_700_086_400_000, 105]],
        total_volumes: [[1_700_000_000_000, 900], [1_700_086_400_000, 1100]],
      }), { status: 200, headers: { 'content-type': 'application/json' } });
    }
    throw new Error(`unexpected URL ${url}`);
  };
  try {
    const coinbase = await buildSymbol('BTC-USD', { range: '1mo' });
    assert.equal(coinbase.source, 'coinbase');
    assert.equal(coinbase.provider, 'Coinbase Exchange (server-side)');
    assert.equal(coinbase.quality.synthetic, false);

    globalThis.fetch = async (input) => {
      const url = String(input);
      if (url.includes('api.exchange.coinbase.com')) throw new Error('Coinbase unavailable');
      if (url.includes('api.coingecko.com')) {
        return new Response(JSON.stringify({
          prices: [[1_700_000_000_000, 100], [1_700_086_400_000, 105]],
          total_volumes: [[1_700_000_000_000, 900], [1_700_086_400_000, 1100]],
        }), { status: 200, headers: { 'content-type': 'application/json' } });
      }
      throw new Error(`unexpected URL ${url}`);
    };
    const coingecko = await buildSymbol('BTC-USD', { range: '1mo' });
    assert.equal(coingecko.source, 'coingecko');
    assert.equal(coingecko.provider, 'CoinGecko (server-side)');
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('snapshot falls back to deterministic data when Yahoo is unavailable', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => { throw new Error('network disabled in test'); };
  try {
    const snapshot = await buildSnapshot(['SPY', 'AAPL'], { range: '1y' });
    assert.equal(snapshot.ok, true);
    assert.equal(snapshot.source, 'synthetic');
    assert.equal(snapshot.sources.SPY, 'synthetic');
    assert.ok(snapshot.candleMap.SPY.length >= 252);
    assert.ok(snapshot.quotes.SPY.price > 0);
    assert.ok(snapshot.warnings.some((warning) => warning.includes('network disabled')));
    assert.equal(Object.keys(snapshot.fundamentals).length, 2);
    assert.equal(Object.keys(snapshot.news).length, 2);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('server-side forecast runs on fallback data when upstream is unavailable', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => { throw new Error('network disabled in test'); };
  try {
    const payload = await buildForecastPayload('SPY', {
      horizon: 5,
      simulations: 200,
      history: 120,
      seed: 7,
      mode: 'ensemble',
    });
    assert.equal(payload.ok, true);
    assert.equal(payload.server, true);
    assert.equal(payload.source, 'synthetic');
    assert.equal(payload.symbol, 'SPY');
    assert.equal(payload.forecast.symbol, 'SPY');
    assert.equal(payload.forecast.horizon, 5);
    assert.equal(payload.forecast.simulation.simulations, 200);
    assert.ok(payload.forecast.median.length >= 5);
    assert.ok(payload.quality.rows >= 252);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
