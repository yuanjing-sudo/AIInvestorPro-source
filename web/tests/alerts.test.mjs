import test from 'node:test';
import assert from 'node:assert/strict';
import {
  ALERT_TYPES, createRule, evaluateRule, evaluateRules, markTriggered,
} from '../js/core/alerts.js';

const context = {
  quotes: {
    AAPL: { price: 200, changePercent: 3.5, volume: 2_000_000 },
    MSFT: { price: 300, changePercent: -4.2, volume: 500_000 },
  },
  indicators: {
    AAPL: { rsi: 76 },
    MSFT: { rsi: 24 },
  },
};

test('every alert type is exposed with metadata', () => {
  assert.ok(ALERT_TYPES.length >= 7);
  ALERT_TYPES.forEach((type) => {
    assert.ok(type.id);
    assert.ok(type.label);
  });
});

test('price and change rules trigger on the correct side', () => {
  const above = createRule({ symbol: 'AAPL', type: 'priceAbove', threshold: 190 });
  const below = createRule({ symbol: 'AAPL', type: 'priceBelow', threshold: 190 });
  assert.ok(evaluateRule(above, context));
  assert.equal(evaluateRule(below, context), null);
  const up = createRule({ symbol: 'AAPL', type: 'changeAbove', threshold: 3 });
  const down = createRule({ symbol: 'MSFT', type: 'changeBelow', threshold: -4 });
  assert.ok(evaluateRule(up, context));
  assert.ok(evaluateRule(down, context));
});

test('RSI rules trigger at extremes', () => {
  const overbought = createRule({ symbol: 'AAPL', type: 'rsiAbove', threshold: 70 });
  const oversold = createRule({ symbol: 'MSFT', type: 'rsiBelow', threshold: 30 });
  const wrong = createRule({ symbol: 'AAPL', type: 'rsiBelow', threshold: 30 });
  assert.ok(evaluateRule(overbought, context));
  assert.ok(evaluateRule(oversold, context));
  assert.equal(evaluateRule(wrong, context), null);
});

test('disabled rules never trigger', () => {
  const rule = createRule({ symbol: 'AAPL', type: 'priceAbove', threshold: 1, enabled: false });
  assert.equal(evaluateRule(rule, context), null);
});

test('missing symbols are ignored safely', () => {
  const rule = createRule({ symbol: 'UNKNOWN', type: 'priceAbove', threshold: 1 });
  assert.equal(evaluateRule(rule, context), null);
});

test('createRule rejects bad input', () => {
  assert.throws(() => createRule({ symbol: '', type: 'priceAbove', threshold: 1 }), /symbol/);
  assert.throws(() => createRule({ symbol: 'AAPL', type: 'nope', threshold: 1 }), /unknown alert type/);
  assert.throws(() => createRule({ symbol: 'AAPL', type: 'priceAbove', threshold: NaN }), /threshold/);
});

test('evaluateRules filters and markTriggered updates metadata', () => {
  const rules = [
    createRule({ symbol: 'AAPL', type: 'priceAbove', threshold: 190 }),
    createRule({ symbol: 'AAPL', type: 'priceBelow', threshold: 190 }),
  ];
  const triggered = evaluateRules(rules, context);
  assert.equal(triggered.length, 1);
  const updated = markTriggered(rules, triggered, '2025-01-01T00:00:00.000Z');
  assert.equal(updated[0].triggerCount, 1);
  assert.equal(updated[0].lastTriggeredAt, '2025-01-01T00:00:00.000Z');
  assert.equal(updated[1].triggerCount, 0);
});
