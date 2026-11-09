// Yahoo Finance symbol search adapter. The endpoint is public but unofficial;
// callers get a small normalized result list and can still load a symbol
// directly if the search service is unavailable.

import { cachedJson } from './http.js';
import { normalizeSymbol } from './yahoo.js';

const SEARCH_BASE = 'https://query1.finance.yahoo.com/v1/finance/search';
const TYPE_MAP = {
  EQUITY: 'equity',
  ETF: 'etf',
  MUTUALFUND: 'fund',
  CRYPTOCURRENCY: 'crypto',
  INDEX: 'index',
  FUTURE: 'future',
  CURRENCY: 'forex',
  OPTION: 'option',
};

export function parseSearch(payload, query = '') {
  const quotes = Array.isArray(payload?.quotes) ? payload.quotes : [];
  const seen = new Set();
  const results = [];
  for (const quote of quotes) {
    if (!quote || typeof quote !== 'object') continue;
    let symbol;
    try {
      symbol = normalizeSymbol(quote.symbol ?? '');
    } catch {
      continue;
    }
    if (seen.has(symbol)) continue;
    const type = TYPE_MAP[String(quote.quoteType ?? '').toUpperCase()] ?? 'asset';
    if (type === 'option') continue;
    seen.add(symbol);
    results.push({
      symbol,
      name: quote.longname ?? quote.shortname ?? quote.symbol ?? symbol,
      exchange: quote.exchange ?? '',
      exchangeDisplay: quote.exchDisp ?? quote.exchange ?? '',
      type,
      sector: quote.sector ?? '',
      industry: quote.industry ?? '',
      direct: symbol === String(query ?? '').trim().toUpperCase(),
    });
    if (results.length >= 12) break;
  }
  return results;
}

export async function searchAssets(query, options = {}) {
  const q = String(query ?? '').trim().slice(0, 80);
  if (!q) return { ok: true, query: q, provider: 'Yahoo Finance search', results: [] };
  const url = new URL(SEARCH_BASE);
  url.searchParams.set('q', q);
  url.searchParams.set('quotesCount', '12');
  url.searchParams.set('newsCount', '0');
  url.searchParams.set('listsCount', '0');
  url.searchParams.set('enableFuzzyQuery', 'false');
  url.searchParams.set('quotesQueryId', 'tss_match_phrase_query');
  url.searchParams.set('multiQuoteQueryId', 'multi_quote_single_token_query');
  url.searchParams.set('newsQueryId', 'news_cie_vespa');
  url.searchParams.set('enableCb', 'true');
  url.searchParams.set('enableNavLinks', 'true');
  url.searchParams.set('enableEnhancedTrivialQuery', 'true');
  const payload = await cachedJson(url.toString(), {
    ttl: options.ttl ?? 300,
    cache: options.cache !== false,
    label: 'Yahoo search',
  });
  const results = parseSearch(payload, q);
  return {
    ok: true,
    query: q,
    provider: 'Yahoo Finance search',
    generatedAt: new Date().toISOString(),
    results,
  };
}
