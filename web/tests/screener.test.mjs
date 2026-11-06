import test from 'node:test';
import assert from 'node:assert/strict';
import { screenUniverse, portfolioSignals, DEFAULT_FILTERS } from '../js/core/screener.js';
import { generateCandles, UNIVERSE } from '../js/core/marketdata.js';

function fixture() {
  const candleMap = {};
  for (const symbol of ['AAPL', 'MSFT', 'JPM', 'XOM', 'GLD']) {
    candleMap[symbol] = generateCandles(symbol, { count: 260, endDate: '2024-12-31' }).candles;
  }
  return candleMap;
}

test('screener returns scored rows sorted descending', () => {
  const rows = screenUniverse(fixture(), UNIVERSE);
  assert.ok(rows.length >= 5);
  for (let i = 1; i < rows.length; i += 1) {
    assert.ok(rows[i - 1].score >= rows[i].score);
  }
  rows.forEach((row) => {
    assert.ok(row.symbol);
    assert.ok(Number.isFinite(row.price));
    assert.ok(Number.isFinite(row.rsi));
    assert.ok(row.score >= 0 && row.score <= 1);
  });
});

test('sector filter is respected', () => {
  const rows = screenUniverse(fixture(), UNIVERSE, { sectors: ['Financials'] });
  assert.ok(rows.length >= 1);
  rows.forEach((row) => assert.equal(row.sector, 'Financials'));
});

test('price and momentum filters remove rows', () => {
  const all = screenUniverse(fixture(), UNIVERSE);
  const filtered = screenUniverse(fixture(), UNIVERSE, { minPrice: 200 });
  assert.ok(filtered.length < all.length);
  filtered.forEach((row) => assert.ok(row.price >= 200));

  const momentum = screenUniverse(fixture(), UNIVERSE, { minMomentum: 0 });
  momentum.forEach((row) => assert.ok(row.momentum >= 0));
});

test('trend-only filter requires SMA20 above SMA50', () => {
  const rows = screenUniverse(fixture(), UNIVERSE, { trendOnly: true });
  rows.forEach((row) => assert.equal(row.trend, true));
});

test('sorting by RSI is ascending', () => {
  const rows = screenUniverse(fixture(), UNIVERSE, { sortBy: 'rsi' });
  for (let i = 1; i < rows.length; i += 1) {
    assert.ok((rows[i - 1].rsi ?? 50) <= (rows[i].rsi ?? 50) + 1e-9);
  }
});

test('default filters are permissive', () => {
  assert.deepEqual(DEFAULT_FILTERS.sectors, []);
  assert.equal(DEFAULT_FILTERS.minPrice, 0);
  assert.equal(DEFAULT_FILTERS.maxRsi, 100);
});

test('portfolio signals produce labels and scores', () => {
  const candleMap = fixture();
  const signals = portfolioSignals(candleMap, ['AAPL', 'MSFT', 'JPM']);
  assert.equal(signals.length, 3);
  signals.forEach((signal) => {
    assert.ok(signal.score >= 0 && signal.score <= 1);
    assert.ok(['Accumulate', 'Neutral', 'Defensive'].includes(signal.label));
  });
});
