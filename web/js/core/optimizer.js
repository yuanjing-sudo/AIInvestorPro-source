// Long-only constrained portfolio optimization. No external solver required:
// projected gradient descent with the simplex projection from math.js.

import { covarianceMatrix, annualizedMean, portfolioRisk } from './risk.js';
import { projectToSimplex, dot, mean, stdev } from './math.js';

export function equalWeights(symbols) {
  return new Array(symbols.length).fill(1 / Math.max(1, symbols.length));
}

export function inverseVolWeights(symbols, returnsBySymbol) {
  const inverse = symbols.map((s) => {
    const vol = stdev(returnsBySymbol[s]);
    return vol > 0 ? 1 / vol : 0;
  });
  const total = inverse.reduce((a, b) => a + b, 0);
  return total > 0 ? inverse.map((v) => v / total) : equalWeights(symbols);
}

function makeObjective(objective, symbols, returnsBySymbol, options) {
  const cov = covarianceMatrix(returnsBySymbol, symbols);
  const mu = symbols.map((s) => annualizedMean(returnsBySymbol[s]));
  const riskFree = options.riskFree ?? 0.02;
  const n = symbols.length;
  const target = 1 / Math.max(1, n);

  return (weights) => {
    const variance = Math.max(1e-14, dot(weights, cov.map((row) => dot(row, weights))));
    const sigma = Math.sqrt(variance);
    const expected = dot(weights, mu);
    switch (objective) {
      case 'minVariance':
        return variance;
      case 'maxReturn':
        return -expected;
      case 'maxSharpe':
        return -(expected - riskFree) / sigma;
      case 'riskParity': {
        const marginal = cov.map((row) => dot(row, weights));
        const contributions = weights.map((w, i) => w * marginal[i]);
        const total = contributions.reduce((a, b) => a + b, 0) || 1;
        return contributions.reduce((acc, c) => acc + (c / total - target) ** 2, 0);
      }
      case 'maxDiversification': {
        const vols = symbols.map((s) => stdev(returnsBySymbol[s]) * Math.sqrt(252));
        const weightedVol = weights.reduce((acc, w, i) => acc + w * vols[i], 0);
        return -(weightedVol / sigma);
      }
      default:
        return -(expected - riskFree) / sigma;
    }
  };
}

function project(weights, maxWeight) {
  return projectToSimplex(weights, maxWeight);
}

function numericalGradient(weights, objective, epsilon = 1e-5) {
  const gradient = new Array(weights.length).fill(0);
  for (let i = 0; i < weights.length; i += 1) {
    const plus = weights.slice();
    const minus = weights.slice();
    plus[i] += epsilon;
    minus[i] -= epsilon;
    gradient[i] = (objective(plus) - objective(minus)) / (2 * epsilon);
  }
  return gradient;
}

export function optimize(symbols, returnsBySymbol, options = {}) {
  const objectiveName = options.objective ?? 'maxSharpe';
  const maxWeight = Math.min(Math.max(options.maxWeight ?? 1, 1 / symbols.length), 1);
  const riskFree = options.riskFree ?? 0.02;
  const objective = makeObjective(objectiveName, symbols, returnsBySymbol, { riskFree });
  let weights = options.initial
    ? project(options.initial, maxWeight)
    : equalWeights(symbols);
  let value = objective(weights);
  let learningRate = options.learningRate ?? 0.8;
  const iterations = options.iterations ?? 1500;

  for (let iteration = 0; iteration < iterations; iteration += 1) {
    const gradient = numericalGradient(weights, objective);
    const magnitude = Math.sqrt(gradient.reduce((a, g) => a + g * g, 0));
    if (!Number.isFinite(magnitude) || magnitude < 1e-10) break;
    const direction = gradient.map((g) => g / magnitude);
    let accepted = false;
    for (let attempt = 0; attempt < 24; attempt += 1) {
      const candidate = project(weights.map((w, i) => w - learningRate * direction[i]), maxWeight);
      const candidateValue = objective(candidate);
      if (Number.isFinite(candidateValue) && candidateValue < value - 1e-14) {
        weights = candidate;
        value = candidateValue;
        learningRate = Math.min(learningRate * 1.15, 2);
        accepted = true;
        break;
      }
      learningRate *= 0.5;
    }
    if (!accepted) break;
    if (learningRate < 1e-10) break;
  }

  const risk = portfolioRisk(symbols, weights, returnsBySymbol);
  const expectedReturn = dot(weights, symbols.map((s) => annualizedMean(returnsBySymbol[s])));
  return {
    symbols,
    weights,
    objective: objectiveName,
    expectedReturn,
    volatility: risk.volatility,
    variance: risk.variance,
    sharpe: risk.volatility > 0 ? (expectedReturn - riskFree) / risk.volatility : 0,
    diversificationRatio: risk.diversificationRatio,
    effectiveN: risk.effectiveN,
    contributions: risk.contributions,
    maxWeight,
    riskFree,
  };
}

export function efficientFrontier(symbols, returnsBySymbol, options = {}) {
  const points = options.points ?? 16;
  const maxWeight = options.maxWeight ?? 1;
  const riskFree = options.riskFree ?? 0.02;
  const cov = covarianceMatrix(returnsBySymbol, symbols);
  const mu = symbols.map((s) => annualizedMean(returnsBySymbol[s]));
  const frontier = [];
  for (let i = 0; i < points; i += 1) {
    const lambda = 10 ** (-1 + (4 * i) / Math.max(1, points - 1));
    const makeObjective = (weights) => {
      const variance = Math.max(1e-14, dot(weights, cov.map((row) => dot(row, weights))));
      return -(dot(weights, mu) - lambda * variance);
    };
    let weights = equalWeights(symbols);
    let value = makeObjective(weights);
    let learningRate = 0.6;
    for (let iteration = 0; iteration < 600; iteration += 1) {
      const gradient = numericalGradient(weights, makeObjective);
      const magnitude = Math.sqrt(gradient.reduce((a, g) => a + g * g, 0));
      if (!Number.isFinite(magnitude) || magnitude < 1e-9) break;
      const direction = gradient.map((g) => g / magnitude);
      let accepted = false;
      for (let attempt = 0; attempt < 20; attempt += 1) {
        const candidate = project(weights.map((w, j) => w - learningRate * direction[j]), maxWeight);
        const candidateValue = makeObjective(candidate);
        if (Number.isFinite(candidateValue) && candidateValue < value - 1e-14) {
          weights = candidate;
          value = candidateValue;
          learningRate = Math.min(learningRate * 1.1, 2);
          accepted = true;
          break;
        }
        learningRate *= 0.5;
      }
      if (!accepted) break;
    }
    const risk = portfolioRisk(symbols, weights, returnsBySymbol);
    const expected = dot(weights, mu);
    frontier.push({
      lambda,
      weights,
      expectedReturn: expected,
      volatility: risk.volatility,
      sharpe: risk.volatility > 0 ? (expected - riskFree) / risk.volatility : 0,
    });
  }
  return frontier.sort((a, b) => a.volatility - b.volatility);
}

// Simple resampling test for robustness of optimizer inputs.
export function bootstrapWeights(symbols, returnsBySymbol, options = {}) {
  const rounds = options.rounds ?? 20;
  const objective = options.objective ?? 'maxSharpe';
  const maxWeight = options.maxWeight ?? 1;
  const samples = symbols.map((s) => returnsBySymbol[s]);
  const rng = options.rng ?? null;
  const averaged = new Array(symbols.length).fill(0);
  for (let round = 0; round < rounds; round += 1) {
    const sampled = {};
    symbols.forEach((symbol, i) => {
      const source = samples[i];
      const values = [];
      for (let j = 0; j < source.length; j += 1) {
        const index = rng ? Math.floor(rng.next() * source.length) : deterministicIndex(round, j, source.length);
        values.push(source[index]);
      }
      sampled[symbol] = values;
    });
    const result = optimize(symbols, sampled, { objective, maxWeight, iterations: 400 });
    result.weights.forEach((w, i) => { averaged[i] += w / rounds; });
  }
  return { symbols, weights: averaged, rounds };
}

function deterministicIndex(round, index, length) {
  const x = Math.sin((round + 1) * 97 + (index + 1) * 13) * 43758.5453;
  return Math.floor((x - Math.floor(x)) * length);
}
