// Simula a hospedagem estática do Render para web/dist (homologação local antes de publicar):
// arquivo existente => serve; demais caminhos => index.html (regra "rewrite /* -> /index.html").
// Cabeçalhos iguais aos indicados em docs/PUBLICAR-RENDER.md.
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';

const RAIZ = new URL('../web/dist/', import.meta.url).pathname;
const PORTA = Number(process.env.PORT || 4197);
const SB = process.env.M360_SUPABASE_URL || 'https://jbimijcvvekomovodfze.supabase.co';
const TIPOS = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.txt': 'text/plain; charset=utf-8', '.svg': 'image/svg+xml' };
export const CABECALHOS = {
  'Content-Security-Policy': `default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self' ${SB}; frame-ancestors 'none'; base-uri 'none'; form-action 'self'`,
  'X-Content-Type-Options': 'nosniff', 'X-Frame-Options': 'DENY', 'Referrer-Policy': 'no-referrer',
  'Permissions-Policy': 'camera=(), microphone=(), geolocation=()', 'X-Robots-Tag': 'noindex, nofollow',
};

createServer(async (req, res) => {
  for (const [k, v] of Object.entries(CABECALHOS)) res.setHeader(k, v);
  const caminho = normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname)).replace(/^\/+/, '');
  let alvo = join(RAIZ, caminho);
  if (!alvo.startsWith(RAIZ)) { res.writeHead(404); return res.end(); }
  try { if (!(await stat(alvo)).isFile()) throw new Error(); } catch { alvo = join(RAIZ, 'index.html'); }
  res.writeHead(200, { 'Content-Type': TIPOS[extname(alvo)] || 'application/octet-stream' });
  res.end(await readFile(alvo));
}).listen(PORTA, '127.0.0.1', () => console.log(`estático (simulação Render) em http://127.0.0.1:${PORTA}`));
