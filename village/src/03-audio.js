'use strict';
// ---------------------------------------------------------------------
// Everything you hear is synthesised at runtime — no audio files, so the
// page stays one self-contained document. Gunshots are shaped noise,
// growls are detuned saws through a moving filter, the wind is a slow
// filter sweep over a noise loop.
// ---------------------------------------------------------------------

const SFX = (() => {
  let ctx = null, master = null, noiseBuf = null;
  let ambienceGain = null, musicGain = null, heartGain = null;
  let started = false, muted = false;
  let heartTimer = 0, heartRate = 0;

  function init() {
    if (ctx) return;
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    ctx = new AC();
    master = ctx.createGain();
    master.gain.value = 0.9;
    master.connect(ctx.destination);

    // one second of white noise, reused by every noise-based voice
    const len = ctx.sampleRate;
    noiseBuf = ctx.createBuffer(1, len, ctx.sampleRate);
    const d = noiseBuf.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
  }

  function resume() {
    init();
    if (ctx && ctx.state === 'suspended') ctx.resume();
  }

  const now = () => (ctx ? ctx.currentTime : 0);

  function noise(dur, gainVal, filterType, freq, q) {
    const src = ctx.createBufferSource();
    src.buffer = noiseBuf;
    src.loop = true;
    const f = ctx.createBiquadFilter();
    f.type = filterType || 'lowpass';
    f.frequency.value = freq || 1200;
    if (q != null) f.Q.value = q;
    const g = ctx.createGain();
    g.gain.value = gainVal;
    src.connect(f); f.connect(g); g.connect(master);
    src.start();
    src.stop(now() + dur + 0.05);
    return { src, f, g };
  }

  function tone(type, freq, dur, gainVal, dest) {
    const o = ctx.createOscillator();
    o.type = type;
    o.frequency.value = freq;
    const g = ctx.createGain();
    g.gain.value = gainVal;
    o.connect(g); g.connect(dest || master);
    o.start();
    o.stop(now() + dur + 0.05);
    return { o, g };
  }

  function decay(param, from, to, t0, dur) {
    param.setValueAtTime(from, t0);
    param.exponentialRampToValueAtTime(Math.max(to, 0.0001), t0 + dur);
  }

  // distance attenuation + air absorption, so far-away growls sit behind the wind
  function atten(d) {
    if (d == null) return { g: 1, f: 18000 };
    const g = clamp(1 - d / 34, 0, 1);
    return { g: g * g, f: clamp(16000 - d * 420, 700, 18000) };
  }

  const V = {
    pistol(d) {
      const a = atten(d), t = now();
      const n = noise(0.24, 0.0, 'lowpass', 3200 * (a.f / 18000) + 400);
      decay(n.g.gain, 0.75 * a.g, 0.001, t, 0.22);
      decay(n.f.frequency, 5200, 380, t, 0.2);
      const b = tone('triangle', 160, 0.14, 0.35 * a.g);
      decay(b.g.gain, 0.4 * a.g, 0.001, t, 0.13);
      decay(b.o.frequency, 190, 60, t, 0.12);
    },
    shotgun(d) {
      const a = atten(d), t = now();
      const n = noise(0.5, 0, 'lowpass', 2600);
      decay(n.g.gain, 0.95 * a.g, 0.001, t, 0.45);
      decay(n.f.frequency, 4200, 220, t, 0.4);
      const b = tone('sine', 90, 0.3, 0);
      decay(b.g.gain, 0.6 * a.g, 0.001, t, 0.28);
      decay(b.o.frequency, 120, 40, t, 0.25);
    },
    dry() {
      const t = now();
      const n = noise(0.07, 0, 'highpass', 2600);
      decay(n.g.gain, 0.28, 0.001, t, 0.06);
    },
    reload() {
      const t = now();
      for (let i = 0; i < 3; i++) {
        const o = ctx.createOscillator(), g = ctx.createGain();
        o.type = 'square'; o.frequency.value = 340 + i * 90;
        g.gain.setValueAtTime(0, t + i * 0.11);
        g.gain.linearRampToValueAtTime(0.12, t + i * 0.11 + 0.01);
        g.gain.exponentialRampToValueAtTime(0.0005, t + i * 0.11 + 0.07);
        o.connect(g); g.connect(master); o.start(t + i * 0.11); o.stop(t + i * 0.11 + 0.1);
      }
    },
    knife() {
      const t = now();
      const n = noise(0.2, 0, 'bandpass', 2400, 1.4);
      decay(n.g.gain, 0.3, 0.001, t, 0.16);
      decay(n.f.frequency, 3600, 900, t, 0.15);
    },
    flesh(d) {
      const a = atten(d), t = now();
      const n = noise(0.18, 0, 'lowpass', 700);
      decay(n.g.gain, 0.5 * a.g, 0.001, t, 0.15);
      const b = tone('sine', 110, 0.12, 0);
      decay(b.g.gain, 0.25 * a.g, 0.001, t, 0.11);
    },
    head(d) {
      const a = atten(d), t = now();
      const n = noise(0.3, 0, 'lowpass', 1500);
      decay(n.g.gain, 0.7 * a.g, 0.001, t, 0.26);
      const b = tone('sine', 70, 0.24, 0);
      decay(b.g.gain, 0.45 * a.g, 0.001, t, 0.22);
    },
    ricochet(d) {
      const a = atten(d), t = now();
      const b = tone('sawtooth', 1800, 0.2, 0);
      decay(b.g.gain, 0.09 * a.g, 0.0005, t, 0.18);
      decay(b.o.frequency, 2600, 500, t, 0.18);
    },
    ghoul(d) {
      const a = atten(d), t = now();
      const o1 = tone('sawtooth', 82, 0.9, 0);
      const o2 = tone('sawtooth', 61, 0.9, 0);
      const f = ctx.createBiquadFilter();
      f.type = 'lowpass'; f.frequency.value = 600; f.Q.value = 6;
      decay(o1.g.gain, 0.16 * a.g, 0.001, t, 0.85);
      decay(o2.g.gain, 0.12 * a.g, 0.001, t, 0.85);
      decay(f.frequency, 900, 220, t, 0.8);
    },
    vurdalak(d) {
      const a = atten(d), t = now();
      const o = tone('sawtooth', 210, 0.55, 0);
      decay(o.g.gain, 0.17 * a.g, 0.001, t, 0.5);
      decay(o.o.frequency, 300, 90, t, 0.5);
      const n = noise(0.5, 0, 'bandpass', 1400, 2);
      decay(n.g.gain, 0.12 * a.g, 0.001, t, 0.45);
    },
    stryga(d) {
      const a = atten(d), t = now();
      const o = tone('sawtooth', 900, 1.0, 0);
      decay(o.g.gain, 0.14 * a.g, 0.001, t, 0.95);
      decay(o.o.frequency, 1500, 320, t, 0.9);
      const o2 = tone('square', 1350, 0.9, 0);
      decay(o2.g.gain, 0.05 * a.g, 0.001, t, 0.85);
    },
    screech(d) {
      const a = atten(d), t = now();
      const o = tone('sawtooth', 1600, 0.8, 0);
      decay(o.g.gain, 0.2 * a.g, 0.001, t, 0.7);
      decay(o.o.frequency, 2400, 400, t, 0.7);
    },
    hurt() {
      const t = now();
      const o = tone('sawtooth', 150, 0.4, 0);
      decay(o.g.gain, 0.22, 0.001, t, 0.35);
      decay(o.o.frequency, 190, 70, t, 0.35);
      const n = noise(0.3, 0, 'lowpass', 900);
      decay(n.g.gain, 0.2, 0.001, t, 0.28);
    },
    guard() {
      const t = now();
      const n = noise(0.16, 0, 'bandpass', 900, 3);
      decay(n.g.gain, 0.3, 0.001, t, 0.14);
      const o = tone('square', 260, 0.12, 0);
      decay(o.g.gain, 0.14, 0.001, t, 0.1);
    },
    pickup() {
      const t = now();
      const o = tone('triangle', 640, 0.18, 0);
      decay(o.g.gain, 0.14, 0.001, t, 0.16);
      o.o.frequency.setValueAtTime(640, t);
      o.o.linearRampToValueAtTime(960, t + 0.09);
    },
    coin() {
      const t = now();
      [1180, 1560].forEach((f, i) => {
        const o = tone('square', f, 0.16, 0);
        o.g.gain.setValueAtTime(0, t + i * 0.05);
        o.g.gain.linearRampToValueAtTime(0.08, t + i * 0.05 + 0.008);
        o.g.gain.exponentialRampToValueAtTime(0.0005, t + i * 0.05 + 0.14);
      });
    },
    deny() {
      const t = now();
      const o = tone('square', 180, 0.18, 0);
      decay(o.g.gain, 0.12, 0.001, t, 0.16);
      decay(o.o.frequency, 180, 90, t, 0.16);
    },
    ui() {
      const t = now();
      const o = tone('sine', 520, 0.08, 0);
      decay(o.g.gain, 0.06, 0.001, t, 0.07);
    },
    heal() {
      const t = now();
      const o = tone('sine', 320, 0.6, 0);
      o.g.gain.setValueAtTime(0.0001, t);
      o.g.gain.exponentialRampToValueAtTime(0.13, t + 0.12);
      o.g.gain.exponentialRampToValueAtTime(0.0005, t + 0.55);
      o.o.frequency.setValueAtTime(320, t);
      o.o.frequency.linearRampToValueAtTime(520, t + 0.5);
    },
    door() {
      const t = now();
      const n = noise(0.8, 0, 'lowpass', 500, 1);
      decay(n.g.gain, 0.22, 0.001, t, 0.7);
      decay(n.f.frequency, 900, 180, t, 0.7);
      const o = tone('sawtooth', 70, 0.7, 0);
      decay(o.g.gain, 0.09, 0.001, t, 0.6);
    },
    break_() {
      const t = now();
      const n = noise(0.35, 0, 'highpass', 1100);
      decay(n.g.gain, 0.4, 0.001, t, 0.3);
    },
    shatter() {
      const t = now();
      const n = noise(0.5, 0, 'highpass', 2400);
      decay(n.g.gain, 0.42, 0.001, t, 0.4);
      const o = tone('sine', 240, 0.5, 0);
      decay(o.g.gain, 0.3, 0.001, t, 0.45);
    },
    save() {
      const t = now();
      [392, 523, 659].forEach((f, i) => {
        const o = tone('sine', f, 1.4, 0);
        o.g.gain.setValueAtTime(0.0001, t + i * 0.16);
        o.g.gain.exponentialRampToValueAtTime(0.1, t + i * 0.16 + 0.08);
        o.g.gain.exponentialRampToValueAtTime(0.0005, t + i * 0.16 + 1.2);
      });
    },
    death() {
      const t = now();
      const o = tone('sawtooth', 120, 2.2, 0);
      decay(o.g.gain, 0.25, 0.0005, t, 2.0);
      decay(o.o.frequency, 120, 28, t, 2.0);
    },
    bossRoar() {
      const t = now();
      const o = tone('sawtooth', 70, 2.4, 0);
      decay(o.g.gain, 0.32, 0.001, t, 2.2);
      o.o.frequency.setValueAtTime(52, t);
      o.o.frequency.linearRampToValueAtTime(96, t + 0.7);
      o.o.frequency.linearRampToValueAtTime(40, t + 2.2);
      const n = noise(2.4, 0, 'bandpass', 420, 1.2);
      decay(n.g.gain, 0.24, 0.001, t, 2.2);
    },
    step(mul) {
      const t = now();
      const n = noise(0.14, 0, 'lowpass', 420 + Math.random() * 200);
      decay(n.g.gain, 0.075 * (mul || 1), 0.0005, t, 0.12);
    },
  };

  function play(name, d) {
    if (!ctx || muted) return;
    const fn = V[name] || V[name + '_'];
    if (!fn) return;
    try { fn(d); } catch (_) { /* an exhausted audio graph must never kill the frame */ }
  }

  // ------------------------------------------------------------ ambience
  function startAmbience() {
    if (!ctx || started) return;
    started = true;
    const src = ctx.createBufferSource();
    src.buffer = noiseBuf; src.loop = true;
    const f = ctx.createBiquadFilter();
    f.type = 'lowpass'; f.frequency.value = 340; f.Q.value = 0.7;
    ambienceGain = ctx.createGain();
    ambienceGain.gain.value = 0.075;
    src.connect(f); f.connect(ambienceGain); ambienceGain.connect(master);
    src.start();
    // slow gusts
    const lfo = ctx.createOscillator(), lfoGain = ctx.createGain();
    lfo.type = 'sine'; lfo.frequency.value = 0.06;
    lfoGain.gain.value = 160;
    lfo.connect(lfoGain); lfoGain.connect(f.frequency);
    lfo.start();

    // low drone bed, gain driven by tension
    musicGain = ctx.createGain();
    musicGain.gain.value = 0;
    musicGain.connect(master);
    [55, 82.5, 110.5].forEach((hz, i) => {
      const o = ctx.createOscillator();
      o.type = i === 2 ? 'triangle' : 'sawtooth';
      o.frequency.value = hz;
      const g = ctx.createGain();
      g.gain.value = i === 2 ? 0.02 : 0.045;
      const lp = ctx.createBiquadFilter();
      lp.type = 'lowpass'; lp.frequency.value = 300;
      o.connect(g); g.connect(lp); lp.connect(musicGain);
      o.start();
    });

    heartGain = ctx.createGain();
    heartGain.gain.value = 0;
    heartGain.connect(master);
  }

  // tension 0..1 raises the drone; hp 0..1 drives the heartbeat
  function setTension(v) {
    if (!musicGain) return;
    musicGain.gain.setTargetAtTime(clamp(v, 0, 1) * 0.55, now(), 1.2);
  }
  function setAmbience(v) {
    if (!ambienceGain) return;
    ambienceGain.gain.setTargetAtTime(clamp(v, 0, 1) * 0.12, now(), 0.6);
  }

  function beat() {
    if (!ctx) return;
    const t = now();
    const o = ctx.createOscillator(), g = ctx.createGain();
    o.type = 'sine'; o.frequency.setValueAtTime(64, t);
    o.frequency.exponentialRampToValueAtTime(34, t + 0.14);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(0.3, t + 0.02);
    g.gain.exponentialRampToValueAtTime(0.0005, t + 0.2);
    o.connect(g); g.connect(master);
    o.start(t); o.stop(t + 0.24);
  }

  // Called every frame; hpFrac below ~0.4 starts the heartbeat and it
  // quickens as the player bleeds out.
  function update(dt, hpFrac) {
    if (!ctx) return;
    if (hpFrac < 0.42) {
      heartRate = lerp(0.95, 0.42, clamp((0.42 - hpFrac) / 0.42, 0, 1));
      heartTimer -= dt;
      if (heartTimer <= 0) { beat(); heartTimer = heartRate; }
    } else heartTimer = 0;
  }

  function setMuted(v) { muted = v; if (master) master.gain.value = v ? 0 : 0.9; }

  return { init, resume, play, startAmbience, setTension, setAmbience, update, setMuted,
           get ready() { return !!ctx; } };
})();
