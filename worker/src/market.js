// Server-side market service. Equities and ETFs use Yahoo Finance; crypto uses
// Coinbase first with CoinGecko, DefiLlama, optional keyed providers and Yahoo
// as fallbacks. Every failure degrades to the deterministic demo feed so the
// API never fails hard. Shared analytics modules are imported directly from the
// web app so the browser and Worker use exactly the same maths.

import {
  UNIVERSE, generateCandles, fundamentalsFor, newsFor, macroSnapshot,
  dataQuality, quotesFromCandles, findAsset, sentimentSummary,
} from '../../web/js/core/marketdata.js';
import { buildForecast } from '../../web/js/core/forecast.js';
import { fetchYahooChart, normalizeSymbol } from './yahoo.js';
import { fetchSecProfile } from './sec.js';
import { fetchYahooNews } from './search.js';
import { fetchCoinbaseChart } from './coinbase.js';
import { fetchCoinGeckoChart } from './coingecko.js';
import { fetchDefiLlamaChart } from './defillama.js';
import { fetchCoinCapChart } from './coincap.js';
import { fetchCoinMarketCapChart } from './coinmarketcap.js';
import { fetchFredSeries, latestValue, yearOverYear } from './fred.js';

export const ALLOWED_SYMBOLS = UNIVERSE.map((asset) => asset.symbol);

const SOURCE_NAMES = {
  coinbase: 'Coinbase Exchange',
  coingecko: 'CoinGecko',
  defillama: 'DefiLlama',
  coincap: 'CoinCap',
  coinmarketcap: 'CoinMarketCap',
  fred: 'FRED',
  yahoo: 'Yahoo Finance',
  'yahoo-news': 'Yahoo Finance news',
  sec: 'SEC EDGAR',
  synthetic: 'Deterministic fallback',
};

export const SOURCE_CATALOG = [
  {
    id: 'coinbase', name: 'Coinbase Exchange', coverage: ['crypto'], kind: 'market',
    requiresKey: false, status: 'active', role: 'primary',
    note: 'Daily OHLCV candles. Long ranges are fetched in 300-candle chunks.',
  },
  {
    id: 'coingecko', name: 'CoinGecko', coverage: ['crypto'], kind: 'market',
    requiresKey: false, status: 'active', role: 'fallback',
    note: 'Free public market chart. Limited to 365 days per request.',
  },
  {
    id: 'defillama', name: 'DefiLlama', coverage: ['crypto', 'defi'], kind: 'market',
    requiresKey: false, status: 'active', role: 'fallback',
    note: 'Coin price history with up to 500 daily points.',
  },
  {
    id: 'fred', name: 'FRED · St. Louis Fed', coverage: ['macro'], kind: 'macro',
    requiresKey: false, status: 'active', role: 'primary',
    note: 'Treasury yields, CPI, unemployment and real GDP CSV series.',
  },
  {
    id: 'yahoo', name: 'Yahoo Finance', coverage: ['equities', 'etfs', 'crypto', 'macro proxies'], kind: 'market',
    requiresKey: false, status: 'active', role: 'primary + fallback',
    note: 'Unofficial public chart endpoint. May be delayed or rate-limited.',
  },
  {
    id: 'yahoo-news', name: 'Yahoo Finance news', coverage: ['equities', 'etfs', 'crypto', 'indices'], kind: 'news',
    requiresKey: false, status: 'active', role: 'best-effort',
    note: 'Public search news feed. Falls back to clearly labelled synthetic headlines when unavailable.',
  },
  {
    id: 'sec', name: 'SEC EDGAR', coverage: ['US equities', 'US ETFs', 'US funds'], kind: 'fundamentals',
    requiresKey: false, status: 'active', role: 'reported company facts',
    note: 'Free public company facts, XBRL metrics and recent filings for US-registered issuers. Not available for indices, FX, futures, crypto or most non-US listings.',
  },
  {
    id: 'coincap', name: 'CoinCap', coverage: ['crypto'], kind: 'market',
    requiresKey: true, status: 'optional', role: 'keyed fallback',
    note: 'Public v2 host is retired; v3 requires COINCAP_API_KEY.',
  },
  {
    id: 'coinmarketcap', name: 'CoinMarketCap', coverage: ['crypto'], kind: 'market',
    requiresKey: true, status: 'optional', role: 'keyed fallback',
    note: 'Historical OHLCV requires COINMARKETCAP_API_KEY.',
  },
  {
    id: 'bloomberg', name: 'Bloomberg', coverage: ['all'], kind: 'licensed',
    requiresKey: true, status: 'unavailable', role: 'not integrated',
    note: 'Requires a licensed Bloomberg Terminal or Bloomberg API subscription.',
  },
  {
    id: 'investing', name: 'Investing.com', coverage: ['all'], kind: 'licensed',
    requiresKey: true, status: 'unavailable', role: 'not integrated',
    note: 'No official public API; scraping is blocked and violates their terms.',
  },
  {
    id: 'tradersunion', name: 'Traders Union', coverage: ['broker data'], kind: 'directory',
    requiresKey: true, status: 'unavailable', role: 'not integrated',
    note: 'Broker-review directory, not a public market-data API.',
  },
  {
    id: 'stooq', name: 'Stooq', coverage: ['equities', 'etfs'], kind: 'market',
    requiresKey: false, status: 'unavailable', role: 'not integrated',
    note: 'CSV endpoint is behind a JavaScript browser challenge.',
  },
];

export function buildSourceCatalog() {
  return {
    ok: true,
    generatedAt: new Date().toISOString(),
    providers: SOURCE_CATALOG,
  };
}

export function resolveSymbols(values) {
  const raw = Array.isArray(values) ? values : String(values ?? '').split(',');
  const seen = new Set();
  const out = [];
  for (const value of raw) {
    if (!value) continue;
    let symbol;
    try {
      symbol = normalizeSymbol(value);
    } catch {
      continue;
    }
    if (seen.has(symbol)) continue;
    seen.add(symbol);
    out.push(symbol);
    if (out.length >= 40) break;
  }
  return out;
}

// Arbitrary Yahoo Finance symbols are allowed. normalizeSymbol enforces the
// safe character set; unknown symbols still get deterministic fallback data if
// every upstream provider rejects them.
export function requireSymbol(value) {
  return normalizeSymbol(value);
}

function inferKind(symbol) {
  if (symbol.startsWith('^')) return 'index';
  if (symbol.endsWith('=F')) return 'future';
  if (symbol.endsWith('=X')) return 'forex';
  if (/(?:-USD|-EUR|-GBP|-JPY|-USDT|-BTC|-ETH)$/.test(symbol)) return 'crypto';
  return 'equity';
}

function inferSector(kind) {
  if (kind === 'crypto') return 'Digital Assets';
  if (kind === 'index') return 'Index';
  if (kind === 'future') return 'Futures';
  if (kind === 'forex') return 'Foreign Exchange';
  return 'Custom';
}

function assetFor(symbol, meta = {}) {
  const known = findAsset(symbol);
  const kind = known?.kind ?? inferKind(symbol);
  return {
    ...(known ?? {}),
    symbol,
    name: meta.longName ?? meta.shortName ?? known?.name ?? symbol,
    sector: known?.sector ?? inferSector(kind),
    kind,
    exchange: meta.exchange ?? known?.exchange ?? '',
    instrumentType: meta.instrumentType ?? known?.instrumentType ?? '',
  };
}

const RANGE_BARS = {
  '1mo': 22, '3mo': 66, '6mo': 126, '1y': 252, '2y': 504, '3y': 756,
};

function sourceName(source) {
  return SOURCE_NAMES[source] ?? source;
}

function providerLabel(sources) {
  const unique = [...new Set(Object.values(sources))];
  if (unique.length === 1) return `${sourceName(unique[0])} (server-side)`;
  return 'Multi-source server-side market data';
}

function providerChain(symbol, options) {
  const asset = assetFor(symbol);
  const chain = [];
  if (asset.kind === 'crypto') {
    if (options.env?.COINMARKETCAP_API_KEY) {
      chain.push(['coinmarketcap', () => fetchCoinMarketCapChart(symbol, options)]);
    }
    if (options.env?.COINCAP_API_KEY) {
      chain.push(['coincap', () => fetchCoinCapChart(symbol, options)]);
    }
    chain.push(['coinbase', () => fetchCoinbaseChart(symbol, options)]);
    chain.push(['coingecko', () => fetchCoinGeckoChart(symbol, options)]);
    chain.push(['defillama', () => fetchDefiLlamaChart(symbol, options)]);
  }
  chain.push(['yahoo', () => fetchYahooChart(symbol, {
    range: options.range ?? '2y',
    interval: options.interval ?? '1d',
    ttl: options.ttl ?? 300,
    cache: options.cache,
  })]);
  return chain;
}

async function loadSymbol(symbol, options = {}) {
  const range = options.range ?? '2y';
  const count = options.count ?? RANGE_BARS[range] ?? 504;
  const errors = [];
  for (const [source, load] of providerChain(symbol, options)) {
    try {
      const chart = await load();
      return {
        symbol,
        asset: assetFor(symbol, chart.meta),
        candles: chart.candles,
        quote: chart.quote,
        meta: chart.meta,
        source,
        warning: null,
      };
    } catch (error) {
      errors.push(`${source}: ${error.message}`);
    }
  }
  const { candles } = generateCandles(symbol, { count });
  return {
    symbol,
    asset: assetFor(symbol),
    candles,
    quote: quotesFromCandles(candles),
    meta: { longName: assetFor(symbol).name, currency: 'USD', exchange: 'Demo' },
    source: 'synthetic',
    warning: `${symbol}: ${errors.join('; ')}`,
  };
}

export async function buildSnapshot(symbols, options = {}) {
  const requested = symbols.length ? symbols : ALLOWED_SYMBOLS;
  // A full snapshot fans out to one upstream request per symbol (plus one or two
  // Coinbase chunks for crypto on longer ranges). Bypass per-symbol edge-cache
  // calls here so the request stays inside the Workers Free plan's 50-subrequest
  // budget. Individual endpoints still cache.
  const loaded = await Promise.all(requested.map((symbol) => loadSymbol(symbol, { ...options, cache: false })));
  const candleMap = {};
  const quotes = {};
  const fundamentals = {};
  const news = {};
  const quality = {};
  const assets = [];
  const sources = {};
  const warnings = [];
  for (const entry of loaded) {
    candleMap[entry.symbol] = entry.candles;
    quotes[entry.symbol] = entry.quote;
    quality[entry.symbol] = dataQuality(entry.candles, entry.source === 'synthetic');
    news[entry.symbol] = newsFor(entry.symbol, entry.candles.at(-1)?.date ?? null);
    fundamentals[entry.symbol] = fundamentalsForAny(entry.symbol, entry.asset);
    assets.push(entry.asset ?? assetFor(entry.symbol, entry.meta));
    sources[entry.symbol] = entry.source;
    if (entry.warning) warnings.push(entry.warning);
  }
  const macroCandles = candleMap.SPY ?? Object.values(candleMap)[0] ?? [];
  const macro = macroSnapshot(macroCandles, quotes.SPY?.asOf ?? null);
  const liveCount = Object.values(sources).filter((value) => value !== 'synthetic').length;
  const providerBreakdown = {};
  for (const source of Object.values(sources)) {
    providerBreakdown[source] = (providerBreakdown[source] ?? 0) + 1;
  }
  return {
    ok: true,
    source: liveCount === loaded.length ? 'live' : liveCount > 0 ? 'mixed' : 'synthetic',
    provider: providerLabel(sources),
    generatedAt: new Date().toISOString(),
    asOf: quotes.SPY?.asOf ?? quotes[loaded[0]?.symbol]?.asOf ?? null,
    assets,
    candleMap,
    quotes,
    fundamentals,
    news,
    quality,
    macro,
    sources,
    providerBreakdown,
    warnings,
  };
}

function fundamentalsForAny(symbol, asset) {
  const known = fundamentalsFor(symbol);
  if (known) return known;
  return {
    symbol,
    kind: asset?.kind ?? inferKind(symbol),
    marketCap: null,
    enterpriseValue: null,
    sharesOutstanding: null,
    pe: null,
    forwardPE: null,
    peg: null,
    priceToSales: null,
    priceToBook: null,
    eps: null,
    revenueGrowth: null,
    earningsGrowth: null,
    grossMargin: null,
    operatingMargin: null,
    profitMargin: null,
    returnOnEquity: null,
    debtToEquity: null,
    currentRatio: null,
    dividendYield: null,
    payoutRatio: null,
    beta: null,
    analystRating: 'Not available',
    analystTarget: null,
    analystUpside: null,
    analystCount: 0,
    expenseRatio: null,
    aum: null,
    employees: null,
    nextEarnings: null,
    fiscalYearEnd: null,
    asOf: null,
  };
}

export async function buildSymbol(symbol, options = {}) {
  const entry = await loadSymbol(symbol, { ...options, range: options.range ?? '2y' });
  const quality = dataQuality(entry.candles, entry.source === 'synthetic');
  const fallbackNews = newsFor(symbol, entry.candles.at(-1)?.date ?? null);
  let items = fallbackNews;
  let newsSource = 'synthetic';
  let sec = null;
  if (options.deep === true) {
    const asset = entry.asset ?? assetFor(symbol, entry.meta);
    const [secResult, newsResult] = await Promise.allSettled([
      fetchSecProfile(symbol, {
        env: options.env,
        kind: asset?.kind,
        cache: options.cache,
      }),
      fetchYahooNews(symbol, { cache: options.cache }),
    ]);
    if (secResult.status === 'fulfilled' && secResult.value) {
      const profile = secResult.value;
      const hasMetrics = Object.values(profile.metrics ?? {}).some((value) => Number.isFinite(value));
      const hasFilings = Array.isArray(profile.filings) && profile.filings.length > 0;
      if (hasMetrics || hasFilings) sec = profile;
    }
    if (newsResult.status === 'fulfilled' && newsResult.value.length) {
      items = newsResult.value;
      newsSource = 'yahoo-news';
    }
  }
  const extraSources = [
    sec ? 'SEC EDGAR' : null,
    newsSource === 'yahoo-news' ? 'Yahoo Finance news' : null,
  ].filter(Boolean);
  return {
    ok: true,
    source: entry.source,
    provider: extraSources.length
      ? `${sourceName(entry.source)} + ${extraSources.join(' + ')} (server-side)`
      : `${sourceName(entry.source)} (server-side)`,
    dataSources: {
      market: entry.source,
      sec: sec ? 'sec' : null,
      news: newsSource,
    },
    generatedAt: new Date().toISOString(),
    asset: entry.asset ?? assetFor(symbol, entry.meta),
    meta: entry.meta,
    candles: entry.candles,
    quote: entry.quote,
    fundamentals: fundamentalsForAny(symbol, entry.asset),
    sec,
    news: items,
    newsSource,
    sentiment: sentimentSummary(items),
    quality,
    macro: macroSnapshot((findSymbolCandles(symbol, entry.candles)), entry.quote?.asOf ?? null),
    warning: entry.warning,
  };
}

function findSymbolCandles(symbol, candles) {
  if (symbol === 'SPY') return candles;
  const { candles: spy } = generateCandles('SPY', { count: Math.max(252, candles.length) });
  return spy;
}

export async function buildForecastPayload(symbol, params = {}, options = {}) {
  const entry = await loadSymbol(symbol, {
    ...options,
    range: '3y',
    count: 756,
    ttl: 300,
  });
  const horizon = clampInt(params.horizon, 5, 126, 21);
  const simulations = clampInt(params.simulations, 200, 5000, 2000);
  const seed = clampInt(params.seed, 0, 999999, 7);
  const history = clampInt(params.history, 60, 252, 180);
  const mode = ['ensemble', 'factor', 'holt', 'drift'].includes(params.mode) ? params.mode : 'ensemble';
  const items = newsFor(symbol, entry.candles.at(-1)?.date ?? null);
  const forecast = buildForecast(entry.candles, {
    symbol,
    horizon,
    simulations,
    seed,
    mode,
    history,
    context: {
      fundamentals: fundamentalsForAny(symbol, entry.asset),
      macro: macroSnapshot(entry.candles, entry.quote?.asOf ?? null),
      sentiment: sentimentSummary(items),
    },
  });
  if (!forecast) {
    const error = new Error('Not enough history to build a forecast');
    error.status = 422;
    throw error;
  }
  return {
    ok: true,
    server: true,
    source: entry.source,
    provider: `${sourceName(entry.source)} + InvestorKit forecast engine (server-side)`,
    generatedAt: new Date().toISOString(),
    symbol,
    warning: entry.warning,
    quote: entry.quote,
    quality: dataQuality(entry.candles, entry.source === 'synthetic'),
    forecast,
  };
}

function clampInt(value, min, max, fallback) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(max, Math.max(min, Math.round(number)));
}

export async function buildMacro(env = {}) {
  const symbols = ['^VIX', '^TNX', '^IRX', 'DX-Y.NYB', 'CL=F', 'GC=F', 'SPY'];
  const fredIds = ['DGS10', 'DGS2', 'CPIAUCSL', 'UNRATE', 'GDPC1'];
  const [yahooResults, fredResults] = await Promise.all([
    Promise.allSettled(symbols.map((symbol) => fetchYahooChart(symbol, {
      range: '6mo',
      interval: '1d',
      ttl: 600,
    }))),
    Promise.allSettled(fredIds.map((id) => fetchFredSeries(id, { ttl: 3600 }))),
  ]);
  const map = {};
  const fred = {};
  const sources = {};
  yahooResults.forEach((result, index) => {
    const symbol = symbols[index];
    if (result.status === 'fulfilled') {
      map[symbol] = result.value;
      sources[symbol] = 'yahoo';
    } else {
      sources[symbol] = 'synthetic';
    }
  });
  fredResults.forEach((result, index) => {
    const id = fredIds[index];
    if (result.status === 'fulfilled') {
      fred[id] = result.value;
      sources[id] = 'fred';
    } else {
      sources[id] = 'synthetic';
    }
  });
  const spy = map.SPY?.candles ?? generateCandles('SPY', { count: 252 }).candles;
  const macro = macroSnapshot(spy);
  const last = (symbol, key = 'price') => map[symbol]?.quote?.[key];
  const yield10Fred = latestValue(fred.DGS10);
  const yield2Fred = latestValue(fred.DGS2);
  const yield10 = Number.isFinite(yield10Fred) ? yield10Fred : last('^TNX');
  const yield2 = Number.isFinite(yield2Fred) ? yield2Fred : last('^IRX');
  const vix = last('^VIX');
  const dollar = last('DX-Y.NYB');
  const oil = last('CL=F');
  const inflation = yearOverYear(fred.CPIAUCSL);
  const unemployment = latestValue(fred.UNRATE);
  const gdpGrowth = yearOverYear(fred.GDPC1);
  if (Number.isFinite(yield10)) macro.yield10y = yield10 / 100;
  if (Number.isFinite(yield2)) macro.yield2y = yield2 / 100;
  if (Number.isFinite(yield10) && Number.isFinite(yield2)) macro.yieldCurve = (yield10 - yield2) / 100;
  if (Number.isFinite(vix)) macro.vix = vix;
  if (Number.isFinite(dollar)) macro.dollarIndex = dollar;
  if (Number.isFinite(oil)) macro.oil = oil;
  if (Number.isFinite(inflation)) macro.inflation = inflation;
  if (Number.isFinite(unemployment)) macro.unemployment = unemployment / 100;
  if (Number.isFinite(gdpGrowth)) macro.gdpGrowth = gdpGrowth;
  if (Number.isFinite(macro.yield2y)) macro.riskFreeRate = macro.yield2y;
  macro.asOf = map.SPY?.quote?.asOf ?? fred.CPIAUCSL?.latest?.date ?? new Date().toISOString();
  macro.regime = macro.vix > 28 ? 'Risk-off' : macro.vix > 21 ? 'Cautious' : 'Risk-on';
  macro.liquidity = macro.vix > 22 ? 'Tightening' : 'Stable';
  const live = Object.values(sources).every((value) => value === 'yahoo' || value === 'fred');
  return {
    ok: true,
    source: live ? 'live' : 'mixed',
    provider: 'FRED + Yahoo Finance macro proxies (server-side)',
    generatedAt: new Date().toISOString(),
    macro,
    sources,
  };
}
