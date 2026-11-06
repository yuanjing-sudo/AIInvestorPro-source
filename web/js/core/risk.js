// Portfolio risk: covariance, risk contribution, Monte Carlo and stress tests.

import {
  mean, stdev, covariance, correlation, cholesky, matrixVector, dot,
  percentileSorted, SeededRandom, inverseNormal, clamp,
} from './math.js';

export function covarianceMatrix(returnsBySymbol, symbols, annualize = true) {
  const matrix = symbols.map((a) => symbols.map((b) => covariance(returnsBySymbol[a], returnsBySymbol[b])));
  return annualize ? matrix.map((row) => row.map((v) => v * 252)) : matrix;
}

export function correlationMatrix(returnsBySymbol, symbols) {
  return symbols.map((a) => symbols.map((b) => correlation(returnsBySymbol[a], returnsBySymbol[b])));
}

export function annualizedMean(returns) {
  return mean(returns) * 252;
}

export function portfolioRisk(symbols, weights, returnsBySymbol) {
  const n = symbols.length;
  if (!n || weights.length !== n) throw new Error('symbols and weights must align');
  const cov = covarianceMatrix(returnsBySymbol, symbols);
  const vols = symbols.map((s) => stdev(returnsBySymbol[s]) * Math.sqrt(252));
  const weighted = matrixVector(cov, weights);
  const variance = Math.max(0, dot(weights, weighted));
  const volatility = Math.sqrt(variance);
  const weightedVol = weights.reduce((acc, w, i) => acc + Math.abs(w) * vols[i], 0);
  const contributions = weights.map((w, i) => {
    const component = variance > 0 ? (w * weighted[i]) / variance : 0;
    return { symbol: symbols[i], weight: w, volatility: vols[i], contribution: component, componentRisk: w * weighted[i] };
  });
  const expectedReturn = symbols.reduce((acc, s, i) => acc + weights[i] * annualizedMean(returnsBySymbol[s]), 0);
  const effectiveN = weights.reduce((acc, w) => acc + w * w, 0) > 0
    ? 1 / weights.reduce((acc, w) => acc + w * w, 0)
    : 0;
  return {
    expectedReturn,
    volatility,
    variance,
    diversificationRatio: volatility > 0 ? weightedVol / volatility : 0,
    effectiveN,
    contributions,
    covariance: cov,
    correlation: correlationMatrix(returnsBySymbol, symbols),
    marginalRisk: weighted,
  };
}

export function parametricVaR(portfolioVolatility, confidence = 0.95, horizonDays = 1) {
  const z = inverseNormal(confidence);
  return z * portfolioVolatility * Math.sqrt(horizonDays / 252);
}

export function beta(returns, benchmarkReturns) {
  const n = Math.min(returns.length, benchmarkReturns.length);
  if (n < 2) return 0;
  const r = returns.slice(-n);
  const b = benchmarkReturns.slice(-n);
  const variance = covariance(b, b);
  return variance > 0 ? covariance(r, b) / variance : 0;
}

export function monteCarlo(symbols, weights, returnsBySymbol, options = {}) {
  const simulations = clamp(Math.round(options.simulations ?? 2000), 100, 20000);
  const horizonDays = clamp(Math.round(options.horizonDays ?? 63), 1, 1260);
  const initialValue = options.initialValue ?? 100000;
  const seed = options.seed ?? 7;
  const annualCov = covarianceMatrix(returnsBySymbol, symbols);
  const dailyCov = annualCov.map((row) => row.map((v) => v / 252));
  const lower = cholesky(dailyCov);
  if (!lower) return null;

  const dailyMean = symbols.map((s) => annualizedMean(returnsBySymbol[s]) / 252);
  const rng = new SeededRandom(BigInt(seed));
  const finals = new Array(simulations);
  const checkpoints = [0.25, 0.5, 0.75, 1];
  const checkpointValues = Object.fromEntries(checkpoints.map((p) => [p, []]));
  const samplePaths = [];
  const dailyValues = Array.from({ length: horizonDays + 1 }, () => []);
  dailyValues[0].push(initialValue);

  for (let sim = 0; sim < simulations; sim += 1) {
    let value = initialValue;
    const path = sim < 24 ? [value] : null;
    for (let day = 1; day <= horizonDays; day += 1) {
      const z = new Array(symbols.length).fill(0).map(() => rng.gaussian());
      const shocks = matrixVector(lower, z);
      let portfolioReturn = 0;
      for (let i = 0; i < symbols.length; i += 1) {
        const assetReturn = dailyMean[i] + shocks[i];
        portfolioReturn += weights[i] * assetReturn;
      }
      value *= Math.max(0, 1 + portfolioReturn);
      dailyValues[day].push(value);
      if (path) path.push(value);
      for (const p of checkpoints) {
        const target = Math.round(horizonDays * p);
        if (day === target) checkpointValues[p].push(value);
      }
    }
    finals[sim] = value;
    if (path) samplePaths.push(path);
  }

  const sorted = [...finals].sort((a, b) => a - b);
  const bands = dailyValues.map((values, day) => {
    const sortedDay = [...values].sort((a, b) => a - b);
    return {
      day,
      p5: percentileSorted(sortedDay, 0.05),
      p25: percentileSorted(sortedDay, 0.25),
      median: percentileSorted(sortedDay, 0.5),
      p75: percentileSorted(sortedDay, 0.75),
      p95: percentileSorted(sortedDay, 0.95),
      mean: mean(sortedDay),
    };
  });
  const summary = {
    simulations,
    horizonDays,
    initialValue,
    mean: mean(sorted),
    median: percentileSorted(sorted, 0.5),
    p5: percentileSorted(sorted, 0.05),
    p25: percentileSorted(sorted, 0.25),
    p75: percentileSorted(sorted, 0.75),
    p95: percentileSorted(sorted, 0.95),
    probabilityOfLoss: sorted.filter((v) => v < initialValue).length / simulations,
    expectedReturn: mean(sorted) / initialValue - 1,
    var95: initialValue - percentileSorted(sorted, 0.05),
    cvar95: (() => {
      const cutoff = percentileSorted(sorted, 0.05);
      const tail = sorted.filter((v) => v <= cutoff);
      return initialValue - (tail.length ? mean(tail) : cutoff);
    })(),
    checkpoints: Object.fromEntries(checkpoints.map((p) => {
      const values = checkpointValues[p].sort((a, b) => a - b);
      return [p, {
        p5: percentileSorted(values, 0.05),
        median: percentileSorted(values, 0.5),
        p95: percentileSorted(values, 0.95),
      }];
    })),
    samplePaths,
    bands,
    finals: sorted,
  };
  return summary;
}

export const STRESS_SCENARIOS = [
  {
    id: 'gfc-2008',
    name: '2008 Global Financial Crisis',
    description: 'Equities −38%, financials −55%, bonds +6%, gold +5%.',
    sectorShocks: {
      'Broad Market': -0.38, Technology: -0.42, Semiconductors: -0.45,
      Financials: -0.55, Energy: -0.30, Healthcare: -0.28, Consumer: -0.30,
      'Consumer Staples': -0.20, 'Fixed Income': 0.06, Commodities: 0.05, 'Digital Assets': -0.50,
    },
  },
  {
    id: 'covid-2020',
    name: 'COVID-19 Crash (Feb–Mar 2020)',
    description: 'Rapid 34% drawdown, energy and financials hit hardest.',
    sectorShocks: {
      'Broad Market': -0.34, Technology: -0.28, Semiconductors: -0.32,
      Financials: -0.40, Energy: -0.55, Healthcare: -0.20, Consumer: -0.26,
      'Consumer Staples': -0.15, 'Fixed Income': 0.04, Commodities: -0.18, 'Digital Assets': -0.40,
    },
  },
  {
    id: 'rate-shock',
    name: 'Inflation / Rate Shock',
    description: 'Bonds −12%, long-duration tech −25%, energy +18%.',
    sectorShocks: {
      'Broad Market': -0.15, Technology: -0.25, Semiconductors: -0.24,
      Financials: -0.08, Energy: 0.18, Healthcare: -0.06, Consumer: -0.12,
      'Consumer Staples': -0.05, 'Fixed Income': -0.12, Commodities: 0.14, 'Digital Assets': -0.35,
    },
  },
  {
    id: 'tech-selloff',
    name: 'Concentrated Tech Selloff',
    description: 'High-multiple technology −30%, defensives flat.',
    sectorShocks: {
      'Broad Market': -0.12, Technology: -0.30, Semiconductors: -0.34,
      Financials: -0.04, Energy: 0.02, Healthcare: 0.03, Consumer: -0.08,
      'Consumer Staples': 0.02, 'Fixed Income': 0.05, Commodities: 0.02, 'Digital Assets': -0.25,
    },
  },
  {
    id: 'liquidity-crunch',
    name: 'Liquidity Crunch',
    description: 'Correlations go to one; nearly everything falls, cash is king.',
    sectorShocks: {
      'Broad Market': -0.25, Technology: -0.28, Semiconductors: -0.30,
      Financials: -0.30, Energy: -0.26, Healthcare: -0.18, Consumer: -0.24,
      'Consumer Staples': -0.15, 'Fixed Income': -0.05, Commodities: -0.20, 'Digital Assets': -0.45,
    },
  },
];

export function runStressTest(symbols, weights, assetsBySymbol, scenario) {
  let shock = 0;
  const byAsset = symbols.map((symbol, i) => {
    const asset = assetsBySymbol[symbol] ?? { sector: 'Custom' };
    const sectorShock = scenario.sectorShocks[asset.sector] ?? scenario.sectorShocks['Broad Market'] ?? -0.2;
    const assetShock = sectorShock;
    shock += weights[i] * assetShock;
    return { symbol, sector: asset.sector, shock: assetShock, weighted: weights[i] * assetShock };
  });
  return { scenario, portfolioShock: shock, byAsset };
}

export function stressTests(symbols, weights, assetsBySymbol) {
  return STRESS_SCENARIOS.map((scenario) => runStressTest(symbols, weights, assetsBySymbol, scenario));
}
