// Deterministic synthetic market data. The browser app runs without network
// access and without an API key, so quotes are generated reproducibly from a
// symbol-seeded PRNG. The same generator feeds the Node tests.

import { SeededRandom, fnv1a, mean, stdev, percentileSorted } from './math.js';

export const UNIVERSE = [
  { symbol: 'SPY', name: 'S&P 500 ETF', sector: 'Broad Market', kind: 'etf', start: 420, drift: 0.09, vol: 0.16, expenseRatio: 0.0945, aum: 512e9 },
  { symbol: 'QQQ', name: 'Nasdaq 100 ETF', sector: 'Technology', kind: 'etf', start: 355, drift: 0.12, vol: 0.22, expenseRatio: 0.2, aum: 268e9 },
  { symbol: 'IWM', name: 'Russell 2000 ETF', sector: 'Broad Market', kind: 'etf', start: 190, drift: 0.07, vol: 0.23, expenseRatio: 0.19, aum: 62e9 },
  { symbol: 'EEM', name: 'Emerging Markets ETF', sector: 'International', kind: 'etf', start: 39, drift: 0.05, vol: 0.21, expenseRatio: 0.57, aum: 18e9 },
  { symbol: 'AAPL', name: 'Apple Inc.', sector: 'Technology', kind: 'equity', start: 170, drift: 0.10, vol: 0.24, employees: 164000 },
  { symbol: 'MSFT', name: 'Microsoft Corp.', sector: 'Technology', kind: 'equity', start: 340, drift: 0.11, vol: 0.22, employees: 228000 },
  { symbol: 'NVDA', name: 'NVIDIA Corp.', sector: 'Semiconductors', kind: 'equity', start: 480, drift: 0.20, vol: 0.42, employees: 29600 },
  { symbol: 'AMD', name: 'Advanced Micro Devices', sector: 'Semiconductors', kind: 'equity', start: 120, drift: 0.14, vol: 0.40, employees: 26000 },
  { symbol: 'AVGO', name: 'Broadcom Inc.', sector: 'Semiconductors', kind: 'equity', start: 620, drift: 0.15, vol: 0.30, employees: 20000 },
  { symbol: 'AMZN', name: 'Amazon.com Inc.', sector: 'Consumer', kind: 'equity', start: 140, drift: 0.10, vol: 0.28, employees: 1525000 },
  { symbol: 'GOOGL', name: 'Alphabet Inc.', sector: 'Technology', kind: 'equity', start: 135, drift: 0.09, vol: 0.25, employees: 182000 },
  { symbol: 'META', name: 'Meta Platforms', sector: 'Technology', kind: 'equity', start: 320, drift: 0.13, vol: 0.32, employees: 67300 },
  { symbol: 'TSLA', name: 'Tesla Inc.', sector: 'Consumer', kind: 'equity', start: 240, drift: 0.12, vol: 0.48, employees: 140000 },
  { symbol: 'JPM', name: 'JPMorgan Chase', sector: 'Financials', kind: 'equity', start: 155, drift: 0.07, vol: 0.20, employees: 309000 },
  { symbol: 'V', name: 'Visa Inc.', sector: 'Financials', kind: 'equity', start: 245, drift: 0.09, vol: 0.19, employees: 31600 },
  { symbol: 'XOM', name: 'Exxon Mobil', sector: 'Energy', kind: 'equity', start: 105, drift: 0.05, vol: 0.24, employees: 62000 },
  { symbol: 'SLB', name: 'SLB', sector: 'Energy', kind: 'equity', start: 48, drift: 0.04, vol: 0.30, employees: 111000 },
  { symbol: 'JNJ', name: 'Johnson & Johnson', sector: 'Healthcare', kind: 'equity', start: 155, drift: 0.04, vol: 0.16, employees: 131900 },
  { symbol: 'UNH', name: 'UnitedHealth Group', sector: 'Healthcare', kind: 'equity', start: 510, drift: 0.08, vol: 0.22, employees: 400000 },
  { symbol: 'WMT', name: 'Walmart Inc.', sector: 'Consumer Staples', kind: 'equity', start: 150, drift: 0.08, vol: 0.18, employees: 2100000 },
  { symbol: 'HD', name: 'Home Depot', sector: 'Consumer', kind: 'equity', start: 320, drift: 0.07, vol: 0.21, employees: 465000 },
  { symbol: 'PG', name: 'Procter & Gamble', sector: 'Consumer Staples', kind: 'equity', start: 150, drift: 0.05, vol: 0.15, employees: 108000 },
  { symbol: 'NEE', name: 'NextEra Energy', sector: 'Utilities', kind: 'equity', start: 72, drift: 0.06, vol: 0.20, employees: 14700 },
  { symbol: 'TLT', name: '20+ Year Treasury Bond ETF', sector: 'Fixed Income', kind: 'etf', start: 95, drift: 0.01, vol: 0.14, expenseRatio: 0.15, aum: 48e9 },
  { symbol: 'GLD', name: 'SPDR Gold Shares', sector: 'Commodities', kind: 'etf', start: 185, drift: 0.06, vol: 0.15, expenseRatio: 0.4, aum: 64e9 },
  { symbol: 'BTC-USD', name: 'Bitcoin', sector: 'Digital Assets', kind: 'crypto', start: 27000, drift: 0.25, vol: 0.55 },
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

function seeded(symbol, salt) {
  return new SeededRandom(fnv1a(`investor-kit:${salt}:${symbol.toUpperCase()}`));
}

export function generateCandles(symbol, options = {}) {
  const asset = findAsset(symbol) ?? {
    symbol: symbol.toUpperCase(),
    name: symbol.toUpperCase(),
    sector: 'Custom',
    kind: 'equity',
    start: 100 + (Number(seedFor(symbol) % 200n)),
    drift: 0.08,
    vol: 0.28,
  };
  const count = options.count ?? 756;
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
    // A slow business cycle plus a shorter earnings rhythm, both deterministic.
    const cycle = 1 + 0.025 * Math.sin((index / 63) * Math.PI * 2)
      + 0.012 * Math.sin((index / 17) * Math.PI * 2 + 0.7);
    const shock = rng.gaussian();
    const open = previousClose * (1 + 0.0004 * rng.gaussian());
    const close = open * Math.exp((drift - 0.5 * vol * vol) * dt + vol * Math.sqrt(dt) * shock);
    const range = Math.abs(close - open) + open * vol * Math.sqrt(dt) * (0.4 + 0.6 * rng.next());
    const high = Math.max(open, close) + range * 0.45;
    const low = Math.max(0.01, Math.min(open, close) - range * 0.45);
    const volume = Math.round((1_000_000 + 8_000_000 * rng.next()) * Math.max(0.35, cycle) * (1 + Math.abs(shock) * 0.15));
    const candle = {
      date,
      dateString: isoDate(date),
      open: round(open),
      high: round(high),
      low: round(low),
      close: round(close),
      volume,
      vwap: round((high + low + close) / 3),
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
    open: last.open,
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

export function logReturnsFromCandles(candles) {
  const out = [];
  for (let i = 1; i < candles.length; i += 1) {
    const previous = candles[i - 1].close;
    out.push(previous > 0 && candles[i].close > 0 ? Math.log(candles[i].close / previous) : 0);
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

// ---------------------------------------------------------------------------
// Fundamental, macro and news "data lines"
// ---------------------------------------------------------------------------

const ANALYST_LABELS = ['Strong Buy', 'Buy', 'Hold', 'Buy', 'Strong Buy', 'Hold'];

export function fundamentalsFor(symbol) {
  const asset = findAsset(symbol);
  if (!asset) return null;
  const rng = seeded(asset.symbol, 'fundamentals');
  const price = asset.start;
  const isEquity = asset.kind === 'equity';
  const isEtf = asset.kind === 'etf';
  const isCrypto = asset.kind === 'crypto';
  const shares = isEquity ? 0.4e9 + rng.next() * 12e9 : null;
  const marketCap = isCrypto
    ? price * (19e6 + rng.next() * 1.2e6)
    : isEquity
      ? price * shares
      : asset.aum ?? price * 1e8;
  const pe = isEquity ? 11 + rng.next() * 34 : null;
  const eps = isEquity ? price / pe : null;
  const dividendYield = isEquity
    ? (asset.sector === 'Technology' ? 0.001 + rng.next() * 0.012 : 0.012 + rng.next() * 0.032)
    : isEtf ? (asset.sector === 'Fixed Income' ? 0.038 : 0.011 + rng.next() * 0.018) : 0;
  const beta = asset.kind === 'crypto' ? 1.75 : 0.55 + rng.next() * 0.9;
  const target = price * (0.9 + rng.next() * 0.35);
  const rating = ANALYST_LABELS[Math.floor(rng.next() * ANALYST_LABELS.length)];
  return {
    symbol: asset.symbol,
    kind: asset.kind,
    marketCap,
    enterpriseValue: marketCap * (1 + rng.next() * 0.25),
    sharesOutstanding: shares,
    pe,
    forwardPE: isEquity ? pe * (0.78 + rng.next() * 0.18) : null,
    peg: isEquity ? 0.8 + rng.next() * 2.2 : null,
    priceToSales: isEquity ? 1.4 + rng.next() * 11 : null,
    priceToBook: isEquity ? 1.1 + rng.next() * 14 : null,
    eps,
    revenueGrowth: isEquity ? -0.03 + rng.next() * 0.34 : null,
    earningsGrowth: isEquity ? -0.08 + rng.next() * 0.46 : null,
    grossMargin: isEquity ? 0.22 + rng.next() * 0.58 : null,
    operatingMargin: isEquity ? 0.05 + rng.next() * 0.36 : null,
    profitMargin: isEquity ? 0.03 + rng.next() * 0.31 : null,
    returnOnEquity: isEquity ? 0.04 + rng.next() * 0.42 : null,
    debtToEquity: isEquity ? 0.1 + rng.next() * 2.4 : null,
    currentRatio: isEquity ? 0.8 + rng.next() * 2.2 : null,
    dividendYield,
    payoutRatio: isEquity ? 0.08 + rng.next() * 0.55 : null,
    beta,
    analystRating: rating,
    analystTarget: target,
    analystUpside: target / price - 1,
    analystCount: 8 + Math.floor(rng.next() * 32),
    expenseRatio: isEtf ? asset.expenseRatio : null,
    aum: isEtf ? asset.aum : null,
    employees: asset.employees ?? null,
    nextEarnings: null,
    fiscalYearEnd: isEquity ? 'December' : null,
    asOf: null,
  };
}

export function macroSnapshot(spyCandles = null, asOf = null) {
  const candles = spyCandles && spyCandles.length ? spyCandles : [];
  const lastDate = asOf ?? candles.at(-1)?.date ?? new Date();
  const date = lastDate instanceof Date ? lastDate : new Date(lastDate);
  const window = candles.slice(-21).map((candle) => candle.close);
  let volatility = 0.16;
  if (window.length > 2) {
    const returns = [];
    for (let i = 1; i < window.length; i += 1) returns.push(window[i] / window[i - 1] - 1);
    volatility = stdev(returns) * Math.sqrt(252);
  }
  const vix = Math.max(9, Math.min(48, volatility * 100 * 1.12));
  return {
    asOf: date,
    regime: vix > 28 ? 'Risk-off' : vix > 21 ? 'Cautious' : 'Risk-on',
    riskFreeRate: 0.043,
    inflation: 0.031,
    gdpGrowth: 0.021,
    unemployment: 0.041,
    yield10y: 0.044,
    yield2y: 0.047,
    yieldCurve: -0.003,
    vix,
    dollarIndex: 104.2,
    oil: 78.4,
    creditSpread: 1.12,
    financialConditions: 'Neutral',
    liquidity: volatility > 0.22 ? 'Tightening' : 'Stable',
    breadth: 0.58,
    putCall: 0.92,
  };
}

const NEWS_TEMPLATES = [
  { headline: (a) => `${a.name} beats quarterly expectations as margins expand`, sentiment: 0.62, impact: 'high', category: 'Earnings' },
  { headline: (a) => `Analysts raise ${a.symbol} price target after demand update`, sentiment: 0.45, impact: 'medium', category: 'Analyst' },
  { headline: (a) => `${a.sector} rotation pressures ${a.symbol} despite solid fundamentals`, sentiment: -0.28, impact: 'medium', category: 'Flows' },
  { headline: (a) => `${a.symbol} options activity builds ahead of macro print`, sentiment: 0.08, impact: 'low', category: 'Derivatives' },
  { headline: (a) => `Institutional ownership in ${a.symbol} edges higher`, sentiment: 0.33, impact: 'low', category: 'Ownership' },
  { headline: (a) => `Supply-chain commentary clouds ${a.sector} outlook`, sentiment: -0.36, impact: 'medium', category: 'Macro' },
  { headline: (a) => `${a.symbol} volume expands above its 20-day average`, sentiment: 0.18, impact: 'low', category: 'Technical' },
  { headline: (a) => `Regulatory review adds uncertainty for ${a.name}`, sentiment: -0.52, impact: 'high', category: 'Regulatory' },
];

const NEWS_SOURCES = ['Market Wire', 'Capital Desk', 'Global Ticker', 'Street Signal', 'Macro Brief'];

export function newsFor(symbol, asOf = null) {
  const asset = findAsset(symbol);
  if (!asset) return [];
  const rng = seeded(asset.symbol, 'news');
  const anchor = asOf instanceof Date ? asOf : asOf ? new Date(asOf) : null;
  const count = 4 + Math.floor(rng.next() * 3);
  const picks = [];
  const used = new Set();
  while (picks.length < count) {
    const index = Math.floor(rng.next() * NEWS_TEMPLATES.length);
    if (used.has(index)) continue;
    used.add(index);
    picks.push(index);
  }
  return picks.map((index, offset) => {
    const template = NEWS_TEMPLATES[index];
    const base = anchor ? new Date(anchor) : new Date();
    base.setUTCDate(base.getUTCDate() - offset * 2 - Math.floor(rng.next() * 2));
    return {
      id: `${asset.symbol}-news-${offset}`,
      symbol: asset.symbol,
      headline: template.headline(asset),
      sentiment: template.sentiment + (rng.next() - 0.5) * 0.12,
      impact: template.impact,
      category: template.category,
      source: NEWS_SOURCES[Math.floor(rng.next() * NEWS_SOURCES.length)],
      date: base,
    };
  });
}

export function sentimentSummary(items) {
  if (!items.length) return { score: 0, label: 'Neutral', positive: 0, negative: 0, neutral: 0 };
  const score = mean(items.map((item) => item.sentiment));
  return {
    score,
    label: score > 0.25 ? 'Bullish' : score < -0.25 ? 'Bearish' : 'Neutral',
    positive: items.filter((item) => item.sentiment > 0.15).length,
    negative: items.filter((item) => item.sentiment < -0.15).length,
    neutral: items.filter((item) => Math.abs(item.sentiment) <= 0.15).length,
  };
}

export function dataQuality(candles, synthetic = true) {
  if (!candles.length) {
    return {
      rows: 0, first: null, last: null, spanYears: 0, missing: 0, duplicates: 0,
      gaps: 0, completeness: 0, synthetic, barsPerYear: 0,
    };
  }
  const first = candles[0].date;
  const last = candles[candles.length - 1].date;
  const firstDate = first instanceof Date ? first : new Date(first);
  const lastDate = last instanceof Date ? last : new Date(last);
  const spanYears = (lastDate - firstDate) / (365.25 * 24 * 3600 * 1000);
  let missing = 0;
  let duplicates = 0;
  let gaps = 0;
  const seen = new Set();
  for (let i = 0; i < candles.length; i += 1) {
    const candle = candles[i];
    for (const key of ['open', 'high', 'low', 'close', 'volume']) {
      if (!Number.isFinite(candle[key])) missing += 1;
    }
    const key = candle.dateString ?? isoDate(candle.date);
    if (seen.has(key)) duplicates += 1;
    seen.add(key);
    if (i > 0) {
      const previous = candles[i - 1].date;
      const currentDate = candle.date instanceof Date ? candle.date : new Date(candle.date);
      const previousDate = previous instanceof Date ? previous : new Date(previous);
      const days = (currentDate - previousDate) / 86_400_000;
      if (days > 5) gaps += 1;
    }
  }
  const expected = candles.length * 5;
  const completeness = expected ? Math.max(0, 1 - missing / expected) : 0;
  return {
    rows: candles.length,
    first: first instanceof Date ? first : new Date(first),
    last: last instanceof Date ? last : new Date(last),
    spanYears,
    missing,
    duplicates,
    gaps,
    completeness,
    synthetic,
    barsPerYear: spanYears > 0 ? candles.length / spanYears : 0,
  };
}

const PERFORMANCE_WINDOWS = [
  { key: '1D', bars: 1 },
  { key: '1W', bars: 5 },
  { key: '1M', bars: 21 },
  { key: '3M', bars: 63 },
  { key: '6M', bars: 126 },
  { key: '1Y', bars: 252 },
  { key: '2Y', bars: 504 },
];

export function performanceWindows(candles) {
  if (!candles.length) return [];
  const last = candles[candles.length - 1];
  const lastClose = last.close;
  const lastDate = last.date instanceof Date ? last.date : new Date(last.date);
  const yearStart = new Date(Date.UTC(lastDate.getUTCFullYear(), 0, 1));
  const dateOf = (candle) => (candle.date instanceof Date ? candle.date : new Date(candle.date));
  return PERFORMANCE_WINDOWS.map(({ key, bars }) => {
    const reference = candles[Math.max(0, candles.length - 1 - bars)];
    const value = reference && reference.close > 0 ? lastClose / reference.close - 1 : 0;
    return { key, bars, value };
  }).concat({
    key: 'YTD',
    bars: candles.findIndex((candle) => dateOf(candle) >= yearStart),
    value: (() => {
      const reference = candles.find((candle) => dateOf(candle) >= yearStart);
      return reference && reference.close > 0 ? lastClose / reference.close - 1 : 0;
    })(),
  });
}

export function drawdownSeriesFromCandles(candles) {
  let peak = candles.length ? candles[0].close : 0;
  return candles.map((candle) => {
    peak = Math.max(peak, candle.close);
    return peak > 0 ? candle.close / peak - 1 : 0;
  });
}

export function historicalVolatility(candles, window = 21) {
  const closes = candles.slice(-window - 1).map((candle) => candle.close);
  if (closes.length < 3) return 0;
  const returns = [];
  for (let i = 1; i < closes.length; i += 1) returns.push(closes[i] / closes[i - 1] - 1);
  return stdev(returns) * Math.sqrt(252);
}

export function pricePercentile(candles, window = 252) {
  const values = candles.slice(-window).map((candle) => candle.close);
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  return percentileSorted(sorted, 0.5) > 0
    ? (values[values.length - 1] - sorted[0]) / (sorted[sorted.length - 1] - sorted[0] || 1)
    : 0;
}

export function marketSnapshot(count = 756) {
  const candleMap = {};
  const quotes = {};
  const fundamentals = {};
  const news = {};
  const quality = {};
  for (const asset of UNIVERSE) {
    const { candles } = generateCandles(asset.symbol, { count });
    candleMap[asset.symbol] = candles;
    quotes[asset.symbol] = quotesFromCandles(candles);
    fundamentals[asset.symbol] = fundamentalsFor(asset.symbol);
    news[asset.symbol] = newsFor(asset.symbol, candles.at(-1)?.date ?? null);
    quality[asset.symbol] = dataQuality(candles);
  }
  return {
    candleMap,
    quotes,
    assets: UNIVERSE,
    fundamentals,
    news,
    quality,
    macro: macroSnapshot(candleMap.SPY),
  };
}
