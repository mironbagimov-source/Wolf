'use strict';
// ---------------------------------------------------------------------
// Mouse + keyboard. Pointer Lock is the good path (raw 1:1 deltas); when
// the browser refuses it — sandboxed iframe, headless run, user denial —
// the same look code is fed by the cursor's offset from the centre of the
// canvas, so the game is never unplayable, only less precise.
// ---------------------------------------------------------------------

const Input = (() => {
  const keys = new Set(), keysPrev = new Set();
  const btns = new Set(), btnsPrev = new Set();
  let lookDX = 0, lookDY = 0;      // raw pixels since last frame (locked mode)
  let steerX = 0, steerY = 0;      // -1..1 offset from centre (fallback mode)
  let wheel = 0;
  let captured = false, locked = false;
  let canvas = null;
  let onCaptureChange = null;

  const TRACKED = new Set([
    'KeyW', 'KeyA', 'KeyS', 'KeyD', 'KeyE', 'KeyR', 'KeyQ', 'KeyH', 'KeyF',
    'ShiftLeft', 'ShiftRight', 'Space', 'Tab', 'ControlLeft', 'ControlRight',
    'Digit1', 'Digit2', 'Digit3', 'Digit4',
  ]);

  const STEER_DEADZONE = 0.08, STEER_RANGE = 0.62;

  function bind(cv, onChange) {
    canvas = cv;
    onCaptureChange = onChange;

    window.addEventListener('keydown', e => {
      if (e.code === 'Tab' || (TRACKED.has(e.code) && captured)) e.preventDefault();
      if (e.repeat) return;
      keys.add(e.code);
    });
    window.addEventListener('keyup', e => keys.delete(e.code));
    window.addEventListener('blur', () => { keys.clear(); btns.clear(); release(); });

    canvas.addEventListener('mousedown', e => {
      e.preventDefault();
      canvas.focus();
      if (!captured) { if (e.button === 0) request(); return; }   // first click only recaptures
      btns.add(e.button);
    });
    window.addEventListener('mouseup', e => btns.delete(e.button));
    canvas.addEventListener('contextmenu', e => e.preventDefault());
    canvas.addEventListener('wheel', e => { if (captured) { e.preventDefault(); wheel += Math.sign(e.deltaY); } }, { passive: false });

    document.addEventListener('mousemove', e => {
      if (captured && locked) { lookDX += e.movementX || 0; lookDY += e.movementY || 0; }
    });
    canvas.addEventListener('mousemove', e => {
      if (locked) return;
      const r = canvas.getBoundingClientRect();
      steerX = clamp(((e.clientX - r.left) / r.width) * 2 - 1, -1, 1);
      steerY = clamp(((e.clientY - r.top) / r.height) * 2 - 1, -1, 1);
    });
    canvas.addEventListener('mouseleave', () => { steerX = 0; steerY = 0; });

    document.addEventListener('pointerlockchange', () => {
      locked = document.pointerLockElement === canvas;
      if (!locked && captured) setCaptured(false);   // native Esc frees the mouse
    });
  }

  function setCaptured(on) {
    if (captured === on) return;
    captured = on;
    canvas.classList.toggle('playing', on);
    if (!on) { steerX = 0; steerY = 0; lookDX = 0; lookDY = 0; btns.clear(); }
    if (onCaptureChange) onCaptureChange(on);
  }

  function request() {
    try {
      const r = canvas.requestPointerLock();
      if (r && r.catch) r.catch(() => {});
    } catch (_) { /* fallback steering carries it */ }
    setCaptured(true);
  }

  function release() {
    if (!captured) return;
    if (locked && document.exitPointerLock) document.exitPointerLock();
    setCaptured(false);
  }

  // Ease the fallback steering so the centre of the screen is calm and the
  // edges turn fast — without this, free-look feels like ice.
  function steerResponse(v) {
    const a = Math.abs(v);
    if (a < STEER_DEADZONE) return 0;
    const t = clamp((a - STEER_DEADZONE) / (STEER_RANGE - STEER_DEADZONE), 0, 1);
    return Math.sign(v) * t * t;
  }

  // Consumed once per frame by the player controller.
  function takeLook(dt, sens) {
    let yaw = 0, pitch = 0;
    if (locked) {
      yaw = -lookDX * sens;
      pitch = -lookDY * sens;
    } else if (captured) {
      const S = 2.6;      // rad/s at full deflection
      yaw = -steerResponse(steerX) * S * dt;
      pitch = -steerResponse(steerY) * S * 0.75 * dt;
    }
    lookDX = 0; lookDY = 0;
    return { yaw, pitch };
  }

  function endFrame() {
    keysPrev.clear(); keys.forEach(k => keysPrev.add(k));
    btnsPrev.clear(); btns.forEach(b => btnsPrev.add(b));
    wheel = 0;
  }

  return {
    bind, request, release,
    held: c => keys.has(c),
    pressed: c => keys.has(c) && !keysPrev.has(c),
    mouseHeld: b => btns.has(b),
    mousePressed: b => btns.has(b) && !btnsPrev.has(b),
    takeLook, endFrame,
    get wheel() { return wheel; },
    get captured() { return captured; },
    get locked() { return locked; },
    clearKeys() { keys.clear(); keysPrev.clear(); btns.clear(); btnsPrev.clear(); },
  };
})();
