import test from 'node:test';
import assert from 'node:assert/strict';
import { handleApi } from '../src/index.js';
import { parseSearch, parseYahooNews, searchAssets } from '../src/search.js';

function jsonResponse(payload, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

const SEARCH_PAYLOAD = {
  quotes: [
    { symbol: 'AAPL', longname: 'Apple Inc.', exchange: 'NMS', exchDisp: 'NASDAQ', quoteType: 'EQUITY', sector: 'Technology' },
    { symbol: 'aapl', shortname: 'Duplicate', quoteType: 'EQUITY' },
    { symbol: 'AAPL240119C00100000', shortname: 'Apple option', quoteType: 'OPTION' },
    { symbol: '^GSPC', shortname: 'S&P 500', quoteType: 'INDEX', exchDisp: 'SNP' },
    { symbol: 'bad symbol', shortname: 'Unsafe', quoteType: 'EQUITY' },
  ],
};

test('parseSearch normalizes and filters Yahoo search results', () => {
  const results = parseSearch(SEARCH_PAYLOAD, 'AAPL');
  assert.deepEqual(results.map((result) => result.symbol), ['AAPL', '^GSPC']);
  assert.equal(results[0].name, 'Apple Inc.');
  assert.equal(results[0].type, 'equity');
  assert.equal(results[0].direct, true);
  assert.equal(results[1].type, 'index');
});

test('searchAssets queries the public Yahoo search endpoint', async () => {
  const original = globalThis.fetch;
  let requested = '';
  globalThis.fetch = async (input) => {
    requested = String(input);
    return jsonResponse(SEARCH_PAYLOAD);
  };
  try {
    const payload = await searchAssets('apple');
    assert.equal(payload.ok, true);
    assert.equal(payload.results.length, 2);
    assert.match(requested, /query1\.finance\.yahoo\.com\/v1\/finance\/search/);
    assert.match(requested, /q=apple/);
  } finally {
    globalThis.fetch = original;
  }
});

test('parseYahooNews normalizes live headlines and sentiment', () => {
  const items = parseYahooNews({
    news: [
      {
        title: 'Apple beats expectations as revenue hits record',
        publisher: 'Market Wire',
        link: 'https://finance.yahoo.com/example',
        providerPublishTime: 1_700_000_000,
      },
      {
        title: 'Apple faces regulatory probe and lawsuit',
        publisher: 'Capital Desk',
        link: 'javascript:alert(1)',
        providerPublishTime: 1_700_100_000,
      },
    ],
  }, 'AAPL');
  assert.equal(items.length, 2);
  assert.equal(items[0].live, true);
  assert.ok(items[0].sentiment > 0);
  assert.match(items[0].category, /Earnings|News/);
  assert.equal(items[1].url, null);
  assert.ok(items[1].sentiment < 0);
  assert.equal(items[1].symbol, 'AAPL');
});

test('search route is exposed and returns normalized assets', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async () => jsonResponse(SEARCH_PAYLOAD);
  try {
    const request = new Request('https://investor-kit.example/api/search?q=apple');
    const response = await handleApi(request, {}, new URL(request.url));
    assert.equal(response.status, 200);
    const payload = await response.json();
    assert.equal(payload.provider, 'Yahoo Finance search');
    assert.equal(payload.results[0].symbol, 'AAPL');
  } finally {
    globalThis.fetch = original;
  }
});
