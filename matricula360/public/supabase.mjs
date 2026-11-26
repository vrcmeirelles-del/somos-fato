// Ponte entre as telas do piloto e o Supabase (modo homologação).
// Login pelo Supabase Auth e chamadas às RPCs do banco. Toda autorização é feita no banco
// (RLS + RPCs); este arquivo só traduz os pedidos das telas. Sem dependências externas.
const CHAVE_SESSAO = 'm360_sb_sessao';

export function criarClienteSupabase({ url, chave }) {
  const lerSessao = () => { try { return JSON.parse(sessionStorage.getItem(CHAVE_SESSAO) || 'null'); } catch { return null; } };
  const gravarSessao = (s) => { try { s ? sessionStorage.setItem(CHAVE_SESSAO, JSON.stringify(s)) : sessionStorage.removeItem(CHAVE_SESSAO); } catch { /* sem storage */ } };

  async function auth(caminho, corpo, token) {
    const r = await fetch(`${url}/auth/v1/${caminho}`, {
      method: 'POST',
      headers: { apikey: chave, 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
      body: JSON.stringify(corpo ?? {}),
    });
    const d = await r.json().catch(() => ({}));
    if (!r.ok) throw Object.assign(new Error(d.error_description || d.msg || d.message || 'Falha na autenticação'), { status: r.status });
    return d;
  }
  async function entrar(email, senha) {
    const d = await auth('token?grant_type=password', { email, password: senha });
    gravarSessao({ access: d.access_token, refresh: d.refresh_token, expira: Date.now() + d.expires_in * 1000, email: d.user?.email });
  }
  async function renovar() {
    const s = lerSessao();
    if (!s?.refresh) throw Object.assign(new Error('Sessão expirada'), { status: 401 });
    const d = await auth('token?grant_type=refresh_token', { refresh_token: s.refresh });
    gravarSessao({ ...s, access: d.access_token, refresh: d.refresh_token, expira: Date.now() + d.expires_in * 1000 });
  }
  async function sair() {
    const s = lerSessao();
    gravarSessao(null);
    if (s?.access) await auth('logout', {}, s.access).catch(() => {});
  }
  async function rpc(nome, args = {}, tentativa = 0) {
    let s = lerSessao();
    if (!s) throw Object.assign(new Error('Sessão ausente'), { status: 401 });
    if (s.expira - Date.now() < 60e3) { await renovar(); s = lerSessao(); }
    const r = await fetch(`${url}/rest/v1/rpc/${nome}`, {
      method: 'POST',
      headers: { apikey: chave, authorization: `Bearer ${s.access}`, 'content-type': 'application/json' },
      body: JSON.stringify(args),
    });
    const d = await r.json().catch(() => null);
    if (r.status === 401 && /JWT/i.test(d?.message || '') && tentativa === 0) { await renovar(); return rpc(nome, args, 1); }
    if (!r.ok) {
      // P0002 = não encontrado / fora do escopo; 42501 = sem permissão; 40001 = conflito de versão; 22023 = regra violada.
      const status = { P0002: 404, 42501: 403, 40001: 409, 22023: 422 }[d?.code] ?? r.status;
      throw Object.assign(new Error(d?.message || `Erro ${r.status}`), { status, codigo: d?.code });
    }
    return d;
  }
  return { entrar, sair, rpc, sessao: lerSessao };
}

// Traduz as rotas usadas pelas telas (contrato da API local) para RPCs do Supabase,
// devolvendo o mesmo formato que as telas já esperam.
export function criarAdaptador(sb) {
  const uuid = () => (crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`);
  const num = (v) => (v == null || v === '' ? null : Number(v));
  const rotas = [
    ['POST', /^\/api\/logout$/, async () => { await sb.sair(); return { ok: true }; }],
    ['GET', /^\/api\/me$/, async () => { const m = await sb.rpc('rpc_me'); m.usuario.email = sb.sessao()?.email; return m; }],
    ['GET', /^\/api\/ies\/(\d+)\/estrutura$/, (p) => sb.rpc('rpc_estrutura', { p_ies: p[1] })],
    ['GET', /^\/api\/ies\/(\d+)\/bi$/, (p, q) => sb.rpc('rpc_bi', { p_ies: p[1], p_coorte: q.get('coorte'), p_agrupar: q.get('agrupar') || 'curso' })],
    ['GET', /^\/api\/ies\/(\d+)\/fila$/, (p) => sb.rpc('rpc_fila', { p_ies: p[1] })],
    ['POST', /^\/api\/ies\/(\d+)\/maim\/ciclo$/, (p) => sb.rpc('rpc_ciclo_maim', { p_ies: p[1] })],
    ['GET', /^\/api\/ies\/(\d+)\/oportunidades$/, (p, q) => sb.rpc('rpc_listar_oportunidades', {
      p_ies: p[1], p_etapa: q.get('etapa') || null, p_coorte: q.get('coorte') || null,
      p_pagina: num(q.get('pagina')) ?? 1, p_por_pagina: num(q.get('por_pagina')) ?? 25, p_curso: num(q.get('curso_id')) })],
    ['POST', /^\/api\/ies\/(\d+)\/oportunidades$/, (p, q, c) => sb.rpc('rpc_criar_oportunidade', { p_ies: p[1], p_dados: c, p_chave: uuid() })],
    ['POST', /^\/api\/ies\/(\d+)\/importacoes$/, async (p, q, c) => {
      const rel = { criadas: 0, duplicadas: 0, rejeitadas: [] };
      for (const [i, linha] of (c.linhas || []).entries()) {
        try { const r = await sb.rpc('rpc_criar_oportunidade', { p_ies: p[1], p_dados: linha, p_chave: uuid() }); r.duplicada ? rel.duplicadas++ : rel.criadas++; }
        catch (e) { if (e.status === 401) throw e; rel.rejeitadas.push({ linha: i + 1, motivo: e.message }); }
      }
      return rel;
    }],
    ['GET', /^\/api\/ies\/(\d+)\/pendencias$/, (p) => sb.rpc('rpc_pendencias', { p_ies: p[1] })],
    ['GET', /^\/api\/ies\/(\d+)\/propostas$/, (p, q) => sb.rpc('rpc_listar_propostas', { p_ies: p[1], p_status: q.get('status') || 'pendente_aprovacao' })],
    ['GET', /^\/api\/ies\/(\d+)\/auditoria$/, (p, q) => sb.rpc('rpc_auditoria', { p_ies: p[1], p_pagina: num(q.get('pagina')) ?? 1 })],
    ['POST', /^\/api\/ies\/(\d+)\/configuracoes$/, (p, q, c) => sb.rpc('rpc_configurar', {
      p_ies: p[1], p_sla_horas: c.sla_horas ?? null, p_max_followups: c.max_followups ?? null,
      p_dias_sem_contato: c.dias_sem_contato ?? null, p_capacidade_atendente: c.capacidade_atendente ?? null })],
    ['POST', /^\/api\/ies\/(\d+)\/metas$/, (p, q, c) => sb.rpc('rpc_definir_meta', { p_ies: p[1], p_curso: c.curso_id, p_coorte: c.coorte, p_meta: c.meta })],
    ['GET', /^\/api\/oportunidades\/(\d+)$/, (p) => sb.rpc('rpc_detalhe', { p_op: p[1] })],
    ['POST', /^\/api\/oportunidades\/(\d+)\/etapa$/, (p, q, c) => sb.rpc('rpc_mover_etapa', { p_op: p[1], p_para: c.para, p_versao: c.versao_esperada, p_motivo: c.motivo ?? null, p_chave: uuid() })],
    ['POST', /^\/api\/oportunidades\/(\d+)\/validacoes$/, (p, q, c) => sb.rpc('rpc_validar', { p_op: p[1], p_dimensao: c.dimensao, p_resultado: c.resultado, p_evidencia: c.evidencia, p_versao: c.versao_esperada })],
    ['POST', /^\/api\/oportunidades\/(\d+)\/confirmar$/, (p, q, c) => sb.rpc('rpc_confirmar', { p_op: p[1], p_versao: c.versao_esperada })],
    ['POST', /^\/api\/oportunidades\/(\d+)\/cancelar$/, (p, q, c) => sb.rpc('rpc_cancelar', { p_op: p[1], p_versao: c.versao_esperada, p_motivo: c.motivo ?? '' })],
    ['POST', /^\/api\/oportunidades\/(\d+)\/propostas$/, async (p, q, c) => {
      const r = await sb.rpc('rpc_criar_proposta', { p_op: p[1], p_desconto: c.desconto_pct, p_validade_dias: c.validade_dias ?? 7 });
      return { ...r, valorFinalCentavos: r.valor_final_centavos, exigeAprovacao: r.status === 'pendente_aprovacao' };
    }],
    ['POST', /^\/api\/oportunidades\/(\d+)\/optout$/, (p, q, c) => sb.rpc('rpc_optout', { p_op: p[1], p_canal: c.canal })],
    ['POST', /^\/api\/oportunidades\/(\d+)\/anonimizar$/, (p) => sb.rpc('rpc_anonimizar', { p_op: p[1] })],
    ['POST', /^\/api\/propostas\/(\d+)\/decisao$/, (p, q, c) => sb.rpc('rpc_decidir_proposta', { p_proposta: p[1], p_decisao: c.decisao })],
    ['POST', /^\/api\/propostas\/(\d+)\/aceite$/, (p) => sb.rpc('rpc_aceitar_proposta', { p_proposta: p[1] })],
    ['POST', /^\/api\/tarefas\/(\d+)\/concluir$/, (p, q, c) => sb.rpc('rpc_concluir_tarefa', { p_tarefa: p[1], p_resultado: c.resultado ?? '' })],
    ['POST', /^\/api\/tarefas\/(\d+)\/disparar$/, (p) => sb.rpc('rpc_disparar_tarefa', { p_tarefa: p[1] })],
    ['GET', /^\/api\/master\/ies$/, () => sb.rpc('rpc_master_listar_ies')],
    ['POST', /^\/api\/master\/ies$/, (p, q, c) => {
      const campus = (c.campus || [])[0] || {};
      return sb.rpc('rpc_provisionar_ies', { p_nome: c.nome, p_plano: c.plano ?? 'piloto', p_campus: campus.nome, p_cursos: campus.cursos || [] });
    }],
    ['POST', /^\/api\/master\/ies\/(\d+)\/status$/, (p, q, c) => sb.rpc('rpc_alterar_status_ies', { p_ies: p[1], p_status: c.status })],
    ['GET', /^\/api\/master\/ies\/(\d+)\/acessos$/, (p) => sb.rpc('rpc_master_acessos', { p_ies: p[1] })],
    ['POST', /^\/api\/master\/escopos$/, async (p, q, c) => ({ ...(await sb.rpc('rpc_conceder_escopo_email', {
      p_email: c.email, p_nome: c.nome, p_ies: c.ies_id, p_curso: c.curso_id ?? null, p_papel: c.papel })), senha_temporaria: null })],
    ['POST', /^\/api\/master\/escopos\/(\d+)\/revogar$/, (p) => sb.rpc('rpc_revogar_escopo', { p_escopo: p[1] })],
    ['POST', /^\/api\/master\/usuarios\/([0-9a-f-]{36})\/revogar$/, (p) => sb.rpc('rpc_revogar_usuario', { p_usuario: p[1] })],
  ];
  return async function chamar(metodo, endereco, corpo) {
    const u = new URL(endereco, location.origin);
    const r = rotas.find(([m, re]) => m === metodo && re.test(u.pathname));
    if (!r) throw Object.assign(new Error('Operação não disponível no modo Supabase'), { status: 404 });
    return r[2](u.pathname.match(r[1]), u.searchParams, corpo ?? {});
  };
}
