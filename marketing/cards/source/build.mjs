// Builds the Passionfruit hand-out cards as HTML pages, one per side, for headless Chrome to render.
// Card: 2 x 3.5 in portrait. With the printer's bleed the file is 2.16 x 3.66 in; its safe area is 1.84 x 3.34 in.
// Pages are laid out at 300 px per inch (648 x 1098) and rendered at 2x, so files come out at 600 dpi.
import fs from 'node:fs';
import path from 'node:path';
import QRCode from 'qrcode';

const [, , outDir, logoPath, url] = process.argv;
const W = 648, H = 1098; // the printer's bleed size: 2.16 x 3.66 in at 300 px per inch
const INK = '#33292F', PAPER = '#F6F5F3';
const logo = 'data:image/png;base64,' + fs.readFileSync(logoPath).toString('base64');

// The ten characters of the app: body colour, a paler ground for the card, and a face each.
const CAST = [
  { id: 'blush', color: '#F3B3A2', ground: '#FBE4DE', eyes: 'dots', mouth: 'smile', top: 'sprout', sx: 1, sy: 1, turn: 0, seed: 8 },
  { id: 'butter', color: '#F2D98A', ground: '#FBF0D2', eyes: 'wide', mouth: 'grin', top: 'antenna', sx: 1.08, sy: 0.9, turn: 20, seed: 33 },
  { id: 'sage', color: '#A9D2B8', ground: '#E1EFE6', eyes: 'wink', mouth: 'smile', top: 'tuft', sx: 0.88, sy: 1.06, turn: 0, seed: 21 },
  { id: 'lilac', color: '#C5B4E3', ground: '#ECE6F5', eyes: 'tall', mouth: 'little', top: 'buds', sx: 1, sy: 1, turn: 45, seed: 52 },
  { id: 'sky', color: '#A9C6E8', ground: '#E2ECF7', eyes: 'dots', mouth: 'grin', top: 'none', sx: 1.1, sy: 0.88, turn: 0, seed: 64 },
  { id: 'coral', color: '#F08F7A', ground: '#FBDDD5', eyes: 'wide', mouth: 'smile', top: 'tuft', sx: 0.94, sy: 1.02, turn: 90, seed: 77 },
  { id: 'mint', color: '#8FD6C4', ground: '#DBF1EB', eyes: 'tall', mouth: 'smirk', top: 'sprout', sx: 1.02, sy: 1.02, turn: 135, seed: 91 },
  { id: 'peach', color: '#F6C59A', ground: '#FCEBDB', eyes: 'wink', mouth: 'grin', top: 'antenna', sx: 0.86, sy: 1.06, turn: 180, seed: 12 },
  { id: 'periwinkle', color: '#9FB0EC', ground: '#DFE4F8', eyes: 'dots', mouth: 'little', top: 'buds', sx: 1.06, sy: 0.94, turn: 0, seed: 40 },
  { id: 'rose', color: '#EBA6C6', ground: '#F8E0EB', eyes: 'sleepy', mouth: 'smile', top: 'none', sx: 0.96, sy: 0.96, turn: 60, seed: 5 },
];

// A torn watercolor wash with a glassy finish, drawn in a -150..150 box. The body is about 200 across.
function body(c) {
  return `<defs>
    <radialGradient id="g" cx=".5" cy=".42" r=".55"><stop offset="0" stop-color="${c.color}" stop-opacity=".9"/><stop offset=".6" stop-color="${c.color}" stop-opacity=".96"/><stop offset=".92" stop-color="${c.color}" stop-opacity="1"/><stop offset="1" stop-color="${c.color}" stop-opacity="1"/></radialGradient>
    <linearGradient id="shade" x1="0" y1="0" x2="0" y2="1"><stop offset=".15" stop-color="#fff" stop-opacity=".3"/><stop offset=".5" stop-color="#fff" stop-opacity="0"/><stop offset=".9" stop-color="${c.color}" stop-opacity=".7"/></linearGradient>
    <filter id="torn" x="-40%" y="-40%" width="180%" height="180%" color-interpolation-filters="sRGB">
      <feTurbulence type="fractalNoise" baseFrequency=".013" numOctaves="4" seed="${c.seed}" result="big"/>
      <feDisplacementMap in="SourceGraphic" in2="big" scale="40" xChannelSelector="R" yChannelSelector="G" result="t"/>
      <feTurbulence type="fractalNoise" baseFrequency=".07" numOctaves="2" seed="${c.seed + 7}" result="fine"/>
      <feDisplacementMap in="t" in2="fine" scale="5" xChannelSelector="G" yChannelSelector="B" result="e"/>
      <feGaussianBlur in="e" stdDeviation=".5"/>
    </filter>
    <filter id="soft"><feGaussianBlur stdDeviation="5"/></filter>
  </defs>
  <ellipse cx="0" cy="112" rx="78" ry="12" fill="${c.color}" opacity=".5" filter="url(#soft)"/>
  <g transform="scale(${c.sx} ${c.sy}) rotate(${c.turn})" filter="url(#torn)">
    <circle r="100" fill="#fff"/>
    <circle r="100" fill="url(#g)"/>
  </g>
  <g transform="scale(${c.sx} ${c.sy})" filter="url(#torn)"><circle r="100" fill="url(#shade)" transform="rotate(${c.turn}) rotate(${-c.turn})"/></g>
  <rect x="-64" y="-70" width="52" height="17" rx="8.5" fill="#fff" opacity=".85" transform="rotate(-28 -38 -62)"/>
  <circle cx="-60" cy="-30" r="5" fill="#fff" opacity=".8"/>`;
}

function face(c) {
  const eye = (x, kind) => {
    if (kind === 'closed') return `<rect x="${x - 14}" y="-15" width="28" height="6" rx="3" fill="${INK}"/>`;
    if (kind === 'tall') return `<rect x="${x - 8}" y="-29" width="16" height="34" rx="8" fill="${INK}"/>`;
    if (kind === 'wide') return `<circle cx="${x}" cy="-12" r="19" fill="${PAPER}"/><circle cx="${x + 3}" cy="-12" r="10" fill="${INK}"/>`;
    return `<circle cx="${x}" cy="-12" r="10" fill="${INK}"/>`;
  };
  const kinds = c.eyes === 'wink' ? ['dots', 'closed'] : c.eyes === 'sleepy' ? ['closed', 'closed'] : [c.eyes, c.eyes];
  const gap = c.eyes === 'wide' ? 34 : 30;
  const mouth = {
    smile: `<path d="M-19 24Q0 44 19 24" fill="none" stroke="${INK}" stroke-width="7" stroke-linecap="round"/>`,
    grin: `<path d="M-22 22H22A22 22 0 0 1 -22 22Z" fill="${INK}"/>`,
    little: `<circle cx="0" cy="30" r="8" fill="none" stroke="${INK}" stroke-width="7"/>`,
    smirk: `<path d="M-8 30Q10 36 22 20" fill="none" stroke="${INK}" stroke-width="7" stroke-linecap="round"/>`,
  }[c.mouth];
  const y = -100 * c.sy; // top of the head
  const top = {
    antenna: `<rect x="-3.5" y="${y - 34}" width="7" height="40" rx="3.5" fill="${INK}"/><circle cx="0" cy="${y - 40}" r="13" fill="#E4532F"/>`,
    sprout: `<path d="M2 ${y + 4}C0 ${y - 22} 10 ${y - 44} 40 ${y - 48}C40 ${y - 22} 26 ${y - 6} 2 ${y + 4}Z" fill="#1F8A5B"/>`,
    buds: `<circle cx="-30" cy="${y + 6}" r="12" fill="${INK}"/><circle cx="30" cy="${y + 6}" r="12" fill="${INK}"/>`,
    tuft: `<g fill="${INK}"><rect x="-3.5" y="${y - 30}" width="7" height="36" rx="3.5"/><rect x="-3.5" y="${y - 24}" width="7" height="30" rx="3.5" transform="rotate(-22 0 ${y + 6})"/><rect x="-3.5" y="${y - 24}" width="7" height="30" rx="3.5" transform="rotate(22 0 ${y + 6})"/></g>`,
    none: '',
  }[c.top];
  return { top, front: `<circle cx="-52" cy="16" r="13" fill="#E4532F" opacity=".26"/><circle cx="52" cy="16" r="13" fill="#E4532F" opacity=".26"/>${eye(-gap, kinds[0])}${eye(gap, kinds[1])}${mouth}` };
}

const character = (c) => { const f = face(c); return `<svg viewBox="-150 -170 300 320" xmlns="http://www.w3.org/2000/svg">${f.top}${body(c)}${f.front}</svg>`; };

const page = (inner, bg) => `<!doctype html><meta charset="utf-8">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght,SOFT@9..144,300..500,0..100&display=block">
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:${W}px;height:${H}px;overflow:hidden;background:${bg};color:${INK};-webkit-font-smoothing:antialiased}
.serif{font-family:Fraunces,Georgia,serif;font-weight:340;letter-spacing:-.02em;font-variation-settings:"SOFT" 100;font-optical-sizing:auto}
.ui{font-family:-apple-system,"SF Pro Text","Helvetica Neue",Arial,sans-serif}
/* 24px is the bleed and the safe area starts 48px in; type and the code stay inside 68px */
.card{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;padding:98px 68px 92px;text-align:center}
.brand{display:flex;align-items:center;gap:6px;font-size:50px;line-height:1}
.brand img{width:92px;height:92px;margin:-14px -12px -8px -20px}
.guy{width:470px;margin-top:92px}
.guy svg{display:block;width:100%;overflow:visible}
.line{margin-top:auto;font-size:66px;line-height:1.04;font-weight:320}
.qr{margin-top:74px;width:396px;height:396px;padding:30px;background:#fff;border-radius:44px;box-shadow:0 14px 40px rgba(27,23,25,.08)}
.qr svg{display:block;width:100%;height:100%}
.scan{margin-top:58px;font-size:60px;line-height:1.06;font-weight:320}
.sub{margin-top:20px;font-size:27px;line-height:1.35;color:#6A5F66}
.url{margin-top:auto;font-size:28px;font-weight:600;letter-spacing:.01em}
</style>${inner}`;

fs.mkdirSync(outDir, { recursive: true });
for (const c of CAST) {
  fs.writeFileSync(path.join(outDir, `front-${c.id}.html`), page(`<div class="card">
    <div class="brand serif"><img src="${logo}" alt="">Passionfruit</div>
    <div class="guy">${character(c)}</div>
    <p class="line serif">Meet someone<br>face to face.</p></div>`, c.ground));
}
const qr = await QRCode.toString(url, { type: 'svg', errorCorrectionLevel: 'Q', margin: 0, color: { dark: INK, light: '#FFFFFF' } });
fs.writeFileSync(path.join(outDir, 'back.html'), page(`<div class="card">
  <div class="brand serif"><img src="${logo}" alt="">Passionfruit</div>
  <div class="qr">${qr}</div>
  <p class="scan serif">Scan to join<br>the list.</p>
  <p class="sub ui">Live video speed dating for iPhone.</p>
  <p class="url ui">${url.replace(/^https?:\/\//, '')}</p></div>`, PAPER));

// One sheet with everything, for looking at on screen. Not for print.
const thumbs = CAST.map((c) => `<img src="front-${c.id}.png">`).join('') + '<img src="back.png">';
fs.writeFileSync(path.join(outDir, 'sheet.html'), `<!doctype html><meta charset="utf-8"><style>
body{margin:0;padding:60px;background:#E9E6E1;display:grid;grid-template-columns:repeat(6,1fr);gap:44px;width:2400px;box-sizing:border-box}
/* crop the bleed away and round the corners a little, the way a cut card looks */
img{width:100%;aspect-ratio:2/3.5;object-fit:cover;object-position:center;border-radius:14px;box-shadow:0 12px 30px rgba(27,23,25,.16);clip-path:inset(2.19% 3.7% round 14px);transform:scale(1.08)}
</style>${thumbs}`);
console.log(CAST.map((c) => c.id).join(' '));
