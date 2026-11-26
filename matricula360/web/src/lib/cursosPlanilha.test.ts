import { describe, expect, it } from 'vitest';
import { errosLinha, lerLinhasTexto, paraCentavos, paraLinhas } from './cursosPlanilha';

describe('planilha de cursos', () => {
  it('converte valores em reais nos formatos comuns', () => {
    expect(paraCentavos('1.290,00')).toBe(129000);
    expect(paraCentavos('R$ 1.290,50')).toBe(129050);
    expect(paraCentavos('1290')).toBe(129000);
    expect(paraCentavos('1290.5')).toBe(129050);
    expect(paraCentavos('1.290')).toBe(129000);
    expect(paraCentavos('abc')).toBeNull();
    expect(paraCentavos('0')).toBeNull();
  });
  it('lê CSV com cabeçalho e texto colado do Excel, normalizando turno e modalidade', () => {
    const csv = lerLinhasTexto('curso;turno;modalidade;mensalidade;desconto_maximo\nDireito;Noite;Presencial;1.290,00;30\n');
    expect(paraLinhas(csv)).toEqual([{ nome: 'Direito', turno: 'noturno', modalidade: 'presencial', mensalidade: '1.290,00', desconto: '30' }]);
    const excel = lerLinhasTexto('Administração\tEaD\tA distância\t399\t\nPsicologia\tManhã\tHíbrido\t1190\t25');
    expect(paraLinhas(excel).map((l) => [l.turno, l.modalidade, l.desconto])).toEqual([['ead', 'ead', '30'], ['matutino', 'semipresencial', '25']]);
  });
  it('aponta erros por linha, inclusive curso repetido no mesmo turno', () => {
    const ls = paraLinhas([['Direito', 'noturno', 'presencial', '1290', '30'], ['direito', 'Noite', 'presencial', '1290', '30'], ['X', 'madrugada', 'presencial', '-1', '120']]);
    expect(errosLinha(ls[0]!, ls, 0)).toEqual([]);
    expect(errosLinha(ls[1]!, ls, 1)).toEqual(['repetido']);
    expect(errosLinha(ls[2]!, ls, 2)).toEqual(['nome', 'turno', 'mensalidade', 'desconto']);
  });
});
