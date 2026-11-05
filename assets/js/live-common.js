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

/**
 * Sualları sadə mətndən oxu:
 *
 *   She ___ to school every day.
 *   *goes
 *   go
 *   going
 *
 *   What is the past of "see"?
 *   *saw
 *   seen
 *
 * Suallar boş sətirlə ayrılır. Birinci sətir — sual, qalanları — variantlar (2–4).
 * Düzgün variantın əvvəlinə * qoyulur.
 */
export function parseLive(text, time = 20) {
  const questions = [];
  const errors = [];
  const blocks = String(text || "").replace(/\r/g, "").split(/\n\s*\n/).map((b) => b.trim()).filter(Boolean);
  blocks.forEach((b, i) => {
    const lines = b.split("\n").map((l) => l.trim()).filter(Boolean);
    const qText = lines.shift();
    const options = [];
    let correct = -1;
    for (const l of lines) {
      const isCorrect = l.startsWith("*") || l.endsWith("*");
      const t = l.replace(/^\*\s*/, "").replace(/\s*\*$/, "").replace(/^[A-Da-d][).]\s+/, "");
      if (isCorrect) { if (correct !== -1) errors.push(`${i + 1}-ci sualda iki düzgün cavab var`); correct = options.length; }
      options.push(t);
    }
    if (options.length < 2) errors.push(`${i + 1}-ci sualda ən azı 2 variant olmalıdır`);
    if (options.length > 4) errors.push(`${i + 1}-ci sualda ən çoxu 4 variant ola bilər`);
    if (correct === -1) errors.push(`${i + 1}-ci sualda düzgün cavabı * ilə işarələ`);
    questions.push({ text: qText, options: options.slice(0, 4), correct: Math.max(correct, 0), time });
  });
  return { questions, errors };
}

// Mətnə geri çevir (redaktə üçün)
export function toLiveText(questions) {
  return (questions || []).map((q) =>
    [q.text, ...q.options.map((o, i) => (i === q.correct ? `*${o}` : o))].join("\n")).join("\n\n");
}
