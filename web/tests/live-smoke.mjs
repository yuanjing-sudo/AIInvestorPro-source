import { readFileSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { JSDOM } from 'jsdom';
import { marketSnapshot, dataQuality, sentimentSummary, newsFor } from '../js/core/marketdata.js';
import { buildForecast } from '../js/core/forecast.js';
import { indicatorDetails } from '../js/core/indicators.js';

const ROOT = fileURLToPath(new URL('..', import.meta.url));
const html = readFileSync(`${ROOT}/index.html`, 'utf8');
const dom = new JSDOM(html, { url: 'http://localhost/', pretendToBeVisual: true, runScripts: 'outside-only' });
const { window } = dom;
const { document } = window;
const gradient = { addColorStop() {} };
const context = new Proxy({}, {
  get(target, prop) {
    if (prop === 'createLinearGradient') return () => gradient;
    if (prop === 'measureText') return () => ({ width: 42 });
    if (prop in target) return target[prop];
    return () => {};
  },
  set(target, prop, value) { target[prop] = value; return true; },
});
window.HTMLCanvasElement.prototype.getContext = () => context;
window.HTMLElement.prototype.scrollIntoView = () => {};
window.matchMedia = () => ({ matches: false, addEventListener() {}, removeEventListener() {} });
class FakeResizeObserver { observe() {} unobserve() {} disconnect() {} }
window.ResizeObserver = FakeResizeObserver;
globalThis.window = window;
globalThis.document = document;
Object.defineProperty(globalThis, 'navigator', { value: window.navigator, configurable: true });
Object.defineProperty(globalThis, 'localStorage', { value: window.localStorage, configurable: true });
globalThis.getComputedStyle = window.getComputedStyle.bind(window);
globalThis.ResizeObserver = FakeResizeObserver;
globalThis.requestAnimationFrame = (callback) => window.setTimeout(callback, 0);
globalThis.cancelAnimationFrame = (id) => window.clearTimeout(id);
globalThis.TextEncoder = TextEncoder;
globalThis.CustomEvent = window.CustomEvent;
globalThis.Event = window.Event;
globalThis.MouseEvent = window.MouseEvent;

const market = marketSnapshot(300);
const snapshot = {
  ...market,
  source: 'live',
  provider: 'Multi-source server-side market data',
  sources: Object.fromEntries(Object.keys(market.candleMap).map((symbol) => [symbol, 'yahoo'])),
  providerBreakdown: { yahoo: Object.keys(market.candleMap).length },
  generatedAt: new Date().toISOString(),
  asOf: market.quotes.SPY.asOf,
  warnings: [],
};
const forecast = buildForecast(market.candleMap.SPY, {
  symbol: 'SPY', horizon: 21, simulations: 200, seed: 7, history: 200, mode: 'ensemble',
});
forecast.server = true;
forecast.provider = 'Test server forecast';

const costCandles = market.candleMap.SPY.map((candle, index) => ({
  ...candle,
  close: candle.close * 4.2 + Math.sin(index / 13) * 8,
  open: candle.open * 4.2 + Math.sin(index / 13) * 8,
  high: candle.high * 4.2 + Math.sin(index / 13) * 8,
  low: candle.low * 4.2 + Math.sin(index / 13) * 8,
}));
const costQuote = {
  ...market.quotes.SPY,
  symbol: 'COST',
  price: costCandles.at(-1).close,
  previousClose: costCandles.at(-2).close,
  changePercent: (costCandles.at(-1).close / costCandles.at(-2).close - 1) * 100,
  asOf: costCandles.at(-1).date,
};
const costNews = newsFor('SPY', costCandles.at(-1).date).map((item, index) => ({
  ...item,
  symbol: 'COST',
  ...(index === 0 ? { live: true, url: 'https://finance.yahoo.com/quote/COST/news', source: 'Yahoo Finance' } : {}),
}));
const costSec = {
  source: 'sec', sourceLabel: 'SEC EDGAR', cik: '909832', entityName: 'Costco Wholesale Corporation',
  asOf: costCandles.at(-1).date, fiscalYearEnd: '0830', currency: 'USD',
  metrics: {
    revenue: 254.5e9, revenueGrowth: 0.06, netIncome: 7.4e9, netMargin: 0.029,
    assets: 69e9, liabilities: 43e9, equity: 26e9, cash: 11e9, operatingCashFlow: 11.3e9,
    freeCashFlow: 6.1e9, epsDiluted: 16.6, sharesOutstanding: 444e6, bookValuePerShare: 58.5,
    debtToEquity: 1.65, currentRatio: 1.02, grossMargin: 0.125, rdIntensity: null,
  },
  annual: {
    revenue: [{ end: '2024-09-01', value: 254.5e9 }],
    netIncome: [{ end: '2024-09-01', value: 7.4e9 }],
    epsDiluted: [{ end: '2024-09-01', value: 16.6 }],
  },
  filings: [{ form: '10-K', filingDate: costCandles.at(-1).date, reportDate: '2024-09-01', description: 'Annual report', url: 'https://www.sec.gov/Archives/edgar/data/909832/example' }],
};
const costPayload = {
  ok: true,
  source: 'yahoo',
  provider: 'Yahoo Finance + SEC EDGAR + Yahoo Finance news (server-side)',
  dataSources: { market: 'yahoo', sec: 'sec', news: 'yahoo-news' },
  generatedAt: new Date().toISOString(),
  asset: { symbol: 'COST', name: 'Costco Wholesale Corporation', sector: 'Consumer Defensive', kind: 'equity', exchange: 'NMS', instrumentType: 'EQUITY' },
  meta: { longName: 'Costco Wholesale Corporation', currency: 'USD', exchange: 'NMS' },
  candles: costCandles,
  quote: costQuote,
  fundamentals: {
    symbol: 'COST', kind: 'equity', marketCap: 380e9, enterpriseValue: 385e9, sharesOutstanding: 444e6,
    pe: 48, forwardPE: 44, peg: 3.2, priceToSales: 1.4, priceToBook: 15, eps: 16,
    revenueGrowth: 0.07, earningsGrowth: 0.1, grossMargin: 0.12, operatingMargin: 0.04,
    profitMargin: 0.03, returnOnEquity: 0.3, debtToEquity: 0.4, currentRatio: 1.1,
    dividendYield: 0.005, payoutRatio: 0.28, beta: 0.8, analystRating: 'Buy', analystTarget: 900,
    analystUpside: 0.1, analystCount: 24, expenseRatio: null, aum: null, employees: 316000,
    nextEarnings: null, fiscalYearEnd: null, asOf: costCandles.at(-1).date,
  },
  sec: costSec,
  news: costNews,
  newsSource: 'yahoo-news',
  sentiment: sentimentSummary(costNews),
  quality: dataQuality(costCandles, false),
  macro: { regime: 'Neutral' },
  warning: null,
};
const insightsPayload = {
  ok: true,
  provider: 'Cloudflare Workers AI',
  model: '@cf/meta/llama-3.3-70b-instruct-fp8-fast',
  generatedAt: new Date().toISOString(),
  symbol: 'SPY',
  source: 'yahoo',
  providerLabel: 'Yahoo Finance (server-side)',
  quality: { rows: 300, synthetic: false },
  indicators: {
    price: forecast.start, sma20: forecast.start * 0.99, sma50: forecast.start * 0.97,
    ema12: forecast.start * 0.995, ema26: forecast.start * 0.985, rsi14: 61.2,
    atr14: 3.4, atrPercent: '0.74%', macd: 1.2, macdSignal: 0.7, macdHistogram: 0.5,
    bollingerUpper: forecast.start * 1.04, bollingerMiddle: forecast.start, bollingerLower: forecast.start * 0.96,
    bollingerPosition: 0.5, stochastic14: 72, williamsR14: -31, roc10Percent: '2.40%',
    vwap20: forecast.start * 0.995, obv: 123456789, aroonUp25: 78, meanVolume: 80000000,
    volumeRatio: 1.12, realizedVolatility21dPercent: '18.20%', pricePercentile1yPercent: '72.00%',
  },
  trend: { label: 'Uptrend', score: 4, tone: 'good', signals: ['Price above SMA20'] },
  levels: { price: forecast.start, support20: forecast.start * 0.95, resistance20: forecast.start * 1.03, support60: forecast.start * 0.9, resistance60: forecast.start * 1.08, rangePosition: 0.55 },
  sentiment: { label: 'Positive', score: 0.24, positive: 2, negative: 0 },
  indicatorDetails: indicatorDetails(market.candleMap.SPY),
  sec: costSec,
  newsSource: 'yahoo-news',
  forecast,
  analysis: {
    summary: 'Test technical scan summary', trend: 'Test trend read', sentiment: 'Test sentiment read',
    signals: ['Price above SMA20', 'MACD above signal'], risks: ['Mean reversion'],
    levels: 'Test levels read', forecast: 'Test forecast read', confidence: 0.61,
    disclaimer: 'Test disclaimer', format: 'json',
  },
};

const json = (payload, status = 200) => new Response(JSON.stringify(payload), {
  status,
  headers: { 'content-type': 'application/json' },
});
globalThis.fetch = async (input) => {
  const url = new URL(String(input));
  if (url.pathname === '/api/health') return json({
    ok: true, live: true, version: '2.0.0',
    providers: ['coinbase', 'coingecko', 'defillama', 'fred', 'yahoo'],
    ai: {
      ok: true, enabled: true, provider: 'Cloudflare Workers AI',
      framework: 'Workers AI native binding', freeTier: true,
      models: { primary: '@cf/meta/llama-3.3-70b-instruct-fp8-fast', fallback: '@cf/meta/llama-3.1-8b-instruct-fp8-fast' },
    },
  });
  if (url.pathname === '/api/market') return json(snapshot);
  if (url.pathname === '/api/macro') return json({ ok: true, source: 'live', macro: { vix: 22.4 } });
  if (url.pathname === '/api/forecast/SPY') return json({ ok: true, server: true, source: 'live', forecast });
  if (url.pathname === '/api/search') {
    return json({ ok: true, query: url.searchParams.get('q'), provider: 'Yahoo Finance search', results: [
      { symbol: 'COST', name: 'Costco Wholesale Corporation', exchange: 'NMS', exchangeDisplay: 'NASDAQ', type: 'equity', direct: false },
    ] });
  }
  if (url.pathname === '/api/quote/COST') return json(costPayload);
  if (url.pathname === '/api/ai/status') return json({
    ok: true, enabled: true, provider: 'Cloudflare Workers AI',
    framework: 'Workers AI native binding', freeTier: true,
    models: { primary: '@cf/meta/llama-3.3-70b-instruct-fp8-fast' },
  });
  if (url.pathname === '/api/ai/analysis/SPY') return json({
    ok: true, provider: 'Cloudflare Workers AI', model: '@cf/meta/llama-3.3-70b-instruct-fp8-fast',
    generatedAt: new Date().toISOString(), symbol: 'SPY', source: 'yahoo',
    providerLabel: 'Yahoo Finance (server-side)', quality: { rows: 300, synthetic: false },
    analysis: {
      summary: 'Generative test summary', stance: 'neutral', confidence: 0.7,
      technical: 'Technical test', fundamental: 'Fundamental test', macro: 'Macro test',
      sentiment: 'Sentiment test', catalysts: ['Catalyst'], risks: ['Risk'],
      actionPlan: ['Action'], disclaimer: 'Test disclaimer', format: 'json',
    },
  });
  if (url.pathname === '/api/ai/insights/SPY') return json(insightsPayload);
  if (url.pathname === '/api/ai/chat') return json({
    ok: true, provider: 'Cloudflare Workers AI', model: '@cf/meta/llama-3.3-70b-instruct-fp8-fast',
    generatedAt: new Date().toISOString(), symbol: 'SPY', reply: 'Test chat reply',
  });
  return json({ ok: false, message: 'not found' }, 404);
};

const errors = [];
window.addEventListener('error', (event) => errors.push(event.error ?? event.message));
process.on('unhandledRejection', (error) => errors.push(error));
const wait = (ms = 60) => new Promise((resolve) => setTimeout(resolve, ms));
function assert(condition, message) { if (!condition) throw new Error(message); }

await import(pathToFileURL(`${ROOT}/js/ui/app.js`).href);
if (document.readyState === 'loading') document.dispatchEvent(new window.Event('DOMContentLoaded'));
await wait(350);

assert(document.querySelector('#data-source').hidden === false, 'live badge visible');
assert(document.querySelector('#data-source-label').textContent.includes('Live'), 'live badge label');
assert(document.querySelector('#sidebar-source').textContent.includes('Multi-source'), 'sidebar source');
assert(document.querySelector('#refresh-data').hidden === false, 'refresh button visible');
assert(document.querySelectorAll('#market-table tbody tr[data-symbol]').length === 26, 'market rows after hydrate');
assert(document.querySelectorAll('#ticker-strip .ticker-item').length === 7, 'ticker after hydrate');

document.querySelector('[data-tab="forecast"]').click();
document.querySelector('#forecast-form').dispatchEvent(new window.Event('submit', { bubbles: true, cancelable: true }));
await wait(700);
assert(document.querySelector('#fc-chart-subtitle').textContent.includes('server-side'), 'server-side forecast label');
assert(document.querySelector('#fc-readiness').textContent.includes('Server'), 'server readiness');

// AI Analyst
document.querySelector('[data-tab="ai"]').click();
await wait(80);
assert(document.querySelector('#tab-ai').hidden === false, 'AI tab opens');
assert(document.querySelector('#ai-status-pill').textContent.includes('Generative'), 'AI status online');
document.querySelector('#ai-generate').click();
await wait(150);
assert(document.querySelector('#ai-analysis').textContent.includes('Generative test summary'), 'AI analysis rendered');
assert(document.querySelector('#ai-analysis').textContent.includes('Technical test'), 'AI analysis sections');
document.querySelector('#ai-input').value = 'What is the main risk?';
document.querySelector('#ai-chat-form').dispatchEvent(new window.Event('submit', { bubbles: true, cancelable: true }));
await wait(150);
assert(document.querySelector('#ai-chat').textContent.includes('Test chat reply'), 'AI chat reply rendered');

document.querySelector('#ai-scan').click();
await wait(250);
assert(document.querySelector('#ai-insights').textContent.includes('Test technical scan summary'), 'AI insights rendered');
assert(document.querySelector('#ai-insights').textContent.includes('RSI'), 'AI insight indicators rendered');
assert(document.querySelector('#ai-insights').textContent.includes('average gains'), 'AI indicator summaries rendered');
assert(document.querySelector('#ai-insights').textContent.includes('Probability up'), 'AI insight forecast stats rendered');
assert(document.querySelector('#ai-insight-chart-wrap').hidden === false, 'AI forecast chart visible');

// Global search and dynamic asset hydration.
document.querySelector('[data-tab="research"]').click();
document.querySelector('#command-open').click();
const commandInput = document.querySelector('#command-input');
commandInput.value = 'cost';
commandInput.dispatchEvent(new window.Event('input', { bubbles: true }));
await wait(450);
const costCommand = Array.from(document.querySelectorAll('#command-results [data-command-index]'))
  .find((item) => item.textContent.includes('COST'));
assert(costCommand, 'remote search result appears in command palette');
costCommand.click();
await wait(400);
assert(document.querySelector('#tab-research').hidden === false, 'dynamic asset opens research');
assert(document.querySelector('#research-symbol').value === 'COST', 'dynamic asset selected');
assert(document.querySelector('#research-fund-note').textContent.includes('Costco'), 'dynamic fundamentals rendered');
assert(document.querySelector('#research-price-canvas').width > 0, 'dynamic price chart rendered');
assert(document.querySelector('#research-technical').textContent.includes('RSI'), 'technical indicators rendered');
assert(document.querySelector('#research-technical').textContent.includes('ADX'), 'expanded technical indicators rendered');
assert(document.querySelector('#research-technical-summary').textContent.includes('indicators'), 'technical summary rendered');
assert(document.querySelector('#research-sec-note').textContent.includes('Costco'), 'SEC profile rendered');
assert(document.querySelector('#research-sec-metrics').textContent.includes('Revenue'), 'SEC metrics rendered');
assert(document.querySelector('#research-sec-filings').textContent.includes('10-K'), 'SEC filings rendered');
assert(document.querySelector('#research-news-note').textContent.includes('live Yahoo Finance'), 'live news label rendered');

if (errors.length) throw new Error(errors.map((error) => error?.stack ?? error).join('\n'));
console.log('Live hydration smoke passed: health, hydrate, badge, ticker, server forecast, AI analysis/chat/insights, search and dynamic research.');
process.exit(0);
