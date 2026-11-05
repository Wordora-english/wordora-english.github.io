// =========================================================
//  WORDORA — su nişanlı PDF göstərici (səhifələr canvas-a çəkilir)
// =========================================================
import * as pdfjsLib from "../vendor/pdfjs/pdf.min.mjs";
import { drawWatermark } from "./watermark.js";

const VENDOR = new URL("../vendor/pdfjs/", import.meta.url).href;
pdfjsLib.GlobalWorkerOptions.workerSrc = VENDOR + "pdf.worker.min.mjs";

/**
 * @param {HTMLElement} container  səhifələrin yerləşəcəyi element
 * @param {Uint8Array} bytes
 * @param {{name:string, code:string, date:string}} wm
 * @param {{maxWidth?: number}} opts
 */
export async function renderPdf(container, bytes, wm, opts = {}) {
  const maxWidth = opts.maxWidth || 900;
  const pdf = await pdfjsLib.getDocument({
    data: bytes,
    standardFontDataUrl: VENDOR + "standard_fonts/",
    cMapUrl: VENDOR + "cmaps/",
    cMapPacked: true,
    wasmUrl: VENDOR + "wasm/",
    iccUrl: VENDOR + "iccs/",
    isEvalSupported: false,
  }).promise;

  let zoom = 1;
  const first = await pdf.getPage(1);
  const v1 = first.getViewport({ scale: 1 });

  const cssWidth = () => Math.round(Math.min(container.clientWidth - 16, maxWidth) * zoom);
  const size = (div, ratio) => {
    const w = cssWidth();
    div.style.width = w + "px";
    div.style.height = Math.round(w * ratio) + "px";
    div.dataset.ratio = ratio;
  };

  const observer = new IntersectionObserver((entries) => {
    for (const en of entries) if (en.isIntersecting) draw(en.target);
  }, { root: opts.scrollRoot || null, rootMargin: "600px 0px" });

  container.innerHTML = "";
  for (let n = 1; n <= pdf.numPages; n++) {
    const div = document.createElement("div");
    div.className = "page";
    div.dataset.n = n;
    div.innerHTML = `<span class="num">${n} / ${pdf.numPages}</span>`;
    size(div, v1.height / v1.width);
    container.appendChild(div);
    observer.observe(div);
  }

  async function draw(div) {
    const key = String(zoom);
    if (div.dataset.rendered === key || div.dataset.busy === key) return;
    div.dataset.busy = key;
    const page = await pdf.getPage(Number(div.dataset.n));
    const base = page.getViewport({ scale: 1 });
    size(div, base.height / base.width);
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const viewport = page.getViewport({ scale: (cssWidth() / base.width) * dpr });
    const canvas = document.createElement("canvas");
    canvas.width = Math.floor(viewport.width);
    canvas.height = Math.floor(viewport.height);
    const ctx = canvas.getContext("2d");
    await page.render({ canvasContext: ctx, viewport, canvas }).promise;
    drawWatermark(ctx, canvas.width, canvas.height, wm, Number(div.dataset.n));
    if (div.dataset.busy !== key) return;
    div.querySelector("canvas")?.remove();
    div.prepend(canvas);
    div.dataset.rendered = key;
    delete div.dataset.busy;
    page.cleanup();
  }

  return {
    pages: pdf.numPages,
    setZoom(z) {
      zoom = z;
      container.querySelectorAll(".page").forEach((div) => {
        size(div, Number(div.dataset.ratio));
        delete div.dataset.rendered;
        observer.unobserve(div); observer.observe(div);
      });
    },
    get zoom() { return zoom; },
    destroy() { observer.disconnect(); pdf.destroy(); container.innerHTML = ""; },
  };
}
