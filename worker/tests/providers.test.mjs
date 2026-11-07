import test from 'node:test';
import assert from 'node:assert/strict';
import { fetchCoinbaseChart } from '../src/coinbase.js';
import { fetchCoinGeckoChart } from '../src/coingecko.js';
import { fetchDefiLlamaChart } from '../src/defillama.js';
import { fetchCoinCapChart } from '../src/coincap.js';
import { fetchCoinMarketCapChart } from '../src/coinmarketcap.js';
import { fetchFredSeries, yearOverYear } from '../src/fred.js';
import { dailyCandlesFromCloses } from '../src/candles.js';

function jsonResponse(payload) {
  return new Response(JSON.stringify(payload), {
    status: 200,
    headers: { 'content-type': 'application/json' },
  });
}

async function withFetch(mock, run) {
  const original = globalThis.fetch;
  globalThis.fetch = mock;
  try {
    return await run();
  } finally {
    globalThis.fetch = original;
  }
}

test('Coinbase candles become dated OHLCV candles', async () => {
  const rows = [
    [1_700_172_800, 102, 106, 103, 105, 1200],
    [1_700_086_400, 100, 104, 101, 103, 1000],
  ];
  const chart = await withFetch(
    async () => jsonResponse(rows),
    () => fetchCoinbaseChart('BTC-USD', { range: '1mo', cache: false }),
  );
  assert.equal(chart.candles.length, 2);
  assert.ok(chart.candles[0].date instanceof Date);
  assert.equal(chart.candles[0].close, 103);
  assert.equal(chart.candles[1].close, 105);
  assert.equal(chart.quote.price, 105);
  assert.equal(chart.quote.previousClose, 103);
});

test('CoinGecko close and volume series become candles', async () => {
  const payload = {
    prices: [[1_700_000_000_000, 100], [1_700_086_400_000, 105]],
    total_volumes: [[1_700_000_000_000, 900], [1_700_086_400_000, 1100]],
  };
  const chart = await withFetch(
    async () => jsonResponse(payload),
    () => fetchCoinGeckoChart('BTC-USD', { range: '1mo', cache: false }),
  );
  assert.equal(chart.candles.length, 2);
  assert.equal(chart.candles[0].volume, 900);
  assert.equal(chart.candles[1].close, 105);
  assert.equal(chart.candles[1].high, 105);
  assert.equal(chart.candles[1].low, 105);
});

test('intraday close series are aggregated into one candle per UTC day', () => {
  const day = Date.parse('2023-11-14T00:00:00.000Z');
  const points = [
    [day, 100],
    [day + 3_600_000, 106],
    [day + 7_200_000, 102],
    [day + 86_400_000, 104],
  ];
  const candles = dailyCandlesFromCloses(points);
  assert.equal(candles.length, 2);
  assert.equal(candles[0].open, 100);
  assert.equal(candles[0].high, 106);
  assert.equal(candles[0].low, 100);
  assert.equal(candles[0].close, 102);
});

test('DefiLlama price points become candles', async () => {
  const payload = {
    coins: {
      'coingecko:bitcoin': {
        prices: [
          { timestamp: 1_700_000_000, price: 100 },
          { timestamp: 1_700_086_400, price: 102 },
        ],
      },
    },
  };
  const chart = await withFetch(
    async () => jsonResponse(payload),
    () => fetchDefiLlamaChart('BTC-USD', { range: '1mo', cache: false }),
  );
  assert.equal(chart.candles.length, 2);
  assert.equal(chart.quote.price, 102);
  assert.equal(chart.candles[1].open, 100);
});

test('optional CoinCap adapter requires a key and parses history', async () => {
  await assert.rejects(
    () => fetchCoinCapChart('BTC-USD', { range: '1mo', cache: false }),
    /COINCAP_API_KEY/,
  );
  const payload = {
    data: [
      { time: 1_700_000_000_000, priceUsd: '100.5' },
      { time: 1_700_086_400_000, priceUsd: '103.5' },
    ],
  };
  const chart = await withFetch(
    async () => jsonResponse(payload),
    () => fetchCoinCapChart('BTC-USD', { range: '1mo', cache: false, key: 'test' }),
  );
  assert.equal(chart.candles.length, 2);
  assert.equal(chart.quote.price, 103.5);
});

test('optional CoinMarketCap adapter parses OHLCV quotes', async () => {
  const payload = {
    data: {
      quotes: [{
        time_open: '2026-01-02T00:00:00.000Z',
        quote: { USD: { open: 100, high: 106, low: 99, close: 105, volume: 1234 } },
      }],
    },
  };
  const chart = await withFetch(
    async () => jsonResponse(payload),
    () => fetchCoinMarketCapChart('BTC-USD', { range: '1mo', cache: false, key: 'test' }),
  );
  assert.equal(chart.candles.length, 1);
  assert.equal(chart.candles[0].high, 106);
  assert.equal(chart.candles[0].volume, 1234);
});

test('FRED CSV parsing and year-over-year calculation', async () => {
  const csv = [
    'observation_date,DGS10',
    '2025-01-01,4.00',
    '2025-02-01,.',
    '2026-01-01,4.40',
  ].join('\n');
  const series = await withFetch(
    async () => new Response(csv, { status: 200, headers: { 'content-type': 'text/csv' } }),
    () => fetchFredSeries('DGS10', { cache: false }),
  );
  assert.equal(series.observations.length, 2);
  assert.equal(series.latest.value, 4.4);
  assert.ok(Math.abs(yearOverYear(series) - 0.1) < 1e-9);
});
