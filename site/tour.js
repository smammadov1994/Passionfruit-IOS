// The app tour: a phone that follows the scroll, the daily pack, and a set of cards being traded in.
// The screens are rebuilt from the app's own design system; the art is the app's art.
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const clamp = (v, lo = 0, hi = 1) => Math.min(hi, Math.max(lo, v));
const lerp = (a, b, t) => a + (b - a) * t;
const smooth = (t) => t * t * (3 - 2 * t);
const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;

/* ───────── the little characters ───────── */
for (const el of $$('.bud')) {
  const grin = el.dataset.face === 'grin';
  el.innerHTML = `<img decoding="async" src="assets/app/Buddy${el.dataset.bud}.webp" alt=""><svg viewBox="0 0 100 100" aria-hidden="true">
    ${el.dataset.top === 'antenna' ? '<path d="M50 15V4" stroke="#1B1719" stroke-width="2.4" stroke-linecap="round" fill="none"/><circle cx="50" cy="2" r="4" fill="#E4532F"/>' : ''}
    <circle cx="27" cy="58" r="6.500" fill="#E4532F" opacity=".22"/><circle cx="73" cy="58" r="6.500" fill="#E4532F" opacity=".22"/>
    <g class="blink"><circle cx="37" cy="46" r="4.400" fill="#1B1719"/><circle cx="63" cy="46" r="4.400" fill="#1B1719"/></g>
    ${grin ? '<path d="M39 57Q50 71 61 57Z" fill="#1B1719"/>' : '<path d="M41 59Q50 67 59 59" fill="none" stroke="#1B1719" stroke-width="3.200" stroke-linecap="round"/>'}</svg>`;
}

/* ───────── scroll bookkeeping (the same rules as the rest of the page) ───────── */
const probe = document.createElement('div');
probe.style.cssText = 'position:fixed;left:0;top:0;width:0;height:100svh;visibility:hidden;pointer-events:none';
document.body.appendChild(probe);
let viewH = innerHeight, dirty = true;
const readViewH = () => { viewH = probe.offsetHeight || innerHeight; };
readViewH();
let scrollRest = 0;
addEventListener('scroll', () => {
  dirty = true;
  const stage = $('#tourStage');
  if (!scrollRest) stage.classList.add('scrolling');
  clearTimeout(scrollRest);
  scrollRest = setTimeout(() => { scrollRest = 0; stage.classList.remove('scrolling'); }, 160);
}, { passive: true });
const tasks = []; // called every frame with (dt, now, dirty)

/* ───────── the phone ───────── */
const DATE_SECONDS = 90, TURN_SECONDS = 30; // DATE_DURATION_SEC and the turn length on the server
const TRAVEL = 345 - 64; // how far the knob runs, in the slider's own points
const COMPLETE_AT = 0.82; // SlideToStart.completeAt in the app

function initPhone() {
  const stage = $('#tourStage'), phone = $('#phone'), screen = $('#screen'), canvas = $('#canvas');
  const steps = $$('#steps .step'), scrs = $$('.scr', canvas);
  const big = $('#slideBig'), tnBody = $('#tnBody');
  const num = $('#lvNum'), arc = $('#lvArc'), clk = $('#lvClk');
  const who = $('#lvWho'), bars = [$('#lvYou'), $('#lvThem')], secs = [$('#lvYouS'), $('#lvThemS')];
  const video = $('#dateVideo'), chat = $('#chat');
  // Stills from the date, one for each thirty-second turn. A scene changes only after the scroll has rested on it
  // for a moment, so a fast scroll goes from the first picture to the last without flashing through the middle.
  const reel = (el) => {
    const frames = $$('.fr', el);
    let cur = 0, want = 0, since = 0;
    return (gone, now) => {
      const next = Math.min(frames.length - 1, Math.floor(gone / TURN_SECONDS));
      if (next !== want) { want = next; since = now; }
      if (want === cur || now - since < 220) return;
      frames.forEach((f, i) => { f.classList.toggle('was', i === cur); f.classList.toggle('on', i === want); });
      cur = want;
    };
  };
  const herReel = reel($('#lvVid'));
  const himReel = reel($('#lvSelf'));
  const toggle = $('#motionToggle'), closeBg = $('#closeBg');
  const grid = stage.parentElement, spacer = $('#tourSpacer');
  let pinned = false, stageH = 0, navH = 64;

  let s0 = 0.8, s1 = 1.2, y0 = 0, y1 = 0; // the big slider: scale and centre line, at rest in the phone and lifted out of it
  const sizer = document.createElement('div'); // reads the width the stylesheet asks for, which is rarely a whole number
  sizer.style.cssText = 'position:absolute;visibility:hidden;pointer-events:none;height:0;width:var(--pw)';
  stage.appendChild(sizer);
  const measure = () => {
    readViewH();
    navH = $('#nav').offsetHeight || 64;
    // A phone an even number of pixels wide sits on whole pixels when centred; on a fraction of one, its edges
    // and everything inside it are redrawn slightly differently on every scroll frame.
    stage.style.setProperty('--pw-px', `${Math.max(120, Math.round(sizer.offsetWidth / 2) * 2)}px`);
    s0 = screen.clientWidth / 393;
    canvas.style.setProperty('--s', s0.toFixed(4));
    canvas.style.height = `${(screen.clientHeight / s0).toFixed(2)}px`; // the frame is a little taller than the app's 852 points
    const st = stage.getBoundingClientRect(), ph = phone.getBoundingClientRect(), sc = screen.getBoundingClientRect();
    y0 = sc.bottom - 66 * s0 - st.top; // the slider's own place: 34 points up from the bottom, 64 tall
    stageH = stage.offsetHeight;
    spacer.style.height = `${stageH}px`;
    y1 = ph.top - st.top + ph.height * 0.6;
    s1 = Math.max(s0, Math.min((st.width - 28) / 345, s0 * 1.85, 1.5));
    dirty = true;
  };
  new ResizeObserver(measure).observe(stage);
  addEventListener('resize', measure);
  measure();

  let active = 0, want = 0, wantAt = 0, visible = false, paused = reduce;
  let p0 = 0, p1 = 0, p2 = 0; // how far through the first three chapters
  const vdSlide = $('#vdSlide'), vdKnob = $('.slide-knob', vdSlide), vdYou = $('#vdYou');
  let lastV = -1;
  let k = 0, drag = null, done = false; // the knob: 0 to 1
  let shownLeft = -1, lastTx = -1, lastG = -1;

  // The date clip is optional: until assets/app/date.mp4 exists, a painted stand-in fills the call.
  let videoAsked = false;
  const askVideo = () => {
    if (videoAsked) return;
    videoAsked = true;
    fetch('assets/app/date.mp4', { method: 'HEAD' }).then((r) => {
      if (!r.ok || !(r.headers.get('content-type') || '').startsWith('video')) return;
      video.src = 'assets/app/date.mp4';
      video.addEventListener('loadeddata', () => video.classList.add('ready'), { once: true });
      sync();
    }).catch(() => {});
  };

  /* chat: a short scripted exchange, on a loop */
  const timed = $$('[data-at]', chat).map((el) => ({ el, at: +el.dataset.at, until: +(el.dataset.until || Infinity), on: null }));
  const picks = $$('[data-pick]', chat).map((el) => ({ el, at: +el.dataset.pick, on: null }));
  const LOOP = 16500;
  let chatT0 = 0;
  const chatAt = (t) => {
    for (const it of timed) { const on = t >= it.at && t < it.until; if (on !== it.on) { it.on = on; it.el.classList.toggle('in', on); } }
    for (const it of picks) { const on = t >= it.at; if (on !== it.on) { it.on = on; it.el.classList.toggle('picked', on); } }
  };
  if (reduce) chatAt(14000);

  const sync = () => {
    const play = visible && !paused;
    if (video.src) { if (play && active === 1) video.play().catch(() => {}); else video.pause(); }
  };
  const setActive = (i) => {
    active = i;
    steps.forEach((s, n) => s.classList.toggle('on', n === i));
    scrs.forEach((s, n) => s.classList.toggle('on', n === i));
    canvas.classList.toggle('dark', i === 1);
    big.classList.toggle('off', i !== 0);
    if (i === 1) askVideo();
    if (i === 4 && !reduce) { chatT0 = performance.now(); chatAt(0); }
    sync();
  };
  const setPaused = (p) => {
    paused = p;
    toggle.textContent = p ? 'Play motion' : 'Pause motion';
    toggle.setAttribute('aria-pressed', String(p));
    document.body.classList.toggle('paused', p);
    if (closeBg) { if (p) closeBg.pause(); else if (closeBg.dataset.visible) closeBg.play().catch(() => {}); }
    sync();
  };
  toggle.addEventListener('click', () => setPaused(!paused));
  setPaused(paused);
  new IntersectionObserver(([e]) => { visible = e.isIntersecting; sync(); }, { threshold: 0.1 }).observe(stage);
  if (closeBg) new IntersectionObserver(([e]) => {
    if (e.isIntersecting) { closeBg.dataset.visible = '1'; if (!paused) closeBg.play().catch(() => {}); }
    else { delete closeBg.dataset.visible; closeBg.pause(); }
  }, { threshold: 0.05 }).observe(closeBg);

  /* the slider can be dragged, as in the app; past 82% it goes by itself and the date begins */
  const finish = () => {
    if (done) return;
    done = true; k = 1;
    setTimeout(() => steps[1].scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'center' }), 450);
  };
  big.addEventListener('pointerdown', (e) => {
    drag = { x: e.clientX, k, scale: big.getBoundingClientRect().width / 345 };
    big.setPointerCapture(e.pointerId);
  });
  big.addEventListener('pointermove', (e) => {
    if (!drag) return;
    k = clamp(drag.k + (e.clientX - drag.x) / (TRAVEL * drag.scale));
    if (k >= COMPLETE_AT) { drag = null; finish(); }
  });
  const drop = () => { drag = null; };
  big.addEventListener('pointerup', drop);
  big.addEventListener('pointercancel', drop);
  big.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ' || e.key === 'ArrowRight') { e.preventDefault(); finish(); } });

  tasks.push((dt, now, moved) => {
    if (moved) {
      const sr = stage.getBoundingClientRect();
      const stacked = sr.width > innerWidth * 0.8; // phone layout: the stage sits above the steps
      // Well inside the section the stage is fixed; near either end it goes back to sticking, which is what carries
      // it in and out with the page. Both put it in the same place, so the change cannot be seen.
      const gr = grid.getBoundingClientRect();
      const pin = stacked && gr.top < navH - 24 && gr.bottom > navH + stageH + 24;
      if (pin !== pinned) { pinned = pin; stage.classList.toggle('pinned', pin); }
      const mid = stacked ? (sr.bottom + viewH) / 2 : viewH / 2;
      let best = 0, bestD = Infinity;
      const rects = steps.map((s) => s.getBoundingClientRect());
      rects.forEach((r, i) => { const d = Math.abs((r.top + r.bottom) / 2 - mid); if (d < bestD) { bestD = d; best = i; } });
      if (best !== want) { want = best; wantAt = now; }
      const through = (r) => clamp((mid - r.top - r.height * 0.12) / (r.height * 0.7));
      p0 = through(rects[0]); p1 = through(rects[1]); p2 = through(rects[2]);
      if (p0 < 0.25 && done && !drag) done = false; // scrolled back up: the slider is ready again
    }
    // Flung through, the chapters in between are skipped.
    if (want !== active && now - wantAt > 120) setActive(want);

    // The slider lifts out of the phone and grows, then the knob crosses.
    const g = reduce ? 0 : smooth(clamp(p0 / 0.4));
    if (!drag && !done) {
      const target = clamp((p0 - 0.35) / 0.55);
      k += (target - k) * (1 - Math.exp(-dt * 14));
      if (target >= COMPLETE_AT && k >= COMPLETE_AT - 0.01) k = 1;
    }
    const tx = Math.round(k * TRAVEL * 10) / 10;
    if (tx !== lastTx) {
      lastTx = tx;
      big.style.setProperty('--tx', `${k >= 1 ? 400 : tx}px`); // at the end the whole track floods with paint
      big.style.setProperty('--p', k.toFixed(3));
      $('.slide-knob', big).style.transform = `translateX(${tx}px)`;
      big.setAttribute('aria-valuenow', String(Math.round(k * 100)));
    }
    const gg = Math.round(g * 500) / 500;
    if (gg !== lastG || moved) {
      lastG = gg;
      big.style.transform = `translateY(${(lerp(y0, y1, gg) - 32).toFixed(1)}px) scale(${lerp(s0, s1, gg).toFixed(4)})`;
      tnBody.style.opacity = (1 - 0.7 * gg).toFixed(3);
    }

    // The date: the clock drains with the scroll, and the question card takes turns.
    const left = Math.round(DATE_SECONDS * (1 - p1));
    if (left !== shownLeft) {
      shownLeft = left;
      num.textContent = `${Math.floor(left / 60)}:${String(left % 60).padStart(2, '0')}`;
      arc.style.strokeDashoffset = String(100 - (left / DATE_SECONDS) * 100);
      clk.classList.toggle('low', left <= 30);
      const gone = Math.min(DATE_SECONDS - 1, DATE_SECONDS - left), mine = Math.floor(gone / TURN_SECONDS) % 2 === 0;
      const turnLeft = TURN_SECONDS - (gone % TURN_SECONDS);
      who.textContent = mine ? 'Your turn' : 'Maya’s turn';
      bars[0].style.setProperty('--v', mine ? turnLeft / TURN_SECONDS : 0);
      bars[1].style.setProperty('--v', mine ? 0 : turnLeft / TURN_SECONDS);
      secs[0].textContent = mine ? `0:${String(turnLeft).padStart(2, '0')}` : '';
      secs[1].textContent = mine ? '' : `0:${String(turnLeft).padStart(2, '0')}`;
    }

    // The private answer: the scroll slides the yes across, and your wash leans toward theirs as it goes.
    const v = Math.round((reduce ? 0 : smooth(clamp((p2 - 0.15) / 0.6))) * 400) / 400;
    if (v !== lastV) {
      lastV = v;
      vdSlide.style.setProperty('--tx', `${v >= 1 ? 400 : (v * TRAVEL).toFixed(1)}px`);
      vdSlide.style.setProperty('--p', v.toFixed(3));
      vdKnob.style.transform = `translateX(${(v * TRAVEL).toFixed(1)}px)`;
      vdYou.style.transform = `translateX(${(v * 66).toFixed(1)}px)`;
    }
    if (active === 1) { herReel(DATE_SECONDS - shownLeft, now); himReel(DATE_SECONDS - shownLeft, now); }
    if (active === 4 && !reduce && !paused && visible) chatAt((now - chatT0) % LOOP);
  });
}

/* ───────── the daily pack ─────────
   One pack, one card. The page shows a single painting on purpose: the other forty-nine are for opening packs. */
function initPack() {
  const stage = $('#packStage'), pack = $('#pack3d'), drawn = $('#drawn');
  const hint = $('#packHint'), btn = $('#packBtn');
  let state = 'closed', down = null;

  const open = () => {
    if (state !== 'closed') return;
    state = 'open';
    stage.style.setProperty('--t', 1);
    stage.classList.add('open');
    hint.textContent = 'Jazz Club, a rare one. Tap it for a new pack.';
    btn.textContent = 'New pack';
  };
  const again = () => { // the card goes, a new pack drops in
    if (state !== 'open') return;
    state = 'kept';
    stage.classList.add('kept');
    setTimeout(() => {
      stage.classList.remove('open', 'kept');
      stage.style.setProperty('--t', 0);
      pack.style.animation = 'none'; void pack.offsetWidth; pack.style.animation = '';
      hint.textContent = 'Slide across the pack to tear it open.';
      btn.textContent = 'Open the pack';
      state = 'closed';
    }, 700);
  };
  btn.addEventListener('click', () => (state === 'closed' ? open() : again()));
  drawn.addEventListener('click', again);

  // The cut follows the finger from left to right; past halfway it finishes by itself.
  stage.addEventListener('pointerdown', (e) => { if (state === 'closed') down = { x: e.clientX, box: pack.getBoundingClientRect() }; });
  addEventListener('pointermove', (e) => {
    if (!down) return;
    if (Math.abs(e.clientX - down.x) < 6) return;
    const t = clamp((e.clientX - down.box.left) / down.box.width);
    stage.style.setProperty('--t', t.toFixed(3));
    if (t > 0.5 && e.clientX > down.x) { down = null; open(); }
  }, { passive: true });
  const up = () => { if (down) { down = null; if (state === 'closed') stage.style.setProperty('--t', 0); } };
  addEventListener('pointerup', up);
  addEventListener('pointercancel', up);
}

/* ───────── a set of five, traded in ───────── */
function initSets() {
  const stage = $('#setsStage'), lis = $$('.sets-row li', stage);
  if (reduce) return;
  let shown = -1, done = false;
  tasks.push((dt, now, moved) => {
    if (!moved) return;
    const r = stage.getBoundingClientRect();
    if (r.bottom < -200 || r.top > viewH + 200) return;
    const p = clamp((viewH * 0.92 - r.top) / (viewH * 0.62));
    const n = Math.min(5, Math.floor(p * 7));
    if (n !== shown) { shown = n; lis.forEach((li, i) => li.classList.toggle('in', i < n)); }
    const next = done ? p > 0.8 : p > 0.97; // a gap, so it cannot flicker on the line
    if (next !== done) { done = next; stage.classList.toggle('done', done); }
  });
}

// Get the phone's pictures decoded while the visitor is still reading the top of the page, so the first
// scroll into the tour has nothing left to unpack.
const warm = () => { for (const img of $$('#tour img')) if (img.decode) img.decode().catch(() => {}); };
if ('requestIdleCallback' in window) requestIdleCallback(warm, { timeout: 2500 }); else setTimeout(warm, 1200);

initPhone();
initPack();
initSets();
let last = performance.now();
requestAnimationFrame(function frame(now) {
  const dt = Math.min(0.1, (now - last) / 1000);
  last = now;
  const moved = dirty;
  dirty = false;
  for (const fn of tasks) fn(dt, now, moved);
  requestAnimationFrame(frame);
});
