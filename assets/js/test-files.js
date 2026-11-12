// =========================================================
//  WORDORA — sınaq faylları
//  • esse şəkli: kiçiltmə, yükləmə, böyüdüb baxmaq
//  • sınağı (PDF) şagirdin adı yazılmış şəkildə yükləmək
//  • sınağın fayllarını silmək (ballar qalır)
// =========================================================
import { sb, esc, toast } from "./app.js";

export const MAX_ESSAY_PHOTOS = 6;

// Şəkli kiçilt (telefon şəkli 3–8 MB olur → ~300 KB). Alınmasa, orijinalı qaytarır.
export async function compressImage(file, maxSide = 1800, quality = 0.82) {
  try {
    const bmp = await createImageBitmap(file, { imageOrientation: "from-image" });
    const k = Math.min(1, maxSide / Math.max(bmp.width, bmp.height));
    const c = document.createElement("canvas");
    c.width = Math.round(bmp.width * k); c.height = Math.round(bmp.height * k);
    const ctx = c.getContext("2d");
    ctx.fillStyle = "#fff"; ctx.fillRect(0, 0, c.width, c.height);
    ctx.drawImage(bmp, 0, 0, c.width, c.height);
    bmp.close?.();
    const blob = await new Promise((r) => c.toBlob(r, "image/jpeg", quality));
    if (blob && blob.size > 0) return blob;
  } catch {}
  if (/^image\/(jpeg|png|webp)$/.test(file.type) && file.size <= 5 * 1024 * 1024) return file;
  throw new Error("Bu şəkli açmaq olmadı. Kameradan yenidən çək (JPG).");
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
