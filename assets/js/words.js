// =========================================================
//  WORDORA — sözlər: tələffüz, günün sözü, mətndən oxuma
// =========================================================

// ---------- Tələffüz (brauzerin pulsuz səsi) ----------
let voice = null;
function pickVoice() {
  const vs = window.speechSynthesis?.getVoices?.() || [];
  voice = vs.find((v) => /en[-_]GB/i.test(v.lang) && /female|google|samantha|serena|kate/i.test(v.name))
       || vs.find((v) => /en[-_]GB/i.test(v.lang))
       || vs.find((v) => /en[-_]US/i.test(v.lang))
       || vs.find((v) => /^en/i.test(v.lang)) || null;
}
if ("speechSynthesis" in window) { pickVoice(); speechSynthesis.onvoiceschanged = pickVoice; }

export const canSpeak = () => "speechSynthesis" in window;

export function speak(text, { rate = 0.9 } = {}) {
  if (!canSpeak() || !text) return false;
  speechSynthesis.cancel();
  const u = new SpeechSynthesisUtterance(text);
  u.lang = voice?.lang || "en-GB";
  if (voice) u.voice = voice;
  u.rate = rate;
  speechSynthesis.speak(u);
  return true;
}

// ---------- Günün sözü: hamı üçün eyni gündə eyni söz ----------
export function wordOfDay(words, date = new Date()) {
  if (!words.length) return null;
  const key = `${date.getFullYear()}-${date.getMonth() + 1}-${date.getDate()}`;
  let h = 2166136261;
  for (const ch of key) { h ^= ch.charCodeAt(0); h = Math.imul(h, 16777619) >>> 0; }
  const sorted = words.slice().sort((a, b) => a.id - b.id);
  return sorted[h % sorted.length];
}

/**
 * Sözləri mətndən oxu — hər sətirdə bir söz:
 *   word | tərcümə | nümunə cümlə (istəyə görə)
 *   word - tərcümə
 */
export function parseWords(text) {
  const out = [], errors = [];
  String(text || "").replace(/\r/g, "").split("\n").map((l) => l.trim()).filter(Boolean).forEach((line, i) => {
    let parts = line.split("|").map((p) => p.trim());
    if (parts.length < 2) parts = line.split(/\s+[-–—]\s+/).map((p) => p.trim());
    if (parts.length < 2 || !parts[0] || !parts[1]) { errors.push(`${i + 1}-ci sətir: "söz | tərcümə" formatında olmalıdır`); return; }
    out.push({ word: parts[0].slice(0, 80), meaning: parts[1].slice(0, 200), example: (parts[2] || "").slice(0, 300) || null });
  });
  return { words: out, errors };
}
