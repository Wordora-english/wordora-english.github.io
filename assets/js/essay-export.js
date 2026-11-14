// =========================================================
//  WORDORA — esseləri Claude ilə yoxlamaq
//  1) Bütün esselər (mətn və ya dəftər şəkilləri) bir PDF-ə yığılır.
//  2) Müəllim PDF-i Claude-a göndərir, Claude hər şagird üçün bal yazır.
//  3) Müəllim Claude-un cavabını sayta yapışdırır — ballar yazılır.
//  Hər şagirdin qısa KODU var (məs. A3F9C2) — ballar onunla uyğunlaşdırılır.
// =========================================================
import { PDFDocument } from "../vendor/pdf-lib/pdf-lib.esm.min.js";

const W = 1240, H = 1754, M = 80;   // A4, 150 dpi
const FONT = "Inter, 'Segoe UI', Roboto, Arial, sans-serif";

export const essayCode = (attemptId) => String(attemptId).replace(/-/g, "").slice(0, 6).toUpperCase();

function newPage() {
  const cv = document.createElement("canvas");
  cv.width = W; cv.height = H;
  const x = cv.getContext("2d");
  x.fillStyle = "#fff"; x.fillRect(0, 0, W, H);
  x.fillStyle = "#111"; x.textBaseline = "alphabetic";
  return { cv, x };
}

// Mətni sətirlərə böl (sözlər + əl ilə yeni sətir)
function wrap(x, text, maxW) {
  const out = [];
  for (const para of String(text || "").replace(/\r/g, "").split("\n")) {
    if (!para.trim()) { out.push(""); continue; }
    let line = "";
    for (const w of para.split(/\s+/)) {
      const t = line ? `${line} ${w}` : w;
      if (x.measureText(t).width > maxW && line) { out.push(line); line = w; }
      else line = t;
    }
    out.push(line);
  }
  return out;
}

function header(x, s, sub) {
  x.fillStyle = "#2b2a6b"; x.fillRect(0, 0, W, 130);
  x.fillStyle = "#fff"; x.font = `800 44px ${FONT}`;
  x.fillText(`KOD: ${s.code}`, M, 72);
  x.font = `600 28px ${FONT}`;
  x.fillText(`${s.name}${s.cls ? ` · ${s.cls}` : ""}`, M, 112);
  x.font = `500 24px ${FONT}`; x.textAlign = "right";
  x.fillText(sub, W - M, 72); x.textAlign = "left";
  x.fillStyle = "#111";
}

async function loadBitmap(url) {
  const res = await fetch(url, { cache: "no-store" });
  if (!res.ok) throw new Error("şəkil açılmadı");
  return createImageBitmap(await res.blob(), { imageOrientation: "from-image" });
}

/**
 * @param {object} o
 *  o.title, o.task (mövzu), o.minWords, o.maxPoints, o.rubric (string[]), o.perCrit
 *  o.students: [{ code, name, cls, words, text, photos: [url] }]
 */
export async function buildEssayPdf(o, onProgress = () => {}) {
  const pages = [];

  // ---- 1-ci səhifə: təlimat
  {
    const { cv, x } = newPage();
    x.fillStyle = "#2b2a6b"; x.fillRect(0, 0, W, 170);
    x.fillStyle = "#fff"; x.font = `800 50px ${FONT}`; x.fillText("WORDORA · Esse yoxlaması", M, 90);
    x.font = `500 28px ${FONT}`; x.fillText(o.title, M, 140);
    x.fillStyle = "#111";
    let y = 240;
    const line = (t, font = `500 28px ${FONT}`, gap = 42) => { x.font = font; for (const l of wrap(x, t, W - 2 * M)) { x.fillText(l, M, y); y += gap; } };
    line("FOR CLAUDE — grading instructions", `800 32px ${FONT}`, 50);
    line(`Task / topic: ${o.task || "(not given — infer from the essays)"}`);
    line(`Minimum words: ${o.minWords || "—"}.  Maximum essay score: ${o.maxPoints}.`);
    line(`Criteria (each max ${o.perCrit}): ${o.rubric.join(", ")}.`);
    y += 10;
    line("Reply with ONE line per student, in exactly this format (comment in Azerbaijani, 1–2 sentences, addressed to the student):", `600 28px ${FONT}`);
    x.fillStyle = "#f1f0fa"; x.fillRect(M - 10, y - 32, W - 2 * M + 20, 60 + 42);
    x.fillStyle = "#2b2a6b";
    line(`KOD | ${o.rubric.join(" | ")} | şərh`, `700 26px ui-monospace, Menlo, Consolas, monospace`);
    line(`A3F9C2 | ${o.rubric.map(() => (o.perCrit >= 3 ? "3" : "1")).join(" | ")} | Yaxşıdır, amma zaman səhvləri var.`, `500 24px ui-monospace, Menlo, Consolas, monospace`);
    x.fillStyle = "#111"; y += 20;
    line(`Students in this file: ${o.students.length}`, `700 28px ${FONT}`);
    x.font = `500 26px ${FONT}`;
    for (const s of o.students) {
      if (y > H - 80) break;
      x.fillText(`${s.code} — ${s.name}${s.cls ? ` (${s.cls})` : ""} · ${s.photos.length ? `${s.photos.length} photo(s)` : `${s.words} words`}`, M + 10, y); y += 38;
    }
    pages.push(cv);
  }

  // ---- hər şagird
  let k = 0;
  for (const s of o.students) {
    onProgress(++k, o.students.length);
    if (s.photos.length) {
      for (let i = 0; i < s.photos.length; i++) {
        const { cv, x } = newPage();
        header(x, s, `dəftər şəkli ${i + 1}/${s.photos.length}`);
        try {
          const bmp = await loadBitmap(s.photos[i]);
          const boxW = W - 2 * 40, boxH = H - 170 - 40;
          const r = Math.min(boxW / bmp.width, boxH / bmp.height);
          const w = bmp.width * r, h = bmp.height * r;
          x.drawImage(bmp, (W - w) / 2, 170 + (boxH - h) / 2, w, h);
          bmp.close?.();
        } catch {
          x.font = `600 30px ${FONT}`; x.fillText("Şəkil yüklənmədi", M, 260);
        }
        pages.push(cv);
      }
    } else {
      {
        let { cv, x } = newPage();
        header(x, s, `${s.words} söz`);
        x.font = `400 30px Georgia, 'Times New Roman', serif`;
        let y = 200;
        const lines = s.text?.trim() ? wrap(x, s.text, W - 2 * M) : ["(boş — esse yazılmayıb)"];
        for (const l of lines) {
          if (y > H - 60) {
            pages.push(cv);
            ({ cv, x } = newPage());
            header(x, s, `${s.words} söz (davamı)`);
            x.font = `400 30px Georgia, 'Times New Roman', serif`;
            y = 200;
          }
          x.fillText(l, M, y); y += 44;
        }
        pages.push(cv);
      }
    }
  }

  const pdf = await PDFDocument.create();
  for (const cv of pages) {
    const jpg = await new Promise((r) => cv.toBlob(r, "image/jpeg", 0.82));
    const img = await pdf.embedJpg(new Uint8Array(await jpg.arrayBuffer()));
    const page = pdf.addPage([595.28, 841.89]);
    page.drawImage(img, { x: 0, y: 0, width: 595.28, height: 841.89 });
  }
  return new Blob([await pdf.save()], { type: "application/pdf" });
}

/**
 * Claude-un cavabını oxu.
 * Sətir: KOD | m1 | m2 | m3 | m4 | şərh   (və ya KOD | ümumi bal | şərh)
 * @returns {{ok: Array<{code, crit, total, comment}>, bad: string[]}}
 */
export function parseGrades(text, rubric, perCrit, maxPoints) {
  const ok = [], bad = [];
  const num = (v) => { const t = String(v).trim().replace(",", "."); return /^\d+(\.\d+)?$/.test(t) ? Number(t) : null; };
  for (const raw of String(text || "").split(/\r?\n/)) {
    const line = raw.trim().replace(/^[-•]\s+/, "").replace(/^\d+[.)]\s+/, "").replace(/^\|/, "").replace(/\|$/, "");
    if (!line) continue;
    const parts = line.split("|").map((p) => p.trim().replace(/^[*`_]+|[*`_]+$/g, "").trim());
    const code = (parts[0] || "").replace(/^KOD:?\s*/i, "").replace(/[*`_\s]/g, "").toUpperCase();
    if (!/^[0-9A-F]{6}$/.test(code)) { if (/[0-9A-F]{6}/i.test(line)) bad.push(raw); continue; }
    const nums = [];
    let i = 1;
    while (i < parts.length && num(parts[i]) !== null) { nums.push(num(parts[i])); i++; }
    const comment = parts.slice(i).join(" | ").trim();
    if (nums.length === rubric.length) {
      const crit = Object.fromEntries(rubric.map((c, j) => [c, Math.min(nums[j], perCrit)]));
      const total = Math.min(Math.round(Object.values(crit).reduce((s, v) => s + v, 0) * 100) / 100, maxPoints);
      ok.push({ code, crit, total, comment });
    } else if (nums.length === 1) {
      ok.push({ code, crit: null, total: Math.min(nums[0], maxPoints), comment });
    } else bad.push(raw);
  }
  return { ok, bad };
}
