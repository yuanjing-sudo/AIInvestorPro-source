// Coinbase Exchange public candles. No API key is required. Daily candles are
// limited to 300 per request, so longer ranges are fetched in 299-day chunks.

import { cachedJson } from './http.js';
import { candlesFromCloses, chartFromCandles, makeCandle, sortDedupe } from './candles.js';

const BASE = 'https://api.exchange.coinbase.com/products';
const RANGE_DAYS = {
  '1mo': 30, '3mo': 66, '6mo': 126, '1y': 252, '2y': 504, '3y': 756,
};
const CHUNK_DAYS = 299;

export function coinbaseProduct(symbol) {
  const value = String(symbol ?? '').toUpperCase();
  return value.includes('-') ? value : `${value}-USD`;
}

export async function fetchCoinbaseChart(symbol, options = {}) {
  const product = coinbaseProduct(symbol);
  const days = RANGE_DAYS[options.range] ?? 504;
  const end = new Date();
  const start = new Date(end.getTime() - days * 86_400_000);
  const chunks = [];
  let cursor = start;
  while (cursor < end) {
    const chunkEnd = new Date(Math.min(cursor.getTime() + CHUNK_DAYS * 86_400_000, end.getTime()));
    chunks.push([cursor, chunkEnd]);
    cursor = new Date(chunkEnd.getTime() + 86_400_000);
  }

  const responses = await Promise.all(chunks.map(([chunkStart, chunkEnd]) => {
    const url = new URL(`${BASE}/${encodeURIComponent(product)}/candles`);
    url.searchParams.set('granularity', '86400');
    url.searchParams.set('start', chunkStart.toISOString());
    url.searchParams.set('end', chunkEnd.toISOString());
    return cachedJson(url.toString(), {
      ttl: options.ttl ?? 300,
      cache: options.cache !== false,
      label: 'Coinbase',
    });
  }));

  const candles = [];
  for (const rows of responses) {
    if (!Array.isArray(rows)) continue;
    for (const row of rows) {
      if (!Array.isArray(row) || row.length < 6) continue;
      const [time, low, high, open, close, volume] = row;
      if (!Number.isFinite(close) || close <= 0) continue;
      candles.push(makeCandle(new Date(time * 1000), open, high, low, close, volume));
    }
  }
  return chartFromCandles(symbol, sortDedupe(candles), {
    exchange: 'Coinbase',
    instrumentType: 'CRYPTO',
    longName: symbol,
  });
}

