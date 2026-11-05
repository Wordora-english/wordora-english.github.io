// =========================================================
//  WORDORA — sertifikat (canvas-da çəkilir, PDF-ə yerləşdirilir)
//  Canvas istənilən şrifti və Azərbaycan hərflərini düzgün çəkir.
// =========================================================
import { PDFDocument } from "../vendor/pdf-lib/pdf-lib.esm.min.js";
import { TEACHER_NAME } from "./config.js";

const W = 2339, H = 1654;   // A4 (üfüqi), ~200 dpi

function loadImg(src) {
  return new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = rej; i.src = src; });
}

function fitText(ctx, text, maxW, size, weight, family) {
  let s = size;
  do { ctx.font = `${weight} ${s}px ${family}`; s -= 4; } while (ctx.measureText(text).width > maxW && s > 20);
}

export async function drawCertificate({ name, className, title, percent, date, code, serial }) {
  try { await Promise.all(["700 80px Outfit", "600 40px Outfit", "500 30px Inter", "400 30px Inter"].map((f) => document.fonts.load(f))); } catch {}
  const c = document.createElement("canvas");
  c.width = W; c.height = H;
  const x = c.getContext("2d");

  // fon
  x.fillStyle = "#ffffff"; x.fillRect(0, 0, W, H);
  const g = x.createLinearGradient(0, 0, W, H);
  g.addColorStop(0, "#3a32b5"); g.addColorStop(.55, "#7b4fe0"); g.addColorStop(1, "#2f7ce0");
  x.fillStyle = g;
  x.fillRect(0, 0, W, 36); x.fillRect(0, H - 36, W, 36); x.fillRect(0, 0, 36, H); x.fillRect(W - 36, 0, 36, H);
  x.strokeStyle = "#d9d2fb"; x.lineWidth = 4; x.strokeRect(70, 70, W - 140, H - 140);
  // künc ulduzları
  const star = (cx, cy, r) => { x.beginPath(); x.moveTo(cx, cy - r); x.quadraticCurveTo(cx, cy, cx + r, cy); x.quadraticCurveTo(cx, cy, cx, cy + r); x.quadraticCurveTo(cx, cy, cx - r, cy); x.quadraticCurveTo(cx, cy, cx, cy - r); x.fill(); };
  x.fillStyle = "#f5b400"; [[130, 130], [W - 130, 130], [130, H - 130], [W - 130, H - 130]].forEach(([a, b]) => star(a, b, 26));

  // loqo
  try { const logo = await loadImg(new URL("../img/logo-icon.png", import.meta.url).href); x.drawImage(logo, W / 2 - 110, 120, 220, 220); } catch {}
  x.textBaseline = "alphabetic";
  x.font = "700 64px Outfit, Arial";
  const wW = x.measureText("WORD").width, oW = x.measureText("ORA").width, x0 = W / 2 - (wW + oW) / 2;
  x.textAlign = "left";
  x.fillStyle = "#0e1f3d"; x.fillText("WORD", x0, 410);
  x.fillStyle = "#7b4fe0"; x.fillText("ORA", x0 + wW, 410);
  x.textAlign = "center";
  x.fillStyle = "#6b6f86"; x.font = "500 30px Inter, Arial"; x.fillText("More Words  •  Bigger Dreams", W / 2, 460);

  x.fillStyle = "#3a32b5"; x.font = "700 110px Outfit, Arial"; x.fillText("SERTİFİKAT", W / 2, 640);
  x.fillStyle = "#26365a"; x.font = "500 38px Inter, Arial"; x.fillText("CERTIFICATE OF ACHIEVEMENT", W / 2, 700);

  x.fillStyle = "#6b6f86"; x.font = "400 36px Inter, Arial"; x.fillText("Bu sertifikat təqdim olunur", W / 2, 800);
  x.fillStyle = "#0e1f3d"; fitText(x, name, W - 500, 104, "700", "Outfit, Arial"); x.fillText(name, W / 2, 925);
  x.strokeStyle = "#f5b400"; x.lineWidth = 5; x.beginPath(); x.moveTo(W / 2 - 520, 955); x.lineTo(W / 2 + 520, 955); x.stroke();
  if (className) { x.fillStyle = "#6b6f86"; x.font = "500 34px Inter, Arial"; x.fillText(className, W / 2, 1005); }

  x.fillStyle = "#26365a"; x.font = "400 38px Inter, Arial";
  x.fillText("ingilis dili üzrə", W / 2, 1090);
  x.fillStyle = "#0e1f3d"; fitText(x, `«${title}»`, W - 500, 50, "600", "Outfit, Arial"); x.fillText(`«${title}»`, W / 2, 1160);
  x.fillStyle = "#26365a"; x.font = "400 38px Inter, Arial"; x.fillText("sınağında göstərdiyi yüksək nəticəyə görə", W / 2, 1225);
  x.fillStyle = "#12925c"; x.font = "700 70px Outfit, Arial"; x.fillText(`${Math.round(percent)}%`, W / 2, 1320);

  // alt hissə
  x.fillStyle = "#0e1f3d"; x.font = "600 34px Inter, Arial";
  x.textAlign = "left"; x.fillText(date, 200, 1470);
  x.fillStyle = "#6b6f86"; x.font = "400 26px Inter, Arial"; x.fillText("Tarix", 200, 1510);
  x.strokeStyle = "#cfcae3"; x.lineWidth = 2; x.beginPath(); x.moveTo(200, 1485); x.lineTo(620, 1485); x.stroke();
  x.textAlign = "right";
  x.fillStyle = "#0e1f3d"; x.font = "600 34px Inter, Arial"; x.fillText(TEACHER_NAME, W - 200, 1470);
  x.fillStyle = "#6b6f86"; x.font = "400 26px Inter, Arial"; x.fillText("İngilis dili müəllimi", W - 200, 1510);
  x.beginPath(); x.moveTo(W - 620, 1485); x.lineTo(W - 200, 1485); x.stroke();
  x.textAlign = "center"; x.fillStyle = "#9a9db3"; x.font = "400 22px Inter, Arial";
  x.fillText(`№ ${serial}  ·  ${code}`, W / 2, 1530);
  return c;
}

export async function downloadCertificate(info) {
  const canvas = await drawCertificate(info);
  const png = await new Promise((r) => canvas.toBlob(r, "image/png"));
  const doc = await PDFDocument.create();
  const img = await doc.embedPng(new Uint8Array(await png.arrayBuffer()));
  const page = doc.addPage([841.89, 595.28]);   // A4 üfüqi (pt)
  page.drawImage(img, { x: 0, y: 0, width: 841.89, height: 595.28 });
  doc.setTitle(`Sertifikat — ${info.name}`);
  doc.setAuthor(TEACHER_NAME);
  doc.setCreator("Wordora");
  const bytes = await doc.save();
  const blob = new Blob([bytes], { type: "application/pdf" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = `Sertifikat_${info.name.replace(/[^\p{L}\p{N}]+/gu, "_")}.pdf`;
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 30000);
}
