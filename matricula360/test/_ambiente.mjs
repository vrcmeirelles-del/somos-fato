import { abrirBanco } from '../src/db.mjs';
import { criarServico } from '../src/servico.mjs';
import { semear, SENHA_PADRAO_PILOTO } from '../src/semente.mjs';

export const SENHA = SENHA_PADRAO_PILOTO;

export function ambiente() {
  const relogio = { agora: new Date() };
  const db = abrirBanco(':memory:');
  const s = criarServico(db, { agora: () => relogio.agora });
  const sem = semear(db, s);
  const u = (k) => ({ id: sem.ids[k], master: k === 'master' ? 1 : 0 });
  return { db, s, ...sem, u, relogio };
}

// Cria uma oportunidade nova e a leva até a matrícula comercial.
export function ateMatriculaComercial(amb, ies = 'alfa', cursoIdx = 0, sufixo = Math.random().toString(36).slice(2, 8)) {
  const { s, u, iesIds, cursos } = amb;
  const com = ies === 'alfa' ? 'comercial1.alfa' : 'comercial.beta';
  const r = s.criarOportunidade(u(com), iesIds[ies], {
    nome: 'Pessoa Teste', email: `t-${sufixo}@exemplo.invalid`, curso_id: cursos[ies][cursoIdx], forma_ingresso: 'enem',
    coorte: '2028.1', base_legal: 'consentimento', origem: 'teste automatizado',
  });
  let v = r.versao;
  for (const para of ['contato', 'inscrito', 'pre_matricula', 'matricula_comercial']) v = s.moverEtapa(u(com), r.id, { para, versao_esperada: v }).versao;
  return { id: r.id, versao: v };
}
