// Probabilistic forecasting and model diagnostics for the web app.
//
// The design is deliberately transparent: a ridge factor model, a Holt trend
// model and a drift/volatility model are evaluated with walk-forward holdout
// data, then blended inversely to their out-of-sample error. Nothing here is a
// promise of future returns; the UI shows the error bars alongside the point
// estimate.

import {
  mean, stdev, percentileSorted, clamp, SeededRandom,
} from './math.js';
import {
  sma, rsi, macd, atr, bollinger, roc, stochastic,
} from './indicators.js';
import { logReturnsFromCandles } from './marketdata.js';

export const FEATURE_DEFINITIONS = [
  { key: 'mom5', label: '5-day momentum', group: 'Momentum' },
  { key: 'mom20', label: '20-day momentum', group: 'Momentum' },
  { key: 'mom60', label: '60-day momentum', group: 'Momentum' },
  { key: 'mom120', label: '120-day momentum', group: 'Momentum' },
  { key: 'rsi', label: 'RSI 14 (centred)', group: 'Momentum' },
  { key: 'macd', label: 'MACD histogram / price', group: 'Trend' },
  { key: 'atr', label: 'ATR / price', group: 'Volatility' },
  { key: 'vol20', label: '20-day volatility', group: 'Volatility' },
  { key: 'volRatio', label: 'Short / long volatility', group: 'Volatility' },
  { key: 'sma20', label: 'Price vs SMA 20', group: 'Trend' },
  { key: 'sma50', label: 'Price vs SMA 50', group: 'Trend' },
  { key: 'volumeZ', label: 'Volume z-score', group: 'Liquidity' },
  { key: 'drawdown', label: 'Drawdown from 6-month high', group: 'Risk' },
  { key: 'rangePos', label: 'Position in 20-day range', group: 'Mean reversion' },
  { key: 'skew', label: '20-day skewness', group: 'Distribution' },
  { key: 'kurt', label: '20-day excess kurtosis', group: 'Distribution' },
  { key: 'slope', label: '20-day trend slope', group: 'Trend' },
  { key: 'gap', label: 'Overnight gap', group: 'Microstructure' },
  { key: 'bbPos', label: 'Bollinger %B (centred)', group: 'Mean reversion' },
  { key: 'stoch', label: 'Stochastic %K (centred)', group: 'Momentum' },
];

export const MODEL_LABELS = {
  ensemble: 'Ensemble',
  factor: 'Factor ridge',
  holt: 'Holt trend',
  drift: 'Drift + volatility',
};

const WARMUP = 130;
const TRADING_DAYS = 252;

function rollingStats(values, window) {
  const out = new Array(values.length).fill(null);
  for (let i = window - 1; i < values.length; i += 1) {
    const slice = values.slice(i - window + 1, i + 1);
    const mu = mean(slice);
    const sigma = stdev(slice);
    out[i] = { mean: mu, stdev: sigma, min: Math.min(...slice), max: Math.max(...slice) };
  }
  return out;
}

function rollingVolatility(logReturns, window) {
  const out = new Array(logReturns.length + 1).fill(null);
  for (let i = window; i < logReturns.length + 1; i += 1) {
    out[i] = stdev(logReturns.slice(i - window, i)) * Math.sqrt(TRADING_DAYS);
  }
  return out;
}

function safe(value, fallback = 0) {
  return Number.isFinite(value) ? value : fallback;
}

/** Build one feature row per bar, aligned to the closing price at that bar. */
export function buildFeatureRows(candles) {
  if (!candles || candles.length < WARMUP + 10) return [];
  const close = candles.map((candle) => candle.close);
  const open = candles.map((candle) => candle.open);
  const high = candles.map((candle) => candle.high);
  const low = candles.map((candle) => candle.low);
  const volume = candles.map((candle) => candle.volume);
  const logReturns = logReturnsFromCandles(candles);

  const sma20 = sma(close, 20);
  const sma50 = sma(close, 50);
  const rsi14 = rsi(close, 14);
  const macdSeries = macd(close);
  const atr14 = atr(high, low, close, 14);
  const bb = bollinger(close, 20, 2);
  const stoch = stochastic(high, low, close, 14, 3);
  const roc5 = roc(close, 5);
  const roc20 = roc(close, 20);
  const roc60 = roc(close, 60);
  const roc120 = roc(close, 120);
  const vol20 = rollingVolatility(logReturns, 20);
  const vol60 = rollingVolatility(logReturns, 60);
  const volumeStats = rollingStats(volume, 20);
  const closeStats = rollingStats(close, 20);
  const high120 = rollingStats(high, 120);

  const rows = [];
  for (let i = WARMUP; i < close.length; i += 1) {
    if (!Number.isFinite(close[i]) || !Number.isFinite(close[i - 1])) continue;
    const price = close[i];
    const daily = [];
    for (let j = Math.max(1, i - 19); j <= i; j += 1) {
      const previous = close[j - 1];
      daily.push(previous > 0 ? Math.log(close[j] / previous) : 0);
    }
    const dailyMean = mean(daily);
    const dailySigma = stdev(daily);
    const skew = dailySigma > 0
      ? daily.reduce((acc, r) => acc + ((r - dailyMean) / dailySigma) ** 3, 0) / daily.length
      : 0;
    const kurt = dailySigma > 0
      ? daily.reduce((acc, r) => acc + ((r - dailyMean) / dailySigma) ** 4, 0) / daily.length - 3
      : 0;
    const slopeWindow = close.slice(Math.max(0, i - 19), i + 1);
    const slope = linearSlope(slopeWindow) / (price || 1);
    const volumeRow = volumeStats[i] ?? { mean: mean(volume), stdev: 0 };
    const rangeRow = closeStats[i] ?? { min: low[i], max: high[i] };
    const bbRow = bb.upper[i] !== null && bb.lower[i] !== null && bb.upper[i] > bb.lower[i]
      ? (price - bb.lower[i]) / (bb.upper[i] - bb.lower[i]) - 0.5
      : 0;
    const atrValue = atr14[i];
    const rsiValue = rsi14[i];
    const stochValue = stoch.k[i];

    const features = [
      safe(roc5[i]) / 100,
      safe(roc20[i]) / 100,
      safe(roc60[i]) / 100,
      safe(roc120[i]) / 100,
      (safe(rsiValue, 50) - 50) / 50,
      (safe(macdSeries.histogram[i])) / (price || 1),
      safe(atrValue) / (price || 1),
      safe(vol20[i]),
      safe(vol60[i]) > 0 ? safe(vol20[i]) / safe(vol60[i]) : 1,
      sma20[i] ? price / sma20[i] - 1 : 0,
      sma50[i] ? price / sma50[i] - 1 : 0,
      volumeRow.stdev > 0 ? (volume[i] - volumeRow.mean) / volumeRow.stdev : 0,
      high120[i]?.max > 0 ? price / high120[i].max - 1 : 0,
      rangeRow.max > rangeRow.min ? (price - rangeRow.min) / (rangeRow.max - rangeRow.min) - 0.5 : 0,
      clamp(skew, -4, 4),
      clamp(kurt, -4, 12),
      clamp(slope, -0.1, 0.1),
      close[i - 1] > 0 ? open[i] / close[i - 1] - 1 : 0,
      clamp(bbRow, -1, 1),
      clamp((safe(stochValue, 50) - 50) / 50, -1, 1),
    ];

    rows.push({
      index: i,
      date: candles[i].date,
      close: price,
      features: features.map((value) => safe(value, 0)),
    });
  }
  return rows;
}

function linearSlope(values) {
  const n = values.length;
  if (n < 2) return 0;
  const xMean = (n - 1) / 2;
  const yMean = mean(values);
  let numerator = 0;
  let denominator = 0;
  for (let i = 0; i < n; i += 1) {
    numerator += (i - xMean) * (values[i] - yMean);
    denominator += (i - xMean) ** 2;
  }
  return denominator > 0 ? numerator / denominator : 0;
}

function standardize(matrix) {
  const columns = matrix[0]?.length ?? 0;
  const means = new Array(columns).fill(0);
  const stds = new Array(columns).fill(1);
  for (let j = 0; j < columns; j += 1) {
    const column = matrix.map((row) => row[j]);
    means[j] = mean(column);
    stds[j] = stdev(column) || 1;
  }
  return {
    matrix: matrix.map((row) => row.map((value, j) => (value - means[j]) / stds[j])),
    means,
    stds,
  };
}

function gaussianSolve(matrix, vector) {
  const n = vector.length;
  const a = matrix.map((row, i) => [...row, vector[i]]);
  for (let i = 0; i < n; i += 1) {
    let pivot = i;
    for (let r = i + 1; r < n; r += 1) {
      if (Math.abs(a[r][i]) > Math.abs(a[pivot][i])) pivot = r;
    }
    if (Math.abs(a[pivot][i]) < 1e-12) continue;
    [a[i], a[pivot]] = [a[pivot], a[i]];
    const divisor = a[i][i];
    for (let c = i; c <= n; c += 1) a[i][c] /= divisor;
    for (let r = 0; r < n; r += 1) {
      if (r === i) continue;
      const factor = a[r][i];
      if (!factor) continue;
      for (let c = i; c <= n; c += 1) a[r][c] -= factor * a[i][c];
    }
  }
  return a.map((row, i) => (Number.isFinite(row[n]) ? row[n] : 0));
}

function ridgeFit(rows, labels, lambda = 1.4) {
  const { matrix, means, stds } = standardize(rows);
  const n = matrix.length;
  const p = (matrix[0]?.length ?? 0) + 1;
  if (!n || p <= 1) return null;
  const design = matrix.map((row) => [1, ...row]);
  const xtx = Array.from({ length: p }, () => new Array(p).fill(0));
  const xty = new Array(p).fill(0);
  for (let i = 0; i < n; i += 1) {
    for (let a = 0; a < p; a += 1) {
      xty[a] += design[i][a] * labels[i];
      for (let b = 0; b < p; b += 1) xtx[a][b] += design[i][a] * design[i][b];
    }
  }
  for (let a = 1; a < p; a += 1) xtx[a][a] += lambda;
  const coefficients = gaussianSolve(xtx, xty);
  const predictions = design.map((row) => row.reduce((acc, value, i) => acc + value * coefficients[i], 0));
  const residual = labels.map((value, i) => value - predictions[i]);
  const total = labels.reduce((acc, value) => acc + (value - mean(labels)) ** 2, 0);
  const residualSum = residual.reduce((acc, value) => acc + value ** 2, 0);
  return {
    coefficients,
    means,
    stds,
    predictions,
    r2: total > 0 ? 1 - residualSum / total : 0,
    rmse: Math.sqrt(residualSum / Math.max(1, n)),
    observations: n,
  };
}

export function buildSamples(candles, horizon = 5) {
  const rows = buildFeatureRows(candles);
  const close = candles.map((candle) => candle.close);
  const samples = [];
  for (const row of rows) {
    const exit = row.index + horizon;
    if (exit >= close.length) continue;
    if (!(row.close > 0) || !(close[exit] > 0)) continue;
    samples.push({
      x: row.features,
      y: Math.log(close[exit] / row.close),
      index: row.index,
    });
  }
  return { rows, samples };
}

/** Out-of-sample walk-forward evaluation of the factor model. */
export function walkForwardFactor(candles, horizon = 5, folds = 20) {
  const { samples } = buildSamples(candles, horizon);
  if (samples.length < 60) {
    return {
      observations: 0, mae: 0, rmse: 0, directionalAccuracy: 0, r2: 0,
      baselineRmse: 0, skill: 0, points: [],
    };
  }
  const trainStart = Math.max(40, Math.floor(samples.length * 0.45));
  const usable = samples.length - trainStart;
  const count = Math.min(folds, usable);
  const points = [];
  for (let fold = 0; fold < count; fold += 1) {
    const position = trainStart + Math.floor((fold / Math.max(1, count - 1)) * (usable - 1));
    const train = samples.slice(0, position);
    if (train.length < 35) continue;
    const fit = ridgeFit(train.map((sample) => sample.x), train.map((sample) => sample.y));
    if (!fit) continue;
    const test = samples[position];
    const standardized = test.x.map((value, j) => (value - fit.means[j]) / fit.stds[j]);
    const predicted = fit.coefficients[0]
      + standardized.reduce((acc, value, j) => acc + value * fit.coefficients[j + 1], 0);
    points.push({
      index: test.index,
      date: candles[test.index]?.date ?? null,
      predicted,
      actual: test.y,
    });
  }
  if (!points.length) {
    return {
      observations: 0, mae: 0, rmse: 0, directionalAccuracy: 0, r2: 0,
      baselineRmse: 0, skill: 0, points: [],
    };
  }
  const errors = points.map((point) => point.predicted - point.actual);
  const mae = mean(errors.map((error) => Math.abs(error)));
  const rmse = Math.sqrt(mean(errors.map((error) => error ** 2)));
  const baseline = mean(points.map((point) => Math.abs(point.actual)));
  const directional = points.filter((point) => Math.sign(point.predicted) === Math.sign(point.actual)).length;
  const actualMean = mean(points.map((point) => point.actual));
  const total = points.reduce((acc, point) => acc + (point.actual - actualMean) ** 2, 0);
  const residual = points.reduce((acc, point) => acc + (point.actual - point.predicted) ** 2, 0);
  return {
    observations: points.length,
    mae,
    rmse,
    directionalAccuracy: directional / points.length,
    r2: total > 0 ? 1 - residual / total : 0,
    baselineRmse: baseline,
    skill: baseline > 0 ? 1 - mae / baseline : 0,
    points,
  };
}

function oneStepError(candles, predictor, window = 126) {
  const close = candles.map((candle) => candle.close);
  const errors = [];
  const start = Math.max(40, close.length - window);
  for (let i = start; i < close.length - 1; i += 1) {
    const prediction = predictor(close.slice(0, i + 1));
    if (!Number.isFinite(prediction) || !(prediction > 0)) continue;
    errors.push(Math.log(prediction / close[i]));
  }
  return errors;
}

export function driftForecast(candles, horizon = 21, lookback = 252) {
  const close = candles.map((candle) => candle.close);
  if (close.length < 40) return null;
  const window = Math.min(lookback, close.length - 1);
  const logReturns = logReturnsFromCandles(candles).slice(-window);
  const average = mean(logReturns);
  // Shrink the drift toward zero: it is the noisiest estimate in finance.
  const drift = average * 0.45;
  const sigma = stdev(logReturns) * Math.sqrt(TRADING_DAYS);
  const start = close[close.length - 1];
  const path = [];
  for (let day = 1; day <= horizon; day += 1) {
    path.push(start * Math.exp(drift * day));
  }
  return {
    model: 'drift',
    expectedLogReturn: drift * horizon,
    expectedReturn: Math.exp(drift * horizon) - 1,
    annualDrift: drift * TRADING_DAYS,
    annualVolatility: sigma,
    path,
    oneStepMae: mean(oneStepError(candles, (slice) => {
      const returns = logReturnsFromCandles(slice.map((value) => ({ close: value }))).slice(-120);
      return slice[slice.length - 1] * Math.exp(mean(returns) * 0.45);
    }, 90).map((error) => Math.abs(error))),
  };
}

export function holtForecast(candles, horizon = 21, alpha = 0.32, beta = 0.08) {
  const close = candles.map((candle) => candle.close).filter((value) => value > 0);
  if (close.length < 40) return null;
  const logs = close.map((value) => Math.log(value));
  let level = logs[0];
  let trend = logs[1] - logs[0];
  for (let i = 1; i < logs.length; i += 1) {
    const previous = level;
    level = alpha * logs[i] + (1 - alpha) * (level + trend);
    trend = beta * (level - previous) + (1 - beta) * trend;
  }
  const path = [];
  for (let day = 1; day <= horizon; day += 1) path.push(Math.exp(level + trend * day));
  const oneStep = oneStepError(candles, (slice) => {
    const logsSlice = slice.map((value) => Math.log(value));
    let l = logsSlice[0];
    let t = logsSlice[1] - logsSlice[0];
    for (let i = 1; i < logsSlice.length; i += 1) {
      const previous = l;
      l = alpha * logsSlice[i] + (1 - alpha) * (l + t);
      t = beta * (l - previous) + (1 - beta) * t;
    }
    return Math.exp(l + t);
  }, 90);
  return {
    model: 'holt',
    expectedLogReturn: level + trend * horizon - logs[logs.length - 1],
    expectedReturn: path[path.length - 1] / close[close.length - 1] - 1,
    annualDrift: trend * TRADING_DAYS,
    annualVolatility: stdev(logReturnsFromCandles(candles).slice(-252)) * Math.sqrt(TRADING_DAYS),
    path,
    oneStepMae: mean(oneStep.map((error) => Math.abs(error))),
  };
}

function studentT(rng, df = 5) {
  const gaussian = rng.gaussian();
  let chiSquare = 0;
  for (let i = 0; i < df; i += 1) {
    const normal = rng.gaussian();
    chiSquare += normal * normal;
  }
  const value = gaussian / Math.sqrt(chiSquare / df);
  // Scale to unit variance for df > 2.
  return value * Math.sqrt((df - 2) / df);
}

export function simulatePaths(start, expectedLogReturn, annualVolatility, horizon, options = {}) {
  const simulations = clamp(Math.round(options.simulations ?? 2000), 200, 5000);
  const seed = options.seed ?? 7;
  const fatTails = options.fatTails !== false;
  const rng = new SeededRandom(BigInt(seed));
  const sigmaDaily = annualVolatility / Math.sqrt(TRADING_DAYS);
  const driftDaily = expectedLogReturn / Math.max(1, horizon);
  const terminals = new Array(simulations);
  const dayValues = Array.from({ length: horizon + 1 }, () => []);
  const samplePaths = [];
  const keep = Math.min(60, simulations);
  for (let simulation = 0; simulation < simulations; simulation += 1) {
    let value = start;
    const path = [value];
    dayValues[0].push(value);
    for (let day = 1; day <= horizon; day += 1) {
      const shock = fatTails ? studentT(rng, 5) : rng.gaussian();
      value *= Math.exp(driftDaily - 0.5 * sigmaDaily ** 2 + sigmaDaily * shock);
      path.push(value);
      dayValues[day].push(value);
    }
    terminals[simulation] = value;
    if (simulation < keep) samplePaths.push(path);
  }
  const sortedTerminals = [...terminals].sort((a, b) => a - b);
  const quantile = (p) => percentileSorted(sortedTerminals, p);
  const sortedDaily = dayValues.map((values) => [...values].sort((a, b) => a - b));
  const band = (p) => sortedDaily.map((values) => percentileSorted(values, p));
  const medianPath = band(0.5);
  const sortedSample = [...terminals].sort((a, b) => a - b);
  const cutoff = percentileSorted(sortedSample, 0.05);
  const tail = sortedSample.filter((value) => value <= cutoff);
  return {
    simulations,
    start,
    terminals,
    medianPath,
    meanTerminal: mean(terminals),
    medianTerminal: quantile(0.5),
    var95: Math.max(0, start - quantile(0.05)),
    cvar95: Math.max(0, start - mean(tail.length ? tail : [quantile(0.05)])),
    probabilityUp: terminals.filter((value) => value > start).length / terminals.length,
    bands: {
      50: { lower: band(0.25), upper: band(0.75) },
      80: { lower: band(0.1), upper: band(0.9) },
      95: { lower: band(0.025), upper: band(0.975) },
    },
    samplePaths,
    expectedReturn: mean(terminals) / start - 1,
  };
}

export function detectRegime(candles) {
  const close = candles.map((candle) => candle.close);
  if (close.length < 60) {
    return { key: 'unknown', label: 'Insufficient data', tone: '', description: 'Not enough bars for a regime classification.', metrics: {} };
  }
  const sma20 = sma(close, 20).at(-1);
  const sma50 = sma(close, 50).at(-1);
  const rsiValue = rsi(close, 14).at(-1) ?? 50;
  const returns = logReturnsFromCandles(candles);
  const vol20 = stdev(returns.slice(-20)) * Math.sqrt(TRADING_DAYS);
  const vol252 = stdev(returns.slice(-252)) * Math.sqrt(TRADING_DAYS);
  const volRatio = vol252 > 0 ? vol20 / vol252 : 1;
  const drawdown = close.at(-1) / Math.max(...close.slice(-252)) - 1;
  const price = close.at(-1);
  const trendPct = sma50 ? sma20 / sma50 - 1 : 0;
  let key = 'range';
  let label = 'Range / neutral';
  let tone = '';
  let description = 'Trend and volatility are close to their recent norms.';
  if (drawdown < -0.18 && volRatio > 1.25) {
    key = 'riskoff';
    label = 'Risk-off';
    tone = 'neg';
    description = 'The asset is in a deep drawdown with elevated volatility. Forecast intervals widen.';
  } else if (volRatio > 1.45) {
    key = 'volatile';
    label = 'High volatility';
    tone = 'warn';
    description = 'Realized volatility is well above its one-year norm. Reduce position-size confidence.';
  } else if (trendPct > 0.012 && price > sma20 && rsiValue > 48) {
    key = 'uptrend';
    label = 'Trend up';
    tone = 'pos';
    description = 'Short and medium moving averages are rising together with constructive momentum.';
  } else if (trendPct < -0.012 && price < sma20 && rsiValue < 52) {
    key = 'downtrend';
    label = 'Trend down';
    tone = 'neg';
    description = 'Moving averages are falling and price is below the short-term trend.';
  }
  return {
    key,
    label,
    tone,
    description,
    metrics: {
      trendPct,
      vol20,
      vol252,
      volRatio,
      drawdown,
      rsi: rsiValue,
    },
  };
}

function normalCdf(value) {
  // Abramowitz and Stegun 7.1.26.
  const x = value / Math.SQRT2;
  const sign = x < 0 ? -1 : 1;
  const abs = Math.abs(x);
  const t = 1 / (1 + 0.3275911 * abs);
  const erf = 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * Math.exp(-abs * abs);
  return 0.5 * (1 + sign * erf);
}

function contextTilt(context, horizon) {
  if (!context) return { tilt: 0, components: [], raw: 0 };
  const { fundamentals: f, macro: m, sentiment: s } = context;
  const components = [];
  const add = (label, value, weight = 1) => {
    if (!Number.isFinite(value) || value === 0) return;
    components.push({ label, value: value * weight });
  };
  if (f) {
    add('Analyst upside', clamp(f.analystUpside ?? 0, -0.35, 0.55) * 0.018);
    add('Revenue growth', clamp(f.revenueGrowth ?? 0, -0.2, 0.45) * 0.012);
    add('Profit margin', clamp(f.profitMargin ?? 0, 0, 0.45) * 0.008);
    add('Valuation drag', -clamp((f.forwardPE ?? 20) / 80, 0, 1) * 0.004);
  }
  if (s) add('News sentiment', clamp(s.score ?? 0, -1, 1) * 0.010);
  if (m) {
    add('Volatility regime', m.vix > 27 ? -0.012 : m.vix < 17 ? 0.006 : 0, 1);
    add('Yield curve', m.yieldCurve < 0 ? -0.004 : 0.003, 1);
    add('Liquidity', m.liquidity === 'Tightening' ? -0.004 : 0.002, 1);
  }
  const raw = components.reduce((acc, component) => acc + component.value, 0);
  // Keep the tilt small relative to the walk-forward model blend.
  const scaled = clamp(raw, -0.035, 0.035) * (horizon / 21) * 0.5;
  return { tilt: scaled, components, raw };
}

export function buildForecast(candles, options = {}) {
  if (!candles || candles.length < 180) return null;
  const horizon = clamp(Math.round(options.horizon ?? 21), 5, 126);
  const simulations = clamp(Math.round(options.simulations ?? 2000), 200, 5000);
  const seed = options.seed ?? 7;
  const mode = options.mode ?? 'ensemble';
  const context = options.context ?? null;
  const close = candles.map((candle) => candle.close);
  const start = close[close.length - 1];
  const historyLength = Math.min(options.history ?? 180, close.length);
  const history = candles.slice(-historyLength);

  const drift = driftForecast(candles, horizon);
  const holt = holtForecast(candles, horizon);
  const training = buildSamples(candles, 5);
  const factor = training.samples.length >= 40
    ? ridgeFit(
      training.samples.map((sample) => sample.x),
      training.samples.map((sample) => sample.y),
    )
    : null;
  const latestFeatures = training.rows.at(-1)?.features ?? [];
  const factorExpected = factor
    ? factor.coefficients[0] + latestFeatures.reduce(
      (acc, value, j) => acc + ((value - factor.means[j]) / factor.stds[j]) * factor.coefficients[j + 1],
      0,
    )
    : 0;
  const factorDiagnostics = walkForwardFactor(candles, 5, 20);
  const factorVol = stdev(logReturnsFromCandles(candles).slice(-252)) * Math.sqrt(TRADING_DAYS);
  const factorModel = {
    model: 'factor',
    expectedLogReturn: factorExpected * (horizon / 5),
    expectedReturn: Math.exp(factorExpected * (horizon / 5)) - 1,
    annualDrift: (factorExpected / 5) * TRADING_DAYS,
    annualVolatility: factorVol,
    oneStepMae: factorDiagnostics.mae * Math.sqrt(horizon / 5),
    r2: factor?.r2 ?? 0,
  };

  const models = [drift, holt, factorModel].filter(Boolean);
  const errors = models.map((model) => {
    if (model.model === 'drift') return Math.max(0.002, (model.oneStepMae || 0.01) * Math.sqrt(horizon));
    if (model.model === 'holt') return Math.max(0.002, (model.oneStepMae || 0.01) * Math.sqrt(horizon));
    return Math.max(0.002, (model.oneStepMae || 0.02) * Math.sqrt(horizon / 5));
  });
  const inverse = errors.map((error) => 1 / error);
  const totalInverse = inverse.reduce((acc, value) => acc + value, 0);
  let weights = inverse.map((value) => value / totalInverse);
  if (mode !== 'ensemble') {
    const selected = models.findIndex((model) => model.model === mode);
    weights = models.map((_, index) => (index === selected ? 1 : 0));
  }
  const modelRows = models.map((model, index) => ({
    key: model.model,
    label: MODEL_LABELS[model.model],
    weight: weights[index],
    expectedReturn: mode === 'ensemble'
      ? model.expectedReturn
      : model.model === mode ? model.expectedReturn : model.expectedReturn,
    expectedLogReturn: model.expectedLogReturn,
    annualVolatility: model.annualVolatility,
    error: errors[index],
    oneStepMae: model.oneStepMae,
    selected: mode === 'ensemble' || model.model === mode,
  }));
  const blendedModelLog = models.reduce((acc, model, index) => acc + model.expectedLogReturn * weights[index], 0);
  const contextResult = contextTilt(context, horizon);
  const contextLog = mode === 'ensemble' ? contextResult.tilt : 0;
  const blendedLog = blendedModelLog + contextLog;
  const blendedReturn = mode === 'ensemble'
    ? Math.exp(blendedLog) - 1
    : models.find((model) => model.model === mode)?.expectedReturn ?? 0;
  const annualVolatility = stdev(logReturnsFromCandles(candles).slice(-252)) * Math.sqrt(TRADING_DAYS);
  const simulation = simulatePaths(start, blendedLog, annualVolatility, horizon, { simulations, seed });
  const regime = detectRegime(candles);

  const futureDates = nextBusinessDays(candles.at(-1).date, horizon);
  const labels = [...history.map((candle) => candle.date), ...futureDates];
  const pad = (values, before = history.length - 1, total = labels.length) => {
    const out = new Array(total).fill(null);
    values.forEach((value, index) => { out[before + index] = value; });
    return out;
  };
  const median = pad([start, ...simulation.medianPath]);
  const bandSeries = [50, 80, 95].map((level) => ({
    level,
    lower: pad([start, ...simulation.bands[level].lower]),
    upper: pad([start, ...simulation.bands[level].upper]),
  }));

  const distribution = histogram(simulation.terminals, 26);
  const scenarios = [
    { key: 'bear', label: 'Bear case', probability: 0.1, price: percentileSorted([...simulation.terminals].sort((a, b) => a - b), 0.1) },
    { key: 'base', label: 'Base case', probability: 0.5, price: simulation.medianTerminal },
    { key: 'bull', label: 'Bull case', probability: 0.9, price: percentileSorted([...simulation.terminals].sort((a, b) => a - b), 0.9) },
  ].map((scenario) => ({ ...scenario, return: scenario.price / start - 1 }));

  const factorContributions = factor
    ? latestFeatures.map((value, index) => {
      const z = (value - factor.means[index]) / factor.stds[index];
      return {
        key: FEATURE_DEFINITIONS[index]?.key ?? `f${index}`,
        label: FEATURE_DEFINITIONS[index]?.label ?? `Feature ${index + 1}`,
        group: FEATURE_DEFINITIONS[index]?.group ?? 'Other',
        z,
        coefficient: factor.coefficients[index + 1],
        contribution: z * factor.coefficients[index + 1],
      };
    }).sort((a, b) => Math.abs(b.contribution) - Math.abs(a.contribution))
    : [];

  const directional = factorDiagnostics.directionalAccuracy;
  const agreement = 1 - clamp(stdev([drift?.expectedReturn ?? 0, holt?.expectedReturn ?? 0, factorModel.expectedReturn]) / Math.max(0.005, Math.abs(blendedReturn) + 0.01), 0, 1);
  const confidence = clamp(
    42
    + (directional - 0.5) * 90
    + clamp(factorDiagnostics.r2, 0, 1) * 16
    + agreement * 18
    + clamp(factorDiagnostics.observations / 40, 0, 1) * 8,
    5,
    95,
  );

  const terminalSorted = [...simulation.terminals].sort((a, b) => a - b);
  const expectedMove = simulation.meanTerminal - start;
  return {
    symbol: options.symbol ?? '',
    horizon,
    mode,
    start,
    startDate: candles.at(-1).date,
    futureDates,
    labels,
    history,
    historyLength,
    median,
    bands: bandSeries,
    samplePaths: simulation.samplePaths.map((path) => pad([start, ...path])),
    distribution,
    scenarios,
    simulation,
    regime,
    models: modelRows,
    factor,
    factorExpected,
    factorContributions,
    factorDiagnostics,
    factorVol,
    annualVolatility,
    blendedLog,
    expectedReturn: blendedReturn,
    expectedLogReturn: blendedLog,
    contextTilt: contextLog,
    contextBreakdown: contextResult.components,
    contextUsed: Boolean(context),
    expectedPrice: start * Math.exp(blendedLog),
    expectedMove,
    probabilityUp: mode === 'ensemble' ? simulation.probabilityUp : normalCdf(blendedLog / Math.max(1e-9, annualVolatility * Math.sqrt(horizon / TRADING_DAYS))),
    targetPrice: simulation.medianTerminal,
    var95: simulation.var95,
    cvar95: simulation.cvar95,
    confidence,
    diagnostics: {
      mae: factorDiagnostics.mae,
      rmse: factorDiagnostics.rmse,
      directionalAccuracy: factorDiagnostics.directionalAccuracy,
      r2: factorDiagnostics.r2,
      baselineRmse: factorDiagnostics.baselineRmse,
      skill: factorDiagnostics.skill,
      observations: factorDiagnostics.observations,
      oneStepMae: mean(errors),
    },
    dataRows: candles.length,
  };
}

function nextBusinessDays(from, count) {
  const date = from instanceof Date ? new Date(from) : new Date(from);
  const out = [];
  while (out.length < count) {
    date.setUTCDate(date.getUTCDate() + 1);
    const day = date.getUTCDay();
    if (day !== 0 && day !== 6) out.push(new Date(date));
  }
  return out;
}

function histogram(values, bins = 24) {
  if (!values.length) return [];
  const sorted = [...values].sort((a, b) => a - b);
  const min = sorted[0];
  const max = sorted[sorted.length - 1];
  const width = (max - min) / bins || 1;
  const counts = new Array(bins).fill(0);
  for (const value of values) {
    const index = clamp(Math.floor((value - min) / width), 0, bins - 1);
    counts[index] += 1;
  }
  return counts.map((count, index) => ({
    low: min + index * width,
    high: min + (index + 1) * width,
    count,
    probability: count / values.length,
  }));
}

export function buildForecastTable(forecast) {
  if (!forecast) return [];
  const start = forecast.start;
  return forecast.scenarios.map((scenario) => ({
    ...scenario,
    change: scenario.price - start,
  }));
}
