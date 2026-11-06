// Long/flat signal generators. A value of 1 means "target 100% long" and is
// acted on at the next bar's open by the backtester, so there is no lookahead.

import {
  sma, ema, rsi, macd, donchian, roc,
} from './indicators.js';

export const STRATEGIES = [
  {
    id: 'buyHold',
    name: 'Buy & Hold',
    description: 'Enter at the first bar and hold to the end.',
    params: [],
  },
  {
    id: 'smaCross',
    name: 'SMA Crossover',
    description: 'Long while the fast SMA is above the slow SMA.',
    params: [
      { key: 'fast', label: 'Fast SMA', min: 2, max: 100, step: 1, value: 20 },
      { key: 'slow', label: 'Slow SMA', min: 5, max: 250, step: 1, value: 50 },
    ],
  },
  {
    id: 'emaCross',
    name: 'EMA Crossover',
    description: 'Long while the fast EMA is above the slow EMA.',
    params: [
      { key: 'fast', label: 'Fast EMA', min: 2, max: 100, step: 1, value: 12 },
      { key: 'slow', label: 'Slow EMA', min: 5, max: 250, step: 1, value: 26 },
    ],
  },
  {
    id: 'rsiMeanReversion',
    name: 'RSI Mean Reversion',
    description: 'Buy oversold RSI, exit when RSI recovers.',
    params: [
      { key: 'period', label: 'RSI period', min: 2, max: 50, step: 1, value: 14 },
      { key: 'oversold', label: 'Oversold', min: 5, max: 45, step: 1, value: 30 },
      { key: 'exit', label: 'Exit level', min: 40, max: 90, step: 1, value: 55 },
    ],
  },
  {
    id: 'macdTrend',
    name: 'MACD Trend',
    description: 'Long while MACD is above its signal line.',
    params: [
      { key: 'fast', label: 'Fast EMA', min: 2, max: 50, step: 1, value: 12 },
      { key: 'slow', label: 'Slow EMA', min: 5, max: 100, step: 1, value: 26 },
      { key: 'signal', label: 'Signal', min: 2, max: 30, step: 1, value: 9 },
    ],
  },
  {
    id: 'donchianBreakout',
    name: 'Donchian Breakout',
    description: 'Buy new highs, exit on new lows.',
    params: [
      { key: 'period', label: 'Channel period', min: 5, max: 120, step: 1, value: 20 },
    ],
  },
  {
    id: 'momentum',
    name: 'Time-Series Momentum',
    description: 'Long when trailing return is positive.',
    params: [
      { key: 'period', label: 'Lookback', min: 5, max: 252, step: 1, value: 60 },
    ],
  },
  {
    id: 'dualMomentum',
    name: 'Dual Momentum',
    description: 'Long when price is above its 200-day SMA and momentum is positive.',
    params: [
      { key: 'trend', label: 'Trend SMA', min: 50, max: 300, step: 1, value: 200 },
      { key: 'momentum', label: 'Momentum window', min: 20, max: 252, step: 1, value: 126 },
    ],
  },
  {
    id: 'composite',
    name: 'Composite Trend Score',
    description: 'Long when at least three of five trend checks agree.',
    params: [],
  },
];

export function strategyById(id) {
  return STRATEGIES.find((s) => s.id === id) ?? STRATEGIES[0];
}

export function defaultParams(id) {
  const strategy = strategyById(id);
  return Object.fromEntries(strategy.params.map((p) => [p.key, p.value]));
}

function neutralSeries(length) {
  return new Array(length).fill(0);
}

export function generateSignals(id, candles, params = {}) {
  const close = candles.map((c) => c.close);
  const high = candles.map((c) => c.high);
  const low = candles.map((c) => c.low);
  const n = candles.length;
  const signal = neutralSeries(n);
  if (!n) return signal;
  const p = { ...defaultParams(id), ...params };

  switch (id) {
    case 'buyHold':
      signal.fill(1);
      return signal;

    case 'smaCross': {
      const fast = sma(close, Math.max(1, Math.round(p.fast)));
      const slow = sma(close, Math.max(2, Math.round(p.slow)));
      for (let i = 0; i < n; i += 1) {
        if (fast[i] !== null && slow[i] !== null) signal[i] = fast[i] > slow[i] ? 1 : 0;
      }
      return signal;
    }

    case 'emaCross': {
      const fast = ema(close, Math.max(1, Math.round(p.fast)));
      const slow = ema(close, Math.max(2, Math.round(p.slow)));
      for (let i = 0; i < n; i += 1) {
        if (fast[i] !== null && slow[i] !== null) signal[i] = fast[i] > slow[i] ? 1 : 0;
      }
      return signal;
    }

    case 'rsiMeanReversion': {
      const values = rsi(close, Math.max(2, Math.round(p.period)));
      let held = 0;
      for (let i = 0; i < n; i += 1) {
        const value = values[i];
        if (value !== null) {
          if (value <= p.oversold) held = 1;
          else if (value >= p.exit) held = 0;
        }
        signal[i] = held;
      }
      return signal;
    }

    case 'macdTrend': {
      const result = macd(close, Math.round(p.fast), Math.round(p.slow), Math.round(p.signal));
      for (let i = 0; i < n; i += 1) {
        if (result.macd[i] !== null && result.signal[i] !== null) {
          signal[i] = result.macd[i] > result.signal[i] ? 1 : 0;
        }
      }
      return signal;
    }

    case 'donchianBreakout': {
      const period = Math.max(2, Math.round(p.period));
      const channel = donchian(high, low, period);
      let held = 0;
      for (let i = 1; i < n; i += 1) {
        if (channel.upper[i - 1] !== null && close[i] > channel.upper[i - 1]) held = 1;
        else if (channel.lower[i - 1] !== null && close[i] < channel.lower[i - 1]) held = 0;
        signal[i] = held;
      }
      return signal;
    }

    case 'momentum': {
      const values = roc(close, Math.max(1, Math.round(p.period)));
      for (let i = 0; i < n; i += 1) {
        if (values[i] !== null) signal[i] = values[i] > 0 ? 1 : 0;
      }
      return signal;
    }

    case 'dualMomentum': {
      const trend = sma(close, Math.max(20, Math.round(p.trend)));
      const momentum = roc(close, Math.max(5, Math.round(p.momentum)));
      for (let i = 0; i < n; i += 1) {
        if (trend[i] !== null && momentum[i] !== null) {
          signal[i] = close[i] > trend[i] && momentum[i] > 0 ? 1 : 0;
        }
      }
      return signal;
    }

    case 'composite': {
      const fast = sma(close, 20);
      const slow = sma(close, 50);
      const momentum = roc(close, 60);
      const rsiValues = rsi(close, 14);
      const macdValues = macd(close);
      for (let i = 0; i < n; i += 1) {
        if (fast[i] === null || slow[i] === null || momentum[i] === null
          || rsiValues[i] === null || macdValues.signal[i] === null) continue;
        let score = 0;
        if (fast[i] > slow[i]) score += 1;
        if (close[i] > slow[i]) score += 1;
        if (momentum[i] > 0) score += 1;
        if (macdValues.macd[i] > macdValues.signal[i]) score += 1;
        if (rsiValues[i] >= 45 && rsiValues[i] <= 75) score += 1;
        signal[i] = score >= 3 ? 1 : 0;
      }
      return signal;
    }

    default:
      return signal;
  }
}
