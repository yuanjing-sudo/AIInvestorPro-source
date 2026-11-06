// Event-driven, next-open backtester. Signals are computed from closes and
// executed at the following bar's open, with commission and slippage applied.

import { analyzeReturns, tradingMetrics } from './analytics.js';
import { clamp } from './math.js';

export function runBacktest(candles, signals, options = {}) {
  if (!candles.length) throw new Error('candles are required');
  const initialCapital = options.initialCapital ?? 100000;
  const commissionRate = (options.commissionBps ?? 5) / 10000;
  const slippageRate = (options.slippageBps ?? 2) / 10000;
  const fraction = clamp(options.fraction ?? 1, 0.01, 1);

  let cash = initialCapital;
  let shares = 0;
  let entry = null;
  let totalCommission = 0;
  const trades = [];
  const equity = [];
  const exposure = [];
  const positionValues = [];

  const buyPrice = (raw) => raw * (1 + slippageRate);
  const sellPrice = (raw) => raw * (1 - slippageRate);

  const enter = (index, rawPrice) => {
    const price = buyPrice(rawPrice);
    const budget = cash * fraction;
    const quantity = budget / (price * (1 + commissionRate));
    if (quantity <= 0) return;
    const notional = quantity * price;
    const commission = notional * commissionRate;
    cash -= notional + commission;
    shares = quantity;
    totalCommission += commission;
    entry = {
      index,
      date: candles[index].date,
      price,
      quantity,
      cost: notional + commission,
      commission,
    };
  };

  const exit = (index, rawPrice, reason) => {
    if (shares <= 0 || !entry) return;
    const price = sellPrice(rawPrice);
    const notional = shares * price;
    const commission = notional * commissionRate;
    cash += notional - commission;
    totalCommission += commission;
    const pnl = notional - commission - entry.cost;
    trades.push({
      entryDate: entry.date,
      exitDate: candles[index].date,
      entryIndex: entry.index,
      exitIndex: index,
      entryPrice: entry.price,
      exitPrice: price,
      quantity: shares,
      side: 'SELL',
      pnl,
      returnPct: entry.cost > 0 ? pnl / entry.cost : 0,
      bars: index - entry.index,
      reason,
      commission: entry.commission + commission,
    });
    shares = 0;
    entry = null;
  };

  for (let i = 0; i < candles.length; i += 1) {
    const price = candles[i].open;
    if (i > 0) {
      const desired = signals[i - 1] ? 1 : 0;
      if (desired === 1 && shares === 0) enter(i, price);
      else if (desired === 0 && shares > 0) exit(i, price, 'signal');
    }
    const value = cash + shares * candles[i].close;
    equity.push(value);
    exposure.push(shares > 0 ? 1 : 0);
    positionValues.push(shares * candles[i].close);
  }

  // Liquidate any open position at the final close so trade statistics are
  // complete. The equity curve's last point reflects the exit costs.
  if (shares > 0) {
    exit(candles.length - 1, candles[candles.length - 1].close, 'end');
    equity[equity.length - 1] = cash;
  }

  const returns = [];
  for (let i = 1; i < equity.length; i += 1) {
    returns.push(equity[i - 1] ? equity[i] / equity[i - 1] - 1 : 0);
  }
  const metrics = analyzeReturns(returns, {
    periodsPerYear: options.periodsPerYear ?? 252,
    riskFree: options.riskFree ?? 0.02,
  });
  const benchmark = benchmarkCurve(candles, initialCapital, commissionRate, slippageRate);
  const benchmarkMetrics = benchmark.metrics;
  const tradeStats = tradingMetrics(trades);
  const timeInMarket = exposure.length
    ? exposure.reduce((a, b) => a + b, 0) / exposure.length
    : 0;

  return {
    initialCapital,
    finalValue: equity[equity.length - 1] ?? initialCapital,
    totalReturn: metrics.totalReturn,
    cagr: metrics.cagr,
    volatility: metrics.volatility,
    sharpe: metrics.sharpe,
    sortino: metrics.sortino,
    maxDrawdown: metrics.maxDrawdown,
    calmar: metrics.calmar,
    var95: metrics.var95,
    cvar95: metrics.cvar95,
    winRate: metrics.winRate,
    profitFactor: metrics.profitFactor,
    trades,
    tradeStats,
    totalCommission,
    timeInMarket,
    exposure,
    positionValues,
    equity,
    drawdown: metrics.drawdown,
    benchmark: benchmark.equity,
    benchmarkMetrics,
    alpha: metrics.totalReturn - benchmarkMetrics.totalReturn,
    dates: candles.map((c) => c.date),
    returns,
    metrics,
  };
}

export function benchmarkCurve(candles, initialCapital = 100000, commissionRate = 0.0005, slippageRate = 0.0002) {
  if (!candles.length) return { equity: [], metrics: analyzeReturns([]) };
  const entryPrice = candles[0].open * (1 + slippageRate);
  const quantity = initialCapital / (entryPrice * (1 + commissionRate));
  const cost = quantity * entryPrice * (1 + commissionRate);
  const leftover = initialCapital - cost;
  const equity = candles.map((c) => leftover + quantity * c.close);
  const exitPrice = candles[candles.length - 1].close * (1 - slippageRate);
  equity[equity.length - 1] = leftover + quantity * exitPrice * (1 - commissionRate);
  const returns = [];
  for (let i = 1; i < equity.length; i += 1) {
    returns.push(equity[i - 1] ? equity[i] / equity[i - 1] - 1 : 0);
  }
  return { equity, metrics: analyzeReturns(returns) };
}
