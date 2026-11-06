// Small dependency-free canvas chart with hover tooltips and band fills.

const DEFAULT_PADDING = { left: 58, right: 18, top: 18, bottom: 30 };

export class CanvasChart {
  constructor(canvas, options = {}) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.wrapper = canvas.parentElement;
    this.options = {
      height: 280,
      padding: DEFAULT_PADDING,
      yFormat: (v) => (Math.abs(v) >= 1000 ? `${(v / 1000).toFixed(1)}k` : Number(v).toFixed(2)),
      xFormat: (label) => label,
      showLegend: false,
      ...options,
    };
    this.series = [];
    this.labels = [];
    this.markers = [];
    this.hoverIndex = null;
    this.tooltip = document.createElement('div');
    this.tooltip.className = 'chart-tooltip';
    this.tooltip.hidden = true;
    if (this.wrapper) this.wrapper.appendChild(this.tooltip);

    this.handleMove = this.handleMove.bind(this);
    this.handleLeave = this.handleLeave.bind(this);
    this.handleResize = this.handleResize.bind(this);
    canvas.addEventListener('mousemove', this.handleMove);
    canvas.addEventListener('mouseleave', this.handleLeave);
    canvas.addEventListener('touchstart', this.handleMove, { passive: true });
    canvas.addEventListener('touchmove', this.handleMove, { passive: true });
    canvas.addEventListener('touchend', this.handleLeave);
    this.observer = new ResizeObserver(this.handleResize);
    this.observer.observe(canvas);
    this.draw();
  }

  setData({ series = [], labels = [], markers = [], yFormat, xFormat } = {}) {
    this.series = series;
    this.labels = labels;
    this.markers = markers;
    if (yFormat) this.options.yFormat = yFormat;
    if (xFormat) this.options.xFormat = xFormat;
    this.draw();
  }

  handleResize() {
    this.draw();
  }

  handleLeave() {
    this.hoverIndex = null;
    this.tooltip.hidden = true;
    this.draw();
  }

  handleMove(event) {
    if (!this.series.length || !this.labels.length) return;
    const rect = this.canvas.getBoundingClientRect();
    const point = event.touches ? event.touches[0] : event;
    const x = point.clientX - rect.left;
    const { left, right } = this.options.padding;
    const width = rect.width - left - right;
    if (x < left || x > rect.width - right || width <= 0) {
      this.handleLeave();
      return;
    }
    const ratio = (x - left) / width;
    const index = Math.round(ratio * (this.labels.length - 1));
    this.hoverIndex = Math.max(0, Math.min(this.labels.length - 1, index));
    this.draw();
    this.updateTooltip(rect);
  }

  updateTooltip(rect) {
    const index = this.hoverIndex;
    if (index === null) return;
    const rows = this.series
      .filter((s) => !s.band && !s.silent && s.values && s.values[index] !== null && Number.isFinite(s.values[index]))
      .slice(0, 6)
      .map((s) => `<div class="tt-row"><span class="tt-dot" style="background:${s.color}"></span><span>${escapeHtml(s.name)}</span><strong>${this.options.yFormat(s.values[index])}</strong></div>`)
      .join('');
    this.tooltip.innerHTML = `<div class="tt-title">${escapeHtml(String(this.options.xFormat(this.labels[index])))}</div>${rows}`;
    this.tooltip.hidden = false;
    const { left, right } = this.options.padding;
    const width = rect.width - left - right;
    const x = left + (index / Math.max(1, this.labels.length - 1)) * width;
    const tooltipWidth = this.tooltip.offsetWidth || 170;
    const tooltipHeight = this.tooltip.offsetHeight || 80;
    const leftPos = Math.min(Math.max(x + 12, 4), rect.width - tooltipWidth - 4);
    const topPos = Math.max(4, Math.min(rect.height / 2 - tooltipHeight / 2, rect.height - tooltipHeight - 4));
    this.tooltip.style.left = `${leftPos}px`;
    this.tooltip.style.top = `${topPos}px`;
  }

  draw() {
    const rect = this.canvas.getBoundingClientRect();
    const width = Math.max(120, rect.width);
    const height = this.options.height;
    const dpr = window.devicePixelRatio || 1;
    if (this.canvas.width !== Math.round(width * dpr) || this.canvas.height !== Math.round(height * dpr)) {
      this.canvas.width = Math.round(width * dpr);
      this.canvas.height = Math.round(height * dpr);
      this.canvas.style.height = `${height}px`;
    }
    const ctx = this.ctx;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, width, height);
    const styles = getComputedStyle(this.canvas);
    const gridColor = styles.getPropertyValue('--chart-grid').trim() || 'rgba(148,163,184,.14)';
    const textColor = styles.getPropertyValue('--chart-text').trim() || '#94a3b8';
    const axisColor = styles.getPropertyValue('--chart-axis').trim() || 'rgba(148,163,184,.35)';

    if (!this.series.length || !this.labels.length) {
      ctx.fillStyle = textColor;
      ctx.font = '13px ui-sans-serif, system-ui, sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText('No data yet', width / 2, height / 2);
      return;
    }

    const pad = this.options.padding;
    const plotLeft = pad.left;
    const plotRight = width - pad.right;
    const plotTop = pad.top;
    const plotBottom = height - pad.bottom;
    const plotWidth = Math.max(1, plotRight - plotLeft);
    const plotHeight = Math.max(1, plotBottom - plotTop);

    let min = Infinity;
    let max = -Infinity;
    const consider = (value) => {
      if (value !== null && Number.isFinite(value)) {
        min = Math.min(min, value);
        max = Math.max(max, value);
      }
    };
    for (const series of this.series) {
      if (series.band) {
        series.band[0].forEach(consider);
        series.band[1].forEach(consider);
      } else if (series.values) {
        series.values.forEach(consider);
      }
    }
    if (!Number.isFinite(min) || !Number.isFinite(max)) return;
    if (min === max) {
      min -= Math.abs(min) * 0.05 + 1;
      max += Math.abs(max) * 0.05 + 1;
    }
    const range = max - min;
    min -= range * 0.06;
    max += range * 0.06;
    const scaleY = (value) => plotBottom - ((value - min) / (max - min)) * plotHeight;
    const scaleX = (index) => plotLeft + (index / Math.max(1, this.labels.length - 1)) * plotWidth;

    // Horizontal grid and y labels.
    ctx.strokeStyle = gridColor;
    ctx.lineWidth = 1;
    ctx.fillStyle = textColor;
    ctx.font = '11px ui-monospace, SFMono-Regular, Menlo, monospace';
    ctx.textAlign = 'right';
    ctx.textBaseline = 'middle';
    const ticks = 5;
    for (let i = 0; i <= ticks; i += 1) {
      const value = min + ((max - min) * i) / ticks;
      const y = scaleY(value);
      ctx.beginPath();
      ctx.moveTo(plotLeft, y);
      ctx.lineTo(plotRight, y);
      ctx.stroke();
      ctx.fillText(this.options.yFormat(value), plotLeft - 8, y);
    }

    // X labels.
    ctx.textAlign = 'center';
    ctx.textBaseline = 'top';
    const xTicks = Math.min(6, this.labels.length);
    for (let i = 0; i < xTicks; i += 1) {
      const index = Math.round((i / Math.max(1, xTicks - 1)) * (this.labels.length - 1));
      const x = scaleX(index);
      ctx.fillText(this.options.xFormat(this.labels[index]), x, plotBottom + 9);
    }

    // Axis.
    ctx.strokeStyle = axisColor;
    ctx.beginPath();
    ctx.moveTo(plotLeft, plotTop);
    ctx.lineTo(plotLeft, plotBottom);
    ctx.lineTo(plotRight, plotBottom);
    ctx.stroke();

    // Bands first.
    for (const series of this.series) {
      if (!series.band) continue;
      const [lower, upper] = series.band;
      ctx.beginPath();
      let started = false;
      for (let i = 0; i < this.labels.length; i += 1) {
        if (!Number.isFinite(upper[i])) continue;
        const x = scaleX(i);
        const y = scaleY(upper[i]);
        if (!started) { ctx.moveTo(x, y); started = true; } else ctx.lineTo(x, y);
      }
      for (let i = this.labels.length - 1; i >= 0; i -= 1) {
        if (!Number.isFinite(lower[i])) continue;
        ctx.lineTo(scaleX(i), scaleY(lower[i]));
      }
      ctx.closePath();
      ctx.fillStyle = series.color;
      ctx.globalAlpha = series.opacity ?? 0.18;
      ctx.fill();
      ctx.globalAlpha = 1;
    }

    // Lines.
    for (const series of this.series) {
      if (series.band || !series.values) continue;
      ctx.beginPath();
      let started = false;
      series.values.forEach((value, i) => {
        if (!Number.isFinite(value)) {
          started = false;
          return;
        }
        const x = scaleX(i);
        const y = scaleY(value);
        if (!started) { ctx.moveTo(x, y); started = true; } else ctx.lineTo(x, y);
      });
      ctx.strokeStyle = series.color;
      ctx.lineWidth = series.width ?? 2;
      ctx.setLineDash(series.dashed ? [5, 4] : []);
      ctx.globalAlpha = series.opacity ?? 1;
      ctx.lineJoin = 'round';
      ctx.lineCap = 'round';
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.globalAlpha = 1;

      if (series.area) {
        const gradient = ctx.createLinearGradient(0, plotTop, 0, plotBottom);
        gradient.addColorStop(0, `${series.color}55`);
        gradient.addColorStop(1, `${series.color}05`);
        ctx.beginPath();
        let first = null;
        let last = null;
        series.values.forEach((value, i) => {
          if (!Number.isFinite(value)) return;
          if (first === null) first = i;
          last = i;
        });
        if (first !== null) {
          ctx.moveTo(scaleX(first), plotBottom);
          for (let i = first; i <= last; i += 1) {
            if (Number.isFinite(series.values[i])) ctx.lineTo(scaleX(i), scaleY(series.values[i]));
          }
          ctx.lineTo(scaleX(last), plotBottom);
          ctx.closePath();
          ctx.fillStyle = gradient;
          ctx.fill();
        }
      }
    }

    // Scatter points (used for the current portfolio on the frontier).
    for (const series of this.series) {
      if (!series.points || !series.values) continue;
      series.values.forEach((value, i) => {
        if (!Number.isFinite(value)) return;
        ctx.beginPath();
        ctx.arc(scaleX(i), scaleY(value), series.pointRadius ?? 5, 0, Math.PI * 2);
        ctx.fillStyle = series.color;
        ctx.fill();
        ctx.strokeStyle = styles.getPropertyValue('--chart-bg').trim() || '#0b1220';
        ctx.lineWidth = 2;
        ctx.stroke();
      });
    }

    // Vertical event markers (e.g. the forecast boundary).
    for (const marker of this.markers) {
      if (!Number.isFinite(marker.index)) continue;
      const x = scaleX(marker.index);
      ctx.strokeStyle = marker.color || axisColor;
      ctx.setLineDash([4, 5]);
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(x, plotTop);
      ctx.lineTo(x, plotBottom);
      ctx.stroke();
      ctx.setLineDash([]);
      if (marker.label) {
        ctx.fillStyle = marker.color || textColor;
        ctx.font = '10px ui-monospace, SFMono-Regular, Menlo, monospace';
        ctx.textAlign = 'left';
        ctx.textBaseline = 'bottom';
        ctx.fillText(marker.label, Math.min(x + 5, plotRight - 48), plotTop + 11);
      }
    }

    // Compact legend.
    if (this.options.showLegend) {
      const visible = this.series.filter((series) => !series.silent && (series.values || series.band));
      let cursor = plotLeft;
      const y = Math.max(10, plotTop - 12);
      ctx.font = '10px ui-sans-serif, system-ui, sans-serif';
      ctx.textAlign = 'left';
      ctx.textBaseline = 'middle';
      for (const series of visible.slice(0, 6)) {
        const label = series.name || '';
        const width = ctx.measureText(label).width;
        ctx.fillStyle = series.color;
        ctx.beginPath();
        ctx.arc(cursor + 3, y, 3, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = textColor;
        ctx.fillText(label, cursor + 11, y);
        cursor += width + 28;
      }
    }

    // Hover crosshair.
    if (this.hoverIndex !== null) {
      const x = scaleX(this.hoverIndex);
      ctx.strokeStyle = axisColor;
      ctx.setLineDash([3, 3]);
      ctx.beginPath();
      ctx.moveTo(x, plotTop);
      ctx.lineTo(x, plotBottom);
      ctx.stroke();
      ctx.setLineDash([]);
      for (const series of this.series) {
        if (series.band || !series.values) continue;
        const value = series.values[this.hoverIndex];
        if (!Number.isFinite(value)) continue;
        ctx.beginPath();
        ctx.arc(x, scaleY(value), 3.5, 0, Math.PI * 2);
        ctx.fillStyle = series.color;
        ctx.fill();
        ctx.strokeStyle = styles.getPropertyValue('--chart-bg').trim() || '#0b1220';
        ctx.lineWidth = 1.5;
        ctx.stroke();
      }
    }
  }

  destroy() {
    this.observer?.disconnect();
    this.canvas.removeEventListener('mousemove', this.handleMove);
    this.canvas.removeEventListener('mouseleave', this.handleLeave);
    this.tooltip.remove();
  }
}

function escapeHtml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}
