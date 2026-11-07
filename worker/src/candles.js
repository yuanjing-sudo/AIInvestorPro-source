// Shared candle normalisation for every server-side provider. Providers return
// OHLCV or close-only series; this module gives the rest of the Worker one
// consistent shape with real Date objects.

export function round(value, digits = 2) {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

export function isoDate(date) {
  return date.toISOString().slice(0, 10);
}

export function makeCandle(date, open, high, low, close, volume = 0) {
  const candleDate = date instanceof Date ? date : new Date(date);
  const openValue = Number(open);
  const closeValue = Number(close);
  const highValue = Math.max(Number(high), openValue, closeValue);
  const lowValue = Math.min(Number(low), openValue, closeValue);
  return {
    date: candleDate,
    dateString: isoDate(candleDate),
    open: round(openValue),
    high: round(highValue),
    low: round(lowValue),
    close: round(closeValue),
    volume: Math.round(Number.isFinite(volume) ? volume : 0),
    vwap: round((highValue + lowValue + closeValue) / 3),
  };
}

export function candlesFromCloses(points, volumeByTime = new Map()) {
  let previous = null;
  const candles = [];
  for (const [timestamp, price] of points) {
    const close = Number(price);
    if (!Number.isFinite(close) || close <= 0) continue;
    const open = previous ?? close;
    candles.push(makeCandle(
      new Date(timestamp),
      open,
      Math.max(open, close),
      Math.min(open, close),
      close,
      volumeByTime.get(timestamp) ?? 0,
    ));
    previous = close;
  }
  return candles;
}


export function dailyCandlesFromCloses(points, volumeByTime = new Map()) {
  const groups = new Map();
  for (const [timestamp, price] of points) {
    const value = Number(price);
    if (!Number.isFinite(value) || value <= 0) continue;
    const date = new Date(timestamp);
    const key = isoDate(date);
    const group = groups.get(key) ?? { date: new Date(`${key}T00:00:00.000Z`), prices: [], volume: 0 };
    group.prices.push(value);
    group.volume += Number(volumeByTime.get(timestamp)) || 0;
    groups.set(key, group);
  }
  const candles = [];
  for (const group of groups.values()) {
    const open = group.prices[0];
    const close = group.prices[group.prices.length - 1];
    candles.push(makeCandle(
      group.date,
      open,
      Math.max(...group.prices),
      Math.min(...group.prices),
      close,
      group.volume,
    ));
  }
  return candles.sort((left, right) => left.date - right.date);
}

export function sortDedupe(candles) {
  const byDate = new Map();
  for (const candle of candles) byDate.set(candle.dateString, candle);
  return [...byDate.values()].sort((left, right) => left.date - right.date);
}

export function chartFromCandles(symbol, candles, meta = {}) {
  if (!candles.length) throw new Error(`No usable candles for ${symbol}`);
  const last = candles[candles.length - 1];
  const previous = candles.length > 1 ? candles[candles.length - 2] : last;
  const recent = candles.slice(-252);
  const price = last.close;
  return {
    symbol,
    candles,
    meta: {
      currency: meta.currency ?? 'USD',
      exchange: meta.exchange ?? '',
      instrumentType: meta.instrumentType ?? '',
      timezone: meta.timezone ?? '',
      regularMarketPrice: price,
      regularMarketTime: Math.floor(last.date.getTime() / 1000),
      fiftyTwoWeekHigh: meta.fiftyTwoWeekHigh ?? Math.max(...recent.map((candle) => candle.high)),
      fiftyTwoWeekLow: meta.fiftyTwoWeekLow ?? Math.min(...recent.map((candle) => candle.low)),
      longName: meta.longName ?? symbol,
      shortName: meta.shortName ?? meta.longName ?? symbol,
    },
    quote: {
      price,
      previousClose: previous.close,
      change: price - previous.close,
      changePercent: previous.close ? ((price / previous.close) - 1) * 100 : 0,
      high: last.high,
      low: last.low,
      open: last.open,
      volume: last.volume,
      asOf: last.date.toISOString(),
    },
  };
}
