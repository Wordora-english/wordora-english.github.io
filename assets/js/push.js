// =========================================================
//  WORDORA — telefona bildirişlər (Web Push)
// =========================================================
import { sb, isIOS, isStandalone } from "./app.js";

const b64 = (s) => {
  const p = "=".repeat((4 - (s.length % 4)) % 4);
  const raw = atob((s + p).replace(/-/g, "+").replace(/_/g, "/"));
  return Uint8Array.from(raw, (c) => c.charCodeAt(0));
};
const toB64 = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

const swReady = () => Promise.race([navigator.serviceWorker.ready, new Promise((_, rej) => setTimeout(() => rej(new Error("Service worker hazır deyil")), 6000))]);

export const pushSupported = () => "serviceWorker" in navigator && "PushManager" in window && "Notification" in window;

// {state: "unsupported" | "ios-install" | "not-ready" | "denied" | "on" | "off", key}
export async function pushState() {
  if (isIOS() && !isStandalone()) return { state: "ios-install" };
  if (!pushSupported()) return { state: "unsupported" };
  const { data: key, error } = await sb.rpc("push_public_key");
  if (error || !key) return { state: "not-ready" };
  if (Notification.permission === "denied") return { state: "denied", key };
  const reg = await swReady();
  const sub = await reg.pushManager.getSubscription();
  if (sub && Notification.permission === "granted") {
    // serverdə də olsun (məs. başqa hesabdan çıxıb-girəndə)
    sb.rpc("push_subscribe", { p_endpoint: sub.endpoint, p_p256dh: toB64(sub.getKey("p256dh")), p_auth: toB64(sub.getKey("auth")) }).then(() => {}, () => {});
    return { state: "on", key };
  }
  return { state: "off", key };
}

export async function enablePush(key) {
  const perm = await Notification.requestPermission();
  if (perm !== "granted") throw new Error("Bildirişlərə icazə verilmədi");
  const reg = await swReady();
  let sub = await reg.pushManager.getSubscription();
  if (!sub) sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: b64(key) });
  const { error } = await sb.rpc("push_subscribe", { p_endpoint: sub.endpoint, p_p256dh: toB64(sub.getKey("p256dh")), p_auth: toB64(sub.getKey("auth")) });
  if (error) throw error;
}

export async function disablePush() {
  const reg = await swReady();
  const sub = await reg.pushManager.getSubscription();
  if (!sub) return;
  await sb.rpc("push_unsubscribe", { p_endpoint: sub.endpoint }).catch(() => {});
  await sub.unsubscribe().catch(() => {});
}
