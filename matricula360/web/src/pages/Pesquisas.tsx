import { ClipboardList } from 'lucide-react';
import { useState } from 'react';
import { useSessao } from '../components/Layout';
import { Aviso, Cartao, Chip, Detalhes, Estado, Kpi, Mensagem, Titulo, Vazio } from '../components/ui';
import { api } from '../lib/api';
import { rotulo } from '../lib/formato';
import { useAcao, useCarregar } from '../lib/hooks';
import type { ErroApi } from '../lib/supabase';
import type { PerguntaPesquisa, Pesquisa } from '../lib/tipos';

const MODELOS: Record<string, { nome: string; publico: string; perguntas: PerguntaPesquisa[] }> = {
  perda: { nome: 'Por que não nos escolheu', publico: 'perdido', perguntas: [
    { id: 'motivo', tipo: 'opcao', texto: 'Qual foi o principal motivo?', opcoes: ['Preço', 'Horário', 'Distância', 'Escolhi outra instituição', 'Desisti de estudar agora', 'Outro'] },
    { id: 'nps', tipo: 'nps', texto: 'De 0 a 10, quanto você recomendaria o nosso atendimento?' },
    { id: 'coment', tipo: 'texto', texto: 'O que poderíamos ter feito diferente?' }] },
  atendimento: { nome: 'Avaliação do atendimento', publico: 'candidato', perguntas: [
    { id: 'nps', tipo: 'nps', texto: 'De 0 a 10, quanto você recomendaria a instituição a um amigo?' },
    { id: 'clareza', tipo: 'escala5', texto: 'As informações sobre curso, valores e matrícula foram claras?' },
    { id: 'coment', tipo: 'texto', texto: 'Quer deixar um comentário?' }] },
  ingresso: { nome: 'Primeiras semanas', publico: 'ingressante', perguntas: [
    { id: 'nps', tipo: 'nps', texto: 'De 0 a 10, quanto você recomendaria o curso?' },
    { id: 'adaptacao', tipo: 'escala5', texto: 'Como está sua adaptação à rotina do curso?' },
    { id: 'apoio', tipo: 'opcao', texto: 'Precisa de apoio em algo?', opcoes: ['Não', 'Horários', 'Financeiro', 'Conteúdo das disciplinas', 'Acesso a sistemas'] },
    { id: 'coment', tipo: 'texto', texto: 'Algo mais que devemos saber?' }] },
};

// Pesquisas de pulso e satisfação (L16): respondidas no portal; resultados agregados e sem identificação.
export function Pesquisas() {
  const { ies } = useSessao();
  const [recarga, setRecarga] = useState(0);
  const r = useCarregar(() => api.pesquisas(ies!), [ies, recarga]);
  const acao = useAcao();
  const fazer = (fn: () => Promise<string>) => acao.executar(async () => { const t = await fn(); setRecarga((n) => n + 1); return t; });
  const d = r.dados;
  return (
    <>
      <Titulo titulo="Pesquisas" subtitulo="NPS, satisfação e motivos de perda, respondidos pelo portal; resultados agregados e sem identificação." />
      {(r.erro as ErroApi | null)?.codigo === 'PGRST202' ? <Vazio texto="Disponível após a migração 28 do banco." /> : <Estado carregando={r.carregando && !d} erro={r.erro} />}
      <Mensagem m={acao.mensagem} />
      {d && (
        <div className="space-y-4">
          <Aviso>{d.aviso}</Aviso>
          {d.pode_gerir && (
            <Detalhes titulo="Nova pesquisa a partir de um modelo">
              <div className="flex flex-wrap gap-2">{Object.entries(MODELOS).map(([k, m]) => (
                <button key={k} className="btn btn-sec btn-peq" disabled={acao.enviando} onClick={() => void fazer(async () => {
                  await api.salvarPesquisa(ies!, { ...m, nome: `${m.nome} ${new Date().toLocaleDateString('pt-BR')}` }); return 'Pesquisa criada em rascunho. Revise e ative.'; })}>{m.nome} · {rotulo(m.publico)}</button>))}</div>
              <p className="nota mt-1">A pesquisa nasce em rascunho; depois de ativada, as perguntas não mudam.</p>
            </Detalhes>)}
          {!d.pesquisas.length && <Vazio texto="Nenhuma pesquisa." />}
          {d.pesquisas.map((p) => <CartaoPesquisa key={p.id} p={p} podeGerir={d.pode_gerir} fazer={fazer} enviando={acao.enviando} />)}
        </div>)}
    </>
  );
}

function CartaoPesquisa({ p, podeGerir, fazer, enviando }: { p: Pesquisa; podeGerir: boolean; fazer: (fn: () => Promise<string>) => Promise<void>; enviando: boolean }) {
  const { ies } = useSessao();
  const r = p.resultado;
  return (
    <Cartao titulo={p.nome} icone={ClipboardList} acao={<span><Chip>{rotulo(p.publico)}</Chip><Chip tipo={p.status === 'ativa' ? 'ok' : p.status === 'rascunho' ? 'tec' : undefined}>{rotulo(p.status)}</Chip></span>}>
      <div className="grid gap-3 sm:grid-cols-4">
        <Kpi rotulo="Respostas" valor={String(r.respostas)} detalhe={`mínimo para exibir: ${p.min_respostas}`} />
        <Kpi rotulo="Taxa de resposta" valor={r.taxa_pct == null ? 'N/D' : `${r.taxa_pct}%`} detalhe={`${r.elegiveis} elegível(is)`} />
        <Kpi rotulo="NPS" valor={!r.suficiente || r.nps == null ? 'N/D' : String(r.nps)} destaque />
      </div>
      {!r.suficiente && <p className="nota mt-2">{r.motivo}</p>}
      {r.suficiente && r.por_pergunta && (
        <div className="mt-3 space-y-3">{p.perguntas.map((q) => {
          const v = r.por_pergunta![q.id];
          return (
            <div key={q.id} className="text-sm">
              <p className="font-medium">{q.texto} <span className="nota">({rotulo(q.tipo)})</span></p>
              {Array.isArray(v) ? (v.length ? <ul className="mt-1 list-disc pl-5 text-xs">{v.slice(0, 30).map((t, i) => <li key={i}>{t}</li>)}</ul> : <p className="nota">Sem comentários.</p>)
                : <Barras valores={v ?? {}} ordem={q.tipo === 'nps' ? Array.from({ length: 11 }, (_, i) => String(i)) : q.tipo === 'escala5' ? ['1', '2', '3', '4', '5'] : q.opcoes ?? Object.keys(v ?? {})} />}
            </div>);
        })}</div>)}
      {podeGerir && p.status !== 'encerrada' && (
        <button className="btn btn-sec btn-peq mt-3" disabled={enviando} onClick={() => void fazer(async () => {
          await api.salvarPesquisa(ies!, { status: p.status === 'rascunho' ? 'ativa' : 'encerrada' }, p.id); return p.status === 'rascunho' ? 'Pesquisa ativa: aparece no portal do público escolhido.' : 'Pesquisa encerrada.'; })}>
          {p.status === 'rascunho' ? 'Ativar' : 'Encerrar'}</button>)}
      <Detalhes titulo="Perguntas"><ol className="list-decimal pl-5 text-sm">{p.perguntas.map((q) => <li key={q.id}>{q.texto} <span className="nota">({rotulo(q.tipo)}{q.opcoes ? `: ${q.opcoes.join(', ')}` : ''})</span></li>)}</ol></Detalhes>
    </Cartao>
  );
}

function Barras({ valores, ordem }: { valores: Record<string, number>; ordem: string[] }) {
  const max = Math.max(1, ...Object.values(valores));
  return (
    <ul className="mt-1 space-y-0.5 text-xs">{ordem.map((k) => (
      <li key={k} className="flex items-center gap-2"><span className="w-40 shrink-0 truncate">{k}</span>
        <span className="h-3 rounded bg-tec" style={{ width: `${(100 * (valores[k] ?? 0)) / max}%`, minWidth: valores[k] ? 4 : 0 }} aria-hidden /><span>{valores[k] ?? 0}</span></li>))}</ul>
  );
}
