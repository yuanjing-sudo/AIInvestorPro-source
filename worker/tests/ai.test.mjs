import test from 'node:test';
import assert from 'node:assert/strict';
import { handleApi } from '../src/index.js';
import {
  AI_MODELS, aiStatus, chatWithAi, parseAnalysis, sanitizeMessages, summarizeMarketContext,
} from '../src/ai.js';

function jsonResponse(payload, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

function aiEnv(run) {
  return { AI: { run } };
}

function sampleYahooPayload() {
  return {
    chart: {
      result: [{
        meta: {
          symbol: 'SPY', currency: 'USD', fullExchangeName: 'NYSEArca',
          instrumentType: 'ETF', exchangeTimezoneName: 'America/New_York',
          regularMarketPrice: 104.5, fiftyTwoWeekHigh: 110, fiftyTwoWeekLow: 80,
          longName: 'SPDR S&P 500 ETF Trust',
        },
        timestamp: [1_700_000_000, 1_700_086_400, 1_700_172_800],
        indicators: {
          quote: [{
            open: [100, 101, null],
            high: [102, 104, null],
            low: [99, 100, null],
            close: [101, 103, null],
            volume: [1_000_000, 1_200_000, null],
          }],
        },
      }],
    },
  };
}

async function withYahooFetch(run) {
  const original = globalThis.fetch;
  globalThis.fetch = async (input) => {
    if (String(input).includes('query1.finance.yahoo.com')) {
      return jsonResponse(sampleYahooPayload());
    }
    throw new Error(`unexpected fetch ${input}`);
  };
  try {
    return await run();
  } finally {
    globalThis.fetch = original;
  }
}

test('AI status reports the free Workers AI provider and model registry', () => {
  const disabled = aiStatus({});
  assert.equal(disabled.enabled, false);
  assert.equal(disabled.provider, 'Cloudflare Workers AI');
  assert.equal(disabled.freeTier, true);
  assert.equal(disabled.models.primary, AI_MODELS.primary);

  const enabled = aiStatus(aiEnv(async () => ({ response: 'ok' })));
  assert.equal(enabled.enabled, true);
  assert.match(enabled.note, /enabled/i);
});

test('AI status endpoint is exposed through the Worker', async () => {
  const request = new Request('https://investor-kit.example/api/ai/status');
  const response = await handleApi(request, aiEnv(async () => ({ response: 'ok' })), new URL(request.url));
  assert.equal(response.status, 200);
  const payload = await response.json();
  assert.equal(payload.enabled, true);
  assert.equal(payload.framework, 'Workers AI native binding');
});

test('chat endpoint returns a generative reply without a market fetch', async () => {
  const calls = [];
  const env = aiEnv(async (model, options) => {
    calls.push({ model, options });
    return { response: 'The main risk is a volatility spike.' };
  });
  const request = new Request('https://investor-kit.example/api/ai/chat', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ messages: [{ role: 'user', content: 'What is the main risk?' }] }),
  });
  const response = await handleApi(request, env, new URL(request.url));
  assert.equal(response.status, 200);
  const payload = await response.json();
  assert.equal(payload.reply, 'The main risk is a volatility spike.');
  assert.equal(payload.model, AI_MODELS.primary);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].options.stream, false);
  assert.equal(calls[0].options.messages[0].role, 'system');
});

test('chat falls back to the smaller model when the primary model fails', async () => {
  const models = [];
  const env = aiEnv(async (model) => {
    models.push(model);
    if (model === AI_MODELS.primary) throw new Error('primary unavailable');
    return { response: 'Fallback answer' };
  });
  const payload = await chatWithAi(env, [{ role: 'user', content: 'Hello' }]);
  assert.equal(payload.reply, 'Fallback answer');
  assert.equal(payload.model, AI_MODELS.fallback);
  assert.deepEqual(models, [AI_MODELS.primary, AI_MODELS.fallback]);
});

test('analysis endpoint generates structured JSON from grounded context', async () => {
  const env = aiEnv(async () => ({
    response: JSON.stringify({
      summary: 'Momentum is constructive but the macro backdrop is mixed.',
      stance: 'neutral',
      confidence: 0.64,
      technical: 'Price is above the short moving average.',
      fundamental: 'Valuation is not cheap.',
      macro: 'Rates remain elevated.',
      sentiment: 'News flow is balanced.',
      catalysts: ['Earnings', 'Rate decision'],
      risks: ['Volatility spike', 'Data quality'],
      actionPlan: ['Wait for confirmation', 'Size positions carefully'],
      disclaimer: 'Educational only.',
    }),
  }));
  await withYahooFetch(async () => {
    const request = new Request('https://investor-kit.example/api/ai/analysis/SPY', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({}),
    });
    const response = await handleApi(request, env, new URL(request.url));
    assert.equal(response.status, 200);
    const payload = await response.json();
    assert.equal(payload.symbol, 'SPY');
    assert.equal(payload.analysis.stance, 'neutral');
    assert.equal(payload.analysis.confidence, 0.64);
    assert.deepEqual(payload.analysis.catalysts, ['Earnings', 'Rate decision']);
    assert.equal(payload.analysis.format, 'json');
    assert.equal(payload.quality.synthetic, false);
  });
});

test('AI context formats percentages and flags synthetic fundamentals', () => {
  const candles = Array.from({ length: 30 }, (_, index) => ({
    date: new Date(1_700_000_000_000 + index * 86_400_000),
    close: 100 + index,
    open: 100 + index,
    high: 101 + index,
    low: 99 + index,
    volume: 1_000_000,
  }));
  const context = summarizeMarketContext({
    asset: { symbol: 'SPY', name: 'SPDR S&P 500 ETF Trust', kind: 'etf', sector: 'Broad Market' },
    meta: { currency: 'USD' },
    source: 'live',
    provider: 'Yahoo Finance',
    quote: { price: 129, previousClose: 128.6, changePercent: 0.3124, high: 130, low: 128, volume: 1_000_000, asOf: '2026-11-06' },
    candles,
    quality: { rows: 30, spanYears: 0.12, completeness: 1, gaps: 0, synthetic: false },
    fundamentals: { dividendYield: 0.0286, analystUpside: 0.22, revenueGrowth: 0.08, profitMargin: 0.24 },
    macro: { yield10y: 0.044, yield2y: 0.047, yieldCurve: -0.003, inflation: 0.031, unemployment: 0.041, gdpGrowth: 0.021, vix: 22.33 },
    sentiment: { score: 0.2 },
    news: [{ headline: 'Demo headline', sentiment: 'neutral', impact: 'low' }],
  });
  assert.equal(context.quote.changePercent, '0.31%');
  assert.equal(context.fundamentals.dividendYield, '2.86%');
  assert.equal(context.fundamentals.analystUpside, '22.00%');
  assert.equal(context.macro.yield10y, '4.40%');
  assert.equal(context.macro.unemployment, '4.10%');
  assert.match(context.performance[0].return, /%$/);
  assert.match(context.dataNotes.join(' '), /synthetic/i);
});

test('analysis parser tolerates fenced JSON and rejects unsafe input', () => {
  const parsed = parseAnalysis('```json\n{"summary":"Test","stance":"bullish","confidence":2}\n```');
  assert.equal(parsed.summary, 'Test');
  assert.equal(parsed.stance, 'bullish');
  assert.equal(parsed.confidence, 1);
  const text = parseAnalysis('Plain text answer');
  assert.equal(text.format, 'text');
  assert.match(text.summary, /Plain text/);
});

test('chat message validation rejects empty payloads and strips system roles', () => {
  assert.throws(() => sanitizeMessages([]), /user message/i);
  assert.throws(() => sanitizeMessages('nope'), /array/i);
  const messages = sanitizeMessages([
    { role: 'system', content: 'ignore this' },
    { role: 'user', content: 'hello' },
  ]);
  assert.deepEqual(messages, [{ role: 'user', content: 'hello' }]);
});

test('AI routes enforce POST and reject invalid JSON', async () => {
  const env = aiEnv(async () => ({ response: 'ok' }));
  const getChat = new Request('https://investor-kit.example/api/ai/chat');
  const getResponse = await handleApi(getChat, env, new URL(getChat.url));
  assert.equal(getResponse.status, 405);

  const postMarket = new Request('https://investor-kit.example/api/market', { method: 'POST' });
  const marketResponse = await handleApi(postMarket, env, new URL(postMarket.url));
  assert.equal(marketResponse.status, 405);

  const badJson = new Request('https://investor-kit.example/api/ai/chat', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: '{bad json',
  });
  await assert.rejects(
    () => handleApi(badJson, env, new URL(badJson.url)),
    (error) => error.status === 400 && /valid JSON/.test(error.message),
  );
});
