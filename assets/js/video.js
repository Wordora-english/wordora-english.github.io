// Görüntülü canlı dərs — Wordora-nın öz sinif otağı (lesson.html)
import { sb, esc } from "./app.js";

const hm = (iso) => { const d = new Date(new Date(iso).getTime() + 4 * 3600e3), p = (n) => String(n).padStart(2, "0"); return `${p(d.getUTCDate())}.${p(d.getUTCMonth() + 1)} ${p(d.getUTCHours())}:${p(d.getUTCMinutes())}`; };

// Portaldakı kart: canlı dərs varsa böyük qırmızı banner, planlaşdırılıbsa kiçik xatırlatma
export async function renderVideoBox(box) {
  if (!box || !sb) return;
  const { data, error } = await sb.rpc("my_video_lessons");
  if (error) { box.innerHTML = ""; return; }   // SQL hələ işə salınmayıb
  box.innerHTML = (data || []).map((v) => v.live
    ? `<div class="vid-live card"><span class="vid-dot"></span>
         <div class="vid-txt"><b>CANLI DƏRS</b><span>${esc(v.title)}</span>
           <small class="muted">Kamera və mikrofon icazəsi istəniləndə "İcazə ver" bas</small></div>
         <a class="btn btn-primary" href="lesson.html?id=${encodeURIComponent(v.id)}">🎥 Dərsə qoşul</a></div>`
    : `<div class="vid-plan card">📅 <b>Canlı dərs:</b> ${esc(v.title)} <span class="muted">— ${hm(v.starts_at)}</span></div>`).join("");
}
