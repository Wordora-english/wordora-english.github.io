// =========================================================
//  WORDORA — tam onlayn sınaq: sualları sadə mətndən oxu
//
//  ## Read the text and answer the questions.      ← mətn (passage) başlığı
//  Tom lives in London with his family. He ...      ← mətnin özü
//
//  What does Tom do?                                ← test sualı
//  *He is a teacher.                                ← * = düzgün variant
//  He is a doctor.
//  He is a student.
//
//  She ___ (go) to school every day.                ← açıq sual
//  = goes                                           ← düzgün cavab(lar): goes/is going
//
//  Write about your favourite hobby.                ← esse
//  = esse 70                                        ← minimum 70 söz
//
//  Bloklar boş sətirlə ayrılır.
// =========================================================

const LETTERS = "ABCDE";

export function parseOnline(text) {
  const questions = [], key = {}, passages = [], errors = [];
  let pid = null;
  const blocks = String(text || "").replace(/\r/g, "").split(/\n\s*\n/).map((b) => b.trim()).filter(Boolean);
  for (const b of blocks) {
    const lines = b.split("\n").map((l) => l.trim()).filter(Boolean);
    if (lines[0].startsWith("##")) {
      pid = `p${passages.length + 1}`;
      passages.push({ id: pid, title: lines[0].replace(/^#+\s*/, ""), text: lines.slice(1).join("\n") });
      continue;
    }
    const n = questions.length + 1;
    const qText = lines.shift().replace(/^\d{1,3}\s*[).]\s*/, "");
    const ansLine = lines.find((l) => l.startsWith("="));
    if (ansLine) {
      const a = ansLine.replace(/^=\s*/, "");
      const essay = a.match(/^(esse|essay)\s*(\d+)?/i);
      if (essay) questions.push({ n, type: "essay", points: 0, min_words: Number(essay[2] || 0), text: qText, pid });
      else if (!a) errors.push(`${n}-ci sual: "=" işarəsindən sonra cavabı yaz`);
      else { questions.push({ n, type: "open", points: 0, text: qText, pid }); key[n] = a; }
      continue;
    }
    if (lines.length < 2) { errors.push(`${n}-ci sual ("${qText.slice(0, 30)}…"): ən azı 2 variant və ya "= cavab" lazımdır`); continue; }
    if (lines.length > 5) errors.push(`${n}-ci sual: ən çoxu 5 variant (A–E) ola bilər`);
    let correct = -1;
    const opts = lines.slice(0, 5).map((l, i) => {
      const isC = l.startsWith("*") || l.endsWith("*");
      if (isC) { if (correct !== -1) errors.push(`${n}-ci sualda iki düzgün cavab var`); correct = i; }
      return l.replace(/^\*\s*/, "").replace(/\s*\*$/, "").replace(/^[A-Ea-e][).]\s+/, "");
    });
    if (correct === -1) errors.push(`${n}-ci sualda düzgün variantı * ilə işarələ`);
    questions.push({ n, type: "choice", options: LETTERS.slice(0, opts.length), points: 0, text: qText, opts, pid });
    key[n] = LETTERS[Math.max(correct, 0)];
  }
  return { questions, key, passages, errors };
}

// Sual bankı üçün: mətni ayrı-ayrı bloklara böl (mətn başlığı öz suallarına yapışıq qalır)
export function splitBlocks(text) {
  const blocks = String(text || "").replace(/\r/g, "").split(/\n\s*\n/).map((b) => b.trim()).filter(Boolean);
  const out = [];
  let pending = null;
  for (const b of blocks) {
    if (b.startsWith("##")) { if (pending) out.push(pending); pending = b; continue; }
    if (pending) { pending += "\n\n" + b; continue; }
    out.push(b);
  }
  if (pending) out.push(pending);
  return out;
}
