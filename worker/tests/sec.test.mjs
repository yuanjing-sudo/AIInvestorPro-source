import test from 'node:test';
import assert from 'node:assert/strict';
import {
  fetchSecProfile, findFact, isSecEligible, parseSecProfile,
} from '../src/sec.js';

function fact(rows) {
  return { units: { USD: rows } };
}

function annualRows(startYear, values) {
  return values.map((value, index) => ({
    start: `${startYear + index}-01-01`,
    end: `${startYear + index}-12-31`,
    val: value,
    form: '10-K',
    filed: `${startYear + index + 1}-02-15`,
    fy: startYear + index,
    fp: 'FY',
  }));
}

const FACTS = {
  entityName: 'Example Corp',
  facts: {
    'us-gaap': {
      Revenues: fact(annualRows(2021, [100, 120, 150])),
      NetIncomeLoss: fact(annualRows(2021, [10, 15, 21])),
      Assets: fact([
        { end: '2023-12-31', val: 500, form: '10-K', filed: '2024-02-15' },
        { end: '2024-12-31', val: 550, form: '10-K', filed: '2025-02-15' },
      ]),
      Liabilities: fact([{ end: '2024-12-31', val: 250, form: '10-K', filed: '2025-02-15' }]),
      StockholdersEquity: fact([{ end: '2024-12-31', val: 300, form: '10-K', filed: '2025-02-15' }]),
      CashAndCashEquivalentsAtCarryingValue: fact([{ end: '2024-12-31', val: 80, form: '10-K', filed: '2025-02-15' }]),
      NetCashProvidedByUsedInOperatingActivities: fact(annualRows(2023, [40])),
      PaymentsToAcquirePropertyPlantAndEquipment: fact(annualRows(2023, [10])),
      EarningsPerShareDiluted: {
        units: { 'USD/shares': annualRows(2023, [2.1]) },
      },
      ResearchAndDevelopmentExpense: fact(annualRows(2023, [15])),
      GrossProfit: fact(annualRows(2023, [90])),
      AssetsCurrent: fact([{ end: '2024-12-31', val: 220, form: '10-K', filed: '2025-02-15' }]),
      LiabilitiesCurrent: fact([{ end: '2024-12-31', val: 110, form: '10-K', filed: '2025-02-15' }]),
    },
    dei: {
      EntityCommonStockSharesOutstanding: {
        units: { shares: [{ end: '2024-12-31', val: 50, form: '10-K', filed: '2025-02-15' }] },
      },
    },
  },
};

const SUBMISSIONS = {
  name: 'Example Corp',
  tickers: ['EXMP'],
  exchanges: ['Nasdaq'],
  sicDescription: 'Testing',
  fiscalYearEnd: '1231',
  filings: {
    recent: {
      form: ['10-K', '8-K', 'S-1'],
      filingDate: ['2025-02-15', '2025-01-10', '2024-12-01'],
      reportDate: ['2024-12-31', '2025-01-10', ''],
      primaryDocument: ['exmp-20241231.htm', 'exmp-8k.htm', 'exmp-s1.htm'],
      primaryDocDescription: ['Annual report', 'Current report', 'Registration'],
      accessionNumber: ['0000000000-25-000001', '0000000000-25-000002', '0000000000-24-000003'],
    },
  },
};

test('parseSecProfile extracts reported metrics, annual series and filings', () => {
  const profile = parseSecProfile(FACTS, SUBMISSIONS, {
    cik_str: 123456, ticker: 'EXMP', title: 'Example Corp',
  });
  assert.equal(profile.entityName, 'Example Corp');
  assert.equal(profile.cik, '123456');
  assert.equal(profile.metrics.revenue, 150);
  assert.equal(profile.metrics.revenueGrowth, 0.25);
  assert.equal(profile.metrics.netMargin, 0.14);
  assert.equal(profile.metrics.freeCashFlow, 30);
  assert.equal(profile.metrics.epsDiluted, 2.1);
  assert.equal(profile.metrics.bookValuePerShare, 6);
  assert.equal(profile.metrics.debtToEquity, 250 / 300);
  assert.equal(profile.metrics.currentRatio, 2);
  assert.equal(profile.annual.revenue.length, 3);
  assert.equal(profile.filings.length, 3);
  assert.match(profile.filings[0].url, /^https:\/\/www\.sec\.gov\/Archives\/edgar\/data\/123456\//);
  assert.equal(profile.asOf, '2025-02-15');
});

test('findFact chooses the latest annual value and rejects short periods', () => {
  const found = findFact(FACTS, ['Revenues'], 'USD', true);
  assert.equal(found.latest.val, 150);
  assert.equal(found.tag, 'Revenues');
});

test('SEC eligibility excludes non-US and non-equity instruments', () => {
  assert.equal(isSecEligible('AAPL', 'equity'), true);
  assert.equal(isSecEligible('SPY', 'etf'), true);
  assert.equal(isSecEligible('BTC-USD', 'crypto'), false);
  assert.equal(isSecEligible('EURUSD=X', 'forex'), false);
  assert.equal(isSecEligible('^GSPC', 'index'), false);
  assert.equal(isSecEligible('CL=F', 'future'), false);
});

test('fetchSecProfile uses SEC tickers, company facts and submissions', async () => {
  const original = globalThis.fetch;
  const requested = [];
  globalThis.fetch = async (input) => {
    const url = String(input);
    requested.push(url);
    if (url.includes('company_tickers.json')) {
      return new Response(JSON.stringify({ 0: { cik_str: 123456, ticker: 'EXMP', title: 'Example Corp' } }), {
        headers: { 'content-type': 'application/json' },
      });
    }
    if (url.includes('/companyfacts/')) {
      return new Response(JSON.stringify(FACTS), { headers: { 'content-type': 'application/json' } });
    }
    if (url.includes('/submissions/')) {
      return new Response(JSON.stringify(SUBMISSIONS), { headers: { 'content-type': 'application/json' } });
    }
    throw new Error(`unexpected fetch ${url}`);
  };
  try {
    const profile = await fetchSecProfile('EXMP', { kind: 'equity' });
    assert.equal(profile.metrics.revenue, 150);
    assert.equal(requested.length, 3);
    assert.match(requested[0], /company_tickers\.json$/);
    assert.match(requested[1], /companyfacts\/CIK0*123456\.json$/);
    assert.match(requested[2], /submissions\/CIK0*123456\.json$/);
  } finally {
    globalThis.fetch = original;
  }
});
