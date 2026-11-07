import { readFileSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { JSDOM } from 'jsdom';
import { marketSnapshot } from '../js/core/marketdata.js';
import { buildForecast } from '../js/core/forecast.js';

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

const json = (payload, status = 200) => new Response(JSON.stringify(payload), {
  status,
  headers: { 'content-type': 'application/json' },
});
globalThis.fetch = async (input) => {
  const url = new URL(String(input));
  if (url.pathname === '/api/health') return json({ ok: true, live: true, version: '2.0.0', providers: ['coinbase', 'coingecko', 'defillama', 'fred', 'yahoo'] });
  if (url.pathname === '/api/market') return json(snapshot);
  if (url.pathname === '/api/macro') return json({ ok: true, source: 'live', macro: { vix: 22.4 } });
  if (url.pathname === '/api/forecast/SPY') return json({ ok: true, server: true, source: 'live', forecast });
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

if (errors.length) throw new Error(errors.map((error) => error?.stack ?? error).join('\n'));
console.log('Live hydration smoke passed: health, hydrate, badge, ticker, server forecast.');
process.exit(0);
