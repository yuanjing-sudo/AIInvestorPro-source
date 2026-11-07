import test from 'node:test';
import assert from 'node:assert/strict';
import worker, { handleApi } from '../src/index.js';
import { buildForecastPayload, buildSnapshot, resolveSymbols } from '../src/market.js';

test('health endpoint reports a live Worker runtime', async () => {
  const request = new Request('https://investor-kit.example/api/health');
  const response = await handleApi(request, {}, new URL(request.url));
  assert.equal(response.status, 200);
  const payload = await response.json();
  assert.equal(payload.ok, true);
  assert.equal(payload.live, true);
  assert.equal(payload.runtime, 'cloudflare-workers');
  assert.ok(payload.assets >= 24);
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

test('symbol resolution drops unknown and duplicate values', () => {
  const symbols = resolveSymbols('spy,SPY,AAPL,NOT_A_REAL_TICKER');
  assert.deepEqual(symbols, ['SPY', 'AAPL']);
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
