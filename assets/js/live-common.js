// =========================================================
//  WORDORA — canlı viktorina üçün ortaq funksiyalar
// =========================================================

// Kahoot tipli rənglər və simvollar (rəngi görməyənlər üçün simvol da var)
export const OPTION_STYLE = [
  { color: "#e5484d", sym: "▲" },
  { color: "#2f7ce0", sym: "◆" },
  { color: "#f5a400", sym: "●" },
  { color: "#12925c", sym: "■" },
];

// Komandalar
export const TEAMS = [
  { name: "Aslanlar", icon: "🦁", color: "#e5484d" },
  { name: "Qartallar", icon: "🦅", color: "#2f7ce0" },
  { name: "Delfinlər", icon: "🐬", color: "#12925c" },
  { name: "Ulduzlar", icon: "⭐", color: "#f5a400" },
];
export const teamLabel = (t) => (TEAMS[t] ? `${TEAMS[t].icon} ${TEAMS[t].name}` : "");

// Şəkil ünvanı: "live/..." yolu → açıq link
export function liveImg(path, supabaseUrl) {
  if (!path) return "";
  if (/^https?:\/\//i.test(path)) return path;
  return `${supabaseUrl}/storage/v1/object/public/live/${String(path).replace(/^live\//, "").split("/").map(encodeURIComponent).join("/")}`;
}

/**
 * Sualları sadə mətndən oxu. Suallar boş sətirlə ayrılır.
 *
 *   She ___ to school every day.      ← sual
 *   *goes                             ← * düzgün variant
 *   go
 *   going
 *
 *   What is the past of "go"?  [x2]   ← [x2] — ikiqat bal
 *   = went                            ← "=" — yazmalı sual (bir neçə düzgün cavab ola bilər)
 *
 *   Listen and write the word.
 *   [səs: beautiful]                  ← proyektor bu sözü səsli oxuyur (ekranda görünmür)
 *   [şəkil: live/abc.jpg]             ← şəkil
 *   [vaxt: 30]                        ← bu suala ayrıca vaxt
 *   = beautiful
 */
const TAG_RE = /\[\s*(x2|2x|⭐|ikiqat|səs|ses|sound|şəkil|sekil|image|img|vaxt|time)\s*(?::\s*([^\]]*))?\]/gi;

export function parseLive(text, time = 20) {
  const questions = [];
  const errors = [];
  const blocks = String(text || "").replace(/\r/g, "").split(/\n\s*\n/).map((b) => b.trim()).filter(Boolean);
  blocks.forEach((b, i) => {
    const n = i + 1;
    const q = { text: "", options: [], correct: -1, time };
    const answers = [];
    let qText = null;
    let correct = -1;
    for (let line of b.split("\n")) {
      line = line.trim();
      if (!line) continue;
      // teqlər (sətrin istənilən yerində ola bilər)
      line = line.replace(TAG_RE, (_, tag, val) => {
        const t = tag.toLowerCase(); val = (val || "").trim();
        if (["x2", "2x", "⭐", "ikiqat"].includes(t)) q.double = true;
        else if (["səs", "ses", "sound"].includes(t)) q.say = val || true;
        else if (["şəkil", "sekil", "image", "img"].includes(t)) { if (val) q.img = val; }
        else if (["vaxt", "time"].includes(t)) { const v = parseInt(val, 10); if (v >= 5 && v <= 120) q.time = v; else errors.push(`${n}-ci sual: vaxt 5–120 saniyə olmalıdır`); }
        return "";
      }).trim();
      if (!line) continue;
      if (qText === null) { qText = line; continue; }
      if (line.startsWith("=")) { const a = line.replace(/^=+\s*/, "").trim(); if (a) answers.push(a.slice(0, 120)); continue; }
      const isCorrect = line.startsWith("*") || line.endsWith("*");
      const t = line.replace(/^\*\s*/, "").replace(/\s*\*$/, "").replace(/^[A-Da-d][).]\s+/, "");
      if (isCorrect) { if (correct !== -1) errors.push(`${n}-ci sualda iki düzgün cavab var`); correct = q.options.length; }
      q.options.push(t);
    }
    if (qText === null) { errors.push(`${n}-ci blokda sual yoxdur (teq sualın içində olmalıdır)`); return; }
    q.text = qText.slice(0, 300);
    if (q.say === true) q.say = q.text;
    if (answers.length) {
      if (q.options.length) errors.push(`${n}-ci sual: həm variant, həm "=" cavab var — birini seç`);
      q.type = "text"; q.answers = answers.slice(0, 8); q.options = []; q.correct = -1;
    } else {
      if (q.options.length < 2) errors.push(`${n}-ci sualda ən azı 2 variant (və ya "= cavab") olmalıdır`);
      if (q.options.length > 4) errors.push(`${n}-ci sualda ən çoxu 4 variant ola bilər`);
      if (correct === -1) errors.push(`${n}-ci sualda düzgün cavabı * ilə işarələ`);
      q.options = q.options.slice(0, 4);
      q.correct = Math.max(correct, 0);
    }
    questions.push(q);
  });
  return { questions, errors };
}

// Mətnə geri çevir (redaktə üçün)
export function toLiveText(questions, defTime = null) {
  return (questions || []).map((q) => {
    const tags = [];
    if (q.double) tags.push("[x2]");
    if (q.time && defTime && q.time !== defTime) tags.push(`[vaxt: ${q.time}]`);
    const lines = [q.text + (tags.length ? "  " + tags.join(" ") : "")];
    if (q.say) lines.push(q.say === q.text ? "[səs]" : `[səs: ${q.say}]`);
    if (q.img) lines.push(`[şəkil: ${q.img}]`);
    if (q.type === "text") lines.push(...(q.answers || []).map((a) => `= ${a}`));
    else lines.push(...q.options.map((o, i) => (i === q.correct ? `*${o}` : o)));
    return lines.join("\n");
  }).join("\n\n");
}

// Ən çox rast gəlinən vaxt (redaktədə "hər suala vaxt" seçimi üçün)
export function commonTime(questions) {
  const c = {};
  for (const q of questions || []) c[q.time || 20] = (c[q.time || 20] || 0) + 1;
  return Number(Object.entries(c).sort((a, b) => b[1] - a[1])[0]?.[0] || 20);
}

// Şəkli kiçilt (ən çox 1280 px, JPEG)
export async function shrinkImage(file, max = 1280) {
  if (file.type === "image/gif") return file;
  const img = await createImageBitmap(file).catch(() => null);
  if (!img) return file;
  const k = Math.min(1, max / Math.max(img.width, img.height));
  const c = document.createElement("canvas");
  c.width = Math.round(img.width * k); c.height = Math.round(img.height * k);
  c.getContext("2d").drawImage(img, 0, 0, c.width, c.height);
  return await new Promise((r) => c.toBlob((b) => r(b || file), "image/jpeg", 0.85));
}

// ---------- Sözlərdən avtomatik viktorina ----------
const shuffle = (a) => { a = a.slice(); for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; };
const clean = (s) => String(s || "").replace(/\s+/g, " ").replace(/[\[\]*=]/g, "").trim();

/**
 * @param words  [{word, meaning}]
 * @param kinds  ["en_az","az_en","listen","spell"]
 */
export function quizFromWords(words, count = 10, kinds = ["en_az", "az_en"]) {
  const pool = shuffle(words.filter((w) => clean(w.word) && clean(w.meaning)));
  if (pool.length < 4 && kinds.some((k) => k === "en_az" || k === "az_en")) kinds = kinds.filter((k) => k === "listen" || k === "spell");
  if (!kinds.length || !pool.length) return "";
  const picks = pool.slice(0, Math.min(count, pool.length));
  return picks.map((w, i) => {
    const kind = kinds[i % kinds.length];
    const word = clean(w.word), meaning = clean(w.meaning);
    const others = (key) => shuffle(pool.filter((x) => x !== w && clean(x[key]).toLowerCase() !== clean(w[key]).toLowerCase()))
      .map((x) => clean(x[key])).filter((v, k, arr) => arr.indexOf(v) === k).slice(0, 3);
    if (kind === "en_az") return [`"${word}" sözünün mənası nədir?`, ...shuffle([`*${meaning}`, ...others("meaning")])].join("\n");
    if (kind === "az_en") return [`"${meaning}" ingiliscə necədir?`, ...shuffle([`*${word}`, ...others("word")])].join("\n");
    if (kind === "listen") return [`🔊 Dinlə və sözü yaz`, `[səs: ${word}]`, `= ${word}`].join("\n");
    return [`"${meaning}" — ingiliscə yaz`, `= ${word}`].join("\n");
  }).join("\n\n");
}
