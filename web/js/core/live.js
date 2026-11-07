// Browser client for the optional Cloudflare Worker API. On a pure static host
// the health check fails quietly and every view keeps using the deterministic
// in-browser data. On Workers, market data and forecasts are served dynamically.

const META_BASE = typeof document !== 'undefined'
  ? document.querySelector('meta[name="ik-api"]')?.getAttribute('content')
  : null;

export const API_BASE = (typeof window !== 'undefined' && window.__IK_API_BASE__)
  || META_BASE
  || '/api';

export const live = {
  enabled: false,
  source: 'demo',
  provider: 'Deterministic local feed',
  lastUpdated: null,
  error: null,
};

export function isLive() {
  return live.enabled;
}

async function request(path, params = {}, timeout = 20000) {
  const url = new URL(`${API_BASE}${path}`, window.location.origin);
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null && value !== '') url.searchParams.set(key, String(value));
  }
  const controller = new AbortController();
  const timer = window.setTimeout(() => controller.abort(), timeout);
  try {
    const response = await fetch(url, {
      headers: { accept: 'application/json' },
      signal: controller.signal,
      cache: 'no-store',
    });
    const type = response.headers.get('content-type') ?? '';
    if (!response.ok || !type.includes('application/json')) {
      throw new Error(`API ${response.status}`);
    }
    const payload = await response.json();
    if (payload?.ok === false) throw new Error(payload.message || payload.error || 'API error');
    return payload;
  } finally {
    window.clearTimeout(timer);
  }
}

export async function checkApi() {
  try {
    const payload = await request('/health', {}, 5000);
    if (payload?.live) {
      live.enabled = true;
      live.error = null;
      return payload;
    }
  } catch (error) {
    live.enabled = false;
    live.error = error?.message ?? 'API unavailable';
  }
  return null;
}

export async function fetchMarket(symbols, options = {}) {
  const payload = await request('/market', {
    symbols: Array.isArray(symbols) ? symbols.join(',') : symbols,
    range: options.range ?? '2y',
  }, options.timeout ?? 30000);
  return payload;
}

export async function fetchMacro() {
  return request('/macro', {}, 20000);
}

export async function fetchSymbol(symbol, options = {}) {
  return request(`/quote/${encodeURIComponent(symbol)}`, {
    range: options.range ?? '2y',
  }, 20000);
}

export async function fetchServerForecast(symbol, parameters = {}) {
  return request(`/forecast/${encodeURIComponent(symbol)}`, {
    horizon: parameters.horizon,
    simulations: parameters.simulations,
    seed: parameters.seed,
    mode: parameters.mode,
    history: parameters.history,
  }, 30000);
}
