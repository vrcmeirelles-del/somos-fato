// Semente de dados 100% SINTÉTICOS para o piloto local.
// Nomes, e-mails e telefones são fictícios (domínio .invalid / prefixo 0000).
import { gerarHash } from './senha.mjs';

export const SENHA_PADRAO_PILOTO = 'piloto-local-2026';

export const USUARIOS_PILOTO = [
  // [email, nome, ies, curso(índice) | null, papel]
  ['gestor.alfa@piloto.invalid', 'Gestora Alfa', 'alfa', null, 'gestor'],
  ['reitoria.alfa@piloto.invalid', 'Reitoria Alfa', 'alfa', null, 'reitoria'],
  ['coord.direito.alfa@piloto.invalid', 'Coordenação Direito Alfa', 'alfa', 0, 'coordenador'],
  ['comercial1.alfa@piloto.invalid', 'Atendente Alfa 1', 'alfa', null, 'comercial'],
  ['comercial2.alfa@piloto.invalid', 'Atendente Alfa 2 (só Direito)', 'alfa', 0, 'comercial'],
  ['secretaria.alfa@piloto.invalid', 'Secretaria Alfa', 'alfa', null, 'secretaria'],
  ['financeiro.alfa@piloto.invalid', 'Financeiro Alfa', 'alfa', null, 'financeiro'],
  ['gestor.beta@piloto.invalid', 'Gestor Beta', 'beta', null, 'gestor'],
  ['comercial.beta@piloto.invalid', 'Atendente Beta', 'beta', null, 'comercial'],
  ['secretaria.beta@piloto.invalid', 'Secretaria Beta', 'beta', null, 'secretaria'],
  ['financeiro.beta@piloto.invalid', 'Financeiro Beta', 'beta', null, 'financeiro'],
  ['revogado.alfa@piloto.invalid', 'Usuário Revogado', 'alfa', null, 'comercial'],
];

const NOMES = ['Ana', 'Bruno', 'Carla', 'Diego', 'Elisa', 'Fábio', 'Gabriela', 'Heitor', 'Íris', 'João', 'Karina', 'Lucas', 'Marina', 'Nuno', 'Olívia', 'Paulo', 'Quésia', 'Rafael', 'Sofia', 'Tiago', 'Úrsula', 'Vítor', 'Wanda', 'Xavier', 'Yara', 'Zeca'];
const SOBRENOMES = ['Fictício', 'Sintético', 'Exemplo', 'Teste', 'Modelo', 'Demonstração'];

export function semear(db, servico, { senha = SENHA_PADRAO_PILOTO } = {}) {
  const agora = new Date().toISOString();
  const masterId = Number(db.prepare('INSERT INTO usuarios(email, nome, senha_hash, master, criado_em) VALUES (?,?,?,1,?)')
    .run('master@piloto.invalid', 'Master da Plataforma', gerarHash(senha), agora).lastInsertRowid);
  const master = { id: masterId, master: 1 };

  const alfa = servico.provisionarIes(master, {
    nome: 'Faculdade Alfa (fictícia)', plano: 'piloto',
    campus: [{ nome: 'Campus Centro', cursos: [
      { nome: 'Direito', turno: 'noturno', modalidade: 'presencial', mensalidade_centavos: 129000, desconto_max_pct: 30 },
      { nome: 'Administração', turno: 'ead', modalidade: 'ead', mensalidade_centavos: 39900, desconto_max_pct: 40 },
    ] }],
  }).id;
  const beta = servico.provisionarIes(master, {
    nome: 'Centro Universitário Beta (fictício)', plano: 'piloto',
    campus: [{ nome: 'Campus Norte', cursos: [
      { nome: 'Psicologia', turno: 'matutino', modalidade: 'presencial', mensalidade_centavos: 115000, desconto_max_pct: 25 },
      { nome: 'Enfermagem', turno: 'noturno', modalidade: 'presencial', mensalidade_centavos: 98000, desconto_max_pct: 25 },
    ] }],
  }).id;
  const iesIds = { alfa, beta };
  const cursos = {
    alfa: db.prepare('SELECT id FROM cursos WHERE ies_id = ? ORDER BY id').all(alfa).map((c) => c.id),
    beta: db.prepare('SELECT id FROM cursos WHERE ies_id = ? ORDER BY id').all(beta).map((c) => c.id),
  };

  const ids = { master: masterId };
  const hash = gerarHash(senha);
  for (const [email, nome, ies, ci, papel] of USUARIOS_PILOTO) {
    let u = db.prepare('SELECT id FROM usuarios WHERE email = ?').get(email);
    if (!u) {
      u = { id: Number(db.prepare('INSERT INTO usuarios(email, nome, senha_hash, criado_em) VALUES (?,?,?,?)').run(email, nome, hash, agora).lastInsertRowid) };
    }
    servico.concederEscopo(master, { email, nome, ies_id: iesIds[ies], curso_id: ci == null ? null : cursos[ies][ci], papel });
    ids[email.split('@')[0]] = u.id;
  }
  servico.revogarUsuario(master, ids['revogado.alfa']);

  const usr = (k) => ({ id: ids[k], master: 0 });
  // Oportunidades sintéticas distribuídas pelo funil.
  const gerar = (ies, comercial, sec, fin, gestor, n, coorte) => {
    const planos = ['novo', 'contato', 'inscrito', 'pre_matricula', 'matricula_comercial', 'confirmado', 'perdido'];
    for (let i = 0; i < n; i++) {
      const nome = `${NOMES[i % NOMES.length]} ${SOBRENOMES[(i + coorte.length) % SOBRENOMES.length]}`;
      const cursoId = cursos[ies][i % 2];
      const r = servico.criarOportunidade(usr(comercial), iesIds[ies], {
        nome, email: `cand${i}.${ies}.${coorte.replace('.', '')}@exemplo.invalid`, telefone: `0000${String(ies === 'alfa' ? 1 : 2)}${coorte.slice(2, 4)}${String(i).padStart(4, '0')}`.padEnd(11, '0'),
        curso_id: cursoId, forma_ingresso: ['vestibular', 'enem', 'transferencia', 'segunda_graduacao', 'indicacao'][i % 5],
        coorte, base_legal: i % 3 ? 'consentimento' : 'procedimentos_preliminares_contrato', origem: ['site', 'evento escolar', 'indicação'][i % 3],
      });
      const alvo = planos[i % planos.length];
      let v = r.versao;
      const passo = (para, extra = {}) => { v = servico.moverEtapa(usr(comercial), r.id, { para, versao_esperada: v, ...extra }).versao; };
      const caminho = ['contato', 'inscrito', 'pre_matricula', 'matricula_comercial'];
      if (alvo === 'perdido') { passo('contato'); passo('perdido', { motivo: 'Optou por outra instituição' }); continue; }
      for (const e of caminho) { if (planos.indexOf(alvo) < planos.indexOf(e)) break; passo(e); }
      if (alvo === 'inscrito' || alvo === 'pre_matricula') servico.criarProposta(usr(comercial), r.id, { desconto_pct: i % 4 === 0 ? 45 : 20, validade_dias: 7 });
      if (alvo === 'confirmado' || (alvo === 'matricula_comercial' && i % 2 === 0)) {
        v = servico.validar(usr(sec), r.id, { dimensao: 'documental', resultado: 'valida', evidencia: 'RG, histórico e comprovante conferidos (sintético)', versao_esperada: v }).versao;
        v = servico.validar(usr(fin), r.id, { dimensao: 'financeira', resultado: i % 5 === 0 ? 'isencao_formal' : 'valida', evidencia: 'Primeira mensalidade conciliada (sintético)', versao_esperada: v }).versao;
      }
      if (alvo === 'confirmado') {
        v = servico.validar(usr(sec), r.id, { dimensao: 'academica', resultado: 'valida', evidencia: 'Requisitos de ingresso atendidos (sintético)', versao_esperada: v }).versao;
        servico.confirmar(usr(sec), r.id, { versao_esperada: v });
      }
    }
  };
  gerar('alfa', 'comercial1.alfa', 'secretaria.alfa', 'financeiro.alfa', 'gestor.alfa', 28, '2027.1');
  gerar('alfa', 'comercial1.alfa', 'secretaria.alfa', 'financeiro.alfa', 'gestor.alfa', 14, '2026.2');
  gerar('beta', 'comercial.beta', 'secretaria.beta', 'financeiro.beta', 'gestor.beta', 16, '2027.1');

  for (const [ies, gestor, metas] of [['alfa', 'gestor.alfa', [12, 8]], ['beta', 'gestor.beta', [6, 5]]]) {
    cursos[ies].forEach((c, i) => servico.definirMeta(usr(gestor), iesIds[ies], { curso_id: c, coorte: '2027.1', meta: metas[i] }));
  }
  return { ids, iesIds, cursos };
}
