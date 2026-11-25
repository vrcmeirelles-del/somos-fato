import { useState } from 'react';
import { useSessao } from '../components/Layout';
import { Campo, Estado, Mensagem, Secao } from '../components/ui';
import { api } from '../lib/api';
import { dataHora } from '../lib/formato';
import { useAcao, useCarregar } from '../lib/hooks';

const CAMPOS = [
  ['sla_horas', 'SLA do primeiro contato (h)'], ['max_followups', 'Máx. follow-ups'],
  ['dias_sem_contato', 'Dias sem contato p/ follow-up'], ['capacidade_atendente', 'Capacidade por atendente'],
] as const;

export function Configuracoes() {
  const { ies, estrutura, tem, recarregarEstrutura } = useSessao();
  const acao = useAcao();
  const [cfg, setCfg] = useState<Record<string, string>>(() => Object.fromEntries(CAMPOS.map(([k]) => [k, String(estrutura?.ies[k] ?? '')])));
  const [coorte, setCoorte] = useState(estrutura?.coortes[0] ?? '2027.1');
  const [metas, setMetas] = useState<Record<number, string>>({});
  const aud = useCarregar(() => (tem('gestor') ? api.auditoria(ies!) : Promise.resolve(null)), [ies]);
  if (!tem('gestor')) return <><h1 className="mb-3 text-2xl font-bold">Configurações</h1><p>Disponível apenas para gestores da instituição.</p></>;

  return (
    <>
      <h1 className="mb-3 text-2xl font-bold sm:text-3xl">Configurações</h1>
      <Mensagem m={acao.mensagem} />
      <Secao titulo="MAIM e SLA">
        <div className="flex flex-wrap items-end gap-2">
          {CAMPOS.map(([k, r]) => <Campo key={k} rotulo={r}><input className="campo w-28" type="number" min={0} value={cfg[k]} onChange={(e) => setCfg({ ...cfg, [k]: e.target.value })} /></Campo>)}
          <button className="btn" disabled={acao.enviando} onClick={() => void acao.executar(async () => {
            await api.configurar(ies!, Object.fromEntries(CAMPOS.map(([k]) => [k, Number(cfg[k])])));
            recarregarEstrutura(); return 'Configuração salva.';
          })}>Salvar</button>
        </div>
      </Secao>
      <Secao titulo="Metas por curso">
        <div className="flex flex-wrap items-end gap-2">
          <Campo rotulo="Coorte"><input className="campo w-24" aria-label="Coorte da meta" value={coorte} onChange={(e) => setCoorte(e.target.value)} /></Campo>
          {estrutura?.cursos.map((c) => <Campo key={c.id} rotulo={c.nome}><input className="campo w-24" type="number" min={0} aria-label={`Meta ${c.nome}`} value={metas[c.id] ?? ''} onChange={(e) => setMetas({ ...metas, [c.id]: e.target.value })} /></Campo>)}
          <button className="btn" disabled={acao.enviando} onClick={() => void acao.executar(async () => {
            for (const c of estrutura?.cursos ?? []) if ((metas[c.id] ?? '') !== '') await api.definirMeta(ies!, c.id, coorte, Number(metas[c.id]));
            recarregarEstrutura(); return 'Metas salvas. Cursos sem meta ficam “N/D”, não zero.';
          })}>Salvar metas</button>
        </div>
      </Secao>
      <Secao titulo="Auditoria (somente leitura)">
        <Estado carregando={aud.carregando && !aud.dados} erro={aud.erro} />
        {aud.dados && (
          <>
            <div className="tabela"><table>
              <thead><tr>{['Quando', 'Quem', 'Ação', 'Entidade', 'Dados'].map((x) => <th key={x} scope="col">{x}</th>)}</tr></thead>
              <tbody>{aud.dados.itens.map((x) => (
                <tr key={x.id}><td>{dataHora(x.em)}</td><td>{x.por ?? 'sistema'}</td><td>{x.acao}</td><td>{x.entidade} {x.entidade_id ?? ''}</td>
                  <td><code className="break-all text-xs">{JSON.stringify(x.dados)}</code></td></tr>
              ))}</tbody>
            </table></div>
            <p className="nota mt-1">Exibindo {aud.dados.itens.length} de {aud.dados.total} eventos.</p>
          </>
        )}
      </Secao>
    </>
  );
}
