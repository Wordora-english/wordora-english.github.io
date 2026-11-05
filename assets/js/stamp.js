// =========================================================
//  WORDORA — yüklənən PDF-ə şagirdin izini yazmaq
//  1) Hər səhifədə çəp, solğun yazı: ad • kod • tarix
//  2) Hər səhifənin altında açıq qeyd: "Yalnız ... üçün"
//  3) Gözə görünməyən gizli yazı (kod) — səhifənin müxtəlif yerlərində
//  4) Faylın daxili məlumatları (metadata) — kod, istifadəçi adı, tarix
// =========================================================
import { PDFDocument, StandardFonts, rgb, degrees } from "../vendor/pdf-lib/pdf-lib.esm.min.js";

// Standart PDF şriftləri ə, ş, ğ, ı hərflərini dəstəkləmir — latın qarşılığına çeviririk
const MAP = { "ə": "e", "Ə": "E", "ş": "s", "Ş": "S", "ğ": "g", "Ğ": "G", "ı": "i", "İ": "I",
              "ö": "o", "Ö": "O", "ü": "u", "Ü": "U", "ç": "c", "Ç": "C", "—": "-", "–": "-", "•": "*" };
export function ascii(text) {
  return String(text ?? "")
    .replace(/[əƏşŞğĞıİöÖüÜçÇ—–•]/g, (c) => MAP[c])
    .normalize("NFKD").replace(/[^\x20-\x7E]/g, "");
}

/**
 * @param {Uint8Array} bytes  orijinal PDF
 * @param {{name:string, username:string, code:string, date:string, title:string}} wm
 * @returns {Promise<Uint8Array>}
 */
export async function stampPdf(bytes, wm) {
  const doc = await PDFDocument.load(bytes, { ignoreEncryption: true, updateMetadata: false });
  const font = await doc.embedFont(StandardFonts.Helvetica);
  const bold = await doc.embedFont(StandardFonts.HelveticaBold);

  const name = ascii(wm.name);
  const line = `${name}  *  ${wm.code}  *  ${ascii(wm.date)}`;
  const footer = `Wordora - Yalniz ${name} ucun - ${wm.code} - ${ascii(wm.date)} - Paylasmaq qadagandir`;
  const pages = doc.getPages();

  pages.forEach((page, i) => {
    const { width: w, height: h } = page.getSize();
    const size = Math.max(9, Math.min(w, h) / 30);

    // 1) Çəp təkrarlanan yazı
    const tw = bold.widthOfTextAtSize(line, size) + size * 4;
    const stepY = size * 7;
    const diag = Math.hypot(w, h);
    let row = 0;
    for (let y = -diag * 0.5; y < h + diag * 0.5; y += stepY, row++) {
      for (let x = -diag + (row % 2) * (tw / 2); x < w + diag; x += tw) {
        page.drawText(line, {
          x, y, size, font: bold,
          color: rgb(0.23, 0.2, 0.71),
          opacity: 0.11,
          rotate: degrees(30),
        });
      }
    }

    // 2) Alt qeyd
    const fs = Math.max(6, size * 0.5);
    const fw = font.widthOfTextAtSize(footer, fs);
    page.drawRectangle({ x: 0, y: 0, width: w, height: fs * 2.4, color: rgb(0.055, 0.12, 0.24), opacity: 0.05 });
    page.drawText(footer, {
      x: Math.max(4, (w - fw) / 2), y: fs * 0.8, size: fs, font,
      color: rgb(0.055, 0.12, 0.24), opacity: 0.6,
    });

    // 3) Gizli yazı — tam şəffaf, gözlə görünmür, amma faylın içində qalır
    const hidden = `WORDORA-ID ${wm.code} ${ascii(wm.username)} ${ascii(wm.date)} p${i + 1}`;
    for (const [hx, hy] of [[8, h - 12], [w / 2, h / 2], [8, 20], [w - 160, h - 40]]) {
      page.drawText(hidden, { x: hx, y: hy, size: 4, font, color: rgb(1, 1, 1), opacity: 0 });
    }
  });

  // 4) Faylın daxili məlumatları
  doc.setSubject(`Wordora - ${wm.code}`);
  doc.setKeywords(["wordora", wm.code, ascii(wm.username), ascii(wm.date)]);
  doc.setCreator("Wordora");
  doc.setProducer(`Wordora ${wm.code}`);
  doc.setModificationDate(new Date());

  return doc.save({ useObjectStreams: true });
}

// Brauzerdə faylı yadda saxlat
export function saveBlob(bytes, filename) {
  const blob = new Blob([bytes], { type: "application/pdf" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 30000);
}

export function safeFilename(title, code) {
  const base = ascii(title).replace(/[^A-Za-z0-9 _.-]/g, "").trim().replace(/\s+/g, "_").slice(0, 60) || "material";
  return `${base}_${code}.pdf`;
}
