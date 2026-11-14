// =========================================================
//  WORDORA — sınaq zamanı əlavə qoruma
//  1. Tam ekran: sınaq tam ekranda yazılır; çıxanda suallar örtülür.
//  2. Fokus itməsi: səhifə ekranda qalsa da, şagird üzən pəncərəyə,
//     yan panelə (Edge panel), Gemini və s. toxunanda brauzer fokusu itirir —
//     suallar dərhal gizlənir, 3 saniyədən çox davam edərsə pozuntu sayılır.
//  3. Ekranın bölünməsi / kiçik pəncərə (telefonda): suallar gizlənir, pozuntu.
//  4. Kənarda keçən vaxt: şagird qayıdanda pozuntuya "X saniyə kənarda" yazılır —
//     1-2 saniyə təsadüf ola bilər, 20+ saniyə isə həqiqi keçiddir.
//  Brauzer ekran şəklini (screenshot) qadağan edə bilməz — amma şagird başqa
//  proqrama toxunan kimi suallar ekrandan silinir və müəllimə xəbər gedir.
// =========================================================

const FOCUS_GRACE = 3000;   // fokus bu qədər itərsə — pozuntu
const SPLIT_GRACE = 2000;
const FS_GRACE = 6000;      // tam ekrana qayıtmaq üçün vaxt

const root = document.documentElement;
const fsSupported = !!(root.requestFullscreen || root.webkitRequestFullscreen) &&
                    !!(document.fullscreenEnabled || document.webkitFullscreenEnabled);
const isFs = () => !!(document.fullscreenElement || document.webkitFullscreenElement);
const touch = matchMedia("(pointer: coarse)").matches;

export function enterFullscreen() {
  if (!fsSupported || isFs()) return;
  try {
    const p = root.requestFullscreen ? root.requestFullscreen({ navigationUI: "hide" }) : root.webkitRequestFullscreen();
    p?.catch?.(() => {});
  } catch {}
}
export function exitFullscreen() {
  try { if (isFs()) (document.exitFullscreen || document.webkitExitFullscreen).call(document)?.catch?.(() => {}); } catch {}
}

/**
 * @param {{report: (kind:string, details?:string, label?:string) => void}} guard
 */
export function startExamGuard(guard) {
  let stopped = false, wasFs = isFs(), lastReport = 0, pausedUntil = 0, awayStart = 0;
  const timers = {};
  const shield = document.createElement("div");
  shield.className = "exam-shield hidden";
  shield.innerHTML = `<div class="exam-shield-box"><div class="ico"></div><h2></h2><p></p><button class="btn btn-primary btn-block hidden">⛶ Tam ekranda davam et</button></div>`;
  document.body.appendChild(shield);
  const btn = shield.querySelector("button");
  btn.addEventListener("click", () => { enterFullscreen(); window.focus(); update(); });

  const state = { focus: false, split: false, fs: false };

  function report(kind, details, label) {
    if (stopped) return;
    lastReport = Date.now();
    guard?.report?.(kind, details, label);
  }
  function arm(name, ms, fn) { if (!timers[name]) timers[name] = setTimeout(() => { timers[name] = null; fn(); }, ms); }
  function disarm(name) { clearTimeout(timers[name]); timers[name] = null; }

  const typing = () => { const a = document.activeElement; return !!a && (a.tagName === "TEXTAREA" || (a.tagName === "INPUT" && a.type !== "button")); };

  function splitNow() {
    if (!touch) return false;
    const sw = Math.min(screen.width, screen.availWidth || screen.width);
    const sh = Math.min(screen.height, screen.availHeight || screen.height);
    const landscape = innerWidth > innerHeight;
    const fullW = landscape ? Math.max(sw, sh) : Math.min(sw, sh);
    const fullH = landscape ? Math.min(sw, sh) : Math.max(sw, sh);
    if (innerWidth < fullW * 0.8) return true;                     // yan-yana bölünmə / kiçik pəncərə
    if (!typing() && innerHeight < fullH * 0.55) return true;      // üst-alt bölünmə (klaviatura açıq deyilsə)
    return false;
  }

  function update() {
    if (stopped) return;
    if (Date.now() < pausedUntil) {   // kamera icazəsi pəncərəsi açıqdır — qısa müddət yoxlamırıq
      Object.keys(timers).forEach(disarm);
      document.body.classList.remove("exam-shielded");
      shield.classList.add("hidden");
      return;
    }
    const visible = document.visibilityState === "visible";
    state.focus = visible && !document.hasFocus();
    state.split = visible && splitNow();
    state.fs = visible && fsSupported && !isFs();
    if (isFs()) wasFs = true;

    // pozuntu taymerləri
    if (state.focus) arm("focus", FOCUS_GRACE, () => {
      if (!document.hasFocus() && document.visibilityState === "visible")
        report("tab_switch", "Səhifə ekranda idi, amma başqa proqram / üzən pəncərə / yan panel açıldı", "Sınaq zamanı başqa proqram və ya üzən pəncərə açıldı");
    }); else disarm("focus");
    if (state.split) arm("split", SPLIT_GRACE, () => {
      if (splitNow()) report("tab_switch", `Ekran bölündü / kiçik pəncərə (${innerWidth}×${innerHeight})`, "Sınaq zamanı ekran bölündü (iki proqram birlikdə)");
    }); else disarm("split");
    if (state.fs && wasFs) arm("fs", FS_GRACE, () => {
      if (!isFs() && Date.now() - lastReport > 15000 && document.visibilityState === "visible")
        report("tab_switch", "Tam ekrandan çıxıb qayıtmadı", "Sınaq zamanı tam ekrandan çıxıldı");
    }); else disarm("fs");

    // kənarda keçən vaxt: başqa proqram / tab / bölünmüş ekran / tam ekrandan çıxma
    const awayNow = !visible || state.focus || state.split || (state.fs && wasFs);
    if (awayNow && !awayStart) awayStart = Date.now();
    else if (!awayNow && awayStart) {
      const s = Math.round((Date.now() - awayStart) / 1000);
      awayStart = 0;
      if (s >= 2) setTimeout(() => guard?.reportAway?.(s), 2500);   // pozuntu əvvəlcə yazılsın
    }

    // örtük
    const on = state.focus || state.split || state.fs;
    document.body.classList.toggle("exam-shielded", on);
    shield.classList.toggle("hidden", !on);
    if (!on) return;
    const [ico, title, text, showBtn] =
      state.focus ? ["👀", "Sınaq səhifəsinə qayıt", "Başqa proqrama, üzən pəncərəyə və ya yan panelə keçmək olmaz. Suallar gizlədildi. 3 saniyədən çox davam etsə, pozuntu sayılacaq.", false]
      : state.split ? ["📱", "Ekranı bölmək olmaz", "Sınağı yalnız tam ekranda, başqa proqram açmadan yaza bilərsən. Bölünmüş ekranı və ya kiçik pəncərəni bağla.", false]
      : ["⛶", "Sınaq tam ekranda yazılır", wasFs ? `Tam ekrandan çıxdın. ${FS_GRACE / 1000} saniyə ərzində qayıtmasan, pozuntu sayılacaq.` : "Davam etmək üçün aşağıdakı düyməni bas.", true];
    shield.querySelector(".ico").textContent = ico;
    shield.querySelector("h2").textContent = title;
    shield.querySelector("p").textContent = text;
    btn.classList.toggle("hidden", !showBtn);
  }

  const evs = [
    [window, "blur"], [window, "focus"], [window, "resize"], [document, "visibilitychange"],
    [document, "fullscreenchange"], [document, "webkitfullscreenchange"], [document, "focusin"], [document, "focusout"],
  ];
  const onEv = () => setTimeout(update, 0);
  evs.forEach(([t, e]) => t.addEventListener(e, onEv));
  const poll = setInterval(update, 800);   // bəzi telefonlarda "blur" hadisəsi gəlmir
  update();

  return {
    // Kameraya icazə soruşulanda brauzer öz pəncərəsini açır — bu vaxt pozuntu sayılmasın (ən çox 20 san.)
    pause(ms = 20000) { pausedUntil = Date.now() + Math.min(ms, 20000); awayStart = 0; update(); },
    resume() { pausedUntil = 0; update(); },
    stop() {
      stopped = true;
      clearInterval(poll);
      Object.keys(timers).forEach(disarm);
      evs.forEach(([t, e]) => t.removeEventListener(e, onEv));
      shield.remove();
      document.body.classList.remove("exam-shielded");
      exitFullscreen();
    },
  };
}
