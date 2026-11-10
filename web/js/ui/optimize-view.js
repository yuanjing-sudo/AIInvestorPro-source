// Constrained optimizer UI and efficient-frontier chart.

import {
  UNIVERSE, returnsBySymbol, state, $, escapeHtml, formatPercent,
  formatNumber, makeChart, statCard,
} from './shared.js';
import { optimize, efficientFrontier } from '../core/optimizer.js';
import { setAllocation } from './risk-view.js';

let frontierChart = null;

function renderOptimizeAssets() {
  const grid = $('#optimize-assets');
  if (!grid) return;
  const available = new Set(UNIVERSE.map((asset) => asset.symbol));
  state.optimize.selected = state.optimize.selected.filter((symbol) => available.has(symbol));
  grid.innerHTML = UNIVERSE.map((asset) => `<label class="checkbox-chip">
    <input type="checkbox" value="${asset.symbol}" ${state.optimize.selected.includes(asset.symbol) ? 'checked' : ''}>
    <span><strong>${asset.symbol}</strong> <span class="muted">${escapeHtml(asset.sector)}</span></span>
  </label>`).join('');
}

export function initOptimize() {
  const grid = $('#optimize-assets');
  renderOptimizeAssets();

  grid.addEventListener('change', () => {
    state.optimize.selected = [...grid.querySelectorAll('input:checked')].map((input) => input.value);
    if (state.optimize.result) {
      state.optimize.result = null;
      state.optimize.frontier = null;
      $('#optimize-results').hidden = true;
    }
  });

  const cap = $('#opt-cap');
  const updateCapLabel = () => { $('#opt-cap-label').textContent = `${cap.value}%`; };
  cap.addEventListener('input', updateCapLabel);
  updateCapLabel();

  $('#optimize-form').addEventListener('submit', (event) => {
    event.preventDefault();
    runOptimizer();
  });

  if (state.optimize.result) renderOptimizeResult();
  document.addEventListener('ik:assets-updated', renderOptimizeAssets);
}

function runOptimizer() {
  const symbols = [...$('#optimize-assets').querySelectorAll('input:checked')].map((input) => input.value);
  if (symbols.length < 2) {
    window.alert('Select at least two assets to optimize.');
    return;
  }
  const maxWeight = Math.max(0.1, Number($('#opt-cap').value) / 100);
  const riskFree = Math.max(0, Number($('#opt-riskfree').value) || 0) / 100;
  const objective = $('#opt-objective').value;

  const result = optimize(symbols, returnsBySymbol, { objective, maxWeight, riskFree });
  const frontier = efficientFrontier(symbols, returnsBySymbol, { points: 14, maxWeight });
  state.optimize = { selected: symbols, result, frontier };
  setAllocation(symbols, result.weights.map((weight) => weight * 100));
  renderOptimizeResult();
  $('#optimize-results').scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function renderOptimizeResult() {
  const { result, frontier } = state.optimize;
  if (!result) return;
  $('#optimize-results').hidden = false;

  $('#opt-stats').innerHTML = [
    statCard('Expected return', formatPercent(result.expectedReturn, 1), 'Annualized, historical sample'),
    statCard('Volatility', formatPercent(result.volatility, 1), 'Annualized'),
    statCard('Sharpe ratio', formatNumber(result.sharpe), `Risk-free ${formatPercent(result.riskFree, 1)}`),
    statCard('Diversification', formatNumber(result.diversificationRatio), 'Weighted vol / portfolio vol'),
    statCard('Effective assets', formatNumber(result.effectiveN, 1), '1 / sum of squared weights'),
    statCard('Max weight', formatPercent(result.maxWeight, 0), 'Constraint'),
  ].join('');

  const contributions = Object.fromEntries(
    result.contributions.map((entry) => [entry.symbol, entry.contribution]),
  );
  const ordered = result.symbols
    .map((symbol, index) => ({ symbol, weight: result.weights[index], contribution: contributions[symbol] ?? 0 }))
    .sort((a, b) => b.weight - a.weight);

  $('#opt-weights tbody').innerHTML = ordered.map((row) => `<tr>
    <td><span class="symbol">${row.symbol}</span></td>
    <td class="num">${formatPercent(row.weight, 1)}</td>
    <td class="num">${formatPercent(row.contribution, 1)}</td>
  </tr>`).join('');

  $('#opt-bars').innerHTML = ordered.map((row) => `<div class="bar-row">
    <span class="symbol">${row.symbol}</span>
    <div class="bar-track"><div class="bar-fill" style="width:${Math.min(100, Math.max(0, row.weight * 100)).toFixed(2)}%"></div></div>
    <span class="bar-value">${formatPercent(row.weight, 1)}</span>
  </div>`).join('');

  if (!frontierChart) {
    frontierChart = makeChart($('#frontier-canvas'), {
      height: 280,
      yFormat: (value) => formatPercent(value, 1),
      xFormat: (label) => `vol ${label}`,
    });
  }
  const labels = frontier.map((point) => formatPercent(point.volatility, 1));
  let nearest = 0;
  let bestDistance = Infinity;
  frontier.forEach((point, index) => {
    const distance = Math.abs(point.volatility - result.volatility);
    if (distance < bestDistance) { bestDistance = distance; nearest = index; }
  });
  const current = new Array(frontier.length).fill(null);
  current[nearest] = result.expectedReturn;

  frontierChart.setData({
    labels,
    series: [
      { name: 'Efficient frontier', values: frontier.map((point) => point.expectedReturn), color: '#38bdf8', width: 2.2 },
      { name: 'Current mix', values: current, color: '#2dd4bf', points: true, pointRadius: 6 },
    ],
    yFormat: (value) => formatPercent(value, 1),
    xFormat: (label) => `vol ${label}`,
  });
}
