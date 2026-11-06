import test from 'node:test';
import assert from 'node:assert/strict';
import {
  equityFromReturns, returnsFromEquity, drawdownSeries, maxDrawdown,
  analyzeReturns, tradingMetrics,
} from '../js/core/analytics.js';

test('equity and returns round-trip', () => {
  const returns = [0.1, -0.05, 0.02];
  const equity = equityFromReturns(returns, 100);
  const expected = [100, 110, 104.5, 106.59];
  equity.forEach((value, i) => assert.ok(Math.abs(value - expected[i]) < 1e-9));
  const back = returnsFromEquity(equity);
  back.forEach((value, i) => assert.ok(Math.abs(value - returns[i]) < 1e-12));
});

test('drawdown series is non-positive and identifies the trough', () => {
  const drawdown = drawdownSeries([100, 120, 90, 110]);
  assert.deepEqual(drawdown, [0, 0, -0.25, -0.08333333333333337]);
  assert.equal(maxDrawdown([100, 120, 90, 110]), -0.25);
});

test('analyzeReturns computes core statistics', () => {
  const returns = [0.01, -0.02, 0.03, 0.005, -0.01, 0.02];
  const metrics = analyzeReturns(returns, { periodsPerYear: 252, riskFree: 0.02 });
  assert.equal(metrics.observations, 6);
  assert.ok(metrics.totalReturn > 0);
  assert.ok(metrics.volatility > 0);
  assert.ok(Number.isFinite(metrics.sharpe));
  assert.ok(metrics.var95 >= 0);
  assert.ok(metrics.cvar95 >= metrics.var95 - 1e-12);
  assert.equal(metrics.positiveDays, 4);
  assert.equal(metrics.negativeDays, 2);
  assert.ok(Math.abs(metrics.winRate - 4 / 6) < 1e-12);
});

test('empty returns produce a safe zeroed result', () => {
  const metrics = analyzeReturns([]);
  assert.equal(metrics.totalReturn, 0);
  assert.equal(metrics.sharpe, 0);
  assert.deepEqual(metrics.equity, [1]);
});

test('trading metrics only counts closed sells', () => {
  const trades = [
    { side: 'BUY', pnl: 999 },
    { side: 'SELL', pnl: 100 },
    { side: 'SELL', pnl: -50 },
    { side: 'SELL', pnl: 25 },
  ];
  const stats = tradingMetrics(trades);
  assert.equal(stats.trades, 3);
  assert.equal(stats.wins, 2);
  assert.equal(stats.losses, 1);
  assert.ok(Math.abs(stats.winRate - 2 / 3) < 1e-12);
  assert.ok(Math.abs(stats.profitFactor - 2.5) < 1e-12);
});
