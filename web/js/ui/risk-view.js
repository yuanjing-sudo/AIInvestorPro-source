// Risk lab: allocation inputs, Monte Carlo fan chart and stress scenarios.

import {
  UNIVERSE, assetsBySymbol, returnsBySymbol, state, $, escapeHtml,
  formatMoneyCompact, formatPercent, formatMoney, makeChart, statCard,
  aggregatePortfolio, signClass,
} from './shared.js';
import { monteCarlo, stressTests, portfolioRisk } from '../core/risk.js';

let mcChart = null;

export function initRisk() {
  $('#risk-form').addEventListener('submit', (event) => {
    event.preventDefault();
    runRisk();
  });
  $('#risk-weights tbody').addEventListener('input', (event) => {
    const input = event.target.closest('input[data-risk-weight]');
    if (!input) return;
    const symbol = input.dataset.riskWeight;
    state.risk.weights[symbol] = Math.max(0, Number(input.value) || 0);
    state.risk.result = null;
    state.risk.stress = null;
    const results = $('#risk-results');
    if (results) results.hidden = true;
    updateContributions();
  });
  renderRiskWeights();
  if (state.risk.result) renderRiskResult();
  document.addEventListener('ik:market-updated', () => {
    state.risk.result = null;
    state.risk.stress = null;
    const results = $('#risk-results');
    if (results) results.hidden = true;
    renderRiskWeights();
  });
}

export function setAllocation(symbols, weightsPercent) {
  state.risk.symbols = [...symbols];
  state.risk.weights = {};
  symbols.forEach((symbol, index) => {
    state.risk.weights[symbol] = Math.max(0, weightsPercent[index] ?? 0);
  });
  state.risk.result = null;
  state.risk.stress = null;
  const results = $('#risk-results');
  if (results) results.hidden = true;
  renderRiskWeights();
}

function normalizedWeights() {
  const raw = state.risk.symbols.map((symbol) => Math.max(0, Number(state.risk.weights[symbol]) || 0));
  const total = raw.reduce((acc, value) => acc + value, 0);
  if (total <= 0) return raw.map(() => 1 / Math.max(1, raw.length));
  return raw.map((value) => value / total);
}

function riskSnapshot() {
  const symbols = state.risk.symbols;
  const weights = normalizedWeights();
  const risk = portfolioRisk(symbols, weights, returnsBySymbol);
  return { symbols, weights, risk };
}

export function renderRiskWeights() {
  const tbody = $('#risk-weights tbody');
  if (!tbody) return;
  const { symbols, weights, risk } = riskSnapshot();
  const contributions = Object.fromEntries(
    risk.contributions.map((entry) => [entry.symbol, entry]),
  );
  tbody.innerHTML = symbols.map((symbol, index) => {
    const entry = contributions[symbol];
    return `<tr>
      <td><span class="symbol">${symbol}</span><span class="sub">${escapeHtml(assetsBySymbol[symbol]?.sector ?? '')}</span></td>
      <td><input type="number" min="0" max="100" step="0.1" value="${(state.risk.weights[symbol] ?? 0).toFixed(1)}" data-risk-weight="${symbol}" inputmode="decimal" aria-label="${symbol} weight percent"></td>
      <td class="num" data-risk-vol="${symbol}">${formatPercent(entry?.volatility ?? 0, 1)}</td>
      <td class="num" data-risk-contribution="${symbol}">${formatPercent(entry?.contribution ?? 0, 1)}</td>
    </tr>`;
  }).join('');
}

function updateContributions() {
  const { symbols, risk } = riskSnapshot();
  const contributions = Object.fromEntries(
    risk.contributions.map((entry) => [entry.symbol, entry]),
  );
  for (const symbol of symbols) {
    const contribution = document.querySelector(`[data-risk-contribution="${symbol}"]`);
    if (contribution) contribution.textContent = formatPercent(contributions[symbol]?.contribution ?? 0, 1);
    const vol = document.querySelector(`[data-risk-vol="${symbol}"]`);
    if (vol) vol.textContent = formatPercent(contributions[symbol]?.volatility ?? 0, 1);
  }
}

function runRisk() {
  const { symbols, weights } = riskSnapshot();
  if (symbols.length < 2) {
    window.alert('Select at least two assets for a portfolio simulation.');
    return;
  }
  const horizonDays = Math.min(1260, Math.max(5, Math.round(Number($('#risk-horizon').value) || 63)));
  const simulations = Math.min(20000, Math.max(200, Math.round(Number($('#risk-sims').value) || 2000)));
  const seed = Math.max(0, Math.round(Number($('#risk-seed').value) || 7));
  const initialValue = aggregatePortfolio().total > 0 ? aggregatePortfolio().total : 100000;

  const result = monteCarlo(symbols, weights, returnsBySymbol, {
    simulations, horizonDays, initialValue, seed,
  });
  if (!result) {
    window.alert('The covariance matrix is singular for this allocation. Choose different assets.');
    return;
  }
  const stress = stressTests(symbols, weights, assetsBySymbol);
  state.risk.result = result;
  state.risk.stress = stress;
  renderRiskResult();
  $('#risk-results').scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function renderRiskResult() {
  const result = state.risk.result;
  if (!result) return;
  $('#risk-results').hidden = false;

  $('#risk-stats').innerHTML = [
    statCard('Median outcome', formatMoney(result.median), `${result.horizonDays} trading days`),
    statCard('5th percentile', formatMoney(result.p5), 'Downside scenario', 'neg'),
    statCard('95th percentile', formatMoney(result.p95), 'Upside scenario', 'pos'),
    statCard('Probability of loss', formatPercent(result.probabilityOfLoss, 1), `${result.simulations.toLocaleString()} paths`),
    statCard('VaR 95', formatMoney(result.var95), 'Value at risk, 95%'),
    statCard('CVaR 95', formatMoney(result.cvar95), 'Expected shortfall'),
    statCard('Expected return', formatPercent(result.expectedReturn, 1), 'Mean simulated outcome', signClass(result.expectedReturn)),
    statCard('Start value', formatMoney(result.initialValue), 'Current portfolio value'),
  ].join('');

  if (!mcChart) {
    mcChart = makeChart($('#mc-canvas'), {
      height: 300,
      yFormat: (value) => formatMoneyCompact(value),
      xFormat: (label) => `Day ${label}`,
    });
  }
  const bands = result.bands;
  const labels = bands.map((point) => point.day);
  const series = [
    {
      name: '5–25%',
      band: [bands.map((point) => point.p5), bands.map((point) => point.p25)],
      color: '#2dd4bf',
      opacity: 0.10,
    },
    {
      name: '25–75%',
      band: [bands.map((point) => point.p25), bands.map((point) => point.p75)],
      color: '#2dd4bf',
      opacity: 0.18,
    },
    {
      name: '75–95%',
      band: [bands.map((point) => point.p75), bands.map((point) => point.p95)],
      color: '#2dd4bf',
      opacity: 0.10,
    },
    ...result.samplePaths.slice(0, 10).map((path, index) => ({
      name: `Sample ${index + 1}`,
      values: path,
      color: '#38bdf8',
      width: 1,
      opacity: 0.10,
    })),
    {
      name: 'Median',
      values: bands.map((point) => point.median),
      color: '#2dd4bf',
      width: 2.5,
    },
  ];
  mcChart.setData({
    labels,
    series,
    yFormat: (value) => formatMoneyCompact(value),
    xFormat: (label) => `Day ${label}`,
  });

  const { symbols, weights, risk } = riskSnapshot();
  const ranked = risk.contributions
    .map((entry, index) => ({ ...entry, weight: weights[index] }))
    .sort((a, b) => b.contribution - a.contribution);
  $('#risk-bars').innerHTML = ranked.map((entry) => `<div class="bar-row">
    <span class="symbol">${entry.symbol}</span>
    <div class="bar-track"><div class="bar-fill risk" style="width:${Math.max(0, Math.min(100, entry.contribution * 100)).toFixed(2)}%"></div></div>
    <span class="bar-value">${formatPercent(entry.contribution, 1)}</span>
  </div>`).join('');

  $('#stress-table tbody').innerHTML = state.risk.stress.map((test) => {
    const largest = [...test.byAsset].sort((a, b) => a.weighted - b.weighted)[0];
    return `<tr>
      <td><strong>${escapeHtml(test.scenario.name)}</strong><span class="sub">${escapeHtml(test.scenario.description)}</span></td>
      <td class="num ${test.portfolioShock >= 0 ? 'pos' : 'neg'}">${formatPercent(test.portfolioShock, 1)}</td>
      <td class="num ${test.portfolioShock >= 0 ? 'pos' : 'neg'}">${result.initialValue ? formatMoney(test.portfolioShock * result.initialValue) : '—'}</td>
      <td>${largest ? `${largest.symbol} <span class="muted">${formatPercent(largest.weighted, 1)}</span>` : '—'}</td>
    </tr>`;
  }).join('');
}
