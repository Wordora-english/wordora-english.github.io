// =========================================================
//  WORDORA — buraxılış imtahanına geri sayım
//  Tarixi dəyişmək üçün yalnız EXAM_DATE sətrini dəyiş.
// =========================================================
export const EXAM_DATE = "2027-03-07T00:00:00+04:00";   // Bakı vaxtı
export const EXAM_LABEL = "7 mart 2027";

const TIPS = [
  (d) => `Hər gün 10 söz öyrənsən, imtahana qədər ~${(d * 10).toLocaleString("az")} söz biləcəksən! 📚`,
  (d) => `Həftədə 2 sınaq yazsan, imtahana qədər ~${Math.max(1, Math.round((d / 7) * 2))} sınaq təcrübən olacaq ✍️`,
  () => "Hər gün azca — imtahan günü çox rahat 💪",
  () => "Səhvlərindən öyrən: hər sınaqdan sonra cavablarına bax 🔍",
  () => "Esse yazmağı unutma — hər həftə bir esse yaz ✨",
];

const pad = (n) => String(n).padStart(2, "0");

export function examCountdown(el) {
  if (!el) return;
  const target = new Date(EXAM_DATE).getTime();
  el.classList.add("exam-cd");
  el.innerHTML = `
    <div class="ecd-title">🎓 Buraxılış imtahanına təxmini qalan vaxt</div>
    <div class="ecd-boxes">
      <div class="ecd-box"><b data-k="d">–</b><span>gün</span></div>
      <div class="ecd-box"><b data-k="h">–</b><span>saat</span></div>
      <div class="ecd-box"><b data-k="m">–</b><span>dəqiqə</span></div>
      <div class="ecd-box"><b data-k="s">–</b><span>saniyə</span></div>
    </div>
    <div class="ecd-date">📅 ${EXAM_LABEL} · təxmini tarix</div>
    <div class="ecd-tip"></div>`;
  const q = (k) => el.querySelector(`[data-k="${k}"]`);
  const tip = el.querySelector(".ecd-tip");
  let tipIdx = new Date().getDate() % TIPS.length;
  const tick = () => {
    const ms = target - Date.now();
    if (ms <= 0) {
      el.innerHTML = `<div class="ecd-title">🍀 Buraxılış imtahanı vaxtıdır!</div><div class="ecd-done">Hamınıza uğurlar! Siz bacararsınız 💪</div>`;
      clearInterval(t1); clearInterval(t2);
      return;
    }
    const s = Math.floor(ms / 1000);
    q("d").textContent = Math.floor(s / 86400);
    q("h").textContent = pad(Math.floor((s % 86400) / 3600));
    q("m").textContent = pad(Math.floor((s % 3600) / 60));
    q("s").textContent = pad(s % 60);
  };
  const showTip = () => {
    const days = Math.max(0, Math.floor((target - Date.now()) / 86400000));
    tip.textContent = TIPS[tipIdx % TIPS.length](days);
    tipIdx++;
  };
  tick(); showTip();
  const t1 = setInterval(tick, 1000);
  const t2 = setInterval(showTip, 12000);
}
