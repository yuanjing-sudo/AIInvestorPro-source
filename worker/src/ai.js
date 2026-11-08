// Generative AI layer for InvestorKit Pro.
//
// Provider: Cloudflare Workers AI (native `AI` binding).
// Default model: Llama 3.3 70B Instruct FP8 Fast, a 70B open-weights model.
// Fallback model: Llama 3.1 8B Instruct FP8 Fast.
//
// Workers AI includes a free daily allocation (10,000 Neurons/day on the Free
// plan). No API key is needed inside a Worker: the binding is configured in
// wrangler.jsonc and Cloudflare authenticates the invocation.

import { buildSymbol, requireSymbol } from './market.js';
import { performanceWindows, historicalVolatility } from '../../web/js/core/marketdata.js';

export const AI_PROVIDER = 'Cloudflare Workers AI';
export const AI_FRAMEWORK = 'Workers AI native binding';
export const FREE_TIER_NEURONS_PER_DAY = 10_000;

export const AI_MODELS = {
  primary: '@cf/meta/llama-3.3-70b-instruct-fp8-fast',
  fallback: '@cf/meta/llama-3.1-8b-instruct-fp8-fast',
  fast: '@cf/qwen/qwen3-30b-a3b-fp8',
};

const ALLOWED_MODELS = new Set(Object.values(AI_MODELS));
const MAX_MESSAGES = 16;
const MAX_CONTENT_CHARS = 4_000;
const MAX_BODY_BYTES = 50_000;
const MAX_OUTPUT_TOKENS = 700;

const DISCLAIMER = 'Educational research only. Generative AI can be wrong, may omit material information and is not personalized investment advice. Verify data independently.';

function apiError(message, status = 400) {
  const error = new Error(message);
  error.status = status;
  return error;
}

export function aiStatus(env = {}) {
  const enabled = Boolean(env?.AI && typeof env.AI.run === 'function');
  return {
    ok: true,
    enabled,
    provider: AI_PROVIDER,
    framework: AI_FRAMEWORK,
    freeTier: true,
    freeTierNeuronsPerDay: FREE_TIER_NEURONS_PER_DAY,
    models: { ...AI_MODELS },
    features: ['grounded-chat', 'generative-analysis', 'model-fallback'],
    note: enabled
      ? 'Generative AI is enabled through the Cloudflare Workers AI binding.'
      : 'Add the AI binding in worker/wrangler.jsonc and deploy the Worker to enable generative AI.',
  };
}

export function sanitizeMessages(input) {
  if (!Array.isArray(input)) throw apiError('messages must be an array');
  const messages = [];
  for (const item of input.slice(-MAX_MESSAGES)) {
    if (!item || typeof item !== 'object') continue;
    const role = item.role === 'assistant' ? 'assistant' : item.role === 'user' ? 'user' : null;
    if (!role) continue;
    const content = String(item.content ?? '').trim();
    if (!content) continue;
    messages.push({ role, content: content.slice(0, MAX_CONTENT_CHARS) });
  }
  if (!messages.some((message) => message.role === 'user')) {
    throw apiError('At least one user message is required');
  }
  return messages;
}

function extractText(result) {
  if (typeof result === 'string') return result.trim();
  if (typeof result?.response === 'string') return result.response.trim();
  if (typeof result?.result?.response === 'string') return result.result.response.trim();
  if (Array.isArray(result?.choices)) {
    const content = result.choices[0]?.message?.content;
    if (typeof content === 'string') return content.trim();
  }
  if (result?.response && typeof result.response === 'object') {
    return JSON.stringify(result.response);
  }
  return '';
}

async function runModel(env, model, messages, options) {
  if (!env?.AI || typeof env.AI.run !== 'function') {
    throw apiError('Cloudflare Workers AI binding is not configured', 503);
  }
  const result = await env.AI.run(model, {
    messages,
    max_tokens: options.maxTokens ?? MAX_OUTPUT_TOKENS,
    temperature: options.temperature ?? 0.3,
    top_p: options.topP ?? 0.9,
    stream: false,
  });
  const text = extractText(result);
  if (!text) throw new Error(`${model} returned an empty response`);
  return { text, model };
}

export async function runAi(env, messages, options = {}) {
  const requested = options.model && ALLOWED_MODELS.has(options.model) ? options.model : null;
  const models = requested
    ? [requested, AI_MODELS.fallback]
    : [AI_MODELS.primary, AI_MODELS.fallback, AI_MODELS.fast];
  const errors = [];
  for (const model of [...new Set(models)]) {
    try {
      return await runModel(env, model, messages, options);
    } catch (error) {
      errors.push(`${model}: ${error.message}`);
    }
  }
  const error = apiError(`AI provider unavailable (${errors.join('; ')})`, 502);
  throw error;
}

function asPercent(value, digits = 2) {
  return Number.isFinite(value) ? `${(value * 100).toFixed(digits)}%` : null;
}

// Quote.changePercent is already expressed in percent (e.g. 0.3124 means
// 0.3124%), unlike returns/volatility/yields which are decimal fractions.
function asPercentValue(value, digits = 2) {
  return Number.isFinite(value) ? `${value.toFixed(digits)}%` : null;
}

function compactFundamentals(value) {
  if (!value) return null;
  return {
    marketCap: value.marketCap ?? null,
    beta: value.beta ?? null,
    peRatio: value.peRatio ?? null,
    dividendYield: asPercent(value.dividendYield),
    analystTarget: value.analystTarget ?? null,
    analystUpside: asPercent(value.analystUpside),
    analystRating: value.analystRating ?? null,
    revenueGrowth: asPercent(value.revenueGrowth),
    profitMargin: asPercent(value.profitMargin),
  };
}

function compactMacro(value) {
  if (!value) return null;
  return {
    yield10y: asPercent(value.yield10y),
    yield2y: asPercent(value.yield2y),
    yieldCurve: asPercent(value.yieldCurve),
    inflation: asPercent(value.inflation),
    unemployment: asPercent(value.unemployment),
    gdpGrowth: asPercent(value.gdpGrowth),
    vix: value.vix ?? null,
    dollarIndex: value.dollarIndex ?? null,
    oil: value.oil ?? null,
    regime: value.regime ?? null,
    asOf: value.asOf ?? null,
  };
}

export function summarizeMarketContext(payload) {
  const candles = payload.candles ?? [];
  const quote = payload.quote ?? {};
  const quality = payload.quality ?? {};
  return {
    symbol: payload.asset?.symbol ?? payload.symbol ?? 'UNKNOWN',
    name: payload.asset?.name ?? payload.meta?.longName ?? 'Unknown asset',
    kind: payload.asset?.kind ?? 'equity',
    sector: payload.asset?.sector ?? 'Unknown',
    asOf: quote.asOf ?? null,
    source: payload.source ?? 'unknown',
    provider: payload.provider ?? 'unknown',
    quote: {
      currency: payload.meta?.currency ?? 'USD',
      price: quote.price ?? null,
      previousClose: quote.previousClose ?? null,
      changePercent: asPercentValue(quote.changePercent),
      high: quote.high ?? null,
      low: quote.low ?? null,
      volume: quote.volume ?? null,
    },
    quality: {
      rows: quality.rows ?? candles.length,
      spanYears: quality.spanYears ?? null,
      completeness: quality.completeness ?? null,
      gaps: quality.gaps ?? null,
      synthetic: quality.synthetic ?? null,
    },
    performance: performanceWindows(candles).map((row) => ({ window: row.key, return: asPercent(row.value) })),
    realizedVolatility21d: asPercent(historicalVolatility(candles, 21)),
    fundamentals: compactFundamentals(payload.fundamentals),
    macro: compactMacro(payload.macro),
    sentiment: payload.sentiment ?? null,
    news: (payload.news ?? []).slice(0, 6).map((item) => ({
      headline: item.headline,
      sentiment: item.sentiment,
      impact: item.impact,
    })),
    dataNotes: [
      'Percentages are formatted as percent strings; do not multiply them again.',
      'Fundamentals and headlines in this build are synthetic demo data and may not be internally consistent with live prices or with each other.',
      'Only the quote, candles, macro series and quality fields come from the live market-data adapters.',
    ],
  };
}

function systemPrompt() {
  return [
    'You are InvestorKit AI, a careful multi-asset research analyst embedded in a portfolio analytics app.',
    'Use only the supplied market context. Do not invent prices, fundamentals, headlines or macro data.',
    'Percent fields are supplied as percent strings; do not rescale or multiply them again.',
    'In this deployment fundamentals and headlines are synthetic demo data. Always label the fundamental and sentiment sections as synthetic demo data, flag inconsistencies, and never present those fields as current facts.',
    'Separate observed facts from inference. Mention data source and data-quality limitations when relevant.',
    'Never guarantee returns, never present a trade as certain, and do not give personalized financial advice.',
    'If the context is insufficient, say what is missing instead of filling gaps.',
    'The app is educational; encourage independent verification and a licensed professional for personal decisions.',
  ].join(' ');
}

export function buildAnalysisMessages(context) {
  return [
    { role: 'system', content: systemPrompt() },
    {
      role: 'user',
      content: [
        'Produce a generative research brief for the asset below.',
        'Return ONLY a valid JSON object with these keys:',
        'summary (string, 2-4 sentences), stance ("bullish" | "neutral" | "bearish"), confidence (number 0-1),',
        'technical (string), fundamental (string), macro (string), sentiment (string),',
        'catalysts (array of 3-5 short strings), risks (array of 3-5 short strings),',
        'actionPlan (array of 3-5 short strings), disclaimer (string).',
        'Use the context; do not add facts that are not present. Keep the whole brief under 450 words.',
        `DISCLAIMER TO INCLUDE: ${DISCLAIMER}`,
        'CONTEXT JSON:',
        JSON.stringify(context),
      ].join('\n'),
    },
  ];
}

export function parseAnalysis(text) {
  const raw = String(text ?? '').trim();
  const cleaned = raw.replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/i, '').trim();
  const start = cleaned.indexOf('{');
  const end = cleaned.lastIndexOf('}');
  let parsed = null;
  if (start >= 0 && end > start) {
    try {
      parsed = JSON.parse(cleaned.slice(start, end + 1));
    } catch {
      parsed = null;
    }
  }
  if (!parsed || typeof parsed !== 'object') {
    return {
      summary: raw.slice(0, 4_000) || 'The model returned no analysis.',
      stance: 'neutral',
      confidence: 0.5,
      technical: '',
      fundamental: '',
      macro: '',
      sentiment: '',
      catalysts: [],
      risks: [],
      actionPlan: [],
      disclaimer: DISCLAIMER,
      format: 'text',
    };
  }
  const asString = (value) => (typeof value === 'string' ? value.trim() : '');
  const asList = (value) => (Array.isArray(value) ? value : [])
    .map((item) => (typeof item === 'string' ? item.trim() : String(item ?? '').trim()))
    .filter(Boolean)
    .slice(0, 6);
  const stance = ['bullish', 'bearish', 'neutral'].includes(String(parsed.stance).toLowerCase())
    ? String(parsed.stance).toLowerCase()
    : 'neutral';
  const confidence = Number(parsed.confidence);
  return {
    summary: asString(parsed.summary) || 'No summary was returned.',
    stance,
    confidence: Number.isFinite(confidence) ? Math.min(1, Math.max(0, confidence)) : 0.5,
    technical: asString(parsed.technical),
    fundamental: asString(parsed.fundamental),
    macro: asString(parsed.macro),
    sentiment: asString(parsed.sentiment),
    catalysts: asList(parsed.catalysts),
    risks: asList(parsed.risks),
    actionPlan: asList(parsed.actionPlan),
    disclaimer: asString(parsed.disclaimer) || DISCLAIMER,
    format: 'json',
  };
}

export async function generateAnalysis(env, symbol, options = {}) {
  const normalized = requireSymbol(symbol);
  const payload = await buildSymbol(normalized, { range: '1y', env });
  const context = summarizeMarketContext(payload);
  const result = await runAi(env, buildAnalysisMessages(context), {
    maxTokens: options.maxTokens ?? 700,
    temperature: options.temperature ?? 0.2,
  });
  return {
    ok: true,
    provider: AI_PROVIDER,
    framework: AI_FRAMEWORK,
    model: result.model,
    freeTier: true,
    generatedAt: new Date().toISOString(),
    symbol: normalized,
    source: payload.source,
    providerLabel: payload.provider,
    quality: payload.quality,
    context: {
      asOf: context.asOf,
      rows: context.quality.rows,
      synthetic: context.quality.synthetic,
      performance: context.performance,
    },
    analysis: parseAnalysis(result.text),
  };
}

export function buildChatMessages(context, messages) {
  return [
    { role: 'system', content: `${systemPrompt()} Answer in concise plain text, usually under 250 words. Use short paragraphs or bullets.` },
    {
      role: 'system',
      content: `MARKET CONTEXT JSON:\n${JSON.stringify(context)}`,
    },
    ...messages,
  ];
}

export async function chatWithAi(env, messages, options = {}) {
  const sanitized = sanitizeMessages(messages);
  let context = null;
  let symbol = null;
  if (options.symbol) {
    symbol = requireSymbol(options.symbol);
    const payload = await buildSymbol(symbol, { range: '1y', env });
    context = summarizeMarketContext(payload);
  }
  const result = await runAi(env, buildChatMessages(context, sanitized), {
    maxTokens: options.maxTokens ?? 550,
    temperature: options.temperature ?? 0.35,
  });
  return {
    ok: true,
    provider: AI_PROVIDER,
    framework: AI_FRAMEWORK,
    model: result.model,
    freeTier: true,
    generatedAt: new Date().toISOString(),
    symbol,
    reply: result.text,
  };
}

export async function readJsonBody(request) {
  const text = await request.text();
  if (text.length > MAX_BODY_BYTES) throw apiError('Request body is too large', 413);
  if (!text) return {};
  try {
    const payload = JSON.parse(text);
    if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
      throw new Error('not an object');
    }
    return payload;
  } catch {
    throw apiError('Request body must be valid JSON');
  }
}
