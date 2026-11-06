// Alert rules, local evaluation and trigger history.

import {
  quotes, indicators, state, $, escapeHtml, dateTime, fillSymbolSelect,
  formatNumber, toast, saveAlerts,
} from './shared.js';
import { ALERT_TYPES, createRule, evaluateRules, markTriggered } from '../core/alerts.js';

const COOLDOWN_MS = 30 * 60 * 1000;

export function initAlerts() {
  fillSymbolSelect($('#alert-symbol'), 'AAPL');
  $('#alert-type').innerHTML = ALERT_TYPES
    .map((type) => `<option value="${type.id}">${escapeHtml(type.label)}</option>`)
    .join('');

  $('#alert-symbol').addEventListener('change', () => {
    if ($('#alert-type').value.startsWith('price')) setDefaultThreshold();
  });
  $('#alert-type').addEventListener('change', setDefaultThreshold);
  $('#alert-form').addEventListener('submit', createAlert);
  $('#alerts-check').addEventListener('click', checkNow);
  $('#alerts-clear').addEventListener('click', () => {
    state.alerts.history = [];
    saveAlerts();
    renderAlerts();
    toast('Alert history cleared.');
  });
  $('#alerts-list').addEventListener('click', handleRuleAction);

  setDefaultThreshold();
  renderAlerts();
}

function typeMeta(id) {
  return ALERT_TYPES.find((type) => type.id === id) ?? ALERT_TYPES[0];
}

function setDefaultThreshold() {
  const type = $('#alert-type').value;
  const quote = quotes[$('#alert-symbol').value];
  const input = $('#alert-threshold');
  const defaults = {
    priceAbove: quote?.price ?? 100,
    priceBelow: quote?.price ?? 100,
    changeAbove: 3,
    changeBelow: -3,
    rsiAbove: 70,
    rsiBelow: 30,
    volumeAbove: quote?.volume ?? 1_000_000,
  };
  input.value = Number((defaults[type] ?? 0).toFixed(2));
}

function createAlert(event) {
  event.preventDefault();
  const symbol = $('#alert-symbol').value;
  const type = $('#alert-type').value;
  const threshold = Number($('#alert-threshold').value);
  const note = $('#alert-note').value.trim();
  if (!Number.isFinite(threshold)) {
    toast('Enter a numeric threshold.');
    return;
  }
  const rule = createRule({ symbol, type, threshold, note });
  state.alerts.rules = [rule, ...state.alerts.rules];
  saveAlerts();
  renderAlerts();
  $('#alert-note').value = '';
  toast(`Alert created for ${symbol}.`);
}

function checkNow() {
  if (!state.alerts.rules.length) {
    toast('Create an alert first.');
    return;
  }
  const now = Date.now();
  const eligible = state.alerts.rules.map((rule) => {
    const last = rule.lastTriggeredAt ? new Date(rule.lastTriggeredAt).getTime() : 0;
    return { ...rule, enabled: Boolean(rule.enabled) && now - last >= COOLDOWN_MS };
  });
  const triggered = evaluateRules(eligible, { quotes, indicators });
  if (!triggered.length) {
    toast('No alerts triggered right now.');
    return;
  }
  const triggeredAt = new Date().toISOString();
  state.alerts.rules = markTriggered(state.alerts.rules, triggered, triggeredAt);
  const history = triggered.map((entry, index) => ({
    id: `${Date.now()}-${index}`,
    message: entry.message,
    at: triggeredAt,
  }));
  state.alerts.history = [...history, ...state.alerts.history].slice(0, 50);
  saveAlerts();
  renderAlerts();
  toast(`${triggered.length} alert${triggered.length === 1 ? '' : 's'} triggered.`);
}

function handleRuleAction(event) {
  const button = event.target.closest('button[data-action]');
  if (!button) return;
  const { action, id } = button.dataset;
  if (action === 'toggle') {
    state.alerts.rules = state.alerts.rules.map((rule) => (
      rule.id === id ? { ...rule, enabled: !rule.enabled } : rule
    ));
  } else if (action === 'delete') {
    state.alerts.rules = state.alerts.rules.filter((rule) => rule.id !== id);
  } else {
    return;
  }
  saveAlerts();
  renderAlerts();
}

function thresholdText(rule) {
  const type = typeMeta(rule.type);
  if (type.unit === 'currency') return `$${Number(rule.threshold).toFixed(2)}`;
  if (type.unit === 'percent') return `${Number(rule.threshold).toFixed(2)}%`;
  if (type.unit === 'number' && rule.type === 'volumeAbove') return formatNumber(rule.threshold, 0);
  return formatNumber(rule.threshold, 1);
}

export function renderAlerts() {
  const rules = state.alerts.rules;
  const enabled = rules.filter((rule) => rule.enabled).length;
  $('#alerts-count').textContent = `${rules.length} rule${rules.length === 1 ? '' : 's'} · ${enabled} enabled`;

  const list = $('#alerts-list');
  list.innerHTML = rules.length
    ? rules.map((rule) => {
      const meta = typeMeta(rule.type);
      return `<div class="list-item">
        <div>
          <strong>${escapeHtml(rule.symbol)} · ${escapeHtml(meta.label)} ${thresholdText(rule)}</strong>
          <span class="meta">${rule.note ? escapeHtml(rule.note) : 'No note'}${rule.lastTriggeredAt ? ` · last hit ${dateTime(rule.lastTriggeredAt)}` : ''}</span>
        </div>
        <div class="list-actions">
          <button class="button ghost small" data-action="toggle" data-id="${rule.id}">${rule.enabled ? 'Disable' : 'Enable'}</button>
          <button class="button ghost small danger" data-action="delete" data-id="${rule.id}">Delete</button>
        </div>
      </div>`;
    }).join('')
    : '<p class="empty-state">No rules yet. Create one on the left.</p>';

  const history = state.alerts.history;
  $('#alerts-history').innerHTML = history.length
    ? history.slice(0, 20).map((entry) => `<div class="list-item">
        <div><strong>${escapeHtml(entry.message)}</strong><span class="meta">${dateTime(entry.at)}</span></div>
      </div>`).join('')
    : '<p class="empty-state">Triggered alerts will appear here.</p>';
}
