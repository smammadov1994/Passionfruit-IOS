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

/* ───────── Hero: two people who spring toward each other ───────── */
function initMeet() {
  const meet = $('#meet'), stage = $('#meetStage');
  const blobs = $$('.blob', stage).map((el, i) => {
    el.innerHTML = washSVG(i ? WASH.sage : WASH.blush, i ? 21 : 8);
    const base = i ? { x: 0.21, y: 0.06 } : { x: -0.21, y: -0.05 };
    return { el, base, x: new Spring(base.x, 60, 9), y: new Spring(base.y, 60, 9), s: new Spring(1, 200, 18), drag: null };
  });
  let W = stage.offsetWidth, heroH = innerHeight;
  let px = 0, py = 0, pull = 0, holdUntil = 0, mutual = false;
  const measure = () => { W = stage.offsetWidth; heroH = $('.hero').offsetHeight; };
  new ResizeObserver(measure).observe(stage);

  const draw = () => {
    for (const b of blobs) b.el.style.transform = `translate3d(${b.x.x * W}px,${b.y.x * W}px,0) scale(${b.s.x})`;
  };
  if (reduce) { draw(); return; }

  // Pigment specks: each one is on a spring to a slow orbit around its person.
  const cv = $('#motes'), ctx = cv.getContext('2d'), size = fitCanvas(cv);
  const mouse = { x: -9999, y: -9999 };
  const INKS = [['#E4532F', '#F08A6E', '#F3B3A2', '#F2D98A', '#F3B3A2'], ['#1F8A5B', '#6DB58F', '#A9D2B8', '#A9C6E8', '#C5B4E3']];
  const motes = Array.from({ length: innerWidth < 700 ? 150 : 280 }, (_, i) => {
    const owner = i % 2, far = Math.random() ** 1.7;
    return {
      owner, ang: Math.random() * Math.PI * 2, rad: 0.06 + far * 0.4, sq: 0.8 + Math.random() * 0.35,
      w: (Math.random() < 0.5 ? -1 : 1) * (0.08 + Math.random() * 0.5) * (1.2 - far),
      k: 14 + Math.random() * 50, c: 3.500 + Math.random() * 4,
      r: 0.7 + Math.random() ** 2 * 3.400, a: 0.35 + Math.random() * 0.55,
      color: INKS[owner][Math.floor(Math.random() * 5)],
      x: (Math.random() - 0.5) * W * 2, y: (Math.random() - 0.5) * W * 2, vx: 0, vy: 0,
    };
  });

  addEventListener('pointermove', (e) => {
    if (!innerWidth || !innerHeight) return;
    px = clamp((e.clientX / innerWidth) * 2 - 1, -1, 1) || 0;
    py = clamp((e.clientY / innerHeight) * 2 - 1, -1, 1) || 0;
  }, { passive: true });

  for (const b of blobs) {
    b.el.addEventListener('pointerdown', (e) => {
      const r = stage.getBoundingClientRect();
      b.drag = { ox: (e.clientX - r.left) / W - 0.5 - b.x.x, oy: (e.clientY - r.top) / W - 0.5 - b.y.x };
      b.el.setPointerCapture(e.pointerId);
      b.x.k = b.y.k = 320; b.x.c = b.y.c = 26;
      b.s.t = 1.06;
      e.preventDefault();
    });
    b.el.addEventListener('pointermove', (e) => {
      if (!b.drag) return;
      const r = stage.getBoundingClientRect();
      b.x.t = clamp((e.clientX - r.left) / W - 0.5 - b.drag.ox, -0.42, 0.42);
      b.y.t = clamp((e.clientY - r.top) / W - 0.5 - b.drag.oy, -0.42, 0.42);
    });
    const release = () => {
      if (!b.drag) return;
      b.drag = null;
      b.x.k = b.y.k = 60; b.x.c = b.y.c = 9; // loose again, so it overshoots on the way home
      b.s.t = 1;
      if (mutual) holdUntil = performance.now() + 2600;
    };
    b.el.addEventListener('pointerup', release);
    b.el.addEventListener('pointercancel', release);
  }

  tickers.add((dt, now) => {
    if (scrollDirty) pull = clamp(scrollY / ((heroH || innerHeight || 1) * 0.6)) || 0;
    const holding = now < holdUntil;
    const near = holding ? 0.4 : 1 - 0.68 * pull; // scrolling draws them together
    const breathe = Math.sin(now / 1700) * 0.012;
    blobs.forEach((b, i) => {
      const dir = i ? -1 : 1;
      if (!b.drag) {
        b.x.t = b.base.x * near + dir * px * 0.022;
        b.y.t = b.base.y * near + dir * (py * 0.022 + breathe);
      }
      b.x.step(dt); b.y.step(dt); b.s.step(dt);
    });
    const d = Math.hypot(blobs[0].x.x - blobs[1].x.x, blobs[0].y.x - blobs[1].y.x);
    const next = mutual ? d < 0.3 : d < 0.22;
    if (next !== mutual) {
      mutual = next;
      meet.classList.toggle('mutual', mutual);
      if (mutual) for (const m of motes) { // a small burst when they meet
        const a = Math.random() * Math.PI * 2, f = 120 + Math.random() * 260;
        m.vx += Math.cos(a) * f; m.vy += Math.sin(a) * f;
      }
    }
    for (const m of motes) {
      m.ang += m.w * dt;
      const b = blobs[m.owner], o = blobs[1 - m.owner];
      const mix = mutual ? 0.5 : 0; // together, both swarms orbit the midpoint
      const cx = (b.x.x + (o.x.x - b.x.x) * mix) * W, cy = (b.y.x + (o.y.x - b.y.x) * mix) * W;
      const rad = m.rad * W * (mutual ? 1.18 : 1);
      let fx = m.k * (cx + Math.cos(m.ang) * rad - m.x) - m.c * m.vx;
      let fy = m.k * (cy + Math.sin(m.ang) * rad * m.sq - m.y) - m.c * m.vy;
      const dx = m.x - mouse.x, dy = m.y - mouse.y, d2 = dx * dx + dy * dy;
      if (d2 < 8100 && d2 > 0.01) { // the pointer pushes specks aside
        const dd = Math.sqrt(d2), f = (1 - dd / 90) * 2600;
        fx += (dx / dd) * f; fy += (dy / dd) * f;
      }
      m.vx += fx * dt; m.vy += fy * dt;
      m.x += m.vx * dt; m.y += m.vy * dt;
    }
  });

  painters.add(() => {
    draw();
    const r = stage.getBoundingClientRect();
    if (r.bottom < -100 || r.top > innerHeight + 100) return;
    mouse.x = pointer.x - r.left - W / 2; mouse.y = pointer.y - r.top - W / 2;
    const { w, h, dpr } = size;
    ctx.setTransform(dpr, 0, 0, dpr, (w / 2) * dpr, (h / 2) * dpr);
    ctx.clearRect(-w / 2, -h / 2, w, h);
    for (const m of motes) {
      ctx.globalAlpha = m.a;
      ctx.fillStyle = m.color;
      ctx.beginPath();
      ctx.arc(m.x, m.y, m.r, 0, Math.PI * 2);
      ctx.fill();
    }
  });
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

/* ───────── Waitlist ───────── */
const KEY = 'tempo.waitlist';
const read = () => { try { return JSON.parse(localStorage.getItem(KEY)); } catch { return null; } };
const save = (v) => { try { localStorage.setItem(KEY, JSON.stringify(v)); } catch { /* private window */ } };

// Two back ends with one shape. With a public Supabase key (static hosting) the form calls the
// database functions directly; without one it talks to the local server in serve.mjs.
// Both resolve to { ok, error?, message?, borough, position, boroughPosition, already, stats }.
const hosted = Boolean(SUPABASE_KEY);
const local = ['localhost', '127.0.0.1', '[::1]'].includes(location.hostname);
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

function renderStats(stats, mine) {
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
        save({ borough: data.borough, position: data.position, boroughPosition: data.boroughPosition });
        renderStats(data.stats, data.borough);
        showJoined(data, form.parentElement);
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
