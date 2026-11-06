// Dependency-free numerical helpers shared by the browser app and Node tests.

export function sum(values) {
  return values.reduce((a, b) => a + b, 0);
}

export function mean(values) {
  return values.length ? sum(values) / values.length : 0;
}

export function variance(values, sample = true) {
  if (values.length < 2) return 0;
  const mu = mean(values);
  const divisor = sample ? values.length - 1 : values.length;
  return values.reduce((acc, v) => acc + (v - mu) * (v - mu), 0) / divisor;
}

export function stdev(values, sample = true) {
  return Math.sqrt(Math.max(0, variance(values, sample)));
}

export function covariance(a, b, sample = true) {
  const n = Math.min(a.length, b.length);
  if (n < 2) return 0;
  const x = a.slice(0, n);
  const y = b.slice(0, n);
  const mx = mean(x);
  const my = mean(y);
  const divisor = sample ? n - 1 : n;
  let total = 0;
  for (let i = 0; i < n; i += 1) total += (x[i] - mx) * (y[i] - my);
  return total / divisor;
}

export function correlation(a, b) {
  const n = Math.min(a.length, b.length);
  if (n < 2) return 0;
  const x = a.slice(0, n);
  const y = b.slice(0, n);
  const denom = stdev(x) * stdev(y);
  return denom > 0 ? covariance(x, y) / denom : 0;
}

export function percentileSorted(sorted, p) {
  if (!sorted.length) return 0;
  const q = Math.min(Math.max(p, 0), 1);
  if (sorted.length === 1) return sorted[0];
  const rank = q * (sorted.length - 1);
  const lower = Math.floor(rank);
  const upper = Math.ceil(rank);
  const weight = rank - lower;
  if (lower === upper) return sorted[lower];
  return sorted[lower] * (1 - weight) + sorted[upper] * weight;
}

export function percentile(values, p) {
  return percentileSorted([...values].sort((a, b) => a - b), p);
}

// Acklam inverse normal CDF, used by parametric risk calculations.
export function inverseNormal(p) {
  const probability = Math.min(Math.max(p, 1e-12), 1 - 1e-12);
  const a = [-3.969683028665376e1, 2.209460984245205e2, -2.759285104469687e2,
    1.38357751867269e2, -3.066479806614716e1, 2.506628277459239];
  const b = [-5.447609879822406e1, 1.615858368580409e2, -1.556989798598866e2,
    6.680131188771972e1, -1.328068155288572e1];
  const c = [-7.784894002430293e-3, -3.223964580411365e-1, -2.400758277161838,
    -2.549732539343734, 4.374664141464968, 2.938163982698783];
  const d = [7.784695709041462e-3, 3.224671290700398e-1, 2.445134137142996,
    3.754408661907416];
  const low = 0.02425;
  const high = 1 - low;
  if (probability < low) {
    const q = Math.sqrt(-2 * Math.log(probability));
    return (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
      ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1);
  }
  if (probability > high) {
    const q = Math.sqrt(-2 * Math.log(1 - probability));
    return -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) /
      ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1);
  }
  const q = probability - 0.5;
  const r = q * q;
  return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q /
    (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1);
}

export function cholesky(matrix) {
  const n = matrix.length;
  if (!n || matrix.some((row) => row.length !== n)) return null;
  const lower = Array.from({ length: n }, () => new Array(n).fill(0));
  for (let i = 0; i < n; i += 1) {
    for (let j = 0; j <= i; j += 1) {
      let value = matrix[i][j];
      for (let k = 0; k < j; k += 1) value -= lower[i][k] * lower[j][k];
      if (i === j) {
        if (value <= 1e-12) return null;
        lower[i][j] = Math.sqrt(value);
      } else {
        if (Math.abs(lower[j][j]) <= 1e-12) return null;
        lower[i][j] = value / lower[j][j];
      }
    }
  }
  return lower;
}

export function matrixVector(matrix, vector) {
  return matrix.map((row) => row.reduce((acc, v, i) => acc + v * vector[i], 0));
}

export function dot(a, b) {
  const n = Math.min(a.length, b.length);
  let total = 0;
  for (let i = 0; i < n; i += 1) total += a[i] * b[i];
  return total;
}

export function projectToSimplex(values, maxWeight = 1) {
  const n = values.length;
  if (!n) return [];
  const upper = Math.max(maxWeight, 1 / n);
  if (n * upper < 1) return new Array(n).fill(1 / n);

  let low = Math.min(...values) - upper - 1;
  let high = Math.max(...values) + 1;
  let result = values.slice();

  for (let i = 0; i < 80; i += 1) {
    const mid = (low + high) / 2;
    result = values.map((v) => Math.min(Math.max(v - mid, 0), upper));
    const total = sum(result);
    if (total > 1) low = mid; else high = mid;
  }
  let total = sum(result);
  if (total > 0) result = result.map((v) => v / total);
  result = result.map((v) => Math.min(Math.max(v, 0), upper));
  total = sum(result);
  if (total > 0) result = result.map((v) => v / total);
  return result;
}

export function maxAbs(values) {
  return values.reduce((acc, v) => Math.max(acc, Math.abs(v)), 0);
}

export class SeededRandom {
  constructor(seed = 42n) {
    const mask = (1n << 64n) - 1n;
    this.mask = mask;
    this.state = BigInt(seed) & mask;
    if (this.state === 0n) this.state = 0x9E3779B97F4A7C15n;
  }

  next() {
    this.state = (this.state + 0x9E3779B97F4A7C15n) & this.mask;
    let z = this.state;
    z = ((z ^ (z >> 30n)) * 0xBF58476D1CE4E5B9n) & this.mask;
    z = ((z ^ (z >> 27n)) * 0x94D049BB133111EBn) & this.mask;
    z ^= z >> 31n;
    return Number(z >> 11n) / 9007199254740992;
  }

  gaussian() {
    const u1 = Math.max(this.next(), 1e-12);
    const u2 = this.next();
    return Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
  }
}

export function fnv1a(text) {
  let hash = 14695981039346656037n;
  for (const byte of new TextEncoder().encode(text)) {
    hash ^= BigInt(byte);
    hash = (hash * 1099511628211n) & 0xFFFFFFFFFFFFFFFFn;
  }
  return hash;
}

export function clamp(value, low, high) {
  return Math.min(Math.max(value, low), high);
}

export function pct(value, decimals = 2) {
  if (!Number.isFinite(value)) return '—';
  return `${(value * 100).toFixed(decimals)}%`;
}

export function money(value, currency = 'USD', decimals = 2) {
  if (!Number.isFinite(value)) return '—';
  try {
    return new Intl.NumberFormat(undefined, {
      style: 'currency', currency, maximumFractionDigits: decimals,
    }).format(value);
  } catch {
    return `${value.toFixed(decimals)} ${currency}`;
  }
}

export function num(value, decimals = 2) {
  if (!Number.isFinite(value)) return '—';
  return value.toFixed(decimals);
}
