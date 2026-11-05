// =========================================================
//  WORDORA — materialı açmaq və su nişanlı yükləmək
// =========================================================
import { sb, formatDate, toast, translateError } from "./app.js";

// Serverdən icazə + su nişanı məlumatı (baxış/yükləmə qeyd olunur)
export async function openMaterial(id, kind = "view") {
  const { data, error } = await sb.rpc("open_material", { p_material: id, p_kind: kind });
  if (error) throw error;
  if (!data?.length) throw new Error("Bu materiala giriş icazən yoxdur.");
  const info = data[0];
  return {
    info,
    wm: {
      name: info.full_name,
      username: info.username,
      code: info.student_code,
      date: formatDate(info.opened_at),
      title: info.title,
    },
  };
}

// Faylı 60 saniyəlik gizli keçidlə al
export async function fetchMaterialBytes(filePath) {
  const { data, error } = await sb.storage.from("materials").createSignedUrl(filePath, 60);
  if (error) throw error;
  const res = await fetch(data.signedUrl, { cache: "no-store" });
  if (!res.ok) throw new Error("Fayl açılmadı");
  return new Uint8Array(await res.arrayBuffer());
}

// Su nişanlı PDF hazırla və yüklə
let busy = false;
export async function downloadMaterial(id, button) {
  if (busy) return;
  busy = true;
  const label = button?.innerHTML;
  if (button) { button.disabled = true; button.textContent = "Hazırlanır…"; }
  try {
    const { info, wm } = await openMaterial(id, "download");
    const bytes = await fetchMaterialBytes(info.file_path);
    const { stampPdf, saveBlob, safeFilename } = await import("./stamp.js");
    const stamped = await stampPdf(bytes, wm);
    saveBlob(stamped, safeFilename(info.title, wm.code));
    toast("Yükləndi. Faylda adın və şəxsi kodun yazılıb.", "ok");
  } catch (err) {
    toast(translateError(err), "err");
  } finally {
    busy = false;
    if (button) { button.disabled = false; button.innerHTML = label; }
  }
}
