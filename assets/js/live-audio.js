// =========================================================
//  WORDORA — canlı viktorina üçün musiqi və səs effektləri
//  Heç bir musiqi faylı yoxdur: hamısı brauzerdə Web Audio ilə
//  "çalınır" (öz yazdığımız melodiyalar — müəllif hüququ problemi yoxdur).
//   • lobby   — sakit, xoş gözləmə musiqisi (92 BPM, C–Am–F–G)
//   • question — həyəcanlı yarış musiqisi (128 BPM), son 5 saniyədə sürətlənir
//   • effektlər: qoşulma, düzgün, səhv, saniyə tıqqıltısı, seriya, fanfar
// =========================================================

const NOTE = (n) => 440 * Math.pow(2, (n - 69) / 12);   // MIDI → Hz
const KEY = "wd_live_sound";

export class LiveAudio {
  constructor({ music = true } = {}) {
    this.ctx = null;
    this.musicOn = music && this.pref("music", music);
    this.sfxOn = this.pref("sfx", true);
    this.mode = null;          // "lobby" | "question" | null
    this.intense = 0;          // 0..1 — son saniyələrdə artır
    this.step = 0; this.nextT = 0; this.timer = null;
  }
  pref(k, d) { try { const v = localStorage.getItem(`${KEY}_${k}`); return v === null ? d : v === "1"; } catch { return d; } }
  save(k, v) { try { localStorage.setItem(`${KEY}_${k}`, v ? "1" : "0"); } catch {} }

  // Brauzerlər səsi yalnız istifadəçi toxunandan sonra açır
  unlock() {
    if (!this.ctx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return false;
      this.ctx = new AC();
      this.master = this.ctx.createGain(); this.master.gain.value = 0.9; this.master.connect(this.ctx.destination);
      this.musicBus = this.ctx.createGain(); this.musicBus.gain.value = this.musicOn ? 0.55 : 0; this.musicBus.connect(this.master);
      this.sfxBus = this.ctx.createGain(); this.sfxBus.gain.value = this.sfxOn ? 0.9 : 0; this.sfxBus.connect(this.master);
      // ağ səs (hi-hat, "whoosh" üçün)
      const len = this.ctx.sampleRate;
      this.noise = this.ctx.createBuffer(1, len, this.ctx.sampleRate);
      const d = this.noise.getChannelData(0);
      for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    }
    if (this.ctx.state === "suspended") this.ctx.resume();
    return this.ctx.state !== "closed";
  }
  get ready() { return !!this.ctx && this.ctx.state === "running"; }

  setMusic(on) {
    this.musicOn = on; this.save("music", on);
    if (this.musicBus) this.musicBus.gain.setTargetAtTime(on ? 0.55 : 0, this.ctx.currentTime, 0.15);
  }
  setSfx(on) {
    this.sfxOn = on; this.save("sfx", on);
    if (this.sfxBus) this.sfxBus.gain.setTargetAtTime(on ? 0.9 : 0, this.ctx.currentTime, 0.05);
  }

  // ---------------- alətlər ----------------
  tone(t, freq, dur, { type = "sine", vol = 0.2, attack = 0.005, bus = this.musicBus, cutoff = 0, detune = 0 } = {}) {
    const c = this.ctx, o = c.createOscillator(), g = c.createGain();
    o.type = type; o.frequency.setValueAtTime(freq, t); o.detune.value = detune;
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(vol, t + attack);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    let node = o;
    if (cutoff) { const f = c.createBiquadFilter(); f.type = "lowpass"; f.frequency.value = cutoff; o.connect(f); node = f; }
    node.connect(g); g.connect(bus);
    o.start(t); o.stop(t + dur + 0.05);
  }
  kick(t, vol = 0.5) {
    const c = this.ctx, o = c.createOscillator(), g = c.createGain();
    o.frequency.setValueAtTime(140, t); o.frequency.exponentialRampToValueAtTime(42, t + 0.12);
    g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.22);
    o.connect(g); g.connect(this.musicBus); o.start(t); o.stop(t + 0.25);
  }
  hat(t, vol = 0.06, dur = 0.04, bus = this.musicBus) {
    const c = this.ctx, s = c.createBufferSource(), f = c.createBiquadFilter(), g = c.createGain();
    s.buffer = this.noise; f.type = "highpass"; f.frequency.value = 7000;
    g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    s.connect(f); f.connect(g); g.connect(bus); s.start(t, Math.random() * 0.5); s.stop(t + dur + 0.02);
  }
  clap(t, vol = 0.12) {
    const c = this.ctx, s = c.createBufferSource(), f = c.createBiquadFilter(), g = c.createGain();
    s.buffer = this.noise; f.type = "bandpass"; f.frequency.value = 1500; f.Q.value = 0.8;
    g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.15);
    s.connect(f); f.connect(g); g.connect(this.musicBus); s.start(t, Math.random() * 0.5); s.stop(t + 0.2);
  }

  // ---------------- musiqi ----------------
  play(mode) {
    if (!this.unlock()) return;
    if (this.mode === mode) return;
    this.mode = mode; this.intense = 0;
    this.step = 0; this.nextT = this.ctx.currentTime + 0.08;
    clearInterval(this.timer);
    if (!mode) return;
    this.timer = setInterval(() => this.schedule(), 25);
  }
  stop() { this.play(null); }
  setIntensity(x) { this.intense = Math.max(0, Math.min(1, x)); }

  schedule() {
    if (!this.ctx) return;
    while (this.nextT < this.ctx.currentTime + 0.12) {
      if (this.mode === "lobby") this.lobbyStep(this.step, this.nextT);
      else if (this.mode === "question") this.questionStep(this.step, this.nextT);
      const bpm = this.mode === "lobby" ? 92 : 128 + this.intense * 22;
      this.nextT += 60 / bpm / 4;   // 16-lıq not
      this.step++;
    }
  }

  // Sakit gözləmə: C – Am – F – G, yumşaq pad + arpecio + yüngül ritm
  lobbyStep(s, t) {
    const chords = [[60, 64, 67, 72], [57, 60, 64, 69], [53, 57, 60, 65], [55, 59, 62, 67]];
    const bar = Math.floor(s / 16) % 4, i = s % 16, ch = chords[bar];
    const spb = 60 / 92;
    if (i === 0) {
      ch.slice(0, 3).forEach((n) => this.tone(t, NOTE(n), spb * 4, { type: "triangle", vol: 0.035, attack: 0.4, detune: 6 }));
      this.tone(t, NOTE(ch[0] - 24), spb * 3.6, { type: "sine", vol: 0.12, attack: 0.02 });
    }
    if (i % 2 === 0) {   // arpecio
      const seq = [0, 1, 2, 3, 2, 1, 2, 3];
      this.tone(t, NOTE(ch[seq[(i / 2) % 8]] + 12), 0.35, { type: "sine", vol: 0.05, attack: 0.004 });
    }
    if (i === 0 || i === 8) this.kick(t, 0.22);
    if (i === 4 || i === 12) this.clap(t, 0.05);
    if (i % 4 === 2) this.hat(t, 0.025, 0.05);
  }

  // Həyəcanlı yarış: Am – F – C – E, pulsasiya edən bas, stab-lar, 16-lıq hi-hat
  questionStep(s, t) {
    const roots = [45, 41, 48, 40];
    const stabs = [[69, 72, 76], [65, 69, 72], [67, 72, 76], [68, 71, 76]];
    const bar = Math.floor(s / 16) % 4, i = s % 16;
    const x = this.intense;
    // bas: hər 8-lik
    if (i % 2 === 0) this.tone(t, NOTE(roots[bar]), 0.16, { type: "sawtooth", vol: 0.09, cutoff: 500 + x * 1400 });
    if (i % 4 === 0) this.kick(t, 0.42 + x * 0.1);
    if (i === 4 || i === 12) this.clap(t, 0.09);
    this.hat(t, i % 2 ? 0.02 : 0.035 + x * 0.02, 0.03);
    // stab-lar (sinkopalı)
    if ([3, 6, 10, 14].includes(i)) stabs[bar].forEach((n) => this.tone(t, NOTE(n), 0.12, { type: "square", vol: 0.018, cutoff: 1800 + x * 2000 }));
    // melodiya parçası hər 2 taktdan bir
    if (bar % 2 === 1 && i % 4 === 0) {
      const mel = [76, 74, 72, 71];
      this.tone(t, NOTE(mel[i / 4]), 0.18, { type: "triangle", vol: 0.05 });
    }
    // son saniyələr: yüksək "tik-tak"
    if (x > 0.5 && i % 4 === 0) this.tone(t, NOTE(96), 0.04, { type: "square", vol: 0.03 });
  }

  // ---------------- effektlər ----------------
  fx(fn) { if (this.unlock() && this.sfxOn) fn(this.ctx.currentTime + 0.01); }
  pop() { this.fx((t) => { this.tone(t, NOTE(79), 0.12, { type: "sine", vol: 0.25, bus: this.sfxBus }); this.tone(t + 0.05, NOTE(84), 0.12, { type: "sine", vol: 0.2, bus: this.sfxBus }); }); }
  tap() { this.fx((t) => this.tone(t, NOTE(88), 0.06, { type: "triangle", vol: 0.18, bus: this.sfxBus })); }
  correct() { this.fx((t) => [72, 76, 79, 84].forEach((n, k) => this.tone(t + k * 0.08, NOTE(n), 0.35, { type: "triangle", vol: 0.22, bus: this.sfxBus }))); }
  wrong() { this.fx((t) => { this.tone(t, NOTE(52), 0.35, { type: "sawtooth", vol: 0.12, cutoff: 900, bus: this.sfxBus }); this.tone(t + 0.18, NOTE(47), 0.45, { type: "sawtooth", vol: 0.12, cutoff: 700, bus: this.sfxBus }); }); }
  tick(high = false) { this.fx((t) => this.tone(t, NOTE(high ? 93 : 86), 0.05, { type: "square", vol: high ? 0.12 : 0.07, bus: this.sfxBus })); }
  whoosh() {
    this.fx((t) => {
      const c = this.ctx, s = c.createBufferSource(), f = c.createBiquadFilter(), g = c.createGain();
      s.buffer = this.noise; f.type = "bandpass"; f.Q.value = 1.2;
      f.frequency.setValueAtTime(400, t); f.frequency.exponentialRampToValueAtTime(4000, t + 0.35);
      g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.25, t + 0.15); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.45);
      s.connect(f); f.connect(g); g.connect(this.sfxBus); s.start(t); s.stop(t + 0.5);
    });
  }
  streak() { this.fx((t) => [76, 79, 83, 88, 91].forEach((n, k) => this.tone(t + k * 0.05, NOTE(n), 0.2, { type: "square", vol: 0.06, cutoff: 3000, bus: this.sfxBus }))); }
  countdown(n) { this.fx((t) => this.tone(t, NOTE(n > 0 ? 76 : 88), n > 0 ? 0.18 : 0.5, { type: "triangle", vol: 0.25, bus: this.sfxBus })); }
  fanfare() {
    this.fx((t) => {
      const seq = [[67, 0, 0.15], [72, 0.15, 0.15], [76, 0.3, 0.15], [79, 0.45, 0.45], [76, 0.95, 0.15], [79, 1.1, 0.9]];
      seq.forEach(([n, d, len]) => {
        this.tone(t + d, NOTE(n), len + 0.1, { type: "sawtooth", vol: 0.08, cutoff: 2600, bus: this.sfxBus });
        this.tone(t + d, NOTE(n - 12), len + 0.1, { type: "triangle", vol: 0.12, bus: this.sfxBus });
      });
      [0, 0.45, 1.1].forEach((d) => this.hat(t + d, 0.15, 0.4, this.sfxBus));
    });
  }
}

// Konfetti (son nəticələrdə)
export function confetti(n = 140) {
  const box = document.createElement("div");
  box.className = "confetti";
  const colors = ["#e5484d", "#2f7ce0", "#f5b400", "#12925c", "#7b4fe0", "#e0529c", "#0ea5a5"];
  for (let i = 0; i < n; i++) {
    const p = document.createElement("i");
    p.style.left = `${Math.random() * 100}%`;
    p.style.background = colors[i % colors.length];
    p.style.animationDelay = `${Math.random() * 1.2}s`;
    p.style.animationDuration = `${2.6 + Math.random() * 2}s`;
    p.style.transform = `rotate(${Math.random() * 360}deg)`;
    if (i % 3 === 0) p.style.borderRadius = "50%";
    box.appendChild(p);
  }
  document.body.appendChild(box);
  setTimeout(() => box.remove(), 6500);
}

export const AVATARS = ["🦊", "🐼", "🐯", "🦁", "🐸", "🐵", "🐨", "🐰", "🐧", "🦉", "🐙", "🦄", "🐲", "🐢", "🐬", "🦋", "🐝", "🐞", "🦖", "🐺", "🐱", "🐶", "🐮", "🦔"];
export const COLORS = ["#e5484d", "#2f7ce0", "#f5a400", "#12925c", "#7b4fe0", "#e0529c", "#0ea5a5", "#f97316"];
export const REACTIONS = ["👏", "😂", "😮", "🔥", "❤️", "👍", "😱", "🎉"];
