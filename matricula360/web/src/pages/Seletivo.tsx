import { FileCheck2, Megaphone } from 'lucide-react';
import { useState } from 'react';
import { useSessao } from '../components/Layout';
import { Aviso, Campo, Cartao, Chip, Detalhes, Estado, Mensagem, Titulo, Vazio } from '../components/ui';
import { api } from '../lib/api';
import { rotulo } from '../lib/formato';
import { useAcao, useCarregar } from '../lib/hooks';
import type { ErroApi } from '../lib/supabase';
import type { Candidatura } from '../lib/tipos';

const TIPOS = ['prova_agendada', 'enem', 'analise_curricular', 'transferencia'];
type Fazer = (fn: () => Promise<string>) => Promise<void>;

// Processo seletivo online (L4): o sistema sugere, pessoas decidem; o candidato vê após a divulgação.
export function Seletivo({ abrirDetalhe }: { abrirDetalhe: (id: number) => void }) {
  const { ies, estrutura } = useSessao();
  const [recarga, setRecarga] = useState(0);
  const s = useCarregar(() => api.seletivo(ies!), [ies, recarga]);
  const acao = useAcao();
  const fazer: Fazer = (fn) => acao.executar(async () => { const t = await fn(); setRecarga((n) => n + 1); return t; });
  const vazio = { nome: '', tipo: 'prova_agendada', coorte: estrutura?.coortes[0] ?? '', inscricoes_ate: '', nota_minima: '', instrucoes: '', tema_redacao: '' };
  const [n, setN] = useState(vazio);
  const d = s.dados;
  return (
    <>
      <Titulo titulo="Processo seletivo" subtitulo="Inscrição, agenda de prova, nota do ENEM, redação corrigida por pessoa e divulgação do resultado." />
      {(s.erro as ErroApi | null)?.codigo === 'PGRST202' ? <Vazio texto="Disponível após a migração 20 do banco." /> : <Estado carregando={s.carregando && !d} erro={s.erro} />}
      <Mensagem m={acao.mensagem} />
      {d && (
        <div className="space-y-4">
          <Aviso>{d.aviso}</Aviso>
          {d.pode_gerir && (
            <Detalhes titulo="Novo processo seletivo">
              <form className="grid gap-2 sm:grid-cols-3" onSubmit={(e) => { e.preventDefault(); void fazer(async () => {
                await api.salvarProcesso(ies!, { ...n, nota_minima: n.nota_minima || null }); setN(vazio); return 'Processo criado.'; }); }}>
                <Campo rotulo="Nome"><input className="campo" required minLength={3} value={n.nome} onChange={(e) => setN({ ...n, nome: e.target.value })} /></Campo>
                <Campo rotulo="Tipo"><select className="campo" value={n.tipo} onChange={(e) => setN({ ...n, tipo: e.target.value })}>{TIPOS.map((t) => <option key={t} value={t}>{rotulo(t)}</option>)}</select></Campo>
                <Campo rotulo="Coorte"><input className="campo" required pattern="\d{4}\.[12]" value={n.coorte} onChange={(e) => setN({ ...n, coorte: e.target.value })} /></Campo>
                <Campo rotulo="Inscrições até"><input className="campo" type="date" required value={n.inscricoes_ate} onChange={(e) => setN({ ...n, inscricoes_ate: e.target.value })} /></Campo>
                <Campo rotulo="Nota mínima (0–1000, para sugestão)"><input className="campo" inputMode="decimal" value={n.nota_minima} onChange={(e) => setN({ ...n, nota_minima: e.target.value })} /></Campo>
                <Campo rotulo="Tema da redação (aparece só no horário da prova)"><input className="campo" value={n.tema_redacao} onChange={(e) => setN({ ...n, tema_redacao: e.target.value })} /></Campo>
                <Campo rotulo="Instruções ao candidato" className="sm:col-span-3"><textarea className="campo" value={n.instrucoes} onChange={(e) => setN({ ...n, instrucoes: e.target.value })} /></Campo>
                <div><button className="btn btn-peq" disabled={acao.enviando}>Criar processo</button></div>
              </form>
            </Detalhes>)}
          {!d.processos.length && <Vazio texto="Nenhum processo seletivo." />}
          {d.processos.map((p) => (
            <Cartao key={p.id} titulo={p.nome} icone={FileCheck2} acao={<span><Chip>{rotulo(p.tipo)}</Chip><Chip tipo={p.resultado_divulgado_em ? 'ok' : 'tec'}>{p.resultado_divulgado_em ? 'resultado divulgado' : rotulo(p.status)}</Chip></span>}>
              <p className="nota">Coorte {p.coorte} · inscrições até {new Date(`${p.inscricoes_ate}T12:00:00`).toLocaleDateString('pt-BR')}{p.nota_minima != null ? ` · nota mínima ${p.nota_minima}` : ''}</p>
              {p.tipo === 'prova_agendada' && (
                <div className="mt-2 text-sm">Agenda: {p.agendas.length ? p.agendas.map((a) => `${new Date(a.inicio).toLocaleString('pt-BR')} · ${a.local} (${a.ocupadas}/${a.vagas})`).join(' | ') : 'nenhuma data'}
                  {d.pode_gerir && !p.resultado_divulgado_em && <NovaAgenda processo={p.id} fazer={fazer} enviando={acao.enviando} />}</div>)}
              {p.candidaturas.length ? (
                <div className="mt-3 space-y-2">{p.candidaturas.map((c) => <LinhaCandidatura key={c.id} c={c} tipo={p.tipo} divulgado={!!p.resultado_divulgado_em} fazer={fazer} enviando={acao.enviando} abrirDetalhe={abrirDetalhe} />)}</div>
              ) : <p className="nota mt-2">Nenhuma candidatura.</p>}
              {d.pode_divulgar && !p.resultado_divulgado_em && p.candidaturas.length > 0 && (
                <button className="btn btn-peq mt-3" disabled={acao.enviando} onClick={() => { if (window.confirm('Divulgar o resultado? Depois disso, nenhum resultado pode ser alterado.')) void fazer(async () => { await api.divulgarResultado(p.id); return 'Resultado divulgado aos candidatos.'; }); }}>
                  <Megaphone className="h-3.5 w-3.5" aria-hidden />Divulgar resultado</button>)}
            </Cartao>))}
        </div>)}
    </>
  );
}

function NovaAgenda({ processo, fazer, enviando }: { processo: number; fazer: Fazer; enviando: boolean }) {
  const { ies } = useSessao();
  const [a, setA] = useState({ inicio: '', local: '', vagas: '50' });
  return (
    <form className="mt-1 flex flex-wrap items-end gap-2" onSubmit={(e) => { e.preventDefault(); void fazer(async () => {
      await api.salvarProcesso(ies!, { agenda: { inicio: new Date(a.inicio).toISOString(), local: a.local, vagas: Number(a.vagas) } }, processo); setA({ inicio: '', local: '', vagas: '50' }); return 'Data de prova incluída.'; }); }}>
      <Campo rotulo="Data e hora"><input className="campo" type="datetime-local" required value={a.inicio} onChange={(e) => setA({ ...a, inicio: e.target.value })} /></Campo>
      <Campo rotulo="Local"><input className="campo" required minLength={2} value={a.local} onChange={(e) => setA({ ...a, local: e.target.value })} /></Campo>
      <Campo rotulo="Vagas"><input className="campo w-20" type="number" min={1} value={a.vagas} onChange={(e) => setA({ ...a, vagas: e.target.value })} /></Campo>
      <button className="btn btn-sec btn-peq" disabled={enviando}>Incluir data</button>
    </form>
  );
}

function LinhaCandidatura({ c, tipo, divulgado, fazer, enviando, abrirDetalhe }: { c: Candidatura; tipo: string; divulgado: boolean; fazer: Fazer; enviando: boolean; abrirDetalhe: (id: number) => void }) {
  const [nota, setNota] = useState(''); const [parecer, setParecer] = useState(''); const [just, setJust] = useState('');
  return (
    <div className="rounded-lg border border-linha p-3 text-sm">
      <p className="font-medium"><button className="text-tec hover:underline" onClick={() => abrirDetalhe(c.oportunidade_id)}>{c.nome}</button> · {c.curso}
        {c.agenda && <span className="font-normal text-suave"> · prova {new Date(c.agenda).toLocaleString('pt-BR')}</span>}
        <Chip tipo={c.resultado === 'aprovado' ? 'ok' : c.resultado === 'pendente' ? 'pend' : undefined}>{rotulo(c.resultado === 'pendente' ? 'pendente_resultado' : c.resultado)}</Chip>
        {c.sugestao && c.resultado === 'pendente' && <Chip tipo="tec">sugestão: {rotulo(c.sugestao)}</Chip>}</p>
      {tipo === 'enem' && <p>ENEM declarado: {c.nota_enem ?? '—'} {c.enem_conferido ? <Chip tipo="ok">conferido</Chip> : !divulgado && c.nota_enem != null &&
        <button className="btn btn-sec btn-peq" disabled={enviando} onClick={() => void fazer(async () => { await api.avaliarCandidatura(c.id, { conferir_enem: true }); return 'Nota do ENEM conferida.'; })}>Conferir no boletim</button>}</p>}
      {c.redacao && <details className="mt-1"><summary className="cursor-pointer text-xs">Ler redação</summary><p className="mt-1 whitespace-pre-line rounded bg-fundo p-2 text-xs">{c.redacao}</p></details>}
      {c.redacao_nota != null && <p className="text-xs">Redação: {c.redacao_nota} · {c.redacao_parecer} · {c.corrigida_por}</p>}
      {c.justificativa && <p className="text-xs">Decisão: {c.justificativa} · {c.resultado_por}</p>}
      {!divulgado && (
        <div className="mt-2 flex flex-wrap items-end gap-2">
          {c.redacao_enviada && c.redacao_nota == null && <>
            <Campo rotulo="Nota da redação"><input className="campo w-20" inputMode="decimal" value={nota} onChange={(e) => setNota(e.target.value)} /></Campo>
            <Campo rotulo="Parecer" className="grow"><input className="campo" value={parecer} onChange={(e) => setParecer(e.target.value)} /></Campo>
            <button className="btn btn-sec btn-peq" disabled={enviando} onClick={() => void fazer(async () => { await api.avaliarCandidatura(c.id, { redacao_nota: Number(nota), redacao_parecer: parecer }); return 'Correção registrada.'; })}>Registrar correção</button></>}
          <Campo rotulo="Justificativa da decisão" className="grow"><input className="campo" value={just} onChange={(e) => setJust(e.target.value)} /></Campo>
          {['aprovado', 'reprovado', 'ausente'].map((r) => <button key={r} className={`btn btn-peq ${r === 'aprovado' ? 'btn-ok' : 'btn-sec'}`} disabled={enviando || just.trim().length < 5}
            onClick={() => void fazer(async () => { await api.avaliarCandidatura(c.id, { resultado: r, justificativa: just }); return `Resultado registrado: ${rotulo(r)}.`; })}>{rotulo(r)}</button>)}
        </div>)}
    </div>
  );
}
