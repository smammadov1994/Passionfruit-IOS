// Variations on the first Passionfruit logo (the fruit cut in half), drawn as layered watercolor washes.
import fs from 'node:fs';

let uid = 0;
// One wash: a shape with a torn edge, a little darker where the paint pools at the rim.
function wash(shape, color, seed, { opacity = 0.82, tear = 26, fine = 5, edge = 0.4 } = {}) {
  const id = `w${uid++}`;
  return `<g style="mix-blend-mode:multiply"><defs><filter id="${id}" x="-20%" y="-20%" width="140%" height="140%" color-interpolation-filters="sRGB">
    <feTurbulence type="fractalNoise" baseFrequency=".006" numOctaves="4" seed="${seed}" result="a"/>
    <feDisplacementMap in="SourceGraphic" in2="a" scale="${tear}" xChannelSelector="R" yChannelSelector="G" result="b"/>
    <feTurbulence type="fractalNoise" baseFrequency=".05" numOctaves="2" seed="${seed + 9}" result="c"/>
    <feDisplacementMap in="b" in2="c" scale="${fine}" xChannelSelector="G" yChannelSelector="B" result="d"/>
    <feGaussianBlur in="d" stdDeviation="1.2"/></filter></defs>
    <g filter="url(#${id})"><g fill="${color}" opacity="${opacity}">${shape}</g>
    <g fill="none" stroke="${color}" stroke-width="14" opacity="${edge}">${shape}</g></g></g>`;
}
const ell = (cx, cy, rx, ry, rot = 0) => `<ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}"${rot ? ` transform="rotate(${rot} ${cx} ${cy})"` : ''}/>`;

// Seeds, kept tidy: one even ring pointing outward, or plain dots.
function seeds(color, kind = 'six') {
  const cx = 512, cy = 540, out = [];
  const one = (x, y, rx, ry, rot, k) => out.push(wash(ell(x.toFixed(0), y.toFixed(0), rx, ry, rot.toFixed(0)), color, 40 + k, { opacity: 0.88, tear: 3, fine: 2, edge: 0.25 }));
  const ring = (count, rad, rx, ry, off = -Math.PI / 2) => {
    for (let i = 0; i < count; i++) { const a = (2 * Math.PI * i) / count + off; one(cx + Math.cos(a) * rad, cy + Math.sin(a) * rad, rx, ry, (a * 180) / Math.PI + 90, i); }
  };
  if (kind === 'six') ring(6, 112, 15, 28);
  if (kind === 'five') ring(5, 104, 18, 32);
  if (kind === 'eight') ring(8, 122, 11, 21);
  if (kind === 'three') ring(3, 84, 20, 36);
  if (kind === 'dots') { one(cx, cy, 15, 15, 0, 9); ring(6, 108, 15, 15); }
  if (kind === 'heart') { ring(6, 122, 12, 22);
    out.push(`<g style="mix-blend-mode:multiply"><path d="M512 590C470 556 452 532 452 508C452 484 486 472 512 500C538 472 572 484 572 508C572 532 554 556 512 590Z" fill="${color}" opacity=".85"/></g>`); }
  return out.join('');
}

function fruit({ rind = '#B79AD6', rind2 = '#8E6BB8', pulp = '#EBCB8B', core = '#E3A77C', seed = '#5A3A63', kind = 'six', coreOn = true, rx = 350, pulpR = 232, top = '', leafColor = '#7DBE98', stemColor = '#4E9A72' }) {
  const cx = 512, cy = 540;
  return `<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
    ${line('M512 214C514 176 520 150 532 124', stemColor, 16) + leaf('M536 150C590 78 716 66 792 104C760 176 640 212 548 190C536 180 530 164 536 150Z', leafColor, 63) + line('M556 164C630 150 700 128 768 108', stemColor, 7)}
    ${wash(ell(cx, cy, rx, rx - 10), rind, 17, { opacity: 0.9 })}
    ${wash(ell(cx, cy, rx, rx - 10), rind2, 19, { opacity: 0.28, edge: 0.5 })}
    <g>${wash(ell(cx, cy, pulpR + 26, pulpR + 22), '#FFFFFF', 23, { opacity: 1, edge: 0 }).replace('mix-blend-mode:multiply', 'mix-blend-mode:normal')}</g>
    ${wash(ell(cx, cy, pulpR, pulpR - 4), pulp, 29, { opacity: 0.85 })}
    ${coreOn ? wash(ell(cx, cy + 4, pulpR * 0.62, pulpR * 0.6), core, 31, { opacity: 0.45, edge: 0.2 }) : ''}
    ${seeds(seed, kind)}
  </svg>`;
}

const leaf = (d, color, s, o = 0.85) => wash(`<path d="${d}"/>`, color, s, { opacity: o, tear: 18, fine: 4, edge: 0.35 });
const line = (d, color, w, s) => `<g style="mix-blend-mode:multiply"><path d="${d}" fill="none" stroke="${color}" stroke-width="${w}" stroke-linecap="round" opacity=".8"/></g>`;
const SAGE = '#B8DCC6', GREEN = '#7DBE98', DEEP = '#4E9A72';

const OPTIONS = [
  { name: 'Lilac, six seeds', note: 'First colours, one tidy ring', svg: fruit({ kind: 'six' }) },
  { name: 'Lilac, dots', note: 'Seeds as seven plain dots', svg: fruit({ kind: 'dots', coreOn: false }) },
  { name: 'Deep plum', note: 'Dark rind, bright yellow pulp, five seeds',
    svg: fruit({ rind: '#9A6FC4', rind2: '#6B3F96', pulp: '#F2C766', core: '#EE9A5C', seed: '#3F2347', kind: 'five', leafColor: '#4E9A72', stemColor: '#3F7F5C' }) },
  { name: 'Berry pink', note: 'Pink rind, butter pulp, six seeds',
    svg: fruit({ rind: '#EBA6C6', rind2: '#C8608F', pulp: '#F5DC9A', core: '#F3B988', seed: '#6A2D4C', kind: 'six' }) },
  { name: 'Wine and gold', note: 'Closest to the real fruit, eight small seeds',
    svg: fruit({ rind: '#B45C86', rind2: '#7E2F58', pulp: '#F4C45E', core: '#EE9A4E', seed: '#3A1B2C', kind: 'eight', leafColor: '#5FA57C', stemColor: '#3F7F5C' }) },
  { name: 'Periwinkle', note: 'Blue-violet rind, peach pulp, three seeds',
    svg: fruit({ rind: '#9FB0EC', rind2: '#6F82D0', pulp: '#F6C9A0', core: '#F0A988', seed: '#3B3F78', kind: 'three', coreOn: false }) },
  { name: 'Coral', note: 'Warm rind, cream pulp, dots',
    svg: fruit({ rind: '#F08F7A', rind2: '#D2614C', pulp: '#FBE9C4', core: '#F7CFA0', seed: '#7A2E24', kind: 'dots', coreOn: false, leafColor: '#8FD6C4', stemColor: '#4E9A72' }) },
  { name: 'Lilac, heart', note: 'A small heart in the middle of the seeds',
    svg: fruit({ kind: 'heart', coreOn: false }) },
  { name: 'Plum, dots', note: 'Deep colours with the calmest seeds',
    svg: fruit({ rind: '#9A6FC4', rind2: '#6B3F96', pulp: '#F2C766', core: '#EE9A5C', seed: '#3F2347', kind: 'dots', coreOn: false, leafColor: '#4E9A72', stemColor: '#3F7F5C' }) },
];

const tiles = OPTIONS.map((o, i) => `<figure><div class="icon">${o.svg}</div><figcaption><b>${(i + 1)}. ${o.name}</b><span>${o.note}</span></figcaption>
  <div class="small"><div class="icon s">${o.svg.replaceAll('id="w', `id="s${i}w`).replaceAll('url(#w', `url(#s${i}w`)}</div><em>Passionfruit</em></div></figure>`).join('');

fs.writeFileSync(process.argv[2], `<!doctype html><meta charset="utf-8">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght,SOFT@9..144,300..500,0..100&display=block">
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{width:2400px;padding:90px 90px 70px;background:#EFECE7;color:#33292F;font-family:-apple-system,"Helvetica Neue",Arial,sans-serif}
h1{font:340 64px/1 Fraunces,Georgia,serif;letter-spacing:-.02em;font-variation-settings:"SOFT" 100;margin-bottom:60px}
main{display:grid;grid-template-columns:repeat(3,1fr);gap:70px 60px}
figure{display:grid;grid-template-columns:auto 1fr;gap:26px 34px;align-items:center}
.icon{width:400px;height:400px;border-radius:92px;background:#FDFCFA;box-shadow:0 24px 60px rgba(27,23,25,.12);overflow:hidden;isolation:isolate}
.icon svg{display:block;width:100%;height:100%}
figcaption b{display:block;font-size:34px;font-weight:600;margin-bottom:8px}
figcaption span{display:block;font-size:25px;line-height:1.3;color:#6A5F66}
.small{grid-column:1/-1;display:flex;align-items:center;gap:18px}
.icon.s{width:96px;height:96px;border-radius:22px;box-shadow:0 8px 20px rgba(27,23,25,.12)}
.small em{font:340 58px/1 Fraunces,Georgia,serif;font-style:normal;letter-spacing:-.02em;font-variation-settings:"SOFT" 100}
</style><h1>Stem and leaf, in different colours and calmer seeds</h1><main>${tiles}</main>`);
