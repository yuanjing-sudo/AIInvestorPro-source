import test from 'node:test';
import assert from 'node:assert/strict';
import {
  createLot, addLot, sell, unrealized, summarizeLots, compareMethods, realizedSummary,
} from '../js/core/taxlots.js';

function threeLots() {
  let lots = [];
  lots = addLot(lots, { symbol: 'AAPL', quantity: 10, costPerShare: 100, acquiredAt: '2024-01-10' });
  lots = addLot(lots, { symbol: 'AAPL', quantity: 10, costPerShare: 150, acquiredAt: '2024-02-10' });
  lots = addLot(lots, { symbol: 'AAPL', quantity: 10, costPerShare: 50, acquiredAt: '2024-03-10' });
  return lots;
}

test('createLot validates inputs', () => {
  assert.throws(() => createLot({ symbol: 'X', quantity: 0, costPerShare: 10 }), /quantity/);
  assert.throws(() => createLot({ symbol: 'X', quantity: 1, costPerShare: 0 }), /costPerShare/);
  assert.throws(() => createLot({ quantity: 1, costPerShare: 1 }), /symbol/);
});

test('FIFO consumes the oldest shares first', () => {
  const lots = threeLots();
  const result = sell(lots, { symbol: 'AAPL', quantity: 15, price: 200, method: 'FIFO' });
  assert.equal(result.sale.costBasis, 1750);
  assert.equal(result.sale.realizedGain, 1250);
  const remaining = result.lots.filter((l) => l.remaining > 0);
  assert.equal(remaining.length, 2);
  assert.equal(remaining.find((l) => l.costPerShare === 150).remaining, 5);
});

test('LIFO uses the newest shares first', () => {
  const result = sell(threeLots(), { symbol: 'AAPL', quantity: 15, price: 200, method: 'LIFO' });
  assert.equal(result.sale.costBasis, 1250);
  assert.equal(result.sale.realizedGain, 1750);
});

test('HIFO minimizes realized gain and LOFO maximizes it', () => {
  const hifo = sell(threeLots(), { symbol: 'AAPL', quantity: 15, price: 200, method: 'HIFO' });
  const lofo = sell(threeLots(), { symbol: 'AAPL', quantity: 15, price: 200, method: 'LOFO' });
  assert.equal(hifo.sale.costBasis, 2000);
  assert.equal(hifo.sale.realizedGain, 1000);
  assert.equal(lofo.sale.costBasis, 1000);
  assert.equal(lofo.sale.realizedGain, 2000);
});

test('selling more than available throws', () => {
  assert.throws(
    () => sell(threeLots(), { symbol: 'AAPL', quantity: 31, price: 200 }),
    /insufficient shares/,
  );
});

test('sell does not mutate the original ledger', () => {
  const lots = threeLots();
  sell(lots, { symbol: 'AAPL', quantity: 20, price: 200, method: 'FIFO' });
  assert.equal(lots.reduce((acc, l) => acc + l.remaining, 0), 30);
});

test('unrealized and summary use current prices', () => {
  const rows = unrealized(threeLots(), { AAPL: 200 });
  assert.equal(rows.length, 3);
  assert.equal(rows[0].unrealizedGain, 1000);
  const summary = summarizeLots(threeLots(), { AAPL: 200 });
  assert.equal(summary.costBasis, 3000);
  assert.equal(summary.marketValue, 6000);
  assert.equal(summary.unrealizedGain, 3000);
});

test('method comparison is ordered by tax cost', () => {
  const comparison = compareMethods(threeLots(), { symbol: 'AAPL', quantity: 15, price: 200 });
  assert.deepEqual(comparison.map((c) => c.method), ['HIFO', 'FIFO', 'LIFO', 'LOFO']);
});

test('realized summary aggregates sales', () => {
  const lots = threeLots();
  const first = sell(lots, { symbol: 'AAPL', quantity: 5, price: 120, method: 'FIFO' });
  const second = sell(first.lots, { symbol: 'AAPL', quantity: 5, price: 180, method: 'FIFO' });
  const summary = realizedSummary([first.sale, second.sale]);
  assert.equal(summary.sales, 2);
  assert.equal(summary.totalProceeds, 5 * 120 + 5 * 180);
  assert.equal(summary.winners, 2);
});
