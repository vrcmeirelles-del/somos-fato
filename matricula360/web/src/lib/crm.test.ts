import { describe, expect, it } from 'vitest';
import { faixaScore, linhaDoTempo, relativo } from './crm';
import type { Detalhe } from './tipos';

describe('crm', () => {
  it('relativo distingue passado, futuro e ausência', () => {
    const agora = Date.parse('2026-11-25T12:00:00Z');
    expect(relativo(null, agora)).toBe('nunca');
    expect(relativo('2026-11-25T11:30:00Z', agora)).toBe('há 30 min');
    expect(relativo('2026-11-25T15:00:00Z', agora)).toBe('em 3 h');
    expect(relativo('2026-11-22T12:00:00Z', agora)).toBe('há 3 d');
  });
  it('linha do tempo mescla fontes em ordem decrescente e funciona sem a migração 10', () => {
    const base = { historico: [{ id: 1, acao: 'oportunidade.criar', dados: {}, em: '2026-11-20T10:00:00Z', por: 'A' }] } as unknown as Detalhe;
    expect(linhaDoTempo(base, (a) => a)).toHaveLength(1);
    const d = { ...base, interacoes: [{ id: 7, tipo: 'ligacao', resumo: 'ligou', em: '2026-11-21T10:00:00Z', por: 'B' }],
      objecoes: [{ id: 3, categoria: 'preco', descricao: 'caro', tratamento: null, status: 'aberta', em: '2026-11-22T10:00:00Z', por: 'B' }] } as Detalhe;
    expect(linhaDoTempo(d, (a) => a).map((e) => e.chave)).toEqual(['o3', 'i7', 'a1']);
  });
  it('score: faixa só para valores presentes', () => {
    expect(faixaScore(null)).toBeUndefined();
    expect(faixaScore(75)).toBe('ok');
    expect(faixaScore(40)).toBe('pend');
    expect(faixaScore(10)).toBeUndefined();
  });
});
