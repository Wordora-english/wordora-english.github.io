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
//  # Reading                                       ← bölmə (istəyə görə; nəticədə bölmə üzrə faiz)
//
//  Bloklar boş sətirlə ayrılır.
// =========================================================

const LETTERS = "ABCDE";

const SECTION_RE = /^#(?!#)\s*(.+)$/;

// Bölmə başlığını (# Reading) ayrıca blok kimi ayır
function toBlocks(text) {
  const out = [];
  for (const b of String(text || "").replace(/\r/g, "").split(/\n\s*\n/).map((x) => x.trim()).filter(Boolean)) {
    const lines = b.split("\n").map((l) => l.trim()).filter(Boolean);
    while (lines.length && SECTION_RE.test(lines[0])) out.push({ section: lines.shift().match(SECTION_RE)[1].trim().slice(0, 40) });
    if (lines.length) out.push({ lines });
  }
  return out;
}

export function parseOnline(text) {
  const questions = [], key = {}, passages = [], errors = [], sections = [];
  let pid = null;
  for (const blk of toBlocks(text)) {
    if (blk.section) {
      if (sections.length) sections[sections.length - 1].to = questions.length;
      sections.push({ name: blk.section, from: questions.length + 1 });
      pid = null;
      continue;
    }
    const lines = [...blk.lines];
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
  if (sections.length) sections[sections.length - 1].to = questions.length;
  return { questions, key, passages, errors, sections: sections.filter((x) => x.to >= x.from) };
}

// Sual bankı üçün: mətni ayrı-ayrı bloklara böl (mətn başlığı öz suallarına yapışıq qalır)
export function splitBlocks(text) {
  const out = [];
  let pending = null;
  const flush = () => { if (pending) out.push(pending); pending = null; };
  for (const blk of toBlocks(text)) {
    if (blk.section) { flush(); continue; }            // bölmə başlığı mətnin suallarını bitirir
    const b = blk.lines.join("\n");
    if (b.startsWith("##")) { flush(); pending = b; continue; }
    if (pending) { pending += "\n\n" + b; continue; }
    out.push(b);
  }
  flush();
  return out;
}
