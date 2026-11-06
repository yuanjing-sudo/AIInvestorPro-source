import test from 'node:test';
import assert from 'node:assert/strict';
import {
  covarianceMatrix, correlationMatrix, portfolioRisk, parametricVaR,
  beta, monteCarlo, stressTests, annualizedMean,
} from '../js/core/risk.js';
import { generateCandles, returnsFromCandles } from '../js/core/marketdata.js';

function sampleReturns() {
  return {
    AAA: [0.01, 0.02, -0.01, 0.03, 0.00, -0.02, 0.015, 0.01],
    BBB: [-0.01, 0.005, 0.02, 0.01, -0.005, 0.01, 0.00, 0.02],
    CCC: [0.02, -0.01, 0.015, -0.005, 0.01, 0.005, -0.01, 0.03],
  };
}

test('covariance matrix is symmetric and annualizes', () => {
  const returns = sampleReturns();
  const matrix = covarianceMatrix(returns, ['AAA', 'BBB', 'CCC']);
  for (let i = 0; i < 3; i += 1) {
    for (let j = 0; j < 3; j += 1) {
      assert.ok(Math.abs(matrix[i][j] - matrix[j][i]) < 1e-12);
    }
    assert.ok(matrix[i][i] > 0);
  }
  const daily = covarianceMatrix(returns, ['AAA', 'BBB', 'CCC'], false);
  assert.ok(Math.abs(matrix[0][0] / daily[0][0] - 252) < 1e-9);
});

test('correlation matrix has ones on the diagonal', () => {
  const matrix = correlationMatrix(sampleReturns(), ['AAA', 'BBB', 'CCC']);
  matrix.forEach((row, i) => assert.ok(Math.abs(row[i] - 1) < 1e-12));
});

test('portfolio risk contributions sum to 100%', () => {
  const returns = sampleReturns();
  const symbols = ['AAA', 'BBB', 'CCC'];
  const weights = [0.5, 0.3, 0.2];
  const risk = portfolioRisk(symbols, weights, returns);
  const total = risk.contributions.reduce((acc, c) => acc + c.contribution, 0);
  assert.ok(Math.abs(total - 1) < 1e-9);
  assert.ok(risk.volatility > 0);
  assert.ok(risk.diversificationRatio >= 1 - 1e-9);
  assert.ok(risk.effectiveN > 1 && risk.effectiveN <= 3);
});

test('single-asset portfolio matches its own volatility', () => {
  const returns = { AAA: [0.01, -0.02, 0.03, 0.01, -0.01, 0.02] };
  const risk = portfolioRisk(['AAA'], [1], returns);
  const annualizedVol = Math.sqrt(returns.AAA.reduce((acc, r, _, arr) => {
    const mu = arr.reduce((a, b) => a + b, 0) / arr.length;
    return acc + (r - mu) ** 2;
  }, 0) / (returns.AAA.length - 1)) * Math.sqrt(252);
  assert.ok(Math.abs(risk.volatility - annualizedVol) < 1e-10);
});

test('parametric VaR rises with confidence and horizon', () => {
  const low = parametricVaR(0.2, 0.95, 1);
  const high = parametricVaR(0.2, 0.99, 1);
  const longer = parametricVaR(0.2, 0.95, 10);
  assert.ok(high > low);
  assert.ok(longer > low);
});

test('beta is one against itself and negative against an inverse series', () => {
  const benchmark = [0.01, -0.02, 0.03, 0.00, 0.01];
  assert.ok(Math.abs(beta(benchmark, benchmark) - 1) < 1e-12);
  const inverse = benchmark.map((r) => -r);
  assert.ok(Math.abs(beta(inverse, benchmark) + 1) < 1e-12);
});

test('Monte Carlo is deterministic and ordered', () => {
  const { candleMap } = {
    candleMap: {
      SPY: generateCandles('SPY', { count: 260, endDate: '2024-12-31' }).candles,
      QQQ: generateCandles('QQQ', { count: 260, endDate: '2024-12-31' }).candles,
    },
  };
  const returns = {
    SPY: returnsFromCandles(candleMap.SPY),
    QQQ: returnsFromCandles(candleMap.QQQ),
  };
  const first = monteCarlo(['SPY', 'QQQ'], [0.6, 0.4], returns, { simulations: 300, horizonDays: 63, seed: 99 });
  const second = monteCarlo(['SPY', 'QQQ'], [0.6, 0.4], returns, { simulations: 300, horizonDays: 63, seed: 99 });
  assert.equal(first.p5, second.p5);
  assert.ok(first.p5 <= first.median);
  assert.ok(first.median <= first.p95);
  assert.ok(first.probabilityOfLoss >= 0 && first.probabilityOfLoss <= 1);
  assert.ok(first.checkpoints[1].p5 <= first.checkpoints[1].p95);
  assert.ok(Array.isArray(first.bands));
  assert.equal(first.bands.length, 63 + 1);
  assert.equal(first.bands[0].median, first.initialValue);
  for (const point of first.bands) {
    assert.ok(point.p5 <= point.median + 1e-9);
    assert.ok(point.median <= point.p95 + 1e-9);
  }
});

test('stress tests apply sector shocks', () => {
  const assets = {
    AAA: { sector: 'Technology' },
    BBB: { sector: 'Fixed Income' },
  };
  const results = stressTests(['AAA', 'BBB'], [0.7, 0.3], assets);
  const gfc = results.find((r) => r.scenario.id === 'gfc-2008');
  assert.ok(gfc.portfolioShock < 0);
  assert.equal(gfc.byAsset[0].shock, -0.42);
  assert.equal(gfc.byAsset[1].shock, 0.06);
});

test('annualized mean scales by 252', () => {
  assert.ok(Math.abs(annualizedMean([0.001, 0.001]) - 0.252) < 1e-12);
});
