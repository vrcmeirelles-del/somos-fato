// Testes de domínio: isolamento entre IES/cursos, papéis, versão, auditoria, LGPD, MAIM, BI.
import test from 'node:test';
import assert from 'node:assert/strict';
import { ambiente, ateMatriculaComercial } from './_ambiente.mjs';

const status = (fn) => { try { fn(); return 200; } catch (e) { return e.status ?? e.message; } };

test('isolamento: duas IES e dois cursos por IES', () => {
  const a = ambiente();
  const { s, u, iesIds, cursos } = a;
  assert.equal(cursos.alfa.length, 2); assert.equal(cursos.beta.length, 2);
  // comercial da Alfa não enxerga a Beta (404, sem revelar existência)
  assert.equal(status(() => s.listarOportunidades(u('comercial1.alfa'), iesIds.beta)), 404);
  const opBeta = s.listarOportunidades(u('gestor.beta'), iesIds.beta).itens[0];
  assert.equal(status(() => s.detalhe(u('gestor.alfa'), opBeta.id)), 404);
  assert.equal(status(() => s.moverEtapa(u('comercial1.alfa'), opBeta.id, { para: 'perdido', versao_esperada: opBeta.versao, motivo: 'x' })), 404);
  // listagem nunca mistura IES
  const lista = s.listarOportunidades(u('gestor.alfa'), iesIds.alfa, { por_pagina: 100 });
  const idsBeta = new Set(a.db.prepare('SELECT id FROM oportunidades WHERE ies_id = ?').all(iesIds.beta).map((r) => r.id));
  assert.ok(lista.itens.every((o) => !idsBeta.has(o.id)));
});

test('coordenador vê apenas cursos autorizados e com dados mascarados', () => {
  const { s, u, iesIds, cursos, db } = ambiente();
  const coord = u('coord.direito.alfa');
  const r = s.listarOportunidades(coord, iesIds.alfa, { por_pagina: 100 });
  assert.ok(r.total > 0);
  assert.ok(r.itens.every((o) => o.curso_id === cursos.alfa[0]));
  assert.ok(r.itens.every((o) => o.dados_mascarados && (!o.email || o.email.includes('***'))));
  const adm = db.prepare('SELECT id FROM oportunidades WHERE curso_id = ? LIMIT 1').get(cursos.alfa[1]);
  assert.equal(status(() => s.detalhe(coord, adm.id)), 404);
  const bi = s.bi(coord, iesIds.alfa, { coorte: '2027.1' });
  assert.equal(bi.cobertura, 'cursos_autorizados');
  assert.equal(bi.linhas.length, 1);
  // coordenador não opera funil
  const dir = db.prepare("SELECT id, versao FROM oportunidades WHERE curso_id = ? AND etapa = 'novo' LIMIT 1").get(cursos.alfa[0]);
  assert.equal(status(() => s.moverEtapa(coord, dir.id, { para: 'contato', versao_esperada: dir.versao })), 403);
});

test('atendente restrito a um curso não cria oportunidade em outro curso', () => {
  const { s, u, iesIds, cursos } = ambiente();
  const d = { nome: 'Fulano Teste', email: 'f@exemplo.invalid', forma_ingresso: 'enem', coorte: '2027.1', base_legal: 'consentimento', origem: 'site' };
  assert.equal(status(() => s.criarOportunidade(u('comercial2.alfa'), iesIds.alfa, { ...d, curso_id: cursos.alfa[1] })), 403);
  assert.equal(status(() => s.criarOportunidade(u('comercial2.alfa'), iesIds.alfa, { ...d, curso_id: cursos.beta[0] })), 404);
  assert.equal(status(() => s.criarOportunidade(u('comercial2.alfa'), iesIds.alfa, { ...d, curso_id: cursos.alfa[0] })), 200);
});

test('usuário revogado e escopo revogado perdem acesso imediatamente', () => {
  const { s, u, iesIds, ids, db } = ambiente();
  assert.equal(status(() => s.login('revogado.alfa@piloto.invalid', 'piloto-local-2026')), 401);
  const { token } = s.login('comercial1.alfa@piloto.invalid', 'piloto-local-2026');
  assert.ok(s.usuarioDaSessao(token));
  s.revogarUsuario(u('master'), ids['comercial1.alfa']);
  assert.equal(s.usuarioDaSessao(token), null);
  assert.equal(status(() => s.listarOportunidades(u('comercial1.alfa'), iesIds.alfa)), 404);
  const esc = db.prepare("SELECT id FROM escopos WHERE usuario_id = ? AND papel = 'gestor'").get(ids['gestor.beta']);
  s.revogarEscopo(u('master'), esc.id);
  assert.equal(status(() => s.bi(u('gestor.beta'), iesIds.beta, { coorte: '2027.1' })), 404);
});

test('master não acessa candidatos sem escopo explícito', () => {
  const { s, u, iesIds } = ambiente();
  assert.equal(status(() => s.listarOportunidades(u('master'), iesIds.alfa)), 404);
  assert.equal(status(() => s.bi(u('master'), iesIds.alfa, { coorte: '2027.1' })), 404);
  assert.ok(s.listarIesMaster(u('master')).length >= 2);
  assert.equal(status(() => s.listarIesMaster(u('gestor.alfa'))), 403);
});

test('conflito de versão: segunda escrita com versão antiga é recusada', () => {
  const { s, u, iesIds, db } = ambiente();
  const op = db.prepare("SELECT id, versao FROM oportunidades WHERE ies_id = ? AND etapa = 'novo' LIMIT 1").get(iesIds.alfa);
  s.moverEtapa(u('comercial1.alfa'), op.id, { para: 'contato', versao_esperada: op.versao });
  assert.equal(status(() => s.moverEtapa(u('gestor.alfa'), op.id, { para: 'perdido', versao_esperada: op.versao, motivo: 'teste' })), 409);
});

test('alteração direta de etapa para confirmado/cancelado é recusada', () => {
  const amb = ambiente();
  const { id, versao } = ateMatriculaComercial(amb);
  const { s, u } = amb;
  assert.equal(status(() => s.moverEtapa(u('gestor.alfa'), id, { para: 'confirmado', versao_esperada: versao })), 422);
  assert.equal(status(() => s.moverEtapa(u('gestor.alfa'), id, { para: 'cancelado', versao_esperada: versao })), 422);
  // O banco também recusa, mesmo contornando a aplicação.
  assert.throws(() => amb.db.prepare("UPDATE oportunidades SET etapa = 'confirmado' WHERE id = ?").run(id), /confirmacao incompleta/);
});

test('segregação: comercial não valida; secretaria não valida financeira; financeiro não valida documental', () => {
  const amb = ambiente();
  const { id, versao } = ateMatriculaComercial(amb);
  const { s, u } = amb;
  const v = (k, dimensao) => status(() => s.validar(u(k), id, { dimensao, resultado: 'valida', evidencia: 'documento conferido', versao_esperada: versao }));
  assert.equal(v('comercial1.alfa', 'documental'), 403);
  assert.equal(v('secretaria.alfa', 'financeira'), 403);
  assert.equal(v('financeiro.alfa', 'documental'), 403);
  assert.equal(v('gestor.alfa', 'documental'), 403);
  assert.equal(status(() => s.validar(u('secretaria.alfa'), id, { dimensao: 'documental', resultado: 'valida', evidencia: '', versao_esperada: versao })), 400);
  assert.equal(status(() => s.validar(u('secretaria.alfa'), id, { dimensao: 'academica', resultado: 'isencao_formal', evidencia: 'xxxxxx', versao_esperada: versao })), 422);
});

test('confirmação incompleta recusada; completa confirma; cancelamento preserva histórico', () => {
  const amb = ambiente();
  const { s, u, db } = amb;
  let { id, versao } = ateMatriculaComercial(amb);
  versao = s.validar(u('secretaria.alfa'), id, { dimensao: 'documental', resultado: 'valida', evidencia: 'RG e histórico conferidos', versao_esperada: versao }).versao;
  assert.equal(status(() => s.confirmar(u('secretaria.alfa'), id, { versao_esperada: versao })), 422);
  versao = s.validar(u('financeiro.alfa'), id, { dimensao: 'financeira', resultado: 'isencao_formal', evidencia: 'Portaria de isenção nº 1 (sintética)', versao_esperada: versao }).versao;
  versao = s.validar(u('secretaria.alfa'), id, { dimensao: 'academica', resultado: 'valida', evidencia: 'Requisitos atendidos', versao_esperada: versao }).versao;
  assert.equal(status(() => s.confirmar(u('comercial1.alfa'), id, { versao_esperada: versao })), 403);
  versao = s.confirmar(u('secretaria.alfa'), id, { versao_esperada: versao }).versao;
  assert.equal(status(() => s.cancelar(u('gestor.alfa'), id, { versao_esperada: versao, motivo: '' })), 400);
  s.cancelar(u('gestor.alfa'), id, { versao_esperada: versao, motivo: 'Desistência formal (sintética)' });
  const h = s.detalhe(u('gestor.alfa'), id);
  assert.equal(h.oportunidade.etapa, 'cancelado');
  assert.ok(h.oportunidade.confirmada_em, 'data de confirmação preservada');
  assert.equal(h.validacoes.length, 3);
  const acoes = h.historico.map((x) => x.acao);
  for (const a of ['oportunidade.criar', 'oportunidade.validar', 'oportunidade.confirmar', 'oportunidade.cancelar']) assert.ok(acoes.includes(a), a);
  assert.ok(db.prepare("SELECT count(*) AS n FROM oportunidades WHERE id = ?").get(id).n === 1, 'nada apagado');
});

test('auditoria é imutável e não contém dados pessoais', () => {
  const { db } = ambiente();
  assert.throws(() => db.prepare("UPDATE auditoria SET acao = 'x'").run(), /auditoria imutavel/);
  assert.throws(() => db.prepare('DELETE FROM auditoria').run(), /auditoria imutavel/);
  const todo = db.prepare('SELECT dados FROM auditoria').all().map((r) => r.dados).join(' ');
  assert.ok(!/@exemplo\.invalid/.test(todo), 'sem e-mails de candidatos');
  assert.ok(!/0000\d{7}/.test(todo), 'sem telefones');
});

test('escrita que falha não deixa auditoria nem dados parciais (atomicidade)', () => {
  const { s, u, iesIds, cursos, db } = ambiente();
  const antes = db.prepare('SELECT count(*) AS n FROM auditoria').get().n;
  const antesOp = db.prepare('SELECT count(*) AS n FROM oportunidades').get().n;
  assert.equal(status(() => s.importar(u('comercial1.alfa'), iesIds.alfa, { linhas: [
    { nome: 'Ok Um', email: 'ok1@exemplo.invalid', curso_id: cursos.alfa[0], forma_ingresso: 'enem', coorte: '2027.1', base_legal: 'consentimento', origem: 'feira' },
  ] })), 200);
  assert.equal(db.prepare('SELECT count(*) AS n FROM oportunidades').get().n, antesOp + 1);
  assert.equal(db.prepare('SELECT count(*) AS n FROM auditoria').get().n, antes + 2); // criar + importar
});

test('LGPD: sem base legal ou origem não entra; importação reporta rejeições e deduplica', () => {
  const { s, u, iesIds, cursos } = ambiente();
  const base = { nome: 'Sem Base', email: 'sb@exemplo.invalid', curso_id: cursos.alfa[0], forma_ingresso: 'enem', coorte: '2027.1', origem: 'site' };
  assert.equal(status(() => s.criarOportunidade(u('comercial1.alfa'), iesIds.alfa, base)), 422);
  assert.equal(status(() => s.criarOportunidade(u('comercial1.alfa'), iesIds.alfa, { ...base, base_legal: 'consentimento', origem: '' })), 400);
  const r = s.importar(u('comercial1.alfa'), iesIds.alfa, { linhas: [
    { ...base, base_legal: 'consentimento', email: 'dup@exemplo.invalid' },
    { ...base, base_legal: 'consentimento', email: 'DUP@exemplo.invalid', nome: 'Mesma Pessoa' },
    { ...base, email: 'semlegal@exemplo.invalid' },
    { ...base, base_legal: 'consentimento', email: 'x@exemplo.invalid', curso_id: cursos.beta[0] },
  ] });
  assert.equal(r.criadas, 1);
  assert.equal(r.duplicadas, 1);
  assert.equal(r.rejeitadas.length, 2);
});

test('opt-out suprime tarefas do canal e revalida na execução', () => {
  const { s, u, iesIds, db } = ambiente();
  const t = db.prepare("SELECT t.id, t.canal, t.oportunidade_id, t.responsavel_id FROM tarefas t WHERE t.ies_id = ? AND t.status = 'aberta' AND t.tipo = 'primeiro_contato' LIMIT 1").get(iesIds.alfa);
  const dono = { id: t.responsavel_id, master: 0 };
  const r = s.optOut(u('comercial1.alfa'), t.oportunidade_id, { canal: t.canal });
  assert.ok(r.tarefas_suprimidas >= 1);
  assert.equal(db.prepare('SELECT status FROM tarefas WHERE id = ?').get(t.id).status, 'suprimida');
  assert.equal(status(() => s.concluirTarefa(dono, t.id, { resultado: 'liguei' })), 422);
});

test('ausência de envio externo: disparo sempre bloqueado e auditado', () => {
  const { s, db, iesIds } = ambiente();
  const t = db.prepare("SELECT id, responsavel_id FROM tarefas WHERE ies_id = ? AND status = 'aberta' AND responsavel_id IS NOT NULL LIMIT 1").get(iesIds.alfa);
  const r = s.dispararTarefa({ id: t.responsavel_id, master: 0 }, t.id);
  assert.equal(r.enviado, false);
  assert.ok(db.prepare("SELECT count(*) AS n FROM auditoria WHERE acao = 'envio_externo.bloqueado'").get().n >= 1);
});

test('desconto excessivo exige aprovação; criador não aprova; desconto > 100 é recusado', () => {
  const { s, u, db, iesIds } = ambiente();
  const op = db.prepare("SELECT id FROM oportunidades WHERE ies_id = ? AND etapa = 'inscrito' LIMIT 1").get(iesIds.alfa);
  assert.equal(status(() => s.criarProposta(u('comercial1.alfa'), op.id, { desconto_pct: 150 })), 422);
  const ok = s.criarProposta(u('comercial1.alfa'), op.id, { desconto_pct: 10 });
  assert.equal(ok.status, 'aprovada');
  const alto = s.criarProposta(u('comercial1.alfa'), op.id, { desconto_pct: 60 });
  assert.equal(alto.status, 'pendente_aprovacao');
  assert.equal(status(() => s.aceitarProposta(u('comercial1.alfa'), alto.id)), 422);
  assert.equal(status(() => s.decidirProposta(u('comercial1.alfa'), alto.id, { decisao: 'aprovar' })), 403);
  const propriaGestor = s.criarProposta(u('gestor.alfa'), op.id, { desconto_pct: 70 });
  assert.equal(status(() => s.decidirProposta(u('gestor.alfa'), propriaGestor.id, { decisao: 'aprovar' })), 403);
  assert.equal(s.decidirProposta(u('gestor.alfa'), alto.id, { decisao: 'aprovar' }).status, 'aprovada');
  assert.equal(status(() => s.decidirProposta(u('gestor.alfa'), alto.id, { decisao: 'rejeitar' })), 422);
});

test('proposta expira após a validade', () => {
  const { s, u, db, iesIds, relogio } = ambiente();
  const op = db.prepare("SELECT id FROM oportunidades WHERE ies_id = ? AND etapa = 'inscrito' LIMIT 1").get(iesIds.alfa);
  const p = s.criarProposta(u('comercial1.alfa'), op.id, { desconto_pct: 5, validade_dias: 1 });
  relogio.agora = new Date(relogio.agora.getTime() + 2 * 86400e3);
  assert.equal(s.aceitarProposta(u('comercial1.alfa'), p.id).status, 'expirada');
});

test('BI: zero vs indisponível, denominador por coorte e pessoas distintas', () => {
  const { s, u, iesIds, db } = ambiente();
  const vazio = s.bi(u('gestor.alfa'), iesIds.alfa, { coorte: '2031.1' });
  assert.equal(vazio.totais.oportunidades, 0);
  assert.equal(vazio.totais.conversao, null);
  assert.equal(vazio.totais.meta, null);
  const b = s.bi(u('gestor.alfa'), iesIds.alfa, { coorte: '2027.1' });
  const den = db.prepare("SELECT count(*) AS n FROM oportunidades WHERE ies_id = ? AND coorte = '2027.1'").get(iesIds.alfa).n;
  assert.equal(b.totais.oportunidades, den);
  assert.equal(b.totais.conversao, b.totais.ingressantes / den);
  const b2 = s.bi(u('gestor.alfa'), iesIds.alfa, { coorte: '2026.2' });
  assert.equal(b2.totais.meta, null, 'coorte sem meta => N/D');
  // meta zero => atingimento indisponível, não infinito/zero
  s.definirMeta(u('gestor.alfa'), iesIds.alfa, { curso_id: b.linhas[0].curso_id, coorte: '2031.1', meta: 0 });
  assert.equal(s.bi(u('gestor.alfa'), iesIds.alfa, { coorte: '2031.1' }).totais.atingimento, null);
});

test('BI consolidado não conta a mesma pessoa duas vezes', () => {
  const amb = ambiente();
  const { s, u, iesIds, cursos } = amb;
  const conf = (cursoIdx) => {
    const c = s.criarOportunidade(u('comercial1.alfa'), iesIds.alfa, { nome: 'Dupla Matrícula', email: 'dupla@exemplo.invalid', curso_id: cursos.alfa[cursoIdx], forma_ingresso: 'enem', coorte: '2029.1', base_legal: 'consentimento', origem: 'site' });
    let v = c.versao;
    for (const para of ['contato', 'inscrito', 'pre_matricula', 'matricula_comercial']) v = s.moverEtapa(u('gestor.alfa'), c.id, { para, versao_esperada: v }).versao;
    v = s.validar(u('secretaria.alfa'), c.id, { dimensao: 'documental', resultado: 'valida', evidencia: 'ok ok ok', versao_esperada: v }).versao;
    v = s.validar(u('secretaria.alfa'), c.id, { dimensao: 'academica', resultado: 'valida', evidencia: 'ok ok ok', versao_esperada: v }).versao;
    v = s.validar(u('financeiro.alfa'), c.id, { dimensao: 'financeira', resultado: 'valida', evidencia: 'ok ok ok', versao_esperada: v }).versao;
    s.confirmar(u('secretaria.alfa'), c.id, { versao_esperada: v });
  };
  conf(0); conf(1);
  const b = s.bi(u('gestor.alfa'), iesIds.alfa, { coorte: '2029.1' });
  assert.equal(b.totais.oportunidades, 2);
  assert.equal(b.totais.ingressantes, 1, 'uma pessoa = um ingressante no consolidado');
  assert.equal(b.linhas.reduce((a, l) => a + l.ingressantes, 0), 2, 'por curso cada curso conta seu ingresso');
});

test('MAIM: follow-up respeita limite, supressão e distribuição por capacidade', () => {
  const { s, u, iesIds, db, relogio } = ambiente();
  // fecha todas as tarefas abertas para isolar o ciclo
  db.prepare("UPDATE tarefas SET status = 'concluida' WHERE status = 'aberta'").run();
  relogio.agora = new Date(relogio.agora.getTime() + 5 * 86400e3);
  const r1 = s.cicloMaim(u('gestor.alfa'), iesIds.alfa);
  assert.ok(r1.follow_ups > 0);
  assert.ok(r1.pendencias_validacao > 0);
  // segundo ciclo imediato não duplica (já existe tarefa aberta)
  const r2 = s.cicloMaim(u('gestor.alfa'), iesIds.alfa);
  assert.equal(r2.follow_ups, 0);
  assert.equal(r2.pendencias_validacao, 0);
  // limite de follow-ups
  s.configurar(u('gestor.alfa'), iesIds.alfa, { max_followups: 1 });
  db.prepare("UPDATE tarefas SET status = 'concluida' WHERE status = 'aberta'").run();
  const r3 = s.cicloMaim(u('gestor.alfa'), iesIds.alfa);
  assert.equal(r3.follow_ups, 0);
  assert.ok(r3.limite_atingido > 0);
  assert.equal(status(() => s.cicloMaim(u('comercial1.alfa'), iesIds.alfa)), 403);
});

test('recuperação: perdido -> contato gera tarefa de recuperação', () => {
  const { s, u, db, iesIds } = ambiente();
  const op = db.prepare("SELECT id, versao FROM oportunidades WHERE ies_id = ? AND etapa = 'perdido' LIMIT 1").get(iesIds.alfa);
  s.moverEtapa(u('comercial1.alfa'), op.id, { para: 'contato', versao_esperada: op.versao });
  assert.equal(db.prepare("SELECT count(*) AS n FROM tarefas WHERE oportunidade_id = ? AND tipo = 'recuperacao' AND status = 'aberta'").get(op.id).n, 1);
});

test('anonimização remove dados pessoais e mantém estatística', () => {
  const { s, u, db, iesIds } = ambiente();
  const op = db.prepare("SELECT id, pessoa_id FROM oportunidades WHERE ies_id = ? LIMIT 1").get(iesIds.alfa);
  const antes = s.bi(u('gestor.alfa'), iesIds.alfa, { coorte: '2027.1' }).totais.oportunidades;
  assert.equal(status(() => s.anonimizar(u('comercial1.alfa'), op.id)), 403);
  s.anonimizar(u('gestor.alfa'), op.id);
  const p = db.prepare('SELECT * FROM pessoas WHERE id = ?').get(op.pessoa_id);
  assert.equal(p.email, null); assert.equal(p.telefone, null); assert.equal(p.nome, 'Titular anonimizado');
  assert.equal(s.bi(u('gestor.alfa'), iesIds.alfa, { coorte: '2027.1' }).totais.oportunidades, antes);
});

test('IES suspensa bloqueia acesso operacional', () => {
  const { s, u, iesIds } = ambiente();
  s.alterarStatusIes(u('master'), iesIds.beta, { status: 'suspensa' });
  assert.equal(status(() => s.listarOportunidades(u('gestor.beta'), iesIds.beta)), 404);
});
