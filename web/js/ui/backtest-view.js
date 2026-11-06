// Backtest form and result rendering.

import {
  candleMap, state, $, fillSymbolSelect, escapeHtml, dateLabel, dateShort,
  formatMoney, formatMoneyCompact, formatPercent, formatNumber, formatSignedMoney,
  signClass, makeChart, statCard, emptyRow,
} from './shared.js';
import { STRATEGIES, strategyById, generateSignals } from '../core/strategies.js';
import { runBacktest } from '../core/backtest.js';

let equityChart = null;
let drawdownChart = null;

export function initBacktest() {
  fillSymbolSelect($('#bt-symbol'), state.backtest.symbol);
  $('#bt-strategy').innerHTML = STRATEGIES
    .map((strategy) => `<option value="${strategy.id}">${escapeHtml(strategy.name)}</option>`)
    .join('');
  $('#bt-strategy').value = state.backtest.strategy;

  $('#bt-strategy').addEventListener('change', (event) => {
    state.backtest.strategy = event.target.value;
    renderParams();
  });
  $('#bt-symbol').addEventListener('change', (event) => {
    state.backtest.symbol = event.target.value;
  });
  $('#backtest-form').addEventListener('submit', runFromForm);
  renderParams();
}

function renderParams() {
  const strategy = strategyById($('#bt-strategy').value);
  $('#bt-hint').textContent = `${strategy.description} · 2 years of deterministic demo data.`;
  $('#bt-params').innerHTML = strategy.params.length
    ? strategy.params.map((param) => `<label class="field">
        <span>${escapeHtml(param.label)}</span>
        <input type="number" data-param="${param.key}" min="${param.min}" max="${param.max}" step="${param.step}" value="${param.value}" inputmode="decimal">
      </label>`).join('')
    : '<p class="muted small" style="align-self:center">This strategy has no parameters.</p>';
}

function readParams() {
  const params = {};
  for (const input of $('#bt-params').querySelectorAll('input[data-param]')) {
    params[input.dataset.param] = Number(input.value);
  }
  return params;
}

function runFromForm(event) {
  event.preventDefault();
  const strategy = strategyById($('#bt-strategy').value);
  const symbol = $('#bt-symbol').value;
  const candles = candleMap[symbol];
  if (!candles?.length) {
    window.alert('No data for that symbol.');
    return;
  }
  const params = readParams();
  const signals = generateSignals(strategy.id, candles, params);
  const initialCapital = Math.max(1000, Number($('#bt-capital').value) || 100000);
  const commissionBps = Math.max(0, Number($('#bt-commission').value) || 0);
  const slippageBps = Math.max(0, Number($('#bt-slippage').value) || 0);
  const fraction = Math.min(100, Math.max(1, Number($('#bt-fraction').value) || 100)) / 100;

  const result = runBacktest(candles, signals, {
    initialCapital,
    commissionBps,
    slippageBps,
    fraction,
  });
  state.backtest = { symbol, strategy: strategy.id, result };
  renderBacktestResult();
  $('#backtest-results').scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function renderBacktestResult() {
  const result = state.backtest.result;
  if (!result) return;
  $('#backtest-results').hidden = false;

  const start = result.initialCapital;
  $('#bt-stats').innerHTML = [
    statCard('Final value', formatMoney(result.finalValue), `${formatPercent(result.totalReturn)} total return`, signClass(result.totalReturn)),
    statCard('CAGR', formatPercent(result.cagr), 'Compound annual growth', signClass(result.cagr)),
    statCard('Sharpe', formatNumber(result.sharpe), `Vol ${formatPercent(result.volatility, 1)}`),
    statCard('Max drawdown', formatPercent(result.maxDrawdown), 'Peak to trough', result.maxDrawdown < -0.2 ? 'neg' : ''),
    statCard('Win rate', formatPercent(result.winRate, 1), `${result.trades.length} closed trades`),
    statCard('Profit factor', Number.isFinite(result.profitFactor) ? formatNumber(result.profitFactor) : '∞', 'Gross profit / loss'),
    statCard('Time in market', formatPercent(result.timeInMarket, 1), 'Bars with exposure'),
    statCard('Alpha vs hold', formatPercent(result.alpha), 'Total return difference', signClass(result.alpha)),
    statCard('Costs', formatMoney(result.totalCommission), `${formatNumber(result.trades.length)} trades`),
    statCard('Start capital', formatMoney(start), 'Initial equity'),
  ].join('');

  if (!equityChart) {
    equityChart = makeChart($('#bt-equity-canvas'), {
      height: 280,
      yFormat: (value) => formatMoneyCompact(value),
    });
  }
  equityChart.setData({
    labels: result.dates.map((date) => dateLabel(date)),
    series: [
      { name: 'Strategy', values: result.equity, color: '#2dd4bf', width: 2.2, area: true },
      { name: 'Buy & hold', values: result.benchmark, color: '#94a3b8', width: 1.5, dashed: true },
    ],
    yFormat: (value) => formatMoneyCompact(value),
  });

  if (!drawdownChart) {
    drawdownChart = makeChart($('#bt-drawdown-canvas'), {
      height: 280,
      yFormat: (value) => formatPercent(value, 1),
    });
  }
  drawdownChart.setData({
    labels: result.dates.map((date) => dateLabel(date)),
    series: [
      { name: 'Drawdown', values: result.drawdown, color: '#fb7185', width: 1.8, area: true },
    ],
    yFormat: (value) => formatPercent(value, 1),
  });

  $('#bt-trade-summary').textContent = result.trades.length
    ? `${result.trades.length} closed trades · ${formatPercent(result.tradeStats.winRate, 1)} win rate · ${formatMoney(result.totalCommission)} total costs · ${formatPercent(result.timeInMarket, 1)} invested`
    : 'No trades were executed by this configuration.';

  const tbody = $('#bt-trades tbody');
  if (!result.trades.length) {
    tbody.innerHTML = emptyRow(7, 'No trades — the strategy stayed flat.');
    return;
  }
  tbody.innerHTML = result.trades.slice(-60).reverse().map((trade) => `<tr>
    <td>${dateShort(trade.entryDate)}</td>
    <td>${dateShort(trade.exitDate)}</td>
    <td class="num">${trade.bars}</td>
    <td class="num">${formatMoney(trade.entryPrice, 2)}</td>
    <td class="num">${formatMoney(trade.exitPrice, 2)}</td>
    <td class="num ${signClass(trade.pnl)}">${formatSignedMoney(trade.pnl)}</td>
    <td class="num ${signClass(trade.returnPct)}">${formatPercent(trade.returnPct, 2)}</td>
  </tr>`).join('');
}
