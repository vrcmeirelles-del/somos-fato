// Camada HTTP do piloto. Sem dependências externas.
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { ErroApp, inteiro } from './servico.mjs';

const PUBLICO = new URL('../public/', import.meta.url).pathname;
const MOTOR = new URL('./motor.mjs', import.meta.url).pathname;
const TIPOS = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.svg': 'image/svg+xml', '.png': 'image/png' };
const COOKIE = 'm360_sessao';
const LIMITE_CORPO = 1024 * 1024;

const CABECALHOS = {
  'Content-Security-Policy': "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'Referrer-Policy': 'no-referrer',
  'Permissions-Policy': 'camera=(), microphone=(), geolocation=()',
  'Cross-Origin-Opener-Policy': 'same-origin',
};

function lerCookie(req, nome) {
  for (const parte of (req.headers.cookie || '').split(';')) {
    const [k, ...v] = parte.trim().split('=');
    if (k === nome) return decodeURIComponent(v.join('='));
  }
  return null;
}

async function lerCorpo(req) {
  let tam = 0; const partes = [];
  for await (const c of req) {
    tam += c.length;
    if (tam > LIMITE_CORPO) throw new ErroApp(413, 'Corpo muito grande');
    partes.push(c);
  }
  if (!tam) return {};
  let d;
  try { d = JSON.parse(Buffer.concat(partes).toString('utf8')); } catch { throw new ErroApp(400, 'JSON inválido'); }
  if (typeof d !== 'object' || d === null || Array.isArray(d)) throw new ErroApp(400, 'Corpo deve ser um objeto JSON');
  return d;
}

// Lista branca de campos por rota: qualquer campo extra é recusado (bloqueia alteração direta de campos).
function somente(d, permitidos) {
  for (const k of Object.keys(d)) if (!permitidos.includes(k)) throw new ErroApp(400, `Campo não permitido: ${k}`);
  return d;
}

export function criarApp(servico, { cookieSeguro = false } = {}) {
  const rotas = [];
  const rota = (metodo, padrao, campos, fn, { publica = false } = {}) => {
    const nomes = [];
    const re = new RegExp('^' + padrao.replace(/:(\w+)/g, (_, n) => { nomes.push(n); return '([^/]+)'; }) + '$');
    rotas.push({ metodo, re, nomes, campos, fn, publica });
  };
  const S = servico;

  rota('POST', '/api/login', ['email', 'senha'], ({ d, req, res }) => {
    const { token, maxAge } = S.login(d.email, d.senha, req.socket.remoteAddress);
    res.setHeader('Set-Cookie', `${COOKIE}=${token}; HttpOnly; SameSite=Strict; Path=/; Max-Age=${maxAge}${cookieSeguro ? '; Secure' : ''}`);
    return { ok: true };
  }, { publica: true });
  rota('POST', '/api/logout', [], ({ req, res }) => {
    const t = lerCookie(req, COOKIE); if (t) S.logout(t);
    res.setHeader('Set-Cookie', `${COOKIE}=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0`);
    return { ok: true };
  });
  rota('GET', '/api/me', null, ({ u }) => S.eu(u));

  rota('GET', '/api/master/ies', null, ({ u }) => S.listarIesMaster(u));
  rota('POST', '/api/master/ies', ['nome', 'plano', 'campus'], ({ u, d }) => S.provisionarIes(u, d));
  rota('POST', '/api/master/ies/:id/status', ['status'], ({ u, p, d }) => S.alterarStatusIes(u, p.id, d));
  rota('GET', '/api/master/ies/:id/acessos', null, ({ u, p }) => S.acessosIes(u, p.id));
  rota('POST', '/api/master/escopos', ['email', 'nome', 'ies_id', 'curso_id', 'papel'], ({ u, d }) => S.concederEscopo(u, d));
  rota('POST', '/api/master/escopos/:id/revogar', [], ({ u, p }) => S.revogarEscopo(u, p.id));
  rota('POST', '/api/master/usuarios/:id/revogar', [], ({ u, p }) => S.revogarUsuario(u, p.id));

  rota('GET', '/api/ies/:id/estrutura', null, ({ u, p }) => S.estrutura(u, p.id));
  rota('POST', '/api/ies/:id/configuracoes', ['sla_horas', 'max_followups', 'dias_sem_contato', 'capacidade_atendente'], ({ u, p, d }) => S.configurar(u, p.id, d));
  rota('POST', '/api/ies/:id/metas', ['curso_id', 'coorte', 'meta'], ({ u, p, d }) => S.definirMeta(u, p.id, d));
  rota('GET', '/api/ies/:id/oportunidades', null, ({ u, p, q }) => S.listarOportunidades(u, p.id, q));
  rota('POST', '/api/ies/:id/oportunidades', ['nome', 'email', 'telefone', 'curso_id', 'forma_ingresso', 'coorte', 'base_legal', 'origem'], ({ u, p, d }) => S.criarOportunidade(u, p.id, d));
  rota('POST', '/api/ies/:id/importacoes', ['linhas'], ({ u, p, d }) => S.importar(u, p.id, d));
  rota('GET', '/api/ies/:id/propostas', null, ({ u, p, q }) => S.listarPropostas(u, p.id, q));
  rota('GET', '/api/ies/:id/fila', null, ({ u, p }) => S.fila(u, p.id));
  rota('POST', '/api/ies/:id/maim/ciclo', [], ({ u, p }) => S.cicloMaim(u, p.id));
  rota('GET', '/api/ies/:id/pendencias', null, ({ u, p }) => S.pendencias(u, p.id));
  rota('GET', '/api/ies/:id/bi', null, ({ u, p, q }) => S.bi(u, p.id, q));
  rota('GET', '/api/ies/:id/auditoria', null, ({ u, p, q }) => S.auditoria(u, p.id, q));

  rota('GET', '/api/oportunidades/:id', null, ({ u, p }) => S.detalhe(u, p.id));
  rota('POST', '/api/oportunidades/:id/etapa', ['para', 'versao_esperada', 'motivo'], ({ u, p, d }) => S.moverEtapa(u, p.id, d));
  rota('POST', '/api/oportunidades/:id/validacoes', ['dimensao', 'resultado', 'evidencia', 'versao_esperada'], ({ u, p, d }) => S.validar(u, p.id, d));
  rota('POST', '/api/oportunidades/:id/confirmar', ['versao_esperada'], ({ u, p, d }) => S.confirmar(u, p.id, d));
  rota('POST', '/api/oportunidades/:id/cancelar', ['versao_esperada', 'motivo'], ({ u, p, d }) => S.cancelar(u, p.id, d));
  rota('POST', '/api/oportunidades/:id/propostas', ['desconto_pct', 'validade_dias'], ({ u, p, d }) => S.criarProposta(u, p.id, d));
  rota('POST', '/api/oportunidades/:id/optout', ['canal'], ({ u, p, d }) => S.optOut(u, p.id, d));
  rota('POST', '/api/oportunidades/:id/anonimizar', [], ({ u, p }) => S.anonimizar(u, p.id));
  rota('POST', '/api/propostas/:id/decisao', ['decisao'], ({ u, p, d }) => S.decidirProposta(u, p.id, d));
  rota('POST', '/api/propostas/:id/aceite', [], ({ u, p }) => S.aceitarProposta(u, p.id));
  rota('POST', '/api/tarefas/:id/concluir', ['resultado'], ({ u, p, d }) => S.concluirTarefa(u, p.id, d));
  rota('POST', '/api/tarefas/:id/disparar', [], ({ u, p }) => S.dispararTarefa(u, p.id));

  // Páginas da aplicação: guarda no SERVIDOR (sem sessão => /login; sem escopo => 404).
  const PAGINAS_APP = [/^\/master$/, /^\/ies\/[^/]+\/(dashboard|crm)$/, /^\/(campanhas|matriculas|propostas|academia|configuracoes)$/];
  const ESTATICOS = { '/': 'index.html', '/demo': 'demo.html', '/login': 'login.html', '/style.css': 'style.css', '/app.css': 'app.css', '/demo.mjs': 'demo.mjs', '/app.mjs': 'app.mjs', '/login.mjs': 'login.mjs' };

  function json(res, status, corpo) {
    res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(JSON.stringify(corpo));
  }
  async function arquivo(res, caminho, status = 200) {
    const corpo = await readFile(caminho);
    res.writeHead(status, { 'Content-Type': TIPOS[extname(caminho)] || 'application/octet-stream', 'Cache-Control': 'no-cache' });
    res.end(corpo);
  }

  return async function manipular(req, res) {
    for (const [k, v] of Object.entries(CABECALHOS)) res.setHeader(k, v);
    const url = new URL(req.url, 'http://local');
    const caminho = url.pathname;
    try {
      if (caminho.startsWith('/api/')) {
        const r = rotas.find((x) => x.metodo === req.method && x.re.test(caminho));
        if (!r) {
          const existe = rotas.some((x) => x.re.test(caminho));
          throw new ErroApp(existe ? 405 : 404, existe ? 'Método não permitido' : 'Não encontrado');
        }
        const m = caminho.match(r.re);
        const p = Object.fromEntries(r.nomes.map((n, i) => [n, decodeURIComponent(m[i + 1])]));
        let u = null;
        if (!r.publica) {
          u = S.usuarioDaSessao(lerCookie(req, COOKIE));
          if (!u) throw new ErroApp(401, 'Sessão ausente ou expirada');
        }
        let d = {};
        if (req.method !== 'GET') {
          // CSRF: exige cabeçalho próprio + JSON (navegadores não enviam isso cross-site sem CORS, que não habilitamos).
          if (req.headers['x-m360'] !== '1' || !String(req.headers['content-type'] || '').startsWith('application/json')) {
            throw new ErroApp(403, 'Requisição recusada (proteção CSRF)');
          }
          d = somente(await lerCorpo(req), r.campos);
        }
        const q = Object.fromEntries(url.searchParams);
        const chave = req.headers['idempotency-key'];
        if (req.method !== 'GET' && chave && u) {
          if (typeof chave !== 'string' || chave.length < 8 || chave.length > 100) throw new ErroApp(400, 'Idempotency-Key inválida');
          const db = S._db;
          const salvo = db.prepare('SELECT rota, status, corpo FROM idempotencia WHERE usuario_id = ? AND chave = ?').get(u.id, chave);
          if (salvo) {
            if (salvo.rota !== `${req.method} ${caminho}`) throw new ErroApp(422, 'Idempotency-Key reutilizada em outra operação');
            res.setHeader('Idempotent-Replay', 'true');
            return json(res, salvo.status, JSON.parse(salvo.corpo));
          }
          // Executa e grava a chave na MESMA transação da operação.
          const resultado = S.tx(() => {
            const out = r.fn({ u, p, d, q, req, res });
            db.prepare('INSERT INTO idempotencia(usuario_id, chave, rota, status, corpo, em) VALUES (?,?,?,?,?,?)')
              .run(u.id, chave, `${req.method} ${caminho}`, 200, JSON.stringify(out), new Date().toISOString());
            return out;
          });
          return json(res, 200, resultado);
        }
        return json(res, 200, r.fn({ u, p, d, q, req, res }));
      }

      if (req.method !== 'GET' && req.method !== 'HEAD') throw new ErroApp(405, 'Método não permitido');
      if (caminho === '/src/motor.mjs') return arquivo(res, MOTOR); // usado pela demo pública (simulação, não autorização)
      if (ESTATICOS[caminho]) return arquivo(res, join(PUBLICO, ESTATICOS[caminho]));
      if (PAGINAS_APP.some((re) => re.test(caminho))) {
        const u = S.usuarioDaSessao(lerCookie(req, COOKIE));
        if (!u) { res.writeHead(302, { Location: '/login' }); return res.end(); }
        if (caminho === '/master' && !u.master) return arquivo(res, join(PUBLICO, '404.html'), 403);
        const mi = caminho.match(/^\/ies\/([^/]+)\//);
        if (mi) {
          let iesId;
          try { iesId = inteiro(mi[1], 'IES'); } catch { return arquivo(res, join(PUBLICO, '404.html'), 404); }
          if (!S.acessoOuNulo(u, iesId)) return arquivo(res, join(PUBLICO, '404.html'), 404);
        }
        return arquivo(res, join(PUBLICO, 'app.html'));
      }
      const alvo = normalize(caminho);
      if (alvo.includes('..')) throw new ErroApp(404, 'Não encontrado');
      return arquivo(res, join(PUBLICO, '404.html'), 404);
    } catch (e) {
      if (e instanceof ErroApp) {
        if (caminho.startsWith('/api/')) return json(res, e.status, { erro: e.message, ...(e.extra || {}) });
        res.writeHead(e.status, { 'Content-Type': 'text/plain; charset=utf-8' });
        return res.end(e.message);
      }
      if (/confirmacao incompleta/.test(e?.message)) return json(res, 422, { erro: 'Confirmação incompleta' });
      if (/auditoria imutavel/.test(e?.message)) return json(res, 403, { erro: 'Auditoria é imutável' });
      console.error('[erro interno]', e);
      if (!res.headersSent) json(res, 500, { erro: 'Erro interno' });
    }
  };
}
