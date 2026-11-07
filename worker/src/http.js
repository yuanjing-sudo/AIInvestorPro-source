// Shared HTTP helpers for server-side market providers. Every helper supports
// Cloudflare's edge cache and can opt out of Cache API calls when the caller is
// already close to the Workers Free plan's 50-subrequest budget.

const UA = 'Mozilla/5.0 (compatible; InvestorKitPro/2.0; +https://github.com/yuanjing-sudo/AIInvestorPro-source)';

function cacheKey(url, accept) {
  return new Request(url, { method: 'GET', headers: { accept } });
}

export async function cachedFetch(url, options = {}) {
  const ttl = options.ttl ?? 300;
  const accept = options.accept ?? 'application/json';
  const label = options.label ?? 'Upstream';
  const useCache = options.cache !== false;
  const edgeCache = useCache && typeof caches !== 'undefined' ? caches.default : null;
  const key = cacheKey(url, accept);
  if (edgeCache) {
    try {
      const hit = await edgeCache.match(key);
      if (hit) return hit.text();
    } catch {
      // Continue with a network request if the edge cache is unavailable.
    }
  }
  const response = await fetch(url, {
    headers: {
      accept,
      'user-agent': UA,
      ...options.headers,
    },
    cf: { cacheTtl: ttl, cacheEverything: true },
  });
  if (!response.ok) throw new Error(`${label} responded ${response.status}`);
  const text = await response.text();
  if (!text) throw new Error(`${label} returned an empty response`);
  if (edgeCache) {
    try {
      await edgeCache.put(key, new Response(text, {
        headers: {
          'content-type': response.headers.get('content-type') || accept,
          'cache-control': `public, max-age=${ttl}`,
        },
      }));
    } catch {
      // Cache writes are best-effort; a cache miss must never break the API.
    }
  }
  return text;
}

export async function cachedJson(url, options = {}) {
  const text = await cachedFetch(url, { ...options, accept: 'application/json' });
  return JSON.parse(text);
}

export async function cachedText(url, options = {}) {
  return cachedFetch(url, { ...options, accept: options.accept ?? 'text/csv,text/plain,*/*' });
}
