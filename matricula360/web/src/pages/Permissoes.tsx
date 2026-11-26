import { Check, KeyRound, Minus } from 'lucide-react';
import { useSessao } from '../components/Layout';
import { Aviso, Cartao, Chip, Estado, Titulo, Vazio } from '../components/ui';
import { api } from '../lib/api';
import { rotulo } from '../lib/formato';
import { useCarregar } from '../lib/hooks';
import type { OperacaoMatriz, Papel } from '../lib/tipos';

const PAPEIS: Papel[] = ['gestor', 'reitoria', 'coordenador', 'comercial', 'secretaria', 'financeiro'];

// Matriz de permissões declarada no banco (migração 11) e permissões efetivas do usuário na instituição.
export function Permissoes() {
  const { ies } = useSessao();
  const p = useCarregar(() => api.permissoes(ies!), [ies]);
  const indisponivel = p.erro && /PGRST202|Could not find|não encontrad/i.test(`${(p.erro as { codigo?: string }).codigo ?? ''} ${p.erro.message}`);
  const modulos = new Map<string, OperacaoMatriz[]>();
  for (const o of p.dados?.matriz ?? []) modulos.set(o.modulo, [...(modulos.get(o.modulo) ?? []), o]);
  return (
    <>
      <Titulo titulo="Perfis e permissões" subtitulo="O que cada papel pode fazer, e o que você pode fazer nesta instituição. Tudo é verificado no servidor." />
      {indisponivel ? <Vazio texto="Disponível após a migração 11 do banco." /> : <Estado carregando={p.carregando && !p.dados} erro={p.erro} />}
      {p.dados && (
        <>
          <Cartao titulo="Seus escopos nesta instituição" icone={KeyRound} className="mb-4">
            <p>{p.dados.escopos.map((e, i) => <Chip key={i} tipo="tec">{rotulo(e.papel)} · {rotulo(e.abrangencia)}: {e.alvo}</Chip>)}</p>
            <div className="mt-2"><Aviso>Abrangência é sempre explícita: instituição inteira, um campus ou um curso. Operações de instituição (configurações, metas, auditoria, MAIM) exigem abrangência de instituição.</Aviso></div>
          </Cartao>
          {[...modulos.entries()].map(([modulo, ops]) => (
            <section key={modulo} className="mb-4">
              <h2 className="mb-2 text-base font-semibold text-marinho">{modulo}</h2>
              <div className="tabela" tabIndex={0} role="region" aria-label="Tabela com rolagem horizontal"><table>
                <thead><tr><th scope="col">Operação</th>{PAPEIS.map((pp) => <th key={pp} scope="col" className="text-center">{rotulo(pp)}</th>)}<th scope="col">Abrangência mínima</th><th scope="col">Você</th></tr></thead>
                <tbody>{ops.map((o) => (
                  <tr key={o.operacao}>
                    <td>{o.descricao}<code className="block text-[10px] text-suave">{o.operacao}</code></td>
                    {PAPEIS.map((pp) => <td key={pp} className="text-center">{o.papeis.includes(pp)
                      ? <Check className="mx-auto h-4 w-4 text-ok" aria-label="permitido" /> : <Minus className="mx-auto h-4 w-4 text-linha" aria-label="não permitido" />}</td>)}
                    <td>{o.abrangencia_minima === 'ies' ? 'Instituição' : 'Curso ou campus'}</td>
                    <td>{o.permitida ? <Chip tipo="ok">permitido</Chip> : <Chip>não</Chip>}</td>
                  </tr>))}</tbody>
              </table></div>
            </section>
          ))}
        </>
      )}
    </>
  );
}
