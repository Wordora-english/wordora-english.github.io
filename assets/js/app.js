// =========================================================
//  WORDORA — ortaq funksiyalar
// =========================================================
import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";
import { SUPABASE_URL, SUPABASE_KEY, EMAIL_DOMAIN, CLASSES } from "./config.js";

export { CLASSES };

export const configured =
  !SUPABASE_URL.startsWith("BURAYA") && !SUPABASE_KEY.startsWith("BURAYA");

export const sb = configured
  ? createClient(SUPABASE_URL, SUPABASE_KEY, {
      auth: { persistSession: true, autoRefreshToken: true },
    })
  : null;

export const USERNAME_RE = /^[a-z0-9._]{3,20}$/;

// ---------- Tor yoxlaması: hər səhifə açılanda ----------
// Server Tor IP-lərindən gələn hər sorğunu "TOR_BLOCKED" xətası ilə dayandırır.
// Belə olanda səhifənin bütün məzmunu bağlanır.
export const torChecked = (async () => {
  if (!sb) return false;
  try {
    const { error } = await sb.rpc("ping");
    if (error && /tor_blocked/i.test(`${error.message} ${error.hint || ""}`)) {
      const show = () => {
        document.body.innerHTML = `
          <div style="min-height:100vh;display:grid;place-items:center;padding:24px;background:#0e1f3d;color:#fff;font-family:Inter,system-ui,sans-serif;text-align:center">
            <div style="max-width:420px">
              <div style="font-size:3rem">🧅</div>
              <h1 style="font-size:1.6rem;margin:.4rem 0">Tor ilə giriş qadağandır</h1>
              <p style="opacity:.85;line-height:1.5">Bu sayta Tor Browser və ya Tor şəbəkəsi ilə daxil olmaq olmaz.
              Adi brauzerdən (Chrome, Safari, Firefox) daxil ol.</p>
            </div>
          </div>`;
      };
      if (document.body) show(); else document.addEventListener("DOMContentLoaded", show);
      return true;
    }
  } catch { /* internet yoxdursa, səhifə öz işini görür */ }
  return false;
})();

export function usernameToEmail(username) {
  return `${username.trim().toLowerCase()}@${EMAIL_DOMAIN}`;
}

// HTML-dən qorunmaq üçün mətni təmizlə
export function esc(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

// "9" → "9-cu sinif", "Magistratura" → "Magistratura"
const CLASS_SUFFIX = { 1: "1-ci", 2: "2-ci", 3: "3-cü", 4: "4-cü", 5: "5-ci", 6: "6-cı", 7: "7-ci", 8: "8-ci", 9: "9-cu", 10: "10-cu", 11: "11-ci" };
export function classLabel(c) {
  return CLASS_SUFFIX[c] ? `${CLASS_SUFFIX[c]} sinif` : String(c ?? "");
}

export function $(sel, root = document) {
  return root.querySelector(sel);
}

export function formatDate(iso) {
  if (!iso) return "";
  const d = new Date(iso);
  const pad = (n) => String(n).padStart(2, "0");
  return `${pad(d.getDate())}.${pad(d.getMonth() + 1)}.${d.getFullYear()}, ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

// ---------- Bildiriş ----------
let toastBox;
export function toast(message, type = "") {
  if (!toastBox) {
    toastBox = document.createElement("div");
    toastBox.className = "toast-box";
    document.body.appendChild(toastBox);
  }
  const el = document.createElement("div");
  el.className = `toast ${type}`;
  el.textContent = message;
  toastBox.appendChild(el);
  setTimeout(() => el.remove(), 3800);
}

// ---------- Xəta mesajlarını Azərbaycan dilinə çevir ----------
export function translateError(err) {
  const msg = (err?.message || String(err || "")).toLowerCase();
  if (msg.includes("tor_blocked")) return "Tor ilə bu sayta giriş qadağandır. Adi brauzerdən daxil ol.";
  if (msg.includes("invalid login credentials")) return "İstifadəçi adı və ya şifrə yanlışdır.";
  if (msg.includes("user already registered") || msg.includes("already been registered"))
    return "Bu istifadəçi adı artıq tutulub. Başqa ad seç.";
  if (msg.includes("password should be at least") || msg.includes("weak"))
    return "Şifrə çox zəifdir. Ən azı 8 simvol, hərf və rəqəm istifadə et.";
  if (msg.includes("email address") && msg.includes("invalid"))
    return "Qeydiyyat sistemi hələ tam tənzimlənməyib (e-poçt domeni). Müəllimə xəbər ver.";
  if (msg.includes("email not confirmed"))
    return "Hesab təsdiqlənməyib. Müəllim Supabase-də 'Confirm email'-i söndürməlidir.";
  if (msg.includes("rate limit") || msg.includes("too many"))
    return "Çox tez-tez cəhd edildi. Bir neçə dəqiqə gözlə.";
  if (msg.includes("failed to fetch") || msg.includes("network"))
    return "İnternet bağlantısını yoxla.";
  if (msg.includes("database error saving new user"))
    return "Məlumatlar düzgün deyil. Bütün xanaları yoxla.";
  return err?.message || "Gözlənilməz xəta baş verdi.";
}

// ---------- Tənzimlənməyib xəbərdarlığı ----------
export function showConfigWarning() {
  if (configured) return;
  const box = document.createElement("div");
  box.className = "config-warn";
  box.innerHTML =
    "<div>⚙️ Sayt hələ bazaya qoşulmayıb. <b>assets/js/config.js</b> faylında Supabase ünvanını və açarını yaz (SETUP.md-yə bax).</div>";
  document.body.insertBefore(box, document.body.children[1] || null);
}

// ---------- Sessiya və profil ----------
export async function getSession() {
  if (!sb) return null;
  const { data } = await sb.auth.getSession();
  return data.session;
}

export async function getMyProfile() {
  const session = await getSession();
  if (!session) return null;
  const { data, error } = await sb
    .from("profiles")
    .select("*")
    .eq("id", session.user.id)
    .maybeSingle();
  if (error) throw error;
  return data;
}

export async function logout() {
  if (sb) await sb.auth.signOut();
  location.href = "login.html";
}

// Ulduz ikonu (loqodakı qızılı ulduz)
export const STAR_SVG =
  '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 0c.6 6.2 5.8 11.4 12 12-6.2.6-11.4 5.8-12 12-.6-6.2-5.8-11.4-12-12C6.2 11.4 11.4 6.2 12 0z"/></svg>';
