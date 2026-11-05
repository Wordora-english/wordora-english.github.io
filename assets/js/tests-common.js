// =========================================================
//  WORDORA — sınaqlar üçün ortaq funksiyalar
// =========================================================

export const TYPE_LABELS = {
  choice: "Test (bir variant)",
  multi: "Çoxhissəli (məs. BBAA)",
  open: "Açıq cavab (yazı)",
  essay: "Esse",
};

export const OPTION_SETS = ["AB", "ABC", "ABCD", "ABCDE"];

/**
 * Cavab açarını mətndən oxu.
 *   "1 A, 2 C, 4 BBAA, 10 went/has gone, 26 esse"
 *   Sətirlərlə də olar:  1) A   2. C   3-B
 * @returns {{questions: object[], key: object, errors: string[]}}
 */
export function parseKey(text) {
  const questions = [];
  const key = {};
  const errors = [];
  const seen = new Set();
  const tokens = String(text || "")
    .replace(/\r/g, "")
    .split(/[,;\n]+/)
    .map((t) => t.trim())
    .filter(Boolean);

  for (const tok of tokens) {
    const m = tok.match(/^(\d{1,3})\s*[).:\-–]?\s*(.+)$/);
    if (!m) { errors.push(`"${tok}" başa düşülmədi`); continue; }
    const n = Number(m[1]);
    const ans = m[2].trim();
    if (seen.has(n)) { errors.push(`${n}-ci sual iki dəfə yazılıb`); continue; }
    seen.add(n);

    if (/^(esse|essay|esse\.?)$/i.test(ans)) {
      questions.push({ n, type: "essay", points: 0, min_words: 0 });
    } else if (/^[A-Ea-e]$/.test(ans)) {
      questions.push({ n, type: "choice", options: "ABCDE", points: 0 });
      key[n] = ans.toUpperCase();
    } else if (/^[A-Ea-e]{2,10}$/.test(ans)) {
      const up = ans.toUpperCase();
      const maxLetter = up.split("").sort().pop();
      const options = OPTION_SETS.find((s) => s.includes(maxLetter)) || "ABCDE";
      questions.push({ n, type: "multi", parts: up.length, options, points: 0 });
      key[n] = up;
    } else {
      questions.push({ n, type: "open", points: 0 });
      key[n] = ans;
    }
  }
  questions.sort((a, b) => a.n - b.n);
  return { questions, key, errors };
}

// Balları bərabər payla: esse balları sabit qalır, qalan bal digər suallara bərabər bölünür
export function distributePoints(questions, total) {
  const essayPts = questions.filter((q) => q.type === "essay").reduce((s, q) => s + (Number(q.points) || 0), 0);
  const others = questions.filter((q) => q.type !== "essay");
  if (!others.length) return questions;
  const each = Math.max(total - essayPts, 0) / others.length;
  let given = 0;
  others.forEach((q, i) => {
    if (i === others.length - 1) q.points = Math.round((total - essayPts - given) * 100) / 100;
    else { q.points = Math.round(each * 100) / 100; given += q.points; }
  });
  return questions;
}

export function totalPoints(questions) {
  return Math.round(questions.reduce((s, q) => s + (Number(q.points) || 0), 0) * 100) / 100;
}

export function wordCount(text) {
  const t = String(text || "").trim();
  return t ? t.split(/\s+/).length : 0;
}

export function fmtNum(x) {
  if (x === null || x === undefined || x === "") return "—";
  const n = Number(x);
  return Number.isInteger(n) ? String(n) : n.toFixed(2).replace(/\.?0+$/, "");
}

export function fmtDuration(min) {
  if (min < 60) return `${min} dəq`;
  const h = Math.floor(min / 60), m = min % 60;
  return m ? `${h} saat ${m} dəq` : `${h} saat`;
}

// datetime-local <-> ISO
export function toLocalInput(iso) {
  if (!iso) return "";
  const d = new Date(iso);
  const pad = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}
export function fromLocalInput(v) {
  return v ? new Date(v).toISOString() : null;
}

// Sınağın indiki vəziyyəti (şagird üçün)
export function testState(t, attempt, now = Date.now()) {
  if (attempt) {
    if (attempt.status === "in_progress") return "in_progress";
    return "done";      // submitted / graded / expired
  }
  if (t.starts_at && now < new Date(t.starts_at).getTime()) return "upcoming";
  if (t.ends_at && now >= new Date(t.ends_at).getTime()) return "closed";
  return "open";
}
