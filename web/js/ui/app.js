// App shell: tab navigation, theme, install prompt, service worker and boot.

import { state, $, $$, redrawCharts, toast } from './shared.js';
import { initDashboard, renderDashboard } from './dashboard.js';
import { initBacktest } from './backtest-view.js';
import { initOptimize } from './optimize-view.js';
import { initRisk } from './risk-view.js';
import { initScreener } from './screener-view.js';
import { initPortfolio } from './portfolio-view.js';
import { initAlerts } from './alerts-view.js';

const TABS = ['dashboard', 'backtest', 'optimize', 'risk', 'screener', 'portfolio', 'alerts', 'platform'];
let installPrompt = null;

function setTab(tab, options = {}) {
  const target = TABS.includes(tab) ? tab : 'dashboard';
  state.tab = target;
  for (const button of $$('.tab')) {
    const active = button.dataset.tab === target;
    button.classList.toggle('is-active', active);
    button.setAttribute('aria-selected', String(active));
  }
  for (const panel of $$('.tab-panel')) {
    const active = panel.id === `tab-${target}`;
    panel.hidden = !active;
    panel.classList.toggle('is-active', active);
  }
  if (target === 'dashboard') renderDashboard();
  if (options.updateUrl !== false) {
    try {
      const url = new URL(window.location.href);
      url.searchParams.set('tab', target);
      window.history.replaceState(null, '', url);
    } catch {
      // History can be restricted in some embedding contexts; navigation still works.
    }
  }
  window.requestAnimationFrame(() => redrawCharts());
}

function initNavigation() {
  for (const button of $$('.tab')) {
    button.addEventListener('click', () => setTab(button.dataset.tab));
  }
  document.addEventListener('click', (event) => {
    const trigger = event.target.closest('[data-goto]');
    if (!trigger) return;
    setTab(trigger.dataset.goto);
  });
  $('.tabs').addEventListener('keydown', (event) => {
    if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
    const tabs = $$('.tab');
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
  const label = pill.querySelector('span:last-child');
  if (!navigator.onLine) {
    pill.classList.add('offline');
    label.textContent = 'Offline';
    return;
  }
  pill.classList.remove('offline');
  label.textContent = state.swReady ? 'Offline-ready' : 'Local-first';
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

function boot() {
  initNavigation();
  initTheme();
  initInstall();
  initDashboard();
  initBacktest();
  initOptimize();
  initRisk();
  initScreener();
  initPortfolio();
  initAlerts();

  const requested = new URLSearchParams(window.location.search).get('tab');
  setTab(TABS.includes(requested) ? requested : 'dashboard', { updateUrl: false });
  initOffline();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', boot, { once: true });
} else {
  boot();
}
