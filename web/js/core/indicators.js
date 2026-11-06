// Series-aligned technical indicators. Every output has the same length as the
// input; warm-up positions are null.

import { mean, stdev } from './math.js';

const nils = (n) => new Array(Math.max(0, n)).fill(null);

export function sma(values, period) {
  if (period <= 0 || values.length < period) return nils(values.length);
  const out = nils(values.length);
  let total = values.slice(0, period).reduce((a, b) => a + b, 0);
  out[period - 1] = total / period;
  for (let i = period; i < values.length; i += 1) {
    total += values[i] - values[i - period];
    out[i] = total / period;
  }
  return out;
}

export function ema(values, period) {
  if (period <= 0 || values.length < period) return nils(values.length);
  const out = nils(values.length);
  const alpha = 2 / (period + 1);
  let previous = values.slice(0, period).reduce((a, b) => a + b, 0) / period;
  out[period - 1] = previous;
  for (let i = period; i < values.length; i += 1) {
    previous = alpha * values[i] + (1 - alpha) * previous;
    out[i] = previous;
  }
  return out;
}

export function rma(values, period) {
  if (period <= 0 || values.length < period) return nils(values.length);
  const out = nils(values.length);
  let previous = values.slice(0, period).reduce((a, b) => a + b, 0) / period;
  out[period - 1] = previous;
  for (let i = period; i < values.length; i += 1) {
    previous = (previous * (period - 1) + values[i]) / period;
    out[i] = previous;
  }
  return out;
}

export function rsi(values, period = 14) {
  if (period <= 0 || values.length <= period) return nils(values.length);
  const out = nils(values.length);
  let gainSum = 0;
  let lossSum = 0;
  for (let i = 1; i <= period; i += 1) {
    const change = values[i] - values[i - 1];
    if (change > 0) gainSum += change; else lossSum -= change;
  }
  let averageGain = gainSum / period;
  let averageLoss = lossSum / period;
  const rsiValue = () => {
    if (averageLoss === 0) return averageGain === 0 ? 50 : 100;
    const rs = averageGain / averageLoss;
    return 100 - 100 / (1 + rs);
  };
  out[period] = rsiValue();
  for (let i = period + 1; i < values.length; i += 1) {
    const change = values[i] - values[i - 1];
    averageGain = (averageGain * (period - 1) + Math.max(change, 0)) / period;
    averageLoss = (averageLoss * (period - 1) + Math.max(-change, 0)) / period;
    out[i] = rsiValue();
  }
  return out;
}

function combine(a, b, operation) {
  const n = Math.min(a.length, b.length);
  const out = nils(n);
  for (let i = 0; i < n; i += 1) {
    if (a[i] !== null && b[i] !== null) out[i] = operation(a[i], b[i]);
  }
  return out;
}

function emaOnOptional(series, period) {
  const indices = [];
  series.forEach((v, i) => { if (v !== null) indices.push(i); });
  if (period <= 0 || indices.length < period) return nils(series.length);
  const smoothed = ema(indices.map((i) => series[i]), period);
  const out = nils(series.length);
  indices.forEach((original, offset) => { out[original] = smoothed[offset]; });
  return out;
}

function smaOnOptional(series, period) {
  const indices = [];
  series.forEach((v, i) => { if (v !== null) indices.push(i); });
  if (period <= 0 || indices.length < period) return nils(series.length);
  const smoothed = sma(indices.map((i) => series[i]), period);
  const out = nils(series.length);
  indices.forEach((original, offset) => { out[original] = smoothed[offset]; });
  return out;
}

export function macd(values, fastPeriod = 12, slowPeriod = 26, signalPeriod = 9) {
  const fast = ema(values, fastPeriod);
  const slow = ema(values, slowPeriod);
  const macdLine = combine(fast, slow, (a, b) => a - b);
  const signal = emaOnOptional(macdLine, signalPeriod);
  const histogram = combine(macdLine, signal, (a, b) => a - b);
  return { macd: macdLine, signal, histogram };
}

export function trueRange(high, low, close) {
  const count = Math.min(high.length, low.length, close.length);
  if (!count) return [];
  const out = new Array(count).fill(0);
  out[0] = Math.max(0, high[0] - low[0]);
  for (let i = 1; i < count; i += 1) {
    out[i] = Math.max(
      high[i] - low[i],
      Math.abs(high[i] - close[i - 1]),
      Math.abs(low[i] - close[i - 1]),
    );
  }
  return out;
}

export function atr(high, low, close, period = 14) {
  return rma(trueRange(high, low, close), period);
}

export function stochastic(high, low, close, kPeriod = 14, dPeriod = 3) {
  const k = nils(close.length);
  for (let i = kPeriod - 1; i < close.length; i += 1) {
    const windowHigh = Math.max(...high.slice(i - kPeriod + 1, i + 1));
    const windowLow = Math.min(...low.slice(i - kPeriod + 1, i + 1));
    const range = windowHigh - windowLow;
    k[i] = range > 0 ? ((close[i] - windowLow) / range) * 100 : 50;
  }
  return { k, d: smaOnOptional(k, dPeriod) };
}

export function williamsR(high, low, close, period = 14) {
  const out = nils(close.length);
  for (let i = period - 1; i < close.length; i += 1) {
    const windowHigh = Math.max(...high.slice(i - period + 1, i + 1));
    const windowLow = Math.min(...low.slice(i - period + 1, i + 1));
    const range = windowHigh - windowLow;
    out[i] = range > 0 ? ((close[i] - windowHigh) / range) * 100 : -50;
  }
  return out;
}

export function roc(values, period = 10) {
  if (period <= 0 || values.length <= period) return nils(values.length);
  const out = nils(values.length);
  for (let i = period; i < values.length; i += 1) {
    const previous = values[i - period];
    out[i] = previous !== 0 ? (values[i] / previous - 1) * 100 : 0;
  }
  return out;
}

export function bollinger(values, period = 20, multiplier = 2) {
  const middle = sma(values, period);
  const upper = nils(values.length);
  const lower = nils(values.length);
  for (let i = period - 1; i < values.length; i += 1) {
    const window = values.slice(i - period + 1, i + 1);
    const deviation = stdev(window, false) * multiplier;
    upper[i] = middle[i] + deviation;
    lower[i] = middle[i] - deviation;
  }
  return { upper, middle, lower };
}

export function donchian(high, low, period = 20) {
  const upper = nils(high.length);
  const lower = nils(low.length);
  const middle = nils(high.length);
  for (let i = period - 1; i < high.length; i += 1) {
    upper[i] = Math.max(...high.slice(i - period + 1, i + 1));
    lower[i] = Math.min(...low.slice(i - period + 1, i + 1));
    middle[i] = (upper[i] + lower[i]) / 2;
  }
  return { upper, middle, lower };
}

export function vwap(high, low, close, volume, period = 20) {
  const count = Math.min(high.length, low.length, close.length, volume.length);
  const out = nils(count);
  for (let i = period - 1; i < count; i += 1) {
    let priceVolume = 0;
    let totalVolume = 0;
    for (let j = i - period + 1; j <= i; j += 1) {
      const typical = (high[j] + low[j] + close[j]) / 3;
      priceVolume += typical * volume[j];
      totalVolume += volume[j];
    }
    out[i] = totalVolume > 0 ? priceVolume / totalVolume : null;
  }
  return out;
}

export function obv(close, volume) {
  const count = Math.min(close.length, volume.length);
  if (!count) return [];
  const out = new Array(count).fill(0);
  for (let i = 1; i < count; i += 1) {
    if (close[i] > close[i - 1]) out[i] = out[i - 1] + volume[i];
    else if (close[i] < close[i - 1]) out[i] = out[i - 1] - volume[i];
    else out[i] = out[i - 1];
  }
  return out;
}

export function aroon(high, low, period = 25) {
  const count = Math.min(high.length, low.length);
  const up = nils(count);
  const down = nils(count);
  for (let i = period; i < count; i += 1) {
    const hw = high.slice(i - period, i + 1);
    const lw = low.slice(i - period, i + 1);
    const highOffset = period - hw.lastIndexOf(Math.max(...hw));
    const lowOffset = period - lw.lastIndexOf(Math.min(...lw));
    up[i] = (100 * (period - highOffset)) / period;
    down[i] = (100 * (period - lowOffset)) / period;
  }
  return { up, down };
}

export function latest(series) {
  for (let i = series.length - 1; i >= 0; i -= 1) {
    if (series[i] !== null && Number.isFinite(series[i])) return series[i];
  }
  return null;
}

export function summarize(candles) {
  const close = candles.map((c) => c.close);
  const high = candles.map((c) => c.high);
  const low = candles.map((c) => c.low);
  const volume = candles.map((c) => c.volume);
  return {
    close,
    sma20: latest(sma(close, 20)),
    sma50: latest(sma(close, 50)),
    ema12: latest(ema(close, 12)),
    ema26: latest(ema(close, 26)),
    rsi: latest(rsi(close, 14)),
    atr: latest(atr(high, low, close, 14)),
    macd: latest(macd(close).macd),
    macdSignal: latest(macd(close).signal),
    bollinger: {
      upper: latest(bollinger(close).upper),
      middle: latest(bollinger(close).middle),
      lower: latest(bollinger(close).lower),
    },
    stochastic: latest(stochastic(high, low, close).k),
    williams: latest(williamsR(high, low, close)),
    roc: latest(roc(close, 10)),
    vwap: latest(vwap(high, low, close, volume, 20)),
    obv: latest(obv(close, volume)),
    aroon: latest(aroon(high, low, 25).up),
    meanVolume: mean(volume),
  };
}
