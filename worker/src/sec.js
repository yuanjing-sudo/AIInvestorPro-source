// SEC EDGAR adapter for reported company fundamentals and recent filings.
//
// SEC EDGAR is a free, public source with a documented fair-access policy. We
// send a descriptive User-Agent, cache responses at the edge and only request
// data for US-registered equity/ETF/fund symbols. Non-US listings, indices,
// futures, FX and crypto are intentionally out of scope.

import { cachedJson } from './http.js';

const TICKERS_URL = 'https://www.sec.gov/files/company_tickers.json';
const FACTS_BASE = 'https://data.sec.gov/api/xbrl/companyfacts/';
const SUBMISSIONS_BASE = 'https://data.sec.gov/submissions/';
const DEFAULT_UA = 'InvestorKitPro/2.0 research@investorkit.example';

const FILING_FORMS = new Set([
  '10-K', '10-Q', '8-K', '20-F', '40-F', '6-K', 'DEF 14A', 'S-1', '424B4',
]);

const REVENUE_TAGS = [
  'RevenueFromContractWithCustomerExcludingAssessedTax',
  'RevenueFromContractWithCustomerIncludingAssessedTax',
  'Revenues',
  'SalesRevenueNet',
  'Revenue',
];
const NET_INCOME_TAGS = ['NetIncomeLoss', 'ProfitLoss', 'NetIncomeLossAvailableToCommonStockholdersBasic'];
const ASSET_TAGS = ['Assets'];
const LIABILITY_TAGS = ['Liabilities'];
const EQUITY_TAGS = ['StockholdersEquity', 'Equity', 'StockholdersEquityIncludingPortionAttributableToNoncontrollingInterest'];
const CASH_TAGS = ['CashAndCashEquivalentsAtCarryingValue', 'CashCashEquivalentsRestrictedCashAndRestrictedCashEquivalents'];
const OPERATING_CASH_TAGS = ['NetCashProvidedByUsedInOperatingActivities'];
const CAPEX_TAGS = ['PaymentsToAcquirePropertyPlantAndEquipment', 'PaymentsToAcquireProductiveAssets'];
const EPS_TAGS = ['EarningsPerShareDiluted', 'EarningsPerShareBasicAndDiluted', 'EarningsPerShareBasic'];
const SHARE_TAGS = ['EntityCommonStockSharesOutstanding', 'CommonStockSharesOutstanding'];
const RD_TAGS = ['ResearchAndDevelopmentExpense'];
const GROSS_PROFIT_TAGS = ['GrossProfit'];
const CURRENT_ASSET_TAGS = ['AssetsCurrent'];
const CURRENT_LIABILITY_TAGS = ['LiabilitiesCurrent'];

function daysBetween(start, end) {
  const first = Date.parse(start);
  const last = Date.parse(end);
  if (!Number.isFinite(first) || !Number.isFinite(last)) return null;
  return (last - first) / 86_400_000;
}

function rowDate(row) {
  return row?.end ?? row?.filed ?? null;
}

function sortRows(rows) {
  return [...rows].sort((a, b) => {
    const byEnd = String(rowDate(b) ?? '').localeCompare(String(rowDate(a) ?? ''));
    if (byEnd) return byEnd;
    return String(b.filed ?? '').localeCompare(String(a.filed ?? ''));
  });
}

export function findFact(facts, tags, unit = 'USD', duration = true) {
  const taxonomies = facts?.facts ?? {};
  let best = null;
  for (const tag of tags) {
    for (const taxonomy of ['us-gaap', 'ifrs-full', 'dei']) {
      const rows = taxonomies?.[taxonomy]?.[tag]?.units?.[unit];
      if (!Array.isArray(rows) || !rows.length) continue;
      const filtered = rows.filter((row) => {
        if (!row?.end) return false;
        if (!duration) return true;
        if (!row.start) return false;
        const days = daysBetween(row.start, row.end);
        return Number.isFinite(days) && days >= 300 && days <= 400;
      });
      if (!filtered.length) continue;
      const sorted = sortRows(filtered);
      const candidate = { tag, taxonomy, rows: sorted, latest: sorted[0] };
      if (!best) {
        best = candidate;
        continue;
      }
      const byEnd = String(candidate.latest.end).localeCompare(String(best.latest.end));
      const byFiled = String(candidate.latest.filed ?? '').localeCompare(String(best.latest.filed ?? ''));
      if (byEnd > 0 || (byEnd === 0 && byFiled > 0)) best = candidate;
    }
  }
  return best;
}

function latestQuarter(facts, tags, unit = 'USD') {
  const taxonomies = facts?.facts ?? {};
  let best = null;
  for (const tag of tags) {
    for (const taxonomy of ['us-gaap', 'ifrs-full']) {
      const rows = taxonomies?.[taxonomy]?.[tag]?.units?.[unit];
      if (!Array.isArray(rows)) continue;
      const filtered = rows.filter((row) => {
        if (!row?.end || !row.start) return false;
        const days = daysBetween(row.start, row.end);
        return Number.isFinite(days) && days >= 60 && days <= 110;
      });
      if (!filtered.length) continue;
      const sorted = sortRows(filtered);
      if (!best) {
        best = sorted[0];
        continue;
      }
      const byEnd = String(sorted[0].end).localeCompare(String(best.end));
      const byFiled = String(sorted[0].filed ?? '').localeCompare(String(best.filed ?? ''));
      if (byEnd > 0 || (byEnd === 0 && byFiled > 0)) best = sorted[0];
    }
  }
  return best;
}

function annualSeries(facts, tags, unit = 'USD', limit = 5) {
  const found = findFact(facts, tags, unit, true);
  if (!found) return [];
  const byEnd = new Map();
  for (const row of found.rows) {
    const key = row.end;
    const current = byEnd.get(key);
    if (!current || String(row.filed ?? '') > String(current.filed ?? '')) byEnd.set(key, row);
  }
  return [...byEnd.values()]
    .sort((a, b) => String(a.end).localeCompare(String(b.end)))
    .slice(-limit)
    .map((row) => ({
      end: row.end,
      value: row.val,
      form: row.form ?? null,
      filed: row.filed ?? null,
      fy: row.fy ?? null,
      fp: row.fp ?? null,
    }));
}

function latestInstant(facts, tags, unit = 'USD') {
  return findFact(facts, tags, unit, false)?.latest ?? null;
}

function latestValue(facts, tags, unit = 'USD') {
  const annual = findFact(facts, tags, unit, true)?.latest;
  if (annual) return annual;
  return latestQuarter(facts, tags, unit);
}

function growth(current, previous) {
  return Number.isFinite(current) && Number.isFinite(previous) && previous !== 0
    ? current / previous - 1
    : null;
}

function ratio(numerator, denominator) {
  return Number.isFinite(numerator) && Number.isFinite(denominator) && denominator !== 0
    ? numerator / denominator
    : null;
}

export function parseSecProfile(facts, submissions, entry = {}) {
  const cik = String(entry.cik_str ?? facts?.cik ?? '').replace(/^0+/, '');
  if (!cik) return null;
  const revenueRow = latestValue(facts, REVENUE_TAGS);
  const revenueSeries = annualSeries(facts, REVENUE_TAGS);
  const netIncomeRow = latestValue(facts, NET_INCOME_TAGS);
  const netIncomeSeries = annualSeries(facts, NET_INCOME_TAGS);
  const epsRow = latestValue(facts, EPS_TAGS, 'USD/shares');
  const epsSeries = annualSeries(facts, EPS_TAGS, 'USD/shares');
  const assetsRow = latestInstant(facts, ASSET_TAGS);
  const liabilitiesRow = latestInstant(facts, LIABILITY_TAGS);
  const equityRow = latestInstant(facts, EQUITY_TAGS);
  const cashRow = latestInstant(facts, CASH_TAGS);
  const operatingCashRow = latestValue(facts, OPERATING_CASH_TAGS);
  const capexRow = latestValue(facts, CAPEX_TAGS);
  const sharesRow = latestInstant(facts, SHARE_TAGS, 'shares');
  const rdRow = latestValue(facts, RD_TAGS);
  const grossProfitRow = latestValue(facts, GROSS_PROFIT_TAGS);
  const currentAssetsRow = latestInstant(facts, CURRENT_ASSET_TAGS);
  const currentLiabilitiesRow = latestInstant(facts, CURRENT_LIABILITY_TAGS);

  const revenue = revenueRow?.val ?? null;
  const previousRevenue = revenueSeries.length > 1 ? revenueSeries.at(-2).value : null;
  const netIncome = netIncomeRow?.val ?? null;
  const assets = assetsRow?.val ?? null;
  const liabilities = liabilitiesRow?.val
    ?? (Number.isFinite(assets) && Number.isFinite(equityRow?.val) ? assets - equityRow.val : null);
  const equity = equityRow?.val ?? null;
  const cash = cashRow?.val ?? null;
  const operatingCashFlow = operatingCashRow?.val ?? null;
  const capex = capexRow?.val ?? null;
  const eps = epsRow?.val ?? null;
  const sharesOutstanding = sharesRow?.val ?? null;
  const rdExpense = rdRow?.val ?? null;
  const grossProfit = grossProfitRow?.val ?? null;
  const currentAssets = currentAssetsRow?.val ?? null;
  const currentLiabilities = currentLiabilitiesRow?.val ?? null;
  const freeCashFlow = Number.isFinite(operatingCashFlow) && Number.isFinite(capex)
    ? operatingCashFlow - Math.abs(capex)
    : null;

  const metrics = {
    revenue,
    revenueGrowth: growth(revenue, previousRevenue),
    netIncome,
    netMargin: ratio(netIncome, revenue),
    assets,
    liabilities,
    equity,
    cash,
    operatingCashFlow,
    capex: Number.isFinite(capex) ? Math.abs(capex) : null,
    freeCashFlow,
    epsDiluted: eps,
    sharesOutstanding,
    bookValuePerShare: ratio(equity, sharesOutstanding),
    debtToEquity: ratio(liabilities, equity),
    currentRatio: ratio(currentAssets, currentLiabilities),
    rdExpense,
    rdIntensity: ratio(rdExpense, revenue),
    grossProfit,
    grossMargin: ratio(grossProfit, revenue),
  };

  const annual = {
    revenue: revenueSeries,
    netIncome: netIncomeSeries,
    epsDiluted: epsSeries,
  };

  const recent = submissions?.filings?.recent ?? {};
  const filings = [];
  const count = Array.isArray(recent.form) ? recent.form.length : 0;
  for (let index = 0; index < count && filings.length < 10; index += 1) {
    const form = String(recent.form[index] ?? '');
    if (!FILING_FORMS.has(form)) continue;
    const accession = String(recent.accessionNumber?.[index] ?? '');
    const primaryDocument = String(recent.primaryDocument?.[index] ?? '');
    const accessionPath = accession.replace(/-/g, '');
    const url = accessionPath && primaryDocument
      ? `https://www.sec.gov/Archives/edgar/data/${cik}/${accessionPath}/${primaryDocument}`
      : null;
    filings.push({
      form,
      filingDate: recent.filingDate?.[index] ?? null,
      reportDate: recent.reportDate?.[index] ?? null,
      description: recent.primaryDocDescription?.[index] ?? '',
      accession,
      url,
    });
  }

  filings.sort((a, b) => String(b.filingDate ?? '').localeCompare(String(a.filingDate ?? '')));
  const latestFiling = filings[0]?.filingDate ?? null;
  return {
    source: 'sec',
    sourceLabel: 'SEC EDGAR',
    cik,
    entityName: facts?.entityName ?? submissions?.name ?? entry.title ?? null,
    tickers: submissions?.tickers ?? (entry.ticker ? [entry.ticker] : []),
    exchanges: submissions?.exchanges ?? [],
    sicDescription: submissions?.sicDescription ?? null,
    fiscalYearEnd: submissions?.fiscalYearEnd ?? null,
    currency: 'USD',
    asOf: latestFiling,
    metrics,
    annual,
    filings,
  };
}

export function isSecEligible(symbol, kind = '') {
  if (['crypto', 'forex', 'future', 'index'].includes(kind)) return false;
  if (symbol.startsWith('^') || symbol.endsWith('=F') || symbol.endsWith('=X')) return false;
  if (/(?:-USD|-EUR|-GBP|-JPY|-USDT|-BTC|-ETH)$/.test(symbol)) return false;
  return /^[A-Z][A-Z0-9.-]{0,14}$/.test(symbol);
}

export async function fetchSecProfile(symbol, options = {}) {
  if (!isSecEligible(symbol, options.kind)) return null;
  const headers = {
    'user-agent': options.env?.SEC_USER_AGENT ?? DEFAULT_UA,
    accept: 'application/json',
  };
  const cache = options.cache !== false;
  const tickers = await cachedJson(TICKERS_URL, {
    ttl: 86_400,
    cache,
    headers,
    label: 'SEC company tickers',
  });
  const entries = Object.values(tickers ?? {});
  const entry = entries.find((item) => String(item?.ticker ?? '').toUpperCase() === symbol);
  if (!entry?.cik_str) return null;
  const cik = String(entry.cik_str).padStart(10, '0');
  const [factsResult, submissionsResult] = await Promise.allSettled([
    cachedJson(`${FACTS_BASE}CIK${cik}.json`, {
      ttl: 21_600,
      cache,
      headers,
      label: 'SEC company facts',
    }),
    cachedJson(`${SUBMISSIONS_BASE}CIK${cik}.json`, {
      ttl: 3_600,
      cache,
      headers,
      label: 'SEC submissions',
    }),
  ]);
  const facts = factsResult.status === 'fulfilled' ? factsResult.value : null;
  const submissions = submissionsResult.status === 'fulfilled' ? submissionsResult.value : null;
  if (!facts && !submissions) return null;
  return parseSecProfile(facts, submissions, entry);
}
