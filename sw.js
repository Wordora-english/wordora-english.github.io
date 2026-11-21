// WORDORA — service worker
// Həmişə əvvəlcə internetdən götürür (yeniliklər dərhal çatsın),
// internet yoxdursa, yadda saxlanmış nüsxəni göstərir.
// Supabase sorğuları və PDF-lər heç vaxt yaddaşa yazılmır.
const CACHE = "wordora-v48";
const SHELL = ["./", "index.html", "login.html", "portal.html", "assets/css/style.css", "assets/js/app.js",
  "assets/js/config.js", "assets/img/logo-icon.png", "assets/img/favicon-32.png", "offline.html"];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).catch(() => {}));
  self.skipWaiting();
});

self.addEventListener("activate", (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))));
  self.clients.claim();
});

self.addEventListener("fetch", (e) => {
  const req = e.request;
  const url = new URL(req.url);
  if (req.method !== "GET" || url.origin !== location.origin) return;   // Supabase, CDN — toxunmuruq
  if (url.pathname.includes("/vendor/") || url.pathname.endsWith(".pdf")) return;
  e.respondWith(
    // "no-cache": brauzer hər dəfə serverdən yeni versiya olub-olmadığını soruşur — yeniliklər dərhal görünür
    fetch(req.url, { cache: "no-cache", credentials: "same-origin" })
      .then((res) => {
        if (res.ok) { const copy = res.clone(); caches.open(CACHE).then((c) => c.put(req, copy)); }
        return res;
      })
      .catch(async () => (await caches.match(req)) || (req.mode === "navigate" ? caches.match("offline.html") : Response.error()))
  );
});

// ---------- 🔔 Bildirişlər ----------
self.addEventListener("push", (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch { d = { title: e.data?.text() || "Wordora" }; }
  e.waitUntil(self.registration.showNotification(d.title || "Wordora", {
    body: d.body || "",
    icon: "assets/img/apple-touch-icon.png",
    badge: "assets/img/favicon-32.png",
    tag: d.tag || undefined,
    data: { url: d.url || "portal.html" },
  }));
});

self.addEventListener("notificationclick", (e) => {
  e.notification.close();
  const url = new URL(e.notification.data?.url || "portal.html", self.registration.scope).href;
  e.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((list) => {
    for (const c of list) if (c.url.startsWith(self.registration.scope) && "focus" in c) { c.navigate(url).catch(() => {}); return c.focus(); }
    return self.clients.openWindow(url);
  }));
});
