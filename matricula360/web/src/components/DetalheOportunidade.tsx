import { useEffect, useRef, useState } from 'react';
import { api } from '../lib/api';
import { dataHora, moeda, rotulo } from '../lib/formato';
import { useAcao, useCarregar } from '../lib/hooks';
import type { Canal, Dimensao } from '../lib/tipos';
import { useSessao } from './Layout';
import { AcoesCandidato, AceiteNaFicha, BolsasNaFicha, CasosNaFicha, AlertaDuplicidade, DocumentosNaFicha, FunilNaFicha, LinhaDoTempo, PainelScore, Reatribuir, Relacionamento } from './FichaCrm';
import { Campo, Chip, Estado, Mensagem } from './ui';

const CANAIS: Canal[] = ['email', 'whatsapp', 'telefone'];
const DIMENSOES: Dimensao[] = ['documental', 'financeira', 'academica'];

export function DetalheOportunidade({ id, aoFechar, aoMudar }: { id: number; aoFechar: () => void; aoMudar?: () => void }) {
  const { tem, ies } = useSessao();
  const dlg = useRef<HTMLDialogElement>(null);
  const d = useCarregar(() => api.detalhe(id), [id]);
  const acao = useAcao();
  const [motivo, setMotivo] = useState('');
  const [desconto, setDesconto] = useState('10');
  const [validade, setValidade] = useState('7');
  useEffect(() => { const el = dlg.current; if (el && !el.open) el.showModal(); }, []);

  const fazer = (fn: () => Promise<string>) => acao.executar(async () => {
    const texto = await fn();
    await d.recarregar();
    aoMudar?.();
    return texto;
  });
  const fechar = () => { dlg.current?.close(); aoFechar(); };
  const o = d.dados?.oportunidade; const p = d.dados?.pessoa; const curso = d.dados?.curso;
  const podeFunil = tem('comercial', 'gestor');
  const m10 = d.dados != null && 'objecoes' in d.dados;

  return (
    <dialog ref={dlg} aria-labelledby="det-titulo" onCancel={(e) => { e.preventDefault(); fechar(); }}
      className="max-h-[92vh] w-[min(920px,calc(100vw-24px))] rounded-2xl p-0 backdrop:bg-marinho/45">
      <div id="det-corpo" className="p-5">
        <div className="flex items-start justify-between gap-3">
          <div>
            <h2 id="det-titulo" className="text-xl font-bold">{p?.nome ?? 'Carregando…'}</h2>
            {curso && o && <p>{curso.nome} · {curso.turno} · {curso.modalidade} · coorte {o.coorte}</p>}
          </div>
          <button className="btn btn-sec btn-peq" aria-label="Fechar" onClick={fechar}>Fechar</button>
        </div>
        <Estado carregando={d.carregando && !d.dados} erro={d.erro} />
        {o && p && curso && d.dados && (
          <>
            <p className="my-2"><Chip>{rotulo(o.etapa)}</Chip><Chip>{rotulo(o.forma_ingresso)}</Chip><Chip>versão {o.versao}</Chip><Chip>responsável: {o.responsavel ?? '—'}</Chip></p>
            <Mensagem m={acao.mensagem} />
            {m10 && <AlertaDuplicidade d={d.dados} />}
            {m10 && d.dados.score && <div className="mb-4"><PainelScore d={d.dados} /></div>}
            <div className="grid gap-4 sm:grid-cols-2">
              <section>
                <h3 className="font-semibold">Contato e LGPD</h3>
                <p>E-mail: {p.email ?? '—'}<br />Telefone: {p.telefone ?? '—'}</p>
                {p.dados_mascarados && <p className="nota">Dados mascarados para o seu perfil (minimização).</p>}
                <p className="mt-1">Base legal: {rotulo(p.base_legal)}<br />Origem: {p.origem}</p>
                <p className="mt-1">Opt-out: {CANAIS.map((c) => <Chip key={c} tipo={p.optout[c] ? 'erro' : undefined}>{c}: {p.optout[c] ? 'bloqueado' : 'permitido'}</Chip>)}</p>
                {tem('comercial', 'gestor', 'secretaria') && !p.anonimizada && (
                  <div className="my-2 flex flex-wrap gap-1.5">
                    {CANAIS.filter((c) => !p.optout[c]).map((c) => (
                      <button key={c} className="btn btn-sec btn-peq" disabled={acao.enviando} onClick={() => void fazer(async () => {
                        const r = await api.optout(id, c); return `Opt-out de ${c} registrado; ${r.tarefas_suprimidas} tarefa(s) suprimida(s).`;
                      })}>Opt-out {c}</button>
                    ))}
                  </div>
                )}
                {tem('gestor') && !p.anonimizada && (
                  <button className="btn btn-perigo btn-peq" disabled={acao.enviando} onClick={() => {
                    if (!window.confirm('Anonimizar os dados pessoais deste titular? A ação não pode ser desfeita; o histórico estatístico é preservado.')) return;
                    void fazer(async () => { await api.anonimizar(id); return 'Titular anonimizado.'; });
                  }}>Anonimizar titular (LGPD)</button>
                )}
              </section>
              <section>
                <h3 className="font-semibold">Funil</h3>
                {podeFunil && d.dados.transicoes.length ? (
                  <div>
                    {d.dados.transicoes.includes('perdido') && (
                      <input className="campo my-1 w-full" aria-label="Motivo da perda" placeholder="Motivo (obrigatório para perda)" maxLength={200} value={motivo} onChange={(e) => setMotivo(e.target.value)} />
                    )}
                    <div className="my-2 flex flex-wrap gap-1.5">
                      {d.dados.transicoes.map((para) => (
                        <button key={para} className={`btn btn-peq ${para === 'perdido' ? 'btn-perigo' : ''}`} disabled={acao.enviando} onClick={() => void fazer(async () => {
                          await api.moverEtapa(id, para, o.versao, para === 'perdido' ? motivo : undefined);
                          return `Etapa atualizada para ${rotulo(para)}.`;
                        })}>→ {rotulo(para)}</button>
                      ))}
                    </div>
                  </div>
                ) : <p className="nota">{o.etapa === 'matricula_comercial' ? 'Próximo passo: validações em Matrículas.' : 'Sem transições disponíveis para seu perfil.'}</p>}
                {o.motivo_perda && <p>Motivo da perda: {o.motivo_perda}</p>}
                <h3 className="mt-3 font-semibold">Validações</h3>
                <p>{DIMENSOES.map((dim) => <Chip key={dim} tipo={o[`val_${dim}`] ? 'ok' : 'pend'}>{rotulo(dim)}: {o[`val_${dim}`] ? 'ok' : 'pendente'}</Chip>)}</p>
                <ul className="mt-1 text-sm">{d.dados.validacoes.map((v) => <li key={v.id} className="border-l-[3px] border-linha pl-2.5">{rotulo(v.dimensao)} · {rotulo(v.resultado)} · {v.por} · {dataHora(v.em)} — {v.evidencia}</li>)}</ul>
              </section>
            </div>
            <DocumentosNaFicha op={id} fazer={fazer} enviando={acao.enviando} />
            {!p.anonimizada && <BolsasNaFicha op={id} fazer={fazer} enviando={acao.enviando} />}
            {o.etapa === 'confirmado' && !p.anonimizada && tem('gestor', 'secretaria', 'coordenador', 'financeiro', 'reitoria') && <CasosNaFicha op={id} fazer={fazer} enviando={acao.enviando} />}
            {['matricula_comercial', 'confirmado', 'cancelado'].includes(o.etapa) && tem('gestor', 'secretaria', 'financeiro', 'coordenador', 'comercial') && <AceiteNaFicha op={id} fazer={fazer} enviando={acao.enviando} />}
            {tem('gestor', 'comercial') && !p.anonimizada && ies && <AcoesCandidato op={id} ies={ies} fazer={fazer} enviando={acao.enviando} />}
            <FunilNaFicha op={id} versaoOp={o.versao} podeEditar={podeFunil && !p.anonimizada} fazer={fazer} enviando={acao.enviando} />
            {m10 && <div className="mt-4 border-t border-linha pt-4"><Relacionamento d={d.dados} fazer={fazer} enviando={acao.enviando} podeEditar={podeFunil && !p.anonimizada} /></div>}
            {m10 && tem('gestor') && <Reatribuir d={d.dados} fazer={fazer} enviando={acao.enviando} />}
            <section className="mt-4">
              <h3 className="font-semibold">Propostas</h3>
              {podeFunil && ['inscrito', 'pre_matricula', 'matricula_comercial'].includes(o.etapa) && (
                <div className="my-2 flex flex-wrap items-end gap-2">
                  <Campo rotulo="Desconto %"><input className="campo w-24" type="number" min={0} max={100} step="0.5" aria-label="Desconto em %" value={desconto} onChange={(e) => setDesconto(e.target.value)} /></Campo>
                  <Campo rotulo="Validade (dias)"><input className="campo w-24" type="number" min={1} max={30} aria-label="Validade em dias" value={validade} onChange={(e) => setValidade(e.target.value)} /></Campo>
                  <button className="btn btn-peq" disabled={acao.enviando} onClick={() => void fazer(async () => {
                    const r = await api.criarProposta(id, Number(desconto), Number(validade));
                    return `Proposta #${r.id}: ${moeda(r.valor_final_centavos)}/mês — ${rotulo(r.status)}${r.status === 'pendente_aprovacao' ? ` (acima do limite de ${r.limite_pct}%)` : ''}.`;
                  })}>Gerar proposta</button>
                  <small className="nota">Mensalidade {moeda(curso.mensalidade_centavos)} · limite sem aprovação {curso.desconto_max_pct}%</small>
                </div>
              )}
              {d.dados.propostas.length ? (
                <div className="tabela" tabIndex={0} role="region" aria-label="Tabela com rolagem horizontal"><table>
                  <thead><tr>{['#', 'Desconto', 'Valor final', 'Validade', 'Status', 'Emitida', ''].map((c) => <th key={c}>{c}</th>)}</tr></thead>
                  <tbody>{d.dados.propostas.map((pr) => (
                    <tr key={pr.id}><td>{pr.id}</td><td>{pr.desconto_pct}%</td><td>{moeda(pr.valor_final_centavos)}</td><td>{dataHora(pr.validade)}</td><td>{rotulo(pr.status)}</td><td className="text-xs">{pr.criado_em ? `${dataHora(pr.criado_em)} · ${pr.criado_por ?? ''}` : '—'}</td>
                      <td>{pr.status === 'aprovada' && podeFunil && <button className="btn btn-peq" disabled={acao.enviando} onClick={() => void fazer(async () => {
                        const r = await api.aceitarProposta(pr.id); return `Proposta ${rotulo(r.status)}.`;
                      })}>Registrar aceite</button>}</td></tr>
                  ))}</tbody>
                </table></div>
              ) : <p className="nota">Nenhuma proposta.</p>}
            </section>
            {m10 ? <LinhaDoTempo d={d.dados} /> : (
            <section className="mt-4">
              <h3 className="font-semibold">Histórico (auditoria)</h3>
              <ul className="text-sm">{d.dados.historico.map((h) => (
                <li key={h.id} className="mb-1 border-l-[3px] border-linha pl-2.5">
                  {dataHora(h.em)} · {h.por ?? 'sistema'} · {h.acao}
                  {typeof h.dados.de === 'string' && ` (${rotulo(h.dados.de)} → ${rotulo(String(h.dados.para))})`}
                  {typeof h.dados.motivo === 'string' && h.dados.motivo && ` — ${h.dados.motivo}`}
                </li>
              ))}</ul>
            </section>
            )}
          </>
        )}
      </div>
    </dialog>
  );
}
