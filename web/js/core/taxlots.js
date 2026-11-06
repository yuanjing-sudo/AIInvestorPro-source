// Tax-lot ledger with FIFO, LIFO, highest-cost and lowest-cost disposal.

export function createLot({ symbol, quantity, costPerShare, acquiredAt, id }) {
  if (!symbol) throw new Error('symbol is required');
  if (!(quantity > 0)) throw new Error('quantity must be positive');
  if (!(costPerShare > 0)) throw new Error('costPerShare must be positive');
  return {
    id: id ?? `${symbol}-${acquiredAt ?? Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    symbol,
    quantity,
    costPerShare,
    acquiredAt: acquiredAt ? new Date(acquiredAt) : new Date(),
    remaining: quantity,
  };
}

export function addLot(lots, lot) {
  return [...lots, createLot(lot)];
}

export function lotsForSymbol(lots, symbol) {
  return lots.filter((lot) => lot.symbol === symbol && lot.remaining > 1e-9);
}

function orderLots(lots, method) {
  const copy = [...lots];
  switch (method) {
    case 'LIFO':
      return copy.sort((a, b) => b.acquiredAt - a.acquiredAt);
    case 'HIFO':
      return copy.sort((a, b) => b.costPerShare - a.costPerShare);
    case 'LOFO':
      return copy.sort((a, b) => a.costPerShare - b.costPerShare);
    case 'FIFO':
    default:
      return copy.sort((a, b) => a.acquiredAt - b.acquiredAt);
  }
}

export function sell(lots, { symbol, quantity, price, soldAt, method = 'FIFO' }) {
  if (!(quantity > 0)) throw new Error('quantity must be positive');
  if (!(price > 0)) throw new Error('price must be positive');
  const available = lotsForSymbol(lots, symbol).reduce((acc, lot) => acc + lot.remaining, 0);
  if (quantity > available + 1e-9) {
    throw new Error(`insufficient shares: requested ${quantity}, available ${available}`);
  }

  const ordered = orderLots(lotsForSymbol(lots, symbol), method);
  let remaining = quantity;
  let costBasis = 0;
  const consumed = [];
  const updated = lots.map((lot) => ({ ...lot }));

  for (const candidate of ordered) {
    if (remaining <= 1e-12) break;
    const target = updated.find((lot) => lot.id === candidate.id);
    if (!target) continue;
    const take = Math.min(target.remaining, remaining);
    costBasis += take * target.costPerShare;
    target.remaining -= take;
    remaining -= take;
    consumed.push({
      lotId: target.id,
      quantity: take,
      costPerShare: target.costPerShare,
      acquiredAt: target.acquiredAt,
    });
  }

  const proceeds = quantity * price;
  const realizedGain = proceeds - costBasis;
  const sale = {
    id: `sale-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    symbol,
    quantity,
    price,
    proceeds,
    costBasis,
    realizedGain,
    gainPercent: costBasis > 0 ? realizedGain / costBasis : 0,
    method,
    soldAt: soldAt ? new Date(soldAt) : new Date(),
    consumed,
  };
  return { lots: updated, sale };
}

export function unrealized(lots, priceMap) {
  return lots
    .filter((lot) => lot.remaining > 1e-9)
    .map((lot) => {
      const price = priceMap[lot.symbol] ?? lot.costPerShare;
      const marketValue = lot.remaining * price;
      const costBasis = lot.remaining * lot.costPerShare;
      return {
        ...lot,
        price,
        marketValue,
        costBasis,
        unrealizedGain: marketValue - costBasis,
        unrealizedPercent: costBasis > 0 ? (marketValue - costBasis) / costBasis : 0,
      };
    });
}

export function summarizeLots(lots, priceMap) {
  const rows = unrealized(lots, priceMap);
  const marketValue = rows.reduce((acc, row) => acc + row.marketValue, 0);
  const costBasis = rows.reduce((acc, row) => acc + row.costBasis, 0);
  return {
    rows,
    marketValue,
    costBasis,
    unrealizedGain: marketValue - costBasis,
    unrealizedPercent: costBasis > 0 ? (marketValue - costBasis) / costBasis : 0,
  };
}

export function compareMethods(lots, { symbol, quantity, price, soldAt }) {
  const methods = ['FIFO', 'LIFO', 'HIFO', 'LOFO'];
  return methods.map((method) => {
    const result = sell(lots, { symbol, quantity, price, soldAt, method });
    return {
      method,
      costBasis: result.sale.costBasis,
      realizedGain: result.sale.realizedGain,
      consumed: result.sale.consumed,
    };
  }).sort((a, b) => a.realizedGain - b.realizedGain);
}

export function realizedSummary(sales) {
  const totalProceeds = sales.reduce((acc, s) => acc + s.proceeds, 0);
  const totalCost = sales.reduce((acc, s) => acc + s.costBasis, 0);
  return {
    sales: sales.length,
    totalProceeds,
    totalCost,
    totalGain: totalProceeds - totalCost,
    winners: sales.filter((s) => s.realizedGain > 0).length,
    losers: sales.filter((s) => s.realizedGain < 0).length,
  };
}
