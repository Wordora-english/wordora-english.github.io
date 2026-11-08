// =========================================================
//  WORDORA — şagird üçün sınaq hesabatı (PDF)
//  Səhifə canvas-da çəkilir (Azərbaycan hərfləri düzgün çıxır),
//  sonra PDF-ə yerləşdirilir. Bir şagird = bir səhifə.
// =========================================================
import { PDFDocument } from "../vendor/pdf-lib/pdf-lib.esm.min.js";
import { TEACHER_NAME } from "./config.js";

const W = 1654, H = 2339;          // A4, ~200 dpi
const M = 90;                      // kənar boşluq
const C = {
  indigo: "#3a32b5", violet: "#7b4fe0", text: "#1d2240", muted: "#6b7090", line: "#e3e6f3",
  ok: "#1f9d5c", okBg: "#e3f6ec", part: "#b07800", partBg: "#fff2d9", bad: "#c62828", badBg: "#fdeceb",
  emptyBg: "#f1f2f7", soft: "#f6f7fc",
};
const FONT = "Inter, Arial, sans-serif", DISPLAY = "Outfit, Inter, Arial, sans-serif";

let logoImg = null;
function loadImg(src) {
  return new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = rej; i.src = src; });
}
async function prepare() {
  try { await Promise.all(["700 60px Outfit", "600 40px Outfit", "700 30px Inter", "500 30px Inter", "400 30px Inter"].map((f) => document.fonts.load(f))); } catch {}
  if (!logoImg) { try { logoImg = await loadImg(new URL("../img/logo-icon.png", import.meta.url).href); } catch {} }
}

const fmt = (x) => { const n = Math.round(Number(x || 0) * 10) / 10; return Number.isInteger(n) ? String(n) : n.toFixed(1).replace(".", ","); };
function rr(x, X, Y, w, h, r) { x.beginPath(); x.roundRect ? x.roundRect(X, Y, w, h, r) : x.rect(X, Y, w, h); }
function clip(x, text, maxW) {
  let t = String(text ?? "");
  if (x.measureText(t).width <= maxW) return t;
  while (t.length > 1 && x.measureText(t + "…").width > maxW) t = t.slice(0, -1);
  return t + "…";
}
function wrap(x, text, maxW) {
  const lines = [];
  for (const para of String(text || "").split(/\n/)) {
    let line = "";
    for (const w of para.split(/\s+/)) {
      const test = line ? line + " " + w : w;
      if (x.measureText(test).width > maxW && line) { lines.push(line); line = w; } else line = test;
    }
    lines.push(line);
  }
  return lines;
}

/**
 * @param {object} d
 *  title, date, student{name, className, code}, variant, score, total,
 *  questions[{n,type,points}], answers{}, details{}, key{}, sections[{name,got,max,pct,pending}],
 *  essayScore, essayMax, essayReview{c:{}, comment}, paper(bool)
 */
export async function drawReport(d) {
  await prepare();
  const cv = document.createElement("canvas");
  cv.width = W; cv.height = H;
  const x = cv.getContext("2d");
  x.fillStyle = "#fff"; x.fillRect(0, 0, W, H);
  x.textBaseline = "alphabetic";

  // ---- başlıq zolağı
  const g = x.createLinearGradient(0, 0, W, 0);
  g.addColorStop(0, C.indigo); g.addColorStop(.6, C.violet); g.addColorStop(1, "#2f7ce0");
  x.fillStyle = g; x.fillRect(0, 0, W, 200);
  if (logoImg) x.drawImage(logoImg, M - 10, 40, 120, 120);
  x.fillStyle = "#fff"; x.font = `700 58px ${DISPLAY}`;
  x.fillText("WORDORA", M + 130, 118);
  x.font = `500 26px ${FONT}`; x.globalAlpha = .85;
  x.fillText("More Words • Bigger Dreams", M + 132, 156);
  x.globalAlpha = 1;
  x.textAlign = "right"; x.font = `700 40px ${DISPLAY}`;
  x.fillText("Sınaq nəticəsi", W - M, 108);
  x.font = `500 26px ${FONT}`; x.globalAlpha = .85;
  x.fillText(d.date || "", W - M, 148);
  x.globalAlpha = 1; x.textAlign = "left";

  // ---- şagird və sınaq
  let y = 290;
  x.fillStyle = C.text; x.font = `700 64px ${DISPLAY}`;
  x.fillText(clip(x, d.student?.name || "", W - 2 * M), M, y);
  y += 52;
  x.fillStyle = C.muted; x.font = `500 30px ${FONT}`;
  const meta = [d.student?.className, d.student?.code, d.variant ? `${d.variant} variantı` : null].filter(Boolean).join("   ·   ");
  x.fillText(meta, M, y);
  y += 54;
  x.fillStyle = C.text; x.font = `600 34px ${FONT}`;
  x.fillText(clip(x, d.title || "", W - 2 * M), M, y);
  y += 40;

  // ---- bal kartı
  const pct = d.total ? Math.round((Number(d.score) || 0) / d.total * 100) : 0;
  const col = pct >= 70 ? C.ok : pct >= 40 ? C.part : C.bad;
  const colBg = pct >= 70 ? C.okBg : pct >= 40 ? C.partBg : C.badBg;
  const qs = (d.questions || []).filter((q) => q.type !== "essay");
  const stat = { ok: 0, part: 0, bad: 0, empty: 0 };
  for (const q of qs) {
    const a = String(d.answers?.[q.n] ?? "").trim();
    const f = Number(d.details?.[q.n]?.frac) || 0;
    if (!a) stat.empty++; else if (f >= 1) stat.ok++; else if (f > 0) stat.part++; else stat.bad++;
  }
  const cardY = y, cardH = 230;
  x.fillStyle = colBg; rr(x, M, cardY, 520, cardH, 28); x.fill();
  x.fillStyle = col; x.font = `700 110px ${DISPLAY}`;
  x.fillText(fmt(d.score), M + 40, cardY + 135);
  const sw = x.measureText(fmt(d.score)).width;
  x.font = `600 46px ${DISPLAY}`; x.fillStyle = C.muted;
  x.fillText(`/ ${fmt(d.total)}`, M + 52 + sw, cardY + 135);
  x.font = `700 36px ${FONT}`; x.fillStyle = col;
  x.fillText(`${pct}%`, M + 40, cardY + 192);
  // faiz zolağı
  x.fillStyle = "rgba(0,0,0,.08)"; rr(x, M + 140, cardY + 172, 340, 18, 9); x.fill();
  x.fillStyle = col; rr(x, M + 140, cardY + 172, Math.max(12, 340 * pct / 100), 18, 9); x.fill();

  // say kartları
  const boxes = [["Düzgün", stat.ok, C.ok, C.okBg], ["Qismən", stat.part, C.part, C.partBg], ["Səhv", stat.bad, C.bad, C.badBg], ["Boş", stat.empty, C.muted, C.emptyBg]];
  const bx0 = M + 550, bw = (W - M - bx0 - 3 * 18) / 4;
  boxes.forEach(([lbl, n, c, bg], i) => {
    const bx = bx0 + i * (bw + 18);
    x.fillStyle = bg; rr(x, bx, cardY, bw, cardH, 24); x.fill();
    x.fillStyle = c; x.font = `700 76px ${DISPLAY}`; x.textAlign = "center";
    x.fillText(String(n), bx + bw / 2, cardY + 125);
    x.font = `600 28px ${FONT}`; x.fillText(lbl, bx + bw / 2, cardY + 180);
    x.textAlign = "left";
  });
  y = cardY + cardH + 70;

  const heading = (t) => {
    x.fillStyle = C.indigo; rr(x, M, y - 30, 8, 36, 4); x.fill();
    x.fillStyle = C.text; x.font = `700 38px ${DISPLAY}`; x.fillText(t, M + 24, y);
    y += 36;
  };

  // ---- bölmələr
  if (d.sections?.length) {
    heading("Bölmələr üzrə");
    for (const s of d.sections) {
      y += 14;
      x.fillStyle = C.text; x.font = `600 30px ${FONT}`; x.fillText(s.name, M, y + 26);
      x.textAlign = "right"; x.fillStyle = C.muted; x.font = `500 28px ${FONT}`;
      x.fillText(s.pending ? "yoxlanılır" : `${fmt(s.got)} / ${fmt(s.max)}   ·   ${s.pct}%`, W - M, y + 26);
      x.textAlign = "left";
      const c2 = s.pct >= 70 ? C.ok : s.pct >= 40 ? "#e0a100" : C.bad;
      x.fillStyle = C.line; rr(x, M, y + 42, W - 2 * M, 16, 8); x.fill();
      if (!s.pending) { x.fillStyle = c2; rr(x, M, y + 42, Math.max(10, (W - 2 * M) * s.pct / 100), 16, 8); x.fill(); }
      y += 68;
    }
    y += 40;
  }

  // ---- cavablar
  if (qs.length) {
    heading("Cavablar");
    y += 18;
    const essayBlock = (d.questions || []).some((q) => q.type === "essay") ? 330 : 0;
    const avail = H - 170 - essayBlock - y;
    const cols = qs.length > 40 ? 6 : 5;
    const rows = Math.ceil(qs.length / cols);
    const gap = 14, cw = (W - 2 * M - (cols - 1) * gap) / cols;
    const ch = Math.max(56, Math.min(96, (avail - (rows - 1) * gap) / rows));
    qs.forEach((q, i) => {
      const cx = M + (i % cols) * (cw + gap), cy = y + Math.floor(i / cols) * (ch + gap);
      const a = String(d.answers?.[q.n] ?? "").trim();
      const f = Number(d.details?.[q.n]?.frac) || 0;
      const [c, bg] = !a ? [C.muted, C.emptyBg] : f >= 1 ? [C.ok, C.okBg] : f > 0 ? [C.part, C.partBg] : [C.bad, C.badBg];
      x.fillStyle = bg; rr(x, cx, cy, cw, ch, 14); x.fill();
      const big = ch >= 80;
      x.fillStyle = C.muted; x.font = `700 ${big ? 26 : 22}px ${FONT}`;
      x.fillText(String(q.n), cx + 16, cy + (big ? 38 : 34));
      const nW = x.measureText(String(q.n)).width + 30;
      x.fillStyle = c; x.font = `700 ${big ? 32 : 26}px ${FONT}`;
      x.fillText(clip(x, a || "—", cw - nW - 16), cx + nW, cy + (big ? 40 : 35));
      if (f < 1) {
        const k = String(d.key?.[q.n] ?? "").split("/")[0];
        x.fillStyle = C.text; x.font = `500 ${big ? 24 : 20}px ${FONT}`;
        if (big) x.fillText(clip(x, `düzgün: ${k}`, cw - 32), cx + 16, cy + 76);
        else { x.textAlign = "right"; x.fillText(clip(x, `→ ${k}`, cw / 2), cx + cw - 12, cy + 35); x.textAlign = "left"; }
      }
    });
    y += rows * (ch + gap) + 50;
  }

  // ---- esse
  if ((d.questions || []).some((q) => q.type === "essay")) {
    heading(`Esse — ${d.essayScore === null || d.essayScore === undefined ? "yoxlanılır" : `${fmt(d.essayScore)} / ${fmt(d.essayMax)}`}`);
    y += 16;
    const crit = Object.entries(d.essayReview?.c || {});
    if (crit.length) {
      let cx = M;
      x.font = `600 28px ${FONT}`;
      for (const [k, v] of crit) {
        const t = `${k}: ${fmt(v)}`;
        const w = x.measureText(t).width + 40;
        x.fillStyle = C.soft; rr(x, cx, y, w, 52, 26); x.fill();
        x.fillStyle = C.text; x.fillText(t, cx + 20, y + 35);
        cx += w + 14;
      }
      y += 76;
    }
    if (d.essayReview?.comment) {
      x.font = `italic 500 30px ${FONT}`;
      const lines = wrap(x, `“${d.essayReview.comment}”`, W - 2 * M - 60).slice(0, 5);
      const bh = lines.length * 44 + 40;
      x.fillStyle = "#ece9ff"; rr(x, M, y, W - 2 * M, bh, 22); x.fill();
      x.fillStyle = C.text;
      lines.forEach((l, i) => x.fillText(l, M + 30, y + 52 + i * 44));
      y += bh + 20;
    }
  }

  // ---- alt hissə
  x.fillStyle = C.line; x.fillRect(M, H - 120, W - 2 * M, 2);
  x.fillStyle = C.muted; x.font = `500 26px ${FONT}`;
  x.fillText(`Müəllim: ${TEACHER_NAME}`, M, H - 72);
  x.textAlign = "right";
  x.fillText("wordora-english.github.io", W - M, H - 72);
  x.textAlign = "left";
  return cv;
}

// Bir neçə səhifəni bir PDF-də birləşdir
export async function reportsToPdf(canvases) {
  const pdf = await PDFDocument.create();
  for (const cv of canvases) {
    const png = await new Promise((r) => cv.toBlob(r, "image/png"));
    const img = await pdf.embedPng(new Uint8Array(await png.arrayBuffer()));
    const page = pdf.addPage([595.28, 841.89]);
    page.drawImage(img, { x: 0, y: 0, width: 595.28, height: 841.89 });
  }
  return new Blob([await pdf.save()], { type: "application/pdf" });
}

export function downloadBlob(blob, name) {
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = name;
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 4000);
}
