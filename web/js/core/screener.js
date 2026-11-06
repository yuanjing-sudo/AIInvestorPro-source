// Cross-sectional screener. Every metric is computed from the same candle map
// used by the dashboard so results are consistent and testable.

import { sma, rsi, atr, roc } from './indicators.js';
import { mean, stdev, percentileSorted, clamp } from './math.js';

export const DEFAULT_FILTERS = {
  sectors: [],
  minPrice: 0,
  maxPrice: Infinity,
  minAvgVolume: 0,
  minMomentum: -Infinity,
  maxMomentum: Infinity,
  minRsi: 0,
  maxRsi: 100,
  trendOnly: false,
  sortBy: 'score',
};

export function screenUniverse(candleMap, assets, filters = {}) {
  const config = { ...DEFAULT_FILTERS, ...filters };
  const rows = [];

  for (const asset of assets) {
    const candles = candleMap[asset.symbol];
    if (!candles || candles.length < 60) continue;
    const close = candles.map((c) => c.close);
    const high = candles.map((c) => c.high);
    const low = candles.map((c) => c.low);
    const volume = candles.map((c) => c.volume);
    const price = close[close.length - 1];
    const previous = close[close.length - 2] ?? price;
    const change = previous ? price / previous - 1 : 0;
    const fast = sma(close, 20);
    const slow = sma(close, 50);
    const rsiValues = rsi(close, 14);
    const atrValues = atr(high, low, close, 14);
    const momentum = roc(close, 63);
    const volumeWindow = volume.slice(-20);
    const averageVolume = mean(volumeWindow);
    const volumeRatio = averageVolume > 0 ? volume[volume.length - 1] / averageVolume : 0;
    const fastValue = fast[fast.length - 1];
    const slowValue = slow[slow.length - 1];
    const rsiValue = rsiValues[rsiValues.length - 1];
    const atrValue = atrValues[atrValues.length - 1];
    const momentumValue = momentum[momentum.length - 1];
    const trend = fastValue !== null && slowValue !== null && fastValue > slowValue;
    const aboveSlow = slowValue !== null && price > slowValue;
    const volatility = atrValue !== null ? atrValue / price : 0;

    rows.push({
      symbol: asset.symbol,
      name: asset.name,
      sector: asset.sector,
      price,
      change,
      rsi: rsiValue,
      momentum: momentumValue,
      trend,
      aboveSlow,
      volatility,
      averageVolume,
      volumeRatio,
      score: 0,
      reasons: [],
    });
  }

  // Rank-based scoring keeps the score comparable across regimes.
  const momentumRanks = ranks(rows.map((r) => r.momentum ?? 0));
  const volumeRanks = ranks(rows.map((r) => r.volumeRatio));
  const lowVolRanks = ranks(rows.map((r) => -r.volatility));
  rows.forEach((row, index) => {
    const trendScore = row.trend ? 1 : 0;
    const momentumScore = momentumRanks[index];
    const rsiScore = row.rsi === null ? 0.5 : 1 - Math.min(1, Math.abs(row.rsi - 55) / 45);
    const liquidityScore = volumeRanks[index];
    const volScore = lowVolRanks[index];
    row.score = 0.30 * trendScore + 0.30 * momentumScore + 0.15 * rsiScore
      + 0.10 * liquidityScore + 0.15 * volScore;
    if (row.trend) row.reasons.push('SMA20 > SMA50');
    if (row.aboveSlow) row.reasons.push('Price above SMA50');
    if (row.rsi !== null && row.rsi < 35) row.reasons.push('Oversold RSI');
    if (row.rsi !== null && row.rsi > 70) row.reasons.push('Overbought RSI');
    if ((row.momentum ?? 0) > 0.1) row.reasons.push('Strong momentum');
    if (row.volumeRatio > 1.5) row.reasons.push('Volume expansion');
  });

  const filtered = rows.filter((row) => {
    if (config.sectors.length && !config.sectors.includes(row.sector)) return false;
    if (row.price < config.minPrice || row.price > config.maxPrice) return false;
    if (row.averageVolume < config.minAvgVolume) return false;
    if ((row.momentum ?? -Infinity) < config.minMomentum) return false;
    if ((row.momentum ?? Infinity) > config.maxMomentum) return false;
    if ((row.rsi ?? 50) < config.minRsi || (row.rsi ?? 50) > config.maxRsi) return false;
    if (config.trendOnly && !row.trend) return false;
    return true;
  });

  const sorters = {
    score: (a, b) => b.score - a.score,
    momentum: (a, b) => (b.momentum ?? -Infinity) - (a.momentum ?? -Infinity),
    rsi: (a, b) => (a.rsi ?? 50) - (b.rsi ?? 50),
    change: (a, b) => b.change - a.change,
    symbol: (a, b) => a.symbol.localeCompare(b.symbol),
  };
  filtered.sort(sorters[config.sortBy] ?? sorters.score);
  return filtered;
}

function ranks(values) {
  if (values.length <= 1) return values.map(() => 0.5);
  const sorted = [...values].sort((a, b) => a - b);
  return values.map((value) => {
    const lower = sorted.filter((v) => v < value).length;
    return sorted.length > 1 ? lower / (sorted.length - 1) : 0.5;
  });
}

export function portfolioSignals(candleMap, symbols) {
  return symbols.map((symbol) => {
    const candles = candleMap[symbol] ?? [];
    if (candles.length < 60) return { symbol, score: 0, label: 'No data' };
    const close = candles.map((c) => c.close);
    const fast = sma(close, 20);
    const slow = sma(close, 50);
    const rsiValue = rsi(close, 14).at(-1);
    const momentum = roc(close, 63).at(-1);
    const trend = fast.at(-1) > slow.at(-1);
    const components = [
      trend ? 1 : 0,
      (momentum ?? 0) > 0 ? 1 : 0,
      rsiValue !== null && rsiValue > 45 && rsiValue < 70 ? 1 : 0,
      close.at(-1) > slow.at(-1) ? 1 : 0,
    ];
    const score = components.reduce((a, b) => a + b, 0) / components.length;
    return {
      symbol,
      score,
      label: score >= 0.75 ? 'Accumulate' : score >= 0.5 ? 'Neutral' : 'Defensive',
      rsi: rsiValue,
      momentum,
      trend,
    };
  });
}

export function percentileRank(values, target) {
  const sorted = [...values].sort((a, b) => a - b);
  const below = sorted.filter((v) => v < target).length;
  return sorted.length > 1 ? below / (sorted.length - 1) : 0.5;
}
