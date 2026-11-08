import { readFileSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { JSDOM } from 'jsdom';

// A dependency-light browser smoke test: loads the real index.html, installs a
// canvas stub, imports the actual application modules and drives every tab.
// Run with: npm run test:ui

const ROOT = fileURLToPath(new URL('..', import.meta.url));
const html = readFileSync(`${ROOT}/index.html`, 'utf8');
const dom = new JSDOM(html, {
  url: 'http://localhost/',
  pretendToBeVisual: true,
  runScripts: 'outside-only',
});

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
  set(target, prop, value) {
    target[prop] = value;
    return true;
  },
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

const errors = [];
window.addEventListener('error', (event) => errors.push(event.error ?? event.message));
process.on('unhandledRejection', (error) => errors.push(error));

const wait = (ms = 60) => new Promise((resolve) => setTimeout(resolve, ms));
function assert(condition, message) {
  if (!condition) throw new Error(message);
}
function submit(selector) {
  const form = document.querySelector(selector);
  form.dispatchEvent(new window.Event('submit', { bubbles: true, cancelable: true }));
}
function click(selector) {
  const element = document.querySelector(selector);
  element.dispatchEvent(new window.MouseEvent('click', { bubbles: true, cancelable: true }));
}

await import(pathToFileURL(`${ROOT}/js/ui/app.js`).href);
if (document.readyState === 'loading') {
  document.dispatchEvent(new window.Event('DOMContentLoaded'));
}
await wait(120);

// Dashboard
assert(document.querySelectorAll('#dashboard-stats .stat').length === 4, 'dashboard stat cards');
assert(document.querySelectorAll('#market-table tbody tr[data-symbol]').length === 26, 'market rows');
assert(document.querySelectorAll('#signal-cards .signal-card').length === 8, 'signal cards');
assert(document.querySelectorAll('#ticker-strip .ticker-item').length === 7, 'ticker items');
assert(document.querySelector('#asset-chart').width > 0, 'asset chart sized');

// Research terminal
document.querySelector('[data-tab="research"]').click();
await wait(80);
assert(document.querySelectorAll('#research-stats .stat').length === 8, 'research stats');
assert(document.querySelectorAll('#research-correlation tbody tr').length >= 5, 'correlation matrix');
assert(document.querySelectorAll('#research-news .news-item').length >= 4, 'research news');
assert(document.querySelectorAll('#research-fundamentals tbody tr').length >= 8, 'fundamental rows');
assert(document.querySelectorAll('#research-macro .macro-cell').length >= 8, 'macro cells');
assert(document.querySelectorAll('#research-horizons .horizon-cell').length === 8, 'multi-horizon scorecard');

// Forecast studio
document.querySelector('[data-tab="forecast"]').click();
submit('#forecast-form');
await wait(900);
assert(document.querySelector('#forecast-results').hidden === false, 'forecast results visible');
assert(document.querySelectorAll('#fc-stats .stat').length === 8, 'forecast stats');
assert(document.querySelectorAll('#fc-models .model-row').length === 3, 'forecast models');
assert(document.querySelectorAll('#fc-diagnostics .metric-cell').length === 8, 'forecast diagnostics');
assert(document.querySelectorAll('#fc-scenarios .scenario-row').length === 3, 'forecast scenarios');
assert(document.querySelector('#fc-chart').width > 0, 'forecast chart sized');

// AI Analyst (static build: clear Worker/AI requirement, no crash)
document.querySelector('[data-tab="ai"]').click();
await wait(40);
assert(document.querySelector('#tab-ai').hidden === false, 'AI tab opens');
assert(document.querySelector('#ai-analysis').textContent.includes('Cloudflare Workers'), 'AI tab explains Worker requirement');
assert(document.querySelector('#ai-symbol').options.length === 26, 'AI symbol selector populated');

// Command palette
document.querySelector('#command-open').click();
await wait(30);
assert(document.querySelectorAll('#command-results .command-item').length > 0, 'command palette results');
document.querySelector('#command-input').value = 'NVDA';
document.querySelector('#command-input').dispatchEvent(new window.Event('input', { bubbles: true }));
await wait(20);
assert(document.querySelector('#command-results').textContent.includes('NVDA'), 'command palette filters assets');

// Backtest
document.querySelector('[data-tab="backtest"]').click();
document.querySelector('#bt-strategy').value = 'smaCross';
document.querySelector('#bt-strategy').dispatchEvent(new window.Event('change', { bubbles: true }));
submit('#backtest-form');
await wait(120);
assert(document.querySelector('#backtest-results').hidden === false, 'backtest results visible');
assert(document.querySelectorAll('#bt-stats .stat').length === 10, 'backtest stats');
assert(document.querySelectorAll('#bt-trades tbody tr').length > 0, 'backtest trades');

// Optimize
document.querySelector('[data-tab="optimize"]').click();
submit('#optimize-form');
await wait(180);
assert(document.querySelector('#optimize-results').hidden === false, 'optimize results visible');
assert(document.querySelectorAll('#opt-stats .stat').length === 6, 'optimize stats');
assert(document.querySelectorAll('#opt-weights tbody tr').length >= 2, 'optimizer weights');
assert(document.querySelectorAll('#opt-bars .bar-row').length >= 2, 'optimizer bars');

// Risk
document.querySelector('[data-tab="risk"]').click();
submit('#risk-form');
await wait(300);
assert(document.querySelector('#risk-results').hidden === false, 'risk results visible');
assert(document.querySelectorAll('#risk-stats .stat').length === 8, 'risk stats');
assert(document.querySelectorAll('#stress-table tbody tr').length === 5, 'stress rows');
assert(document.querySelectorAll('#risk-bars .bar-row').length >= 2, 'risk bars');

// Screener
document.querySelector('[data-tab="screener"]').click();
submit('#screener-form');
await wait(60);
assert(document.querySelectorAll('#screener-table tbody tr[data-symbol]').length > 0, 'screener rows');

// Portfolio buy + sell
document.querySelector('[data-tab="portfolio"]').click();
const txSymbol = document.querySelector('#tx-symbol');
txSymbol.value = 'AAPL';
txSymbol.dispatchEvent(new window.Event('change', { bubbles: true }));
document.querySelector('#tx-side').value = 'buy';
document.querySelector('#tx-quantity').value = '2';
document.querySelector('#tx-price').value = '100';
document.querySelector('#tx-fee').value = '1';
submit('#transaction-form');
await wait(60);
const holdingRows = [...document.querySelectorAll('#holdings-table tbody tr')];
assert(holdingRows.some((row) => row.textContent.includes('AAPL')), 'buy creates holding');

document.querySelector('#tx-side').value = 'sell';
document.querySelector('#tx-quantity').value = '1';
document.querySelector('#tx-price').value = '120';
document.querySelector('#tx-fee').value = '0';
submit('#transaction-form');
await wait(60);
document.querySelector('#tax-symbol').value = 'AAPL';
document.querySelector('#tax-quantity').value = '1';
document.querySelector('#tax-price').value = '130';
submit('#tax-form');
await wait(30);
assert(document.querySelectorAll('#tax-table tbody tr').length === 4, 'tax comparison rows');

// Alerts
document.querySelector('[data-tab="alerts"]').click();
document.querySelector('#alert-symbol').value = 'AAPL';
document.querySelector('#alert-type').value = 'priceAbove';
document.querySelector('#alert-type').dispatchEvent(new window.Event('change', { bubbles: true }));
document.querySelector('#alert-threshold').value = '0';
submit('#alert-form');
await wait(30);
assert(document.querySelectorAll('#alerts-list .list-item').length === 1, 'alert rule created');
click('#alerts-check');
await wait(30);
assert(document.querySelectorAll('#alerts-history .list-item').length === 1, 'alert history');

// Platform + navigation
document.querySelector('[data-tab="platform"]').click();
assert(document.querySelector('#tab-platform').hidden === false, 'platform tab opens');
document.querySelector('[data-tab="dashboard"]').click();
assert(document.querySelector('#tab-dashboard').hidden === false, 'dashboard tab opens');

if (errors.length) {
  throw new Error(`Browser errors: ${errors.map((error) => error?.stack ?? error).join('\n')}`);
}

console.log('UI smoke passed: dashboard, research, forecast, AI analyst, backtest, optimize, risk, screener, portfolio, tax lots, alerts, command palette, navigation.');
