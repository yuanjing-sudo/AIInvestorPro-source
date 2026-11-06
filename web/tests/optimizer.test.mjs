import test from 'node:test';
import assert from 'node:assert/strict';
import {
  optimize, efficientFrontier, equalWeights, inverseVolWeights, bootstrapWeights,
} from '../js/core/optimizer.js';
import { sum } from '../js/core/math.js';

function sampleReturns() {
  return {
    AAA: [0.01, 0.02, -0.01, 0.03, 0.00, -0.02, 0.015, 0.01, 0.005, -0.003],
    BBB: [-0.01, 0.005, 0.02, 0.01, -0.005, 0.01, 0.00, 0.02, -0.01, 0.004],
    CCC: [0.02, -0.01, 0.015, -0.005, 0.01, 0.005, -0.01, 0.03, 0.01, -0.002],
    DDD: [0.002, 0.001, -0.001, 0.003, 0.001, -0.002, 0.002, 0.001, 0.000, 0.001],
  };
}

const symbols = ['AAA', 'BBB', 'CCC', 'DDD'];

test('equal weights sum to one', () => {
  assert.equal(sum(equalWeights(symbols)), 1);
});

test('inverse volatility weights favor the calm asset', () => {
  const weights = inverseVolWeights(symbols, sampleReturns());
  assert.ok(Math.abs(sum(weights) - 1) < 1e-12);
  assert.ok(weights[3] > weights[0]);
});

for (const objective of ['minVariance', 'maxSharpe', 'riskParity', 'maxDiversification']) {
  test(`optimizer respects constraints for ${objective}`, () => {
    const result = optimize(symbols, sampleReturns(), { objective, maxWeight: 0.6, iterations: 800 });
    assert.ok(Math.abs(sum(result.weights) - 1) < 1e-7);
    result.weights.forEach((w) => assert.ok(w >= -1e-9 && w <= 0.6 + 1e-7));
    assert.ok(Number.isFinite(result.expectedReturn));
    assert.ok(result.volatility >= 0);
    const contributions = result.contributions.reduce((acc, c) => acc + c.contribution, 0);
    assert.ok(Math.abs(contributions - 1) < 1e-6);
  });
}

test('min variance volatility does not exceed equal weight volatility', () => {
  const result = optimize(symbols, sampleReturns(), { objective: 'minVariance', iterations: 1000 });
  const equal = optimize(symbols, sampleReturns(), {
    objective: 'minVariance', initial: equalWeights(symbols), iterations: 1,
  });
  assert.ok(result.volatility <= equal.volatility + 1e-6);
});

test('efficient frontier is ordered by volatility and feasible', () => {
  const frontier = efficientFrontier(symbols, sampleReturns(), { points: 6, maxWeight: 1 });
  assert.equal(frontier.length, 6);
  for (let i = 1; i < frontier.length; i += 1) {
    assert.ok(frontier[i].volatility >= frontier[i - 1].volatility - 1e-9);
  }
  frontier.forEach((point) => {
    assert.ok(Math.abs(sum(point.weights) - 1) < 1e-6);
    point.weights.forEach((w) => assert.ok(w >= -1e-9));
  });
});

test('bootstrap averages weights without changing constraints', () => {
  const result = bootstrapWeights(symbols, sampleReturns(), {
    rounds: 8, objective: 'maxSharpe', maxWeight: 0.7,
  });
  assert.equal(result.weights.length, symbols.length);
  assert.ok(Math.abs(sum(result.weights) - 1) < 1e-6);
  result.weights.forEach((w) => assert.ok(w >= -1e-9 && w <= 0.7 + 1e-6));
});
