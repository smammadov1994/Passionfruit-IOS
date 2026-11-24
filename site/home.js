// Passionfruit landing page: the New York City waitlist form, and the button that keeps it in reach.
import { boroughForZip } from './nyc.mjs';
import { SUPABASE_URL, SUPABASE_KEY } from './config.js';

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;

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
// Where this visitor came from, kept with the sign-up so an ad's clicks can be told apart from
// word of mouth. A `from` or `utm_source` in the link wins; Facebook and Instagram add `fbclid`
// to every link they send here; otherwise the site that linked here, or "direct". Worked out
// once per visit and remembered, because the address can lose its extras while someone reads.
const SOURCE_KEY = 'tempo.source';
function visitSource() {
  try { const kept = sessionStorage.getItem(SOURCE_KEY); if (kept) return kept; } catch { /* private window */ }
  const q = new URLSearchParams(location.search);
  let from = q.get('from') || q.get('utm_source') || (q.has('fbclid') ? 'meta' : '');
  if (!from) {
    try { const host = document.referrer && new URL(document.referrer).hostname; if (host && host !== location.hostname) from = host; } catch { /* odd referrer */ }
  }
  from = (from || 'direct').toLowerCase().replace(/[^a-z0-9._-]/g, '').slice(0, 40) || 'direct';
  try { sessionStorage.setItem(SOURCE_KEY, from); } catch { /* private window */ }
  return from;
}
const source = visitSource();

const api = {
  ready: hosted || local,
  stats: () => (hosted ? rpc('waitlist_stats') : fetch('api/waitlist/stats').then((r) => (r.ok ? r.json() : null))),
  async join({ email, zip, website }) {
    if (hosted) return rpc('waitlist_join', { p_email: email, p_zip: zip, p_website: website, p_source: source });
    const res = await fetch('api/waitlist', {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email, zip, website }),
    });
    return { ...(await res.json()), ok: res.ok };
  },
};

let joined = false;

// How many are on the list already, under the form. Shown only once there is a real number
// worth showing: nothing is made up, and a short list is not an argument.
function renderCount(stats) {
  const out = $('[data-count]');
  const total = stats?.total ?? 0;
  if (!out || total < 100) return;
  out.innerHTML = `<b>${total.toLocaleString('en-US')}</b> New Yorkers are on the list.`;
  out.hidden = false;
}

function showJoined(result, focusIn) {
  const { borough, position, boroughPosition, already } = result;
  joined = true;
  for (const form of $$('[data-join]')) form.hidden = true;
  for (const link of $$('[data-to-join]')) link.hidden = true;
  $('#dock').hidden = true;
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
  for (const li of $$('[data-boro]')) li.classList.toggle('mine', li.dataset.boro === borough);
  if (focusIn) $('[data-joined]', focusIn)?.focus({ preventScroll: true });
}

function initWaitlist() {
  const saved = read();
  if (api.ready) api.stats().then(renderCount).catch(() => {});
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
        renderCount(data.stats);
      } catch {
        say('We could not reach the list. Check your connection and try again.', 'err');
      } finally {
        btn.disabled = false;
      }
    });
  }
}

/* ───────── Always in reach ───────── */
// Every "Join the waitlist" button goes to the first form and puts the cursor in the email box.
function initJoinLinks() {
  const first = $('#h-email');
  for (const link of $$('[data-to-join]')) {
    link.addEventListener('click', (e) => {
      e.preventDefault();
      $('#top').scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'start' });
      // After the scroll has started, so the keyboard does not fight it on a phone.
      setTimeout(() => first.focus({ preventScroll: true }), reduce ? 0 : 450);
    });
  }
}

// On a phone, the button docks to the bottom whenever no form is on screen.
function initDock() {
  const dock = $('#dock');
  const seen = new Set();
  // Shown and put away with a class, so it can glide up and down instead of appearing at once.
  if (!joined) dock.hidden = false;
  const update = () => { dock.classList.toggle('show', !joined && seen.size === 0); };
  const watch = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) seen.add(entry.target); else seen.delete(entry.target);
    }
    update();
  }, { threshold: 0.35 });
  for (const form of $$('[data-join]')) watch.observe(form);
}

/* ───────── Motion ───────── */
// Sections rise into place the first time they are seen, and the skyline's lights come up.
// Nothing here is tied to the scroll position except the small drift in the hero on wide screens.
function initMotion() {
  document.documentElement.classList.add('js');
  const seen = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add('in');
      seen.unobserve(entry.target);
    }
  }, { threshold: 0.18, rootMargin: '0px 0px -6% 0px' });
  for (const group of $$('.steps, .boros')) [...group.children].forEach((el, i) => el.style.setProperty('--i', i));
  for (const el of $$('.rise, [data-skyline]')) seen.observe(el);
  initClock();
}

// The date clock in step two counts a real 90 seconds while it is on screen, then starts over.
function initClock() {
  const clock = $('[data-clock]');
  if (!clock || reduce) return;
  let left = 90, timer = 0;
  const show = () => { clock.textContent = `${Math.floor(left / 60)}:${String(left % 60).padStart(2, '0')}`; };
  const tick = () => { left = left > 0 ? left - 1 : 90; show(); };
  new IntersectionObserver(([entry]) => {
    clearInterval(timer);
    if (entry.isIntersecting) timer = setInterval(tick, 1000);
  }, { threshold: 0.5 }).observe(clock);
}

const nav = $('#nav');
const art = $('.hero-art');
const wide = matchMedia('(min-width: 861px)');
let ticking = false;
const onScroll = () => {
  if (ticking) return;
  ticking = true;
  requestAnimationFrame(() => {
    ticking = false;
    const y = scrollY;
    nav.classList.toggle('stuck', y > 8);
    // The park painting and the phone drift apart a little as the hero leaves: wide screens only.
    if (!reduce && wide.matches && y < innerHeight * 1.2) art.style.setProperty('--drift', (y * 0.07).toFixed(1));
  });
};
addEventListener('scroll', onScroll, { passive: true });
onScroll();
initMotion();

initWaitlist();
initJoinLinks();
initDock();
