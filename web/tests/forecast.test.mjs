import test from 'node:test';
import assert from 'node:assert/strict';
import { generateCandles } from '../js/core/marketdata.js';
import {
  buildFeatureRows, buildSamples, buildForecast, simulatePaths, detectRegime,
  walkForwardFactor, FEATURE_DEFINITIONS,
} from '../js/core/forecast.js';

const { candles } = generateCandles('SPY', { count: 756, endDate: '2025-06-30' });

test('feature rows are finite and aligned to the feature definitions', () => {
  const rows = buildFeatureRows(candles);
  assert.ok(rows.length > 500);
  for (const row of rows.slice(0, 5)) {
    assert.equal(row.features.length, FEATURE_DEFINITIONS.length);
    assert.ok(row.features.every((value) => Number.isFinite(value)));
    assert.ok(row.close > 0);
  }
});

test('samples label the forward horizon without look-ahead', () => {
  const { samples } = buildSamples(candles, 5);
  assert.ok(samples.length > 400);
  const sample = samples[10];
  assert.ok(Number.isFinite(sample.y));
  assert.ok(sample.index >= 130);
});

test('walk-forward diagnostics report honest out-of-sample metrics', () => {
  const diagnostics = walkForwardFactor(candles, 5, 12);
  assert.ok(diagnostics.observations >= 8);
  assert.ok(diagnostics.mae >= 0);
  assert.ok(diagnostics.rmse >= diagnostics.mae * 0.8);
  assert.ok(diagnostics.directionalAccuracy >= 0 && diagnostics.directionalAccuracy <= 1);
  assert.ok(diagnostics.points.every((point) => Number.isFinite(point.predicted)));
});

test('simulation is reproducible for a fixed seed and orders its bands', () => {
  const first = simulatePaths(100, 0.02, 0.2, 21, { simulations: 500, seed: 11 });
  const second = simulatePaths(100, 0.02, 0.2, 21, { simulations: 500, seed: 11 });
  assert.equal(first.medianTerminal, second.medianTerminal);
  assert.ok(first.bands[50].lower.every((value, index) => value <= first.bands[50].upper[index]));
  assert.ok(first.bands[95].lower.every((value, index) => value <= first.bands[50].lower[index]));
  assert.ok(first.probabilityUp >= 0 && first.probabilityUp <= 1);
  assert.ok(first.var95 >= 0);
});

test('regime detection returns a labelled state', () => {
  const regime = detectRegime(candles);
  assert.ok(typeof regime.label === 'string');
  assert.ok(regime.label.length > 0);
  assert.ok(Number.isFinite(regime.metrics.vol20));
});

test('forecast exposes intervals, scenarios and model weights', () => {
  const forecast = buildForecast(candles, { horizon: 21, simulations: 500, seed: 7 });
  assert.ok(forecast);
  assert.equal(forecast.horizon, 21);
  assert.ok(forecast.expectedPrice > 0);
  assert.ok(forecast.median.at(-1) > 0);
  assert.ok(forecast.bands.length === 3);
  for (const band of forecast.bands) {
    assert.ok(band.lower.every((value, index) => value <= band.upper[index]));
  }
  assert.equal(forecast.scenarios.length, 3);
  assert.equal(forecast.models.length, 3);
  const weights = forecast.models.reduce((acc, model) => acc + model.weight, 0);
  assert.ok(Math.abs(weights - 1) < 1e-9);
  assert.ok(forecast.probabilityUp >= 0 && forecast.probabilityUp <= 1);
  assert.ok(forecast.confidence >= 0 && forecast.confidence <= 100);
  assert.ok(forecast.factorContributions.length > 0);
  assert.ok(forecast.diagnostics.observations > 0);
  assert.equal(forecast.dataRows, 756);
});

test('same inputs and seed produce the same forecast', () => {
  const a = buildForecast(candles, { horizon: 10, simulations: 300, seed: 42 });
  const b = buildForecast(candles, { horizon: 10, simulations: 300, seed: 42 });
  assert.equal(a.expectedPrice, b.expectedPrice);
  assert.equal(a.medianTerminal, b.medianTerminal);
  assert.equal(a.probabilityUp, b.probabilityUp);
});

test('model selection focuses the requested model', () => {
  const factor = buildForecast(candles, { horizon: 10, simulations: 200, seed: 3, mode: 'factor' });
  const selected = factor.models.filter((model) => model.selected);
  assert.equal(selected.length, 1);
  assert.equal(selected[0].key, 'factor');
  assert.equal(selected[0].weight, 1);
});

test('fundamental, macro and sentiment lines tilt the ensemble', () => {
  const without = buildForecast(candles, { horizon: 21, simulations: 200, seed: 9 });
  const withContext = buildForecast(candles, {
    horizon: 21,
    simulations: 200,
    seed: 9,
    context: {
      fundamentals: { analystUpside: 0.4, revenueGrowth: 0.25, profitMargin: 0.3, forwardPE: 24 },
      macro: { vix: 31, yieldCurve: -0.01, liquidity: 'Tightening' },
      sentiment: { score: 0.55 },
    },
  });
  assert.equal(withContext.contextUsed, true);
  assert.ok(withContext.contextBreakdown.length >= 4);
  assert.notEqual(withContext.contextTilt, 0);
  assert.notEqual(withContext.expectedLogReturn, without.expectedLogReturn);
});
