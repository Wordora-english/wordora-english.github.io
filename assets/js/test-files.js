// =========================================================
//  WORDORA — sınaq faylları
//  • esse şəkli: saytın içində kamera, yükləmə, böyüdüb baxmaq
//  • sınağı (PDF) şagirdin adı yazılmış şəkildə yükləmək
//  • sınağın fayllarını silmək (ballar qalır)
// =========================================================
import { sb, esc, toast } from "./app.js";

export const MAX_ESSAY_PHOTOS = 6;

// =========================================================
//  Kamera — saytın İÇİNDƏ açılır (qalereya, fayl seçmək, başqa proqram yoxdur).
//  Sınaq tam ekranda qalır, qoruma işləməyə davam edir.
// =========================================================
const CAM_CONSTRAINTS = { audio: false, video: { facingMode: { ideal: "environment" }, width: { ideal: 2560 }, height: { ideal: 1440 } } };

export function cameraError(err) {
  const n = err?.name || "";
  if (n === "NotAllowedError" || n === "SecurityError")
    return "Kameraya icazə verilməyib. Ünvan sətrindəki 🔒 (və ya ⓘ) işarəsinə toxun → Kamera → İcazə ver. Sonra yenidən bas.";
  if (n === "NotFoundError" || n === "OverconstrainedError") return "Bu cihazda kamera tapılmadı.";
  if (n === "NotReadableError") return "Kamera başqa proqramda açıqdır. O proqramı bağla və yenidən bas.";
  if (!navigator.mediaDevices?.getUserMedia) return "Bu brauzer kameranı açmağı dəstəkləmir. Chrome və ya Safari-də aç.";
  return "Kamera açılmadı: " + (err?.message || n || "naməlum xəta");
}

// Sınaqdan əvvəl: kameraya icazə al (icazə pəncərəsi sınaq zamanı çıxmasın deyə)
export async function checkCamera() {
  const st = await navigator.mediaDevices.getUserMedia(CAM_CONSTRAINTS);
  st.getTracks().forEach((t) => t.stop());
  return true;
}

/**
 * Kameranı aç, şəkil çək. Qaytarır: JPEG Blob və ya null (bağladısa).
 * @param {{beforeAsk?:()=>void, afterAsk?:()=>void, title?:string}} o
 */
export function openCamera(o = {}) {
  return new Promise((resolve) => {
    const el = document.createElement("div");
    el.className = "cam";
    el.innerHTML = `<div class="cam-top">${esc(o.title || "📷 Esseni çək")}<span class="small">Dəftəri düz tut, işıqlı yerdə çək. Yazı aydın oxunsun.</span></div>
      <div class="cam-view"><video playsinline muted autoplay></video><img alt="" class="hidden"><div class="cam-msg hidden"></div></div>
      <div class="cam-bar">
        <button type="button" class="cam-btn" data-c="close">✕ Bağla</button>
        <button type="button" class="cam-shot" data-c="shot" aria-label="Çək" disabled></button>
        <button type="button" class="cam-btn hidden" data-c="again">↺ Yenidən</button>
        <button type="button" class="cam-btn cam-ok hidden" data-c="use">✓ Göndər</button>
        <span class="cam-sp"></span>
      </div>`;
    document.body.appendChild(el);
    const video = el.querySelector("video"), img = el.querySelector("img"), msg = el.querySelector(".cam-msg");
    const btn = (c) => el.querySelector(`[data-c="${c}"]`);
    let stream = null, blob = null, done = false;

    const finish = (val) => {
      if (done) return; done = true;
      stream?.getTracks().forEach((t) => t.stop());
      if (img.src) URL.revokeObjectURL(img.src);
      el.remove();
      resolve(val);
    };
    const mode = (shot) => {
      video.classList.toggle("hidden", shot); img.classList.toggle("hidden", !shot);
      btn("shot").classList.toggle("hidden", shot); btn("close").classList.toggle("hidden", shot);
      btn("again").classList.toggle("hidden", !shot); btn("use").classList.toggle("hidden", !shot);
      el.querySelector(".cam-sp").classList.toggle("hidden", shot);
    };

    (async () => {
      o.beforeAsk?.();
      try {
        stream = await navigator.mediaDevices.getUserMedia(CAM_CONSTRAINTS);
      } catch (err) {
        msg.textContent = cameraError(err); msg.classList.remove("hidden"); video.classList.add("hidden");
        return;
      } finally { o.afterAsk?.(); }
      if (done) { stream.getTracks().forEach((t) => t.stop()); return; }
      video.srcObject = stream;
      try { await video.play(); } catch {}
      btn("shot").disabled = false;
    })();

    el.querySelector(".cam-bar").addEventListener("click", async (e) => {
      const c = e.target.closest("[data-c]")?.dataset.c;
      if (!c) return;
      if (c === "close") return finish(null);
      if (c === "use") return finish(blob);
      if (c === "again") { blob = null; mode(false); return; }
      if (c === "shot") {
        const w = video.videoWidth, h = video.videoHeight;
        if (!w || !h) return;
        const k = Math.min(1, 1800 / Math.max(w, h));
        const cv = document.createElement("canvas");
        cv.width = Math.round(w * k); cv.height = Math.round(h * k);
        cv.getContext("2d").drawImage(video, 0, 0, cv.width, cv.height);
        blob = await new Promise((r) => cv.toBlob(r, "image/jpeg", 0.85));
        if (!blob) return;
        if (img.src) URL.revokeObjectURL(img.src);
        img.src = URL.createObjectURL(blob);
        mode(true);
      }
    });
  });
}

export async function signedUrls(bucket, names, seconds = 3600) {
  if (!names.length) return {};
  const { data, error } = await sb.storage.from(bucket).createSignedUrls(names, seconds);
  if (error) return {};
  return Object.fromEntries((data || []).filter((x) => x.signedUrl).map((x) => [x.path, x.signedUrl]));
}

// Şəkillərə baxış: böyüt / kiçilt / çevir / sürüşdür
export function photoViewer(urls, start = 0) {
  let i = start, zoom = 1, rot = 0;
  const el = document.createElement("div");
  el.className = "pv";
  el.innerHTML = `<div class="pv-bar">
      <span class="pv-n"></span>
      <button data-a="out" title="Kiçilt">−</button><button data-a="in" title="Böyüt">+</button>
      <button data-a="rot" title="Çevir">⟳</button>
      ${urls.length > 1 ? '<button data-a="prev">‹</button><button data-a="next">›</button>' : ""}
      <button data-a="x" title="Bağla">✕</button></div>
    <div class="pv-stage"><div class="pv-wrap"><img alt="Esse şəkli"></div></div>`;
  document.body.appendChild(el);
  const img = el.querySelector("img"), stage = el.querySelector(".pv-stage"), wrap = el.querySelector(".pv-wrap");
  const layout = () => {
    const r = (img.naturalHeight || 4) / (img.naturalWidth || 3);   // hündürlük / en
    const side = rot % 180 !== 0;
    const shownR = side ? 1 / r : r;                                 // ekranda hündürlük / en
    const base = Math.min(stage.clientWidth, Math.max(stage.clientHeight / shownR, 600));   // böyük ekranda bütün səhifə görünsün
    const w = base * zoom;                                           // ekranda görünən en
    const h = side ? w / r : w * r;                                  // ekranda görünən hündürlük
    wrap.style.width = `${w}px`; wrap.style.height = `${h}px`;
    img.style.width = `${side ? h : w}px`; img.style.height = `${side ? w : h}px`;
    img.style.transform = `translate(-50%, -50%) rotate(${rot}deg)`;
  };
  img.onload = layout;
  addEventListener("resize", layout);
  const draw = () => {
    if (img.getAttribute("src") !== urls[i]) img.src = urls[i];
    el.querySelector(".pv-n").textContent = urls.length > 1 ? `${i + 1} / ${urls.length}` : "";
    layout();
  };
  const close = () => { el.remove(); document.removeEventListener("keydown", key); removeEventListener("resize", layout); };
  const key = (e) => { if (e.key === "Escape") close(); if (e.key === "ArrowRight") act("next"); if (e.key === "ArrowLeft") act("prev"); };
  function act(a) {
    if (a === "x") return close();
    if (a === "in") zoom = Math.min(4, zoom + 0.5);
    if (a === "out") zoom = Math.max(0.5, zoom - 0.5);
    if (a === "rot") rot = (rot + 90) % 360;
    if (a === "next") { i = (i + 1) % urls.length; zoom = 1; rot = 0; stage.scrollTo(0, 0); }
    if (a === "prev") { i = (i - 1 + urls.length) % urls.length; zoom = 1; rot = 0; stage.scrollTo(0, 0); }
    draw();
  }
  el.querySelector(".pv-bar").addEventListener("click", (e) => { const b = e.target.closest("[data-a]"); if (b) act(b.dataset.a); });
  stage.addEventListener("click", (e) => { if (e.target === stage) close(); });   // boş yerə toxunanda bağlanır
  document.addEventListener("keydown", key);
  draw();
}

export function thumbsHtml(names, urls, { removable = false } = {}) {
  return names.map((n, k) => `<span class="ess-th">
      <img src="${esc(urls[n] || "")}" alt="" data-pv="${k}" loading="lazy">
      ${removable ? `<button type="button" class="ess-del" data-del="${esc(n)}" title="Sil">✕</button>` : ""}</span>`).join("");
}

// Sınağı yüklə — hər səhifəyə şagirdin adı və kodu yazılır
export async function downloadTestFile(test, variant, me, kind = "pdf") {
  const code = variant || "A";
  const v = code === "A" ? null : (test.variants || []).find((x) => x.code === code);
  const path = kind === "pdf" ? (v ? v.pdf_path : test.pdf_path) : (v?.audio_path || test.audio_path);
  if (!path) throw new Error(kind === "pdf" ? "Bu sınağın PDF-i yoxdur" : "Bu sınaqda dinləmə yoxdur");
  const { data, error } = await sb.storage.from("tests").createSignedUrl(path, 120);
  if (error) throw new Error("Faylı yükləmək hələ açıq deyil və ya fayl silinib");
  const res = await fetch(data.signedUrl, { cache: "no-store" });
  if (!res.ok) throw new Error("Fayl açılmadı");
  const bytes = new Uint8Array(await res.arrayBuffer());
  const { stampPdf, saveBlob, safeFilename, ascii } = await import("./stamp.js");
  if (kind === "pdf") {
    const wm = { name: me.full_name, username: me.username, code: me.student_code || "", date: new Date().toLocaleDateString("az-AZ"), title: test.title };
    saveBlob(await stampPdf(bytes, wm), safeFilename(`${test.title}${code !== "A" ? ` ${code}` : ""}`, me.student_code || ""));
  } else {
    const ext = (path.split(".").pop() || "mp3").toLowerCase();
    const blob = new Blob([bytes], { type: res.headers.get("content-type") || "audio/mpeg" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `${ascii(test.title).replace(/[^A-Za-z0-9 _.-]/g, "").trim().replace(/\s+/g, "_").slice(0, 60) || "dinleme"}.${ext}`;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 30000);
  }
}

// Sınağın fayllarını sil (PDF, dinləmə, esse şəkilləri) — ballar, cavablar, şərhlər qalır
export async function testFilesInfo(testId) {
  const { data, error } = await sb.rpc("admin_test_files", { p_test: testId });
  if (error) throw error;
  return data;
}
export async function cleanTestFiles(testId, info = null) {
  info ||= await testFilesInfo(testId);
  const chunks = (arr) => Array.from({ length: Math.ceil(arr.length / 100) }, (_, k) => arr.slice(k * 100, k * 100 + 100));
  for (const c of chunks(info.tests || [])) { const { error } = await sb.storage.from("tests").remove(c); if (error) throw error; }
  for (const c of chunks((info.essays || []).map((x) => x.name))) { const { error } = await sb.storage.from("essays").remove(c); if (error) throw error; }
  const { error } = await sb.rpc("admin_mark_files_cleaned", { p_test: testId });
  if (error) throw error;
  return info;
}

// Admin paneli açılanda: vaxtı çatmış sınaqların fayllarını səssizcə sil
export async function autoCleanTests() {
  try {
    const { data, error } = await sb.rpc("admin_tests_due_clean");
    if (error || !data?.length) return 0;
    let freed = 0;
    for (const row of data) {
      const id = typeof row === "string" ? row : row.admin_tests_due_clean || Object.values(row)[0];
      try { const info = await cleanTestFiles(id); freed += Number(info.bytes) || 0; } catch {}
    }
    if (freed > 0) toast(`🧹 Bitmiş sınaqların faylları silindi — ${(freed / 1048576).toFixed(1)} MB yer boşaldı (ballar qalır)`, "ok");
    return freed;
  } catch { return 0; }
}

export const fmtMB = (b) => `${(Number(b || 0) / 1048576).toFixed(1)} MB`;
