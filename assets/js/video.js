// Görüntülü canlı dərs — Jitsi Meet (pulsuz) və ya müəllimin öz Zoom/Meet linki
import { sb, esc, toast, translateError } from "./app.js";

const q = (v) => encodeURIComponent(JSON.stringify(v));

export function meetUrl({ room, url, name, teacher, title }) {
  if (url) return url;   // müəllimin öz linki (Zoom, Google Meet …)
  const cfg = [
    `userInfo.displayName=${q(teacher ? `${name} (müəllim)` : name)}`,
    "config.prejoinConfig.enabled=false",
    "config.disableDeepLinking=true",
    "config.deeplinking.disabled=true",
    `config.startWithAudioMuted=${teacher ? "false" : "true"}`,
    "config.defaultLanguage=%22tr%22",
  ];
  if (title) cfg.push(`config.subject=${q(title)}`);
  return `https://meet.jit.si/${encodeURIComponent(room)}#${cfg.join("&")}`;
}

export async function joinLesson(id, title, btn) {
  if (btn) { btn.disabled = true; btn.textContent = "Qoşulur…"; }
  const { data, error } = await sb.rpc("video_join", { p_id: id });
  if (error) {
    if (btn) { btn.disabled = false; btn.textContent = "Dərsə qoşul"; }
    return toast(translateError(error), "err");
  }
  location.href = meetUrl({ ...data, title });
}

const hm = (iso) => { const d = new Date(new Date(iso).getTime() + 4 * 3600e3), p = (n) => String(n).padStart(2, "0"); return `${p(d.getUTCDate())}.${p(d.getUTCMonth() + 1)} ${p(d.getUTCHours())}:${p(d.getUTCMinutes())}`; };

// Portaldakı kart: canlı dərs varsa böyük qırmızı banner, planlaşdırılıbsa kiçik xatırlatma
export async function renderVideoBox(box) {
  if (!box || !sb) return;
  const { data, error } = await sb.rpc("my_video_lessons");
  if (error) { box.innerHTML = ""; return; }   // SQL hələ işə salınmayıb
  const list = data || [];
  box.innerHTML = list.map((v) => v.live
    ? `<div class="vid-live card"><span class="vid-dot"></span>
         <div class="vid-txt"><b>CANLI DƏRS</b><span>${esc(v.title)}</span>
           <small class="muted">Kamera və mikrofon icazəsi istəniləndə "İcazə ver" bas</small></div>
         <button class="btn btn-primary" data-vjoin="${v.id}" data-vtitle="${esc(v.title)}">🎥 Dərsə qoşul</button></div>`
    : `<div class="vid-plan card">📅 <b>Canlı dərs:</b> ${esc(v.title)} <span class="muted">— ${hm(v.starts_at)}</span></div>`).join("");
  box.querySelectorAll("[data-vjoin]").forEach((b) => b.addEventListener("click", () => joinLesson(b.dataset.vjoin, b.dataset.vtitle, b)));
}
