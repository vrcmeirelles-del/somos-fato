// Interface autenticada do piloto. A UI esconde ações por conveniência;
// a autorização real está no servidor (toda chamada é revalidada lá).
const $ = (s) => document.querySelector(s);

function h(tag, attrs = {}, ...filhos) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v == null || v === false) continue;
    if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
    else if (k === 'class') e.className = v;
    else e.setAttribute(k, v === true ? '' : v);
  }
  for (const f of filhos.flat()) if (f != null && f !== false) e.append(f instanceof Node ? f : String(f));
  return e;
}

const uuid = () => (crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`);

async function api(metodo, url, corpo) {
  const opts = { method: metodo, credentials: 'same-origin', headers: {} };
  if (metodo !== 'GET') {
    opts.headers = { 'content-type': 'application/json', 'x-m360': '1', 'idempotency-key': uuid() };
    opts.body = JSON.stringify(corpo ?? {});
  }
  const r = await fetch(url, opts);
  const d = await r.json().catch(() => ({}));
  if (r.status === 401) { location.href = '/login'; throw new Error('Sessão expirada'); }
  if (!r.ok) throw Object.assign(new Error(d.erro || `Erro ${r.status}`), { status: r.status });
  return d;
}

const moeda = (c) => (c / 100).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
const pct = (x) => (x == null ? h('span', { class: 'nd', title: 'Indisponível: sem denominador ou sem meta' }, 'N/D') : `${(x * 100).toFixed(1)}%`);
const num = (x) => (x == null ? h('span', { class: 'nd', title: 'Indisponível' }, 'N/D') : String(x));
const data = (iso) => (iso ? new Date(iso).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' }) : '');
const ROTULO = {
  novo: 'Novo', contato: 'Contato', inscrito: 'Inscrito', pre_matricula: 'Pré-matrícula', matricula_comercial: 'Matrícula comercial',
  confirmado: 'Ingresso efetivo', perdido: 'Perdido', cancelado: 'Cancelado',
  vestibular: 'Vestibular', enem: 'ENEM', transferencia: 'Transferência', segunda_graduacao: '2ª graduação / portador de diploma', reingresso: 'Reingresso',
  indicacao: 'Indicação', convenio: 'Convênio', visita_escolar: 'Visita escolar', evento: 'Evento', pos_graduacao: 'Pós-graduação',
  consentimento: 'Consentimento', procedimentos_preliminares_contrato: 'Procedimentos preliminares de contrato', legitimo_interesse: 'Legítimo interesse',
  documental: 'Documental', financeira: 'Financeira', academica: 'Acadêmica', valida: 'Válida', invalida: 'Inválida', isencao_formal: 'Isenção formal',
  primeiro_contato: 'Primeiro contato', follow_up: 'Follow-up', pendencia_validacao: 'Pendência de validação', recuperacao: 'Recuperação',
  gestor: 'Gestor', reitoria: 'Reitoria', coordenador: 'Coordenação', comercial: 'Comercial', secretaria: 'Secretaria', financeiro: 'Financeiro',
  pendente_aprovacao: 'Pendente de aprovação', aprovada: 'Aprovada', rejeitada: 'Rejeitada', aceita: 'Aceita', expirada: 'Expirada',
};
const rot = (k) => ROTULO[k] ?? k;
const status = (msg, tipo = 'sucesso') => h('p', { role: tipo === 'erro' ? 'alert' : 'status', class: tipo }, msg);

let ME; let IES; let EST;
const tem = (...p) => EST && p.some((x) => EST.papeis.includes(x));

function iesAtual() {
  const m = location.pathname.match(/^\/ies\/(\d+)\//);
  if (m) return Number(m[1]);
  const q = Number(new URLSearchParams(location.search).get('ies'));
  if (q) return q;
  try { const s = Number(localStorage.getItem('m360_ies')); if (s) return s; } catch { /* sem storage */ }
  return ME.escopos[0]?.ies_id ?? null;
}

function montarTopo() {
  const iesUnicas = [...new Map(ME.escopos.map((e) => [e.ies_id, e.ies_nome])).entries()];
  const sel = $('#ies');
  sel.replaceChildren(...iesUnicas.map(([id, nome]) => h('option', { value: id, selected: id === IES }, nome)));
  sel.hidden = !iesUnicas.length;
  sel.onchange = () => {
    try { localStorage.setItem('m360_ies', sel.value); } catch { /* ignore */ }
    const rota = location.pathname.match(/^\/ies\/\d+\/(\w+)/)?.[1];
    location.href = rota ? `/ies/${sel.value}/${rota}` : `${location.pathname}?ies=${sel.value}`;
  };
  const papeis = ME.escopos.filter((e) => e.ies_id === IES).map((e) => rot(e.papel) + (e.curso_nome ? ` (${e.curso_nome})` : ''));
  $('#quem').textContent = `${ME.usuario.nome}${papeis.length ? ' · ' + [...new Set(papeis)].join(', ') : ''}${ME.usuario.master ? ' · Master' : ''}`;
  $('#sair').onclick = async () => { await api('POST', '/api/logout'); location.href = '/login'; };
  const links = [];
  if (IES) {
    links.push([`/ies/${IES}/dashboard`, 'Painel'], [`/ies/${IES}/crm`, 'CRM']);
    for (const [p, n] of [['matriculas', 'Matrículas'], ['propostas', 'Propostas'], ['campanhas', 'Campanhas'], ['academia', 'Academia'], ['configuracoes', 'Configurações']]) links.push([`/${p}?ies=${IES}`, n]);
  }
  if (ME.usuario.master) links.push(['/master', 'Master']);
  $('#nav').replaceChildren(...links.map(([href, n]) => h('a', { href, 'aria-current': href.split('?')[0] === location.pathname ? 'page' : null }, n)));
}

// ---------------- Painel ----------------
async function paginaPainel(main) {
  const coortes = EST.coortes.length ? EST.coortes : [];
  const selC = h('select', { id: 'coorte' }, coortes.map((c) => h('option', { value: c }, c)));
  const selA = h('select', { id: 'agrupar' }, ['curso', 'turno', 'modalidade', 'forma_ingresso', 'atendente'].map((a) => h('option', { value: a }, rot(a) === a ? a.replace('_', ' ') : rot(a))));
  const area = h('div');
  const fila = h('section');
  main.replaceChildren(
    h('h1', {}, `Painel · ${EST.ies.nome}`),
    h('div', { class: 'filtros' }, h('label', {}, 'Coorte ', selC), h('label', {}, 'Agrupar por ', selA)),
    area, fila,
  );
  async function carregar() {
    if (!selC.value) { area.replaceChildren(h('p', { class: 'nd' }, 'Sem coortes com dados ou metas. Indicadores indisponíveis.')); return; }
    const bi = await api('GET', `/api/ies/${IES}/bi?coorte=${encodeURIComponent(selC.value)}&agrupar=${selA.value}`);
    const t = bi.totais;
    area.replaceChildren(
      h('div', { class: 'kpis' },
        [['Oportunidades', num(t.oportunidades)], ['Matrículas comerciais', num(t.matriculas_comerciais)], ['Ingressantes efetivos', num(t.ingressantes)],
          ['Conversão (coorte)', pct(t.conversao)], ['Meta', num(t.meta)], ['Atingimento', pct(t.atingimento)],
          ['Cancelamentos', num(t.cancelamentos)], ['Oportunidades necessárias (projeção)', num(t.projecao_oportunidades_necessarias)]]
          .map(([k, v]) => h('div', { class: 'kpi' }, h('span', {}, k), h('strong', {}, v)))),
      h('p', { class: 'nota' }, `N/D = indisponível (sem denominador ou sem meta), distinto de zero. Denominador da conversão: oportunidades da coorte ${bi.coorte}. Ingressantes contam pessoas distintas. Cobertura: ${bi.cobertura === 'ies' ? 'instituição inteira' : 'somente cursos autorizados'}.`),
      h('div', { class: 'tabela' }, h('table', {},
        h('thead', {}, h('tr', {}, ['Grupo', 'Oport.', 'Mat. comerciais', 'Ingressantes', 'Conversão', 'Meta', 'Atingimento', 'Perdidos', 'Cancel.'].map((c) => h('th', { scope: 'col' }, c)))),
        h('tbody', {}, bi.linhas.length ? bi.linhas.map((l) => h('tr', {},
          h('td', {}, rot(l.chave)), h('td', {}, l.oportunidades), h('td', {}, l.matriculas_comerciais), h('td', {}, l.ingressantes),
          h('td', {}, pct(l.conversao)), h('td', {}, num(l.meta)), h('td', {}, pct(l.atingimento)), h('td', {}, l.perdidos), h('td', {}, l.cancelamentos),
        )) : h('tr', {}, h('td', { colspan: 9, class: 'nd' }, 'Sem dados para esta coorte (indisponível).'))))),
    );
  }
  selC.onchange = carregar; selA.onchange = carregar;
  await carregar();
  if (tem('gestor', 'comercial', 'secretaria', 'financeiro')) await desenharFila(fila);
}

async function desenharFila(alvo, todas = false) {
  const f = await api('GET', `/api/ies/${IES}/fila`);
  const totalFila = f.tarefas.length;
  const atrasadas = f.tarefas.filter((t) => t.atrasada).length;
  if (!todas) f.tarefas = f.tarefas.slice(0, 10);
  const msg = h('div');
  const botaoCiclo = tem('gestor') ? h('button', { class: 'peq', onclick: async (ev) => {
    ev.target.disabled = true;
    try {
      const r = await api('POST', `/api/ies/${IES}/maim/ciclo`);
      await desenharFila(alvo);
      alvo.prepend(status(`Ciclo MAIM: ${r.follow_ups} follow-ups, ${r.pendencias_validacao} pendências de validação, ${r.suprimidos_optout} suprimidos por opt-out, ${r.limite_atingido} no limite, ${r.atrasadas} tarefas atrasadas.`));
    } catch (e) { msg.replaceChildren(status(e.message, 'erro')); ev.target.disabled = false; }
  } }, 'Executar ciclo MAIM') : null;
  alvo.replaceChildren(
    h('h2', {}, 'Fila de acompanhamento (MAIM)'),
    h('p', { class: 'nota' }, 'Tarefas internas com SLA. Envio externo está desativado: o botão “Disparar” só revalida e registra a tentativa.'),
    h('p', {}, `${totalFila} tarefa(s) aberta(s) · ${atrasadas} atrasada(s) no SLA${totalFila > f.tarefas.length ? ` · exibindo as ${f.tarefas.length} mais urgentes` : ''}`,
      totalFila > f.tarefas.length ? h('button', { class: 'sec peq', onclick: () => desenharFila(alvo, true) }, ' Ver todas') : null),
    botaoCiclo, msg,
    h('div', { class: 'tabela' }, h('table', {},
      h('thead', {}, h('tr', {}, ['Vence', 'Tipo', 'Candidato', 'Curso', 'Canal', 'Responsável', 'Ações'].map((c) => h('th', { scope: 'col' }, c)))),
      h('tbody', {}, f.tarefas.length ? f.tarefas.map((t) => {
        const entrada = h('input', { 'aria-label': `Resultado do contato da tarefa ${t.id}`, placeholder: 'Resultado do contato', maxlength: 300 });
        return h('tr', {},
          h('td', { class: t.atrasada ? 'atrasada' : null }, data(t.vence_em), t.atrasada ? ' (atrasada)' : ''),
          h('td', {}, rot(t.tipo)), h('td', {}, h('button', { class: 'sec peq', onclick: () => abrirDetalhe(t.oportunidade_id) }, t.nome)),
          h('td', {}, t.curso), h('td', {}, t.canal ?? '—'), h('td', {}, t.responsavel ?? h('span', { class: 'nd' }, 'sem responsável')),
          h('td', {}, t.tipo === 'pendencia_validacao' ? h('a', { href: `/matriculas?ies=${IES}` }, 'Ir para matrículas') : h('div', { class: 'form-linha' }, entrada,
            h('button', { class: 'peq', onclick: async () => {
              try { const r = await api('POST', `/api/tarefas/${t.id}/concluir`, { resultado: entrada.value }); await desenharFila(alvo); alvo.prepend(status(`Tarefa ${r.status}${r.motivo ? ' — ' + r.motivo : ''}.`)); }
              catch (e) { msg.replaceChildren(status(e.message, 'erro')); }
            } }, 'Registrar contato'),
            h('button', { class: 'sec peq', onclick: async () => {
              try { const r = await api('POST', `/api/tarefas/${t.id}/disparar`); msg.replaceChildren(status(`${r.motivo}. Elegível na revalidação: ${r.elegivel ? 'sim' : 'não'}.`)); }
              catch (e) { msg.replaceChildren(status(e.message, 'erro')); }
            } }, 'Disparar'))));
      }) : h('tr', {}, h('td', { colspan: 7, class: 'nd' }, 'Nenhuma tarefa aberta.')))),
    ),
  );
}

// ---------------- CRM ----------------
async function paginaCrm(main) {
  const selC = h('select', { 'aria-label': 'Coorte' }, h('option', { value: '' }, 'Todas as coortes'), EST.coortes.map((c) => h('option', { value: c }, c)));
  const selCurso = h('select', { 'aria-label': 'Curso' }, h('option', { value: '' }, 'Todos os cursos'), EST.cursos.map((c) => h('option', { value: c.id }, `${c.nome} · ${c.turno}`)));
  const quadro = h('div', { class: 'kanban', role: 'list' });
  const msg = h('div');
  main.replaceChildren(
    h('h1', {}, 'CRM educacional'),
    tem('comercial', 'gestor') ? formNova(msg, () => carregar()) : null,
    tem('comercial', 'gestor') ? formImportar(msg, () => carregar()) : null,
    msg,
    h('div', { class: 'filtros' }, h('label', {}, 'Coorte ', selC), h('label', {}, 'Curso ', selCurso)),
    quadro,
  );
  async function carregar() {
    const cols = await Promise.all(EST.etapas.map(async (et) => {
      const qs = new URLSearchParams({ etapa: et, por_pagina: '50' });
      if (selC.value) qs.set('coorte', selC.value);
      if (selCurso.value) qs.set('curso_id', selCurso.value);
      return [et, await api('GET', `/api/ies/${IES}/oportunidades?${qs}`)];
    }));
    quadro.replaceChildren(...cols.map(([et, r]) => h('section', { class: 'coluna', role: 'listitem', 'aria-label': rot(et) },
      h('h2', {}, h('span', {}, rot(et)), h('span', {}, r.total)),
      r.itens.map((o) => h('button', { class: 'cartao', onclick: () => abrirDetalhe(o.id, carregar) },
        h('strong', {}, o.nome), h('small', {}, `${o.curso} · ${o.turno} · ${o.coorte}`), h('small', {}, `${rot(o.forma_ingresso)} · ${o.responsavel ?? 'sem responsável'}`))),
      r.total > r.itens.length ? h('p', { class: 'nota' }, `Exibindo ${r.itens.length} de ${r.total}. Use os filtros para refinar.`) : null)));
  }
  selC.onchange = carregar; selCurso.onchange = carregar;
  window.__recarregar = carregar;
  await carregar();
}

function campo(rotulo, el) { return h('label', {}, rotulo + ' ', el); }

function formNova(msg, depois) {
  const f = {
    nome: h('input', { required: true, maxlength: 120 }), email: h('input', { type: 'email' }), telefone: h('input', { inputmode: 'tel' }),
    curso_id: h('select', {}, EST.cursos.map((c) => h('option', { value: c.id }, `${c.nome} · ${c.turno}`))),
    forma_ingresso: h('select', {}, EST.formas_ingresso.map((x) => h('option', { value: x }, rot(x)))),
    coorte: h('input', { value: EST.coortes[0] ?? '2027.1', pattern: '\\d{4}\\.[12]' }),
    base_legal: h('select', {}, h('option', { value: '' }, 'Selecione…'), EST.bases_legais.map((x) => h('option', { value: x }, rot(x)))),
    origem: h('input', { placeholder: 'ex.: site, evento escolar' }),
  };
  return h('details', {}, h('summary', {}, 'Nova oportunidade'),
    h('form', { class: 'form-linha', onsubmit: async (ev) => {
      ev.preventDefault();
      const corpo = Object.fromEntries(Object.entries(f).map(([k, el]) => [k, k === 'curso_id' ? Number(el.value) : el.value]));
      if (!corpo.email) delete corpo.email; if (!corpo.telefone) delete corpo.telefone;
      try {
        const r = await api('POST', `/api/ies/${IES}/oportunidades`, corpo);
        msg.replaceChildren(status(r.duplicada ? `Já existia oportunidade para esta pessoa, curso e coorte (#${r.id}). Nada foi duplicado.` : `Oportunidade #${r.id} criada e distribuída.`));
        ev.target.reset(); depois();
      } catch (e) { msg.replaceChildren(status(e.message, 'erro')); }
    } },
    campo('Nome', f.nome), campo('E-mail', f.email), campo('Telefone', f.telefone), campo('Curso', f.curso_id), campo('Forma de ingresso', f.forma_ingresso),
    campo('Coorte', f.coorte), campo('Base legal (LGPD)', f.base_legal), campo('Origem', f.origem), h('button', { type: 'submit' }, 'Cadastrar')));
}

function formImportar(msg, depois) {
  const ta = h('textarea', { 'aria-label': 'Linhas para importar', placeholder: 'nome;email;telefone;curso_id;forma_ingresso;coorte;base_legal;origem' });
  return h('details', {}, h('summary', {}, 'Importar lista (deduplicada)'),
    h('p', { class: 'nota' }, `Uma linha por candidato, separada por ponto e vírgula: nome;email;telefone;curso_id;forma_ingresso;coorte;base_legal;origem. Cursos: ${EST.cursos.map((c) => `${c.id}=${c.nome}`).join(', ')}. Linhas sem origem ou base legal são rejeitadas.`),
    ta, h('button', { onclick: async () => {
      const linhas = ta.value.split('\n').map((l) => l.trim()).filter(Boolean).map((l) => {
        const [nome, email, telefone, curso_id, forma_ingresso, coorte, base_legal, origem] = l.split(';').map((x) => x?.trim());
        const o = { nome, curso_id: Number(curso_id), forma_ingresso, coorte, base_legal, origem };
        if (email) o.email = email; if (telefone) o.telefone = telefone;
        return o;
      });
      try {
        const r = await api('POST', `/api/ies/${IES}/importacoes`, { linhas });
        msg.replaceChildren(status(`Importação: ${r.criadas} criadas, ${r.duplicadas} duplicadas, ${r.rejeitadas.length} rejeitadas.`),
          r.rejeitadas.length ? h('ul', {}, r.rejeitadas.map((x) => h('li', {}, `Linha ${x.linha}: ${x.motivo}`))) : null);
        depois();
      } catch (e) { msg.replaceChildren(status(e.message, 'erro')); }
    } }, 'Importar'));
}

// ---------------- Detalhe ----------------
async function abrirDetalhe(id, aoMudar) {
  const dlg = $('#detalhe');
  const corpo = $('#det-corpo');
  const recarregar = async (aviso) => { await desenhar(aviso); aoMudar?.(); };
  async function desenhar(aviso) {
    let d;
    try { d = await api('GET', `/api/oportunidades/${id}`); }
    catch (e) { corpo.replaceChildren(status(e.message, 'erro'), h('button', { onclick: () => dlg.close() }, 'Fechar')); return; }
    const o = d.oportunidade; const p = d.pessoa;
    const msg = h('div', {}, aviso ? status(aviso) : null);
    const exec = (fn) => async (ev) => {
      ev?.target && (ev.target.disabled = true);
      try { const r = await fn(); await recarregar(r); } catch (e) { msg.replaceChildren(status(e.message, 'erro')); if (ev?.target) ev.target.disabled = false; }
    };
    const motivo = h('input', { 'aria-label': 'Motivo da perda', placeholder: 'Motivo (obrigatório para perda)', maxlength: 200 });
    const desconto = h('input', { type: 'number', min: 0, max: 100, step: '0.5', value: 10, 'aria-label': 'Desconto em %' });
    const validade = h('input', { type: 'number', min: 1, max: 30, value: 7, 'aria-label': 'Validade em dias' });
    const podeFunil = tem('comercial', 'gestor');
    corpo.replaceChildren(
      h('div', { class: 'det-topo' },
        h('div', {}, h('h2', { id: 'det-titulo' }, p.nome), h('p', {}, `${d.curso.nome} · ${d.curso.turno} · ${d.curso.modalidade} · coorte ${o.coorte}`)),
        h('button', { class: 'sec', onclick: () => dlg.close(), 'aria-label': 'Fechar' }, 'Fechar')),
      h('p', {}, h('span', { class: 'chip' }, rot(o.etapa)), h('span', { class: 'chip' }, rot(o.forma_ingresso)), h('span', { class: 'chip' }, `versão ${o.versao}`),
        h('span', { class: 'chip' }, `responsável: ${o.responsavel ?? '—'}`)),
      msg,
      h('div', { class: 'grade2' },
        h('section', {}, h('h3', {}, 'Contato e LGPD'),
          h('p', {}, `E-mail: ${p.email ?? '—'}`, h('br'), `Telefone: ${p.telefone ?? '—'}`, p.dados_mascarados ? h('br') : null, p.dados_mascarados ? h('small', { class: 'nota' }, 'Dados mascarados para o seu perfil (minimização).') : null),
          h('p', {}, `Base legal: ${rot(p.base_legal)}`, h('br'), `Origem: ${p.origem}`),
          h('p', {}, 'Opt-out: ', ['email', 'whatsapp', 'telefone'].map((c) => h('span', { class: p.optout[c] ? 'chip erro' : 'chip' }, `${c}: ${p.optout[c] ? 'bloqueado' : 'permitido'}`))),
          tem('comercial', 'gestor', 'secretaria') && !p.anonimizada ? h('div', { class: 'acoes' }, ['email', 'whatsapp', 'telefone'].filter((c) => !p.optout[c]).map((c) =>
            h('button', { class: 'sec peq', onclick: exec(async () => { const r = await api('POST', `/api/oportunidades/${id}/optout`, { canal: c }); return `Opt-out de ${c} registrado; ${r.tarefas_suprimidas} tarefa(s) suprimida(s).`; }) }, `Opt-out ${c}`))) : null,
          tem('gestor') && !p.anonimizada ? h('button', { class: 'perigo peq', onclick: exec(async () => {
            if (!confirm('Anonimizar os dados pessoais deste titular? A ação não pode ser desfeita; o histórico estatístico é preservado.')) throw new Error('Operação cancelada');
            await api('POST', `/api/oportunidades/${id}/anonimizar`); return 'Titular anonimizado.';
          }) }, 'Anonimizar titular (LGPD)') : null),
        h('section', {}, h('h3', {}, 'Funil'),
          podeFunil && d.transicoes.length ? h('div', {},
            d.transicoes.includes('perdido') ? motivo : null,
            h('div', { class: 'acoes' }, d.transicoes.map((para) => h('button', { class: para === 'perdido' ? 'perigo peq' : 'peq', onclick: exec(async () => {
              await api('POST', `/api/oportunidades/${id}/etapa`, { para, versao_esperada: o.versao, ...(para === 'perdido' ? { motivo: motivo.value } : {}) });
              return `Etapa atualizada para ${rot(para)}.`;
            }) }, `→ ${rot(para)}`)))) : h('p', { class: 'nota' }, o.etapa === 'matricula_comercial' ? 'Próximo passo: validações em Matrículas.' : 'Sem transições disponíveis para seu perfil.'),
          o.motivo_perda ? h('p', {}, `Motivo da perda: ${o.motivo_perda}`) : null,
          h('h3', {}, 'Validações'),
          h('p', {}, ['documental', 'financeira', 'academica'].map((dim) => h('span', { class: o[`val_${dim}`] ? 'chip ok' : 'chip pend' }, `${rot(dim)}: ${o[`val_${dim}`] ? 'ok' : 'pendente'}`))),
          d.validacoes.length ? h('ul', { class: 'historico' }, d.validacoes.map((v) => h('li', {}, `${rot(v.dimensao)} · ${rot(v.resultado)} · ${v.por} · ${data(v.em)} — ${v.evidencia}`))) : null),
      ),
      h('section', {}, h('h3', {}, 'Propostas'),
        podeFunil && ['inscrito', 'pre_matricula', 'matricula_comercial'].includes(o.etapa) ? h('div', { class: 'form-linha' },
          campo('Desconto %', desconto), campo('Validade (dias)', validade),
          h('button', { class: 'peq', onclick: exec(async () => {
            const r = await api('POST', `/api/oportunidades/${id}/propostas`, { desconto_pct: Number(desconto.value), validade_dias: Number(validade.value) });
            return `Proposta #${r.id}: ${moeda(r.valorFinalCentavos)}/mês — ${rot(r.status)}${r.exigeAprovacao ? ` (acima do limite de ${r.limite_pct}%)` : ''}.`;
          }) }, 'Gerar proposta'),
          h('small', { class: 'nota' }, `Mensalidade ${moeda(d.curso.mensalidade_centavos)} · limite sem aprovação ${d.curso.desconto_max_pct}%`)) : null,
        d.propostas.length ? h('div', { class: 'tabela' }, h('table', {}, h('thead', {}, h('tr', {}, ['#', 'Desconto', 'Valor final', 'Validade', 'Status', ''].map((c) => h('th', {}, c)))),
          h('tbody', {}, d.propostas.map((pr) => h('tr', {}, h('td', {}, pr.id), h('td', {}, `${pr.desconto_pct}%`), h('td', {}, moeda(pr.valor_final_centavos)), h('td', {}, data(pr.validade)), h('td', {}, rot(pr.status)),
            h('td', {}, pr.status === 'aprovada' && podeFunil ? h('button', { class: 'peq', onclick: exec(async () => { const r = await api('POST', `/api/propostas/${pr.id}/aceite`); return `Proposta ${rot(r.status)}.`; }) }, 'Registrar aceite') : null)))))) : h('p', { class: 'nota' }, 'Nenhuma proposta.')),
      h('section', {}, h('h3', {}, 'Histórico (auditoria)'),
        h('ul', { class: 'historico' }, d.historico.map((ev) => h('li', {}, `${data(ev.em)} · ${ev.por ?? 'sistema'} · ${ev.acao}${ev.dados.de ? ` (${rot(ev.dados.de)} → ${rot(ev.dados.para)})` : ''}${ev.dados.motivo ? ` — ${ev.dados.motivo}` : ''}`)))),
    );
  }
  await desenhar();
  if (!dlg.open) dlg.showModal();
}

// ---------------- Matrículas ----------------
async function paginaMatriculas(main) {
  const msg = h('div');
  const tabela = h('div', { class: 'tabela' });
  main.replaceChildren(h('h1', {}, 'Matrículas'),
    h('p', { class: 'nota' }, 'Matrícula comercial, validações documental/financeira/acadêmica e ingresso efetivo são etapas separadas. Secretaria valida documental e acadêmica; financeiro valida financeira (inclui isenção formal); comercial não valida. A confirmação só ocorre com as três dimensões válidas.'),
    msg, tabela);
  async function carregar() {
    const itens = await api('GET', `/api/ies/${IES}/pendencias`);
    const dims = [...(tem('secretaria') ? ['documental', 'academica'] : []), ...(tem('financeiro') ? ['financeira'] : [])];
    tabela.replaceChildren(h('table', {},
      h('thead', {}, h('tr', {}, ['Candidato', 'Curso', 'Coorte', 'Situação', 'Validações', 'Ações'].map((c) => h('th', { scope: 'col' }, c)))),
      h('tbody', {}, itens.length ? itens.map((o) => {
        const completo = o.val_documental && o.val_financeira && o.val_academica;
        const selDim = h('select', { 'aria-label': 'Dimensão' }, dims.map((x) => h('option', { value: x }, rot(x))));
        const selRes = h('select', { 'aria-label': 'Resultado' }, h('option', { value: 'valida' }, 'Válida'), h('option', { value: 'invalida' }, 'Inválida'), tem('financeiro') ? h('option', { value: 'isencao_formal' }, 'Isenção formal (financeira)') : null);
        const evid = h('input', { 'aria-label': 'Evidência', placeholder: 'Evidência (obrigatória)', maxlength: 500 });
        const motivo = h('input', { 'aria-label': 'Motivo do cancelamento', placeholder: 'Motivo do cancelamento', maxlength: 200 });
        const fazer = (fn) => async (ev) => { ev.target.disabled = true; try { msg.replaceChildren(status(await fn())); await carregar(); } catch (e) { msg.replaceChildren(status(e.message, 'erro')); ev.target.disabled = false; } };
        return h('tr', {},
          h('td', {}, h('button', { class: 'sec peq', onclick: () => abrirDetalhe(o.id, carregar) }, o.nome)), h('td', {}, o.curso), h('td', {}, o.coorte),
          h('td', {}, rot(o.etapa)),
          h('td', {}, ['documental', 'financeira', 'academica'].map((dim) => h('span', { class: o[`val_${dim}`] ? 'chip ok' : 'chip pend' }, rot(dim)))),
          h('td', {}, o.etapa === 'matricula_comercial' ? h('div', {},
            dims.length ? h('div', { class: 'form-linha' }, selDim, selRes, evid, h('button', { class: 'peq', onclick: fazer(async () => {
              await api('POST', `/api/oportunidades/${o.id}/validacoes`, { dimensao: selDim.value, resultado: selRes.value, evidencia: evid.value, versao_esperada: o.versao });
              return 'Validação registrada com evidência.';
            }) }, 'Registrar')) : null,
            tem('secretaria', 'gestor') ? h('div', { class: 'acoes' },
              h('button', { class: 'ok peq', disabled: !completo, title: completo ? null : 'Faltam validações', onclick: fazer(async () => { await api('POST', `/api/oportunidades/${o.id}/confirmar`, { versao_esperada: o.versao }); return 'Ingresso efetivo confirmado.'; }) }, 'Confirmar ingresso'),
              motivo, h('button', { class: 'perigo peq', onclick: fazer(async () => { await api('POST', `/api/oportunidades/${o.id}/cancelar`, { versao_esperada: o.versao, motivo: motivo.value }); return 'Matrícula cancelada (histórico preservado).'; }) }, 'Cancelar')) : null)
            : o.etapa === 'confirmado' && tem('secretaria', 'gestor') ? h('div', { class: 'form-linha' }, motivo, h('button', { class: 'perigo peq', onclick: fazer(async () => { await api('POST', `/api/oportunidades/${o.id}/cancelar`, { versao_esperada: o.versao, motivo: motivo.value }); return 'Ingresso cancelado (histórico preservado).'; }) }, 'Cancelar ingresso'))
              : h('span', { class: 'nota' }, o.etapa === 'cancelado' ? `Cancelada em ${data(o.cancelada_em)}` : `Confirmada em ${data(o.confirmada_em)}`)));
      }) : h('tr', {}, h('td', { colspan: 6, class: 'nd' }, 'Nenhuma matrícula comercial registrada.')))));
  }
  await carregar();
}

// ---------------- Propostas ----------------
async function paginaPropostas(main) {
  if (!tem('gestor', 'comercial')) { main.replaceChildren(h('h1', {}, 'Propostas'), h('p', {}, 'Seu perfil não acessa propostas.')); return; }
  const sel = h('select', { 'aria-label': 'Status' }, ['pendente_aprovacao', 'aprovada', 'aceita', 'rejeitada', 'expirada'].map((s) => h('option', { value: s }, rot(s))));
  const msg = h('div'); const tabela = h('div', { class: 'tabela' });
  main.replaceChildren(h('h1', {}, 'Propostas e bolsas'),
    h('p', { class: 'nota' }, 'Descontos acima do limite do curso exigem aprovação de gestor. Quem cria a proposta não pode aprová-la (segregação de funções).'),
    h('div', { class: 'filtros' }, h('label', {}, 'Status ', sel)), msg, tabela);
  async function carregar() {
    const itens = await api('GET', `/api/ies/${IES}/propostas?status=${sel.value}`);
    tabela.replaceChildren(h('table', {}, h('thead', {}, h('tr', {}, ['#', 'Candidato', 'Curso', 'Desconto', 'Limite', 'Valor final', 'Criada por', 'Validade', ''].map((c) => h('th', { scope: 'col' }, c)))),
      h('tbody', {}, itens.length ? itens.map((p) => h('tr', {},
        h('td', {}, p.id), h('td', {}, p.nome), h('td', {}, p.curso), h('td', {}, `${p.desconto_pct}%`), h('td', {}, `${p.desconto_max_pct}%`),
        h('td', {}, moeda(p.valor_final_centavos)), h('td', {}, p.criado_por_nome), h('td', {}, data(p.validade)),
        h('td', {}, p.status === 'pendente_aprovacao' && tem('gestor') ? h('div', { class: 'acoes' }, ['aprovar', 'rejeitar'].map((dec) => h('button', { class: dec === 'aprovar' ? 'ok peq' : 'perigo peq', onclick: async (ev) => {
          ev.target.disabled = true;
          try { const r = await api('POST', `/api/propostas/${p.id}/decisao`, { decisao: dec }); msg.replaceChildren(status(`Proposta #${p.id}: ${rot(r.status)}.`)); await carregar(); }
          catch (e) { msg.replaceChildren(status(e.message, 'erro')); ev.target.disabled = false; }
        } }, dec === 'aprovar' ? 'Aprovar' : 'Rejeitar'))) : null))) : h('tr', {}, h('td', { colspan: 9, class: 'nd' }, 'Nenhuma proposta neste status.')))));
  }
  sel.onchange = carregar;
  await carregar();
}

// ---------------- Configurações ----------------
async function paginaConfiguracoes(main) {
  if (!tem('gestor')) { main.replaceChildren(h('h1', {}, 'Configurações'), h('p', {}, 'Disponível apenas para gestores da instituição.')); return; }
  const msg = h('div');
  const c = EST.ies;
  const f = Object.fromEntries(['sla_horas', 'max_followups', 'dias_sem_contato', 'capacidade_atendente'].map((k) => [k, h('input', { type: 'number', value: c[k], min: 0 })]));
  const coorteMeta = h('input', { value: EST.coortes[0] ?? '2027.1', 'aria-label': 'Coorte da meta' });
  const metas = EST.cursos.map((cu) => [cu, h('input', { type: 'number', min: 0, 'aria-label': `Meta ${cu.nome}` })]);
  const aud = h('div', { class: 'tabela' });
  main.replaceChildren(h('h1', {}, 'Configurações'), msg,
    h('section', {}, h('h2', {}, 'MAIM e SLA'),
      h('div', { class: 'form-linha' }, campo('SLA do primeiro contato (h)', f.sla_horas), campo('Máx. follow-ups', f.max_followups), campo('Dias sem contato p/ follow-up', f.dias_sem_contato), campo('Capacidade por atendente', f.capacidade_atendente),
        h('button', { onclick: async () => {
          try { await api('POST', `/api/ies/${IES}/configuracoes`, Object.fromEntries(Object.entries(f).map(([k, el]) => [k, Number(el.value)]))); msg.replaceChildren(status('Configuração salva.')); }
          catch (e) { msg.replaceChildren(status(e.message, 'erro')); }
        } }, 'Salvar'))),
    h('section', {}, h('h2', {}, 'Metas por curso'),
      h('div', { class: 'form-linha' }, campo('Coorte', coorteMeta), metas.map(([cu, el]) => campo(cu.nome, el)),
        h('button', { onclick: async () => {
          try {
            for (const [cu, el] of metas) if (el.value !== '') await api('POST', `/api/ies/${IES}/metas`, { curso_id: cu.id, coorte: coorteMeta.value, meta: Number(el.value) });
            msg.replaceChildren(status('Metas salvas. Cursos sem meta ficam “N/D”, não zero.'));
          } catch (e) { msg.replaceChildren(status(e.message, 'erro')); }
        } }, 'Salvar metas'))),
    h('section', {}, h('h2', {}, 'Auditoria (somente leitura)'), aud));
  const a = await api('GET', `/api/ies/${IES}/auditoria`);
  aud.replaceChildren(h('table', {}, h('thead', {}, h('tr', {}, ['Quando', 'Quem', 'Ação', 'Entidade', 'Dados'].map((x) => h('th', { scope: 'col' }, x)))),
    h('tbody', {}, a.itens.map((x) => h('tr', {}, h('td', {}, data(x.em)), h('td', {}, x.por ?? 'sistema'), h('td', {}, x.acao), h('td', {}, `${x.entidade} ${x.entidade_id ?? ''}`), h('td', {}, h('code', {}, JSON.stringify(x.dados))))))),
  h('p', { class: 'nota' }, `Exibindo ${a.itens.length} de ${a.total} eventos.`));
}

function paginaBacklog(titulo, itens) {
  return (main) => main.replaceChildren(h('h1', {}, titulo),
    h('p', { class: 'aviso' }, 'Fora do escopo do piloto. Planejado para depois do MVP, conforme a Bíblia-Mestra.'),
    h('ul', {}, itens.map((i) => h('li', {}, i))));
}

// ---------------- Master ----------------
async function paginaMaster(main) {
  const msg = h('div'); const lista = h('div', { class: 'tabela' }); const acessos = h('section');
  const nome = h('input', { maxlength: 120 }); const plano = h('select', {}, ['piloto', 'essencial', 'completo'].map((p) => h('option', {}, p)));
  const campus = h('input', { value: 'Campus Principal' });
  const cursos = h('textarea', { 'aria-label': 'Cursos', placeholder: 'Direito;noturno;presencial;1290,00;30\nAdministração;ead;ead;399,00;40' });
  main.replaceChildren(h('h1', {}, 'Painel Master'),
    h('p', { class: 'nota' }, 'O Master provisiona instituições e concede escopos. Não acessa dados de candidatos sem escopo explícito.'), msg,
    h('details', {}, h('summary', {}, 'Provisionar instituição'),
      h('div', { class: 'form-linha' }, campo('Nome', nome), campo('Plano', plano), campo('Campus', campus)),
      h('p', { class: 'nota' }, 'Cursos: um por linha — nome;turno;modalidade;mensalidade;desconto máximo %'), cursos,
      h('button', { onclick: async () => {
        try {
          const lc = cursos.value.split('\n').map((l) => l.trim()).filter(Boolean).map((l) => {
            const [n, turno, modalidade, mens, desc] = l.split(';').map((x) => x.trim());
            return { nome: n, turno, modalidade, mensalidade_centavos: Math.round(Number(String(mens).replace(/\./g, '').replace(',', '.')) * 100), desconto_max_pct: Number(desc ?? 30) };
          });
          const r = await api('POST', '/api/master/ies', { nome: nome.value, plano: plano.value, campus: [{ nome: campus.value, cursos: lc }] });
          msg.replaceChildren(status(`IES #${r.id} provisionada.`)); await carregar();
        } catch (e) { msg.replaceChildren(status(e.message, 'erro')); }
      } }, 'Provisionar')),
    lista, acessos);
  async function carregar() {
    const ies = await api('GET', '/api/master/ies');
    lista.replaceChildren(h('table', {}, h('thead', {}, h('tr', {}, ['IES', 'Plano', 'Status', 'Cursos', 'Usuários', ''].map((c) => h('th', { scope: 'col' }, c)))),
      h('tbody', {}, ies.map((i) => h('tr', {}, h('td', {}, i.nome), h('td', {}, i.plano), h('td', {}, i.status), h('td', {}, i.cursos), h('td', {}, i.usuarios),
        h('td', {}, h('div', { class: 'acoes' },
          h('button', { class: 'peq', onclick: () => desenharAcessos(i) }, 'Acessos'),
          h('button', { class: 'sec peq', onclick: async () => {
            try { await api('POST', `/api/master/ies/${i.id}/status`, { status: i.status === 'ativa' ? 'suspensa' : 'ativa' }); await carregar(); }
            catch (e) { msg.replaceChildren(status(e.message, 'erro')); }
          } }, i.status === 'ativa' ? 'Suspender' : 'Reativar'))))))));
  }
  async function desenharAcessos(i) {
    const a = await api('GET', `/api/master/ies/${i.id}/acessos`);
    const email = h('input', { type: 'email' }); const nomeU = h('input');
    const papel = h('select', {}, ['gestor', 'reitoria', 'coordenador', 'comercial', 'secretaria', 'financeiro'].map((p) => h('option', { value: p }, rot(p))));
    const curso = h('select', {}, h('option', { value: '' }, 'Toda a instituição'), a.cursos.map((c) => h('option', { value: c.id }, `${c.nome} · ${c.turno}`)));
    const fazer = (fn) => async () => { try { msg.replaceChildren(status(await fn())); await desenharAcessos(i); await carregar(); } catch (e) { msg.replaceChildren(status(e.message, 'erro')); } };
    acessos.replaceChildren(h('h2', {}, `Acessos · ${i.nome}`),
      h('div', { class: 'form-linha' }, campo('E-mail', email), campo('Nome', nomeU), campo('Papel', papel), campo('Curso', curso),
        h('button', { onclick: fazer(async () => {
          const r = await api('POST', '/api/master/escopos', { email: email.value, nome: nomeU.value || email.value, ies_id: i.id, papel: papel.value, curso_id: curso.value ? Number(curso.value) : null });
          return r.senha_temporaria ? `Convite criado. Senha temporária (exibida uma única vez): ${r.senha_temporaria}` : 'Escopo concedido a usuário existente.';
        }) }, 'Conceder escopo')),
      h('div', { class: 'tabela' }, h('table', {}, h('thead', {}, h('tr', {}, ['Usuário', 'Papel', 'Curso', 'Situação', ''].map((c) => h('th', { scope: 'col' }, c)))),
        h('tbody', {}, a.escopos.map((e) => h('tr', {}, h('td', {}, `${e.nome} (${e.email})`), h('td', {}, rot(e.papel)), h('td', {}, e.curso_nome ?? 'toda a IES'),
          h('td', {}, e.usuario_revogado_em ? 'usuário revogado' : e.revogado_em ? 'escopo revogado' : 'ativo'),
          h('td', {}, !e.revogado_em && !e.usuario_revogado_em ? h('div', { class: 'acoes' },
            h('button', { class: 'sec peq', onclick: fazer(async () => { await api('POST', `/api/master/escopos/${e.id}/revogar`); return 'Escopo revogado.'; }) }, 'Revogar escopo'),
            h('button', { class: 'perigo peq', onclick: fazer(async () => { await api('POST', `/api/master/usuarios/${e.usuario_id}/revogar`); return 'Usuário revogado em todas as IES; sessões encerradas.'; }) }, 'Revogar usuário')) : null)))))));
  }
  await carregar();
}

// ---------------- roteamento ----------------
async function iniciar() {
  ME = await api('GET', '/api/me');
  IES = iesAtual();
  if (IES && !ME.escopos.some((e) => e.ies_id === IES)) IES = ME.escopos[0]?.ies_id ?? null;
  montarTopo();
  const main = $('#app');
  const caminho = location.pathname;
  try {
    if (caminho === '/master') return await paginaMaster(main);
    if (!IES) { main.replaceChildren(h('h1', {}, 'Sem instituição'), h('p', {}, 'Seu usuário não possui escopo em nenhuma instituição.')); return; }
    EST = await api('GET', `/api/ies/${IES}/estrutura`);
    if (/\/dashboard$/.test(caminho)) return await paginaPainel(main);
    if (/\/crm$/.test(caminho)) return await paginaCrm(main);
    if (caminho === '/matriculas') return await paginaMatriculas(main);
    if (caminho === '/propostas') return await paginaPropostas(main);
    if (caminho === '/configuracoes') return await paginaConfiguracoes(main);
    if (caminho === '/campanhas') return paginaBacklog('Campanhas', ['Cadastro de campanhas, canais e metas por campanha', 'Atribuição de origem e custo por oportunidade', 'Integrações Meta/Google/TikTok (desligadas por padrão; exigem autorização)'])(main);
    if (caminho === '/academia') return paginaBacklog('Academia', ['Trilhas por competência (SDR, Closer, Farmer adaptados à educação)', 'Scripts, rubricas e reavaliação', 'PDI do atendente e registro de treinamento'])(main);
    main.replaceChildren(h('h1', {}, 'Página não encontrada'));
  } catch (e) {
    main.replaceChildren(status(e.message, 'erro'));
  }
}
iniciar();
