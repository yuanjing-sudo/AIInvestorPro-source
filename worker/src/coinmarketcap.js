// Optional CoinMarketCap adapter. The historical OHLCV endpoint requires an
// API key; set COINMARKETCAP_API_KEY to enable it.

import { cachedJson } from './http.js';
import { chartFromCandles, makeCandle, sortDedupe } from './candles.js';

const BASE = 'https://pro-api.coinmarketcap.com/v2/cryptocurrency/ohlcv/historical';
const RANGE_DAYS = {
  '1mo': 30, '3mo': 66, '6mo': 126, '1y': 252, '2y': 504, '3y': 756,
};

export function coinMarketCapSymbol(symbol) {
  return String(symbol ?? '').toUpperCase().replace(/-USD$/, '');
}

export async function fetchCoinMarketCapChart(symbol, options = {}) {
  const key = options.key ?? options.env?.COINMARKETCAP_API_KEY;
  if (!key) throw new Error('COINMARKETCAP_API_KEY is not configured');
  const days = RANGE_DAYS[options.range] ?? 504;
  const end = new Date();
  const start = new Date(end.getTime() - days * 86_400_000);
  const url = new URL(BASE);
  url.searchParams.set('symbol', coinMarketCapSymbol(symbol));
  url.searchParams.set('time_start', start.toISOString());
  url.searchParams.set('time_end', end.toISOString());
  url.searchParams.set('interval', 'daily');
  url.searchParams.set('convert', 'USD');
  const payload = await cachedJson(url.toString(), {
    ttl: options.ttl ?? 300,
    cache: options.cache !== false,
    label: 'CoinMarketCap',
    headers: { 'X-CMC_PRO_API_KEY': key },
  });
  const quotes = payload.data?.quotes ?? [];
  const candles = [];
  for (const quote of quotes) {
    const usd = quote.quote?.USD;
    if (!usd) continue;
    const open = Number(usd.open);
    const close = Number(usd.close);
    if (!Number.isFinite(close) || close <= 0) continue;
    candles.push(makeCandle(
      new Date(quote.time_open),
      open,
      Number(usd.high),
      Number(usd.low),
      close,
      Number(usd.volume),
    ));
  }
  return chartFromCandles(symbol, sortDedupe(candles), {
    exchange: 'CoinMarketCap',
    instrumentType: 'CRYPTO',
    longName: symbol,
  });
}
