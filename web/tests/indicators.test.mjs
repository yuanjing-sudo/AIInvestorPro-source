import test from 'node:test';
import assert from 'node:assert/strict';
import {
  sma, ema, rma, rsi, macd, trueRange, atr, stochastic, williamsR,
  roc, bollinger, donchian, vwap, obv, aroon, latest, summarize,
  adx, mfi, cci, keltner, chaikinMoneyFlow, regressionSlope,
  realizedVolatility, indicatorDetails,
} from '../js/core/indicators.js';
import { generateCandles } from '../js/core/marketdata.js';

test('SMA aligns warm-up with nulls', () => {
  assert.deepEqual(sma([1, 2, 3, 4, 5], 3), [null, null, 2, 3, 4]);
  assert.deepEqual(sma([1, 2], 3), [null, null]);
});

test('EMA seeds with the SMA and applies alpha', () => {
  assert.deepEqual(ema([1, 2, 3, 4, 5], 3), [null, null, 2, 3, 4]);
  const values = ema([1, 2, 3, 4, 5], 2);
  assert.equal(values[0], null);
  assert.equal(values[1], 1.5);
  assert.ok(Math.abs(values[2] - 2.5) < 1e-12);
});

test('RMA uses Wilder smoothing', () => {
  assert.deepEqual(rma([1, 2, 3, 4], 2), [null, 1.5, 2.25, 3.125]);
});

test('RSI returns 100 for a monotonic advance and 0 for decline', () => {
  const up = rsi(Array.from({ length: 20 }, (_, i) => 100 + i), 14);
  const down = rsi(Array.from({ length: 20 }, (_, i) => 100 - i), 14);
  assert.equal(latest(up), 100);
  assert.equal(latest(down), 0);
});

test('ATR uses Wilder smoothing and does not drop a true range', () => {
  const tr = trueRange([10, 11, 12], [9, 10, 11], [9.5, 10.5, 11.5]);
  assert.deepEqual(tr, [1, 1.5, 1.5]);
  assert.deepEqual(atr([10, 11, 12], [9, 10, 11], [9.5, 10.5, 11.5], 2), [null, 1.25, 1.375]);
});

test('MACD series align and produce a histogram', () => {
  const closes = Array.from({ length: 120 }, (_, i) => 100 + Math.sin(i / 7) * 5 + i * 0.1);
  const result = macd(closes, 12, 26, 9);
  assert.equal(result.macd.length, closes.length);
  assert.equal(result.signal.length, closes.length);
  assert.equal(result.histogram.length, closes.length);
  assert.ok(latest(result.macd) !== null);
  assert.ok(latest(result.signal) !== null);
});

test('Bollinger bands collapse for a flat series', () => {
  const values = new Array(30).fill(50);
  const bands = bollinger(values, 20, 2);
  assert.equal(latest(bands.middle), 50);
  assert.equal(latest(bands.upper), 50);
  assert.equal(latest(bands.lower), 50);
});

test('Donchian channel uses the requested lookback', () => {
  const high = [1, 2, 3, 4, 5];
  const low = [0, 1, 2, 3, 4];
  const channel = donchian(high, low, 3);
  assert.equal(channel.upper[2], 3);
  assert.equal(channel.lower[2], 0);
  assert.equal(channel.middle[2], 1.5);
  assert.equal(channel.upper[4], 5);
});

test('ROC handles a simple two-bar return', () => {
  const values = roc([100, 110, 121], 1);
  assert.equal(values[0], null);
  assert.ok(Math.abs(values[1] - 10) < 1e-12);
  assert.ok(Math.abs(values[2] - 10) < 1e-12);
});

test('VWAP weights typical price by volume', () => {
  const high = [10, 10];
  const low = [10, 10];
  const close = [10, 10];
  const volume = [100, 900];
  assert.equal(latest(vwap(high, low, close, volume, 2)), 10);
});

test('OBV accumulates signed volume', () => {
  assert.deepEqual(obv([10, 11, 10, 10], [100, 200, 300, 400]), [0, 200, -100, -100]);
});

test('Aroon is 100 at a fresh high and 0 at the oldest high', () => {
  const rising = aroon([1, 2, 3, 4, 5], [0, 1, 2, 3, 4], 3);
  assert.equal(rising.up[4], 100);
  assert.equal(rising.down[4], 0);
  const falling = aroon([5, 4, 3, 2, 1], [4, 3, 2, 1, 0], 3);
  assert.equal(falling.up[4], 0);
  assert.equal(falling.down[4], 100);
});

test('stochastic and Williams %R stay in range', () => {
  const { candles } = generateCandles('AAPL', { count: 120, endDate: '2024-12-31' });
  const high = candles.map((c) => c.high);
  const low = candles.map((c) => c.low);
  const close = candles.map((c) => c.close);
  const stoch = stochastic(high, low, close);
  const williams = williamsR(high, low, close);
  assert.ok(latest(stoch.k) >= 0 && latest(stoch.k) <= 100);
  assert.ok(latest(williams) >= -100 && latest(williams) <= 0);
});

test('summarize produces finite values on synthetic data', () => {
  const { candles } = generateCandles('MSFT', { count: 260, endDate: '2024-12-31' });
  const summary = summarize(candles);
  for (const key of ['sma20', 'sma50', 'rsi', 'atr', 'macd', 'vwap', 'meanVolume']) {
    assert.ok(Number.isFinite(summary[key]), `${key} should be finite`);
  }
  for (const key of ['adx', 'mfi', 'cci', 'cmf', 'obvSlopePercent', 'regressionSlopePercent', 'volumeTrendPercent', 'realizedVolatility21d']) {
    assert.ok(Number.isFinite(summary[key]), `${key} should be finite`);
  }
  assert.ok(Number.isFinite(summary.bollinger.position));
  assert.ok(Number.isFinite(summary.donchian.position));
  assert.ok(Number.isFinite(summary.keltner.position));
});

test('ADX separates a strong trend from a flat series', () => {
  const rising = Array.from({ length: 80 }, (_, i) => 100 + i);
  const high = rising.map((v) => v + 1);
  const low = rising.map((v) => v - 1);
  const result = adx(high, low, rising, 14);
  assert.ok(latest(result.adx) > 25);
  assert.ok(latest(result.plusDI) > latest(result.minusDI));
  const flat = new Array(80).fill(100);
  assert.ok(latest(adx(flat.map((v) => v + 1), flat.map((v) => v - 1), flat, 14).adx) < 25);
});

test('MFI, CCI, CMF and Keltner return bounded, finite series', () => {
  const { candles } = generateCandles('AAPL', { count: 120, endDate: '2024-12-31' });
  const high = candles.map((c) => c.high);
  const low = candles.map((c) => c.low);
  const close = candles.map((c) => c.close);
  const volume = candles.map((c) => c.volume);
  const flow = latest(mfi(high, low, close, volume));
  assert.ok(flow >= 0 && flow <= 100);
  assert.ok(Number.isFinite(latest(cci(high, low, close))));
  assert.ok(Number.isFinite(latest(chaikinMoneyFlow(high, low, close, volume))));
  const bands = keltner(high, low, close);
  assert.ok(Number.isFinite(latest(bands.upper)));
  assert.ok(Number.isFinite(latest(bands.lower)));
});

test('regression slope and realized volatility are directionally correct', () => {
  const rising = Array.from({ length: 40 }, (_, i) => 100 + i * 2);
  assert.ok(latest(regressionSlope(rising, 20)) > 0);
  const falling = rising.map((value) => 200 - value);
  assert.ok(latest(regressionSlope(falling, 20)) < 0);
  const steady = Array.from({ length: 40 }, (_, i) => 100 * 1.01 ** i);
  assert.ok(realizedVolatility(steady, 21) < 1e-12);
});

test('indicatorDetails exposes values, signals, summaries and readings', () => {
  const { candles } = generateCandles('SPY', { count: 504, endDate: '2026-11-06' });
  const details = indicatorDetails(candles);
  assert.ok(details.length >= 20);
  const rsi = details.find((item) => item.key === 'rsi14');
  assert.ok(rsi);
  assert.match(rsi.summary, /average gains/i);
  assert.match(rsi.reading, /momentum/i);
  for (const item of details) {
    assert.equal(typeof item.label, 'string');
    assert.equal(typeof item.display, 'string');
    assert.equal(typeof item.signal, 'string');
    assert.ok(item.summary.length > 20, `${item.key} should have a summary`);
    assert.ok(item.reading.length > 5, `${item.key} should have a reading`);
  }
});
