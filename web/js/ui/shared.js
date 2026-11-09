// Shared state, market context, formatting and persistence for the web app.

import { UNIVERSE, marketSnapshot, returnsFromCandles } from '../core/marketdata.js';
import { summarize } from '../core/indicators.js';
import { CanvasChart } from './charts.js';

export { UNIVERSE };
export const CORE_UNIVERSE = [...UNIVERSE];
export const CORE_SYMBOLS = CORE_UNIVERSE.map((asset) => asset.symbol);

export const market = marketSnapshot(756);
export const quotes = market.quotes;
export const candleMap = market.candleMap;
export const fundamentals = market.fundamentals;
export const news = market.news;
export const quality = market.quality;
export const sources = {};
export const secBySymbol = {};
export const macro = market.macro;

export const SOURCE_LABELS = {
  coinbase: 'Coinbase',
  coingecko: 'CoinGecko',
  defillama: 'DefiLlama',
  coincap: 'CoinCap',
  coinmarketcap: 'CoinMarketCap',
  fred: 'FRED',
  yahoo: 'Yahoo Finance',
  'yahoo-news': 'Yahoo Finance news',
  sec: 'SEC EDGAR',
  synthetic: 'Synthetic fallback',
  local: 'Local feed',
};

export function sourceLabel(id) {
  return SOURCE_LABELS[id] ?? id ?? 'Unknown';
}
market.source = 'demo';
market.provider = 'Deterministic local feed';
market.sources = sources;
market.sec = secBySymbol;
market.generatedAt = new Date().toISOString();
market.live = false;
export const assetsBySymbol = Object.fromEntries(UNIVERSE.map((asset) => [asset.symbol, asset]));
export const returnsBySymbol = Object.fromEntries(
  UNIVERSE.map((asset) => [asset.symbol, returnsFromCandles(candleMap[asset.symbol])]),
);
export const indicators = Object.fromEntries(
  UNIVERSE.map((asset) => [asset.symbol, summarize(candleMap[asset.symbol])]),
);

function normalizeServerCandles(candles) {
  return candles.map((candle) => ({
    ...candle,
    date: candle.date instanceof Date ? candle.date : new Date(candle.date),
  }));
}

/**
 * Merge a server snapshot into the shared mutable market objects. Views listen
 * for the `ik:market-updated` event and re-render with the new prices.
 */
export function upsertAsset(asset) {
  if (!asset?.symbol) return null;
  const symbol = String(asset.symbol).toUpperCase();
  const normalized = {
    symbol,
    name: asset.name ?? symbol,
    sector: asset.sector ?? 'Custom',
    kind: asset.kind ?? 'equity',
    exchange: asset.exchange ?? '',
    instrumentType: asset.instrumentType ?? '',
  };
  const existing = assetsBySymbol[symbol];
  if (existing) {
    Object.assign(existing, normalized);
    return existing;
  }
  assetsBySymbol[symbol] = normalized;
  UNIVERSE.push(normalized);
  return normalized;
}

export function hydrateSymbol(payload) {
  const symbol = payload?.asset?.symbol ?? payload?.symbol;
  if (!symbol || !Array.isArray(payload.candles) || !payload.candles.length) return false;
  upsertAsset(payload.asset ?? {
    symbol,
    name: payload.meta?.longName ?? payload.meta?.shortName ?? symbol,
    kind: 'equity',
  });
  const candles = normalizeServerCandles(payload.candles);
  candleMap[symbol] = candles;
  returnsBySymbol[symbol] = returnsFromCandles(candles);
  indicators[symbol] = summarize(candles);
  if (payload.quote) quotes[symbol] = payload.quote;
  if (payload.fundamentals) fundamentals[symbol] = payload.fundamentals;
  if (payload.news) news[symbol] = payload.news;
  if (payload.quality) quality[symbol] = payload.quality;
  if (payload.source) sources[symbol] = payload.source;
  if (payload.sec) secBySymbol[symbol] = payload.sec;
  if (payload.provider) market.provider = payload.provider;
  market.live = true;
  market.source = market.source === 'demo' ? 'live' : market.source;
  if (typeof document !== 'undefined') {
    document.dispatchEvent(new CustomEvent('ik:symbol-updated', { detail: { symbol, payload } }));
    document.dispatchEvent(new CustomEvent('ik:assets-updated', { detail: { symbol } }));
  }
  return true;
}

export function hydrateMarket(snapshot) {
  if (!snapshot?.candleMap) return false;
  if (Array.isArray(snapshot.assets)) {
    for (const asset of snapshot.assets) upsertAsset(asset);
  }
  const symbols = Object.keys(snapshot.candleMap);
  if (!symbols.length) return false;
  for (const symbol of symbols) {
    if (!assetsBySymbol[symbol]) upsertAsset({ symbol, name: snapshot.quotes?.[symbol]?.name ?? symbol });
    const candles = normalizeServerCandles(snapshot.candleMap[symbol]);
    candleMap[symbol] = candles;
    returnsBySymbol[symbol] = returnsFromCandles(candles);
    indicators[symbol] = summarize(candles);
  }
  if (snapshot.quotes) Object.assign(quotes, snapshot.quotes);
  if (snapshot.fundamentals) Object.assign(fundamentals, snapshot.fundamentals);
  if (snapshot.news) Object.assign(news, snapshot.news);
  if (snapshot.quality) Object.assign(quality, snapshot.quality);
  if (snapshot.sources) Object.assign(sources, snapshot.sources);
  if (snapshot.sec) Object.assign(secBySymbol, snapshot.sec);
  if (snapshot.macro) Object.assign(macro, snapshot.macro);
  market.source = snapshot.source ?? 'live';
  market.provider = snapshot.provider ?? 'Server API';
  market.providerBreakdown = snapshot.providerBreakdown ?? {};
  market.generatedAt = snapshot.generatedAt ?? new Date().toISOString();
  market.asOf = snapshot.asOf ?? null;
  market.live = market.source !== 'synthetic';
  market.warnings = snapshot.warnings ?? [];
  if (typeof document !== 'undefined') {
    document.dispatchEvent(new CustomEvent('ik:assets-updated', { detail: { count: UNIVERSE.length } }));
    document.dispatchEvent(new CustomEvent('ik:market-updated', { detail: snapshot }));
  }
  return true;
}

const PORTFOLIO_KEY = 'ik.portfolio.v1';
const ALERTS_KEY = 'ik.alerts.v1';

function readJSON(key) {
  try {
    const raw = localStorage.getItem(key);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

function writeJSON(key, value) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // Storage can be disabled in private modes; the app still works in memory.
  }
}

export function demoPortfolio() {
  return {
    cash: 25000,
    lots: [
      { id: 'demo-aapl', symbol: 'AAPL', quantity: 20, costPerShare: 150, acquiredAt: new Date('2023-06-15T00:00:00Z'), remaining: 20 },
      { id: 'demo-msft', symbol: 'MSFT', quantity: 12, costPerShare: 300, acquiredAt: new Date('2023-09-01T00:00:00Z'), remaining: 12 },
      { id: 'demo-spy', symbol: 'SPY', quantity: 15, costPerShare: 400, acquiredAt: new Date('2024-01-15T00:00:00Z'), remaining: 15 },
      { id: 'demo-nvda', symbol: 'NVDA', quantity: 8, costPerShare: 450, acquiredAt: new Date('2024-03-01T00:00:00Z'), remaining: 8 },
      { id: 'demo-gld', symbol: 'GLD', quantity: 30, costPerShare: 180, acquiredAt: new Date('2024-05-01T00:00:00Z'), remaining: 30 },
    ],
    sales: [],
  };
}

function revivePortfolio(raw) {
  if (!raw || !Array.isArray(raw.lots)) return null;
  return {
    cash: Number.isFinite(raw.cash) ? raw.cash : 0,
    lots: raw.lots
      .filter((lot) => lot && lot.symbol && Number.isFinite(lot.quantity))
      .map((lot) => ({
        ...lot,
        acquiredAt: new Date(lot.acquiredAt ?? Date.now()),
        remaining: Number.isFinite(lot.remaining) ? lot.remaining : lot.quantity,
      })),
    sales: Array.isArray(raw.sales)
      ? raw.sales.map((sale) => ({ ...sale, soldAt: new Date(sale.soldAt ?? Date.now()) }))
      : [],
  };
}

export const state = {
  tab: 'dashboard',
  symbol: 'SPY',
  portfolio: revivePortfolio(readJSON(PORTFOLIO_KEY)) ?? demoPortfolio(),
  alerts: (() => {
    const saved = readJSON(ALERTS_KEY);
    return {
      rules: Array.isArray(saved?.rules) ? saved.rules : [],
      history: Array.isArray(saved?.history) ? saved.history : [],
    };
  })(),
  optimize: {
    selected: ['SPY', 'QQQ', 'AAPL', 'MSFT', 'JPM', 'GLD', 'TLT'],
    result: null,
    frontier: null,
  },
  risk: {
    symbols: ['SPY', 'QQQ', 'AAPL', 'MSFT', 'JPM', 'GLD', 'TLT'],
    weights: {},
    result: null,
    stress: null,
  },
  backtest: { symbol: 'SPY', strategy: 'smaCross', result: null },
  forecast: {
    symbol: 'SPY',
    horizon: 21,
    mode: 'ensemble',
    simulations: 2000,
    seed: 7,
    history: 180,
    result: null,
  },
  research: { symbol: 'SPY' },
  screener: {
    filters: {
      sectors: [], minPrice: 0, maxPrice: Infinity, minAvgVolume: 0,
      minMomentum: -Infinity, maxMomentum: Infinity, minRsi: 0, maxRsi: 100,
      trendOnly: false, sortBy: 'score',
    },
  },
  swReady: false,
};

for (const symbol of state.risk.symbols) {
  state.risk.weights[symbol] = 100 / state.risk.symbols.length;
}

export function savePortfolio() {
  writeJSON(PORTFOLIO_KEY, {
    cash: state.portfolio.cash,
    lots: state.portfolio.lots.map((lot) => ({
      ...lot,
      acquiredAt: lot.acquiredAt instanceof Date ? lot.acquiredAt.toISOString() : lot.acquiredAt,
    })),
    sales: state.portfolio.sales.map((sale) => ({
      ...sale,
      soldAt: sale.soldAt instanceof Date ? sale.soldAt.toISOString() : sale.soldAt,
      consumed: (sale.consumed ?? []).map((entry) => ({
        ...entry,
        acquiredAt: entry.acquiredAt instanceof Date ? entry.acquiredAt.toISOString() : entry.acquiredAt,
      })),
    })),
  });
}

export function saveAlerts() {
  writeJSON(ALERTS_KEY, {
    rules: state.alerts.rules,
    history: state.alerts.history.slice(0, 50),
  });
}

export function aggregatePortfolio() {
  const grouped = new Map();
  for (const lot of state.portfolio.lots) {
    if (!(lot.remaining > 1e-9)) continue;
    const price = quotes[lot.symbol]?.price ?? lot.costPerShare;
    const current = grouped.get(lot.symbol) ?? {
      symbol: lot.symbol, quantity: 0, costBasis: 0, price,
    };
    current.quantity += lot.remaining;
    current.costBasis += lot.remaining * lot.costPerShare;
    current.price = price;
    grouped.set(lot.symbol, current);
  }
  const holdings = [...grouped.values()].map((row) => {
    const marketValue = row.quantity * row.price;
    const averageCost = row.quantity > 0 ? row.costBasis / row.quantity : 0;
    return {
      ...row,
      averageCost,
      marketValue,
      unrealized: marketValue - row.costBasis,
      unrealizedPercent: row.costBasis > 0 ? (marketValue - row.costBasis) / row.costBasis : 0,
      allocation: 0,
    };
  }).sort((a, b) => b.marketValue - a.marketValue);

  const marketValue = holdings.reduce((acc, row) => acc + row.marketValue, 0);
  const costBasis = holdings.reduce((acc, row) => acc + row.costBasis, 0);
  for (const row of holdings) {
    row.allocation = marketValue > 0 ? row.marketValue / marketValue : 0;
  }
  const realized = state.portfolio.sales.reduce((acc, sale) => acc + (sale.realizedGain ?? 0), 0);
  const unrealized = marketValue - costBasis;
  return {
    holdings,
    marketValue,
    costBasis,
    unrealized,
    unrealizedPercent: costBasis > 0 ? unrealized / costBasis : 0,
    realized,
    cash: state.portfolio.cash,
    total: marketValue + state.portfolio.cash,
  };
}

export function formatMoney(value, digits = 0) {
  if (!Number.isFinite(value)) return '—';
  try {
    return new Intl.NumberFormat(undefined, {
      style: 'currency', currency: 'USD',
      minimumFractionDigits: digits, maximumFractionDigits: digits,
    }).format(value);
  } catch {
    return `$${value.toFixed(digits)}`;
  }
}

export function formatMoneyCompact(value) {
  if (!Number.isFinite(value)) return '—';
  const abs = Math.abs(value);
  if (abs >= 1e9) return `$${(value / 1e9).toFixed(1)}B`;
  if (abs >= 1e6) return `$${(value / 1e6).toFixed(1)}M`;
  if (abs >= 1e4) return `$${(value / 1e3).toFixed(1)}k`;
  return formatMoney(value, 0);
}

export function formatPercent(value, digits = 2) {
  if (!Number.isFinite(value)) return '—';
  return `${(value * 100).toFixed(digits)}%`;
}

export function formatSignedPercent(value, digits = 2) {
  if (!Number.isFinite(value)) return '—';
  return `${value >= 0 ? '+' : '−'}${(Math.abs(value) * 100).toFixed(digits)}%`;
}

export function formatCompact(value, digits = 1) {
  if (!Number.isFinite(value)) return '—';
  const abs = Math.abs(value);
  if (abs >= 1e12) return `${(value / 1e12).toFixed(digits)}T`;
  if (abs >= 1e9) return `${(value / 1e9).toFixed(digits)}B`;
  if (abs >= 1e6) return `${(value / 1e6).toFixed(digits)}M`;
  if (abs >= 1e3) return `${(value / 1e3).toFixed(digits)}K`;
  return value.toFixed(0);
}

export function formatNumber(value, digits = 2) {
  if (!Number.isFinite(value)) return '—';
  if (Math.abs(value) >= 1000) {
    return new Intl.NumberFormat(undefined, { maximumFractionDigits: digits }).format(value);
  }
  return value.toFixed(digits);
}

export function formatSignedMoney(value, digits = 0) {
  if (!Number.isFinite(value)) return '—';
  return `${value >= 0 ? '+' : '−'}${formatMoney(Math.abs(value), digits)}`;
}

export function signClass(value) {
  if (!Number.isFinite(value) || value === 0) return '';
  return value > 0 ? 'pos' : 'neg';
}

export function dateLabel(value) {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return '—';
  return date.toLocaleDateString(undefined, { month: 'short', year: '2-digit' });
}

export function dateShort(value) {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return '—';
  return date.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
}

export function dateTime(value) {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return '—';
  return date.toLocaleString(undefined, {
    month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
  });
}

export function $(selector, root = document) {
  return root.querySelector(selector);
}

export function $$(selector, root = document) {
  return [...root.querySelectorAll(selector)];
}

export function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

export const charts = new Set();

export function makeChart(canvas, options = {}) {
  const chart = new CanvasChart(canvas, options);
  charts.add(chart);
  return chart;
}

export function redrawCharts() {
  for (const chart of charts) chart.draw();
}

let toastTimer = null;

export function toast(message) {
  const element = $('#toast');
  if (!element) return;
  element.textContent = message;
  element.hidden = false;
  window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => { element.hidden = true; }, 3000);
}

export function fillSymbolSelect(select, selected) {
  if (!select) return;
  select.innerHTML = UNIVERSE
    .map((asset) => `<option value="${asset.symbol}">${asset.symbol} · ${escapeHtml(asset.name)}</option>`)
    .join('');
  if (selected) select.value = selected;
}

export function statCard(label, value, sub = '', valueClass = '') {
  return `<div class="stat">
    <div class="stat-label">${escapeHtml(label)}</div>
    <div class="stat-value ${valueClass}">${value}</div>
    ${sub ? `<div class="stat-sub">${sub}</div>` : ''}
  </div>`;
}

export function emptyRow(columns, message) {
  return `<tr><td class="empty-row" colspan="${columns}">${escapeHtml(message)}</td></tr>`;
}
