// Server-side market service. Tries Yahoo Finance first, then falls back to the
// deterministic demo feed so the API never fails hard. Shared analytics modules
// are imported directly from the web app so the browser and Worker use exactly
// the same maths.

import {
  UNIVERSE, generateCandles, fundamentalsFor, newsFor, macroSnapshot,
  dataQuality, quotesFromCandles, findAsset, sentimentSummary,
} from '../../web/js/core/marketdata.js';
import { buildForecast } from '../../web/js/core/forecast.js';
import { fetchYahooChart, normalizeSymbol } from './yahoo.js';

export const ALLOWED_SYMBOLS = UNIVERSE.map((asset) => asset.symbol);
const ALLOWED = new Set(ALLOWED_SYMBOLS);

export function resolveSymbols(values) {
  const raw = Array.isArray(values) ? values : String(values ?? '').split(',');
  const seen = new Set();
  const out = [];
  for (const value of raw) {
    if (!value) continue;
    const symbol = normalizeSymbol(value);
    if (!ALLOWED.has(symbol) || seen.has(symbol)) continue;
    seen.add(symbol);
    out.push(symbol);
    if (out.length >= 40) break;
  }
  return out;
}

export function requireSymbol(value) {
  const symbol = normalizeSymbol(value);
  if (!ALLOWED.has(symbol)) {
    const error = new Error(`Unknown symbol: ${symbol}`);
    error.status = 404;
    throw error;
  }
  return symbol;
}

function assetFor(symbol) {
  return findAsset(symbol) ?? {
    symbol,
    name: symbol,
    sector: 'Custom',
    kind: 'equity',
  };
}

const RANGE_BARS = {
  '1mo': 22, '3mo': 66, '6mo': 126, '1y': 252, '2y': 504, '3y': 756,
};

async function loadSymbol(symbol, options = {}) {
  const range = options.range ?? '2y';
  const count = options.count ?? RANGE_BARS[range] ?? 504;
  try {
    const chart = await fetchYahooChart(symbol, {
      range,
      interval: options.interval ?? '1d',
      ttl: options.ttl ?? 300,
    });
    return {
      symbol,
      candles: chart.candles,
      quote: chart.quote,
      meta: chart.meta,
      source: 'yahoo',
      warning: null,
    };
  } catch (error) {
    const { candles } = generateCandles(symbol, { count });
    return {
      symbol,
      candles,
      quote: quotesFromCandles(candles),
      meta: { longName: assetFor(symbol).name, currency: 'USD', exchange: 'Demo' },
      source: 'synthetic',
      warning: `${symbol}: ${error.message}`,
    };
  }
}

export async function buildSnapshot(symbols, options = {}) {
  const requested = symbols.length ? symbols : ALLOWED_SYMBOLS;
  const loaded = await Promise.all(requested.map((symbol) => loadSymbol(symbol, options)));
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
    quality[entry.symbol] = dataQuality(entry.candles);
    news[entry.symbol] = newsFor(entry.symbol, entry.candles.at(-1)?.date ?? null);
    fundamentals[entry.symbol] = fundamentalsFor(entry.symbol) ?? {
      symbol: entry.symbol,
      kind: 'equity',
      marketCap: null,
      beta: null,
      analystTarget: null,
      analystUpside: null,
      analystRating: null,
    };
    assets.push(assetFor(entry.symbol));
    sources[entry.symbol] = entry.source;
    if (entry.warning) warnings.push(entry.warning);
  }
  const macroCandles = candleMap.SPY ?? Object.values(candleMap)[0] ?? [];
  const macro = macroSnapshot(macroCandles, quotes.SPY?.asOf ?? null);
  const liveCount = Object.values(sources).filter((value) => value === 'yahoo').length;
  return {
    ok: true,
    source: liveCount === loaded.length ? 'live' : liveCount > 0 ? 'mixed' : 'synthetic',
    provider: 'Yahoo Finance chart API (server-side)',
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
    warnings,
  };
}

export async function buildSymbol(symbol, options = {}) {
  const entry = await loadSymbol(symbol, { ...options, range: options.range ?? '2y' });
  const quality = dataQuality(entry.candles);
  const items = newsFor(symbol, entry.candles.at(-1)?.date ?? null);
  return {
    ok: true,
    source: entry.source,
    provider: entry.source === 'yahoo'
      ? 'Yahoo Finance chart API (server-side)'
      : 'Deterministic synthetic fallback',
    generatedAt: new Date().toISOString(),
    asset: assetFor(symbol),
    meta: entry.meta,
    candles: entry.candles,
    quote: entry.quote,
    fundamentals: fundamentalsFor(symbol),
    news: items,
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

export async function buildForecastPayload(symbol, params = {}) {
  const entry = await loadSymbol(symbol, {
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
      fundamentals: fundamentalsFor(symbol),
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
    provider: entry.source === 'yahoo'
      ? 'Yahoo Finance + InvestorKit forecast engine (server-side)'
      : 'Deterministic fallback + InvestorKit forecast engine (server-side)',
    generatedAt: new Date().toISOString(),
    symbol,
    warning: entry.warning,
    quote: entry.quote,
    quality: dataQuality(entry.candles),
    forecast,
  };
}

function clampInt(value, min, max, fallback) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(max, Math.max(min, Math.round(number)));
}

export async function buildMacro() {
  const symbols = ['^VIX', '^TNX', '^IRX', 'DX-Y.NYB', 'CL=F', 'GC=F', 'SPY'];
  const results = await Promise.allSettled(symbols.map((symbol) => fetchYahooChart(symbol, {
    range: '6mo',
    interval: '1d',
    ttl: 600,
  })));
  const map = {};
  const sources = {};
  results.forEach((result, index) => {
    const symbol = symbols[index];
    if (result.status === 'fulfilled') {
      map[symbol] = result.value;
      sources[symbol] = 'yahoo';
    } else {
      sources[symbol] = 'synthetic';
    }
  });
  const spy = map.SPY?.candles ?? generateCandles('SPY', { count: 252 }).candles;
  const macro = macroSnapshot(spy);
  const last = (symbol, key = 'price') => map[symbol]?.quote?.[key];
  const yield10 = last('^TNX');
  const yield2 = last('^IRX');
  const vix = last('^VIX');
  const dollar = last('DX-Y.NYB');
  const oil = last('CL=F');
  if (Number.isFinite(yield10)) macro.yield10y = yield10 / 100;
  if (Number.isFinite(yield2)) macro.yield2y = yield2 / 100;
  if (Number.isFinite(yield10) && Number.isFinite(yield2)) macro.yieldCurve = (yield10 - yield2) / 100;
  if (Number.isFinite(vix)) macro.vix = vix;
  if (Number.isFinite(dollar)) macro.dollarIndex = dollar;
  if (Number.isFinite(oil)) macro.oil = oil;
  macro.asOf = map.SPY?.quote?.asOf ?? new Date().toISOString();
  macro.regime = macro.vix > 28 ? 'Risk-off' : macro.vix > 21 ? 'Cautious' : 'Risk-on';
  macro.liquidity = macro.vix > 22 ? 'Tightening' : 'Stable';
  return {
    ok: true,
    source: Object.values(sources).every((value) => value === 'yahoo') ? 'live' : 'mixed',
    provider: 'Yahoo Finance macro proxies (server-side)',
    generatedAt: new Date().toISOString(),
    macro,
    sources,
  };
}
