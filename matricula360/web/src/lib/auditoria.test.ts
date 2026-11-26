import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { descreverEvento } from '../pages/Auditoria';

// Todo código de auditoria gravado pelas migrações precisa de tradução institucional (Bíblia: auditoria legível).
describe('auditoria legível', () => {
  it('nenhum código de auditoria das migrações cai na descrição técnica genérica', () => {
    const dir = join(__dirname, '../../../supabase/migrations');
    const sql = readdirSync(dir).filter((f) => f.endsWith('.sql')).map((f) => readFileSync(join(dir, f), 'utf8')).join('\n');
    const fixos = [...sql.matchAll(/privado\.auditar\([^,]*,\s*'([a-z_.]+)'/g)].map((m) => m[1]!).filter((c) => !c.endsWith('.'));
    const familias = ['plano.submeter', 'plano.aprovar', 'plano.devolver', 'plano.revisar', 'plano.encerrar', 'recuperacao.contatada', 'recuperacao.reativar',
      'recuperacao.descartada', 'rubrica.nova_versao', 'rubrica.salvar', 'rubrica.publicar', 'tarefa.concluida', 'tarefa.suprimida', 'tarefa.cancelada',
      'avaliacao.salvar', 'avaliacao.finalizar'];
    const sem = [...new Set([...fixos, ...familias])].filter((acao) => {
      const t = descreverEvento({ acao, dados: {}, entidade: 'x', entidade_id: '1' });
      return t.startsWith(`${acao} (`);
    });
    expect(sem).toEqual([]);
  });
});
