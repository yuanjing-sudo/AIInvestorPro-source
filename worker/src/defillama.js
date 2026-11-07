// DefiLlama coin-price fallback. DefiLlama exposes up to 500 daily points per
// request and is useful when both Coinbase and CoinGecko are unavailable.

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
  '1mo': 30, '3mo': 66, '6mo': 126, '1y': 365, '2y': 500, '3y': 500,
};

export function defiLlamaId(symbol) {
  return IDS[String(symbol ?? '').toUpperCase()] ?? null;
}

export async function fetchDefiLlamaChart(symbol, options = {}) {
  const id = defiLlamaId(symbol);
  if (!id) throw new Error(`No DefiLlama mapping for ${symbol}`);
  const span = Math.min(500, RANGE_DAYS[options.range] ?? 365);
  const coin = `coingecko:${id}`;
  const url = `https://coins.llama.fi/chart/${encodeURIComponent(coin)}?span=${span}&period=1d`;
  const payload = await cachedJson(url, {
    ttl: options.ttl ?? 300,
    cache: options.cache !== false,
    label: 'DefiLlama',
  });
  const prices = payload.coins?.[coin]?.prices ?? [];
  const points = prices
    .filter((point) => Number.isFinite(point.timestamp) && Number.isFinite(point.price))
    .map((point) => [point.timestamp * 1000, point.price]);
  return chartFromCandles(symbol, candlesFromCloses(points), {
    exchange: 'DefiLlama',
    instrumentType: 'CRYPTO',
    longName: id,
  });
}

