import test from 'node:test';
import assert from 'node:assert/strict';
import {
  UNIVERSE, generateCandles, fundamentalsFor, newsFor, sentimentSummary,
  macroSnapshot, dataQuality, performanceWindows, historicalVolatility,
  pricePercentile, marketSnapshot, findAsset,
} from '../js/core/marketdata.js';

const { candles } = generateCandles('AAPL', { count: 756, endDate: '2025-06-30' });

test('the demo universe is broad enough for multi-asset research', () => {
  assert.ok(UNIVERSE.length >= 24);
  assert.equal(findAsset('spy').symbol, 'SPY');
  assert.equal(findAsset('missing'), null);
  const sectors = new Set(UNIVERSE.map((asset) => asset.sector));
  assert.ok(sectors.size >= 10, 'at least ten sectors');
});

test('fundamentals are deterministic and complete for equities', () => {
  const first = fundamentalsFor('AAPL');
  const second = fundamentalsFor('AAPL');
  assert.deepEqual(first, second);
  assert.equal(first.kind, 'equity');
  assert.ok(first.marketCap > 0);
  assert.ok(first.pe > 0);
  assert.ok(first.analystTarget > 0);
  assert.ok(first.employees > 0);
  assert.ok(first.beta > 0);
});

test('ETF and crypto profiles avoid equity-only fields', () => {
  const etf = fundamentalsFor('SPY');
  assert.equal(etf.kind, 'etf');
  assert.equal(etf.pe, null);
  assert.ok(etf.expenseRatio > 0);
  const crypto = fundamentalsFor('BTC-USD');
  assert.equal(crypto.kind, 'crypto');
  assert.equal(crypto.pe, null);
  assert.ok(crypto.marketCap > 0);
});

test('news is seeded and summarisable', () => {
  const items = newsFor('NVDA', new Date('2025-06-30T00:00:00Z'));
  assert.ok(items.length >= 4);
  assert.deepEqual(items, newsFor('NVDA', new Date('2025-06-30T00:00:00Z')));
  assert.ok(items.every((item) => item.headline && item.source && item.symbol === 'NVDA'));
  const summary = sentimentSummary(items);
  assert.ok(summary.positive + summary.negative + summary.neutral === items.length);
  assert.ok(['Bullish', 'Bearish', 'Neutral'].includes(summary.label));
});

test('macro snapshot is data-driven and bounded', () => {
  const macro = macroSnapshot(candles);
  assert.ok(macro.vix >= 9 && macro.vix <= 48);
  assert.ok(['Risk-on', 'Cautious', 'Risk-off'].includes(macro.regime));
  assert.ok(Number.isFinite(macro.yieldCurve));
  assert.ok(macro.asOf instanceof Date);
});

test('data quality catches coverage and completeness', () => {
  const quality = dataQuality(candles);
  assert.equal(quality.rows, 756);
  assert.equal(quality.missing, 0);
  assert.equal(quality.duplicates, 0);
  assert.equal(quality.completeness, 1);
  assert.ok(quality.spanYears > 2.5);
  assert.equal(quality.synthetic, true);
});

test('performance windows and volatility metrics are finite', () => {
  const windows = performanceWindows(candles);
  assert.ok(windows.length >= 8);
  assert.ok(windows.every((row) => Number.isFinite(row.value)));
  assert.ok(Number.isFinite(historicalVolatility(candles, 21)));
  const percentile = pricePercentile(candles, 252);
  assert.ok(percentile >= 0 && percentile <= 1);
});

test('market snapshot includes quotes, fundamentals, news and quality', () => {
  const snapshot = marketSnapshot(120);
  assert.equal(Object.keys(snapshot.candleMap).length, UNIVERSE.length);
  assert.equal(Object.keys(snapshot.fundamentals).length, UNIVERSE.length);
  assert.equal(Object.keys(snapshot.news).length, UNIVERSE.length);
  assert.equal(Object.keys(snapshot.quality).length, UNIVERSE.length);
  assert.ok(snapshot.macro.vix > 0);
  assert.ok(snapshot.quotes.SPY.price > 0);
});

test('candles are deterministic and have valid OHLC relationships', () => {
  const a = generateCandles('MSFT', { count: 260, endDate: '2024-12-31' }).candles;
  const b = generateCandles('MSFT', { count: 260, endDate: '2024-12-31' }).candles;
  assert.deepEqual(a, b);
  for (const candle of a.slice(-20)) {
    assert.ok(candle.high >= Math.max(candle.open, candle.close));
    assert.ok(candle.low <= Math.min(candle.open, candle.close));
    assert.ok(candle.volume > 0);
    assert.ok(candle.vwap > 0);
  }
});
