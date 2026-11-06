// Portfolio ledger, transactions and tax-lot comparison.

import {
  UNIVERSE, quotes, state, $, escapeHtml, formatMoney, formatPercent,
  formatSignedMoney, signClass, statCard, aggregatePortfolio,
  savePortfolio, toast, demoPortfolio, fillSymbolSelect, emptyRow,
} from './shared.js';
import { addLot, sell, compareMethods } from '../core/taxlots.js';

export function initPortfolio() {
  fillSymbolSelect($('#tx-symbol'), 'AAPL');
  fillSymbolSelect($('#tax-symbol'), 'AAPL');
  setPriceFromQuote('#tx-symbol', '#tx-price');
  setPriceFromQuote('#tax-symbol', '#tax-price');

  $('#tx-symbol').addEventListener('change', () => setPriceFromQuote('#tx-symbol', '#tx-price'));
  $('#tax-symbol').addEventListener('change', () => setPriceFromQuote('#tax-symbol', '#tax-price'));

  $('#transaction-form').addEventListener('submit', recordTransaction);
  $('#tax-form').addEventListener('submit', (event) => {
    event.preventDefault();
    renderTaxComparison();
  });
  $('#portfolio-demo').addEventListener('click', () => {
    state.portfolio = demoPortfolio();
    savePortfolio();
    renderPortfolio();
    toast('Demo portfolio loaded.');
  });
  $('#portfolio-reset').addEventListener('click', () => {
    if (!window.confirm('Clear all holdings, sales and cash from this browser?')) return;
    state.portfolio = { cash: 0, lots: [], sales: [] };
    savePortfolio();
    renderPortfolio();
    $('#tax-table tbody').innerHTML = emptyRow(4, 'No lots to compare.');
    toast('Portfolio cleared.');
  });

  renderPortfolio();
  $('#tax-table tbody').innerHTML = emptyRow(4, 'Choose a symbol, quantity and price, then compare.');
}

function formatShares(value) {
  if (!Number.isFinite(value)) return '—';
  return Number.isInteger(value) ? String(value) : String(Number(value.toFixed(4)));
}

function setPriceFromQuote(symbolSelector, priceSelector) {
  const symbol = $(symbolSelector).value;
  const quote = quotes[symbol];
  if (quote) $(priceSelector).value = quote.price.toFixed(2);
  const hint = $('#tx-hint');
  if (hint && symbolSelector === '#tx-symbol') {
    hint.textContent = `Latest ${symbol} demo quote: ${formatMoney(quote?.price ?? 0, 2)}.`;
  }
}

function recordTransaction(event) {
  event.preventDefault();
  const symbol = $('#tx-symbol').value;
  const side = $('#tx-side').value;
  const quantity = Number($('#tx-quantity').value);
  const price = Number($('#tx-price').value);
  const fee = Math.max(0, Number($('#tx-fee').value) || 0);

  if (!(quantity > 0) || !(price > 0)) {
    toast('Enter a positive quantity and price.');
    return;
  }

  if (side === 'buy') {
    const total = quantity * price + fee;
    if (total > state.portfolio.cash + 1e-9) {
      toast(`Not enough cash: ${formatMoney(total)} needed, ${formatMoney(state.portfolio.cash)} available.`);
      return;
    }
    const costPerShare = (quantity * price + fee) / quantity;
    state.portfolio.lots = addLot(state.portfolio.lots, {
      symbol, quantity, costPerShare, acquiredAt: new Date(),
    });
    state.portfolio.cash -= total;
    toast(`Bought ${formatShares(quantity)} ${symbol} at ${formatMoney(price, 2)}.`);
  } else {
    const netPrice = price - fee / quantity;
    if (netPrice <= 0) {
      toast('The fee is larger than the sale proceeds.');
      return;
    }
    try {
      const result = sell(state.portfolio.lots, {
        symbol, quantity, price: netPrice, soldAt: new Date(), method: 'FIFO',
      });
      state.portfolio.lots = result.lots;
      state.portfolio.sales.push(result.sale);
      state.portfolio.cash += quantity * netPrice;
      toast(`Sold ${formatShares(quantity)} ${symbol}: ${formatSignedMoney(result.sale.realizedGain)} realized.`);
    } catch (error) {
      toast(error.message);
      return;
    }
  }

  savePortfolio();
  renderPortfolio();
  renderTaxComparison();
}

function renderPortfolio() {
  const aggregate = aggregatePortfolio();
  const activeLots = aggregate.holdings.length;
  $('#portfolio-summary').innerHTML = [
    statCard('Total value', formatMoney(aggregate.total), `${activeLots} position${activeLots === 1 ? '' : 's'} + cash`),
    statCard('Cash', formatMoney(aggregate.cash), 'Available to deploy'),
    statCard('Unrealized P&L', formatSignedMoney(aggregate.unrealized), formatPercent(aggregate.unrealizedPercent), signClass(aggregate.unrealized)),
    statCard('Realized P&L', formatSignedMoney(aggregate.realized), `${state.portfolio.sales.length} sale${state.portfolio.sales.length === 1 ? '' : 's'}`, signClass(aggregate.realized)),
  ].join('');

  const tbody = $('#holdings-table tbody');
  if (!aggregate.holdings.length) {
    tbody.innerHTML = emptyRow(6, 'No holdings yet. Record a buy or load the demo portfolio.');
    return;
  }
  tbody.innerHTML = aggregate.holdings.map((row) => `<tr>
    <td><span class="symbol">${row.symbol}</span><span class="sub">${formatPercent(row.allocation, 1)} of holdings</span></td>
    <td class="num">${formatShares(row.quantity)}</td>
    <td class="num">${formatMoney(row.averageCost, 2)}</td>
    <td class="num">${formatMoney(row.price, 2)}</td>
    <td class="num">${formatMoney(row.marketValue)}</td>
    <td class="num ${signClass(row.unrealized)}">${formatSignedMoney(row.unrealized)}<span class="sub">${formatPercent(row.unrealizedPercent, 2)}</span></td>
  </tr>`).join('');
}

function renderTaxComparison() {
  const symbol = $('#tax-symbol').value;
  const quantity = Number($('#tax-quantity').value);
  const price = Number($('#tax-price').value);
  const tbody = $('#tax-table tbody');

  if (!(quantity > 0) || !(price > 0)) {
    tbody.innerHTML = emptyRow(4, 'Enter a positive quantity and sale price.');
    return;
  }

  try {
    const comparison = compareMethods(state.portfolio.lots, {
      symbol, quantity, price, soldAt: new Date(),
    });
    tbody.innerHTML = comparison.map((row, index) => `<tr>
      <td><strong>${row.method}</strong><span class="sub">${row.consumed.length} lot${row.consumed.length === 1 ? '' : 's'}</span></td>
      <td class="num">${formatMoney(row.costBasis)}</td>
      <td class="num ${signClass(row.realizedGain)}">${formatSignedMoney(row.realizedGain)}</td>
      <td><span class="pill ${index === 0 ? 'good' : ''}">#${index + 1}</span></td>
    </tr>`).join('');
  } catch (error) {
    tbody.innerHTML = emptyRow(4, error.message);
  }
}
