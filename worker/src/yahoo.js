// Server-side Yahoo Finance chart adapter for the Cloudflare Worker.
// Only public, unauthenticated chart endpoints are used. Every failure is
// surfaced to the caller so the Worker can fall back to deterministic data.

import { cachedJson } from './http.js';

const CHART_BASE = 'https://query1.finance.yahoo.com/v8/finance/chart/';
const SYMBOL_PATTERN = /^[A-Z0-9^.=_-]{1,24}$/;

export function normalizeSymbol(value) {
  const symbol = decodeURIComponent(String(value ?? '')).trim().toUpperCase();
  if (!SYMBOL_PATTERN.test(symbol)) throw new Error(`Invalid symbol: ${value}`);
  return symbol;
}

function finite(value, fallback = 0) {
  return Number.isFinite(value) ? value : fallback;
}

function round(value) {
  return Math.round(value * 100) / 100;
}

function isoDate(date) {
  return date.toISOString().slice(0, 10);
}

export function parseChart(payload, requestedSymbol = '') {
  const result = payload?.chart?.result?.[0];
  if (!result) {
    const message = payload?.chart?.error?.description || payload?.chart?.error?.code || 'No chart data';
    throw new Error(String(message));
  }
  const meta = result.meta ?? {};
  const timestamps = Array.isArray(result.timestamp) ? result.timestamp : [];
  const quote = result.indicators?.quote?.[0] ?? {};
  const candles = [];
  for (let index = 0; index < timestamps.length; index += 1) {
    const close = quote.close?.[index];
    if (!Number.isFinite(close) || close <= 0) continue;
    const open = finite(quote.open?.[index], close);
    const high = finite(quote.high?.[index], Math.max(open, close));
    const low = finite(quote.low?.[index], Math.min(open, close));
    const volume = finite(quote.volume?.[index], 0);
    const date = new Date(timestamps[index] * 1000);
    candles.push({
      date,
      dateString: isoDate(date),
      open: round(open),
      high: round(Math.max(high, open, close)),
      low: round(Math.min(low, open, close)),
      close: round(close),
      volume: Math.round(volume),
      vwap: round((high + low + close) / 3),
    });
  }
  if (!candles.length) throw new Error(`No usable candles for ${requestedSymbol || meta.symbol || 'symbol'}`);
  const last = candles[candles.length - 1];
  const previous = candles.length > 1 ? candles[candles.length - 2] : last;
  const reportedPrice = finite(meta.regularMarketPrice, last.close);
  const marketPrice = reportedPrice > 0 ? reportedPrice : last.close;
  const marketTime = Number.isFinite(meta.regularMarketTime)
    ? new Date(meta.regularMarketTime * 1000).toISOString()
    : last.date;

  return {
    symbol: meta.symbol || requestedSymbol,
    meta: {
      currency: meta.currency ?? 'USD',
      exchange: meta.fullExchangeName ?? meta.exchangeName ?? '',
      instrumentType: meta.instrumentType ?? '',
      timezone: meta.exchangeTimezoneName ?? '',
      regularMarketPrice: marketPrice,
      regularMarketTime: meta.regularMarketTime ?? null,
      fiftyTwoWeekHigh: finite(meta.fiftyTwoWeekHigh, Math.max(...candles.slice(-252).map((candle) => candle.high))),
      fiftyTwoWeekLow: finite(meta.fiftyTwoWeekLow, Math.min(...candles.slice(-252).map((candle) => candle.low))),
      longName: meta.longName ?? meta.shortName ?? requestedSymbol,
      shortName: meta.shortName ?? meta.longName ?? requestedSymbol,
    },
    candles,
    quote: {
      price: marketPrice,
      previousClose: previous.close,
      change: marketPrice - previous.close,
      changePercent: previous.close ? ((marketPrice / previous.close) - 1) * 100 : 0,
      high: last.high,
      low: last.low,
      open: last.open,
      volume: last.volume,
      asOf: marketTime,
    },
  };
}

export async function fetchYahooChart(symbol, options = {}) {
  const normalized = normalizeSymbol(symbol);
  const range = options.range ?? '2y';
  const interval = options.interval ?? '1d';
  const url = new URL(`${CHART_BASE}${encodeURIComponent(normalized)}`);
  url.searchParams.set('range', range);
  url.searchParams.set('interval', interval);
  url.searchParams.set('includePrePost', 'false');
  url.searchParams.set('events', 'div,splits');
  const payload = await cachedJson(url.toString(), {
    ttl: options.ttl ?? 300,
    cache: options.cache !== false,
    label: 'Yahoo',
  });
  return parseChart(payload, normalized);
}
