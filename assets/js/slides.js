// =========================================================
//  WORDORA — görüntülü dərsdə PDF / şəkil göstərmək
//  Fayl səhifələri kətana (canvas) çəkilir və video kimi şagirdlərə gedir.
//  Telefonda da işləyir (ekran paylaşmağı dəstəkləməyən telefonlar üçün).
// =========================================================
const W = 1280, H = 720;

async function loadPdf(bytes) {
  const pdfjsLib = await import("../vendor/pdfjs/pdf.min.mjs");
  const VENDOR = new URL("../vendor/pdfjs/", import.meta.url).href;
  pdfjsLib.GlobalWorkerOptions.workerSrc = VENDOR + "pdf.worker.min.mjs";
  return pdfjsLib.getDocument({
    data: bytes, standardFontDataUrl: VENDOR + "standard_fonts/", cMapUrl: VENDOR + "cmaps/", cMapPacked: true,
    wasmUrl: VENDOR + "wasm/", iccUrl: VENDOR + "iccs/", isEvalSupported: false,
  }).promise;
}

const loadImage = (file) => new Promise((ok, bad) => {
  const url = URL.createObjectURL(file), img = new Image();
  img.onload = () => ok(img); img.onerror = () => bad(new Error("Şəkil açılmadı"));
  img.src = url;
});

/** @param {File[]} files  bir PDF və ya bir neçə şəkil */
export async function openSlides(files) {
  const canvas = document.createElement("canvas");
  canvas.width = W; canvas.height = H;
  const ctx = canvas.getContext("2d");
  let pages = [], pdf = null;
  const pdfFile = files.find((f) => /pdf$/i.test(f.type) || /\.pdf$/i.test(f.name));
  if (pdfFile) {
    pdf = await loadPdf(new Uint8Array(await pdfFile.arrayBuffer()));
    pages = Array.from({ length: pdf.numPages }, (_, i) => ({ pdf: i + 1 }));
  } else {
    for (const f of files.filter((f) => /^image\//.test(f.type))) pages.push({ img: await loadImage(f) });
  }
  if (!pages.length) throw new Error("PDF və ya şəkil seçin");

  let i = 0, busy = Promise.resolve();
  async function draw() {
    ctx.fillStyle = "#fff"; ctx.fillRect(0, 0, W, H);
    const pg = pages[i];
    if (pg.img) {
      const s = Math.min(W / pg.img.width, H / pg.img.height);
      ctx.drawImage(pg.img, (W - pg.img.width * s) / 2, (H - pg.img.height * s) / 2, pg.img.width * s, pg.img.height * s);
    } else {
      const page = await pdf.getPage(pg.pdf);
      const v1 = page.getViewport({ scale: 1 });
      const scale = Math.min(W / v1.width, H / v1.height);
      const vp = page.getViewport({ scale });
      const off = document.createElement("canvas");
      off.width = Math.ceil(vp.width); off.height = Math.ceil(vp.height);
      await page.render({ canvasContext: off.getContext("2d"), viewport: vp }).promise;
      ctx.drawImage(off, (W - off.width) / 2, (H - off.height) / 2);
    }
  }
  await draw();
  const stream = canvas.captureStream(5);
  const track = stream.getVideoTracks()[0];
  track.contentHint = "detail";
  // Səhifə dəyişməsə də, yeni qoşulan şagird görsün deyə hər saniyə yenidən çəkirik
  const keep = setInterval(() => { ctx.fillStyle = "rgba(255,255,255,0.004)"; ctx.fillRect(0, 0, 1, 1); }, 1000);
  const go = (n) => { const j = Math.max(0, Math.min(pages.length - 1, n)); if (j === i) return busy; i = j; busy = busy.then(draw); return busy; };
  return {
    stream, track, canvas,
    get page() { return i + 1; }, get pages() { return pages.length; },
    next: () => go(i + 1), prev: () => go(i - 1),
    stop() { clearInterval(keep); track.stop(); pdf?.destroy?.(); },
  };
}
