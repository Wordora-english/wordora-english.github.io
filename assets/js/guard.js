// =========================================================
//  WORDORA — qoruma (yalnız təsdiqlənmiş şagirdlər üçün işləyir)
//  • F12 / developer paneli və düymələri
//  • PrintScreen (kompüterdə)
//  • Sınaq zamanı başqa tab-a keçid (tabSwitch: true olanda)
//  • Bir hesab = eyni anda bir cihaz
//  Hər pozuntu serverdə qeyd olunur, müəllimə Telegram-la gedir;
//  limitdən sonra hesab avtomatik bloklanır.
// =========================================================
import { sb, toast, esc } from "./app.js";

export const VIOLATION_LABELS = {
  devtools: "Developer paneli (F12) açıldı",
  devtools_key: "F12 / developer düymələri basıldı",
  printscreen: "Ekran şəkli düyməsi basıldı",
  tab_switch: "Sınaq zamanı başqa tab, proqram və ya pəncərəyə keçid",
  second_device: "Hesaba ikinci cihazdan giriş",
};

const SESSION_KEY = (uid) => `wd_session_${uid}`;

// Girişdən sonra çağırılır — bu cihaz hesabın "sahibi" olur
export async function claimSession(uid) {
  try {
    const { data, error } = await sb.rpc("claim_session");
    if (!error && data) localStorage.setItem(SESSION_KEY(uid), data);
  } catch { /* localStorage bağlı ola bilər */ }
}

function modal({ icon, title, text, button = "Anladım", danger = false, onClose }) {
  document.querySelector(".wd-modal")?.remove();
  const el = document.createElement("div");
  el.className = "wd-modal";
  el.innerHTML = `
    <div class="wd-modal-box ${danger ? "danger" : ""}" role="alertdialog" aria-modal="true">
      <div class="wd-modal-ico">${icon}</div>
      <h2>${esc(title)}</h2>
      <p>${text}</p>
      <button class="btn ${danger ? "btn-bad" : "btn-primary"} btn-block">${esc(button)}</button>
    </div>`;
  document.body.appendChild(el);
  el.querySelector("button").addEventListener("click", () => { el.remove(); onClose?.(); });
}

export function startGuard({ me, page = location.pathname.split("/").pop(), tabSwitch = false, onBlocked } = {}) {
  if (!sb || !me || me.role === "admin" || me.status !== "approved") return { stop() {} };

  let lastReport = 0;
  let stopped = false;
  const timers = [];

  async function report(kind, details = "", label = "") {
    if (stopped) return;
    const now = Date.now();
    if (kind !== "second_device" && now - lastReport < 4000) return;   // eyni anda təkrar siqnal
    lastReport = now;
    let res;
    try {
      const { data, error } = await sb.rpc("report_violation", { p_kind: kind, p_details: details, p_page: page });
      if (error) throw error;
      res = data;
    } catch { return; }
    if (!res || res.ignored) return;

    if (res.blocked) {
      stop();
      modal({
        icon: "🔒", danger: true, title: "Hesabın bloklandı",
        text: `${esc(label || VIOLATION_LABELS[kind] || kind)}.<br>Xəbərdarlıq limiti keçildi. Hesabını yalnız müəllim aça bilər.`,
        onClose: () => (onBlocked ? onBlocked() : (location.href = "portal.html")),
      });
    } else if (res.counted) {
      const left = Math.max(res.max - res.warnings, 0);
      modal({
        icon: "⚠️", title: `Xəbərdarlıq ${res.warnings}/${res.max}`,
        text: `<b>${esc(label || VIOLATION_LABELS[kind] || kind)}.</b><br>Bu hərəkət qeyd olundu və müəllimə bildirildi.<br>` +
              (left === 0 ? "<b>Növbəti pozuntuda hesabın avtomatik bloklanacaq.</b>"
                          : `Daha ${left} xəbərdarlıqdan sonra hesabın bloklanacaq.`),
      });
    }
  }

  // ---------- 1. Developer düymələri ----------
  const onKey = (e) => {
    const k = (e.key || "").toLowerCase();
    const ctrl = e.ctrlKey || e.metaKey;
    const devKey =
      e.key === "F12" ||
      (ctrl && e.shiftKey && ["i", "j", "c", "k"].includes(k)) ||
      (e.metaKey && e.altKey && ["i", "j", "c", "u"].includes(k)) ||
      (ctrl && k === "u");
    if (devKey) {
      e.preventDefault();
      e.stopPropagation();
      report("devtools_key", e.key + (e.shiftKey ? "+Shift" : "") + (ctrl ? "+Ctrl" : ""));
    }
  };
  const onKeyUp = (e) => { if (e.key === "PrintScreen") report("printscreen"); };
  const onCtx = (e) => e.preventDefault();
  document.addEventListener("keydown", onKey, true);
  document.addEventListener("keyup", onKeyUp, true);
  document.addEventListener("contextmenu", onCtx);

  // ---------- 2. Developer paneli açıqdırmı? ----------
  // "debugger" yalnız panel açıq olanda dayanır — dayanma vaxtı ölçülür.
  timers.push(setInterval(() => {
    const t = performance.now();
    // eslint-disable-next-line no-debugger
    debugger;
    if (performance.now() - t > 150) report("devtools", "panel açıq");
  }, 2500));

  // ---------- 3. Başqa tab (yalnız sınaqda) ----------
  const onVis = () => { if (tabSwitch && document.visibilityState === "hidden") report("tab_switch"); };
  document.addEventListener("visibilitychange", onVis);

  // ---------- 4. Bir hesab = bir cihaz ----------
  const key = SESSION_KEY(me.id);
  let token = null;
  try { token = localStorage.getItem(key); } catch {}
  (async () => {
    if (!token) { await claimSession(me.id); try { token = localStorage.getItem(key); } catch {} }
  })();
  async function checkSession() {
    if (stopped || !token || document.visibilityState === "hidden") return;
    const { data, error } = await sb.rpc("check_session", { p_token: token });
    if (error || data !== false) return;
    stop();
    await report("second_device", "köhnə cihaz çıxarıldı");
    try { localStorage.removeItem(key); } catch {}
    await sb.auth.signOut();
    modal({
      icon: "📱", danger: true, title: "Başqa cihazdan daxil olundu",
      text: "Hesabına başqa cihazdan giriş edildi. Bir hesab eyni anda yalnız bir cihazda işləyə bilər.<br>Bu sən deyilsənsə, dərhal müəllimə xəbər ver.",
      onClose: () => (location.href = "login.html"),
    });
  }
  timers.push(setInterval(checkSession, 30000));
  document.addEventListener("visibilitychange", checkSession);

  function stop() {
    stopped = true;
    timers.forEach(clearInterval);
    document.removeEventListener("keydown", onKey, true);
    document.removeEventListener("keyup", onKeyUp, true);
    document.removeEventListener("visibilitychange", onVis);
  }

  // Şagird sınağa qayıdanda: son pozuntuya "neçə saniyə kənarda qaldı" yazılır
  async function reportAway(seconds) {
    if (stopped) return;
    try { await sb.rpc("report_away", { p_seconds: Math.round(seconds) }); } catch {}
  }

  return { stop, report, reportAway };
}

// Tor xətası gələndə göstərilən ekran
export function isTorError(err) {
  return /tor_blocked/i.test(err?.message || "") || /tor_blocked/i.test(err?.hint || "");
}
export function torScreen(container) {
  container.innerHTML = `
    <div class="card narrow state blocked" style="margin:24px auto">
      <div class="big-ico">🧅</div>
      <h1 style="font-size:1.5rem">Tor ilə giriş qadağandır</h1>
      <p class="muted">Bu sayta Tor Browser və ya Tor şəbəkəsi ilə daxil olmaq olmaz. Adi brauzerdən (Chrome, Safari, Firefox) daxil ol.</p>
    </div>`;
}
