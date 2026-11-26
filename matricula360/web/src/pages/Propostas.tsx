import { useState } from 'react';
import { useSessao } from '../components/Layout';
import { Estado, Mensagem, Titulo } from '../components/ui';
import { api } from '../lib/api';
import { dataHora, moeda, rotulo } from '../lib/formato';
import { useAcao, useCarregar } from '../lib/hooks';
import type { StatusProposta } from '../lib/tipos';

const STATUS: StatusProposta[] = ['pendente_aprovacao', 'aprovada', 'aceita', 'rejeitada', 'expirada', 'substituida'];

export function Propostas() {
  const { ies, tem } = useSessao();
  const [status, setStatus] = useState<StatusProposta>('pendente_aprovacao');
  const lista = useCarregar(() => (tem('gestor', 'comercial') ? api.propostas(ies!, status) : Promise.resolve([])), [ies, status]);
  const acao = useAcao();
  if (!tem('gestor', 'comercial')) return <><Titulo titulo="Propostas" /><p>Seu perfil não acessa propostas.</p></>;
  return (
    <>
      <Titulo titulo="Propostas" subtitulo="Uma proposta ativa por oportunidade; descontos acima do limite exigem aprovação." />
      <p className="nota mb-3">Descontos acima do limite do curso exigem aprovação de gestor. Quem cria a proposta não pode aprová-la (segregação de funções).</p>
      <label className="mb-3 inline-block text-sm">Status{' '}
        <select className="campo" aria-label="Status" value={status} onChange={(e) => setStatus(e.target.value as StatusProposta)}>
          {STATUS.map((s) => <option key={s} value={s}>{rotulo(s)}</option>)}
        </select>
      </label>
      <Mensagem m={acao.mensagem} />
      <Estado carregando={lista.carregando && !lista.dados} erro={lista.erro} />
      <div className="tabela">
        <table>
          <thead><tr>{['#', 'Candidato', 'Curso', 'Desconto', 'Limite', 'Valor final', 'Criada por', 'Validade', ''].map((c) => <th key={c} scope="col">{c}</th>)}</tr></thead>
          <tbody>
            {lista.dados?.length ? lista.dados.map((p) => (
              <tr key={p.id}>
                <td>{p.id}</td><td>{p.nome}</td><td>{p.curso}</td><td>{p.desconto_pct}%</td><td>{p.desconto_max_pct}%</td>
                <td>{moeda(p.valor_final_centavos)}</td><td>{p.criado_por_nome}</td><td>{dataHora(p.validade)}</td>
                <td>{p.status === 'pendente_aprovacao' && tem('gestor') && (
                  <div className="flex gap-1.5">
                    {(['aprovar', 'rejeitar'] as const).map((dec) => (
                      <button key={dec} className={`btn btn-peq ${dec === 'aprovar' ? 'btn-ok' : 'btn-perigo'}`} disabled={acao.enviando}
                        onClick={() => void acao.executar(async () => {
                          const r = await api.decidirProposta(p.id, dec); await lista.recarregar(); return `Proposta #${p.id}: ${rotulo(r.status)}.`;
                        })}>{dec === 'aprovar' ? 'Aprovar' : 'Rejeitar'}</button>
                    ))}
                  </div>
                )}</td>
              </tr>
            )) : !lista.carregando && <tr><td colSpan={9} className="nd">Nenhuma proposta neste status.</td></tr>}
          </tbody>
        </table>
      </div>
    </>
  );
}
