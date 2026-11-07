// Optional CoinCap adapter. CoinCap's public v2 host is no longer resolvable and
// the v3 API requires a key. Set COINCAP_API_KEY to enable this provider.

import { cachedJson } from './http.js';
import { candlesFromCloses, chartFromCandles } from './candles.js';

const IDS = {
  'BTC-USD': 'bitcoin',
  'ETH-USD': 'ethereum',
  'SOL-USD': 'solana',
  'LINK-USD': 'chainlink',
  'AAVE-USD': 'aave',
  'DOGE-USD': 'dogecoin',
  'XRP-USD': 'ripple',
  'ADA-USD': 'cardano',
};
const RANGE_DAYS = {
  '1mo': 30, '3mo': 66, '6mo': 126, '1y': 252, '2y': 504, '3y': 756,
};

export function coinCapId(symbol) {
  return IDS[String(symbol ?? '').toUpperCase()] ?? null;
}

export async function fetchCoinCapChart(symbol, options = {}) {
  const key = options.key ?? options.env?.COINCAP_API_KEY;
  if (!key) throw new Error('COINCAP_API_KEY is not configured');
  const id = coinCapId(symbol);
  if (!id) throw new Error(`No CoinCap mapping for ${symbol}`);
  const days = RANGE_DAYS[options.range] ?? 504;
  const end = Date.now();
  const start = end - days * 86_400_000;
  const url = `https://rest.coincap.io/v3/assets/${encodeURIComponent(id)}/history?interval=d1&start=${start}&end=${end}`;
  const payload = await cachedJson(url, {
    ttl: options.ttl ?? 300,
    cache: options.cache !== false,
    label: 'CoinCap',
    headers: { authorization: `Bearer ${key}` },
  });
  const rows = Array.isArray(payload.data) ? payload.data : [];
  const points = rows
    .map((row) => [Number(row.time), Number(row.priceUsd)])
    .filter(([timestamp, price]) => Number.isFinite(timestamp) && Number.isFinite(price));
  return chartFromCandles(symbol, candlesFromCloses(points), {
    exchange: 'CoinCap',
    instrumentType: 'CRYPTO',
    longName: id,
  });
}
