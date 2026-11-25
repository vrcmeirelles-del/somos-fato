// Serviço de domínio do Matrícula 360°.
// Toda autorização acontece aqui, a partir da identidade da sessão — nunca do cliente.
// Toda escrita grava auditoria na MESMA transação.
import {
  stages, todasEtapas, podeTransitar, confirm, DIMENSOES, FORMAS_INGRESSO, BASES_LEGAIS, CANAIS,
  calcularProposta, taxa, RegraViolada, normalizarEmail, normalizarTelefone, mascararEmail, mascararTelefone,
} from './motor.mjs';
import { gerarHash, conferirSenha, novoToken, hashToken, senhaTemporaria } from './senha.mjs';

export class ErroApp extends Error {
  constructor(status, msg, extra) { super(msg); this.status = status; this.extra = extra; }
}
const naoEncontrado = () => new ErroApp(404, 'Não encontrado');
const proibido = (m = 'Seu perfil não tem permissão para esta operação') => new ErroApp(403, m);
const invalido = (m) => new ErroApp(422, m);

export const PAPEIS = ['gestor', 'reitoria', 'coordenador', 'comercial', 'secretaria', 'financeiro'];
const LEITURA = PAPEIS;
const VE_DADOS_PESSOAIS = ['gestor', 'comercial', 'secretaria', 'financeiro'];
const OPERA_FUNIL = ['comercial', 'gestor'];
const TURNOS = ['matutino', 'vespertino', 'noturno', 'integral', 'ead'];
const MODALIDADES = ['presencial', 'ead', 'semipresencial'];
const SESSAO_HORAS = 8;

// ---------- validação de entrada ----------
export function inteiro(v, nome, { min = 1, max = 2 ** 31 - 1 } = {}) {
  const n = typeof v === 'string' && /^-?\d+$/.test(v) ? Number(v) : v;
  if (!Number.isInteger(n) || n < min || n > max) throw new ErroApp(400, `${nome} inválido`);
  return n;
}
function texto(v, nome, min = 1, max = 200) {
  if (typeof v !== 'string') throw new ErroApp(400, `${nome} obrigatório`);
  const t = v.trim();
  if (t.length < min || t.length > max) throw new ErroApp(400, `${nome} deve ter entre ${min} e ${max} caracteres`);
  return t;
}
function opcao(v, lista, nome) {
  if (!lista.includes(v)) throw new ErroApp(400, `${nome} inválido`);
  return v;
}
function coorteValida(v) {
  if (typeof v !== 'string' || !/^\d{4}\.[12]$/.test(v)) throw new ErroApp(400, 'Coorte deve ter formato AAAA.1 ou AAAA.2');
  return v;
}

export function criarServico(db, { agora = () => new Date() } = {}) {
  const todos = (sql, ...p) => db.prepare(sql).all(...p);
  const um = (sql, ...p) => db.prepare(sql).get(...p);
  const exec = (sql, ...p) => db.prepare(sql).run(...p);
  const iso = (d = agora()) => d.toISOString();
  const somarHoras = (h) => new Date(agora().getTime() + h * 3600e3).toISOString();

  // ---------- transação ----------
  let profundidade = 0;
  function tx(fn) {
    if (profundidade > 0) {
      const sp = `sp${profundidade}`;
      db.exec(`SAVEPOINT ${sp}`); profundidade++;
      try { const v = fn(); db.exec(`RELEASE ${sp}`); return v; }
      catch (e) { db.exec(`ROLLBACK TO ${sp}`); db.exec(`RELEASE ${sp}`); throw e; }
      finally { profundidade--; }
    }
    db.exec('BEGIN IMMEDIATE'); profundidade++;
    try { const v = fn(); db.exec('COMMIT'); return v; }
    catch (e) { db.exec('ROLLBACK'); throw e; }
    finally { profundidade--; }
  }

  function auditar(u, iesId, acao, entidade, entidadeId, dados = {}) {
    exec('INSERT INTO auditoria(ies_id, usuario_id, acao, entidade, entidade_id, dados, em) VALUES (?,?,?,?,?,?,?)',
      iesId ?? null, u?.id ?? null, acao, entidade, entidadeId == null ? null : String(entidadeId), JSON.stringify(dados), iso());
  }

  // ---------- identidade e escopo ----------
  function escoposAtivos(uid) {
    return todos(`SELECT e.id, e.ies_id, e.curso_id, e.papel FROM escopos e
      JOIN usuarios u ON u.id = e.usuario_id JOIN ies i ON i.id = e.ies_id
      WHERE e.usuario_id = ? AND e.revogado_em IS NULL AND u.ativo = 1 AND u.revogado_em IS NULL AND i.status = 'ativa'`, uid);
  }

  // Resolve o acesso do usuário a uma IES para um conjunto de papéis.
  // Sem nenhum escopo na IES => 404 (não revela existência). Com escopo, mas sem papel => 403.
  function acesso(u, iesId, papeis) {
    const es = escoposAtivos(u.id).filter((e) => e.ies_id === iesId);
    if (!es.length) throw naoEncontrado();
    const ok = es.filter((e) => papeis.includes(e.papel));
    if (!ok.length) throw proibido();
    const total = ok.some((e) => e.curso_id == null);
    const cursos = new Set(ok.filter((e) => e.curso_id != null).map((e) => e.curso_id));
    return { total, cursos, permite: (c) => total || cursos.has(c), papeis: new Set(es.map((e) => e.papel)) };
  }
  function acessoOuNulo(u, iesId, papeis) {
    try { return acesso(u, iesId, papeis); } catch { return null; }
  }
  function filtroCursos(a, col = 'o.curso_id') {
    if (a.total) return { sql: '', params: [] };
    const ids = [...a.cursos];
    return { sql: ` AND ${col} IN (${ids.map(() => '?').join(',') || 'NULL'})`, params: ids };
  }
  function exigirMaster(u) { if (!u.master) throw proibido('Operação restrita ao Master'); }

  // Carrega oportunidade exigindo leitura no curso (senão 404) e papel para a operação (senão 403).
  function carregarOportunidade(u, id, papeis) {
    id = inteiro(id, 'Identificador');
    const op = um('SELECT * FROM oportunidades WHERE id = ?', id);
    if (!op) throw naoEncontrado();
    const leitura = acessoOuNulo(u, op.ies_id, LEITURA);
    if (!leitura || !leitura.permite(op.curso_id)) throw naoEncontrado();
    if (papeis !== LEITURA) {
      const a = acesso(u, op.ies_id, papeis);
      if (!a.permite(op.curso_id)) throw proibido();
    }
    return op;
  }

  // ---------- autenticação ----------
  const tentativas = new Map();
  function login(email, senha, ip = 'local') {
    const chave = `${String(email).toLowerCase()}|${ip}`;
    const t = tentativas.get(chave) ?? { n: 0, ate: 0 };
    if (t.ate > Date.now()) throw new ErroApp(429, 'Muitas tentativas. Aguarde alguns minutos.');
    const u = um('SELECT * FROM usuarios WHERE email = ?', String(email ?? '').trim());
    const ok = conferirSenha(senha, u?.senha_hash) && u.ativo === 1 && !u.revogado_em;
    if (!ok) {
      t.n++; if (t.n >= 5) { t.ate = Date.now() + 5 * 60e3; t.n = 0; }
      tentativas.set(chave, t);
      throw new ErroApp(401, 'Credenciais inválidas');
    }
    tentativas.delete(chave);
    const token = novoToken();
    tx(() => {
      exec('DELETE FROM sessoes WHERE expira_em < ?', iso());
      exec('INSERT INTO sessoes(token_hash, usuario_id, criado_em, expira_em) VALUES (?,?,?,?)', hashToken(token), u.id, iso(), somarHoras(SESSAO_HORAS));
      auditar(u, null, 'sessao.login', 'usuario', u.id);
    });
    return { token, maxAge: SESSAO_HORAS * 3600 };
  }
  function usuarioDaSessao(token) {
    if (!token) return null;
    return um(`SELECT u.id, u.nome, u.email, u.master FROM sessoes s JOIN usuarios u ON u.id = s.usuario_id
      WHERE s.token_hash = ? AND s.expira_em > ? AND u.ativo = 1 AND u.revogado_em IS NULL`, hashToken(token), iso()) ?? null;
  }
  function logout(token) { exec('DELETE FROM sessoes WHERE token_hash = ?', hashToken(token)); }

  function eu(u) {
    const es = todos(`SELECT e.id, e.ies_id, i.nome AS ies_nome, e.curso_id, c.nome AS curso_nome, e.papel
      FROM escopos e JOIN ies i ON i.id = e.ies_id LEFT JOIN cursos c ON c.id = e.curso_id
      WHERE e.usuario_id = ? AND e.revogado_em IS NULL AND i.status = 'ativa' ORDER BY i.nome, e.papel`, u.id);
    return { usuario: { id: u.id, nome: u.nome, email: u.email, master: u.master === 1 }, escopos: es };
  }

  // ---------- Master ----------
  function provisionarIes(u, d) {
    exigirMaster(u);
    const nome = texto(d.nome, 'Nome da IES', 2, 120);
    const plano = d.plano == null ? 'piloto' : opcao(d.plano, ['piloto', 'essencial', 'completo'], 'Plano');
    if (!Array.isArray(d.campus) || !d.campus.length || d.campus.length > 20) throw new ErroApp(400, 'Informe de 1 a 20 campi');
    return tx(() => {
      if (um('SELECT 1 FROM ies WHERE nome = ?', nome)) throw new ErroApp(409, 'Já existe IES com este nome');
      const iesId = Number(exec('INSERT INTO ies(nome, plano, criado_em) VALUES (?,?,?)', nome, plano, iso()).lastInsertRowid);
      for (const cp of d.campus) {
        const campusId = Number(exec('INSERT INTO campus(ies_id, nome) VALUES (?,?)', iesId, texto(cp.nome, 'Nome do campus', 2, 120)).lastInsertRowid);
        if (!Array.isArray(cp.cursos) || !cp.cursos.length || cp.cursos.length > 100) throw new ErroApp(400, 'Cada campus precisa de 1 a 100 cursos');
        for (const c of cp.cursos) {
          const desc = c.desconto_max_pct ?? 30;
          if (typeof desc !== 'number' || desc < 0 || desc > 100) throw new ErroApp(400, 'Desconto máximo inválido');
          exec('INSERT INTO cursos(ies_id, campus_id, nome, turno, modalidade, mensalidade_centavos, desconto_max_pct) VALUES (?,?,?,?,?,?,?)',
            iesId, campusId, texto(c.nome, 'Nome do curso', 2, 120), opcao(c.turno, TURNOS, 'Turno'),
            opcao(c.modalidade, MODALIDADES, 'Modalidade'), inteiro(c.mensalidade_centavos, 'Mensalidade'), desc);
        }
      }
      auditar(u, iesId, 'ies.provisionar', 'ies', iesId, { plano });
      return { id: iesId };
    });
  }
  function listarIesMaster(u) {
    exigirMaster(u);
    // Master vê configuração e acessos, não candidatos.
    return todos(`SELECT i.id, i.nome, i.plano, i.status, i.criado_em,
      (SELECT count(*) FROM cursos c WHERE c.ies_id = i.id) AS cursos,
      (SELECT count(DISTINCT e.usuario_id) FROM escopos e WHERE e.ies_id = i.id AND e.revogado_em IS NULL) AS usuarios
      FROM ies i ORDER BY i.nome`);
  }
  function alterarStatusIes(u, iesId, d) {
    exigirMaster(u);
    iesId = inteiro(iesId, 'IES');
    const status = opcao(d.status, ['ativa', 'suspensa'], 'Status');
    return tx(() => {
      if (!exec('UPDATE ies SET status = ? WHERE id = ?', status, iesId).changes) throw naoEncontrado();
      auditar(u, iesId, 'ies.status', 'ies', iesId, { status });
      return { id: iesId, status };
    });
  }
  function acessosIes(u, iesId) {
    exigirMaster(u);
    iesId = inteiro(iesId, 'IES');
    if (!um('SELECT 1 FROM ies WHERE id = ?', iesId)) throw naoEncontrado();
    return {
      cursos: todos('SELECT c.id, c.nome, c.turno, c.modalidade, cp.nome AS campus FROM cursos c JOIN campus cp ON cp.id = c.campus_id WHERE c.ies_id = ? ORDER BY c.nome', iesId),
      escopos: todos(`SELECT e.id, e.papel, e.curso_id, c.nome AS curso_nome, e.concedido_em, e.revogado_em,
        u.id AS usuario_id, u.nome, u.email, u.revogado_em AS usuario_revogado_em
        FROM escopos e JOIN usuarios u ON u.id = e.usuario_id LEFT JOIN cursos c ON c.id = e.curso_id
        WHERE e.ies_id = ? ORDER BY e.revogado_em IS NOT NULL, u.nome`, iesId),
    };
  }
  function concederEscopo(u, d) {
    exigirMaster(u);
    const iesId = inteiro(d.ies_id, 'IES');
    const papel = opcao(d.papel, PAPEIS, 'Papel');
    const cursoId = d.curso_id == null ? null : inteiro(d.curso_id, 'Curso');
    if (papel === 'coordenador' && cursoId == null) throw invalido('Coordenador exige curso autorizado');
    const email = normalizar(() => normalizarEmail(d.email));
    if (!email) throw new ErroApp(400, 'E-mail obrigatório');
    return tx(() => {
      if (!um('SELECT 1 FROM ies WHERE id = ?', iesId)) throw naoEncontrado();
      if (cursoId != null && !um('SELECT 1 FROM cursos WHERE id = ? AND ies_id = ?', cursoId, iesId)) throw invalido('Curso não pertence à IES');
      let alvo = um('SELECT * FROM usuarios WHERE email = ?', email);
      let senha = null;
      if (!alvo) {
        senha = senhaTemporaria() + 'Aa1';
        const id = Number(exec('INSERT INTO usuarios(email, nome, senha_hash, criado_em) VALUES (?,?,?,?)',
          email, texto(d.nome, 'Nome', 2, 120), gerarHash(senha), iso()).lastInsertRowid);
        alvo = { id };
        auditar(u, iesId, 'usuario.convidar', 'usuario', id);
      } else if (alvo.revogado_em) throw invalido('Usuário revogado; crie novo convite com outro e-mail');
      try {
        const eid = Number(exec('INSERT INTO escopos(usuario_id, ies_id, curso_id, papel, concedido_por, concedido_em) VALUES (?,?,?,?,?,?)',
          alvo.id, iesId, cursoId, papel, u.id, iso()).lastInsertRowid);
        auditar(u, iesId, 'escopo.conceder', 'escopo', eid, { usuario_id: alvo.id, papel, curso_id: cursoId });
        return { escopo_id: eid, usuario_id: alvo.id, senha_temporaria: senha };
      } catch (e) {
        if (/UNIQUE/.test(e.message)) throw new ErroApp(409, 'Escopo já concedido');
        throw e;
      }
    });
  }
  function revogarEscopo(u, escopoId) {
    exigirMaster(u);
    escopoId = inteiro(escopoId, 'Escopo');
    return tx(() => {
      const e = um('SELECT * FROM escopos WHERE id = ?', escopoId);
      if (!e) throw naoEncontrado();
      if (e.revogado_em) return { id: escopoId, ja_revogado: true };
      exec('UPDATE escopos SET revogado_em = ? WHERE id = ?', iso(), escopoId);
      auditar(u, e.ies_id, 'escopo.revogar', 'escopo', escopoId, { usuario_id: e.usuario_id });
      return { id: escopoId };
    });
  }
  function revogarUsuario(u, usuarioId) {
    exigirMaster(u);
    usuarioId = inteiro(usuarioId, 'Usuário');
    if (usuarioId === u.id) throw invalido('Master não pode revogar a si mesmo');
    return tx(() => {
      if (!exec('UPDATE usuarios SET revogado_em = coalesce(revogado_em, ?), ativo = 0 WHERE id = ?', iso(), usuarioId).changes) throw naoEncontrado();
      exec('DELETE FROM sessoes WHERE usuario_id = ?', usuarioId);
      exec('UPDATE tarefas SET responsavel_id = NULL WHERE responsavel_id = ? AND status = ?', usuarioId, 'aberta');
      auditar(u, null, 'usuario.revogar', 'usuario', usuarioId);
      return { id: usuarioId };
    });
  }

  // ---------- estrutura / configuração ----------
  function estrutura(u, iesId) {
    iesId = inteiro(iesId, 'IES');
    const a = acesso(u, iesId, LEITURA);
    const f = filtroCursos(a, 'c.id');
    const ies = um('SELECT id, nome, plano, sla_horas, max_followups, dias_sem_contato, capacidade_atendente FROM ies WHERE id = ?', iesId);
    return {
      ies,
      papeis: [...a.papeis],
      acesso_total: a.total,
      cursos: todos(`SELECT c.id, c.nome, c.turno, c.modalidade, c.mensalidade_centavos, c.desconto_max_pct, cp.nome AS campus
        FROM cursos c JOIN campus cp ON cp.id = c.campus_id WHERE c.ies_id = ?${f.sql} ORDER BY c.nome`, iesId, ...f.params),
      coortes: todos('SELECT DISTINCT coorte FROM oportunidades WHERE ies_id = ? UNION SELECT DISTINCT coorte FROM metas WHERE ies_id = ? ORDER BY 1 DESC', iesId, iesId).map((r) => r.coorte),
      etapas: todasEtapas, formas_ingresso: FORMAS_INGRESSO, bases_legais: BASES_LEGAIS, canais: CANAIS,
    };
  }
  function configurar(u, iesId, d) {
    iesId = inteiro(iesId, 'IES');
    acesso(u, iesId, ['gestor']);
    const campos = { sla_horas: [1, 168], max_followups: [0, 10], dias_sem_contato: [1, 60], capacidade_atendente: [1, 1000] };
    const sets = []; const vals = [];
    for (const [k, [min, max]] of Object.entries(campos)) {
      if (d[k] !== undefined) { sets.push(`${k} = ?`); vals.push(inteiro(d[k], k, { min, max })); }
    }
    if (!sets.length) throw new ErroApp(400, 'Nada a alterar');
    return tx(() => {
      exec(`UPDATE ies SET ${sets.join(', ')} WHERE id = ?`, ...vals, iesId);
      auditar(u, iesId, 'ies.configurar', 'ies', iesId, d);
      return um('SELECT sla_horas, max_followups, dias_sem_contato, capacidade_atendente FROM ies WHERE id = ?', iesId);
    });
  }
  function definirMeta(u, iesId, d) {
    iesId = inteiro(iesId, 'IES');
    const cursoId = inteiro(d.curso_id, 'Curso');
    const a = acesso(u, iesId, ['gestor']);
    if (!a.permite(cursoId) || !um('SELECT 1 FROM cursos WHERE id = ? AND ies_id = ?', cursoId, iesId)) throw naoEncontrado();
    const coorte = coorteValida(d.coorte);
    const meta = inteiro(d.meta, 'Meta', { min: 0, max: 100000 });
    return tx(() => {
      exec('INSERT INTO metas(ies_id, curso_id, coorte, meta) VALUES (?,?,?,?) ON CONFLICT(ies_id, curso_id, coorte) DO UPDATE SET meta = excluded.meta', iesId, cursoId, coorte, meta);
      auditar(u, iesId, 'meta.definir', 'curso', cursoId, { coorte, meta });
      return { curso_id: cursoId, coorte, meta };
    });
  }

  // ---------- CRM ----------
  function normalizar(fn) {
    try { return fn(); } catch (e) { if (e instanceof RegraViolada) throw new ErroApp(400, e.message); throw e; }
  }

  // Distribuição por escopo e capacidade: atendente comercial ativo do curso com menor carga aberta.
  function distribuir(iesId, cursoId) {
    const cap = um('SELECT capacidade_atendente AS c FROM ies WHERE id = ?', iesId).c;
    const r = um(`SELECT u.id, (SELECT count(*) FROM tarefas t WHERE t.responsavel_id = u.id AND t.status = 'aberta') AS carga
      FROM usuarios u JOIN escopos e ON e.usuario_id = u.id
      WHERE e.ies_id = ? AND e.papel = 'comercial' AND e.revogado_em IS NULL AND u.ativo = 1 AND u.revogado_em IS NULL
        AND (e.curso_id IS NULL OR e.curso_id = ?)
      GROUP BY u.id HAVING carga < ? ORDER BY carga, u.id LIMIT 1`, iesId, cursoId, cap);
    return r?.id ?? null;
  }
  function canalPermitido(p, preferidos = ['whatsapp', 'email', 'telefone']) {
    return preferidos.find((c) => !p[`optout_${c}`] && ((c === 'email' && p.email) || (c !== 'email' && p.telefone))) ?? null;
  }
  function criarTarefa(op, tipo, { canal = null, horas, responsavel = op.responsavel_id } = {}) {
    const vence = somarHoras(horas);
    const id = Number(exec('INSERT INTO tarefas(ies_id, oportunidade_id, tipo, canal, responsavel_id, vence_em, criado_em) VALUES (?,?,?,?,?,?,?)',
      op.ies_id, op.id, tipo, canal, responsavel, vence, iso()).lastInsertRowid);
    return id;
  }

  function _criarOportunidade(u, iesId, d) {
    const cursoId = inteiro(d.curso_id, 'Curso');
    const a = acesso(u, iesId, OPERA_FUNIL);
    const curso = um('SELECT * FROM cursos WHERE id = ? AND ies_id = ?', cursoId, iesId);
    if (!curso) throw naoEncontrado();
    if (!a.permite(cursoId)) throw proibido();
    const nome = texto(d.nome, 'Nome', 2, 120);
    const email = normalizar(() => normalizarEmail(d.email));
    const telefone = normalizar(() => normalizarTelefone(d.telefone));
    if (!email && !telefone) throw new ErroApp(400, 'Informe e-mail ou telefone');
    const forma = opcao(d.forma_ingresso, FORMAS_INGRESSO, 'Forma de ingresso');
    const coorte = coorteValida(d.coorte);
    // LGPD: sem base legal e origem documentadas, não entra.
    if (d.base_legal == null || d.base_legal === '') throw invalido('Base legal obrigatória (LGPD)');
    const baseLegal = opcao(d.base_legal, BASES_LEGAIS, 'Base legal');
    const origem = texto(d.origem, 'Origem do contato', 2, 80);

    let pessoa = um('SELECT * FROM pessoas WHERE ies_id = ? AND ((email IS NOT NULL AND email = ?) OR (telefone IS NOT NULL AND telefone = ?))', iesId, email, telefone);
    let pessoaNova = false;
    if (!pessoa) {
      const pid = Number(exec('INSERT INTO pessoas(ies_id, nome, email, telefone, base_legal, origem, criado_em) VALUES (?,?,?,?,?,?,?)',
        iesId, nome, email, telefone, baseLegal, origem, iso()).lastInsertRowid);
      pessoa = um('SELECT * FROM pessoas WHERE id = ?', pid);
      pessoaNova = true;
    }
    const existente = um('SELECT id, versao, etapa FROM oportunidades WHERE pessoa_id = ? AND curso_id = ? AND coorte = ?', pessoa.id, cursoId, coorte);
    if (existente) return { id: existente.id, duplicada: true, versao: existente.versao, etapa: existente.etapa };

    const resp = distribuir(iesId, cursoId);
    const opId = Number(exec(`INSERT INTO oportunidades(ies_id, curso_id, pessoa_id, forma_ingresso, coorte, responsavel_id, criado_em, atualizado_em)
      VALUES (?,?,?,?,?,?,?,?)`, iesId, cursoId, pessoa.id, forma, coorte, resp, iso(), iso()).lastInsertRowid);
    const op = um('SELECT * FROM oportunidades WHERE id = ?', opId);
    const sla = um('SELECT sla_horas FROM ies WHERE id = ?', iesId).sla_horas;
    const canal = canalPermitido(pessoa);
    let tarefaId = null;
    if (canal) tarefaId = criarTarefa(op, 'primeiro_contato', { canal, horas: sla });
    auditar(u, iesId, 'oportunidade.criar', 'oportunidade', opId, { curso_id: cursoId, forma_ingresso: forma, coorte, origem, pessoa_nova: pessoaNova, responsavel_id: resp, tarefa_id: tarefaId });
    return { id: opId, duplicada: false, versao: 1, etapa: 'novo', responsavel_id: resp };
  }
  function criarOportunidade(u, iesId, d) {
    iesId = inteiro(iesId, 'IES');
    return tx(() => _criarOportunidade(u, iesId, d));
  }
  function importar(u, iesId, d) {
    iesId = inteiro(iesId, 'IES');
    acesso(u, iesId, OPERA_FUNIL);
    if (!Array.isArray(d.linhas) || !d.linhas.length || d.linhas.length > 500) throw new ErroApp(400, 'Envie de 1 a 500 linhas');
    return tx(() => {
      const rel = { criadas: 0, duplicadas: 0, rejeitadas: [] };
      d.linhas.forEach((l, i) => {
        try {
          if (typeof l !== 'object' || l === null || Array.isArray(l)) throw new ErroApp(400, 'Linha inválida');
          const r = tx(() => _criarOportunidade(u, iesId, l));
          r.duplicada ? rel.duplicadas++ : rel.criadas++;
        } catch (e) {
          if (!(e instanceof ErroApp)) throw e;
          rel.rejeitadas.push({ linha: i + 1, motivo: e.message });
        }
      });
      auditar(u, iesId, 'oportunidade.importar', 'ies', iesId, { criadas: rel.criadas, duplicadas: rel.duplicadas, rejeitadas: rel.rejeitadas.length });
      return rel;
    });
  }

  function pessoaVisivel(u, op, p) {
    const a = acessoOuNulo(u, op.ies_id, VE_DADOS_PESSOAIS);
    const pleno = Boolean(a && a.permite(op.curso_id));
    return {
      id: p.id, nome: p.nome,
      email: pleno ? p.email : mascararEmail(p.email),
      telefone: pleno ? p.telefone : mascararTelefone(p.telefone),
      dados_mascarados: !pleno,
      base_legal: p.base_legal, origem: p.origem,
      optout: { email: !!p.optout_email, whatsapp: !!p.optout_whatsapp, telefone: !!p.optout_telefone },
      anonimizada: Boolean(p.anonimizada_em),
    };
  }

  function listarOportunidades(u, iesId, f = {}) {
    iesId = inteiro(iesId, 'IES');
    const a = acesso(u, iesId, LEITURA);
    const pleno = acessoOuNulo(u, iesId, VE_DADOS_PESSOAIS);
    const pagina = f.pagina == null ? 1 : inteiro(f.pagina, 'Página');
    const porPagina = f.por_pagina == null ? 25 : inteiro(f.por_pagina, 'Itens por página', { max: 100 });
    const cond = ['o.ies_id = ?']; const ps = [iesId];
    if (f.etapa) { cond.push('o.etapa = ?'); ps.push(opcao(f.etapa, todasEtapas, 'Etapa')); }
    if (f.coorte) { cond.push('o.coorte = ?'); ps.push(coorteValida(f.coorte)); }
    if (f.curso_id) { cond.push('o.curso_id = ?'); ps.push(inteiro(f.curso_id, 'Curso')); }
    if (f.responsavel === 'eu') { cond.push('o.responsavel_id = ?'); ps.push(u.id); }
    const fc = filtroCursos(a);
    const where = cond.join(' AND ') + fc.sql; ps.push(...fc.params);
    const total = um(`SELECT count(*) AS n FROM oportunidades o WHERE ${where}`, ...ps).n;
    const itens = todos(`SELECT o.id, o.etapa, o.versao, o.coorte, o.forma_ingresso, o.curso_id, c.nome AS curso, c.turno,
        o.val_documental, o.val_financeira, o.val_academica, o.atualizado_em, o.responsavel_id, r.nome AS responsavel,
        p.nome, p.email, p.telefone
      FROM oportunidades o JOIN cursos c ON c.id = o.curso_id JOIN pessoas p ON p.id = o.pessoa_id LEFT JOIN usuarios r ON r.id = o.responsavel_id
      WHERE ${where} ORDER BY o.atualizado_em DESC, o.id DESC LIMIT ? OFFSET ?`, ...ps, porPagina, (pagina - 1) * porPagina)
      .map((o) => {
        const ve = Boolean(pleno && pleno.permite(o.curso_id));
        return { ...o, email: ve ? o.email : mascararEmail(o.email), telefone: ve ? o.telefone : mascararTelefone(o.telefone), dados_mascarados: !ve };
      });
    return { itens, total, pagina, por_pagina: porPagina };
  }

  function detalhe(u, id) {
    const op = carregarOportunidade(u, id, LEITURA);
    const p = um('SELECT * FROM pessoas WHERE id = ?', op.pessoa_id);
    const curso = um('SELECT id, nome, turno, modalidade, mensalidade_centavos, desconto_max_pct FROM cursos WHERE id = ?', op.curso_id);
    return {
      oportunidade: { ...op, responsavel: um('SELECT nome FROM usuarios WHERE id = ?', op.responsavel_id)?.nome ?? null },
      curso,
      pessoa: pessoaVisivel(u, op, p),
      transicoes: todasEtapas.filter((e) => podeTransitar(op.etapa, e)),
      validacoes: todos('SELECT v.id, v.dimensao, v.resultado, v.evidencia, v.em, u.nome AS por FROM validacoes v JOIN usuarios u ON u.id = v.usuario_id WHERE v.oportunidade_id = ? ORDER BY v.id', op.id),
      propostas: todos('SELECT id, desconto_pct, mensalidade_centavos, valor_final_centavos, validade, status, criado_por, decidido_por, criado_em FROM propostas WHERE oportunidade_id = ? ORDER BY id DESC', op.id),
      tarefas: todos('SELECT id, tipo, canal, status, vence_em, responsavel_id, resultado FROM tarefas WHERE oportunidade_id = ? ORDER BY id DESC', op.id),
      historico: todos(`SELECT a.id, a.acao, a.dados, a.em, u.nome AS por FROM auditoria a LEFT JOIN usuarios u ON u.id = a.usuario_id
        WHERE a.entidade = 'oportunidade' AND a.entidade_id = ? ORDER BY a.id`, String(op.id)).map((h) => ({ ...h, dados: JSON.parse(h.dados) })),
    };
  }

  function atualizarComVersao(op, versaoEsperada, sets, vals) {
    const r = exec(`UPDATE oportunidades SET ${sets}, versao = versao + 1, atualizado_em = ? WHERE id = ? AND versao = ?`,
      ...vals, iso(), op.id, versaoEsperada);
    if (r.changes === 0) {
      const atual = um('SELECT versao FROM oportunidades WHERE id = ?', op.id);
      throw new ErroApp(409, 'Conflito de versão: o registro foi alterado por outra operação. Recarregue e tente novamente.', { versao_atual: atual.versao });
    }
    return versaoEsperada + 1;
  }
  const versao = (d) => inteiro(d.versao_esperada, 'versao_esperada');

  function moverEtapa(u, id, d) {
    const v = versao(d);
    const para = opcao(d.para, todasEtapas, 'Etapa de destino');
    return tx(() => {
      const op = carregarOportunidade(u, id, OPERA_FUNIL);
      if (para === 'confirmado') throw invalido('Ingresso efetivo só pela confirmação de matrícula');
      if (para === 'cancelado') throw invalido('Cancelamento só pela operação de cancelamento');
      if (!podeTransitar(op.etapa, para)) throw invalido(`Transição inválida: ${op.etapa} → ${para}`);
      let motivo = null;
      if (para === 'perdido') motivo = texto(d.motivo, 'Motivo da perda', 3, 200);
      const nova = atualizarComVersao(op, v,
        `etapa = ?, motivo_perda = ?${para === 'matricula_comercial' ? ', matricula_comercial_em = ?' : ''}`,
        para === 'matricula_comercial' ? [para, motivo, iso()] : [para, motivo]);
      if (para === 'perdido') {
        exec("UPDATE tarefas SET status = 'cancelada', encerrada_em = ?, resultado = 'oportunidade perdida' WHERE oportunidade_id = ? AND status = 'aberta'", iso(), op.id);
      }
      if (op.etapa === 'perdido' && para === 'contato') {
        const p = um('SELECT * FROM pessoas WHERE id = ?', op.pessoa_id);
        const canal = canalPermitido(p);
        if (canal) criarTarefa({ ...op, responsavel_id: op.responsavel_id ?? distribuir(op.ies_id, op.curso_id) }, 'recuperacao', { canal, horas: 24 });
      }
      auditar(u, op.ies_id, 'oportunidade.etapa', 'oportunidade', op.id, { de: op.etapa, para, motivo, versao: nova });
      return { id: op.id, etapa: para, versao: nova };
    });
  }

  function validar(u, id, d) {
    const v = versao(d);
    const dimensao = opcao(d.dimensao, DIMENSOES, 'Dimensão');
    const resultado = opcao(d.resultado, ['valida', 'invalida', 'isencao_formal'], 'Resultado');
    if (resultado === 'isencao_formal' && dimensao !== 'financeira') throw invalido('Isenção formal só se aplica à dimensão financeira');
    const evidencia = texto(d.evidencia, 'Evidência', 5, 500);
    // Segregação: secretaria valida documental e acadêmica; financeiro valida financeira. Comercial não valida.
    const papel = dimensao === 'financeira' ? 'financeiro' : 'secretaria';
    return tx(() => {
      const op = carregarOportunidade(u, id, [papel]);
      if (op.etapa !== 'matricula_comercial') throw invalido('Validações só após a matrícula comercial e antes da confirmação');
      exec('INSERT INTO validacoes(oportunidade_id, dimensao, resultado, evidencia, usuario_id, em) VALUES (?,?,?,?,?,?)', op.id, dimensao, resultado, evidencia, u.id, iso());
      const nova = atualizarComVersao(op, v, `val_${dimensao} = ?`, [resultado === 'invalida' ? 0 : 1]);
      auditar(u, op.ies_id, 'oportunidade.validar', 'oportunidade', op.id, { dimensao, resultado, versao: nova });
      return { id: op.id, dimensao, resultado, versao: nova };
    });
  }

  function confirmar(u, id, d) {
    const v = versao(d);
    return tx(() => {
      const op = carregarOportunidade(u, id, ['secretaria', 'gestor']);
      try {
        confirm({ stage: op.etapa, documental: op.val_documental === 1, financeira: op.val_financeira === 1, academica: op.val_academica === 1 });
      } catch (e) { if (e instanceof RegraViolada) throw invalido(e.message); throw e; }
      const nova = atualizarComVersao(op, v, 'etapa = ?, confirmada_em = ?', ['confirmado', iso()]);
      exec("UPDATE tarefas SET status = 'cancelada', encerrada_em = ?, resultado = 'ingresso confirmado' WHERE oportunidade_id = ? AND status = 'aberta'", iso(), op.id);
      auditar(u, op.ies_id, 'oportunidade.confirmar', 'oportunidade', op.id, { versao: nova });
      return { id: op.id, etapa: 'confirmado', versao: nova };
    });
  }

  function cancelar(u, id, d) {
    const v = versao(d);
    const motivo = texto(d.motivo, 'Motivo do cancelamento', 3, 200);
    return tx(() => {
      const op = carregarOportunidade(u, id, ['secretaria', 'gestor']);
      if (!['matricula_comercial', 'confirmado'].includes(op.etapa)) throw invalido('Só é possível cancelar matrícula comercial ou ingresso confirmado');
      const nova = atualizarComVersao(op, v, 'etapa = ?, cancelada_em = ?, motivo_cancelamento = ?', ['cancelado', iso(), motivo]);
      exec("UPDATE tarefas SET status = 'cancelada', encerrada_em = ?, resultado = 'matrícula cancelada' WHERE oportunidade_id = ? AND status = 'aberta'", iso(), op.id);
      auditar(u, op.ies_id, 'oportunidade.cancelar', 'oportunidade', op.id, { de: op.etapa, motivo, versao: nova });
      return { id: op.id, etapa: 'cancelado', versao: nova };
    });
  }

  // ---------- propostas ----------
  function criarProposta(u, id, d) {
    const validadeDias = d.validade_dias == null ? 7 : inteiro(d.validade_dias, 'Validade (dias)', { min: 1, max: 30 });
    if (typeof d.desconto_pct !== 'number') throw new ErroApp(400, 'Desconto obrigatório');
    return tx(() => {
      const op = carregarOportunidade(u, id, OPERA_FUNIL);
      if (!['inscrito', 'pre_matricula', 'matricula_comercial'].includes(op.etapa)) throw invalido('Proposta só para inscrito, pré-matrícula ou matrícula comercial');
      const c = um('SELECT mensalidade_centavos, desconto_max_pct FROM cursos WHERE id = ?', op.curso_id);
      let calc;
      try { calc = calcularProposta({ mensalidadeCentavos: c.mensalidade_centavos, descontoPct: d.desconto_pct, descontoMaxPct: c.desconto_max_pct }); }
      catch (e) { if (e instanceof RegraViolada) throw invalido(e.message); throw e; }
      const status = calc.exigeAprovacao ? 'pendente_aprovacao' : 'aprovada';
      const pid = Number(exec(`INSERT INTO propostas(ies_id, oportunidade_id, mensalidade_centavos, desconto_pct, valor_final_centavos, validade, status, criado_por, criado_em)
        VALUES (?,?,?,?,?,?,?,?,?)`, op.ies_id, op.id, calc.mensalidadeCentavos, calc.descontoPct, calc.valorFinalCentavos, somarHoras(validadeDias * 24), status, u.id, iso()).lastInsertRowid);
      auditar(u, op.ies_id, 'proposta.criar', 'oportunidade', op.id, { proposta_id: pid, desconto_pct: calc.descontoPct, limite_pct: c.desconto_max_pct, status });
      return { id: pid, status, ...calc, limite_pct: c.desconto_max_pct };
    });
  }
  function carregarProposta(u, pid, papeis) {
    pid = inteiro(pid, 'Proposta');
    const p = um('SELECT * FROM propostas WHERE id = ?', pid);
    if (!p) throw naoEncontrado();
    const op = carregarOportunidade(u, p.oportunidade_id, papeis);
    return { p, op };
  }
  function decidirProposta(u, pid, d) {
    const decisao = opcao(d.decisao, ['aprovar', 'rejeitar'], 'Decisão');
    return tx(() => {
      const { p, op } = carregarProposta(u, pid, ['gestor']);
      if (p.criado_por === u.id) throw proibido('Segregação de funções: quem criou a proposta não pode decidi-la');
      if (p.status !== 'pendente_aprovacao') throw invalido('Proposta não está pendente de aprovação');
      if (p.validade < iso()) {
        exec("UPDATE propostas SET status = 'expirada' WHERE id = ?", p.id);
        auditar(u, op.ies_id, 'proposta.expirar', 'oportunidade', op.id, { proposta_id: p.id });
        return { id: p.id, status: 'expirada' };
      }
      const status = decisao === 'aprovar' ? 'aprovada' : 'rejeitada';
      const r = exec("UPDATE propostas SET status = ?, decidido_por = ?, decidido_em = ? WHERE id = ? AND status = 'pendente_aprovacao'", status, u.id, iso(), p.id);
      if (!r.changes) throw new ErroApp(409, 'Proposta já decidida');
      auditar(u, op.ies_id, 'proposta.decidir', 'oportunidade', op.id, { proposta_id: p.id, status });
      return { id: p.id, status };
    });
  }
  function aceitarProposta(u, pid) {
    return tx(() => {
      const { p, op } = carregarProposta(u, pid, OPERA_FUNIL);
      if (p.status !== 'aprovada') throw invalido('Só propostas aprovadas podem ser aceitas');
      if (p.validade < iso()) {
        exec("UPDATE propostas SET status = 'expirada' WHERE id = ?", p.id);
        auditar(u, op.ies_id, 'proposta.expirar', 'oportunidade', op.id, { proposta_id: p.id });
        return { id: p.id, status: 'expirada' };
      }
      exec("UPDATE propostas SET status = 'aceita' WHERE id = ?", p.id);
      auditar(u, op.ies_id, 'proposta.aceitar', 'oportunidade', op.id, { proposta_id: p.id });
      return { id: p.id, status: 'aceita' };
    });
  }
  function listarPropostas(u, iesId, f = {}) {
    iesId = inteiro(iesId, 'IES');
    const a = acesso(u, iesId, ['gestor', 'comercial']);
    const fc = filtroCursos(a);
    const status = f.status ? opcao(f.status, ['pendente_aprovacao', 'aprovada', 'rejeitada', 'aceita', 'expirada'], 'Status') : 'pendente_aprovacao';
    return todos(`SELECT pr.id, pr.oportunidade_id, pr.desconto_pct, pr.valor_final_centavos, pr.mensalidade_centavos, pr.validade, pr.status,
        pr.criado_por, cr.nome AS criado_por_nome, c.nome AS curso, c.desconto_max_pct, p.nome
      FROM propostas pr JOIN oportunidades o ON o.id = pr.oportunidade_id JOIN cursos c ON c.id = o.curso_id
      JOIN pessoas p ON p.id = o.pessoa_id JOIN usuarios cr ON cr.id = pr.criado_por
      WHERE pr.ies_id = ? AND pr.status = ?${fc.sql} ORDER BY pr.id DESC LIMIT 200`, iesId, status, ...fc.params);
  }

  // ---------- LGPD ----------
  function optOut(u, id, d) {
    const canal = opcao(d.canal, CANAIS, 'Canal');
    return tx(() => {
      const op = carregarOportunidade(u, id, ['comercial', 'gestor', 'secretaria']);
      exec(`UPDATE pessoas SET optout_${canal} = 1 WHERE id = ?`, op.pessoa_id);
      const r = exec("UPDATE tarefas SET status = 'suprimida', encerrada_em = ?, resultado = ? WHERE status = 'aberta' AND canal = ? AND oportunidade_id IN (SELECT id FROM oportunidades WHERE pessoa_id = ?)",
        iso(), `opt-out ${canal}`, canal, op.pessoa_id);
      auditar(u, op.ies_id, 'pessoa.optout', 'oportunidade', op.id, { canal, tarefas_suprimidas: Number(r.changes) });
      return { canal, tarefas_suprimidas: Number(r.changes) };
    });
  }
  function anonimizar(u, id) {
    return tx(() => {
      const op = carregarOportunidade(u, id, ['gestor']);
      exec(`UPDATE pessoas SET nome = 'Titular anonimizado', email = NULL, telefone = NULL, optout_email = 1, optout_whatsapp = 1, optout_telefone = 1, anonimizada_em = ? WHERE id = ?`, iso(), op.pessoa_id);
      exec("UPDATE tarefas SET status = 'cancelada', encerrada_em = ?, resultado = 'titular anonimizado' WHERE status = 'aberta' AND oportunidade_id IN (SELECT id FROM oportunidades WHERE pessoa_id = ?)", iso(), op.pessoa_id);
      auditar(u, op.ies_id, 'pessoa.anonimizar', 'oportunidade', op.id, {});
      return { anonimizada: true };
    });
  }

  // ---------- MAIM (motor de acompanhamento interno; envio externo DESLIGADO) ----------
  function fila(u, iesId) {
    iesId = inteiro(iesId, 'IES');
    const a = acesso(u, iesId, ['gestor', 'comercial', 'secretaria', 'financeiro']);
    const fc = filtroCursos(a);
    const soMinhas = !a.papeis.has('gestor') && a.papeis.has('comercial') && !a.papeis.has('secretaria') && !a.papeis.has('financeiro');
    const tarefas = todos(`SELECT t.id, t.tipo, t.canal, t.vence_em, t.status, t.oportunidade_id, t.responsavel_id, r.nome AS responsavel,
        o.etapa, c.nome AS curso, p.nome, (t.vence_em < ?) AS atrasada
      FROM tarefas t JOIN oportunidades o ON o.id = t.oportunidade_id JOIN cursos c ON c.id = o.curso_id JOIN pessoas p ON p.id = o.pessoa_id
      LEFT JOIN usuarios r ON r.id = t.responsavel_id
      WHERE t.ies_id = ? AND t.status = 'aberta'${soMinhas ? ' AND t.responsavel_id = ?' : ''}${fc.sql}
      ORDER BY t.vence_em LIMIT 200`, iso(), iesId, ...(soMinhas ? [u.id] : []), ...fc.params);
    return { tarefas: tarefas.map((t) => ({ ...t, atrasada: t.atrasada === 1 })), envio_externo: 'desativado' };
  }
  function cicloMaim(u, iesId) {
    iesId = inteiro(iesId, 'IES');
    acesso(u, iesId, ['gestor']);
    return tx(() => {
      const cfg = um('SELECT * FROM ies WHERE id = ?', iesId);
      const limite = new Date(agora().getTime() - cfg.dias_sem_contato * 86400e3).toISOString();
      const rel = { follow_ups: 0, suprimidos_optout: 0, limite_atingido: 0, pendencias_validacao: 0, sem_responsavel_redistribuidas: 0, atrasadas: 0 };
      const candidatas = todos(`SELECT o.* FROM oportunidades o WHERE o.ies_id = ? AND o.etapa IN ('contato','inscrito','pre_matricula')
        AND o.atualizado_em < ? AND NOT EXISTS (SELECT 1 FROM tarefas t WHERE t.oportunidade_id = o.id AND t.status = 'aberta')`, iesId, limite);
      for (const op of candidatas) {
        const feitos = um("SELECT count(*) AS n FROM tarefas WHERE oportunidade_id = ? AND tipo = 'follow_up'", op.id).n;
        if (feitos >= cfg.max_followups) { rel.limite_atingido++; continue; }
        const p = um('SELECT * FROM pessoas WHERE id = ?', op.pessoa_id);
        const canal = canalPermitido(p);
        if (!canal) { rel.suprimidos_optout++; continue; }
        criarTarefa({ ...op, responsavel_id: op.responsavel_id ?? distribuir(iesId, op.curso_id) }, 'follow_up', { canal, horas: 24 });
        rel.follow_ups++;
      }
      const pend = todos(`SELECT o.* FROM oportunidades o WHERE o.ies_id = ? AND o.etapa = 'matricula_comercial'
        AND (o.val_documental = 0 OR o.val_financeira = 0 OR o.val_academica = 0)
        AND NOT EXISTS (SELECT 1 FROM tarefas t WHERE t.oportunidade_id = o.id AND t.status = 'aberta' AND t.tipo = 'pendencia_validacao')`, iesId);
      for (const op of pend) { criarTarefa({ ...op, responsavel_id: null }, 'pendencia_validacao', { horas: 48 }); rel.pendencias_validacao++; }
      const orfas = todos(`SELECT t.id, o.curso_id FROM tarefas t JOIN oportunidades o ON o.id = t.oportunidade_id
        WHERE t.ies_id = ? AND t.status = 'aberta' AND t.responsavel_id IS NULL AND t.tipo <> 'pendencia_validacao'`, iesId);
      for (const t of orfas) {
        const r = distribuir(iesId, t.curso_id);
        if (r) { exec('UPDATE tarefas SET responsavel_id = ? WHERE id = ?', r, t.id); rel.sem_responsavel_redistribuidas++; }
      }
      rel.atrasadas = um("SELECT count(*) AS n FROM tarefas WHERE ies_id = ? AND status = 'aberta' AND vence_em < ?", iesId, iso()).n;
      auditar(u, iesId, 'maim.ciclo', 'ies', iesId, rel);
      return rel;
    });
  }
  function carregarTarefa(u, tid) {
    tid = inteiro(tid, 'Tarefa');
    const t = um('SELECT * FROM tarefas WHERE id = ?', tid);
    if (!t) throw naoEncontrado();
    const papeis = t.tipo === 'pendencia_validacao' ? ['gestor', 'secretaria', 'financeiro'] : ['gestor', 'comercial'];
    const op = carregarOportunidade(u, t.oportunidade_id, papeis);
    const gestor = acessoOuNulo(u, op.ies_id, ['gestor']);
    if (t.tipo !== 'pendencia_validacao' && !gestor && t.responsavel_id !== u.id) throw proibido('Tarefa atribuída a outro atendente');
    return { t, op };
  }
  // Revalidação na execução: etapa encerrada ou opt-out suprimem a tarefa.
  function revalidar(t, op) {
    if (['perdido', 'cancelado', 'confirmado'].includes(op.etapa)) return { status: 'cancelada', motivo: 'etapa encerrada' };
    if (t.canal) {
      const p = um('SELECT * FROM pessoas WHERE id = ?', op.pessoa_id);
      if (p[`optout_${t.canal}`] || p.anonimizada_em) return { status: 'suprimida', motivo: `opt-out ${t.canal}` };
    }
    return null;
  }
  function concluirTarefa(u, tid, d) {
    const resultado = texto(d.resultado, 'Resultado do contato', 3, 300);
    return tx(() => {
      const { t, op } = carregarTarefa(u, tid);
      if (t.status !== 'aberta') throw invalido('Tarefa já encerrada');
      const bloqueio = revalidar(t, op);
      const status = bloqueio ? bloqueio.status : 'concluida';
      exec('UPDATE tarefas SET status = ?, resultado = ?, encerrada_em = ? WHERE id = ? AND status = ?', status, bloqueio ? bloqueio.motivo : resultado, iso(), t.id, 'aberta');
      auditar(u, op.ies_id, `tarefa.${status}`, 'oportunidade', op.id, { tarefa_id: t.id, tipo: t.tipo, canal: t.canal });
      return { id: t.id, status, motivo: bloqueio?.motivo ?? null };
    });
  }
  function dispararTarefa(u, tid) {
    return tx(() => {
      const { t, op } = carregarTarefa(u, tid);
      const bloqueio = revalidar(t, op);
      // Envio externo permanece desligado no piloto. Nada sai do servidor.
      auditar(u, op.ies_id, 'envio_externo.bloqueado', 'oportunidade', op.id, { tarefa_id: t.id, canal: t.canal, revalidacao: bloqueio?.motivo ?? 'elegivel' });
      return { enviado: false, motivo: 'Envio externo desativado no piloto', elegivel: !bloqueio };
    });
  }
  function pendencias(u, iesId) {
    iesId = inteiro(iesId, 'IES');
    const a = acesso(u, iesId, LEITURA);
    const fc = filtroCursos(a);
    return todos(`SELECT o.id, o.versao, o.etapa, o.val_documental, o.val_financeira, o.val_academica, o.coorte, o.matricula_comercial_em,
        o.confirmada_em, o.cancelada_em, c.nome AS curso, p.nome
      FROM oportunidades o JOIN cursos c ON c.id = o.curso_id JOIN pessoas p ON p.id = o.pessoa_id
      WHERE o.ies_id = ? AND o.etapa IN ('matricula_comercial','confirmado','cancelado')${fc.sql}
      ORDER BY o.etapa = 'matricula_comercial' DESC, o.atualizado_em DESC LIMIT 200`, iesId, ...fc.params);
  }

  // ---------- BI ----------
  // Indisponível (null) é diferente de zero. Denominador = oportunidades da coorte.
  // Ingressantes contam PESSOAS distintas (sem dupla contagem no consolidado).
  function bi(u, iesId, f = {}) {
    iesId = inteiro(iesId, 'IES');
    const a = acesso(u, iesId, LEITURA);
    const coorte = coorteValida(f.coorte);
    const dims = {
      curso: "c.nome || ' · ' || c.turno",
      turno: 'c.turno',
      modalidade: 'c.modalidade',
      forma_ingresso: 'o.forma_ingresso',
      atendente: "coalesce(r.nome, 'Sem responsável')",
    };
    const agrupar = f.agrupar ? opcao(f.agrupar, Object.keys(dims), 'Agrupamento') : 'curso';
    const fc = filtroCursos(a);
    const base = `FROM oportunidades o JOIN cursos c ON c.id = o.curso_id LEFT JOIN usuarios r ON r.id = o.responsavel_id
      WHERE o.ies_id = ? AND o.coorte = ?${fc.sql}`;
    const cols = `count(*) AS oportunidades,
      sum(o.matricula_comercial_em IS NOT NULL) AS matriculas_comerciais,
      count(DISTINCT CASE WHEN o.etapa = 'confirmado' THEN o.pessoa_id END) AS ingressantes,
      sum(o.etapa = 'cancelado') AS cancelamentos,
      sum(o.etapa = 'perdido') AS perdidos`;
    const enriquecer = (r, meta) => ({
      ...r,
      matriculas_comerciais: r.matriculas_comerciais ?? 0,
      cancelamentos: r.cancelamentos ?? 0,
      perdidos: r.perdidos ?? 0,
      conversao: taxa(r.ingressantes, r.oportunidades),
      meta,
      atingimento: meta == null || meta === 0 ? null : r.ingressantes / meta,
    });
    const fm = filtroCursos(a, 'm.curso_id');
    const metaTotal = um(`SELECT count(*) AS n, sum(m.meta) AS s FROM metas m WHERE m.ies_id = ? AND m.coorte = ?${fm.sql}`, iesId, coorte, ...fm.params);
    const metasPorCurso = new Map(todos(`SELECT m.curso_id, m.meta FROM metas m WHERE m.ies_id = ? AND m.coorte = ?${fm.sql}`, iesId, coorte, ...fm.params).map((m) => [m.curso_id, m.meta]));
    const linhas = todos(`SELECT ${dims[agrupar]} AS chave, ${agrupar === 'curso' ? 'o.curso_id' : 'NULL'} AS curso_id, ${cols} ${base} GROUP BY chave ORDER BY chave`, iesId, coorte, ...fc.params)
      .map((r) => enriquecer(r, agrupar === 'curso' ? (metasPorCurso.get(r.curso_id) ?? null) : null));
    const tot = enriquecer(um(`SELECT ${cols} ${base}`, iesId, coorte, ...fc.params), metaTotal.n ? metaTotal.s : null);
    const faltam = tot.meta == null ? null : Math.max(tot.meta - tot.ingressantes, 0);
    tot.projecao_oportunidades_necessarias = faltam == null || !tot.conversao ? null : Math.ceil(faltam / tot.conversao);
    return { coorte, agrupar, totais: tot, linhas, cobertura: a.total ? 'ies' : 'cursos_autorizados' };
  }

  function auditoria(u, iesId, f = {}) {
    iesId = inteiro(iesId, 'IES');
    acesso(u, iesId, ['gestor']);
    const pagina = f.pagina == null ? 1 : inteiro(f.pagina, 'Página');
    const total = um('SELECT count(*) AS n FROM auditoria WHERE ies_id = ?', iesId).n;
    const itens = todos(`SELECT a.id, a.acao, a.entidade, a.entidade_id, a.dados, a.em, u.nome AS por FROM auditoria a LEFT JOIN usuarios u ON u.id = a.usuario_id
      WHERE a.ies_id = ? ORDER BY a.id DESC LIMIT 50 OFFSET ?`, iesId, (pagina - 1) * 50).map((x) => ({ ...x, dados: JSON.parse(x.dados) }));
    return { itens, total, pagina, por_pagina: 50 };
  }

  return {
    tx, login, logout, usuarioDaSessao, eu, acessoOuNulo: (u, i, p) => acessoOuNulo(u, i, p ?? LEITURA),
    provisionarIes, listarIesMaster, alterarStatusIes, acessosIes, concederEscopo, revogarEscopo, revogarUsuario,
    estrutura, configurar, definirMeta,
    criarOportunidade, importar, listarOportunidades, detalhe, moverEtapa, validar, confirmar, cancelar,
    criarProposta, decidirProposta, aceitarProposta, listarPropostas,
    optOut, anonimizar, fila, cicloMaim, concluirTarefa, dispararTarefa, pendencias, bi, auditoria,
    _db: db,
  };
}
