import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeSymbol, parseChart } from '../src/yahoo.js';
import { dataQuality } from '../../web/js/core/marketdata.js';

function samplePayload() {
  return {
    chart: {
      result: [{
        meta: {
          symbol: 'SPY',
          currency: 'USD',
          fullExchangeName: 'NYSEArca',
          instrumentType: 'ETF',
          exchangeTimezoneName: 'America/New_York',
          regularMarketPrice: 104.5,
          fiftyTwoWeekHigh: 110,
          fiftyTwoWeekLow: 80,
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

test('normalizeSymbol accepts market symbols and rejects unsafe values', () => {
  assert.equal(normalizeSymbol(' spy '), 'SPY');
  assert.equal(normalizeSymbol('btc-usd'), 'BTC-USD');
  assert.equal(normalizeSymbol('^VIX'), '^VIX');
  assert.equal(normalizeSymbol('DX-Y.NYB'), 'DX-Y.NYB');
  assert.throws(() => normalizeSymbol('SPY/evil'));
  assert.throws(() => normalizeSymbol(''));
});

test('parseChart converts Yahoo timestamps and nulls into clean candles', () => {
  const parsed = parseChart(samplePayload(), 'SPY');
  assert.equal(parsed.symbol, 'SPY');
  assert.equal(parsed.candles.length, 2);
  assert.equal(parsed.candles[0].close, 101);
  assert.equal(parsed.candles[0].dateString, '2023-11-14');
  assert.ok(parsed.candles[0].date instanceof Date);
  assert.equal(parsed.candles[0].date.toISOString(), '2023-11-14T22:13:20.000Z');
  assert.equal(parsed.candles[1].close, 103);
  assert.equal(parsed.candles[1].high, 104);
  assert.ok(parsed.candles.every((candle) => candle.high >= candle.close));
  assert.ok(parsed.candles.every((candle) => candle.low <= candle.close));
  assert.equal(parsed.quote.price, 104.5);
  assert.equal(parsed.quote.previousClose, 101);
  assert.equal(parsed.meta.currency, 'USD');
});

test('dataQuality reports live candles as non-synthetic', () => {
  const parsed = parseChart(samplePayload(), 'SPY');
  const quality = dataQuality(parsed.candles, false);
  assert.equal(quality.synthetic, false);
  assert.ok(quality.spanYears > 0);
  assert.ok(quality.barsPerYear > 0);
});

test('parseChart rejects empty or malformed payloads', () => {
  assert.throws(() => parseChart({ chart: { result: [] } }, 'SPY'));
  assert.throws(() => parseChart({}, 'SPY'));
  assert.throws(() => parseChart({
    chart: { result: [{ meta: {}, timestamp: [1], indicators: { quote: [{ close: [null] }] } }] },
  }, 'SPY'));
});
