import { describe, expect, it } from 'vitest';
import { comprovanteHtml, contarDestaques, partesContrato } from './contrato';
import type { ComprovanteAceite } from './tipos';

describe('contrato: cláusulas em destaque', () => {
  it('separa os trechos marcados com **', () => {
    expect(partesContrato('A **multa** e o **reajuste** valem.')).toEqual([
      { texto: 'A ', destaque: false }, { texto: 'multa', destaque: true }, { texto: ' e o ', destaque: false },
      { texto: 'reajuste', destaque: true }, { texto: ' valem.', destaque: false }]);
  });
  it('marcação aberta fica como texto comum e é sinalizada', () => {
    expect(partesContrato('cláusula **aberta')).toEqual([{ texto: 'cláusula **aberta', destaque: false }]);
    expect(contarDestaques('cláusula **aberta')).toEqual({ total: 0, balanceado: false });
    expect(contarDestaques('**a** e **b**')).toEqual({ total: 2, balanceado: true });
  });
});

describe('comprovante do aceite', () => {
  const base: ComprovanteAceite = {
    instituicao: 'Faculdade Alfa', curso: 'Direito · noite', coorte: '2027.1', aceito_em: '2026-11-26T15:00:00Z', procedimento: 'aceite-v2',
    evidencia: { candidato: { nome: 'Ana <script>', cpf: '52998224725', nascimento: '2010-01-02', menor_de_18: true },
      representante_legal: { nome: 'Maria Sintética', cpf: '11144477735', vinculo: 'mae' },
      condicoes: { proposta_id: 7, mensalidade_centavos: 129000, desconto_pct: 10, valor_final_centavos: 116100 },
      declaracoes: { li_o_contrato: true }, confirmacao: { canal: 'email', destino: 'a***@x.invalid', modo: 'simulacao' } },
    evidencia_texto: '{"a": 1}', evidencia_hash: 'f'.repeat(64), evidencia_integra: true,
    contrato_versao: 2, contrato_texto: 'Texto **multa de 10%** fim', contrato_hash: 'a'.repeat(64), contrato_integro: true,
    nome_confirmado: 'Ana', arrependimento_ate: '2026-12-03T15:00:00Z', desistencia_em: null, desistencia_motivo: null,
  };
  it('traz identificação, representante, condições, hashes e contrato com destaque, escapando HTML', () => {
    const h = comprovanteHtml(base);
    expect(h).toContain('CPF 529.982.247-25');
    expect(h).toContain('Maria Sintética · CPF 111.444.777-35 · mãe');
    expect(h).toContain('<strong class="d">multa de 10%</strong>');
    expect(h).toContain('modo simulação');
    expect(h).toContain('f'.repeat(64));
    expect(h).toContain('Ana &lt;script&gt;');
    expect(h).not.toContain('<script>');
  });
  it('denuncia hash que não confere e registra desistência', () => {
    const h = comprovanteHtml({ ...base, evidencia_integra: false, desistencia_em: '2026-11-27T10:00:00Z', desistencia_motivo: 'Mudei de cidade' });
    expect(h).toContain('NÃO conferem');
    expect(h).toContain('Desistência registrada');
  });
});
