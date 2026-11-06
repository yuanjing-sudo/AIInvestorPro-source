// Price/indicator alert rules. Rules are pure data so they can be persisted or
// evaluated server-side without changes.

export const ALERT_TYPES = [
  { id: 'priceAbove', label: 'Price above', unit: 'currency', description: 'Trigger when the last price is at or above the threshold.' },
  { id: 'priceBelow', label: 'Price below', unit: 'currency', description: 'Trigger when the last price is at or below the threshold.' },
  { id: 'changeAbove', label: 'Daily change above', unit: 'percent', description: 'Trigger on a large positive move.' },
  { id: 'changeBelow', label: 'Daily change below', unit: 'percent', description: 'Trigger on a large negative move.' },
  { id: 'rsiAbove', label: 'RSI above', unit: 'number', description: 'Trigger when RSI(14) is at or above the threshold.' },
  { id: 'rsiBelow', label: 'RSI below', unit: 'number', description: 'Trigger when RSI(14) is at or below the threshold.' },
  { id: 'volumeAbove', label: 'Volume above', unit: 'number', description: 'Trigger when volume exceeds the threshold.' },
];

export function createRule({ symbol, type, threshold, enabled = true, note = '' }) {
  if (!symbol) throw new Error('symbol is required');
  if (!ALERT_TYPES.some((t) => t.id === type)) throw new Error(`unknown alert type: ${type}`);
  if (!Number.isFinite(threshold)) throw new Error('threshold must be a number');
  return {
    id: `rule-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    symbol: symbol.toUpperCase(),
    type,
    threshold,
    enabled,
    note,
    createdAt: new Date().toISOString(),
    lastTriggeredAt: null,
    triggerCount: 0,
  };
}

export function evaluateRule(rule, { quotes, indicators }) {
  if (!rule.enabled) return null;
  const quote = quotes[rule.symbol];
  if (!quote) return null;
  const ind = indicators[rule.symbol] ?? {};
  let value = null;
  let triggered = false;
  let label = '';

  switch (rule.type) {
    case 'priceAbove':
      value = quote.price;
      triggered = value >= rule.threshold;
      label = `price ${value.toFixed(2)} ≥ ${rule.threshold}`;
      break;
    case 'priceBelow':
      value = quote.price;
      triggered = value <= rule.threshold;
      label = `price ${value.toFixed(2)} ≤ ${rule.threshold}`;
      break;
    case 'changeAbove':
      value = quote.changePercent;
      triggered = value >= rule.threshold;
      label = `change ${value.toFixed(2)}% ≥ ${rule.threshold}%`;
      break;
    case 'changeBelow':
      value = quote.changePercent;
      triggered = value <= rule.threshold;
      label = `change ${value.toFixed(2)}% ≤ ${rule.threshold}%`;
      break;
    case 'rsiAbove':
      value = ind.rsi;
      triggered = Number.isFinite(value) && value >= rule.threshold;
      label = `RSI ${Number.isFinite(value) ? value.toFixed(1) : '—'} ≥ ${rule.threshold}`;
      break;
    case 'rsiBelow':
      value = ind.rsi;
      triggered = Number.isFinite(value) && value <= rule.threshold;
      label = `RSI ${Number.isFinite(value) ? value.toFixed(1) : '—'} ≤ ${rule.threshold}`;
      break;
    case 'volumeAbove':
      value = quote.volume;
      triggered = value >= rule.threshold;
      label = `volume ${Math.round(value).toLocaleString()} ≥ ${rule.threshold.toLocaleString()}`;
      break;
    default:
      return null;
  }

  if (!triggered) return null;
  return {
    rule,
    value,
    triggeredAt: new Date().toISOString(),
    message: `${rule.symbol}: ${label}${rule.note ? ` — ${rule.note}` : ''}`,
  };
}

export function evaluateRules(rules, context) {
  return rules
    .map((rule) => evaluateRule(rule, context))
    .filter(Boolean);
}

export function markTriggered(rules, triggered, timestamp = new Date().toISOString()) {
  const ids = new Set(triggered.map((t) => t.rule.id));
  return rules.map((rule) => (ids.has(rule.id)
    ? { ...rule, lastTriggeredAt: timestamp, triggerCount: (rule.triggerCount ?? 0) + 1 }
    : rule));
}
