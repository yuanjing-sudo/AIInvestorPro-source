// CoinGecko public market-chart fallback. The free API allows up to 365 days
// per request; longer forecast requests simply use the available window.

import { cachedJson } from './http.js';
import { chartFromCandles, dailyCandlesFromCloses } from './candles.js';

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

export function coinGeckoId(symbol) {
  return IDS[String(symbol ?? '').toUpperCase()] ?? null;
}

export async function fetchCoinGeckoChart(symbol, options = {}) {
  const id = coinGeckoId(symbol);
  if (!id) throw new Error(`No CoinGecko mapping for ${symbol}`);
  const days = Math.min(365, RANGE_DAYS[options.range] ?? 365);
  const url = new URL(`https://api.coingecko.com/api/v3/coins/${encodeURIComponent(id)}/market_chart`);
  url.searchParams.set('vs_currency', 'usd');
  url.searchParams.set('days', String(days));
  const payload = await cachedJson(url.toString(), {
    ttl: options.ttl ?? 300,
    cache: options.cache !== false,
    label: 'CoinGecko',
  });
  const prices = Array.isArray(payload.prices) ? payload.prices : [];
  const volumes = new Map((payload.total_volumes ?? []).map(([timestamp, value]) => [timestamp, value]));
  return chartFromCandles(symbol, dailyCandlesFromCloses(prices, volumes), {
    exchange: 'CoinGecko',
    instrumentType: 'CRYPTO',
    longName: id,
  });
}

