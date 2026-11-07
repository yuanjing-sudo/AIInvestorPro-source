// FRED (Federal Reserve Bank of St. Louis) macro series. The CSV endpoint is
// public and does not require an API key.

import { cachedText } from './http.js';

export async function fetchFredSeries(seriesId, options = {}) {
  const url = `https://fred.stlouisfed.org/graph/fredgraph.csv?id=${encodeURIComponent(seriesId)}`;
  const text = await cachedText(url, {
    ttl: options.ttl ?? 3600,
    cache: options.cache !== false,
    label: 'FRED',
  });
  const lines = text.trim().split(/\r?\n/);
  const observations = [];
  for (let index = 1; index < lines.length; index += 1) {
    const [date, raw] = lines[index].split(',');
    const value = Number(raw);
    if (!date || !Number.isFinite(value)) continue;
    observations.push({ date, value });
  }
  if (!observations.length) throw new Error(`FRED ${seriesId} returned no observations`);
  return { id: seriesId, observations, latest: observations.at(-1), source: 'fred' };
}

export function latestValue(series) {
  return series?.latest?.value ?? null;
}

export function valueMonthsAgo(series, months) {
  const latest = series?.latest;
  if (!latest) return null;
  const target = new Date(`${latest.date}T00:00:00Z`);
  target.setUTCMonth(target.getUTCMonth() - months);
  let match = null;
  for (const observation of series.observations) {
    if (new Date(`${observation.date}T00:00:00Z`) <= target) match = observation;
    else break;
  }
  return match?.value ?? null;
}

export function yearOverYear(series) {
  const latest = latestValue(series);
  const previous = valueMonthsAgo(series, 12);
  if (!Number.isFinite(latest) || !Number.isFinite(previous) || previous === 0) return null;
  return latest / previous - 1;
}
