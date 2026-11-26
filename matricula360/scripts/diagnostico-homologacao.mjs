// Diagnóstico somente leitura do Supabase de homologação, com as contas sintéticas.
// Reproduz os pontos levantados na homologação antes de qualquer correção.
// Uso: NODE_USE_ENV_PROXY=1 M360_SUPABASE_CHAVE_PUBLICAVEL=sb_publishable_... node scripts/diagnostico-homologacao.mjs
import { readFileSync } from 'node:fs';

const BASE = process.env.M360_SUPABASE_URL || 'https://jbimijcvvekomovodfze.supabase.co';
const K = process.env.M360_SUPABASE_CHAVE_PUBLICAVEL;
const senhas = JSON.parse(readFileSync('dados/contas-homologacao.json', 'utf8'));
async function entrar(perfil) {
  const email = `m360.${perfil}@example.com`;
  const t = await (await fetch(`${BASE}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: K, 'content-type': 'application/json' }, body: JSON.stringify({ email, password: senhas[email] }) })).json();
  return async (fn, args = {}) => {
    const r = await fetch(`${BASE}/rest/v1/rpc/${fn}`, { method: 'POST', headers: { apikey: K, authorization: `Bearer ${t.access_token}`, 'content-type': 'application/json' }, body: JSON.stringify(args) });
    const d = await r.json(); if (!r.ok) throw new Error(`${fn}: ${r.status} ${d.message}`); return d;
  };
}
const titulo = (t) => console.log(`\n=== ${t}`);

const g = await entrar('gestor.alfa');
const ops = (await g('rpc_listar_oportunidades', { p_ies: 1, p_por_pagina: 100 })).itens;

titulo('1. Oportunidades aparentemente duplicadas');
const porNome = Object.entries(ops.reduce((a, o) => ((a[o.nome] ??= []).push(o), a), {})).filter(([, v]) => v.length > 1);
for (const [nome, v] of porNome) console.log(`"${nome}": ${v.length} oportunidades — e-mails: ${v.map((o) => o.email).join(', ')} — etapas: ${v.map((o) => o.etapa).join(', ')}`);
const porEmail = Object.values(ops.reduce((a, o) => (o.email && (a[o.email] ??= []).push(o), a), {})).filter((v) => v.length > 1);
console.log(`mesmo e-mail em mais de uma oportunidade: ${porEmail.length} (${porEmail.map((v) => `${v[0].email}: cursos ${v.map((o) => o.curso).join('/')}`).join('; ') || 'nenhum'})`);

titulo('2. Propostas repetidas');
const props = (await Promise.all(['pendente_aprovacao', 'aprovada', 'aceita', 'rejeitada', 'expirada'].map((s) => g('rpc_listar_propostas', { p_ies: 1, p_status: s })))).flat();
const porOp = Object.values(props.reduce((a, p) => ((a[p.oportunidade_id] ??= []).push(p), a), {})).filter((v) => v.length > 1);
for (const v of porOp) console.log(`oportunidade ${v[0].oportunidade_id} (${v[0].nome}): ${v.length} propostas — ${v.map((p) => `#${p.id} ${p.desconto_pct}% ${p.status} por ${p.criado_por_nome}`).join(' | ')}`);
const ativasSimultaneas = porOp.filter((v) => v.filter((p) => ['pendente_aprovacao', 'aprovada'].includes(p.status)).length > 1);
console.log(`oportunidades com mais de uma proposta ATIVA (pendente/aprovada) ao mesmo tempo: ${ativasSimultaneas.length}`);

titulo('3. Projeção de oportunidades necessárias');
const bi = await g('rpc_bi', { p_ies: 1, p_coorte: '2027.1' });
const t = bi.totais;
const decididas = t.ingressantes + t.perdidos + t.cancelamentos;
console.log(`oportunidades=${t.oportunidades} ingressantes=${t.ingressantes} perdidos=${t.perdidos} cancelamentos=${t.cancelamentos} meta=${t.meta}`);
console.log(`conversão usada=${t.conversao} (ingressantes/TODAS, inclusive ${t.oportunidades - decididas} ainda em aberto)`);
console.log(`projeção exibida=${t.projecao_oportunidades_necessarias}  = ceil((meta-ingressantes)/conversão)`);
console.log(`com taxa sobre oportunidades DECIDIDAS (${t.ingressantes}/${decididas}) a projeção seria ${decididas ? Math.ceil((t.meta - t.ingressantes) / (t.ingressantes / decididas)) : 'N/D'}`);

titulo('4. Elegibilidade das tarefas de primeiro contato');
const fila = (await g('rpc_fila', { p_ies: 1 })).tarefas;
const inelegiveis = fila.filter((x) => x.tipo === 'primeiro_contato' && x.etapa !== 'novo');
console.log(`tarefas abertas: ${fila.length}; de primeiro contato: ${fila.filter((x) => x.tipo === 'primeiro_contato').length}; primeiro contato em oportunidade que JÁ saiu de "novo": ${inelegiveis.length}`);
console.log(`etapas dessas oportunidades: ${[...new Set(inelegiveis.map((x) => x.etapa))].join(', ') || '—'}`);
const terminais = fila.filter((x) => ['confirmado', 'perdido', 'cancelado', 'matricula_comercial'].includes(x.etapa) && x.tipo !== 'pendencia_validacao');
console.log(`tarefas comerciais abertas em matrícula comercial/encerradas: ${terminais.length}`);

titulo('5. Metas cadastradas');
console.log(`BI 2027.1: meta total=${t.meta}; por curso: ${bi.linhas.map((l) => `${l.chave}=${l.meta}`).join(', ')}`);
console.log('(tela Configurações: ver diagnóstico de código no relatório)');

titulo('6. Coerência dos agrupamentos do BI');
for (const ag of ['curso', 'turno', 'modalidade', 'forma_ingresso', 'atendente']) {
  const b = await g('rpc_bi', { p_ies: 1, p_coorte: '2027.1', p_agrupar: ag });
  const soma = (k) => b.linhas.reduce((a, l) => a + l[k], 0);
  console.log(`${ag.padEnd(15)} grupos=${b.linhas.length} Σoport=${soma('oportunidades')}/${b.totais.oportunidades} Σingress=${soma('ingressantes')}/${b.totais.ingressantes} Σmat.com=${soma('matriculas_comerciais')}/${b.totais.matriculas_comerciais} chaves=[${b.linhas.map((l) => l.chave).join(' | ')}]`);
}

titulo('7. Consistência dos escopos institucionais');
for (const p of ['gestor.alfa', 'reitoria.alfa', 'coord.alfa', 'comercial.alfa', 'secretaria.alfa', 'financeiro.alfa', 'gestor.beta', 'comercial.beta', 'master']) {
  const me = await (await entrar(p))('rpc_me');
  console.log(`${p.padEnd(17)} master=${me.usuario.master} escopos=${me.escopos.map((e) => `${e.ies_nome.split(' ')[0]}:${e.papel}${e.curso_nome ? '(' + e.curso_nome + ')' : ''}`).join(', ') || '—'}`);
}

titulo('8. Ações com envio externo desativado');
const alvo = fila.find((x) => x.tipo !== 'pendencia_validacao');
if (alvo) {
  const r = await g('rpc_disparar_tarefa', { p_tarefa: alvo.id });
  const depois = (await g('rpc_fila', { p_ies: 1 })).tarefas.find((x) => x.id === alvo.id);
  console.log(`disparo da tarefa ${alvo.id}: ${JSON.stringify(r)}; tarefa continua aberta: ${Boolean(depois)}`);
}
const aud = await g('rpc_auditoria', { p_ies: 1 });
console.log(`eventos "envio_externo.bloqueado" na última página de auditoria: ${aud.itens.filter((x) => x.acao === 'envio_externo.bloqueado').length}`);
