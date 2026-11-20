// =========================================================
//  WORDORA — gündəlik məşq seriyası: alovun səviyyələri
//  Seriya limitsizdir; müəyyən günlərdə alovun rəngi dəyişir.
// =========================================================
export const TIERS = [
  { from: 0,   key: "seed",    name: "Toxum",          to: "",                 label: "0",    emoji: "🌱", filter: "",                                                grad: "linear-gradient(135deg,#3aa76d 0%,#12925c 55%,#0b6b5c 100%)" },
  { from: 1,   key: "fire",    name: "Alov",           to: "Alova",            label: "1",    emoji: "🔥", filter: "",                                                grad: "linear-gradient(135deg,#f97316 0%,#e5484d 55%,#b0306b 100%)" },
  { from: 7,   key: "week",    name: "Həftəlik alov",  to: "Həftəlik alova",   label: "7",    emoji: "🔥", filter: "hue-rotate(-42deg) saturate(1.6)",                grad: "linear-gradient(135deg,#e5484d 0%,#c2185b 55%,#7a1449 100%)" },
  { from: 14,  key: "blue",    name: "Mavi alov",      to: "Mavi alova",       label: "14",   emoji: "🔥", filter: "hue-rotate(185deg) saturate(1.3)",               grad: "linear-gradient(135deg,#2f9ee0 0%,#2f6fe0 50%,#3a32b5 100%)" },
  { from: 30,  key: "purple",  name: "Bənövşəyi alov", to: "Bənövşəyi alova",  label: "1 ay", emoji: "🔥", filter: "hue-rotate(240deg) saturate(1.4)",               grad: "linear-gradient(135deg,#9b5cf0 0%,#7b4fe0 50%,#b13f93 100%)" },
  { from: 60,  key: "green",   name: "Zümrüd alov",    to: "Zümrüd alova",     label: "2 ay", emoji: "🔥", filter: "hue-rotate(95deg) saturate(1.5)",                grad: "linear-gradient(135deg,#1fc98a 0%,#12925c 50%,#0b6b5c 100%)" },
  { from: 100, key: "gold",    name: "Qızıl alov",     to: "Qızıl alova",      label: "100",  emoji: "🔥", filter: "hue-rotate(28deg) saturate(2) brightness(1.3)", grad: "linear-gradient(135deg,#ffd75e 0%,#f5b400 45%,#e07a00 100%)" },
  { from: 180, key: "diamond", name: "Almaz alov",     to: "Almaz alova",      label: "6 ay", emoji: "💎", filter: "",                                                grad: "linear-gradient(135deg,#7fe3ff 0%,#2fb4e0 45%,#2f6fe0 100%)" },
  { from: 270, key: "star",    name: "Ulduz alov",     to: "Ulduz alova",      label: "9 ay", emoji: "🌟", filter: "",                                                grad: "linear-gradient(135deg,#1d1a5e 0%,#3a32b5 50%,#7b4fe0 100%)" },
  { from: 365, key: "king",    name: "Kral alovu",     to: "Kral alovuna",     label: "1 il", emoji: "👑", filter: "",                                                grad: "linear-gradient(135deg,#00c6ff 0%,#7b4fe0 30%,#e0529c 60%,#f5b400 100%)" },
];

export function tierOf(n) {
  n = Number(n) || 0;
  let i = 0;
  for (let k = 0; k < TIERS.length; k++) if (n >= TIERS[k].from) i = k;
  const t = TIERS[i], next = TIERS[i + 1] || null;
  return { ...t, index: i, next, left: next ? next.from - n : 0 };
}

// Rəngli alov (emoji + rəng filtri)
export const flame = (n, size = "") => {
  const t = tierOf(n);
  return `<span class="flame-i ${t.key}" style="${t.filter ? `filter:${t.filter};` : ""}${size ? `font-size:${size};` : ""}">${t.emoji}</span>`;
};

// Növbəti səviyyəyə nə qədər qalıb
export function nextText(n) {
  const t = tierOf(n);
  if (!t.next) { const y = Math.floor(n / 365), d = n % 365; return `Ən yüksək səviyyə — Kral alovu! 👑 ${y} il${d ? ` ${d} gün` : ""} ara vermədən`; }
  return `${t.next.to} ${t.left} gün qaldı`;
}

// Bu gün yeni səviyyəyə keçdimi?
export const tierUp = (before, after) => tierOf(after).index > tierOf(before).index && tierOf(after).index > 1;

// ---------- Gündəlik sual sayı (seriyanın gününə görə) — SQL: daily_count ----------
export const PLAN = [
  { from: 1, to: 1, n: 5, label: "1-ci gün" }, { from: 2, to: 2, n: 7, label: "2-ci gün" }, { from: 3, to: 3, n: 8, label: "3-cü gün" },
  { from: 4, to: 4, n: 9, label: "4-cü gün" }, { from: 5, to: 7, n: 10, label: "5–7-ci gün" }, { from: 8, to: 14, n: 20, label: "2-ci həftə" },
  { from: 15, to: 29, n: 25, label: "3–4-cü həftə" }, { from: 30, to: Infinity, n: 30, label: "1 aydan sonra" },
];
export const countFor = (day) => (PLAN.find((p) => day >= p.from && day <= p.to) || PLAN[0]).n;

// Azərbaycan dilində sıra şəkilçisi: 1-ci, 3-cü, 6-cı, 9-cu, 10-cu, 40-cı ...
export function ord(n) {
  n = Math.abs(Math.round(n));
  const last = n % 10, tens = n % 100;
  if (last) return `${n}-${{ 1: "ci", 2: "ci", 3: "cü", 4: "cü", 5: "ci", 6: "cı", 7: "ci", 8: "ci", 9: "cu" }[last]}`;
  if (n % 100 === 0 && n) return `${n}-cü`;
  return `${n}-${{ 10: "cu", 20: "ci", 30: "cu", 40: "cı", 50: "ci", 60: "cı", 70: "ci", 80: "ci", 90: "cı" }[tens]}`;
}

// Plan pilləsi (cari pillə vurğulanır)
export function planHtml(day) {
  return `<div class="plan">${PLAN.map((p) => `<span class="${day >= p.from && day <= p.to ? "on" : day > p.to ? "got" : ""}"><b>${p.n}</b><small>${p.label}</small></span>`).join("")}</div>`;
}
