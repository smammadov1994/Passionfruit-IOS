// Passionfruit launch site: static files plus the New York City waitlist API. No dependencies.
//   node --env-file-if-exists=server/.env site/serve.mjs      (SITE_PORT=4174 by default)
// Sign-ups go to the Supabase `waitlist` table when DATABASE_URL is set (server/.env has it),
// otherwise to site/data/waitlist.jsonl.
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { boroughForZip } from './nyc.mjs';
import { openStore } from './store.mjs';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const DATA = path.join(ROOT, 'data');
const PORT = Number(process.env.SITE_PORT ?? 4174); // not PORT: server/.env sets that for the app API

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.mp4': 'video/mp4', '.jpg': 'image/jpeg', '.png': 'image/png', '.svg': 'image/svg+xml',
  '.woff2': 'font/woff2', '.ico': 'image/x-icon',
};

const store = await openStore();

const hits = new Map(); // ip -> timestamps, at most 8 sign-up attempts a minute
function limited(ip) {
  const now = Date.now();
  const recent = (hits.get(ip) ?? []).filter((t) => now - t < 60_000);
  recent.push(now);
  hits.set(ip, recent);
  return recent.length > 8;
}

function json(res, status, body) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
  res.end(JSON.stringify(body));
}

async function readBody(req) {
  let raw = '';
  for await (const chunk of req) {
    raw += chunk;
    if (raw.length > 2048) throw new Error('too large');
  }
  return JSON.parse(raw || '{}');
}

async function join(req, res) {
  if (limited(req.socket.remoteAddress ?? '')) return json(res, 429, { error: 'slow_down', message: 'Too many tries. Give it a minute.' });
  let body;
  try { body = await readBody(req); } catch { return json(res, 400, { error: 'bad_request', message: 'That did not go through. Try again.' }); }
  if (body.website) return json(res, 200, { ok: true, borough: 'Manhattan', position: 1, boroughPosition: 1 }); // honeypot
  const email = String(body.email ?? '').trim().toLowerCase();
  const zip = String(body.zip ?? '').trim();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email) || email.length > 254) {
    return json(res, 422, { error: 'email', message: 'Enter an email address we can reach you at.' });
  }
  const borough = boroughForZip(zip);
  if (!borough) {
    return json(res, 422, { error: 'zip', message: 'That ZIP is outside the five boroughs. Passionfruit opens in New York City first.' });
  }
  const result = await store.join(email, zip, borough);
  return json(res, result.already ? 200 : 201, { ok: true, ...result, stats: await store.stats() });
}

async function serveFile(req, res, pathname) {
  let rel = pathname === '/' ? 'index.html' : decodeURIComponent(pathname.slice(1));
  if (!path.extname(rel)) rel += '.html'; // /privacy serves privacy.html, the way GitHub Pages does
  const file = path.resolve(ROOT, rel);
  if (!file.startsWith(ROOT + path.sep) || file.startsWith(DATA) || ['serve.mjs', 'store.mjs'].includes(path.basename(file))) {
    res.writeHead(404).end('Not found');
    return;
  }
  let buf;
  try { buf = await readFile(file); } catch { res.writeHead(404).end('Not found'); return; }
  const type = TYPES[path.extname(file)] ?? 'application/octet-stream';
  const range = /^bytes=(\d*)-(\d*)$/.exec(req.headers.range ?? '');
  if (range && (range[1] || range[2])) { // Safari needs byte ranges to play video
    const start = range[1] ? Number(range[1]) : Math.max(0, buf.length - Number(range[2]));
    const end = range[1] && range[2] ? Math.min(Number(range[2]), buf.length - 1) : buf.length - 1;
    if (start > end || start >= buf.length) { res.writeHead(416, { 'content-range': `bytes */${buf.length}` }).end(); return; }
    res.writeHead(206, { 'content-type': type, 'accept-ranges': 'bytes', 'content-range': `bytes ${start}-${end}/${buf.length}`, 'content-length': end - start + 1 });
    res.end(buf.subarray(start, end + 1));
    return;
  }
  res.writeHead(200, { 'content-type': type, 'accept-ranges': 'bytes', 'content-length': buf.length, 'cache-control': 'no-cache' });
  res.end(req.method === 'HEAD' ? undefined : buf);
}

createServer(async (req, res) => {
  try {
    const { pathname } = new URL(req.url ?? '/', 'http://localhost');
    if (pathname === '/api/waitlist' && req.method === 'POST') return await join(req, res);
    if (pathname === '/api/waitlist/stats' && req.method === 'GET') return json(res, 200, await store.stats());
    if (req.method !== 'GET' && req.method !== 'HEAD') return json(res, 405, { error: 'method' });
    return await serveFile(req, res, pathname);
  } catch (err) {
    console.error(err);
    if (!res.headersSent) json(res, 500, { error: 'server', message: 'Something broke on our side. Try again.' });
  }
}).listen(PORT, () => console.log(`Passionfruit launch site: http://localhost:${PORT} (waitlist: ${store.kind})`));
