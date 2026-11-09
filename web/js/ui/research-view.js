// Research terminal: relative strength, drawdown, fundamentals, macro,
// correlation, sentiment and data-quality coverage for one asset.

import {
  quotes, candleMap, fundamentals, news, quality, sources, macro, market, secBySymbol,
  assetsBySymbol, returnsBySymbol, indicators, state, $, escapeHtml, dateShort, sourceLabel,
  formatMoney, formatMoneyCompact, formatPercent, formatSignedPercent,
  formatNumber, formatCompact, signClass, makeChart, statCard, toast, fillSymbolSelect,
  hydrateSymbol,
} from './shared.js';
import { live, fetchSymbol } from '../core/live.js';
import { analyzeReturns, drawdownSeries } from '../core/analytics.js';
import { correlationMatrix, beta } from '../core/risk.js';
import {
  performanceWindows, historicalVolatility, pricePercentile, sentimentSummary,
  drawdownSeriesFromCandles,
} from '../core/marketdata.js';
import { sma, indicatorDetails } from '../core/indicators.js';

let relativeChart = null;
let drawdownChart = null;
let priceChart = null;
let annotateMode = false;

const deepLoaded = new Set();
const deepLoading = new Set();

async function ensureDeep(symbol) {
  if (!live.enabled || deepLoaded.has(symbol) || deepLoading.has(symbol)) return;
  deepLoading.add(symbol);
  try {
    const payload = await fetchSymbol(symbol, { deep: true, range: '2y' });
    if (hydrateSymbol(payload)) deepLoaded.add(symbol);
  } catch {
    // The snapshot still provides prices and technicals if deep data is unavailable.
  } finally {
    deepLoading.delete(symbol);
  }
}

const ANNOTATIONS_KEY = 'ik.annotations.v1';
const ANNOTATION_COLORS = ['#f6c85f', '#2ee6c5', '#7dd3fc', '#f0abfc', '#fda4af', '#a3e635'];

function readAnnotations() {
  try {
    const parsed = JSON.parse(localStorage.getItem(ANNOTATIONS_KEY) ?? '{}');
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch {
    return {};
  }
}

function writeAnnotations(all) {
  try {
    localStorage.setItem(ANNOTATIONS_KEY, JSON.stringify(all));
  } catch {
    // Storage can be unavailable in private modes; annotations remain in memory.
  }
}

function symbolAnnotations(symbol) {
  const all = readAnnotations();
  return Array.isArray(all[symbol]) ? all[symbol] : [];
}

function saveSymbolAnnotations(symbol, items) {
  const all = readAnnotations();
  all[symbol] = items.slice(-40);
  writeAnnotations(all);
}

function annotationColor(index) {
  return ANNOTATION_COLORS[index % ANNOTATION_COLORS.length];
}

function renderAnnotationList(symbol, labels) {
  const target = $('#research-annotations');
  if (!target) return;
  const items = symbolAnnotations(symbol);
  if (!items.length) {
    target.innerHTML = '<span class="muted small">No notes yet. Enable Annotate and click the chart to add one.</span>';
    return;
  }
  target.innerHTML = items.map((item) => {
    const index = labels.indexOf(item.date);
    const price = index >= 0 ? ` · bar ${index + 1}` : ' · outside current window';
    return `<span class="annotation-chip" style="--annotation-color:${item.color || '#f6c85f'}">
      <span>${escapeHtml(item.label)}</span>
      <small>${escapeHtml(item.date)}${price}</small>
      <button type="button" class="annotation-remove" data-annotation-id="${escapeHtml(item.id)}" aria-label="Remove annotation">×</button>
    </span>`;
  }).join('');
}

function renderPriceChart(symbol, candles, quote, vol) {
  const slice = candles.slice(-252);
  const labels = slice.map((candle) => dateShort(candle.date));
  const closes = slice.map((candle) => candle.close);
  if (!priceChart) {
    priceChart = makeChart($('#research-price-canvas'), {
      height: 300,
      yFormat: (value) => formatMoney(value, 2),
      xFormat: (label) => label,
      showLegend: true,
      onClick: ({ label, value }) => {
        if (!annotateMode) return;
        const text = window.prompt(`Annotation for ${symbol} on ${label}:`, '');
        if (!text?.trim()) return;
        const items = symbolAnnotations(symbol);
        items.push({
          id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
          date: label,
          label: text.trim().slice(0, 120),
          price: Number.isFinite(value) ? Number(value.toFixed(2)) : null,
          color: annotationColor(items.length),
        });
        saveSymbolAnnotations(symbol, items);
        renderPriceChart(symbol, candles, quote, vol);
        toast(`Annotation saved for ${symbol}`);
      },
    });
  }
  const saved = symbolAnnotations(symbol);
  const annotations = saved
    .map((item) => ({ ...item, index: labels.indexOf(item.date) }))
    .filter((item) => item.index >= 0);
  priceChart.setData({
    labels,
    annotations,
    series: [
      { name: symbol, values: closes, color: '#2ee6c5', width: 2, area: true },
      { name: 'SMA20', values: sma(closes, 20), color: '#7dd3fc', width: 1.3, silent: true },
      { name: 'SMA50', values: sma(closes, 50), color: '#f6c85f', width: 1.2, silent: true },
    ],
    yFormat: (value) => formatMoney(value, 2),
  });
  const pill = $('#research-price-pill');
  if (pill) pill.textContent = `${formatMoney(quote.price, 2)} · ${formatPercent(vol, 1)} vol · ${saved.length} notes`;
  renderAnnotationList(symbol, labels);
}

function technicalRows(symbol) {
  return indicatorDetails(candleMap[symbol] ?? []);
}

function renderTechnical(symbol, quote) {
  const target = $('#research-technical');
  if (!target) return;
  const rows = technicalRows(symbol);
  target.innerHTML = rows.map((row) => `<div class="indicator-cell" title="${escapeHtml(row.summary)}">
    <span>${escapeHtml(row.label)}</span>
    <strong class="${row.tone}">${escapeHtml(row.display)}</strong>
    <small>${escapeHtml(row.signal)}</small>
    <p class="indicator-summary">${escapeHtml(row.summary)}</p>
    <p class="indicator-reading">${escapeHtml(row.reading)}</p>
  </div>`).join('');
  const bullish = rows.filter((row) => row.tone === 'good').length;
  const bearish = rows.filter((row) => row.tone === 'bad').length;
  const summary = $('#research-technical-summary');
  if (summary) {
    summary.textContent = `${rows.length} indicators · ${bullish} constructive · ${bearish} cautionary · ${rows.length - bullish - bearish} neutral`;
  }
  const trend = $('#research-trend-pill');
  if (trend) {
    const close = quote?.price ?? 0;
    const row = indicators[symbol] ?? {};
    const bullishTrend = close > row.sma20 && row.sma20 > row.sma50;
    const bearishTrend = close < row.sma20 && row.sma20 < row.sma50;
    trend.textContent = bullishTrend ? 'Uptrend' : bearishTrend ? 'Downtrend' : 'Sideways';
    trend.className = `pill ${bullishTrend ? 'good' : bearishTrend ? 'bad' : 'warn'}`;
  }
}

const PEERS = ['SPY', 'QQQ', 'TLT', 'GLD', 'BTC-USD', 'AAPL', 'JPM', 'XOM'];

export function initResearch() {
  const select = $('#research-symbol');
  if (!select) return;
  fillSymbolSelect(select, state.research.symbol);
  select.addEventListener('change', () => {
    state.research.symbol = select.value;
    renderResearch();
    ensureDeep(state.research.symbol);
  });
  $('#research-export')?.addEventListener('click', exportSnapshot);
  $('#research-annotate')?.addEventListener('click', () => {
    annotateMode = !annotateMode;
    const button = $('#research-annotate');
    if (button) {
      button.setAttribute('aria-pressed', String(annotateMode));
      button.classList.toggle('primary', annotateMode);
    }
    toast(annotateMode ? 'Annotation mode on · click the price chart to add a note' : 'Annotation mode off');
  });
  $('#research-annotations')?.addEventListener('click', (event) => {
    const button = event.target.closest('[data-annotation-id]');
    if (!button) return;
    const symbol = state.research.symbol;
    const items = symbolAnnotations(symbol).filter((item) => item.id !== button.dataset.annotationId);
    saveSymbolAnnotations(symbol, items);
    renderResearch();
    toast('Annotation removed');
  });
  $('#research-search-form')?.addEventListener('submit', (event) => {
    event.preventDefault();
    const query = $('#research-search-input')?.value.trim();
    if (query) document.dispatchEvent(new CustomEvent('ik:open-search', { detail: { query } }));
  });
  document.addEventListener('ik:market-updated', renderResearch);
  document.addEventListener('ik:symbol-updated', (event) => {
    if (event.detail?.symbol === state.research.symbol) renderResearch();
  });
  document.addEventListener('ik:assets-updated', () => {
    fillSymbolSelect(select, state.research.symbol);
    ensureDeep(state.research.symbol);
  });
  renderResearch();
  ensureDeep(state.research.symbol);
}

function exportSnapshot() {
  const symbol = state.research.symbol;
  const snapshot = {
    generatedAt: new Date().toISOString(),
    symbol,
    dataSource: {
      source: market.source,
      provider: market.provider,
      generatedAt: market.generatedAt,
      asOf: market.asOf,
      live: market.live,
    },
    quote: quotes[symbol],
    fundamentals: fundamentals[symbol],
    sec: secBySymbol[symbol] ?? null,
    news: news[symbol],
    newsSource: (news[symbol] ?? []).some((item) => item.live) ? 'yahoo-news' : 'synthetic',
    indicators: indicatorDetails(candleMap[symbol] ?? []),
    performance: performanceWindows(candleMap[symbol]),
    macro,
    quality: quality[symbol],
  };
  try {
    const blob = new Blob([JSON.stringify(snapshot, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = `investor-kit-${symbol}-research.json`;
    anchor.click();
    URL.revokeObjectURL(url);
    toast(`${symbol} research snapshot exported`);
  } catch {
    toast('Export is unavailable in this browser context');
  }
}

export function setResearchSymbol(symbol) {
  if (!assetsBySymbol[symbol]) return;
  state.research.symbol = symbol;
  const select = $('#research-symbol');
  if (select) select.value = symbol;
  renderResearch();
}

export function renderResearch() {
  const symbol = assetsBySymbol[state.research.symbol] ? state.research.symbol : 'SPY';
  state.research.symbol = symbol;
  const asset = assetsBySymbol[symbol];
  const quote = quotes[symbol];
  const candles = candleMap[symbol];
  const returns = returnsBySymbol[symbol];
  const yearReturns = returns.slice(-252);
  const metrics = analyzeReturns(yearReturns);
  const spyReturns = returnsBySymbol.SPY.slice(-252);
  const assetBeta = beta(yearReturns, spyReturns);
  const basics = fundamentals[symbol];
  const items = news[symbol] ?? [];
  const sentiment = sentimentSummary(items);
  const perf = Object.fromEntries(performanceWindows(candles).map((row) => [row.key, row.value]));
  const qualityRow = quality[symbol];
  const drawdown = drawdownSeriesFromCandles(candles.slice(-504));
  const maxDd = Math.min(...drawdown);
  const vol = historicalVolatility(candles, 21);
  const percentile = pricePercentile(candles, 252);

  $('#research-stats').innerHTML = [
    statCard('Last price', formatMoney(quote.price, 2), `${formatSignedPercent(quote.changePercent / 100)} today`, signClass(quote.changePercent)),
    statCard('1 month', formatSignedPercent(perf['1M'] ?? 0), '21 trading days', signClass(perf['1M'])),
    statCard('3 months', formatSignedPercent(perf['3M'] ?? 0), '63 trading days', signClass(perf['3M'])),
    statCard('1 year', formatSignedPercent(perf['1Y'] ?? 0), 'Total return', signClass(perf['1Y'])),
    statCard('Volatility · 21d', formatPercent(vol, 1), `Percentile ${Math.round(percentile * 100)} of 1Y`, vol > 0.35 ? 'warn' : ''),
    statCard('Sharpe · 1Y', formatNumber(metrics.sharpe), 'Risk-free 2%', signClass(metrics.sharpe)),
    statCard('Beta vs SPY', formatNumber(assetBeta), '252 daily returns', ''),
    statCard('Max drawdown · 1Y', formatPercent(metrics.maxDrawdown, 1), 'Peak to trough', 'neg'),
  ].join('');

  $('#research-rs-pill').textContent = `${symbol} / SPY`;
  $('#research-dd-pill').textContent = `${formatPercent(maxDd, 1)} max`;
  renderHorizons(perf);

  const spyCandles = candleMap.SPY;
  const aligned = Math.min(candles.length, spyCandles.length, 252);
  const assetSlice = candles.slice(-aligned);
  const spySlice = spyCandles.slice(-aligned);
  const ratio = assetSlice.map((candle, index) => candle.close / spySlice[index].close);
  const base = ratio[0] || 1;
  const relative = ratio.map((value) => (value / base) * 100);

  if (!relativeChart) {
    relativeChart = makeChart($('#research-relative-canvas'), {
      height: 220,
      yFormat: (value) => value.toFixed(0),
      xFormat: (label) => label,
      showLegend: true,
    });
  }
  relativeChart.setData({
    labels: assetSlice.map((candle) => dateShort(candle.date)),
    series: [
      { name: 'Relative', values: relative, color: '#2ee6c5', width: 2.1, area: true },
      { name: 'Baseline 100', values: relative.map(() => 100), color: '#64788f', width: 1, dashed: true, silent: true },
    ],
    yFormat: (value) => value.toFixed(0),
  });

  if (!drawdownChart) {
    drawdownChart = makeChart($('#research-drawdown-canvas'), {
      height: 220,
      yFormat: (value) => formatPercent(value, 0),
      xFormat: (label) => label,
    });
  }
  const drawdownSlice = drawdownSeries(candles.slice(-504).map((candle) => candle.close));
  drawdownChart.setData({
    labels: candles.slice(-drawdownSlice.length).map((candle) => dateShort(candle.date)),
    series: [
      { name: 'Drawdown', values: drawdownSlice, color: '#ff6b81', width: 1.8, area: true },
    ],
    yFormat: (value) => formatPercent(value, 0),
  });

  renderPriceAndTechnical(symbol, candles, quote, vol);
  renderFundamentals(symbol, basics, quote);
  renderMacro();
  renderCorrelation(symbol);
  renderNews(symbol, items, sentiment);
  renderSec(symbol);
  renderQuality(qualityRow, percentile, vol);
  ensureDeep(symbol);
}

function renderHorizons(perf) {
  const spyPerf = Object.fromEntries(performanceWindows(candleMap.SPY).map((row) => [row.key, row.value]));
  const keys = ['1D', '1W', '1M', '3M', '6M', '1Y', '2Y', 'YTD'];
  $('#research-horizon-pill').textContent = `${keys.length} horizons`;
  $('#research-horizons').innerHTML = keys.map((key) => {
    const value = perf[key] ?? 0;
    const spy = spyPerf[key] ?? 0;
    const excess = value - spy;
    return `<div class="horizon-cell">
      <header><span>${key}</span><span>vs SPY</span></header>
      <strong class="${signClass(value)}">${formatSignedPercent(value, 1)}</strong>
      <small class="${signClass(excess)}">${excess >= 0 ? '+' : '−'}${Math.abs(excess * 100).toFixed(2)} pp</small>
    </div>`;
  }).join('');
}

function renderFundamentals(symbol, basics, quote) {
  const asset = assetsBySymbol[symbol];
  const value = (input, formatter = formatNumber) => (
    input === null || input === undefined || !Number.isFinite(input) ? '—' : formatter(input)
  );
  const percent = (input) => value(input, (number) => formatPercent(number, 1));
  const peers = [
    ['Market cap', value(basics.marketCap, (number) => `$${formatCompact(number)}`)],
    ['Enterprise value', value(basics.enterpriseValue, (number) => `$${formatCompact(number)}`)],
    ['P/E (trailing)', value(basics.pe, (number) => formatNumber(number, 1))],
    ['Forward P/E', value(basics.forwardPE, (number) => formatNumber(number, 1))],
    ['Price / sales', value(basics.priceToSales, (number) => formatNumber(number, 1))],
    ['Price / book', value(basics.priceToBook, (number) => formatNumber(number, 1))],
    ['Revenue growth', percent(basics.revenueGrowth)],
    ['Earnings growth', percent(basics.earningsGrowth)],
    ['Gross margin', percent(basics.grossMargin)],
    ['Operating margin', percent(basics.operatingMargin)],
    ['Profit margin', percent(basics.profitMargin)],
    ['Return on equity', percent(basics.returnOnEquity)],
    ['Debt / equity', value(basics.debtToEquity, (number) => `${number.toFixed(2)}×`)],
    ['Current ratio', value(basics.currentRatio, (number) => number.toFixed(2))],
    ['Dividend yield', percent(basics.dividendYield)],
    ['Payout ratio', percent(basics.payoutRatio)],
    ['Beta', value(basics.beta, (number) => number.toFixed(2))],
    ['Expense ratio', value(basics.expenseRatio, (number) => `${number.toFixed(2)}%`)],
    ['Employees', value(basics.employees, (number) => formatCompact(number, 1))],
    ['Analyst target', `${formatMoney(basics.analystTarget, 2)} (${formatSignedPercent(basics.analystUpside, 1)})`],
  ];
  const rows = [];
  for (let index = 0; index < peers.length; index += 2) {
    const left = peers[index];
    const right = peers[index + 1] ?? ['', ''];
    rows.push(`<tr>
      <td class="muted">${left[0]}</td><td class="num">${left[1]}</td>
      <td class="muted">${right[0]}</td><td class="num">${right[1]}</td>
    </tr>`);
  }
  $('#research-fundamentals tbody').innerHTML = rows.join('');
  const sec = secBySymbol[symbol];
  $('#research-fund-note').textContent = `${asset.name} · ${asset.sector} · ${basics.kind.toUpperCase()} · synthetic fundamentals${sec ? ' · reported SEC facts below' : ''}`;
  $('#research-rating').textContent = `${basics.analystRating} · ${basics.analystCount} analysts`;
  $('#research-rating').className = `pill ${basics.analystUpside > 0 ? 'good' : 'bad'}`;
}

function renderSec(symbol) {
  const target = $('#research-sec-metrics tbody');
  if (!target) return;
  const sec = secBySymbol[symbol];
  const note = $('#research-sec-note');
  const pill = $('#research-sec-pill');
  const filingsTarget = $('#research-sec-filings');
  const annualTarget = $('#research-sec-annual tbody');
  if (!sec) {
    target.innerHTML = '<tr><td colspan="4" class="muted">No SEC facts loaded for this asset.</td></tr>';
    if (annualTarget) annualTarget.innerHTML = '';
    if (filingsTarget) filingsTarget.innerHTML = '';
    if (pill) {
      pill.textContent = deepLoading.has(symbol) ? 'Loading…' : live.enabled ? 'Not available' : 'Worker required';
      pill.className = 'pill warn';
    }
    if (note) {
      note.textContent = !live.enabled
        ? 'SEC EDGAR facts require the Cloudflare Worker deployment.'
        : deepLoading.has(symbol)
          ? 'Loading reported SEC company facts and recent filings…'
          : 'SEC EDGAR covers US-registered issuers. Indices, FX, futures, crypto and many non-US listings are out of scope.';
    }
    return;
  }
  const metrics = sec.metrics ?? {};
  const money = (value) => (Number.isFinite(value) ? `$${formatCompact(value)}` : '—');
  const pct = (value) => (Number.isFinite(value) ? formatPercent(value, 1) : '—');
  const num = (value, digits = 2) => (Number.isFinite(value) ? formatNumber(value, digits) : '—');
  const pairs = [
    ['Revenue', money(metrics.revenue)],
    ['Revenue growth', pct(metrics.revenueGrowth)],
    ['Net income', money(metrics.netIncome)],
    ['Net margin', pct(metrics.netMargin)],
    ['Operating cash flow', money(metrics.operatingCashFlow)],
    ['Free cash flow', money(metrics.freeCashFlow)],
    ['Total assets', money(metrics.assets)],
    ['Total liabilities', money(metrics.liabilities)],
    ['Shareholders equity', money(metrics.equity)],
    ['Cash & equivalents', money(metrics.cash)],
    ['EPS diluted', Number.isFinite(metrics.epsDiluted) ? formatMoney(metrics.epsDiluted, 2) : '—'],
    ['Book value / share', Number.isFinite(metrics.bookValuePerShare) ? formatMoney(metrics.bookValuePerShare, 2) : '—'],
    ['Debt / equity', Number.isFinite(metrics.debtToEquity) ? `${metrics.debtToEquity.toFixed(2)}×` : '—'],
    ['Current ratio', num(metrics.currentRatio)],
    ['Gross margin', pct(metrics.grossMargin)],
    ['R&D intensity', pct(metrics.rdIntensity)],
  ];
  const rows = [];
  for (let index = 0; index < pairs.length; index += 2) {
    const left = pairs[index];
    const right = pairs[index + 1] ?? ['', ''];
    rows.push(`<tr><td class="muted">${left[0]}</td><td class="num">${left[1]}</td><td class="muted">${right[0]}</td><td class="num">${right[1]}</td></tr>`);
  }
  target.innerHTML = rows.join('');

  if (annualTarget) {
    const dates = [...new Set([
      ...(sec.annual?.revenue ?? []).map((row) => row.end),
      ...(sec.annual?.netIncome ?? []).map((row) => row.end),
      ...(sec.annual?.epsDiluted ?? []).map((row) => row.end),
    ])].filter(Boolean).sort().slice(-5);
    const byDate = (series) => Object.fromEntries((series ?? []).map((row) => [row.end, row.value]));
    const revenue = byDate(sec.annual?.revenue);
    const netIncome = byDate(sec.annual?.netIncome);
    const eps = byDate(sec.annual?.epsDiluted);
    annualTarget.innerHTML = dates.length ? dates.map((date) => `<tr>
      <td>${escapeHtml(dateShort(date))}</td>
      <td class="num">${money(revenue[date])}</td>
      <td class="num">${money(netIncome[date])}</td>
      <td class="num">${Number.isFinite(eps[date]) ? formatMoney(eps[date], 2) : '—'}</td>
    </tr>`).join('') : '<tr><td colspan="4" class="muted">Annual series not reported for this issuer.</td></tr>';
  }

  if (filingsTarget) {
    filingsTarget.innerHTML = (sec.filings ?? []).slice(0, 8).map((filing) => {
      const label = `${filing.form} · ${filing.filingDate ?? '—'}`;
      const body = filing.url
        ? `<a href="${escapeHtml(filing.url)}" target="_blank" rel="noopener noreferrer">${escapeHtml(label)}</a>`
        : escapeHtml(label);
      return `<div class="filing-row"><span>${body}</span><small>${escapeHtml(filing.description || filing.reportDate || '')}</small></div>`;
    }).join('') || '<span class="muted small">No recent filings returned.</span>';
  }

  if (note) note.textContent = `${sec.entityName ?? symbol} · CIK ${sec.cik} · filed ${dateShort(sec.asOf)} · reported facts, not forecasts`;
  if (pill) {
    pill.textContent = metrics.revenue || metrics.assets ? 'SEC reported' : 'Filings only';
    pill.className = 'pill good';
  }
}

function renderPriceAndTechnical(symbol, candles, quote, vol) {
  renderPriceChart(symbol, candles, quote, vol);
  renderTechnical(symbol, quote);
}

function renderMacro() {
  $('#research-macro-regime').textContent = macro.regime;
  $('#research-macro-regime').className = `pill ${macro.regime === 'Risk-on' ? 'good' : macro.regime === 'Risk-off' ? 'bad' : 'warn'}`;
  const cells = [
    ['Risk-free', formatPercent(macro.riskFreeRate, 1), '3-month proxy'],
    ['10Y yield', formatPercent(macro.yield10y, 2), 'Government'],
    ['2Y yield', formatPercent(macro.yield2y, 2), 'Government'],
    ['Curve', formatPercent(macro.yieldCurve, 2), macro.yieldCurve < 0 ? 'Inverted' : 'Positive'],
    ['Inflation', formatPercent(macro.inflation, 1), 'Year over year'],
    ['GDP growth', formatPercent(macro.gdpGrowth, 1), 'Real, annualized'],
    ['Unemployment', formatPercent(macro.unemployment, 1), 'Labor market'],
    ['VIX proxy', formatNumber(macro.vix, 1), macro.vix > 25 ? 'Elevated' : 'Contained'],
    ['Dollar index', formatNumber(macro.dollarIndex, 1), 'Trade-weighted'],
    ['Oil', formatMoney(macro.oil, 2), 'WTI proxy'],
    ['Credit spread', formatPercent(macro.creditSpread / 100, 2), 'High yield'],
    ['Breadth', formatPercent(macro.breadth, 0), 'Advancing issues'],
  ];
  $('#research-macro').innerHTML = cells.map(([label, value, note]) => `
    <div class="macro-cell">
      <span>${escapeHtml(label)}</span>
      <strong>${value}</strong>
      <small>${escapeHtml(note)}</small>
    </div>
  `).join('');
}

function renderCorrelation(symbol) {
  const symbols = [symbol, ...PEERS.filter((peer) => peer !== symbol)].slice(0, 7);
  const series = symbols.map((key) => returnsBySymbol[key].slice(-252));
  const matrix = correlationMatrix(
    Object.fromEntries(symbols.map((key, index) => [key, series[index]])),
    symbols,
  );
  const header = `<tr><th scope="col">Asset</th>${symbols.map((key) => `<th scope="col">${key}</th>`).join('')}</tr>`;
  const rows = symbols.map((rowSymbol, row) => `<tr>
    <td>${rowSymbol}</td>
    ${symbols.map((_, column) => {
      const value = matrix[row][column];
      const strength = Math.min(0.52, Math.abs(value) * 0.52);
      const color = value >= 0 ? `rgba(46, 230, 197, ${strength})` : `rgba(255, 107, 129, ${strength})`;
      return `<td style="background:${color}">${value.toFixed(2)}</td>`;
    }).join('')}
  </tr>`).join('');
  $('#research-correlation thead').innerHTML = header;
  $('#research-correlation tbody').innerHTML = rows;
}

function renderNews(symbol, items, sentiment) {
  const badge = $('#research-sentiment');
  badge.textContent = `${sentiment.label} ${sentiment.score >= 0 ? '+' : ''}${sentiment.score.toFixed(2)}`;
  badge.className = `pill ${sentiment.score > 0.2 ? 'good' : sentiment.score < -0.2 ? 'bad' : ''}`;
  const liveNews = items.some((item) => item.live);
  $('#research-news-note').textContent = `${items.length} ${liveNews ? 'live Yahoo Finance' : 'synthetic local'} headlines · ${sentiment.positive} positive / ${sentiment.negative} negative`;
  $('#research-news').innerHTML = items.map((item) => {
    const color = item.sentiment > 0.15 ? 'var(--good)' : item.sentiment < -0.15 ? 'var(--danger)' : 'var(--faint)';
    const headline = item.url
      ? `<a href="${escapeHtml(item.url)}" target="_blank" rel="noopener noreferrer">${escapeHtml(item.headline)}</a>`
      : escapeHtml(item.headline);
    return `<div class="news-item">
      <header>
        <span class="news-meta">${escapeHtml(item.category)} · ${escapeHtml(item.source)}${item.live ? ' · live' : ''}</span>
        <span class="news-meta">${dateShort(item.date)}</span>
      </header>
      <div class="news-headline"><span class="sentiment-dot" style="display:inline-block;background:${color};margin-right:6px"></span>${headline}</div>
      <div class="news-meta">Sentiment ${item.sentiment >= 0 ? '+' : ''}${item.sentiment.toFixed(2)} · impact ${escapeHtml(item.impact)} · ${symbol}</div>
    </div>`;
  }).join('');
}

function renderQuality(row, percentile, vol) {
  const cell = (label, value) => `<div class="quality-cell"><span>${escapeHtml(label)}</span><strong>${value}</strong></div>`;
  $('#research-quality').innerHTML = [
    cell('Bars loaded', formatNumber(row.rows, 0)),
    cell('History span', `${row.spanYears.toFixed(2)} yrs`),
    cell('First bar', dateShort(row.first)),
    cell('Last bar', dateShort(row.last)),
    cell('Completeness', formatPercent(row.completeness, 1)),
    cell('Missing fields', formatNumber(row.missing, 0)),
    cell('Duplicates', formatNumber(row.duplicates, 0)),
    cell('Calendar gaps', formatNumber(row.gaps, 0)),
    cell('Bars / year', formatNumber(row.barsPerYear, 0)),
    cell('Price percentile', `${Math.round(percentile * 100)}%`),
    cell('Realized vol', formatPercent(vol, 1)),
    cell('Source', row.synthetic ? 'Synthetic · local' : sourceLabel(sources[state.research.symbol] ?? 'server')),
    cell('SEC facts', secBySymbol[state.research.symbol] ? 'Reported' : 'Not available'),
    cell('Headlines', (news[state.research.symbol] ?? []).some((item) => item.live) ? 'Live' : 'Synthetic'),
  ].join('');
}
