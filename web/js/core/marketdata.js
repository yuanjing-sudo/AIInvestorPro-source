// Deterministic synthetic market data. The browser app runs without network
// access and without an API key, so quotes are generated reproducibly from a
// symbol-seeded PRNG. The same generator feeds the Node tests.

import { SeededRandom, fnv1a, mean } from './math.js';

export const UNIVERSE = [
  { symbol: 'SPY', name: 'S&P 500 ETF', sector: 'Broad Market', start: 420, drift: 0.09, vol: 0.16 },
  { symbol: 'QQQ', name: 'Nasdaq 100 ETF', sector: 'Technology', start: 355, drift: 0.12, vol: 0.22 },
  { symbol: 'AAPL', name: 'Apple Inc.', sector: 'Technology', start: 170, drift: 0.10, vol: 0.24 },
  { symbol: 'MSFT', name: 'Microsoft Corp.', sector: 'Technology', start: 340, drift: 0.11, vol: 0.22 },
  { symbol: 'NVDA', name: 'NVIDIA Corp.', sector: 'Semiconductors', start: 480, drift: 0.20, vol: 0.42 },
  { symbol: 'AMZN', name: 'Amazon.com Inc.', sector: 'Consumer', start: 140, drift: 0.10, vol: 0.28 },
  { symbol: 'GOOGL', name: 'Alphabet Inc.', sector: 'Technology', start: 135, drift: 0.09, vol: 0.25 },
  { symbol: 'META', name: 'Meta Platforms', sector: 'Technology', start: 320, drift: 0.13, vol: 0.32 },
  { symbol: 'JPM', name: 'JPMorgan Chase', sector: 'Financials', start: 155, drift: 0.07, vol: 0.20 },
  { symbol: 'XOM', name: 'Exxon Mobil', sector: 'Energy', start: 105, drift: 0.05, vol: 0.24 },
  { symbol: 'JNJ', name: 'Johnson & Johnson', sector: 'Healthcare', start: 155, drift: 0.04, vol: 0.16 },
  { symbol: 'WMT', name: 'Walmart Inc.', sector: 'Consumer Staples', start: 150, drift: 0.08, vol: 0.18 },
  { symbol: 'TLT', name: '20+ Year Treasury Bond ETF', sector: 'Fixed Income', start: 95, drift: 0.01, vol: 0.14 },
  { symbol: 'GLD', name: 'SPDR Gold Shares', sector: 'Commodities', start: 185, drift: 0.06, vol: 0.15 },
  { symbol: 'BTC-USD', name: 'Bitcoin', sector: 'Digital Assets', start: 27000, drift: 0.25, vol: 0.55 },
];

const UNIVERSE_MAP = new Map(UNIVERSE.map((entry) => [entry.symbol, entry]));

export function findAsset(symbol) {
  return UNIVERSE_MAP.get(symbol.toUpperCase()) ?? null;
}

function isoDate(date) {
  return date.toISOString().slice(0, 10);
}

function seedFor(symbol) {
  return fnv1a(`investor-kit:${symbol.toUpperCase()}`);
}

export function generateCandles(symbol, options = {}) {
  const asset = findAsset(symbol) ?? {
    symbol: symbol.toUpperCase(),
    name: symbol.toUpperCase(),
    sector: 'Custom',
    start: 100 + (Number(seedFor(symbol) % 200n)),
    drift: 0.08,
    vol: 0.28,
  };
  const count = options.count ?? 504;
  const endDate = options.endDate ? new Date(options.endDate) : new Date();
  const rng = new SeededRandom(seedFor(asset.symbol));
  const drift = options.drift ?? asset.drift;
  const vol = options.vol ?? asset.vol;
  const dt = 1 / 252;

  const dates = [];
  const cursor = new Date(Date.UTC(endDate.getUTCFullYear(), endDate.getUTCMonth(), endDate.getUTCDate()));
  while (dates.length < count) {
    const day = cursor.getUTCDay();
    if (day !== 0 && day !== 6) dates.unshift(new Date(cursor));
    cursor.setUTCDate(cursor.getUTCDate() - 1);
  }

  let previousClose = asset.start;
  const candles = dates.map((date, index) => {
    const cycle = 1 + 0.02 * Math.sin((index / 47) * Math.PI * 2);
    const shock = rng.gaussian();
    const open = previousClose * (1 + 0.0004 * rng.gaussian());
    const close = open * Math.exp((drift - 0.5 * vol * vol) * dt + vol * Math.sqrt(dt) * shock);
    const range = Math.abs(close - open) + open * vol * Math.sqrt(dt) * (0.4 + 0.6 * rng.next());
    const high = Math.max(open, close) + range * 0.45;
    const low = Math.max(0.01, Math.min(open, close) - range * 0.45);
    const volume = Math.round((1_000_000 + 8_000_000 * rng.next()) * cycle * (1 + Math.abs(shock) * 0.15));
    const candle = {
      date,
      dateString: isoDate(date),
      open: round(open),
      high: round(high),
      low: round(low),
      close: round(close),
      volume,
    };
    previousClose = close;
    return candle;
  });

  return { asset, candles };
}

function round(value) {
  return Math.round(value * 100) / 100;
}

export function quotesFromCandles(candles) {
  if (!candles.length) return null;
  const last = candles[candles.length - 1];
  const previous = candles.length > 1 ? candles[candles.length - 2] : last;
  const change = last.close - previous.close;
  return {
    price: last.close,
    previousClose: previous.close,
    change,
    changePercent: previous.close ? (change / previous.close) * 100 : 0,
    high: last.high,
    low: last.low,
    volume: last.volume,
    asOf: last.date,
  };
}

export function returnsFromCandles(candles) {
  const out = [];
  for (let i = 1; i < candles.length; i += 1) {
    const previous = candles[i - 1].close;
    out.push(previous ? candles[i].close / previous - 1 : 0);
  }
  return out;
}

export function alignedReturns(candleMap, symbols) {
  const series = symbols.map((symbol) => returnsFromCandles(candleMap[symbol]));
  const n = Math.min(...series.map((s) => s.length));
  return series.map((s) => s.slice(s.length - n));
}

export function averageVolume(candles, period = 20) {
  const window = candles.slice(-period).map((c) => c.volume);
  return mean(window);
}

export function marketSnapshot(count = 504) {
  const candleMap = {};
  const quotes = {};
  for (const asset of UNIVERSE) {
    const { candles } = generateCandles(asset.symbol, { count });
    candleMap[asset.symbol] = candles;
    quotes[asset.symbol] = quotesFromCandles(candles);
  }
  return { candleMap, quotes, assets: UNIVERSE };
}
