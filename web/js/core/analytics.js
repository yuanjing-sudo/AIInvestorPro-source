// Performance analytics. Inputs are periodic simple returns unless noted.

import { mean, stdev, percentile } from './math.js';

export function equityFromReturns(returns, initial = 1) {
  const equity = [initial];
  for (const r of returns) equity.push(equity[equity.length - 1] * (1 + r));
  return equity;
}

export function returnsFromEquity(equity) {
  const out = [];
  for (let i = 1; i < equity.length; i += 1) {
    const previous = equity[i - 1];
    out.push(previous ? equity[i] / previous - 1 : 0);
  }
  return out;
}

export function drawdownSeries(equity) {
  let peak = equity.length ? equity[0] : 0;
  return equity.map((value) => {
    peak = Math.max(peak, value);
    return peak > 0 ? value / peak - 1 : 0;
  });
}

export function maxDrawdown(equity) {
  const series = drawdownSeries(equity);
  return series.length ? Math.min(...series) : 0;
}

export function analyzeReturns(returns, options = {}) {
  const periodsPerYear = options.periodsPerYear ?? 252;
  const riskFree = options.riskFree ?? 0.02;
  const clean = returns.filter((r) => Number.isFinite(r));
  if (!clean.length) {
    return emptyMetrics();
  }
  const equity = equityFromReturns(clean);
  const totalReturn = equity[equity.length - 1] - 1;
  const years = clean.length / periodsPerYear;
  const cagr = years > 0 && equity[equity.length - 1] > 0
    ? Math.pow(equity[equity.length - 1], 1 / years) - 1
    : 0;
  const volatility = stdev(clean) * Math.sqrt(periodsPerYear);
  const downside = clean.filter((r) => r < 0);
  const downsideDeviation = downside.length
    ? Math.sqrt(downside.reduce((acc, r) => acc + r * r, 0) / clean.length) * Math.sqrt(periodsPerYear)
    : 0;
  const average = mean(clean);
  const annualizedReturn = average * periodsPerYear;
  const sharpe = volatility > 0 ? (annualizedReturn - riskFree) / volatility : 0;
  const sortino = downsideDeviation > 0 ? (annualizedReturn - riskFree) / downsideDeviation : 0;
  const maxDd = maxDrawdown(equity);
  const calmar = maxDd < 0 ? cagr / Math.abs(maxDd) : 0;

  const sorted = [...clean].sort((a, b) => a - b);
  const var95 = -percentile(sorted, 0.05);
  const var99 = -percentile(sorted, 0.01);
  const cutoff = percentile(sorted, 0.05);
  const tail = sorted.filter((r) => r <= cutoff);
  const cvar95 = tail.length ? -mean(tail) : var95;

  const wins = clean.filter((r) => r > 0);
  const losses = clean.filter((r) => r < 0);
  const grossProfit = wins.reduce((a, b) => a + b, 0);
  const grossLoss = Math.abs(losses.reduce((a, b) => a + b, 0));
  const mu = mean(clean);
  const sigma = stdev(clean);
  const skewness = sigma > 0
    ? clean.reduce((acc, r) => acc + ((r - mu) / sigma) ** 3, 0) / clean.length
    : 0;
  const kurtosis = sigma > 0
    ? clean.reduce((acc, r) => acc + ((r - mu) / sigma) ** 4, 0) / clean.length - 3
    : 0;
  const positiveDays = clean.filter((r) => r > 0).length;
  const negativeDays = clean.filter((r) => r < 0).length;
  const flatDays = clean.length - positiveDays - negativeDays;
  const winRate = clean.length ? positiveDays / clean.length : 0;
  const profitFactor = grossLoss > 0 ? grossProfit / grossLoss : grossProfit > 0 ? Infinity : 0;
  const ulcer = Math.sqrt(mean(drawdownSeries(equity).map((d) => d * d)));

  return {
    observations: clean.length,
    totalReturn,
    cagr,
    annualizedReturn,
    volatility,
    sharpe,
    sortino,
    maxDrawdown: maxDd,
    calmar,
    var95,
    var99,
    cvar95,
    best: sorted[sorted.length - 1] ?? 0,
    worst: sorted[0] ?? 0,
    winRate,
    profitFactor,
    skewness,
    kurtosis,
    ulcer,
    positiveDays,
    negativeDays,
    flatDays,
    equity,
    drawdown: drawdownSeries(equity),
  };
}

export function emptyMetrics() {
  return {
    observations: 0,
    totalReturn: 0,
    cagr: 0,
    annualizedReturn: 0,
    volatility: 0,
    sharpe: 0,
    sortino: 0,
    maxDrawdown: 0,
    calmar: 0,
    var95: 0,
    var99: 0,
    cvar95: 0,
    best: 0,
    worst: 0,
    winRate: 0,
    profitFactor: 0,
    skewness: 0,
    kurtosis: 0,
    ulcer: 0,
    positiveDays: 0,
    negativeDays: 0,
    flatDays: 0,
    equity: [1],
    drawdown: [0],
  };
}

export function rollingSharpe(returns, window = 63, riskFree = 0.02, periodsPerYear = 252) {
  const out = new Array(returns.length).fill(null);
  for (let i = window - 1; i < returns.length; i += 1) {
    const slice = returns.slice(i - window + 1, i + 1);
    const sigma = stdev(slice) * Math.sqrt(periodsPerYear);
    out[i] = sigma > 0 ? (mean(slice) * periodsPerYear - riskFree) / sigma : 0;
  }
  return out;
}

export function tradingMetrics(trades) {
  const closed = trades.filter((t) => t.side === 'SELL' && Number.isFinite(t.pnl));
  if (!closed.length) {
    return { trades: 0, wins: 0, losses: 0, winRate: 0, profitFactor: 0, averageWin: 0, averageLoss: 0, expectancy: 0 };
  }
  const wins = closed.filter((t) => t.pnl > 0);
  const losses = closed.filter((t) => t.pnl < 0);
  const grossProfit = wins.reduce((a, t) => a + t.pnl, 0);
  const grossLoss = Math.abs(losses.reduce((a, t) => a + t.pnl, 0));
  return {
    trades: closed.length,
    wins: wins.length,
    losses: losses.length,
    winRate: wins.length / closed.length,
    profitFactor: grossLoss > 0 ? grossProfit / grossLoss : grossProfit > 0 ? Infinity : 0,
    averageWin: wins.length ? grossProfit / wins.length : 0,
    averageLoss: losses.length ? grossLoss / losses.length : 0,
    expectancy: mean(closed.map((t) => t.pnl)),
  };
}
