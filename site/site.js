// Passionfruit launch site: spring physics, scroll-driven scenes, and the New York City waitlist.
import { boroughForZip } from './nyc.mjs';
import { SUPABASE_URL, SUPABASE_KEY } from './config.js';

const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const clamp = (v, lo = 0, hi = 1) => Math.min(hi, Math.max(lo, v));
const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;

/* ───────── Spring: a damped harmonic oscillator, integrated every frame ───────── */
class Spring {
  constructor(x = 0, k = 110, c = 16) { this.x = x; this.v = 0; this.t = x; this.k = k; this.c = c; }
  step(dt) {
    const a = -this.k * (this.x - this.t) - this.c * this.v;
    this.v += a * dt;
    this.x += this.v * dt;
    if (!Number.isFinite(this.x) || !Number.isFinite(this.v)) this.snap(Number.isFinite(this.t) ? this.t : 0); // self-heal
  }
  get resting() { return Math.abs(this.v) < 0.002 && Math.abs(this.x - this.t) < 0.0005; }
  snap(x) { this.x = this.t = x; this.v = 0; }
}

const tickers = new Set(); // functions called every frame with dt in seconds
const painters = new Set(); // functions called once per frame to draw
const pointer = { x: -9999, y: -9999 }; // client coordinates
addEventListener('pointermove', (e) => { pointer.x = e.clientX; pointer.y = e.clientY; }, { passive: true });
addEventListener('pointerleave', () => { pointer.x = pointer.y = -9999; });

/** Sizes a canvas to its CSS box at device resolution; returns a getter for the CSS size. */
function fitCanvas(cv, onResize) {
  const size = { w: 0, h: 0, dpr: 1 };
  const fit = () => {
    size.dpr = Math.min(2, devicePixelRatio || 1);
    size.w = cv.clientWidth; size.h = cv.clientHeight;
    cv.width = Math.max(1, Math.round(size.w * size.dpr));
    cv.height = Math.max(1, Math.round(size.h * size.dpr));
    onResize?.();
  };
  new ResizeObserver(fit).observe(cv);
  fit();
  return size;
}
let last = performance.now();
let scrollDirty = true;
addEventListener('scroll', () => { scrollDirty = true; }, { passive: true });
addEventListener('resize', () => { scrollDirty = true; });

function frame(now) {
  const dt = Math.min(0.12, (now - last) / 1000);
  last = now;
  // fixed small sub-steps: springs stay stable and keep real-time speed at any frame rate
  const n = Math.max(1, Math.ceil(dt / 0.008));
  for (const fn of tickers) for (let i = 0; i < n; i++) fn(dt / n, now);
  for (const fn of painters) fn(now); // canvas drawing: once per frame, after the physics
  scrollDirty = false;
  requestAnimationFrame(frame);
}

/* ───────── Watercolor wash (same recipe as marketing/src/Watercolor.tsx) ───────── */
let washId = 0;
function washSVG(color, seed) {
  const id = `wash${washId++}`;
  return `<svg viewBox="-150 -150 300 300" aria-hidden="true"><defs>
    <radialGradient id="${id}g"><stop offset="0" stop-color="${color}" stop-opacity=".3"/><stop offset=".55" stop-color="${color}" stop-opacity=".42"/><stop offset=".86" stop-color="${color}" stop-opacity=".62"/><stop offset=".97" stop-color="${color}" stop-opacity=".95"/><stop offset="1" stop-color="${color}" stop-opacity="0"/></radialGradient>
    <filter id="${id}f" x="-60%" y="-60%" width="220%" height="220%" color-interpolation-filters="sRGB">
      <feTurbulence type="fractalNoise" baseFrequency=".013" numOctaves="4" seed="${seed}" result="big"/>
      <feDisplacementMap in="SourceGraphic" in2="big" scale="42" xChannelSelector="R" yChannelSelector="G" result="torn"/>
      <feTurbulence type="fractalNoise" baseFrequency=".07" numOctaves="2" seed="${seed + 7}" result="fine"/>
      <feDisplacementMap in="torn" in2="fine" scale="5" xChannelSelector="G" yChannelSelector="B" result="edge"/>
      <feGaussianBlur in="edge" stdDeviation=".6"/>
    </filter></defs>
    <circle r="100" fill="url(#${id}g)" filter="url(#${id}f)" opacity=".88"/></svg>`;
}
const WASH = { blush: '#F3B3A2', sage: '#A9D2B8', butter: '#F2D98A', sky: '#A9C6E8', lilac: '#C5B4E3' };

// The face of the app's little characters: two dot eyes, a smile, rosy cheeks, one highlight.
const BUDDY_FACE = `<svg class="face" viewBox="-150 -150 300 300" aria-hidden="true">
  <rect x="-62" y="-66" width="50" height="16" rx="8" fill="#fff" opacity=".8" transform="rotate(-28 -37 -58)"/>
  <circle cx="-58" cy="-28" r="4.5" fill="#fff" opacity=".75"/>
  <circle cx="-50" cy="16" r="13" fill="#E4532F" opacity=".26"/><circle cx="50" cy="16" r="13" fill="#E4532F" opacity=".26"/>
  <g class="eyes"><g class="blink"><circle cx="-29" cy="-12" r="10" fill="#33292F"/><circle cx="29" cy="-12" r="10" fill="#33292F"/></g></g>
  <path class="mouth" d="M-19 22Q0 42 19 22" fill="none" stroke="#33292F" stroke-width="7" stroke-linecap="round"/></svg>`;

const buddySVG = () => washSVG('#F2B98C', 33).replace('<svg ', '<svg class="body" ') + BUDDY_FACE;

/* ───────── Hero: two people who spring toward each other ───────── */
let mapReady = false;      // the map is drawn and may take the stage
let playJoin = () => {};   // just signed up: the two meet, become one, then the map
function initMeet() {
  const meet = $('#meet'), stage = $('#meetStage');
  // A wash as a picture: the browser paints its torn edge once and from then on only slides and fades it.
  const washImg = (color, seed) => `<img alt="" draggable="false" src="data:image/svg+xml;utf8,${encodeURIComponent(washSVG(color, seed).replace('<svg ', '<svg xmlns="http://www.w3.org/2000/svg" '))}">`;
  // Coral and butter: together they make the character's peach.
  const blobs = $$('.blob', stage).map((el, i) => {
    el.innerHTML = washImg(i ? WASH.butter : '#F08F7A', i ? 21 : 8);
    const base = i ? { x: 0.21, y: 0.06 } : { x: -0.21, y: -0.05 };
    return { el, base, x: base.x, y: base.y };
  });
  // The one the two become: a single wash that opens its eyes, like the match screen in the app.
  const buddy = document.createElement('div');
  buddy.className = 'buddy';
  buddy.innerHTML = washImg('#F2B98C', 33) + BUDDY_FACE;
  stage.appendChild(buddy);

  let W = stage.offsetWidth, pull = 0, held = 0, near = 1, grow = 0.6, mutual = false, flipped = 0;
  let joinAt = 0, forced = false; // a fresh sign-up plays the whole sequence on its own, then keeps the map up
  playJoin = () => { joinAt = performance.now(); };
  const pin = $('#heroPin'), hero = $('.hero'), hold = $('#heroHold');
  let pinStart = 0, pinLen = 1;
  const probe = document.createElement('div'); // as tall as the window with the browser's bars showing
  probe.style.cssText = 'position:fixed;left:0;top:0;width:0;height:100svh;visibility:hidden;pointer-events:none';
  document.body.appendChild(probe);
  const measure = () => {
    W = stage.offsetWidth;
    // A hero taller than the window sticks once its bottom edge reaches the bottom of the window.
    // Measured with svh, not innerHeight: on a phone innerHeight changes mid-scroll as the address bar hides, and the hero would jump.
    const over = Math.max(0, hero.offsetHeight - (probe.offsetHeight || innerHeight));
    hero.style.setProperty('--pin-top', `${-over}px`);
    pinStart = pin.offsetTop + over; pinLen = hold.offsetHeight;
  };
  new ResizeObserver(measure).observe(hero);
  addEventListener('resize', measure);
  new ResizeObserver(measure).observe(stage);

  const draw = () => {
    for (const b of blobs) b.el.style.transform = `translate3d(${(b.x * W).toFixed(1)}px,${(b.y * W).toFixed(1)}px,0)`;
    buddy.style.transform = `scale(${grow.toFixed(3)})`;
  };
  if (reduce) { draw(); return; }

  // One motion, driven by the scroll: the two slide toward the middle, and past a point they are one.
  tickers.add((dt, now) => {
    if (scrollDirty) {
      held = clamp((scrollY - pinStart) / (pinLen || 1)) || 0; // how far through the hold
      pull = clamp(held / 0.3); // they have met in the first third of it; the rest is for watching
    }
    // Someone on the list gets one more act: the character gives way to the map of who else is on it.
    const joining = joinAt > 0 && now - joinAt < 2300;
    if (joinAt > 0 && !joining) forced = true;
    const onMap = mapReady && (forced || held > 0.55);
    if (onMap !== meet.classList.contains('mapped')) meet.classList.toggle('mapped', onMap);
    const together = onMap || joining;
    // A wide gap between on and off, and a short rest after each change, so a fast flick never makes it flicker.
    const next = together || (mutual ? pull > 0.5 : pull > 0.8);
    if (next !== mutual && now - flipped > 450) { flipped = now; mutual = next; meet.classList.toggle('mutual', mutual); }
    const ease = 1 - Math.exp(-dt * 12); // follows the scroll closely, without a bounce
    near += ((together || mutual ? 0 : 1 - pull) - near) * ease;
    grow += ((mutual ? 1 : 0.6) - grow) * ease;
    for (const b of blobs) { b.x = b.base.x * near; b.y = b.base.y * near; }
  });
  painters.add(draw);
}

/* ───────── Manhattan skyline: watercolor buildings on springs, driven by scroll ───────── */
function initSkyline() {
  const cv = $('#skyline');
  const ctx = cv.getContext('2d');
  let seed = 11;
  const rnd = () => { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 4294967296; };
  const INK = { blush: '243,179,162', sage: '150,200,172', butter: '240,210,120', sky: '160,192,230', lilac: '190,172,224', accent: '228,83,47' };
  // Outlines in building units: x across, y up from the ground.
  const SHAPES = {
    box: (w, h) => [[0, 0], [0, h], [w, h], [w, 0]],
    slant: (w, h) => [[0, 0], [0, h * 0.82], [w, h], [w, 0]],
    tank: (w, h) => [[0, 0], [0, h * 0.86], [w * 0.3, h * 0.86], [w * 0.3, h], [w * 0.62, h], [w * 0.62, h * 0.86], [w, h * 0.86], [w, 0]],
    empire: (w, h) => [[0, 0], [0, h * 0.58], [w * 0.14, h * 0.58], [w * 0.14, h * 0.74], [w * 0.3, h * 0.74], [w * 0.3, h * 0.84], [w * 0.43, h * 0.84], [w * 0.47, h], [w * 0.53, h], [w * 0.57, h * 0.84], [w * 0.7, h * 0.84], [w * 0.7, h * 0.74], [w * 0.86, h * 0.74], [w * 0.86, h * 0.58], [w, h * 0.58], [w, 0]],
    chrysler: (w, h) => [[0, 0], [0, h * 0.6], [w * 0.12, h * 0.65], [w * 0.2, h * 0.72], [w * 0.3, h * 0.78], [w * 0.38, h * 0.84], [w * 0.46, h * 0.88], [w * 0.5, h], [w * 0.54, h * 0.88], [w * 0.62, h * 0.84], [w * 0.7, h * 0.78], [w * 0.8, h * 0.72], [w * 0.88, h * 0.65], [w, h * 0.6], [w, 0]],
    wtc: (w, h) => [[0, 0], [w * 0.2, h * 0.8], [w * 0.46, h * 0.8], [w * 0.48, h], [w * 0.52, h], [w * 0.54, h * 0.8], [w * 0.8, h * 0.8], [w, 0]],
  };
  // Hand-painted edge: split every side into short runs and nudge each point.
  const rough = (pts, amp) => {
    const out = [];
    for (let i = 0; i < pts.length - 1; i++) {
      const [x0, y0] = pts[i], [x1, y1] = pts[i + 1];
      const n = Math.max(1, Math.round(Math.hypot(x1 - x0, y1 - y0) / 16));
      for (let j = 0; j < n; j++) {
        const t = j / n;
        out.push([x0 + (x1 - x0) * t + (rnd() - 0.5) * amp, y0 + (y1 - y0) * t + (j || i ? (rnd() - 0.5) * amp : 0)]);
      }
    }
    out.push(pts[pts.length - 1]);
    return out;
  };
  const gauss = (x, m, s) => Math.exp(-(((x - m) / s) ** 2));
  const rise = (x) => 95 * gauss(x, 290, 80) + 120 * gauss(x, 590, 150); // downtown and midtown
  const list = [];
  const add = (x, w, h, shape, c, layer) => {
    const base = SHAPES[shape](w, h);
    list.push({
      x, w, h, c: INK[c], layer, a: rough(base, 2.200), b: rough(base, 3.600),
      sp: new Spring(0, 55 + rnd() * 45, 6 + rnd() * 3.500), kick: 0.4 + rnd() * 0.8,
      delay: 250 + x * 0.9 + rnd() * 220, born: false,
    });
  };
  const pick = (arr) => arr[Math.floor(rnd() * arr.length)];
  for (let x = -30; x < 1030;) { // far row: pale and tall
    const w = 22 + rnd() * 30;
    add(x, w, 46 + rnd() * 70 + rise(x + w / 2), rnd() < 0.2 ? 'slant' : 'box', pick(['sky', 'lilac', 'sage', 'sky']), 0);
    x += w + rnd() * 4 - 6;
  }
  add(273, 36, 292, 'wtc', 'sky', 1);       // One World Trade
  add(386, 30, 204, 'slant', 'lilac', 1);
  add(476, 52, 264, 'empire', 'blush', 1);  // Empire State
  add(598, 36, 238, 'chrysler', 'butter', 1); // Chrysler
  add(690, 13, 284, 'box', 'lilac', 1);     // a pencil tower
  add(756, 34, 188, 'slant', 'sage', 1);
  for (let x = -20; x < 1020;) { // near row: low and warm
    const w = 16 + rnd() * 26;
    add(x, w, 22 + rnd() * 46 + rise(x + w / 2) * 0.42, rnd() < 0.22 ? 'tank' : 'box', rnd() < 0.07 ? 'accent' : pick(['blush', 'butter', 'sage', 'sky', 'blush']), 2);
    x += w + rnd() * 10 - 3;
  }
  list.sort((p, q) => p.layer - q.layer);
  const blots = Array.from({ length: 7 }, (_, i) => {
    const n = 26, pts = [];
    for (let j = 0; j < n; j++) pts.push(0.72 + rnd() * 0.5);
    return { x: 60 + i * 150 + rnd() * 60, y: 0.3 + rnd() * 0.4, r: 70 + rnd() * 70, c: INK[['blush', 'sky', 'butter', 'sage', 'lilac', 'blush', 'sky'][i]], pts, drift: rnd() * 2 - 1, sp: new Spring(0, 30, 9) };
  });

  const size = fitCanvas(cv);
  const t0 = performance.now();
  let p = 0, visible = true, lastY = scrollY, band = 1;
  new IntersectionObserver(([e]) => { visible = e.isIntersecting; }).observe(cv);
  const geo = () => {
    const s = Math.max(size.w / 1000, 0.62); // phones see a crop of midtown, not a squeezed city
    return { s, ox: (size.w - 1000 * s) / 2, vy: (size.h - 8) / 300, ground: size.h - 3 };
  };

  if (reduce) {
    for (const b of list) b.sp.snap(1);
    for (const b of blots) b.sp.snap(1);
  } else {
    addEventListener('scroll', () => { // scroll speed knocks the buildings like a bar graph
      const dy = clamp(scrollY - lastY, -90, 90);
      lastY = scrollY;
      if (visible) for (const b of list) b.sp.v -= dy * 0.016 * b.kick;
    }, { passive: true });
    tickers.add((dt, now) => {
      if (!visible) return;
      if (scrollDirty) { band = cv.offsetTop + size.h || 1; p = clamp(scrollY / band); }
      const { s, ox } = geo();
      const r = cv.getBoundingClientRect();
      const near = pointer.y > r.top - 40 && pointer.y < r.bottom + 60;
      for (const b of list) {
        if (!b.born && now - t0 > b.delay) b.born = true;
        const cx = b.x + b.w / 2;
        const sink = clamp(p * 1.7 - (cx / 1000) * 0.6); // a wave that runs downtown to uptown
        const lift = near ? 0.13 * gauss(pointer.x - r.left, ox + cx * s, 70) : 0;
        b.sp.t = b.born ? 1 - 0.72 * sink * sink * (3 - 2 * sink) + lift : 0;
        b.sp.step(dt);
      }
      for (const b of blots) { b.sp.t = now - t0 > 150 ? 1 + p * 0.9 : 0; b.sp.step(dt); }
    });
  }

  const paint = (now) => {
    if (!visible || !size.w) return;
    const { w, h, dpr } = size, { s, ox, vy, ground } = geo();
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, h);
    ctx.globalCompositeOperation = 'multiply';
    for (const b of blots) { // loose blots of wash behind the buildings
      const k = Math.max(0, b.sp.x), R = b.r * s * (0.5 + 0.5 * k) * (h / 240);
      const cx = ox + (b.x + b.drift * p * 90) * s, cy = h * b.y + Math.sin(now / 2600 + b.x) * 4;
      const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, R * 1.2);
      g.addColorStop(0, `rgba(${b.c},${0.16 * Math.min(1, k)})`);
      g.addColorStop(0.75, `rgba(${b.c},${0.3 * Math.min(1, k)})`);
      g.addColorStop(1, `rgba(${b.c},${0.42 * Math.min(1, k)})`);
      ctx.fillStyle = g;
      ctx.beginPath();
      b.pts.forEach((q, i) => {
        const a = (i / b.pts.length) * Math.PI * 2;
        ctx[i ? 'lineTo' : 'moveTo'](cx + Math.cos(a) * R * q * 1.25, cy + Math.sin(a) * R * q * 0.8);
      });
      ctx.closePath();
      ctx.fill();
    }
    for (const b of list) {
      const k = b.sp.x;
      if (k < 0.01) continue;
      const top = ground - b.h * vy * k, x0 = ox + b.x * s + (b.layer - 1) * p * 14;
      const alpha = [0.36, 0.7, 0.56][b.layer];
      const g = ctx.createLinearGradient(0, top, 0, ground);
      g.addColorStop(0, `rgba(${b.c},${alpha})`);
      g.addColorStop(0.7, `rgba(${b.c},${alpha * 0.72})`);
      g.addColorStop(1, `rgba(${b.c},${alpha * 0.3})`); // pigment thins out where it meets wet paper
      ctx.fillStyle = g;
      for (const pts of [b.a, b.b]) {
        ctx.beginPath();
        pts.forEach(([x, y], i) => ctx[i ? 'lineTo' : 'moveTo'](x0 + x * s, ground - y * vy * k));
        ctx.closePath();
        ctx.fill();
      }
    }
    ctx.globalCompositeOperation = 'source-over';
    ctx.fillStyle = 'rgba(27,23,25,.16)';
    ctx.fillRect(0, ground + 1, w, 1);
  };
  if (reduce) { new ResizeObserver(() => paint(0)).observe(cv); paint(0); } else painters.add(paint);
}

/* ───────── Spring reveals ───────── */
function initReveals() {
  const lines = $$('h1 [data-line]');
  const rises = $$('[data-rise]');
  if (reduce) return;
  const live = new Set();
  const launch = (el, delay, dist, unit, k = 110, c = 15) => {
    const sp = new Spring(1, k, c);
    setTimeout(() => { sp.t = 0; live.add({ el, sp, dist, unit }); }, delay);
  };
  lines.forEach((el, i) => launch(el, 120 + i * 95, 110, '%', 95, 16));

  const io = new IntersectionObserver((entries) => {
    let i = 0;
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      io.unobserve(e.target);
      launch(e.target, i++ * 75, 34, 'px');
    }
  }, { rootMargin: '0px 0px -8% 0px', threshold: 0.12 });
  rises.forEach((el) => io.observe(el));

  tickers.add((dt) => {
    for (const item of live) {
      const { el, sp, dist, unit } = item;
      sp.step(dt);
      if (sp.resting) {
        el.style.transform = 'none'; el.style.opacity = '1'; el.style.willChange = 'auto';
        live.delete(item);
        continue;
      }
      el.style.transform = `translate3d(0,${sp.x * dist}${unit},0)`;
      if (unit === 'px') el.style.opacity = clamp(1 - sp.x * 1.15);
    }
  });
}

/* ───────── Statement: words light up as you scroll ───────── */
function initSay() {
  const el = $('#say');
  const words = el.textContent.trim().split(/\s+/);
  el.setAttribute('aria-label', words.join(' '));
  el.innerHTML = words.map((w) => `<span class="w" aria-hidden="true">${w}</span>`).join(' ');
  if (reduce) return;
  const spans = $$('.w', el);
  let lit = -1;
  tickers.add(() => {
    if (!scrollDirty) return;
    const r = el.getBoundingClientRect();
    const p = clamp((innerHeight * 0.86 - r.top) / (r.height + innerHeight * 0.36));
    const n = Math.round(p * spans.length);
    if (n === lit) return;
    lit = n;
    spans.forEach((s, i) => s.classList.toggle('lit', i < n));
  });
}

/* ───────── The date: sticky stage, four chapters, a clock that drains with scroll ───────── */
function initDate() {
  const stage = $('#stage'), stepsEl = $('#steps');
  const steps = $$('.step', stepsEl), shots = $$('.shot', stage);
  const arc = $('#clockArc'), num = $('#clockNum'), clock = $('.clock', stage);
  const toggle = $('#motionToggle');
  const videos = shots.map((s) => $('video', s));
  const q = new Spring(0, 130, 23); // critically damped: follows the scroll without wobble
  let active = 0, visible = false, paused = reduce, shown = '';

  const syncVideos = () => {
    videos.forEach((v, i) => {
      if (!v) return;
      if (visible && !paused && i === active) v.play().catch(() => {});
      else v.pause();
    });
  };
  const setPaused = (p) => {
    paused = p;
    toggle.textContent = p ? 'Play motion' : 'Pause motion';
    toggle.setAttribute('aria-pressed', String(p));
    syncVideos();
    const bg = $('#closeBg');
    if (p) bg.pause(); else if (bg.dataset.visible) bg.play().catch(() => {});
  };
  toggle.addEventListener('click', () => setPaused(!paused));
  setPaused(paused);

  new IntersectionObserver(([e]) => { visible = e.isIntersecting; syncVideos(); }, { threshold: 0.2 }).observe(stage);
  const bg = $('#closeBg');
  new IntersectionObserver(([e]) => {
    if (e.isIntersecting) { bg.dataset.visible = '1'; if (!paused) bg.play().catch(() => {}); }
    else { delete bg.dataset.visible; bg.pause(); }
  }, { threshold: 0.05 }).observe(bg);

  tickers.add((dt) => {
    if (scrollDirty) {
      const sr = stage.getBoundingClientRect();
      const stacked = sr.width > innerWidth * 0.8; // phone layout: stage sits above the steps
      const mid = stacked ? (sr.bottom + innerHeight) / 2 : innerHeight / 2;
      let best = 0, bestD = Infinity;
      steps.forEach((s, i) => {
        const r = s.getBoundingClientRect();
        const d = Math.abs((r.top + r.bottom) / 2 - mid);
        if (d < bestD) { bestD = d; best = i; }
      });
      if (best !== active) {
        active = best;
        steps.forEach((s, i) => s.classList.toggle('on', i === active));
        shots.forEach((s, i) => s.classList.toggle('on', i === active));
        syncVideos();
      }
      const c = (el) => { const b = el.getBoundingClientRect(); return (b.top + b.bottom) / 2; };
      const c0 = c(steps[0]), c2 = c(steps[2]);
      q.t = clamp((mid - c0) / (c2 - c0 || 1)); // 0 at the middle of step one, 1 at the middle of "Answer in private"
      if (reduce) q.snap(q.t);
    }
    q.step(dt);
    const left = Math.round(240 * (1 - clamp(q.x)));
    const text = `${Math.floor(left / 60)}:${String(left % 60).padStart(2, '0')}`;
    if (text !== shown) {
      shown = text;
      num.textContent = text;
      arc.style.transform = `scaleX(${left / 240})`;
      clock.classList.toggle('low', left <= 30);
    }
  });
}

/* ───────── Boroughs: names slide home on springs, rules draw across ───────── */
function initBoroughs() {
  const rows = $$('#boroughs li').map((li, i) => ({ li, name: $('.b-name', li), i, sp: new Spring(0, 85, 15), last: null }));
  if (reduce) return;
  tickers.add((dt) => {
    for (const r of rows) {
      if (scrollDirty) {
        const b = r.li.getBoundingClientRect();
        r.sp.t = clamp((innerHeight * 0.96 - b.top) / (innerHeight * 0.42));
      }
      r.sp.step(dt);
      const v = Math.round(r.sp.x * 1000) / 1000;
      if (v === r.last) continue;
      r.last = v;
      r.name.style.transform = `translate3d(${(1 - v) * (5 + r.i * 2.6)}vw,0,0)`;
      r.name.style.opacity = clamp(0.15 + v * 0.85);
      r.li.style.setProperty('--rule', clamp(v));
    }
  });
}

/* ───────── After sign-up: the two washes become New York City ─────────
   Simplified borough outlines as [longitude, latitude]. Dots are one per person on the list,
   placed inside that person's borough. The list stores a ZIP code, never an address, so a dot
   shows the borough someone is in and nothing finer. */
const NYC_SHAPES = {
  'The Bronx': { color: WASH.sky, ink: '#5E86BD', rings: [[[-73.933, 40.882], [-73.912, 40.915], [-73.855, 40.905], [-73.825, 40.890], [-73.783, 40.880], [-73.780, 40.845], [-73.800, 40.815], [-73.840, 40.805], [-73.880, 40.800], [-73.910, 40.795], [-73.932, 40.808], [-73.933, 40.835], [-73.922, 40.860], [-73.910, 40.873]]] },
  Manhattan: { color: WASH.blush, ink: '#D9694C', rings: [[[-74.019, 40.700], [-74.013, 40.716], [-74.010, 40.740], [-73.995, 40.775], [-73.960, 40.830], [-73.935, 40.877], [-73.912, 40.872], [-73.930, 40.845], [-73.934, 40.810], [-73.928, 40.795], [-73.942, 40.776], [-73.960, 40.755], [-73.971, 40.740], [-73.972, 40.725], [-73.975, 40.710], [-73.997, 40.707]]] },
  Queens: { color: WASH.butter, ink: '#C99A2E', rings: [
    [[-73.962, 40.738], [-73.938, 40.778], [-73.912, 40.790], [-73.875, 40.785], [-73.850, 40.800], [-73.790, 40.797], [-73.752, 40.780], [-73.702, 40.752], [-73.708, 40.726], [-73.728, 40.680], [-73.742, 40.640], [-73.768, 40.618], [-73.822, 40.640], [-73.857, 40.648], [-73.868, 40.694], [-73.903, 40.690], [-73.928, 40.727]],
    [[-73.745, 40.598], [-73.800, 40.585], [-73.870, 40.572], [-73.938, 40.552], [-73.940, 40.562], [-73.870, 40.584], [-73.800, 40.598], [-73.750, 40.610]],
  ] },
  Brooklyn: { color: WASH.sage, ink: '#3F9B70', rings: [[[-73.962, 40.738], [-73.928, 40.727], [-73.903, 40.690], [-73.868, 40.694], [-73.857, 40.648], [-73.880, 40.625], [-73.900, 40.600], [-73.935, 40.585], [-73.940, 40.575], [-74.000, 40.570], [-74.012, 40.580], [-74.035, 40.610], [-74.040, 40.625], [-74.025, 40.650], [-74.015, 40.665], [-74.018, 40.678], [-73.998, 40.700], [-73.970, 40.708], [-73.962, 40.720]]] },
  'Staten Island': { color: WASH.lilac, ink: '#8C72C4', rings: [[[-74.075, 40.645], [-74.055, 40.605], [-74.070, 40.590], [-74.110, 40.555], [-74.150, 40.530], [-74.215, 40.500], [-74.250, 40.498], [-74.255, 40.515], [-74.235, 40.555], [-74.205, 40.590], [-74.200, 40.630], [-74.180, 40.645], [-74.130, 40.642], [-74.090, 40.648]]] },
};
const MAP_SPAN = 0.4245; // degrees of latitude the 280-unit drawing area covers
const project = ([lon, lat]) => [10 + ((lon + 74.26) * 0.758 / MAP_SPAN) * 280, 10 + ((40.917 - lat) / MAP_SPAN) * 280];
for (const shape of Object.values(NYC_SHAPES)) shape.rings = shape.rings.map((ring) => ring.map(project));

function inRing(ring, x, y) {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i], [xj, yj] = ring[j];
    if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}
function seeded(seed) { // small repeatable generator, so the same list always draws the same map
  let a = seed >>> 0;
  return () => { a = (a + 0x6D2B79F5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
function pointsIn(shape, count, seed) {
  const rnd = seeded(seed), all = shape.rings.flat(), out = [];
  const xs = all.map((p) => p[0]), ys = all.map((p) => p[1]);
  const x0 = Math.min(...xs), x1 = Math.max(...xs), y0 = Math.min(...ys), y1 = Math.max(...ys);
  for (let tries = 0; out.length < count && tries < count * 60; tries++) {
    const x = x0 + rnd() * (x1 - x0), y = y0 + rnd() * (y1 - y0);
    if (shape.rings.some((ring) => inRing(ring, x, y))) out.push([x, y]);
  }
  return out;
}

// Behind the map: soft white waves, layered like sheets of modelling clay, sliding past each
// other and fading into the paper at the edges.
function wavesSVG() {
  const rows = [ // y of the crest, height of the swell, seconds per loop, direction, fill
    [36, 9, 46, 1, '#FFFFFF'], [84, 11, 34, -1, '#F4F8FC'], [132, 10, 40, 1, '#FFFFFF'],
    [180, 12, 30, -1, '#EEF4FA'], [228, 10, 38, 1, '#FFFFFF'], [272, 9, 44, -1, '#F2F7FB'],
  ];
  // Each band is twice the stage wide and slides by one swell (a quarter of its width), which loops without a seam.
  return rows.map(([y, amp, secs, dir, fill], n) => {
    let d = `M-150 ${y}`;
    for (let x = -150; x < 450; x += 150) d += `q37.5 ${-amp} 75 0t75 0`;
    d += `V${y + 90}H-150Z`;
    return `<div class="wave" style="--secs:${secs}s;--to:${dir * 25}%"><svg viewBox="-150 0 600 300" preserveAspectRatio="none" aria-hidden="true"><defs>
      <filter id="clay${n}" x="-5%" y="-30%" width="110%" height="160%" color-interpolation-filters="sRGB"><feDropShadow dx="0" dy="-2.5" stdDeviation="3" flood-color="#7E9CC2" flood-opacity=".2"/></filter>
      </defs><path d="${d}" fill="${fill}" filter="url(#clay${n})"/></svg></div>`;
  }).join('');
}

const MAP_DOTS_MAX = 140; // per borough; past this the map would turn solid
let mapState = null; // { borough, zip } once this visitor has joined
function renderMap(stats) {
  if (!mapState) return;
  const meet = $('#meet'), stage = $('#meetStage');
  let map = $('#nycMap');
  if (!map) {
    map = document.createElement('div');
    map.id = 'nycMap'; map.className = 'nyc-map';
    const water = document.createElement('div');
    water.className = 'water';
    water.innerHTML = wavesSVG();
    stage.appendChild(water);
    stage.appendChild(map);
  }
  const names = Object.keys(NYC_SHAPES);
  const land = names.map((name, i) => {
    const sh = NYC_SHAPES[name];
    const d = sh.rings.map((ring) => 'M' + ring.map((p) => p.map((v) => v.toFixed(1)).join(' ')).join('L') + 'Z').join('');
    return `<path d="${d}" fill="${sh.color}" stroke="${sh.color}" stroke-width="5" stroke-linejoin="round" filter="url(#nycTorn${i % 2})" class="${name === mapState.borough ? 'mine' : ''}"/>`;
  }).join('');
  let dots = '', order = 0;
  names.forEach((name, i) => {
    const sh = NYC_SHAPES[name];
    const others = Math.max(0, (stats?.boroughs?.[name] ?? 0) - (name === mapState.borough ? 1 : 0));
    for (const [x, y] of pointsIn(sh, Math.min(others, MAP_DOTS_MAX), 101 + i * 977)) {
      const r = 1.5 + ((x * 7 + y * 13) % 10) / 9;
      dots += `<circle class="dot" cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="${r.toFixed(2)}" fill="${sh.ink}" style="--d:${(600 + (order++ % 60) * 28)}ms"/>`;
    }
  });
  const names_ = names.map((name) => { // a name on each borough; Manhattan is too thin, so its name sits in the Hudson
    const ring = NYC_SHAPES[name].rings[0];
    const cx = ring.reduce((a, p) => a + p[0], 0) / ring.length, cy = ring.reduce((a, p) => a + p[1], 0) / ring.length;
    const side = name === 'Manhattan';
    return `<text class="b-label${name === mapState.borough ? ' mine' : ''}" x="${(side ? cx - 13 : cx).toFixed(1)}" y="${(cy + 2.5).toFixed(1)}" text-anchor="${side ? 'end' : 'middle'}">${name}</text>`;
  }).join('');
  const [mx, my] = pointsIn(NYC_SHAPES[mapState.borough], 1, Number(mapState.zip) || 7)[0] ?? [150, 150];
  const anchor = mx > 232 ? 'end' : 'start', lx = mx + (mx > 232 ? -8 : 8);
  map.innerHTML = `<svg viewBox="0 0 300 300" role="img" aria-label="Map of New York City with a dot for each person on the list"><defs>
    <filter id="nycTorn0" x="-10%" y="-10%" width="120%" height="120%" color-interpolation-filters="sRGB"><feTurbulence type="fractalNoise" baseFrequency=".035" numOctaves="3" seed="12"/><feDisplacementMap in="SourceGraphic" scale="9" xChannelSelector="R" yChannelSelector="G"/><feGaussianBlur stdDeviation=".7"/></filter>
    <filter id="nycTorn1" x="-10%" y="-10%" width="120%" height="120%" color-interpolation-filters="sRGB"><feTurbulence type="fractalNoise" baseFrequency=".04" numOctaves="3" seed="41"/><feDisplacementMap in="SourceGraphic" scale="8" xChannelSelector="G" yChannelSelector="B"/><feGaussianBlur stdDeviation=".7"/></filter>
    </defs><g class="under">${land}</g><g class="land">${land}</g>${names_}${dots}
    <circle class="you" cx="${mx.toFixed(1)}" cy="${my.toFixed(1)}" r="4.2"/>
    <text class="you-label" x="${lx.toFixed(1)}" y="${(my + 3.6).toFixed(1)}" text-anchor="${anchor}">You</text></svg>`;

  const total = stats?.total ?? 0, others = Math.max(0, total - 1);
  $('[data-cap=map]').textContent = !stats ? `You’re on the map, in ${mapState.borough}.`
    : others === 0 ? 'You’re the first dot on the map.'
    : `You and ${others.toLocaleString('en-US')} other${others === 1 ? '' : 's'} across the five boroughs.`;
  mapReady = true; // initMeet brings it on: after the two have become one
  if (reduce) meet.classList.add('mapped');
}

/* ───────── Waitlist ───────── */
const KEY = 'tempo.waitlist';
const read = () => { try { return JSON.parse(localStorage.getItem(KEY)); } catch { return null; } };
const save = (v) => { try { localStorage.setItem(KEY, JSON.stringify(v)); } catch { /* private window */ } };

// Two back ends with one shape. With a public Supabase key (static hosting) the form calls the
// database functions directly; without one it talks to the local server in serve.mjs.
// Both resolve to { ok, error?, message?, borough, position, boroughPosition, already, stats }.
const local = ['localhost', '127.0.0.1', '[::1]'].includes(location.hostname);
const hosted = Boolean(SUPABASE_KEY) && !local; // on your own machine serve.mjs answers instead
async function rpc(fn, args = {}) {
  const headers = { 'content-type': 'application/json', apikey: SUPABASE_KEY };
  if (!SUPABASE_KEY.startsWith('sb_')) headers.authorization = `Bearer ${SUPABASE_KEY}`; // older JWT-style keys
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, { method: 'POST', headers, body: JSON.stringify(args) });
  if (!res.ok) throw new Error(`waitlist ${res.status}`);
  return res.json();
}
const api = {
  ready: hosted || local,
  stats: () => (hosted ? rpc('waitlist_stats') : fetch('api/waitlist/stats').then((r) => (r.ok ? r.json() : null))),
  async join({ email, zip, website }) {
    if (hosted) return rpc('waitlist_join', { p_email: email, p_zip: zip, p_website: website });
    const res = await fetch('api/waitlist', {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email, zip, website }),
    });
    return { ...(await res.json()), ok: res.ok };
  },
};

let lastStats = null;
function renderStats(stats, mine) {
  if (stats) lastStats = stats;
  renderMap(lastStats);
  for (const li of $$('#boroughs li')) {
    const n = stats?.boroughs?.[li.dataset.b];
    const out = $('[data-count]', li);
    li.classList.toggle('mine', li.dataset.b === mine);
    if (n === undefined) continue;
    out.textContent = n > 0 ? `${n.toLocaleString('en-US')} on the list` : 'Be the first';
    out.classList.toggle('first', n === 0);
  }
}

function showJoined(result, focusIn) {
  const { borough, position, boroughPosition, already } = result;
  mapState = { borough, zip: result.zip };
  renderMap(lastStats);
  for (const form of $$('[data-join]')) form.hidden = true;
  for (const box of $$('[data-joined]')) {
    box.hidden = false;
    box.innerHTML = `
      <h3>${already ? 'You’re already in' : 'You’re in'}, <em>${borough}.</em></h3>
      <p>We’ll email you once, when Passionfruit opens in ${borough}. Dates need people, so bring someone from your side of the city.</p>
      <div class="place">
        <div><b>${boroughPosition.toLocaleString('en-US')}</b><span>your place in ${borough}</span></div>
        <div><b>${position.toLocaleString('en-US')}</b><span>your place in New York City</span></div>
      </div>
      <button class="btn btn-line" type="button" data-share>Copy the link for a friend</button>`;
    $('[data-share]', box).addEventListener('click', async (e) => {
      const btn = e.currentTarget, url = location.origin + location.pathname;
      try {
        if (navigator.share && matchMedia('(pointer:coarse)').matches) await navigator.share({ title: document.title, url });
        else { await navigator.clipboard.writeText(url); btn.textContent = 'Link copied'; }
      } catch { btn.textContent = url; }
    });
  }
  if (focusIn) $('[data-joined]', focusIn)?.focus({ preventScroll: true });
}

function initWaitlist() {
  const saved = read();
  if (api.ready) api.stats().then((s) => renderStats(s, saved?.borough)).catch(() => {});
  if (saved) showJoined({ ...saved, already: true });

  for (const form of $$('[data-join]')) {
    const email = form.elements.email, zip = form.elements.zip;
    const hint = $('[data-hint]', form), btn = $('button[type=submit]', form);
    const idle = hint.textContent;
    const say = (text, kind = '') => { hint.textContent = text; hint.className = `hint ${kind}`; };
    const outside = 'That ZIP is outside the five boroughs. Passionfruit opens in New York City first.';

    zip.addEventListener('input', () => {
      zip.value = zip.value.replace(/\D/g, '').slice(0, 5);
      zip.removeAttribute('aria-invalid');
      if (zip.value.length < 5) return say(idle);
      const b = boroughForZip(zip.value);
      if (b) say(`${b}. You’re in range.`, 'ok');
      else { zip.setAttribute('aria-invalid', 'true'); say(outside, 'err'); }
    });
    email.addEventListener('input', () => email.removeAttribute('aria-invalid'));

    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email.value.trim())) {
        email.setAttribute('aria-invalid', 'true'); email.focus();
        return say('Enter an email address we can reach you at.', 'err');
      }
      if (!boroughForZip(zip.value)) {
        zip.setAttribute('aria-invalid', 'true'); zip.focus();
        return say(zip.value.length === 5 ? outside : 'Enter your five-digit New York City ZIP code.', 'err');
      }
      btn.disabled = true; say('Adding you to the list…');
      try {
        if (!api.ready) return say('The list is not open yet. Check back soon.', 'err');
        const data = await api.join({ email: email.value.trim(), zip: zip.value, website: form.elements.website.value });
        if (!data.ok) {
          if (data.error === 'zip') { zip.setAttribute('aria-invalid', 'true'); zip.focus(); }
          if (data.error === 'email') { email.setAttribute('aria-invalid', 'true'); email.focus(); }
          return say(data.message ?? 'That did not go through. Try again.', 'err');
        }
        const mine = { borough: data.borough, position: data.position, boroughPosition: data.boroughPosition, zip: zip.value };
        save(mine);
        showJoined({ ...data, ...mine }, form.parentElement);
        playJoin();
        renderStats(data.stats, data.borough);
        const stage = $('#meetStage').getBoundingClientRect();
        if (stage.top < 0 || stage.bottom > innerHeight) $('#meetStage').scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'center' });
      } catch {
        say('We could not reach the list. Check your connection and try again.', 'err');
      } finally {
        btn.disabled = false;
      }
    });
  }
}

/* ───────── Boot ───────── */
$$('[data-wash]').forEach((el, i) => {
  el.innerHTML = washSVG(WASH[el.dataset.wash], 33 + i * 9);
  if ('stretch' in el.dataset) $('svg', el).setAttribute('preserveAspectRatio', 'none'); // wash spread behind a line of type
});
$$('[data-buddy]').forEach((el) => { el.innerHTML = buddySVG(); });
const nav = $('#nav');
tickers.add(() => { if (scrollDirty) nav.classList.toggle('stuck', scrollY > 8); });
initSkyline();
initMeet();
initReveals();
initSay();
initDate();
initBoroughs();
initWaitlist();
requestAnimationFrame(frame);
