import test from 'node:test';
import assert from 'node:assert/strict';
import { runBacktest, benchmarkCurve } from '../js/core/backtest.js';
import { generateSignals, STRATEGIES, defaultParams } from '../js/core/strategies.js';
import { generateCandles } from '../js/core/marketdata.js';

function makeCandles(closes, start = 100) {
  return closes.map((close, index) => {
    const date = new Date(Date.UTC(2024, 0, 1 + index));
    const previous = index === 0 ? start : closes[index - 1];
    return {
      date,
      dateString: date.toISOString().slice(0, 10),
      open: previous,
      high: Math.max(previous, close) + 1,
      low: Math.min(previous, close) - 1,
      close,
      volume: 1000 + index,
    };
  });
}

test('buy and hold enters at the next open and reports a trade', () => {
  const candles = makeCandles([100, 102, 104, 106, 108]);
  const signals = new Array(candles.length).fill(1);
  const result = runBacktest(candles, signals, {
    initialCapital: 10000, commissionBps: 0, slippageBps: 0,
  });
  assert.equal(result.trades.length, 1);
  assert.equal(result.trades[0].side, 'SELL');
  assert.equal(result.trades[0].entryIndex, 1);
  assert.equal(result.trades[0].exitIndex, 4);
  assert.ok(result.finalValue > 10000);
  assert.ok(result.totalReturn > 0);
  assert.equal(result.timeInMarket, 0.8);
  assert.ok(result.benchmark.length === candles.length);
});

test('a signal on the final bar cannot be executed (no lookahead)', () => {
  const candles = makeCandles([100, 101, 102, 103]);
  const signals = [0, 0, 0, 1];
  const result = runBacktest(candles, signals, { commissionBps: 0, slippageBps: 0 });
  assert.equal(result.trades.length, 0);
  assert.equal(result.finalValue, result.initialCapital);
});

test('flat signals preserve capital after costs', () => {
  const candles = makeCandles([100, 99, 98, 97]);
  const result = runBacktest(candles, new Array(candles.length).fill(0));
  assert.equal(result.trades.length, 0);
  assert.equal(result.finalValue, result.initialCapital);
  assert.equal(result.totalReturn, 0);
});

test('entry and exit costs reduce the captured move', () => {
  const candles = makeCandles([100, 110, 120, 130]);
  const signals = new Array(candles.length).fill(1);
  const free = runBacktest(candles, signals, { commissionBps: 0, slippageBps: 0 });
  const costly = runBacktest(candles, signals, { commissionBps: 20, slippageBps: 10 });
  assert.ok(costly.finalValue < free.finalValue);
  assert.ok(costly.totalCommission > 0);
});

test('commission is accounted for in trade pnl', () => {
  const candles = makeCandles([100, 100, 100, 100]);
  const signals = [1, 1, 0, 0];
  const result = runBacktest(candles, signals, { commissionBps: 10, slippageBps: 0 });
  assert.equal(result.trades.length, 1);
  assert.ok(result.trades[0].pnl < 0);
  assert.ok(result.totalCommission > 0);
});

test('benchmark curve tracks a buy and hold position', () => {
  const candles = makeCandles([100, 110, 120]);
  const benchmark = benchmarkCurve(candles, 10000, 0, 0);
  assert.equal(benchmark.equity.length, 3);
  assert.ok(benchmark.equity[2] > benchmark.equity[0]);
  assert.ok(benchmark.metrics.totalReturn > 0);
});

test('all strategies generate aligned, finite signals', () => {
  const { candles } = generateCandles('AAPL', { count: 320, endDate: '2024-12-31' });
  for (const strategy of STRATEGIES) {
    const params = defaultParams(strategy.id);
    const signals = generateSignals(strategy.id, candles, params);
    assert.equal(signals.length, candles.length, strategy.id);
    signals.forEach((value) => assert.ok(value === 0 || value === 1, strategy.id));
    const result = runBacktest(candles, signals, { initialCapital: 50000 });
    assert.ok(Number.isFinite(result.finalValue), strategy.id);
    assert.ok(Number.isFinite(result.sharpe), strategy.id);
    assert.ok(result.maxDrawdown <= 0, strategy.id);
  }
});

test('strategy warm-up leaves early signals flat except buy and hold', () => {
  const { candles } = generateCandles('MSFT', { count: 100, endDate: '2024-12-31' });
  const signals = generateSignals('smaCross', candles, { fast: 20, slow: 50 });
  assert.equal(signals[0], 0);
  assert.equal(signals[48], 0);
});
