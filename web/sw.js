/* InvestorKit service worker: offline-first for the app shell and analytics. */
const CACHE = 'investor-kit-v4';
const ASSETS = [
  './',
  './index.html',
  './styles.css',
  './manifest.webmanifest',
  './icons/icon.svg',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './js/core/math.js',
  './js/core/indicators.js',
  './js/core/analytics.js',
  './js/core/marketdata.js',
  './js/core/risk.js',
  './js/core/optimizer.js',
  './js/core/strategies.js',
  './js/core/backtest.js',
  './js/core/screener.js',
  './js/core/taxlots.js',
  './js/core/alerts.js',
  './js/core/forecast.js',
  './js/core/live.js',
  './js/ui/charts.js',
  './js/ui/shared.js',
  './js/ui/dashboard.js',
  './js/ui/research-view.js',
  './js/ui/forecast-view.js',
  './js/ui/backtest-view.js',
  './js/ui/optimize-view.js',
  './js/ui/risk-view.js',
  './js/ui/screener-view.js',
  './js/ui/portfolio-view.js',
  './js/ui/alerts-view.js',
  './js/ui/app.js',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(ASSETS)).then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  // Never cache the Worker API: live quotes and forecasts must stay dynamic.
  if (url.pathname.startsWith('/api/')) return;

  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request)
        .then((response) => {
          const copy = response.clone();
          caches.open(CACHE).then((cache) => cache.put('./index.html', copy));
          return response;
        })
        .catch(() => caches.match('./index.html').then((cached) => cached ?? caches.match('./'))),
    );
    return;
  }

  event.respondWith(
    caches.match(request).then((cached) => {
      if (cached) return cached;
      return fetch(request).then((response) => {
        if (!response || response.status !== 200 || response.type === 'opaque') return response;
        const copy = response.clone();
        caches.open(CACHE).then((cache) => cache.put(request, copy));
        return response;
      });
    }),
  );
});
