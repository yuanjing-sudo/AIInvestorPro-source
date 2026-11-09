// Cloudflare Worker entry point for InvestorKit Pro.
//
// The Worker serves the static PWA through the ASSETS binding and exposes a
// small server-side API: live market snapshots, quotes, macro data and forecast
// execution. The browser falls back to its deterministic local feed if this API
// is unavailable (for example on the static GitHub Pages deployment).

import {
  ALLOWED_SYMBOLS, buildForecastPayload, buildMacro, buildSnapshot, buildSourceCatalog,
  buildSymbol, requireSymbol, resolveSymbols,
} from './market.js';
import { UNIVERSE } from '../../web/js/core/marketdata.js';
import { aiStatus, chatWithAi, generateAnalysis, generateInsights, readJsonBody } from './ai.js';
import { searchAssets } from './search.js';

const VERSION = '2.0.0';
const RANGE_VALUES = new Set(['1mo', '3mo', '6mo', '1y', '2y', '3y']);

function corsHeaders() {
  return {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET, POST, OPTIONS',
    'access-control-allow-headers': 'content-type, accept',
    'access-control-max-age': '86400',
  };
}

function json(payload, status = 200, cacheSeconds = 0) {
  const headers = {
    'content-type': 'application/json; charset=utf-8',
    'x-content-type-options': 'nosniff',
    ...corsHeaders(),
  };
  if (cacheSeconds > 0) {
    headers['cache-control'] = `public, max-age=${cacheSeconds}, stale-while-revalidate=${cacheSeconds * 4}`;
  } else {
    headers['cache-control'] = 'no-store';
  }
  return new Response(JSON.stringify(payload), { status, headers });
}

function errorResponse(error) {
  const status = Number(error?.status) || 500;
  return json({
    ok: false,
    error: status >= 500 ? 'Upstream or server error' : 'Request error',
    message: error?.message ?? 'Unknown error',
  }, status);
}

function rangeFrom(value) {
  return RANGE_VALUES.has(value) ? value : '2y';
}

async function handleApi(request, env, url) {
  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders() });
  }
  const parts = url.pathname.split('/').filter(Boolean);
  // parts: ['api', 'market'] or ['api', 'forecast', 'SPY']
  const route = parts[1] ?? '';
  const aiPath = url.pathname.startsWith('/api/ai/');
  if (request.method !== 'GET' && request.method !== 'HEAD' && !(aiPath && request.method === 'POST')) {
    return json({ ok: false, error: 'Method not allowed' }, 405);
  }

  if (route === 'health') {
    return json({
      ok: true,
      service: 'investor-kit-worker',
      version: VERSION,
      runtime: 'cloudflare-workers',
      live: true,
      assets: UNIVERSE.length,
      providers: buildSourceCatalog().providers.filter((provider) => provider.status === 'active').map((provider) => provider.id),
      ai: aiStatus(env),
      now: new Date().toISOString(),
      endpoints: ['/api/health', '/api/sources', '/api/search', '/api/market', '/api/quote/:symbol', '/api/forecast/:symbol', '/api/macro', '/api/ai/status', '/api/ai/chat', '/api/ai/analysis/:symbol', '/api/ai/insights/:symbol'],
    }, 200, 30);
  }

  if (route === 'universe') {
    return json({ ok: true, assets: UNIVERSE, symbols: ALLOWED_SYMBOLS }, 200, 3600);
  }

  if (route === 'sources') {
    return json(buildSourceCatalog(), 200, 3600);
  }

  if (route === 'search') {
    const payload = await searchAssets(url.searchParams.get('q') ?? '', { env });
    return json(payload, 200, 300);
  }

  if (route === 'market') {
    const symbols = resolveSymbols(url.searchParams.get('symbols') ?? '');
    if (!symbols.length) return json({ ok: false, error: 'No valid symbols requested' }, 400);
    const snapshot = await buildSnapshot(symbols, {
      range: rangeFrom(url.searchParams.get('range')),
      env,
    });
    return json(snapshot, 200, 60);
  }

  if (route === 'quote' || route === 'symbol') {
    const symbol = requireSymbol(parts[2] ?? '');
    const payload = await buildSymbol(symbol, {
      range: rangeFrom(url.searchParams.get('range')),
      env,
    });
    return json(payload, 200, 60);
  }

  if (route === 'forecast') {
    const symbol = requireSymbol(parts[2] ?? '');
    const payload = await buildForecastPayload(symbol, Object.fromEntries(url.searchParams), { env });
    return json(payload, 200, 120);
  }

  if (route === 'macro') {
    const payload = await buildMacro(env);
    return json(payload, 200, 300);
  }

  if (route === 'ai') {
    const action = parts[2] ?? '';
    if (action === 'status') {
      if (request.method !== 'GET' && request.method !== 'HEAD') {
        return json({ ok: false, error: 'Method not allowed' }, 405);
      }
      return json(aiStatus(env), 200, 60);
    }
    if (request.method !== 'POST') {
      return json({ ok: false, error: 'Method not allowed' }, 405);
    }
    if (action === 'chat') {
      const body = await readJsonBody(request);
      const payload = await chatWithAi(env, body.messages, { symbol: body.symbol });
      return json(payload, 200, 0);
    }
    if (action === 'analysis') {
      const symbol = requireSymbol(parts[3] ?? '');
      const body = await readJsonBody(request);
      const payload = await generateAnalysis(env, symbol, body);
      return json(payload, 200, 0);
    }
    if (action === 'insights') {
      const symbol = requireSymbol(parts[3] ?? '');
      const body = await readJsonBody(request);
      const payload = await generateInsights(env, symbol, body);
      return json(payload, 200, 0);
    }
    return json({ ok: false, error: 'Unknown AI route' }, 404);
  }

  return json({ ok: false, error: 'Unknown API route' }, 404);
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname.startsWith('/api/')) {
      try {
        return await handleApi(request, env, url);
      } catch (error) {
        return errorResponse(error);
      }
    }
    // All non-API requests are static assets. The ASSETS binding resolves the
    // correct file, including index.html for the app shell.
    if (env?.ASSETS) return env.ASSETS.fetch(request);
    return new Response('InvestorKit assets binding is not configured.', {
      status: 500,
      headers: { 'content-type': 'text/plain; charset=utf-8' },
    });
  },
};

export { handleApi };
