// Testes de API sobre HTTP real (servidor efêmero em porta aleatória, banco em memória).
import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFileSync, readdirSync } from 'node:fs';
import { ambiente, SENHA } from './_ambiente.mjs';
import { criarApp } from '../src/app.mjs';

let srv; let base; let amb;
before(async () => {
  amb = ambiente();
  srv = createServer(criarApp(amb.s));
  await new Promise((r) => srv.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${srv.address().port}`;
});
after(() => srv.close());

async function entrar(email) {
  const r = await fetch(`${base}/api/login`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-m360': '1' }, body: JSON.stringify({ email, senha: SENHA }) });
  assert.equal(r.status, 200, `login ${email}`);
  return r.headers.get('set-cookie').split(';')[0];
}
function cliente(cookie) {
  return async (metodo, url, corpo, extra = {}) => {
    const headers = { cookie, ...(metodo !== 'GET' ? { 'content-type': 'application/json', 'x-m360': '1' } : {}), ...extra };
    const r = await fetch(base + url, { method: metodo, headers, body: metodo !== 'GET' ? JSON.stringify(corpo ?? {}) : undefined, redirect: 'manual' });
    const txt = await r.text();
    let d; try { d = JSON.parse(txt); } catch { d = txt; }
    return { status: r.status, d, headers: r.headers };
  };
}

test('cabeçalhos de segurança e cookie HttpOnly/SameSite', async () => {
  const r = await fetch(`${base}/`);
  assert.match(r.headers.get('content-security-policy'), /default-src 'self'/);
  assert.equal(r.headers.get('x-frame-options'), 'DENY');
  assert.equal(r.headers.get('x-content-type-options'), 'nosniff');
  const l = await fetch(`${base}/api/login`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-m360': '1' }, body: JSON.stringify({ email: 'gestor.alfa@piloto.invalid', senha: SENHA }) });
  const c = l.headers.get('set-cookie');
  assert.match(c, /HttpOnly/); assert.match(c, /SameSite=Strict/);
});

test('rotas públicas preservadas e páginas da aplicação com guarda no servidor', async () => {
  for (const p of ['/', '/demo', '/login', '/style.css', '/demo.mjs', '/src/motor.mjs']) assert.equal((await fetch(base + p)).status, 200, p);
  const semSessao = await fetch(`${base}/ies/1/dashboard`, { redirect: 'manual' });
  assert.equal(semSessao.status, 302);
  assert.equal(semSessao.headers.get('location'), '/login');
  const g = cliente(await entrar('gestor.alfa@piloto.invalid'));
  assert.equal((await g('GET', `/ies/${amb.iesIds.alfa}/crm`)).status, 200);
  assert.equal((await g('GET', `/ies/${amb.iesIds.beta}/crm`)).status, 404, 'IES alheia');
  assert.equal((await g('GET', '/ies/abc/crm')).status, 404, 'ID adulterado');
  assert.equal((await g('GET', '/master')).status, 403, 'não master');
  assert.equal((await fetch(`${base}/../package.json`)).status, 404);
  assert.equal((await fetch(`${base}/src/servico.mjs`)).status, 404, 'código do servidor não é servido');
});

test('API exige sessão; CSRF exige cabeçalho próprio e JSON', async () => {
  assert.equal((await fetch(`${base}/api/me`)).status, 401);
  const cookie = await entrar('comercial1.alfa@piloto.invalid');
  const r = await fetch(`${base}/api/ies/${amb.iesIds.alfa}/maim/ciclo`, { method: 'POST', headers: { cookie, 'content-type': 'application/json' }, body: '{}' });
  assert.equal(r.status, 403);
  const r2 = await fetch(`${base}/api/logout`, { method: 'POST', headers: { cookie, 'x-m360': '1', 'content-type': 'text/plain' }, body: '{}' });
  assert.equal(r2.status, 403);
});

test('IDOR: IDs de outra IES e IDs adulterados', async () => {
  const c = cliente(await entrar('comercial1.alfa@piloto.invalid'));
  const opBeta = amb.db.prepare('SELECT id, versao FROM oportunidades WHERE ies_id = ? LIMIT 1').get(amb.iesIds.beta);
  assert.equal((await c('GET', `/api/oportunidades/${opBeta.id}`)).status, 404);
  assert.equal((await c('POST', `/api/oportunidades/${opBeta.id}/etapa`, { para: 'perdido', versao_esperada: opBeta.versao, motivo: 'idor' })).status, 404);
  assert.equal((await c('GET', `/api/ies/${amb.iesIds.beta}/bi?coorte=2027.1`)).status, 404);
  for (const id of ['-1', '0', '1.5', '1e3', 'abc', '99999999999', '1%20OR%201=1']) assert.equal((await c('GET', `/api/oportunidades/${id}`)).status, 400, id);
  assert.equal((await c('GET', '/api/oportunidades/999999')).status, 404, 'inexistente');
  const t = amb.db.prepare('SELECT id FROM tarefas WHERE ies_id = ? LIMIT 1').get(amb.iesIds.beta);
  assert.equal((await c('POST', `/api/tarefas/${t.id}/disparar`)).status, 404);
  const pr = amb.db.prepare('SELECT id FROM propostas WHERE ies_id = ? LIMIT 1').get(amb.iesIds.beta);
  if (pr) assert.equal((await c('POST', `/api/propostas/${pr.id}/aceite`)).status, 404);
});

test('elevação de privilégio: campos não permitidos e rotas de Master', async () => {
  const c = cliente(await entrar('comercial1.alfa@piloto.invalid'));
  const op = amb.db.prepare("SELECT id, versao FROM oportunidades WHERE ies_id = ? AND etapa = 'novo' LIMIT 1").get(amb.iesIds.alfa);
  const r = await c('POST', `/api/oportunidades/${op.id}/etapa`, { para: 'contato', versao_esperada: op.versao, val_documental: 1 });
  assert.equal(r.status, 400); assert.match(r.d.erro, /Campo não permitido/);
  const r2 = await c('POST', `/api/ies/${amb.iesIds.alfa}/oportunidades`, { nome: 'X Y', email: 'xy@exemplo.invalid', curso_id: amb.cursos.alfa[0], forma_ingresso: 'enem', coorte: '2027.1', base_legal: 'consentimento', origem: 'site', ies_id: amb.iesIds.beta });
  assert.equal(r2.status, 400);
  assert.equal((await c('POST', '/api/master/escopos', { email: 'eu@piloto.invalid', ies_id: amb.iesIds.alfa, papel: 'gestor' })).status, 403);
  assert.equal((await c('GET', '/api/master/ies')).status, 403);
  assert.equal((await c('POST', `/api/ies/${amb.iesIds.alfa}/metas`, { curso_id: amb.cursos.alfa[0], coorte: '2027.1', meta: 999 })).status, 403);
});

test('corrida: duas mudanças simultâneas com a mesma versão => uma vence, outra 409', async () => {
  const c = cliente(await entrar('comercial1.alfa@piloto.invalid'));
  const g = cliente(await entrar('gestor.alfa@piloto.invalid'));
  const op = amb.db.prepare("SELECT id, versao FROM oportunidades WHERE ies_id = ? AND etapa = 'novo' LIMIT 1 OFFSET 1").get(amb.iesIds.alfa);
  const [a, b] = await Promise.all([
    c('POST', `/api/oportunidades/${op.id}/etapa`, { para: 'contato', versao_esperada: op.versao }),
    g('POST', `/api/oportunidades/${op.id}/etapa`, { para: 'perdido', versao_esperada: op.versao, motivo: 'corrida' }),
  ]);
  assert.deepEqual([a.status, b.status].sort(), [200, 409]);
  const perdedor = a.status === 409 ? a : b;
  assert.equal(perdedor.d.versao_atual, op.versao + 1);
});

test('idempotência: repetir o mesmo evento não duplica', async () => {
  const c = cliente(await entrar('comercial1.alfa@piloto.invalid'));
  const corpo = { nome: 'Idem Potente', email: 'idem@exemplo.invalid', curso_id: amb.cursos.alfa[1], forma_ingresso: 'evento', coorte: '2027.2', base_legal: 'consentimento', origem: 'feira' };
  const k = { 'idempotency-key': 'chave-teste-0001' };
  const antes = amb.db.prepare('SELECT count(*) AS n FROM auditoria').get().n;
  const r1 = await c('POST', `/api/ies/${amb.iesIds.alfa}/oportunidades`, corpo, k);
  const r2 = await c('POST', `/api/ies/${amb.iesIds.alfa}/oportunidades`, corpo, k);
  assert.equal(r1.status, 200); assert.equal(r2.status, 200);
  assert.deepEqual(r1.d, r2.d);
  assert.equal(r2.headers.get('idempotent-replay'), 'true');
  assert.equal(amb.db.prepare('SELECT count(*) AS n FROM auditoria').get().n, antes + 1);
  // mesma chave, outra rota => recusa
  const op = amb.db.prepare("SELECT id, versao FROM oportunidades WHERE id = ?").get(r1.d.id);
  assert.equal((await c('POST', `/api/oportunidades/${op.id}/etapa`, { para: 'contato', versao_esperada: op.versao }, k)).status, 422);
  // sem chave, o mesmo cadastro é deduplicado pelo domínio
  const r3 = await c('POST', `/api/ies/${amb.iesIds.alfa}/oportunidades`, corpo);
  assert.equal(r3.d.duplicada, true);
});

test('revogação encerra a sessão em uso', async () => {
  const cookie = await entrar('comercial2.alfa@piloto.invalid');
  const c = cliente(cookie);
  assert.equal((await c('GET', '/api/me')).status, 200);
  const m = cliente(await entrar('master@piloto.invalid'));
  assert.equal((await m('POST', `/api/master/usuarios/${amb.ids['comercial2.alfa']}/revogar`)).status, 200);
  assert.equal((await c('GET', '/api/me')).status, 401);
  assert.equal((await c('GET', `/ies/${amb.iesIds.alfa}/dashboard`)).status, 302);
});

test('login: credenciais inválidas e limitação de tentativas', async () => {
  const tentar = () => fetch(`${base}/api/login`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-m360': '1' }, body: JSON.stringify({ email: 'financeiro.beta@piloto.invalid', senha: 'errada-errada' }) });
  const st = [];
  for (let i = 0; i < 6; i++) st.push((await tentar()).status);
  assert.deepEqual(st.slice(0, 5), [401, 401, 401, 401, 401]);
  assert.equal(st[5], 429);
});

test('BI via API devolve null (N/D) e não zero quando indisponível', async () => {
  const g = cliente(await entrar('gestor.alfa@piloto.invalid'));
  const r = await g('GET', `/api/ies/${amb.iesIds.alfa}/bi?coorte=2035.2`);
  assert.equal(r.status, 200);
  assert.equal(r.d.totais.conversao, null);
  assert.equal(r.d.totais.meta, null);
  assert.equal((await g('GET', `/api/ies/${amb.iesIds.alfa}/bi?coorte=2027`)).status, 400);
  assert.equal((await g('GET', `/api/ies/${amb.iesIds.alfa}/oportunidades?por_pagina=1000`)).status, 400, 'sem páginas gigantes');
});

test('código do servidor não contém chamadas de rede de saída nem SDK de IA', () => {
  const arquivos = readdirSync(new URL('../src/', import.meta.url)).filter((f) => f.endsWith('.mjs'));
  for (const f of arquivos) {
    const t = readFileSync(new URL(`../src/${f}`, import.meta.url), 'utf8');
    assert.ok(!/\bfetch\(|https?\.request|net\.connect|anthropic|openai|whatsapp-web|nodemailer/i.test(t), f);
  }
  const pkg = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
  assert.equal(pkg.dependencies, undefined, 'sem dependências externas');
});
