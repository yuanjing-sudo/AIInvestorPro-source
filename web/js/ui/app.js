// App shell: navigation, command palette, ticker, theme, install prompt,
// service worker and boot.

import {
  UNIVERSE, state, quotes, candleMap, $, $$, redrawCharts, toast,
  escapeHtml, dateShort, formatSignedPercent, signClass, hydrateMarket,
} from './shared.js';
import { checkApi, fetchMacro, fetchMarket, live } from '../core/live.js';
import { initDashboard, renderDashboard } from './dashboard.js';
import { initBacktest } from './backtest-view.js';
import { initOptimize } from './optimize-view.js';
import { initRisk } from './risk-view.js';
import { initScreener } from './screener-view.js';
import { initPortfolio } from './portfolio-view.js';
import { initAlerts } from './alerts-view.js';
import { initResearch, renderResearch } from './research-view.js';
import { initForecast } from './forecast-view.js';

const TABS = [
  'dashboard', 'research', 'forecast', 'backtest', 'optimize',
  'risk', 'screener', 'portfolio', 'alerts', 'platform',
];

const PAGE_META = {
  dashboard: { label: 'Dashboard', hint: 'Portfolio overview and market board' },
  research: { label: 'Research terminal', hint: 'Fundamentals, macro, correlation, sentiment' },
  forecast: { label: 'Forecast studio', hint: 'Ensemble model with confidence intervals' },
  backtest: { label: 'Backtest', hint: 'Strategy research with costs and slippage' },
  optimize: { label: 'Optimize', hint: 'Constrained portfolio construction' },
  risk: { label: 'Risk lab', hint: 'Monte Carlo, VaR and stress scenarios' },
  screener: { label: 'Screener', hint: 'Rank the universe by factor score' },
  portfolio: { label: 'Ledger & tax', hint: 'Holdings, lots and realized gains' },
  alerts: { label: 'Alerts', hint: 'Local price and indicator rules' },
  platform: { label: 'Platform', hint: 'Install, offline and architecture' },
};

const TICKER_SYMBOLS = ['SPY', 'QQQ', 'BTC-USD', 'NVDA', 'GLD', 'TLT', 'AAPL'];

let installPrompt = null;
let commandActive = 0;
let commandItems = [];

function setTab(tab, options = {}) {
  const target = TABS.includes(tab) ? tab : 'dashboard';
  state.tab = target;
  for (const button of $$('.tab')) {
    const active = button.dataset.tab === target;
    button.classList.toggle('is-active', active);
    if (button.hasAttribute('role')) button.setAttribute('aria-selected', String(active));
  }
  for (const panel of $$('.tab-panel')) {
    const active = panel.id === `tab-${target}`;
    panel.hidden = !active;
    panel.classList.toggle('is-active', active);
  }
  if (target === 'dashboard') renderDashboard();
  if (target === 'research') renderResearch();
  if (options.updateUrl !== false) {
    try {
      const url = new URL(window.location.href);
      url.searchParams.set('tab', target);
      window.history.replaceState(null, '', url);
    } catch {
      // History can be restricted in some embedding contexts.
    }
  }
  window.requestAnimationFrame(() => redrawCharts());
}

function initNavigation() {
  for (const button of $$('.tab')) {
    button.addEventListener('click', () => {
      if (button.dataset.command) return;
      if (button.dataset.tab) setTab(button.dataset.tab);
    });
  }
  document.addEventListener('click', (event) => {
    const trigger = event.target.closest('[data-goto]');
    if (!trigger) return;
    setTab(trigger.dataset.goto);
  });
  $('.tabs').addEventListener('keydown', (event) => {
    if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
    const tabs = $$('.tab', $('.tabs'));
    const current = tabs.indexOf(document.activeElement);
    if (current < 0) return;
    event.preventDefault();
    const next = (current + (event.key === 'ArrowRight' ? 1 : -1) + tabs.length) % tabs.length;
    tabs[next].focus();
    setTab(tabs[next].dataset.tab);
  });
  document.addEventListener('ik:open-symbol', (event) => {
    const symbol = event.detail?.symbol;
    if (!symbol) return;
    state.symbol = symbol;
    setTab('dashboard');
  });
  document.addEventListener('click', (event) => {
    const ticker = event.target.closest('[data-ticker-symbol]');
    if (!ticker) return;
    state.symbol = ticker.dataset.tickerSymbol;
    setTab('dashboard');
  });
}

function sparkline(values) {
  if (!values.length) return '';
  const min = Math.min(...values);
  const max = Math.max(...values);
  const range = max - min || 1;
  const points = values.map((value, index) => {
    const x = (index / Math.max(1, values.length - 1)) * 42;
    const y = 16 - ((value - min) / range) * 14;
    return `${x.toFixed(1)},${y.toFixed(1)}`;
  }).join(' ');
  const up = values[values.length - 1] >= values[0];
  return `<svg class="ticker-spark" viewBox="0 0 42 18" aria-hidden="true"><polyline points="${points}" fill="none" stroke="${up ? 'var(--good)' : 'var(--danger)'}" stroke-width="1.4" stroke-linejoin="round" stroke-linecap="round"/></svg>`;
}

function initTicker() {
  const strip = $('#ticker-strip');
  if (!strip) return;
  strip.innerHTML = TICKER_SYMBOLS.map((symbol) => {
    const quote = quotes[symbol];
    if (!quote) return '';
    const candles = candleMap[symbol].slice(-32).map((candle) => candle.close);
    return `<button type="button" class="ticker-item" data-ticker-symbol="${symbol}" title="${escapeHtml(symbol)} · click to chart">
      <span class="ticker-symbol">${symbol}</span>
      <span class="ticker-price">${quote.price.toLocaleString(undefined, { maximumFractionDigits: 2 })}</span>
      <span class="ticker-change ${signClass(quote.changePercent)}">${formatSignedPercent(quote.changePercent / 100, 2)}</span>
      ${sparkline(candles)}
    </button>`;
  }).join('');

  const spy = candleMap.SPY;
  const date = spy.at(-1)?.date;
  $('#header-asof').textContent = date ? `As of ${dateShort(date)}` : '—';
  $('#sidebar-rows').textContent = `${(spy.length * UNIVERSE.length).toLocaleString()} bars`;
  $('#sidebar-close').textContent = date ? dateShort(date) : '—';
}

function applyDataSource() {
  const badge = $('#data-source');
  const label = $('#data-source-label');
  if (!badge || !label) return;
  badge.hidden = !live.enabled;
  if (!live.enabled) {
    $('#refresh-data').hidden = true;
    const source = $('#sidebar-source');
    if (source) source.textContent = 'Demo · local';
    const copy = $('#sidebar-copy');
    if (copy) copy.textContent = '26 assets · 3 years of OHLCV · fundamentals, macro and sentiment lines.';
    return;
  }
  const source = live.source === 'live' ? 'Live · Yahoo' : live.source === 'mixed' ? 'Live · mixed' : 'Server · fallback';
  label.textContent = source;
  $('#refresh-data').hidden = false;
  const sidebarSource = $('#sidebar-source');
  if (sidebarSource) sidebarSource.textContent = live.source === 'live' ? 'Yahoo · live' : 'Worker · mixed';
  const copy = $('#sidebar-copy');
  if (copy) copy.textContent = `${live.provider}. Prices and candles are hydrated from the Worker API; the local feed remains the offline fallback.`;
}

async function loadLiveData(options = {}) {
  if (!live.enabled) return false;
  const button = $('#refresh-data');
  button?.classList.add('is-busy');
  try {
    const symbols = UNIVERSE.map((asset) => asset.symbol);
    const [snapshot, macroPayload] = await Promise.all([
      fetchMarket(symbols, { range: '2y' }),
      fetchMacro().catch(() => null),
    ]);
    if (macroPayload?.macro) snapshot.macro = macroPayload.macro;
    live.source = snapshot.source ?? 'live';
    live.provider = snapshot.provider ?? 'Cloudflare Worker API';
    live.lastUpdated = snapshot.generatedAt ?? new Date().toISOString();
    live.error = null;
    hydrateMarket(snapshot);
    initTicker();
    applyDataSource();
    if (options.announce) toast(`Live data refreshed · ${live.source} · ${dateShort(live.lastUpdated)}`);
    return true;
  } catch (error) {
    live.error = error?.message ?? 'Live data unavailable';
    applyDataSource();
    if (options.announce) toast(`Live refresh failed: ${live.error}`);
    return false;
  } finally {
    button?.classList.remove('is-busy');
  }
}

async function initLiveData() {
  const health = await checkApi();
  if (!health) {
    applyDataSource();
    return;
  }
  live.enabled = true;
  live.provider = 'Yahoo Finance via Cloudflare Worker';
  live.source = 'mixed';
  applyDataSource();
  await loadLiveData();
  $('#refresh-data')?.addEventListener('click', () => loadLiveData({ announce: true }));
  window.setInterval(() => {
    if (live.enabled && document.visibilityState === 'visible') loadLiveData();
  }, 5 * 60 * 1000);
}

function initTheme() {
  const button = $('#theme-button');
  let saved = null;
  try { saved = localStorage.getItem('ik.theme'); } catch { saved = null; }
  if (!saved && window.matchMedia?.('(prefers-color-scheme: light)').matches) {
    document.documentElement.dataset.theme = 'light';
  }
  const updateLabel = () => {
    const mode = document.documentElement.dataset.theme === 'light' ? 'light' : 'dark';
    button.title = `Switch to ${mode === 'light' ? 'dark' : 'light'} theme`;
    button.setAttribute('aria-label', button.title);
  };
  button.addEventListener('click', () => {
    const next = document.documentElement.dataset.theme === 'light' ? 'dark' : 'light';
    document.documentElement.dataset.theme = next;
    try { localStorage.setItem('ik.theme', next); } catch { /* ignore */ }
    updateLabel();
    redrawCharts();
  });
  updateLabel();
}

function initInstall() {
  const button = $('#install-button');
  window.addEventListener('beforeinstallprompt', (event) => {
    event.preventDefault();
    installPrompt = event;
    button.hidden = false;
  });
  button.addEventListener('click', async () => {
    if (!installPrompt) return;
    installPrompt.prompt();
    try {
      await installPrompt.userChoice;
    } catch {
      // The prompt can be dismissed by the platform.
    }
    installPrompt = null;
    button.hidden = true;
  });
  window.addEventListener('appinstalled', () => {
    installPrompt = null;
    button.hidden = true;
    toast('InvestorKit installed. It now works offline.');
  });
}

function updateStatus() {
  const pill = $('#offline-status');
  if (!pill) return;
  const label = pill.querySelector('span:last-child');
  if (!navigator.onLine) {
    pill.classList.add('offline');
    if (label) label.textContent = 'Offline';
    return;
  }
  pill.classList.remove('offline');
  if (label) label.textContent = state.swReady ? 'Offline-ready' : 'Local-first';
}

function initOffline() {
  window.addEventListener('online', updateStatus);
  window.addEventListener('offline', updateStatus);
  updateStatus();
  if ('serviceWorker' in navigator && window.location.protocol.startsWith('http')) {
    navigator.serviceWorker.register(new URL('../../sw.js', import.meta.url))
      .then(() => {
        state.swReady = true;
        updateStatus();
      })
      .catch(() => {
        state.swReady = false;
        updateStatus();
      });
  }
}

// ---------------------------------------------------------------------------
// Command palette
// ---------------------------------------------------------------------------

function openCommand() {
  const dialog = $('#command-palette');
  if (!dialog) return;
  $('#command-input').value = '';
  renderCommand('');
  if (typeof dialog.showModal === 'function') {
    if (!dialog.open) dialog.showModal();
  } else {
    dialog.setAttribute('open', '');
  }
  window.setTimeout(() => $('#command-input')?.focus(), 20);
}

function closeCommand() {
  const dialog = $('#command-palette');
  if (!dialog) return;
  if (typeof dialog.close === 'function' && dialog.open) dialog.close();
  else dialog.removeAttribute('open');
}

function commandEntries(query) {
  const normalized = query.trim().toLowerCase();
  const pages = TABS.map((tab) => ({
    type: 'page',
    tab,
    label: PAGE_META[tab].label,
    hint: PAGE_META[tab].hint,
  }));
  const assets = UNIVERSE.map((asset) => ({
    type: 'asset',
    symbol: asset.symbol,
    label: `${asset.symbol} · ${asset.name}`,
    hint: `${asset.sector} · ${asset.kind}`,
  }));
  return [...pages, ...assets].filter((item) => {
    if (!normalized) return true;
    return `${item.label} ${item.hint} ${item.symbol ?? ''}`.toLowerCase().includes(normalized);
  }).slice(0, 28);
}

function renderCommand(query) {
  const results = $('#command-results');
  if (!results) return;
  commandItems = commandEntries(query);
  commandActive = Math.min(commandActive, Math.max(0, commandItems.length - 1));
  if (!commandItems.length) {
    results.innerHTML = '<p class="empty-state" style="padding:18px">No matches. Try a ticker, sector or page.</p>';
    return;
  }
  let lastType = '';
  results.innerHTML = commandItems.map((item, index) => {
    const group = item.type !== lastType
      ? `<div class="command-group">${item.type === 'page' ? 'Pages' : 'Assets'}</div>`
      : '';
    lastType = item.type;
    const symbol = item.type === 'asset' ? `<span class="command-symbol">${item.symbol}</span>` : '<span class="command-symbol">→</span>';
    return `${group}<button type="button" class="command-item ${index === commandActive ? 'is-active' : ''}" data-command-index="${index}" role="option">
      ${symbol}<span>${escapeHtml(item.label)}</span><small>${escapeHtml(item.hint)}</small>
    </button>`;
  }).join('');
}

function activateCommand(index) {
  const item = commandItems[index];
  if (!item) return;
  closeCommand();
  if (item.type === 'page') setTab(item.tab);
  if (item.type === 'asset') {
    state.symbol = item.symbol;
    state.research.symbol = item.symbol;
    setTab('research');
    toast(`${item.symbol} loaded in Research`);
  }
}

function initCommand() {
  const dialog = $('#command-palette');
  if (!dialog) return;
  $('#command-open')?.addEventListener('click', openCommand);
  $('#mobile-more')?.addEventListener('click', (event) => {
    event.preventDefault();
    openCommand();
  });
  $('#command-input')?.addEventListener('input', (event) => {
    commandActive = 0;
    renderCommand(event.target.value);
  });
  $('#command-input')?.addEventListener('keydown', (event) => {
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      if (!commandItems.length) return;
      commandActive = (commandActive + (event.key === 'ArrowDown' ? 1 : -1) + commandItems.length) % commandItems.length;
      renderCommand($('#command-input').value);
      $('.command-item.is-active')?.scrollIntoView({ block: 'nearest' });
    }
    if (event.key === 'Enter') {
      event.preventDefault();
      activateCommand(commandActive);
    }
    if (event.key === 'Escape') closeCommand();
  });
  $('#command-results')?.addEventListener('click', (event) => {
    const item = event.target.closest('[data-command-index]');
    if (!item) return;
    activateCommand(Number(item.dataset.commandIndex));
  });
  dialog.addEventListener('click', (event) => {
    if (event.target === dialog) closeCommand();
  });
  document.addEventListener('keydown', (event) => {
    const modifier = event.metaKey || event.ctrlKey;
    if (modifier && event.key.toLowerCase() === 'k') {
      event.preventDefault();
      if (dialog.open || dialog.hasAttribute('open')) closeCommand();
      else openCommand();
    }
    if (event.key === 'Escape' && (dialog.open || dialog.hasAttribute('open'))) closeCommand();
    if (event.key === '/' && !/input|textarea|select/i.test(document.activeElement?.tagName ?? '')) {
      event.preventDefault();
      openCommand();
    }
  });
}

function boot() {
  initNavigation();
  initTheme();
  initInstall();
  initTicker();
  initCommand();
  initDashboard();
  initBacktest();
  initOptimize();
  initRisk();
  initScreener();
  initPortfolio();
  initAlerts();
  initResearch();
  initForecast();

  const requested = new URLSearchParams(window.location.search).get('tab');
  setTab(TABS.includes(requested) ? requested : 'dashboard', { updateUrl: false });
  initOffline();
  initLiveData();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', boot, { once: true });
} else {
  boot();
}
