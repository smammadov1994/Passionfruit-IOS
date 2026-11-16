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

// Seeds on two rings around the middle, each pointing outward.
function seeds(color, { cx = 512, cy = 540, skip = [] } = {}) {
  const out = [];
  let k = 0;
  for (const [rad, count, off] of [[66, 5, 0.3], [132, 9, 0.75]]) {
    for (let i = 0; i < count; i++, k++) {
      if (skip.includes(k)) continue;
      const a = (2 * Math.PI * i) / count + off + Math.sin(k * 7.3) * 0.1;
      const x = cx + Math.cos(a) * rad, y = cy + Math.sin(a) * rad * 0.96;
      out.push(wash(ell(x.toFixed(0), y.toFixed(0), 15, 27, ((a * 180) / Math.PI + 90).toFixed(0)), color, 40 + k, { opacity: 0.85, tear: 8, fine: 3, edge: 0.3 }));
    }
  }
  return out.join('');
}

function fruit({ rind = '#B79AD6', rind2 = '#8E6BB8', pulp = '#EBCB8B', core = '#E3A77C', seed = '#5A3A63', rx = 350, pulpR = 232, inner = '', top = '' }) {
  const cx = 512, cy = 540;
  return `<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
    ${top}
    ${wash(ell(cx, cy, rx, rx - 10), rind, 17, { opacity: 0.9 })}
    ${wash(ell(cx, cy, rx, rx - 10), rind2, 19, { opacity: 0.28, edge: 0.5 })}
    <g>${wash(ell(cx, cy, pulpR + 26, pulpR + 22), '#FFFFFF', 23, { opacity: 1, edge: 0 }).replace('mix-blend-mode:multiply', 'mix-blend-mode:normal')}</g>
    ${wash(ell(cx, cy, pulpR, pulpR - 4), pulp, 29, { opacity: 0.85 })}
    ${wash(ell(cx, cy + 4, pulpR * 0.62, pulpR * 0.6), core, 31, { opacity: 0.6, edge: 0.25 })}
    ${inner || seeds(seed)}
  </svg>`;
}

const leaf = (d, color, s, o = 0.85) => wash(`<path d="${d}"/>`, color, s, { opacity: o, tear: 18, fine: 4, edge: 0.35 });
const line = (d, color, w, s) => `<g style="mix-blend-mode:multiply"><path d="${d}" fill="none" stroke="${color}" stroke-width="${w}" stroke-linecap="round" opacity=".8"/></g>`;
const SAGE = '#B8DCC6', GREEN = '#7DBE98', DEEP = '#4E9A72';

const OPTIONS = [
  { name: 'Original', note: 'One soft leaf, top left',
    svg: fruit({ top: leaf('M150 178C190 120 300 104 372 128C350 172 250 206 168 204C150 200 144 190 150 178Z', SAGE, 61) }) },
  { name: 'Stem and leaf', note: 'Short stem, veined leaf to the right',
    svg: fruit({ top: line('M512 214C514 176 520 150 532 124', DEEP, 16) + leaf('M536 150C590 78 716 66 792 104C760 176 640 212 548 190C536 180 530 164 536 150Z', GREEN, 63) + line('M556 164C630 150 700 128 768 108', DEEP, 7) }) },
  { name: 'Two leaves', note: 'A pair, like a sprout',
    svg: fruit({ top: leaf('M500 196C440 190 350 150 318 84C392 70 480 110 510 170C514 182 510 192 500 196Z', GREEN, 65) + leaf('M524 196C584 190 674 150 706 84C632 70 544 110 514 170C510 182 514 192 524 196Z', SAGE, 67) }) },
  { name: 'Vine', note: 'Leaf with a curling tendril',
    svg: fruit({ top: leaf('M470 196C420 150 330 130 252 150C290 214 390 234 462 214C472 210 474 202 470 196Z', SAGE, 69) + line('M512 214C520 150 590 110 650 128C700 146 700 206 656 212C624 214 610 186 630 168', DEEP, 13) }) },
  { name: 'Dot guy', note: 'Seeds make a face, like the app characters',
    svg: fruit({ top: leaf('M150 178C190 120 300 104 372 128C350 172 250 206 168 204C150 200 144 190 150 178Z', SAGE, 61),
      inner: wash(ell(446, 506, 26, 30), '#5A3A63', 71, { opacity: 0.9, tear: 6, fine: 2, edge: 0.3 }) + wash(ell(578, 506, 26, 30), '#5A3A63', 72, { opacity: 0.9, tear: 6, fine: 2, edge: 0.3 })
        + `<g style="mix-blend-mode:multiply"><path d="M462 592Q512 642 562 592" fill="none" stroke="#5A3A63" stroke-width="20" stroke-linecap="round" opacity=".85"/></g>`
        + wash(ell(392, 572, 30, 26), '#E4532F', 73, { opacity: 0.3, tear: 6, edge: 0 }) + wash(ell(632, 572, 30, 26), '#E4532F', 74, { opacity: 0.3, tear: 6, edge: 0 }) }) },
  { name: 'Deep plum', note: 'Richer rind, brighter pulp, darker leaf',
    svg: fruit({ rind: '#9A6FC4', rind2: '#6B3F96', pulp: '#F2C766', core: '#EE9A5C', seed: '#3F2347',
      top: line('M512 214C514 176 520 150 532 124', '#3F7F5C', 16) + leaf('M536 150C590 78 716 66 792 104C760 176 640 212 548 190C536 180 530 164 536 150Z', DEEP, 63, 0.9) }) },
];

const tiles = OPTIONS.map((o, i) => `<figure><div class="icon">${o.svg}</div><figcaption><b>${String.fromCharCode(65 + i)}. ${o.name}</b><span>${o.note}</span></figcaption>
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
</style><h1>Passionfruit logo, six takes on the first one</h1><main>${tiles}</main>`);
