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

const POSITIVE_WORDS = ['beat', 'beats', 'growth', 'record', 'raise', 'raised', 'upgrade', 'strong', 'profit', 'surge', 'rally', 'buyback', 'outperform', 'expands', 'wins'];
const NEGATIVE_WORDS = ['miss', 'misses', 'cut', 'cuts', 'downgrade', 'weak', 'loss', 'probe', 'lawsuit', 'recall', 'warns', 'slump', 'falls', 'risk', 'layoff', 'investigation'];

function headlineSentiment(title) {
  const text = String(title ?? '').toLowerCase();
  let score = 0;
  for (const word of POSITIVE_WORDS) if (text.includes(word)) score += 0.18;
  for (const word of NEGATIVE_WORDS) if (text.includes(word)) score -= 0.2;
  return Math.max(-0.85, Math.min(0.85, score));
}

function headlineCategory(title) {
  const text = String(title ?? '').toLowerCase();
  if (/earn|revenue|profit|guidance|quarter/.test(text)) return 'Earnings';
  if (/analyst|rating|target|upgrade|downgrade/.test(text)) return 'Analyst';
  if (/regulat|sec |lawsuit|probe|antitrust|fine/.test(text)) return 'Regulatory';
  if (/fed|rate|inflation|jobs|tariff|economy|macro/.test(text)) return 'Macro';
  if (/price|volume|breakout|technical|momentum/.test(text)) return 'Technical';
  return 'News';
}

function safeHttpUrl(value) {
  try {
    const url = new URL(String(value ?? ''));
    return url.protocol === 'http:' || url.protocol === 'https:' ? url.toString() : null;
  } catch {
    return null;
  }
}

export function parseYahooNews(payload, symbol = '') {
  const items = Array.isArray(payload?.news) ? payload.news : [];
  const seen = new Set();
  const out = [];
  for (const item of items) {
    if (!item || typeof item !== 'object') continue;
    const headline = String(item.title ?? '').trim();
    if (!headline || seen.has(headline)) continue;
    seen.add(headline);
    const timestamp = Number(item.providerPublishTime);
    const date = Number.isFinite(timestamp) && timestamp > 0
      ? new Date(timestamp * 1000)
      : new Date();
    const sentiment = headlineSentiment(headline);
    out.push({
      id: `${symbol}-yahoo-news-${out.length}`,
      symbol,
      headline: headline.slice(0, 240),
      sentiment,
      impact: Math.abs(sentiment) > 0.35 ? 'high' : Math.abs(sentiment) > 0.15 ? 'medium' : 'low',
      category: headlineCategory(headline),
      source: String(item.publisher ?? 'Yahoo Finance').slice(0, 80),
      date,
      url: safeHttpUrl(item.link),
      live: true,
    });
    if (out.length >= 8) break;
  }
  return out;
}

export async function fetchYahooNews(symbol, options = {}) {
  const url = new URL(SEARCH_BASE);
  url.searchParams.set('q', symbol);
  url.searchParams.set('quotesCount', '0');
  url.searchParams.set('newsCount', '10');
  url.searchParams.set('listsCount', '0');
  url.searchParams.set('enableFuzzyQuery', 'false');
  url.searchParams.set('newsQueryId', 'news_cie_vespa');
  url.searchParams.set('enableCb', 'true');
  const payload = await cachedJson(url.toString(), {
    ttl: options.ttl ?? 600,
    cache: options.cache !== false,
    label: 'Yahoo news',
  });
  return parseYahooNews(payload, symbol);
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
