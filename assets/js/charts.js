// =========================================================
//  WORDORA — sadə SVG qrafiklər (kitabxanasız)
// =========================================================
import { esc } from "./app.js";

/**
 * Faiz xətti qrafiki (0–100).
 * @param {{label:string, value:number, title?:string}[]} pts
 */
export function percentChart(pts, { height = 200 } = {}) {
  if (!pts.length) return '<div class="empty small">Hələ nəticə yoxdur.</div>';
  const W = 640, H = height, L = 34, R = 12, T = 14, B = 30;
  const iw = W - L - R, ih = H - T - B;
  const x = (i) => L + (pts.length === 1 ? iw / 2 : (i * iw) / (pts.length - 1));
  const y = (v) => T + ih - (Math.max(0, Math.min(100, v)) / 100) * ih;
  const grid = [0, 25, 50, 75, 100].map((g) =>
    `<line x1="${L}" x2="${W - R}" y1="${y(g)}" y2="${y(g)}" stroke="var(--line)" stroke-width="1"/>
     <text x="${L - 6}" y="${y(g) + 4}" text-anchor="end" font-size="11" fill="var(--muted)">${g}</text>`).join("");
  const path = pts.map((p, i) => `${i ? "L" : "M"}${x(i).toFixed(1)},${y(p.value).toFixed(1)}`).join(" ");
  const area = `${path} L${x(pts.length - 1).toFixed(1)},${y(0)} L${x(0).toFixed(1)},${y(0)} Z`;
  const step = Math.ceil(pts.length / 8);
  const dots = pts.map((p, i) => `
    <circle cx="${x(i)}" cy="${y(p.value)}" r="4.5" fill="var(--card)" stroke="#5b4fe0" stroke-width="2.5"><title>${esc(p.title || p.label)}: ${Math.round(p.value)}%</title></circle>
    ${i % step === 0 || i === pts.length - 1 ? `<text x="${x(i)}" y="${H - 10}" text-anchor="middle" font-size="11" fill="var(--muted)">${esc(p.label)}</text>` : ""}`).join("");
  return `<svg viewBox="0 0 ${W} ${H}" width="100%" role="img" aria-label="Nəticələrin qrafiki" style="display:block;max-height:${H + 20}px">
    <defs><linearGradient id="pc-g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#7b4fe0" stop-opacity=".28"/><stop offset="1" stop-color="#7b4fe0" stop-opacity="0"/></linearGradient></defs>
    ${grid}<path d="${area}" fill="url(#pc-g)"/><path d="${path}" fill="none" stroke="#5b4fe0" stroke-width="3" stroke-linejoin="round" stroke-linecap="round"/>${dots}</svg>`;
}

/** Üfüqi zolaqlar: [{label, value, max}] */
export function barList(rows, { unit = "" } = {}) {
  if (!rows.length) return '<div class="empty small">Məlumat yoxdur.</div>';
  const max = Math.max(...rows.map((r) => r.max ?? r.value), 1);
  return `<div class="bars">${rows.map((r) => `
    <div class="bar-row"><span class="bar-l">${esc(r.label)}</span>
      <span class="bar-t"><span class="bar-f" style="width:${Math.max(2, (r.value / max) * 100)}%"></span></span>
      <span class="bar-v">${esc(String(r.display ?? r.value))}${unit}</span></div>`).join("")}</div>`;
}
