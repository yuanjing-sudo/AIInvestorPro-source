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

function rmaOnOptional(series, period) {
  const indices = [];
  series.forEach((v, i) => { if (v !== null) indices.push(i); });
  if (period <= 0 || indices.length < period) return nils(series.length);
  const smoothed = rma(indices.map((i) => series[i]), period);
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

// Average Directional Index (Wilder). ADX measures trend strength, while
// +DI/-DI indicate direction. Values above 25 are commonly treated as a trend.
export function adx(high, low, close, period = 14) {
  const count = Math.min(high.length, low.length, close.length);
  const plusDI = nils(count);
  const minusDI = nils(count);
  const adxSeries = nils(count);
  if (count <= period) return { adx: adxSeries, plusDI, minusDI };
  const plusDM = new Array(count).fill(0);
  const minusDM = new Array(count).fill(0);
  const tr = new Array(count).fill(0);
  tr[0] = Math.max(0, high[0] - low[0]);
  for (let i = 1; i < count; i += 1) {
    const up = high[i] - high[i - 1];
    const down = low[i - 1] - low[i];
    plusDM[i] = up > down && up > 0 ? up : 0;
    minusDM[i] = down > up && down > 0 ? down : 0;
    tr[i] = Math.max(
      high[i] - low[i],
      Math.abs(high[i] - close[i - 1]),
      Math.abs(low[i] - close[i - 1]),
    );
  }
  const trSmooth = rma(tr, period);
  const plusSmooth = rma(plusDM, period);
  const minusSmooth = rma(minusDM, period);
  const dx = nils(count);
  for (let i = period - 1; i < count; i += 1) {
    if (!(trSmooth[i] > 0)) continue;
    plusDI[i] = (100 * plusSmooth[i]) / trSmooth[i];
    minusDI[i] = (100 * minusSmooth[i]) / trSmooth[i];
    const total = plusDI[i] + minusDI[i];
    dx[i] = total > 0 ? (100 * Math.abs(plusDI[i] - minusDI[i])) / total : 0;
  }
  return { adx: rmaOnOptional(dx, period), plusDI, minusDI };
}

export function mfi(high, low, close, volume, period = 14) {
  const count = Math.min(high.length, low.length, close.length, volume.length);
  const out = nils(count);
  const typical = new Array(count);
  for (let i = 0; i < count; i += 1) typical[i] = (high[i] + low[i] + close[i]) / 3;
  for (let i = period; i < count; i += 1) {
    let positive = 0;
    let negative = 0;
    for (let j = i - period + 1; j <= i; j += 1) {
      const flow = typical[j] * volume[j];
      if (typical[j] > typical[j - 1]) positive += flow;
      else if (typical[j] < typical[j - 1]) negative += flow;
    }
    if (negative === 0) out[i] = positive === 0 ? 50 : 100;
    else if (positive === 0) out[i] = 0;
    else out[i] = 100 - 100 / (1 + positive / negative);
  }
  return out;
}

export function cci(high, low, close, period = 20) {
  const count = Math.min(high.length, low.length, close.length);
  const typical = new Array(count);
  for (let i = 0; i < count; i += 1) typical[i] = (high[i] + low[i] + close[i]) / 3;
  const middle = sma(typical, period);
  const out = nils(count);
  for (let i = period - 1; i < count; i += 1) {
    const window = typical.slice(i - period + 1, i + 1);
    const deviation = mean(window.map((value) => Math.abs(value - middle[i])));
    out[i] = deviation > 0 ? (typical[i] - middle[i]) / (0.015 * deviation) : 0;
  }
  return out;
}

export function keltner(high, low, close, period = 20, multiplier = 2) {
  const count = Math.min(high.length, low.length, close.length);
  const middle = ema(close.slice(0, count), period);
  const atrSeries = atr(high.slice(0, count), low.slice(0, count), close.slice(0, count), period);
  const upper = nils(count);
  const lower = nils(count);
  for (let i = 0; i < count; i += 1) {
    if (middle[i] !== null && atrSeries[i] !== null) {
      upper[i] = middle[i] + multiplier * atrSeries[i];
      lower[i] = middle[i] - multiplier * atrSeries[i];
    }
  }
  return { upper, middle, lower };
}

export function chaikinMoneyFlow(high, low, close, volume, period = 20) {
  const count = Math.min(high.length, low.length, close.length, volume.length);
  const out = nils(count);
  for (let i = period - 1; i < count; i += 1) {
    let moneyFlow = 0;
    let totalVolume = 0;
    for (let j = i - period + 1; j <= i; j += 1) {
      const range = high[j] - low[j];
      const multiplier = range > 0
        ? ((close[j] - low[j]) - (high[j] - close[j])) / range
        : 0;
      moneyFlow += multiplier * volume[j];
      totalVolume += volume[j];
    }
    out[i] = totalVolume > 0 ? moneyFlow / totalVolume : 0;
  }
  return out;
}

export function regressionSlope(values, period = 20) {
  const out = nils(values.length);
  if (period < 2) return out;
  const xMean = (period - 1) / 2;
  let denominator = 0;
  for (let x = 0; x < period; x += 1) denominator += (x - xMean) ** 2;
  for (let i = period - 1; i < values.length; i += 1) {
    const window = values.slice(i - period + 1, i + 1);
    const yMean = mean(window);
    let numerator = 0;
    for (let x = 0; x < period; x += 1) numerator += (x - xMean) * (window[x] - yMean);
    out[i] = denominator > 0 ? numerator / denominator : 0;
  }
  return out;
}

export function realizedVolatility(values, period = 21) {
  if (values.length < period + 1) return null;
  const returns = [];
  for (let i = values.length - period; i < values.length; i += 1) {
    if (values[i - 1] > 0) returns.push(values[i] / values[i - 1] - 1);
  }
  return returns.length > 1 ? stdev(returns) * Math.sqrt(252) : null;
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
  const macdResult = macd(close);
  const bollingerResult = bollinger(close);
  const donchianResult = donchian(high, low, 20);
  const keltnerResult = keltner(high, low, close, 20);
  const aroonResult = aroon(high, low, 25);
  const adxResult = adx(high, low, close, 14);
  const obvSeries = obv(close, volume);
  const meanVolume = mean(volume);
  const lastClose = close.at(-1) ?? null;
  const bollingerRange = Number.isFinite(bollingerResult.upper.at(-1)) && Number.isFinite(bollingerResult.lower.at(-1))
    ? latest(bollingerResult.upper) - latest(bollingerResult.lower)
    : null;
  const bollingerMiddle = latest(bollingerResult.middle);
  const donchianUpper = latest(donchianResult.upper);
  const donchianLower = latest(donchianResult.lower);
  const donchianRange = Number.isFinite(donchianUpper) && Number.isFinite(donchianLower)
    ? donchianUpper - donchianLower
    : 0;
  const keltnerUpper = latest(keltnerResult.upper);
  const keltnerLower = latest(keltnerResult.lower);
  const keltnerRange = Number.isFinite(keltnerUpper) && Number.isFinite(keltnerLower)
    ? keltnerUpper - keltnerLower
    : 0;
  const obvSlope = latest(regressionSlope(obvSeries, 20));
  const closeSlope = latest(regressionSlope(close, 20));
  const volumeSlope = latest(regressionSlope(volume, 20));
  const meanClose = mean(close.slice(-20));
  const meanVolume20 = mean(volume.slice(-20));
  return {
    close,
    sma20: latest(sma(close, 20)),
    sma50: latest(sma(close, 50)),
    ema12: latest(ema(close, 12)),
    ema26: latest(ema(close, 26)),
    rsi: latest(rsi(close, 14)),
    atr: latest(atr(high, low, close, 14)),
    macd: latest(macdResult.macd),
    macdSignal: latest(macdResult.signal),
    macdHistogram: latest(macdResult.histogram),
    bollinger: {
      upper: latest(bollingerResult.upper),
      middle: bollingerMiddle,
      lower: latest(bollingerResult.lower),
      bandwidth: bollingerMiddle > 0 && Number.isFinite(bollingerRange)
        ? bollingerRange / bollingerMiddle
        : null,
      position: Number.isFinite(bollingerRange) && bollingerRange > 0 && Number.isFinite(lastClose)
        ? (lastClose - latest(bollingerResult.lower)) / bollingerRange
        : null,
    },
    stochastic: latest(stochastic(high, low, close).k),
    williams: latest(williamsR(high, low, close)),
    roc: latest(roc(close, 10)),
    vwap: latest(vwap(high, low, close, volume, 20)),
    obv: latest(obvSeries),
    obvSlope,
    obvSlopePercent: meanVolume20 > 0 && Number.isFinite(obvSlope) ? (obvSlope / meanVolume20) * 100 : null,
    aroon: latest(aroonResult.up),
    aroonDown: latest(aroonResult.down),
    adx: latest(adxResult.adx),
    plusDI: latest(adxResult.plusDI),
    minusDI: latest(adxResult.minusDI),
    mfi: latest(mfi(high, low, close, volume, 14)),
    cci: latest(cci(high, low, close, 20)),
    donchian: {
      upper: donchianUpper,
      middle: latest(donchianResult.middle),
      lower: donchianLower,
      position: donchianRange > 0 && Number.isFinite(lastClose)
        ? (lastClose - donchianLower) / donchianRange
        : null,
    },
    keltner: {
      upper: keltnerUpper,
      middle: latest(keltnerResult.middle),
      lower: keltnerLower,
      position: keltnerRange > 0 && Number.isFinite(lastClose)
        ? (lastClose - keltnerLower) / keltnerRange
        : null,
    },
    cmf: latest(chaikinMoneyFlow(high, low, close, volume, 20)),
    regressionSlope: closeSlope,
    regressionSlopePercent: meanClose > 0 && Number.isFinite(closeSlope)
      ? (closeSlope / meanClose) * 100
      : null,
    volumeSlope,
    volumeTrendPercent: meanVolume20 > 0 && Number.isFinite(volumeSlope)
      ? (volumeSlope / meanVolume20) * 100
      : null,
    realizedVolatility21d: realizedVolatility(close, 21),
    meanVolume,
    volumeRatio: meanVolume > 0 ? (volume.at(-1) ?? 0) / meanVolume : null,
  };
}

function compactNumber(value, digits = 1) {
  if (!Number.isFinite(value)) return '—';
  const absolute = Math.abs(value);
  if (absolute >= 1e12) return `${(value / 1e12).toFixed(digits)}T`;
  if (absolute >= 1e9) return `${(value / 1e9).toFixed(digits)}B`;
  if (absolute >= 1e6) return `${(value / 1e6).toFixed(digits)}M`;
  if (absolute >= 1e3) return `${(value / 1e3).toFixed(digits)}K`;
  return value.toFixed(digits);
}

function indicatorDisplay(value, format = 'number', digits = 2) {
  if (!Number.isFinite(value)) return '—';
  if (format === 'percent') return `${(value * 100).toFixed(digits)}%`;
  if (format === 'percentValue') return `${value.toFixed(digits)}%`;
  if (format === 'money') return `$${value.toFixed(digits)}`;
  if (format === 'moneyCompact') return `$${compactNumber(value, digits)}`;
  if (format === 'ratio') return `${value.toFixed(digits)}×`;
  if (format === 'compact') return compactNumber(value, digits);
  return value.toFixed(digits);
}

// A single source of truth for indicator values, display strings, signals and
// plain-English summaries. Research and the AI Analyst both render this list.
export function indicatorDetails(candles) {
  const s = summarize(candles);
  const price = s.close.at(-1) ?? null;
  const atrPercent = Number.isFinite(s.atr) && price ? s.atr / price : null;
  const detail = (key, label, value, format, digits, signal, tone, summary, reading) => ({
    key,
    label,
    value,
    display: indicatorDisplay(value, format, digits),
    signal,
    tone,
    summary,
    reading,
  });
  return [
    detail('rsi14', 'RSI · 14', s.rsi, 'number', 1,
      s.rsi > 70 ? 'Overbought' : s.rsi < 30 ? 'Oversold' : 'Neutral',
      s.rsi > 70 ? 'warn' : s.rsi < 30 ? 'bad' : '',
      'RSI compares average gains with average losses on a 0-100 scale. Above 70 is often overbought, below 30 oversold and 50 is neutral.',
      Number.isFinite(s.rsi) ? `At ${s.rsi.toFixed(1)}, momentum is ${s.rsi > 70 ? 'stretched to the upside' : s.rsi < 30 ? 'washed out' : 'not at an extreme'}.` : 'Not enough history.'),
    detail('macdHistogram', 'MACD hist.', s.macdHistogram, 'number', 3,
      s.macdHistogram >= 0 ? 'Bullish' : 'Bearish',
      s.macdHistogram >= 0 ? 'good' : 'bad',
      'MACD compares fast and slow exponential averages. The histogram shows whether momentum is accelerating or fading versus its signal line.',
      Number.isFinite(s.macdHistogram) ? `The histogram is ${s.macdHistogram >= 0 ? 'positive' : 'negative'}, so short-term momentum is ${s.macdHistogram >= 0 ? 'above' : 'below'} its signal line.` : 'Not enough history.'),
    detail('atr14', 'ATR · 14', s.atr, 'money', 2,
      Number.isFinite(atrPercent) && atrPercent > 0.04 ? 'High volatility' : 'Normal range',
      Number.isFinite(atrPercent) && atrPercent > 0.04 ? 'warn' : '',
      'Average True Range measures the typical daily trading range, including gaps. It is a volatility and position-sizing input, not a direction call.',
      Number.isFinite(atrPercent) ? `A one-day move of about ${(atrPercent * 100).toFixed(2)}% of price is normal for this window.` : 'Not enough history.'),
    detail('bollingerPosition', 'Bollinger pos.', s.bollinger.position, 'percent', 0,
      s.bollinger.position > 0.9 ? 'Upper band' : s.bollinger.position < 0.1 ? 'Lower band' : 'Inside bands',
      s.bollinger.position > 0.9 ? 'warn' : s.bollinger.position < 0.1 ? 'bad' : '',
      'Bollinger position locates price between the lower and upper volatility bands. Extremes can signal stretch, but strong trends can ride a band.',
      Number.isFinite(s.bollinger.position) ? `Price is at ${(s.bollinger.position * 100).toFixed(0)}% of the 20-day band range.` : 'Not enough history.'),
    detail('stochastic14', 'Stochastic', s.stochastic, 'number', 1,
      s.stochastic > 80 ? 'Overbought' : s.stochastic < 20 ? 'Oversold' : 'Neutral',
      s.stochastic > 80 ? 'warn' : s.stochastic < 20 ? 'bad' : '',
      'Stochastic compares the close with the recent high-low range. It is a short-term momentum oscillator sensitive to mean reversion.',
      Number.isFinite(s.stochastic) ? `The %K reading is ${s.stochastic.toFixed(1)}.` : 'Not enough history.'),
    detail('williamsR14', 'Williams %R', s.williams, 'number', 1,
      s.williams > -20 ? 'Overbought' : s.williams < -80 ? 'Oversold' : 'Neutral',
      s.williams > -20 ? 'warn' : s.williams < -80 ? 'bad' : '',
      'Williams %R is an inverted stochastic: readings near 0 are overbought and near -100 oversold. It works best with trend confirmation.',
      Number.isFinite(s.williams) ? `The reading is ${s.williams.toFixed(1)}.` : 'Not enough history.'),
    detail('roc10', 'ROC · 10', s.roc, 'percentValue', 2,
      s.roc >= 0 ? 'Positive momentum' : 'Negative momentum',
      s.roc >= 0 ? 'good' : 'bad',
      'Rate of change measures the percentage move over ten bars. It is a raw momentum reading, not a valuation signal.',
      Number.isFinite(s.roc) ? `Price is ${s.roc >= 0 ? 'up' : 'down'} ${Math.abs(s.roc).toFixed(2)}% over the lookback.` : 'Not enough history.'),
    detail('vwap20', 'VWAP · 20', s.vwap, 'money', 2,
      price >= s.vwap ? 'Above VWAP' : 'Below VWAP',
      price >= s.vwap ? 'good' : 'bad',
      'VWAP is the volume-weighted average price. Trading above it suggests buyers have paid up on volume; below it suggests supply.',
      Number.isFinite(s.vwap) ? `Price is ${price >= s.vwap ? 'above' : 'below'} the 20-day volume-weighted average.` : 'Not enough history.'),
    detail('obv', 'OBV', s.obv, 'compact', 1,
      s.obvSlope > 0 ? 'Accumulation' : s.obvSlope < 0 ? 'Distribution' : 'Flat',
      s.obvSlope > 0 ? 'good' : s.obvSlope < 0 ? 'bad' : '',
      'On-balance volume adds volume on up days and subtracts it on down days. The slope helps distinguish accumulation from distribution.',
      Number.isFinite(s.obvSlopePercent) ? `The 20-bar OBV slope is ${s.obvSlopePercent >= 0 ? 'positive' : 'negative'} (${s.obvSlopePercent.toFixed(2)}% of average volume).` : 'Not enough history.'),
    detail('aroonUp25', 'Aroon Up · 25', s.aroon, 'number', 1,
      s.aroon > 70 ? 'Strong trend' : s.aroon < 30 ? 'Weak trend' : 'Transition',
      s.aroon > 70 ? 'good' : s.aroon < 30 ? 'bad' : '',
      'Aroon measures how recently price made a 25-bar high. High readings mean the uptrend is fresh; low readings mean it is aging.',
      Number.isFinite(s.aroon) ? `The last 25-bar high was about ${(((100 - s.aroon) / 100) * 25).toFixed(0)} bars ago.` : 'Not enough history.'),
    detail('aroonDown25', 'Aroon Down · 25', s.aroonDown, 'number', 1,
      s.aroonDown > 70 ? 'Fresh lows' : s.aroonDown < 30 ? 'Lows aging' : 'Transition',
      s.aroonDown > 70 ? 'bad' : '',
      'Aroon Down measures how recently price made a 25-bar low. Rising readings show fresh downside pressure.',
      Number.isFinite(s.aroonDown) ? `The Aroon Down reading is ${s.aroonDown.toFixed(1)}.` : 'Not enough history.'),
    detail('volumeRatio', 'Volume ratio', s.volumeRatio, 'ratio', 2,
      s.volumeRatio > 1.4 ? 'Volume expansion' : s.volumeRatio < 0.7 ? 'Volume contraction' : 'Normal',
      s.volumeRatio > 1.4 ? 'good' : '',
      'Volume ratio compares the latest bar with the 20-day average. Expansion confirms moves; contraction warns that a move lacks participation.',
      Number.isFinite(s.volumeRatio) ? `Latest volume is ${s.volumeRatio.toFixed(2)}× the 20-day average.` : 'Not enough history.'),
    detail('realizedVolatility21d', 'Realized vol.', s.realizedVolatility21d, 'percent', 1,
      s.realizedVolatility21d > 0.35 ? 'Elevated' : 'Contained',
      s.realizedVolatility21d > 0.35 ? 'warn' : '',
      'Realized volatility annualizes the standard deviation of recent daily returns. It is backward-looking and regime-sensitive.',
      Number.isFinite(s.realizedVolatility21d) ? `Recent annualized volatility is ${(s.realizedVolatility21d * 100).toFixed(1)}%.` : 'Not enough history.'),
    detail('adx14', 'ADX · 14', s.adx, 'number', 1,
      s.adx > 25 ? (s.plusDI >= s.minusDI ? 'Strong uptrend' : 'Strong downtrend') : 'Weak trend',
      s.adx > 25 ? (s.plusDI >= s.minusDI ? 'good' : 'bad') : 'warn',
      'ADX measures trend strength regardless of direction. Above 25 is trending; below 20 is often choppy. +DI and -DI give the direction.',
      Number.isFinite(s.adx) ? `ADX is ${s.adx.toFixed(1)}, with +DI ${Number.isFinite(s.plusDI) ? s.plusDI.toFixed(1) : '—'} and -DI ${Number.isFinite(s.minusDI) ? s.minusDI.toFixed(1) : '—'}.` : 'Not enough history.'),
    detail('mfi14', 'MFI · 14', s.mfi, 'number', 1,
      s.mfi > 80 ? 'Overbought' : s.mfi < 20 ? 'Oversold' : 'Neutral',
      s.mfi > 80 ? 'warn' : s.mfi < 20 ? 'bad' : '',
      'Money Flow Index combines price and volume to estimate buying or selling pressure. It is a volume-weighted RSI.',
      Number.isFinite(s.mfi) ? `MFI is ${s.mfi.toFixed(1)}; ${s.mfi > 80 ? 'buying pressure is stretched' : s.mfi < 20 ? 'selling pressure is stretched' : 'flow is balanced'}.` : 'Not enough history.'),
    detail('cci20', 'CCI · 20', s.cci, 'number', 1,
      s.cci > 100 ? 'Overbought' : s.cci < -100 ? 'Oversold' : 'Neutral',
      s.cci > 100 ? 'warn' : s.cci < -100 ? 'bad' : '',
      'Commodity Channel Index measures price deviation from its typical-price average. Extremes can flag cyclical turning points.',
      Number.isFinite(s.cci) ? `CCI is ${s.cci.toFixed(1)}.` : 'Not enough history.'),
    detail('donchianPosition20', 'Donchian pos.', s.donchian.position, 'percent', 0,
      s.donchian.position > 0.9 ? 'Near high' : s.donchian.position < 0.1 ? 'Near low' : 'Mid-channel',
      s.donchian.position > 0.9 ? 'good' : s.donchian.position < 0.1 ? 'bad' : '',
      'Donchian position locates price inside the 20-day high-low channel. Channel edges are common breakout and stop references.',
      Number.isFinite(s.donchian.position) ? `Price is at ${(s.donchian.position * 100).toFixed(0)}% of the 20-day channel.` : 'Not enough history.'),
    detail('keltnerPosition20', 'Keltner pos.', s.keltner.position, 'percent', 0,
      s.keltner.position > 1 ? 'Above upper' : s.keltner.position < 0 ? 'Below lower' : 'Inside channel',
      s.keltner.position > 1 ? 'good' : s.keltner.position < 0 ? 'bad' : '',
      'Keltner position compares price with an EMA plus/minus ATR bands. It combines trend and volatility and is useful for breakout confirmation.',
      Number.isFinite(s.keltner.position) ? `Price is at ${(s.keltner.position * 100).toFixed(0)}% of the Keltner channel.` : 'Not enough history.'),
    detail('cmf20', 'Chaikin MF · 20', s.cmf, 'number', 3,
      s.cmf > 0.05 ? 'Accumulation' : s.cmf < -0.05 ? 'Distribution' : 'Balanced',
      s.cmf > 0.05 ? 'good' : s.cmf < -0.05 ? 'bad' : '',
      'Chaikin Money Flow weights volume by where the close sits in each bar range. Positive readings indicate accumulation.',
      Number.isFinite(s.cmf) ? `CMF is ${s.cmf.toFixed(3)}.` : 'Not enough history.'),
    detail('obvSlope20', 'OBV slope · 20', s.obvSlopePercent, 'percentValue', 2,
      s.obvSlope > 0 ? 'Rising' : s.obvSlope < 0 ? 'Falling' : 'Flat',
      s.obvSlope > 0 ? 'good' : s.obvSlope < 0 ? 'bad' : '',
      'OBV slope measures whether cumulative volume is trending up or down. It is a confirmation filter for price trends.',
      Number.isFinite(s.obvSlopePercent) ? `The normalized OBV slope is ${s.obvSlopePercent.toFixed(2)}%.` : 'Not enough history.'),
    detail('bollingerBandwidth20', 'BB bandwidth', s.bollinger.bandwidth, 'percent', 1,
      s.bollinger.bandwidth < 0.06 ? 'Squeeze' : s.bollinger.bandwidth > 0.15 ? 'Expanded' : 'Normal',
      s.bollinger.bandwidth < 0.06 ? 'warn' : '',
      'Bollinger bandwidth measures how wide the volatility bands are relative to price. A squeeze often precedes a larger move, without predicting direction.',
      Number.isFinite(s.bollinger.bandwidth) ? `Band width is ${(s.bollinger.bandwidth * 100).toFixed(1)}% of the midline.` : 'Not enough history.'),
    detail('regressionSlope20', 'Trend slope · 20', s.regressionSlopePercent, 'percentValue', 3,
      s.regressionSlopePercent > 0 ? 'Upward' : s.regressionSlopePercent < 0 ? 'Downward' : 'Flat',
      s.regressionSlopePercent > 0 ? 'good' : s.regressionSlopePercent < 0 ? 'bad' : '',
      'Linear regression slope fits a straight line to the last 20 closes. It gives a clean, noise-reduced direction and speed estimate.',
      Number.isFinite(s.regressionSlopePercent) ? `The fitted trend is ${s.regressionSlopePercent >= 0 ? 'rising' : 'falling'} ${Math.abs(s.regressionSlopePercent).toFixed(3)}% per bar.` : 'Not enough history.'),
    detail('volumeTrend20', 'Volume trend · 20', s.volumeTrendPercent, 'percentValue', 1,
      s.volumeTrendPercent > 5 ? 'Rising' : s.volumeTrendPercent < -5 ? 'Falling' : 'Stable',
      s.volumeTrendPercent > 5 ? 'good' : s.volumeTrendPercent < -5 ? 'warn' : '',
      'Volume trend is the regression slope of volume, normalized by average volume. Rising participation can validate a move; falling participation can weaken it.',
      Number.isFinite(s.volumeTrendPercent) ? `Volume is ${s.volumeTrendPercent >= 0 ? 'trending higher' : 'trending lower'} by ${Math.abs(s.volumeTrendPercent).toFixed(1)}% of average per bar.` : 'Not enough history.'),
  ];
}
