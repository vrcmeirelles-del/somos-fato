import { describe, expect, it } from 'vitest';
import { aplicarResultado, novoId, sha256 } from './fila';
import type { LeadCampo } from './tipos';

const lead = (id: string): LeadCampo => ({ id_local: id, nome: 'X', curso_id: 1, coorte: '2027.1', consentimento: true, consentimento_hash: 'a'.repeat(64), capturado_em: '' });
describe('fila do modo feira', () => {
  it('mantém só os rejeitados, com o motivo', () => {
    expect(aplicarResultado([lead('a'), lead('b')], [{ id_local: 'b', motivo: 'Telefone inválido' }])).toEqual([{ ...lead('b'), motivo: 'Telefone inválido' }]);
  });
  it('gera identificador local no formato UUID v4 e hash SHA-256 do termo', async () => {
    expect(novoId()).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
    expect(await sha256('abc')).toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });
});
