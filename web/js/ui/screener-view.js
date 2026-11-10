// Screener filters and result table.

import {
  UNIVERSE, candleMap, state, $, escapeHtml, formatMoney, formatPercent,
} from './shared.js';
import { screenUniverse } from '../core/screener.js';

function renderSectorOptions() {
  const select = $('#sc-sector');
  if (!select) return;
  const current = select.value;
  const sectors = [...new Set(UNIVERSE.map((asset) => asset.sector))].sort();
  select.innerHTML = '<option value="">All sectors</option>'
    + sectors.map((sector) => `<option value="${escapeHtml(sector)}">${escapeHtml(sector)}</option>`).join('');
  if (sectors.includes(current)) select.value = current;
}

export function initScreener() {
  renderSectorOptions();

  $('#screener-form').addEventListener('submit', (event) => {
    event.preventDefault();
    applyFilters();
  });

  $('#screener-table tbody').addEventListener('click', (event) => {
    const row = event.target.closest('tr[data-symbol]');
    if (!row) return;
    document.dispatchEvent(new CustomEvent('ik:open-symbol', { detail: { symbol: row.dataset.symbol } }));
  });

  renderScreener();
  document.addEventListener('ik:market-updated', renderScreener);
  document.addEventListener('ik:assets-updated', () => {
    renderSectorOptions();
    renderScreener();
  });
}

function applyFilters() {
  const sector = $('#sc-sector').value;
  state.screener.filters = {
    sectors: sector ? [sector] : [],
    minPrice: 0,
    maxPrice: Infinity,
    minAvgVolume: 0,
    minMomentum: Number($('#sc-momentum').value) || -100,
    maxMomentum: Infinity,
    minRsi: 0,
    maxRsi: Number($('#sc-rsi').value) || 100,
    trendOnly: $('#sc-trend').checked,
    sortBy: $('#sc-sort').value,
  };
  renderScreener();
}

export function renderScreener() {
  const rows = screenUniverse(candleMap, UNIVERSE, state.screener.filters);
  $('#sc-count').textContent = `${rows.length} of ${UNIVERSE.length} assets match`;
  const tbody = $('#screener-table tbody');
  if (!rows.length) {
    tbody.innerHTML = '<tr><td class="empty-row" colspan="8">No assets match these filters.</td></tr>';
    return;
  }
  tbody.innerHTML = rows.map((row) => {
    const change = row.change * 100;
    const momentum = Number.isFinite(row.momentum) ? row.momentum : 0;
    const score = Math.round(row.score * 100);
    const tone = score >= 70 ? 'good' : score < 45 ? 'bad' : '';
    const reasons = row.reasons.slice(0, 2).map(escapeHtml).join(' · ') || '—';
    return `<tr class="clickable" data-symbol="${row.symbol}">
      <td><span class="symbol">${row.symbol}</span><span class="sub">${escapeHtml(row.name)}</span></td>
      <td>${escapeHtml(row.sector)}</td>
      <td class="num">${formatMoney(row.price, 2)}</td>
      <td class="num ${change >= 0 ? 'pos' : 'neg'}">${change >= 0 ? '+' : ''}${change.toFixed(2)}%</td>
      <td class="num ${momentum >= 0 ? 'pos' : 'neg'}">${momentum >= 0 ? '+' : ''}${momentum.toFixed(1)}%</td>
      <td class="num">${Number.isFinite(row.rsi) ? row.rsi.toFixed(1) : '—'}</td>
      <td><span class="pill ${tone}">${score}</span></td>
      <td class="muted">${reasons}</td>
    </tr>`;
  }).join('');
}
