// =========================================================
//  WORDORA — su nişanı
//  Su nişanı birbaşa səhifənin şəklinin içinə çəkilir (ayrıca element deyil),
//  ona görə ekran şəklində və telefonla çəkilmiş fotoda da görünür.
// =========================================================

/**
 * @param {CanvasRenderingContext2D} ctx
 * @param {number} w  canvas eni (piksel)
 * @param {number} h  canvas hündürlüyü (piksel)
 * @param {{name:string, code:string, date:string}} wm
 * @param {number} pageNo
 */
export function drawWatermark(ctx, w, h, wm, pageNo) {
  const base = Math.max(10, Math.round(w / 34));
  const line = `${wm.name}  •  ${wm.code}  •  ${wm.date}`;

  ctx.save();

  // 1) Çəp, təkrarlanan əsas yazı
  ctx.translate(w / 2, h / 2);
  ctx.rotate(-Math.PI / 6);
  ctx.font = `600 ${base}px Inter, "Segoe UI", Arial, sans-serif`;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillStyle = "rgba(58, 50, 181, 0.13)";
  const textW = ctx.measureText(line).width + base * 4;
  const stepY = base * 6;
  const diag = Math.hypot(w, h);
  let row = 0;
  for (let y = -diag / 2; y <= diag / 2; y += stepY, row++) {
    const shift = (row % 2) * (textW / 2);
    for (let x = -diag / 2 - textW; x <= diag / 2 + textW; x += textW) {
      ctx.fillText(line, x + shift, y);
    }
  }
  ctx.restore();

  // 2) Gizli kod: çox solğun, kiçik, bütün səhifəyə səpələnmiş.
  //    Şəklin bir hissəsi kəsilsə də, kod qalır.
  ctx.save();
  const small = Math.max(7, Math.round(base * 0.42));
  ctx.font = `500 ${small}px ui-monospace, Menlo, Consolas, monospace`;
  ctx.fillStyle = "rgba(14, 31, 61, 0.05)";
  ctx.textBaseline = "top";
  const gx = small * 14, gy = small * 9;
  let r = 0;
  for (let y = small; y < h; y += gy, r++) {
    for (let x = (r % 2) * (gx / 2); x < w; x += gx) {
      ctx.fillText(`${wm.code}·${pageNo}`, x, y);
    }
  }
  ctx.restore();

  // 3) Alt zolaq — açıq oxunan qeyd
  ctx.save();
  const bandH = Math.round(base * 1.6);
  ctx.fillStyle = "rgba(14, 31, 61, 0.06)";
  ctx.fillRect(0, h - bandH, w, bandH);
  ctx.font = `600 ${Math.round(base * 0.55)}px Inter, "Segoe UI", Arial, sans-serif`;
  ctx.fillStyle = "rgba(14, 31, 61, 0.55)";
  ctx.textBaseline = "middle";
  ctx.textAlign = "center";
  ctx.fillText(
    `Wordora · Yalnız ${wm.name} üçün · ${wm.code} · ${wm.date} · Səh. ${pageNo}`,
    w / 2,
    h - bandH / 2,
  );
  ctx.restore();
}
