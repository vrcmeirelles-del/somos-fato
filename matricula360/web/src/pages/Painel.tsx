import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { useSessao } from '../components/Layout';
import { Estado, Kpi, Mensagem, Secao, Valor } from '../components/ui';
import { api } from '../lib/api';
import { dataHora, num, pct, rotulo } from '../lib/formato';
import { useAcao, useCarregar } from '../lib/hooks';

const AGRUPAMENTOS = ['curso', 'turno', 'modalidade', 'forma_ingresso', 'atendente'];

export function Painel({ abrirDetalhe }: { abrirDetalhe: (id: number) => void }) {
  const { ies, estrutura, tem } = useSessao();
  const [coorte, setCoorte] = useState(estrutura?.coortes[0] ?? '');
  const [agrupar, setAgrupar] = useState('curso');
  useEffect(() => { setCoorte(estrutura?.coortes[0] ?? ''); }, [estrutura]);
  const bi = useCarregar(() => (ies && coorte ? api.bi(ies, coorte, agrupar) : Promise.resolve(null)), [ies, coorte, agrupar]);
  const t = bi.dados?.totais;

  return (
    <>
      <h1 className="mb-3 text-2xl font-bold sm:text-3xl">Painel · {estrutura?.ies.nome}</h1>
      <div className="mb-4 flex flex-wrap items-end gap-3">
        <label className="text-sm">Coorte{' '}
          <select id="coorte" className="campo" value={coorte} onChange={(e) => setCoorte(e.target.value)}>
            {(estrutura?.coortes ?? []).map((c) => <option key={c}>{c}</option>)}
          </select>
        </label>
        <label className="text-sm">Agrupar por{' '}
          <select id="agrupar" className="campo" value={agrupar} onChange={(e) => setAgrupar(e.target.value)}>
            {AGRUPAMENTOS.map((a) => <option key={a} value={a}>{rotulo(a)}</option>)}
          </select>
        </label>
      </div>
      {!coorte ? <p className="nd">Sem coortes com dados ou metas. Indicadores indisponíveis.</p> : (
        <>
          <Estado carregando={bi.carregando && !bi.dados} erro={bi.erro} />
          {t && bi.dados && (
            <>
              <div className="kpis grid grid-cols-2 gap-3 sm:grid-cols-[repeat(auto-fit,minmax(150px,1fr))]">
                <Kpi rotulo="Oportunidades" valor={num(t.oportunidades)} />
                <Kpi rotulo="Matrículas comerciais" valor={num(t.matriculas_comerciais)} />
                <Kpi rotulo="Ingressantes efetivos" valor={num(t.ingressantes)} />
                <Kpi rotulo="Conversão (coorte)" valor={pct(t.conversao)} />
                <Kpi rotulo="Meta" valor={num(t.meta)} />
                <Kpi rotulo="Atingimento" valor={pct(t.atingimento)} />
                <Kpi rotulo="Cancelamentos" valor={num(t.cancelamentos)} />
                <Kpi rotulo="Oportunidades necessárias (projeção)" valor={num(t.projecao_oportunidades_necessarias)} />
              </div>
              <p className="nota mt-2">
                N/D = indisponível (sem denominador ou sem meta), distinto de zero. Denominador da conversão: oportunidades da coorte {bi.dados.coorte}.
                Ingressantes contam pessoas distintas. Cobertura: {bi.dados.cobertura === 'ies' ? 'instituição inteira' : 'somente cursos autorizados'}.
              </p>
              <div className="tabela mt-3">
                <table>
                  <thead><tr>{['Grupo', 'Oport.', 'Mat. comerciais', 'Ingressantes', 'Conversão', 'Meta', 'Atingimento', 'Perdidos', 'Cancel.'].map((c) => <th key={c} scope="col">{c}</th>)}</tr></thead>
                  <tbody>
                    {bi.dados.linhas.length ? bi.dados.linhas.map((l) => (
                      <tr key={l.chave}>
                        <td>{rotulo(l.chave)}</td><td>{l.oportunidades}</td><td>{l.matriculas_comerciais}</td><td>{l.ingressantes}</td>
                        <td><Valor v={pct(l.conversao)} /></td><td><Valor v={num(l.meta)} /></td><td><Valor v={pct(l.atingimento)} /></td>
                        <td>{l.perdidos}</td><td>{l.cancelamentos}</td>
                      </tr>
                    )) : <tr><td colSpan={9} className="nd">Sem dados para esta coorte (indisponível).</td></tr>}
                  </tbody>
                </table>
              </div>
            </>
          )}
        </>
      )}
      {tem('gestor', 'comercial', 'secretaria', 'financeiro') && <FilaMaim abrirDetalhe={abrirDetalhe} />}
    </>
  );
}

function FilaMaim({ abrirDetalhe }: { abrirDetalhe: (id: number) => void }) {
  const { ies, tem } = useSessao();
  const fila = useCarregar(() => api.fila(ies!), [ies]);
  const acao = useAcao();
  const [todas, setTodas] = useState(false);
  const [resultados, setResultados] = useState<Record<number, string>>({});
  const tarefas = fila.dados?.tarefas ?? [];
  const visiveis = todas ? tarefas : tarefas.slice(0, 10);
  const atrasadas = tarefas.filter((t) => t.atrasada).length;

  return (
    <Secao titulo="Fila de acompanhamento (MAIM)" acao={tem('gestor') && (
      <button className="btn btn-peq" disabled={acao.enviando} onClick={() => void acao.executar(async () => {
        const r = await api.cicloMaim(ies!);
        await fila.recarregar();
        return `Ciclo MAIM: ${r.follow_ups} follow-ups, ${r.pendencias_validacao} pendências de validação, ${r.suprimidos_optout} suprimidos por opt-out, ${r.limite_atingido} no limite, ${r.atrasadas} tarefas atrasadas.`;
      })}>Executar ciclo MAIM</button>)}>
      <p className="nota">Tarefas internas com SLA. Envio externo está desativado: “Disparar” só revalida e registra a tentativa.</p>
      <p className="my-1 text-sm">{tarefas.length} tarefa(s) aberta(s) · {atrasadas} atrasada(s) no SLA
        {tarefas.length > visiveis.length && <> · exibindo as {visiveis.length} mais urgentes <button className="btn btn-sec btn-peq ml-1" onClick={() => setTodas(true)}>Ver todas</button></>}
      </p>
      <Mensagem m={acao.mensagem} />
      <Estado carregando={fila.carregando && !fila.dados} erro={fila.erro} />
      <div className="tabela">
        <table>
          <thead><tr>{['Vence', 'Tipo', 'Candidato', 'Curso', 'Canal', 'Responsável', 'Ações'].map((c) => <th key={c} scope="col">{c}</th>)}</tr></thead>
          <tbody>
            {visiveis.length ? visiveis.map((t) => (
              <tr key={t.id}>
                <td className={t.atrasada ? 'font-semibold text-erro' : ''}>{dataHora(t.vence_em)}{t.atrasada ? ' (atrasada)' : ''}</td>
                <td>{rotulo(t.tipo)}</td>
                <td><button className="btn btn-sec btn-peq" onClick={() => abrirDetalhe(t.oportunidade_id)}>{t.nome}</button></td>
                <td>{t.curso}</td><td>{t.canal ?? '—'}</td><td>{t.responsavel ?? <span className="nd">sem responsável</span>}</td>
                <td>
                  {t.tipo === 'pendencia_validacao' ? <Link className="text-acao underline" to={`/matriculas?ies=${ies}`}>Ir para matrículas</Link> : (
                    <div className="flex flex-wrap items-center gap-1.5">
                      <input className="campo text-sm" aria-label={`Resultado do contato da tarefa ${t.id}`} placeholder="Resultado do contato" maxLength={300}
                        value={resultados[t.id] ?? ''} onChange={(e) => setResultados({ ...resultados, [t.id]: e.target.value })} />
                      <button className="btn btn-peq" disabled={acao.enviando} onClick={() => void acao.executar(async () => {
                        const r = await api.concluirTarefa(t.id, resultados[t.id] ?? '');
                        await fila.recarregar();
                        return `Tarefa ${r.status}${r.motivo ? ' — ' + r.motivo : ''}.`;
                      })}>Registrar contato</button>
                      <button className="btn btn-sec btn-peq" disabled={acao.enviando} onClick={() => void acao.executar(async () => {
                        const r = await api.dispararTarefa(t.id);
                        return `${r.motivo}. Elegível na revalidação: ${r.elegivel ? 'sim' : 'não'}.`;
                      })}>Disparar</button>
                    </div>
                  )}
                </td>
              </tr>
            )) : <tr><td colSpan={7} className="nd">Nenhuma tarefa aberta.</td></tr>}
          </tbody>
        </table>
      </div>
    </Secao>
  );
}
