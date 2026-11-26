import { useState } from 'react';
import { useSessao } from '../components/Layout';
import { Chip, Estado, Mensagem, Titulo } from '../components/ui';
import { api } from '../lib/api';
import { dataHora, rotulo } from '../lib/formato';
import { useAcao, useCarregar } from '../lib/hooks';
import type { Dimensao, Pendencia } from '../lib/tipos';

const DIMENSOES: Dimensao[] = ['documental', 'financeira', 'academica'];

export function Matriculas({ abrirDetalhe }: { abrirDetalhe: (id: number) => void }) {
  const { ies } = useSessao();
  const lista = useCarregar(() => api.pendencias(ies!), [ies]);
  const acao = useAcao();
  return (
    <>
      <Titulo titulo="Conversão e Matrículas" subtitulo="Matrícula comercial, validações por dimensão e ingresso efetivo." />
      <p className="nota mb-3">Matrícula comercial, validações documental/financeira/acadêmica e ingresso efetivo são etapas separadas. Secretaria valida documental e acadêmica;
        financeiro valida financeira (inclui isenção formal); comercial não valida. A confirmação só ocorre com as três dimensões válidas.</p>
      <Mensagem m={acao.mensagem} />
      <Estado carregando={lista.carregando && !lista.dados} erro={lista.erro} />
      <div className="tabela" tabIndex={0} role="region" aria-label="Tabela com rolagem horizontal">
        <table>
          <thead><tr>{['Candidato', 'Curso', 'Coorte', 'Situação', 'Validações', 'Ações'].map((c) => <th key={c} scope="col">{c}</th>)}</tr></thead>
          <tbody>
            {lista.dados?.length ? lista.dados.map((o) => (
              <Linha key={o.id} o={o} acao={acao} aoMudar={() => void lista.recarregar()} abrirDetalhe={abrirDetalhe} />
            )) : !lista.carregando && <tr><td colSpan={6} className="nd">Nenhuma matrícula comercial registrada.</td></tr>}
          </tbody>
        </table>
      </div>
    </>
  );
}

function Linha({ o, acao, aoMudar, abrirDetalhe }: { o: Pendencia; acao: ReturnType<typeof useAcao>; aoMudar: () => void; abrirDetalhe: (id: number) => void }) {
  const { tem } = useSessao();
  const dims = [...(tem('secretaria') ? (['documental', 'academica'] as Dimensao[]) : []), ...(tem('financeiro') ? (['financeira'] as Dimensao[]) : [])];
  const [dim, setDim] = useState<Dimensao | undefined>(dims[0]);
  const [resultado, setResultado] = useState('valida');
  const [evidencia, setEvidencia] = useState('');
  const [motivo, setMotivo] = useState('');
  const completo = o.val_documental && o.val_financeira && o.val_academica;
  const fazer = (fn: () => Promise<string>) => acao.executar(async () => { const t = await fn(); aoMudar(); return t; });

  return (
    <tr>
      <td><button className="btn btn-sec btn-peq" onClick={() => abrirDetalhe(o.id)}>{o.nome}</button></td>
      <td>{o.curso}</td><td>{o.coorte}</td><td>{rotulo(o.etapa)}</td>
      <td>{DIMENSOES.map((d) => <Chip key={d} tipo={o[`val_${d}`] ? 'ok' : 'pend'}>{rotulo(d)}</Chip>)}</td>
      <td>
        {o.etapa === 'matricula_comercial' ? (
          <div className="grid gap-2">
            {dims.length > 0 && (
              <div className="flex flex-wrap items-center gap-1.5">
                <select className="campo text-sm" aria-label="Dimensão" value={dim} onChange={(e) => setDim(e.target.value as Dimensao)}>
                  {dims.map((d) => <option key={d} value={d}>{rotulo(d)}</option>)}
                </select>
                <select className="campo text-sm" aria-label="Resultado" value={resultado} onChange={(e) => setResultado(e.target.value)}>
                  <option value="valida">Válida</option><option value="invalida">Inválida</option>
                  {tem('financeiro') && <option value="isencao_formal">Isenção formal (financeira)</option>}
                </select>
                <input className="campo text-sm" aria-label="Evidência" placeholder="Evidência (obrigatória)" maxLength={500} value={evidencia} onChange={(e) => setEvidencia(e.target.value)} />
                <button className="btn btn-peq" disabled={acao.enviando || !dim} onClick={() => void fazer(async () => {
                  await api.validar(o.id, dim!, resultado, evidencia, o.versao); setEvidencia(''); return 'Validação registrada com evidência.';
                })}>Registrar</button>
              </div>
            )}
            {tem('secretaria', 'gestor') && (
              <div className="flex flex-wrap items-center gap-1.5">
                <button className="btn btn-ok btn-peq" disabled={acao.enviando || !completo} title={completo ? undefined : 'Faltam validações'}
                  onClick={() => void fazer(async () => { await api.confirmar(o.id, o.versao); return 'Ingresso efetivo confirmado.'; })}>Confirmar ingresso</button>
                <input className="campo text-sm" aria-label="Motivo do cancelamento" placeholder="Motivo do cancelamento" maxLength={200} value={motivo} onChange={(e) => setMotivo(e.target.value)} />
                <button className="btn btn-perigo btn-peq" disabled={acao.enviando}
                  onClick={() => void fazer(async () => { await api.cancelar(o.id, o.versao, motivo); return 'Matrícula cancelada (histórico preservado).'; })}>Cancelar</button>
              </div>
            )}
          </div>
        ) : o.etapa === 'confirmado' && tem('secretaria', 'gestor') ? (
          <div className="flex flex-wrap items-center gap-1.5">
            <input className="campo text-sm" aria-label="Motivo do cancelamento" placeholder="Motivo do cancelamento" maxLength={200} value={motivo} onChange={(e) => setMotivo(e.target.value)} />
            <button className="btn btn-perigo btn-peq" disabled={acao.enviando}
              onClick={() => void fazer(async () => { await api.cancelar(o.id, o.versao, motivo); return 'Ingresso cancelado (histórico preservado).'; })}>Cancelar ingresso</button>
          </div>
        ) : <span className="nota">{o.etapa === 'cancelado' ? `Cancelada em ${dataHora(o.cancelada_em)}` : `Confirmada em ${dataHora(o.confirmada_em)}`}</span>}
      </td>
    </tr>
  );
}
