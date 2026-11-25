import { describe, expect, it } from 'vitest';
import { ND, centavos, linhaImportacao, moeda, num, pct, rotulo } from './formato';

describe('formato', () => {
  it('indisponível nunca vira zero', () => {
    expect(pct(null)).toBe(ND);
    expect(num(null)).toBe(ND);
    expect(pct(0)).toBe('0.0%');
    expect(num(0)).toBe('0');
  });
  it('percentual com uma casa', () => { expect(pct(0.14285714)).toBe('14.3%'); });
  it('moeda em reais a partir de centavos', () => { expect(moeda(129000).replace(/\s/g, ' ')).toBe('R$ 1.290,00'); });
  it('converte texto em centavos sem erro de ponto flutuante', () => {
    expect(centavos('1.290,00')).toBe(129000);
    expect(centavos('399,90')).toBe(39990);
    expect(centavos('0,29')).toBe(29);
    expect(() => centavos('abc')).toThrow();
    expect(() => centavos('0')).toThrow();
  });
  it('rótulos conhecidos e passagem direta dos desconhecidos', () => {
    expect(rotulo('matricula_comercial')).toBe('Matrícula comercial');
    expect(rotulo('confirmado')).toBe('Ingresso efetivo');
    expect(rotulo('xyz')).toBe('xyz');
    expect(rotulo(null)).toBe('');
  });
  it('linha de importação omite contato vazio e converte curso', () => {
    expect(linhaImportacao('Ana;;0000123456;2;enem;2027.1;consentimento;feira')).toEqual({
      nome: 'Ana', curso_id: 2, forma_ingresso: 'enem', coorte: '2027.1', base_legal: 'consentimento', origem: 'feira', telefone: '0000123456' });
  });
});
