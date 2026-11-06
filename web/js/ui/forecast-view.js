// Forecast studio: transparent ensemble forecasts with simulation intervals,
// walk-forward diagnostics, scenario analysis and feature attribution.

import {
  UNIVERSE, candleMap, quotes, quality, fundamentals, news, macro, state, $,
  escapeHtml, dateShort, formatMoney, formatMoneyCompact, formatPercent,
  formatSignedPercent, formatNumber, signClass, makeChart, statCard, toast,
} from './shared.js';
import { buildForecast } from '../core/forecast.js';
import { sentimentSummary } from '../core/marketdata.js';

let forecastChart = null;
let lastForecast = null;

export function initForecast() {
  const select = $('#fc-symbol');
  const form = $('#forecast-form');
  if (!select || !form) return;
  select.innerHTML = UNIVERSE
    .map((asset) => `<option value="${asset.symbol}">${asset.symbol} · ${escapeHtml(asset.name)}</option>`)
    .join('');
  select.value = state.forecast.symbol;
  $('#fc-horizon').value = String(state.forecast.horizon);
  $('#fc-mode').value = state.forecast.mode;
  $('#fc-sims').value = String(state.forecast.simulations);
  $('#fc-seed').value = String(state.forecast.seed);
  $('#fc-history').value = String(state.forecast.history);

  form.addEventListener('submit', (event) => {
    event.preventDefault();
    runForecast({ announce: true });
  });
  select.addEventListener('change', () => runForecast());
  renderForecast(lastForecast);
  runForecast();
}

export function runForecast(options = {}) {
  const button = $('#forecast-form button[type="submit"]');
  const symbol = $('#fc-symbol').value;
  const horizon = Number($('#fc-horizon').value) || 21;
  const mode = $('#fc-mode').value;
  const simulations = Number($('#fc-sims').value) || 2000;
  const seed = Number($('#fc-seed').value) || 7;
  const history = Number($('#fc-history').value) || 180;
  state.forecast = { symbol, horizon, mode, simulations, seed, history };
  $('#fc-readiness').textContent = 'Computing…';
  $('#fc-readiness').className = 'pill warn';
  button?.classList.add('is-busy');
  window.setTimeout(() => {
    try {
      const result = buildForecast(candleMap[symbol], {
        symbol, horizon, mode, simulations, seed, history,
        context: {
          fundamentals: fundamentals[symbol],
          macro,
          sentiment: sentimentSummary(news[symbol] ?? []),
        },
      });
      lastForecast = result;
      if (!result) throw new Error('Not enough history for this asset.');
      renderForecast(result);
      $('#fc-readiness').textContent = 'Forecast ready';
      $('#fc-readiness').className = 'pill good';
      if (options.announce) toast(`${symbol} forecast updated · ${horizon} trading days`);
    } catch (error) {
      $('#fc-readiness').textContent = 'Model error';
      $('#fc-readiness').className = 'pill bad';
      toast(error?.message ?? 'Forecast failed');
    } finally {
      button?.classList.remove('is-busy');
    }
  }, 20);
}

function renderForecast(forecast) {
  if (!forecast) return;
  $('#forecast-results').hidden = false;
  const { symbol, horizon, start, expectedPrice, expectedReturn, probabilityUp, targetPrice, var95, confidence, regime } = forecast;
  const quote = quotes[symbol];
  const qualityRow = quality[symbol];
  const direction = expectedReturn >= 0;
  const confidenceTone = confidence >= 65 ? 'good' : confidence >= 45 ? 'warn' : 'bad';

  $('#fc-stats').innerHTML = [
    statCard('Expected price', formatMoney(expectedPrice, 2), `${formatSignedPercent(expectedReturn, 1)} over ${horizon}d`, signClass(expectedReturn)),
    statCard('Median target', formatMoney(targetPrice, 2), `From ${formatMoney(start, 2)}`, signClass(targetPrice - start)),
    statCard('Probability up', formatPercent(probabilityUp, 0), direction ? 'Model leans positive' : 'Model leans negative', direction ? 'pos' : 'neg'),
    statCard('95% downside', formatMoney(var95, 0), 'Value at risk · terminal', 'neg'),
    statCard('Model confidence', `${Math.round(confidence)}/100`, confidence >= 65 ? 'Strong evidence' : confidence >= 45 ? 'Moderate evidence' : 'Low evidence', confidenceTone),
    statCard('Realized volatility', formatPercent(forecast.annualVolatility, 1), 'Annualized · 1 year', forecast.annualVolatility > 0.35 ? 'warn' : ''),
    statCard('Regime', regime.label, `Vol ratio ${formatNumber(regime.metrics.volRatio, 2)}×`, regime.tone),
    statCard('Data coverage', `${formatNumber(forecast.dataRows, 0)} bars`, `${qualityRow.spanYears.toFixed(1)} years · synthetic`, ''),
  ].join('');

  $('#fc-chart-title').textContent = `${symbol} · ${horizon}-day forecast cone`;
  $('#fc-chart-subtitle').textContent = `History ${forecast.historyLength} bars · ${forecast.simulation.simulations.toLocaleString()} simulated paths · ${forecast.mode === 'ensemble' ? 'walk-forward ensemble' : forecast.mode}`;

  renderChart(forecast);
  renderBandLegend();
  renderRegime(forecast);
  renderScenarios(forecast);
  renderDistribution(forecast.distribution, start);
  renderModels(forecast);
  renderDiagnostics(forecast);
  renderFeatures(forecast);
  renderData(forecast, qualityRow, quote);
}

function renderChart(forecast) {
  if (!forecastChart) {
    forecastChart = makeChart($('#fc-chart'), {
      height: 340,
      padding: { left: 62, right: 20, top: 36, bottom: 34 },
      yFormat: (value) => formatMoneyCompact(value),
      xFormat: (label) => (label instanceof Date ? dateShort(label) : String(label)),
      showLegend: true,
    });
  }
  const labels = forecast.labels;
  const bands = [...forecast.bands].reverse(); // 95, 80, 50 broad to narrow
  const colors = { 95: '#4cc9ff', 80: '#2ee6c5', 50: '#8b7cff' };
  const gap = forecast.historyLength - 1;
  const samples = forecast.samplePaths.slice(0, 7).map((path, index) => ({
    name: `Path ${index + 1}`,
    values: path,
    color: index % 2 ? '#4cc9ff' : '#2ee6c5',
    width: 0.7,
    opacity: 0.16,
    silent: true,
  }));
  forecastChart.setData({
    labels,
    markers: [{ index: gap, label: 'TODAY', color: '#ffc857' }],
    series: [
      ...samples,
      ...bands.map((band) => ({
        name: `${band.level}% interval`,
        band: [band.lower, band.upper],
        color: colors[band.level],
        opacity: band.level === 95 ? 0.10 : band.level === 80 ? 0.14 : 0.20,
        silent: true,
      })),
      { name: 'History', values: forecast.history.map((candle) => candle.close), color: '#e9f0fb', width: 1.6 },
      { name: 'Median', values: forecast.median, color: '#2ee6c5', width: 2.4, dashed: true },
    ],
    yFormat: (value) => formatMoneyCompact(value),
  });
}

function renderBandLegend() {
  const chips = [
    ['95% interval', 'rgba(76, 201, 255, .32)'],
    ['80% interval', 'rgba(46, 230, 197, .36)'],
    ['50% interval', 'rgba(139, 124, 255, .46)'],
    ['Median', '#2ee6c5'],
    ['History', '#e9f0fb'],
  ];
  $('#fc-band-legend').innerHTML = chips.map(([label, color]) => `
    <span class="legend-chip"><span class="legend-swatch" style="background:${color}"></span>${label}</span>
  `).join('');
}

function renderRegime(forecast) {
  const regime = forecast.regime;
  const metrics = regime.metrics;
  const meter = Math.round(Math.min(100, Math.max(0, (1 - Math.min(1, metrics.volRatio / 2)) * 100)));
  $('#fc-regime').innerHTML = `
    <div class="regime-card">
      <span class="regime-badge ${regime.tone}">${escapeHtml(regime.label)}</span>
      <p class="muted small">${escapeHtml(regime.description)}</p>
      <div class="regime-meter"><span style="width:${meter}%"></span></div>
      <div class="metric-grid">
        <div class="metric-cell"><span>20d vol</span><strong>${formatPercent(metrics.vol20, 1)}</strong></div>
        <div class="metric-cell"><span>Vol ratio</span><strong>${formatNumber(metrics.volRatio, 2)}×</strong></div>
        <div class="metric-cell"><span>Drawdown</span><strong>${formatPercent(metrics.drawdown, 1)}</strong></div>
        <div class="metric-cell"><span>RSI</span><strong>${formatNumber(metrics.rsi, 1)}</strong></div>
      </div>
    </div>`;
}

function renderScenarios(forecast) {
  const tone = { bear: 'neg', base: '', bull: 'pos' };
  $('#fc-scenarios').innerHTML = forecast.scenarios.map((scenario) => `
    <div class="scenario-row">
      <div><strong class="${tone[scenario.key]}">${scenario.label}</strong><small>${scenario.key === 'bear' ? '10th percentile' : scenario.key === 'base' ? 'Median outcome' : '90th percentile'}</small></div>
      <div class="scenario-price">${formatMoney(scenario.price, 2)}</div>
      <div class="${signClass(scenario.return)}">${formatSignedPercent(scenario.return, 1)}</div>
    </div>
  `).join('');
}

function renderDistribution(distribution, start) {
  const canvas = $('#fc-distribution');
  if (!canvas || !distribution.length) return;
  const wrapper = canvas.parentElement;
  const width = Math.max(180, wrapper?.clientWidth || 320);
  const height = 180;
  const dpr = window.devicePixelRatio || 1;
  canvas.width = Math.round(width * dpr);
  canvas.height = Math.round(height * dpr);
  canvas.style.height = `${height}px`;
  const ctx = canvas.getContext('2d');
  if (!ctx) return;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, width, height);
  const styles = getComputedStyle(canvas);
  const text = styles.getPropertyValue('--chart-text').trim() || '#93a7c2';
  const grid = styles.getPropertyValue('--chart-grid').trim() || 'rgba(148,163,184,.13)';
  const accent = styles.getPropertyValue('--accent').trim() || '#2ee6c5';
  const danger = styles.getPropertyValue('--danger').trim() || '#ff6b81';
  const maxCount = Math.max(...distribution.map((bin) => bin.count));
  const pad = { left: 8, right: 8, top: 12, bottom: 26 };
  const plotWidth = width - pad.left - pad.right;
  const plotHeight = height - pad.top - pad.bottom;
  const barWidth = plotWidth / distribution.length;
  for (const [index, bin] of distribution.entries()) {
    const barHeight = maxCount > 0 ? (bin.count / maxCount) * plotHeight : 0;
    const x = pad.left + index * barWidth + 1;
    const y = pad.top + plotHeight - barHeight;
    ctx.fillStyle = (bin.low + bin.high) / 2 >= start ? `${accent}bb` : `${danger}bb`;
    ctx.fillRect(x, y, Math.max(1, barWidth - 2), barHeight);
  }
  ctx.strokeStyle = grid;
  ctx.beginPath();
  ctx.moveTo(pad.left, pad.top + plotHeight);
  ctx.lineTo(width - pad.right, pad.top + plotHeight);
  ctx.stroke();
  ctx.fillStyle = text;
  ctx.font = '10px ui-monospace, SFMono-Regular, Menlo, monospace';
  ctx.textAlign = 'left';
  ctx.textBaseline = 'top';
  ctx.fillText(formatMoneyCompact(distribution[0].low), pad.left, height - pad.bottom + 7);
  ctx.textAlign = 'right';
  ctx.fillText(formatMoneyCompact(distribution[distribution.length - 1].high), width - pad.right, height - pad.bottom + 7);
  ctx.textAlign = 'center';
  ctx.fillText('Start', pad.left + (width - pad.left - pad.right) / 2, pad.top);
  ctx.strokeStyle = text;
  ctx.setLineDash([3, 3]);
  const startRatio = (start - distribution[0].low) / Math.max(1e-9, distribution[distribution.length - 1].high - distribution[0].low);
  const startX = pad.left + Math.min(1, Math.max(0, startRatio)) * plotWidth;
  ctx.beginPath();
  ctx.moveTo(startX, pad.top);
  ctx.lineTo(startX, pad.top + plotHeight);
  ctx.stroke();
  ctx.setLineDash([]);
}

function renderModels(forecast) {
  $('#fc-models').innerHTML = forecast.models.map((model) => {
    const active = model.selected;
    return `<div class="model-row ${active ? '' : 'is-muted'}">
      <header>
        <span class="model-name">${escapeHtml(model.label)}</span>
        <span class="model-weight">${(model.weight * 100).toFixed(1)}% weight</span>
      </header>
      <span class="model-stat">Expected ${formatSignedPercent(model.expectedReturn, 1)} · error ${(model.error * 100).toFixed(1)}%</span>
      <span class="model-stat">${active ? 'Active' : 'Inactive'} · vol ${formatPercent(model.annualVolatility, 1)}</span>
      <div class="model-bar"><span style="width:${Math.max(3, model.weight * 100)}%"></span></div>
    </div>`;
  }).join('');
}

function renderDiagnostics(forecast) {
  const diag = forecast.diagnostics;
  const skill = diag.skill;
  $('#fc-skill').textContent = `${skill >= 0 ? '+' : ''}${(skill * 100).toFixed(1)}% skill`;
  $('#fc-skill').className = `pill ${skill > 0.02 ? 'good' : skill < -0.02 ? 'bad' : 'warn'}`;
  const cell = (label, value, note = '') => `<div class="metric-cell"><span>${label}</span><strong>${value}</strong>${note ? `<small>${note}</small>` : ''}</div>`;
  $('#fc-diagnostics').innerHTML = [
    cell('Directional', formatPercent(diag.directionalAccuracy, 1), 'Walk-forward'),
    cell('MAE', `${(diag.mae * 100).toFixed(2)}%`, 'Log-return units'),
    cell('RMSE', `${(diag.rmse * 100).toFixed(2)}%`, 'Log-return units'),
    cell('R²', formatNumber(diag.r2, 3), 'Out-of-sample'),
    cell('Baseline', `${(diag.baselineRmse * 100).toFixed(2)}%`, 'Naive MAE'),
    cell('Observations', formatNumber(diag.observations, 0), 'Holdout folds'),
    cell('1-step MAE', `${(diag.oneStepMae * 100).toFixed(2)}%`, 'Model blend'),
    cell('Confidence', `${Math.round(forecast.confidence)}/100`, 'Composite'),
  ].join('');
}

function renderFeatures(forecast) {
  const contributions = forecast.factorContributions.slice(0, 9);
  const max = Math.max(1e-9, ...contributions.map((row) => Math.abs(row.contribution)));
  $('#fc-features').innerHTML = contributions.map((row) => {
    const width = Math.max(3, (Math.abs(row.contribution) / max) * 100);
    const positive = row.contribution >= 0;
    return `<div class="bar-row">
      <span title="${escapeHtml(row.label)}">${escapeHtml(row.label)}</span>
      <span class="bar-track"><span class="bar-fill ${positive ? 'pos' : 'neg'}" style="width:${width}%"></span></span>
      <span class="bar-value ${positive ? 'pos' : 'neg'}">${(row.contribution * 10000).toFixed(2)} bps</span>
    </div>`;
  }).join('') || '<p class="empty-state">Feature attribution is not available for this window.</p>';
}

function renderData(forecast, qualityRow, quote) {
  $('#fc-data-pill').textContent = `${qualityRow.rows} row dataset`;
  const cell = (label, value) => `<div class="metric-cell"><span>${label}</span><strong>${value}</strong></div>`;
  $('#fc-data').innerHTML = [
    cell('Bars', formatNumber(qualityRow.rows, 0)),
    cell('Span', `${qualityRow.spanYears.toFixed(2)} yrs`),
    cell('Completeness', formatPercent(qualityRow.completeness, 1)),
    cell('Gaps', formatNumber(qualityRow.gaps, 0)),
    cell('Duplicates', formatNumber(qualityRow.duplicates, 0)),
    cell('Last close', formatMoney(quote.price, 2)),
    cell('History used', `${forecast.historyLength} bars`),
    cell('First bar', dateShort(qualityRow.first)),
    cell('Context tilt', `${(forecast.contextTilt * 10000).toFixed(1)} bps`),
    cell('Context lines', forecast.contextUsed ? `${forecast.contextBreakdown.length} active` : 'price only'),
  ].join('');
}
