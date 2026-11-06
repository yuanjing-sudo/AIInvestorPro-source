// Dashboard: portfolio summary, market table, selected-asset chart and signals.

import {
  UNIVERSE, quotes, candleMap, indicators, returnsBySymbol, assetsBySymbol,
  state, $, escapeHtml, dateLabel, formatMoney, formatMoneyCompact,
  formatPercent, formatNumber, formatSignedMoney, signClass, makeChart,
  statCard, aggregatePortfolio, fillSymbolSelect,
} from './shared.js';
import { sma } from '../core/indicators.js';
import { analyzeReturns } from '../core/analytics.js';
import { portfolioSignals } from '../core/screener.js';

let assetChart = null;

export function initDashboard() {
  fillSymbolSelect($('#dashboard-symbol'), state.symbol);
  $('#dashboard-symbol').addEventListener('change', (event) => {
    state.symbol = event.target.value;
    renderDashboard();
  });

  $('#market-table tbody').addEventListener('click', (event) => {
    const row = event.target.closest('tr[data-symbol]');
    if (!row) return;
    state.symbol = row.dataset.symbol;
    renderDashboard();
  });

  $('#signal-cards').addEventListener('click', (event) => {
    const card = event.target.closest('[data-symbol]');
    if (!card) return;
    state.symbol = card.dataset.symbol;
    renderDashboard();
  });

  renderDashboard();
}

export function renderDashboard() {
  renderStats();
  renderMarketTable();
  renderAsset();
  renderSignals();
}

function renderStats() {
  const aggregate = aggregatePortfolio();
  const spy = analyzeReturns(returnsBySymbol.SPY.slice(-252));
  $('#dashboard-stats').innerHTML = [
    statCard('Total value', formatMoney(aggregate.total), `${formatMoney(aggregate.cash)} cash`),
    statCard('Unrealized P&L', formatSignedMoney(aggregate.unrealized), formatPercent(aggregate.unrealizedPercent), signClass(aggregate.unrealized)),
    statCard('SPY Sharpe · 1Y', formatNumber(spy.sharpe), 'Risk-free rate 2%'),
    statCard('SPY max drawdown · 1Y', formatPercent(spy.maxDrawdown), 'Peak to trough', spy.maxDrawdown < -0.15 ? 'neg' : ''),
  ].join('');
}

function renderMarketTable() {
  const tbody = $('#market-table tbody');
  tbody.innerHTML = UNIVERSE.map((asset) => {
    const quote = quotes[asset.symbol];
    const ind = indicators[asset.symbol];
    const trend = Number.isFinite(ind?.sma20) && Number.isFinite(ind?.sma50)
      ? ind.sma20 > ind.sma50
      : false;
    const change = quote.changePercent;
    return `<tr class="clickable ${state.symbol === asset.symbol ? 'is-selected' : ''}" data-symbol="${asset.symbol}">
      <td><span class="symbol">${asset.symbol}</span><span class="sub">${escapeHtml(asset.name)}</span></td>
      <td class="num">${formatMoney(quote.price, 2)}</td>
      <td class="num ${change >= 0 ? 'pos' : 'neg'}">${change >= 0 ? '+' : ''}${change.toFixed(2)}%</td>
      <td class="num">${Number.isFinite(ind?.rsi) ? ind.rsi.toFixed(1) : '—'}</td>
      <td><span class="pill ${trend ? 'good' : 'bad'}">${trend ? 'Up' : 'Down'}</span></td>
    </tr>`;
  }).join('');

  const last = candleMap.SPY?.at(-1)?.date;
  $('#market-asof').textContent = last
    ? (last instanceof Date ? last : new Date(last)).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })
    : '—';
}

function renderAsset() {
  const symbol = assetsBySymbol[state.symbol] ? state.symbol : 'SPY';
  state.symbol = symbol;
  const asset = assetsBySymbol[symbol];
  const candles = candleMap[symbol].slice(-300);
  const close = candles.map((candle) => candle.close);
  const fast = sma(close, 20);
  const slow = sma(close, 50);

  $('#asset-title').textContent = asset.symbol;
  $('#asset-subtitle').textContent = `${asset.name} · ${asset.sector}`;
  $('#dashboard-symbol').value = symbol;

  if (!assetChart) {
    assetChart = makeChart($('#asset-chart'), {
      height: 260,
      yFormat: (value) => formatMoneyCompact(value),
    });
  }
  assetChart.setData({
    labels: candles.map((candle) => dateLabel(candle.date)),
    series: [
      { name: 'Close', values: close, color: '#2dd4bf', width: 2.2, area: true },
      { name: 'SMA 20', values: fast, color: '#38bdf8', width: 1.4 },
      { name: 'SMA 50', values: slow, color: '#fbbf24', width: 1.4 },
    ],
    yFormat: (value) => formatMoneyCompact(value),
  });

  const ind = indicators[symbol];
  const quote = quotes[symbol];
  const window = candleMap[symbol].slice(-252);
  const high52 = Math.max(...window.map((candle) => candle.high));
  const low52 = Math.min(...window.map((candle) => candle.low));
  const atrPercent = quote.price > 0 ? (ind.atr ?? 0) / quote.price : 0;
  const macdHistogram = (ind.macd ?? 0) - (ind.macdSignal ?? 0);
  const vol60 = analyzeReturns(returnsBySymbol[symbol].slice(-60)).volatility;
  const mini = (label, value) => `<div class="mini-stat"><span>${label}</span><strong>${value}</strong></div>`;

  $('#asset-stats').innerHTML = [
    mini('Price', formatMoney(quote.price, 2)),
    mini('RSI 14', Number.isFinite(ind.rsi) ? ind.rsi.toFixed(1) : '—'),
    mini('ATR %', formatPercent(atrPercent, 1)),
    mini('MACD hist', Number.isFinite(macdHistogram) ? macdHistogram.toFixed(2) : '—'),
    mini('52w high', formatMoney(high52, 2)),
    mini('52w low', formatMoney(low52, 2)),
    mini('60d vol', formatPercent(vol60, 1)),
    mini('Avg volume', formatNumber(ind.meanVolume ?? 0, 0)),
  ].join('');
}

function renderSignals() {
  const signals = portfolioSignals(candleMap, UNIVERSE.map((asset) => asset.symbol))
    .sort((a, b) => b.score - a.score)
    .slice(0, 8);
  $('#signal-cards').innerHTML = signals.map((signal) => {
    const momentum = Number.isFinite(signal.momentum)
      ? `${signal.momentum >= 0 ? '+' : ''}${signal.momentum.toFixed(1)}%`
      : '—';
    const tone = signal.label === 'Accumulate' ? 'good' : signal.label === 'Defensive' ? 'bad' : '';
    return `<button type="button" class="signal-card" data-symbol="${signal.symbol}">
      <header><span class="symbol">${signal.symbol}</span><span class="pill ${tone}">${signal.label}</span></header>
      <div class="signal-score">${Math.round(signal.score * 100)}<span class="muted" style="font-size:.72rem">/100</span></div>
      <div class="signal-meta">RSI ${Number.isFinite(signal.rsi) ? signal.rsi.toFixed(1) : '—'} · 3M ${momentum}</div>
      <div class="signal-bar"><span style="width:${Math.round(signal.score * 100)}%"></span></div>
    </button>`;
  }).join('');
}
