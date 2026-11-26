import { LifeBuoy } from 'lucide-react';
import { useState } from 'react';
import { useSessao } from '../components/Layout';
import { Aviso, Campo, Cartao, Chip, Detalhes, Estado, Kpi, Mensagem, Titulo, Vazio } from '../components/ui';
import { api } from '../lib/api';
import { dataHora, rotulo } from '../lib/formato';
import { useAcao, useCarregar } from '../lib/hooks';
import type { ErroApi } from '../lib/supabase';
import type { Caso, Casos } from '../lib/tipos';

type Fazer = (fn: () => Promise<string>) => Promise<void>;
export const MOTIVOS_CASO = ['frequencia', 'desempenho', 'financeiro', 'adaptacao', 'pessoal', 'rematricula_recusada', 'outro'];

// Sucesso do aluno (L15): casos com triagem e roteamento, trilhas de intervenção e agenda de atendimentos.
export function SucessoAluno({ abrirDetalhe }: { abrirDetalhe: (id: number) => void }) {
  const { ies } = useSessao();
  const [recarga, setRecarga] = useState(0);
  const r = useCarregar(() => api.casos(ies!), [ies, recarga]);
  const acao = useAcao();
  const fazer: Fazer = (fn) => acao.executar(async () => { const t = await fn(); setRecarga((n) => n + 1); return t; });
  const [filtro, setFiltro] = useState('abertos');
  const d = r.dados;
  const casos = (d?.casos ?? []).filter((c) => filtro === 'todos' ? true : filtro === 'meus' ? c.responsavel_id === d?.eu && ['aberto', 'em_atendimento'].includes(c.status)
    : filtro === 'sem_dono' ? !c.responsavel_id && ['aberto', 'em_atendimento'].includes(c.status) : ['aberto', 'em_atendimento'].includes(c.status));
  return (
    <>
      <Titulo titulo="Sucesso do aluno" subtitulo="Casos com triagem e roteamento automático, trilhas de intervenção por motivo e agenda de atendimentos." />
      {(r.erro as ErroApi | null)?.codigo === 'PGRST202' ? <Vazio texto="Disponível após a migração 25 do banco." /> : <Estado carregando={r.carregando && !d} erro={r.erro} />}
      <Mensagem m={acao.mensagem} />
      {d && (
        <div className="space-y-4">
          <Aviso>{d.aviso} Para abrir um caso, use a ficha do aluno (botão “Abrir caso”).</Aviso>
          <div className="grid gap-3 sm:grid-cols-5">
            <Kpi rotulo="Casos abertos" valor={String(d.indicadores.abertos)} />
            <Kpi rotulo="Vencidos" valor={String(d.indicadores.vencidos)} destaque={d.indicadores.vencidos > 0} />
            <Kpi rotulo="Sem responsável" valor={String(d.indicadores.sem_dono)} destaque={d.indicadores.sem_dono > 0} />
            <Kpi rotulo="Meus casos" valor={String(d.indicadores.meus)} />
            <Kpi rotulo="Tempo médio de resolução" valor={d.indicadores.horas_medias_resolucao == null ? 'N/D' : `${d.indicadores.horas_medias_resolucao} h`} detalhe={`${d.indicadores.resolvidos} resolvido(s)`} />
          </div>
          {d.agenda.length > 0 && (
            <Cartao titulo="Próximos atendimentos">
              <ul className="text-sm">{d.agenda.map((a, i) => <li key={i}>{dataHora(a.quando)} · {a.nome} · {a.texto} <span className="nota">({a.por})</span></li>)}</ul>
            </Cartao>)}
          <Cartao titulo="Casos" icone={LifeBuoy} acao={<select aria-label="Filtro de casos" className="campo w-auto" value={filtro} onChange={(e) => setFiltro(e.target.value)}>
            <option value="abertos">Abertos</option><option value="meus">Meus</option><option value="sem_dono">Sem responsável</option><option value="todos">Todos</option></select>}>
            {!casos.length ? <Vazio texto="Nenhum caso neste filtro." /> : <div className="space-y-2">{casos.map((c) => <CartaoCaso key={c.id} c={c} d={d} fazer={fazer} enviando={acao.enviando} abrirDetalhe={abrirDetalhe} />)}</div>}
          </Cartao>
          <Detalhes titulo="Trilhas de intervenção">
            <div className="space-y-2">{d.trilhas.map((t) => <Trilha key={t.motivo} t={t} editar={d.pode_trilhas} fazer={fazer} enviando={acao.enviando} />)}</div>
          </Detalhes>
        </div>)}
    </>
  );
}

export function CartaoCaso({ c, d, fazer, enviando, abrirDetalhe }: { c: Caso; d: Casos; fazer: Fazer; enviando: boolean; abrirDetalhe?: (id: number) => void }) {
  const [txt, setTxt] = useState(''); const [quando, setQuando] = useState(''); const [dest, setDest] = useState('');
  const aberto = ['aberto', 'em_atendimento'].includes(c.status);
  const meu = c.responsavel_id === d.eu;
  const passo = c.passos && c.passos_concluidos < c.passos.length ? c.passos[c.passos_concluidos] : null;
  const ir = (acaoCaso: string, msg: string, extra?: { agendado?: string; resp?: string }) => void fazer(async () => {
    await api.atenderCaso(c.id, acaoCaso, txt || undefined, extra?.agendado, extra?.resp); setTxt(''); setQuando(''); setDest(''); return msg; });
  return (
    <details className={`rounded-lg border p-3 text-sm ${c.vencido ? 'border-erro/50' : 'border-linha'}`}>
      <summary className="cursor-pointer">
        <span className="font-medium">{c.nome}</span> · {rotulo(c.motivo)} <Chip tipo={c.prioridade === 'alta' ? 'erro' : c.prioridade === 'media' ? 'pend' : undefined}>{rotulo(c.prioridade)}</Chip>
        <Chip tipo={c.status === 'resolvido' ? 'ok' : aberto ? 'tec' : undefined}>{rotulo(c.status)}</Chip>{c.vencido && <Chip tipo="erro">vencido</Chip>}
        <span className="nota"> · {c.responsavel ?? 'sem responsável'} · prazo {dataHora(c.prazo)}</span>
      </summary>
      <div className="mt-2 space-y-2">
        <p>{abrirDetalhe && <button className="text-tec hover:underline" onClick={() => abrirDetalhe(c.oportunidade_id)}>Abrir ficha</button>} · {c.curso} · {c.origem === 'rematricula' ? 'aberto automaticamente pela recusa de rematrícula' : 'aberto pela equipe'}</p>
        {c.passos && <ol className="list-decimal pl-5">{c.passos.map((p, i) => <li key={i} className={i < c.passos_concluidos ? 'text-ok line-through' : ''}>{p}</li>)}</ol>}
        <ul className="border-l-2 border-linha pl-3 text-xs">{c.eventos.map((e, i) => <li key={i}>{dataHora(e.em)} · {e.por} · {rotulo(e.tipo === 'abertura' ? 'aberto' : e.tipo)}: {e.texto}{e.agendado_para ? ` (para ${dataHora(e.agendado_para)})` : ''}</li>)}</ul>
        {c.resolucao && <p>Desfecho: {c.resolucao}</p>}
        {d.pode_atender && aberto && (!c.responsavel_id
          ? <button className="btn btn-sec btn-peq" disabled={enviando} onClick={() => ir('assumir', 'Caso assumido.')}>Assumir caso</button>
          : (meu || d.pode_trilhas) && (
            <div className="space-y-2">
              <Campo rotulo={passo ? `Registro (próximo passo: ${passo})` : 'Registro'}><textarea className="campo" value={txt} onChange={(e) => setTxt(e.target.value)} /></Campo>
              <div className="flex flex-wrap items-end gap-2">
                {passo && <button className="btn btn-ok btn-peq" disabled={enviando || txt.trim().length < 5} onClick={() => ir('passo', 'Passo concluído.')}>Concluir passo</button>}
                <button className="btn btn-sec btn-peq" disabled={enviando || txt.trim().length < 2} onClick={() => ir('nota', 'Nota registrada.')}>Registrar nota</button>
                <Campo rotulo="Agendar para"><input className="campo" type="datetime-local" value={quando} onChange={(e) => setQuando(e.target.value)} /></Campo>
                <button className="btn btn-sec btn-peq" disabled={enviando || !quando} onClick={() => ir('agendar', 'Atendimento agendado.', { agendado: new Date(quando).toISOString() })}>Agendar</button>
                <Campo rotulo="Encaminhar para"><select className="campo" value={dest} onChange={(e) => setDest(e.target.value)}><option value="">Escolher…</option>
                  {d.equipe.filter((p) => p.id !== c.responsavel_id).map((p) => <option key={p.id} value={p.id}>{p.nome}</option>)}</select></Campo>
                <button className="btn btn-sec btn-peq" disabled={enviando || !dest || txt.trim().length < 5} onClick={() => ir('encaminhar', 'Caso encaminhado.', { resp: dest })}>Encaminhar</button>
                <button className="btn btn-ok btn-peq" disabled={enviando || txt.trim().length < 10} onClick={() => ir('resolver', 'Caso resolvido.')}>Resolver</button>
                {d.pode_trilhas && <button className="btn btn-fantasma btn-peq" disabled={enviando || txt.trim().length < 5} onClick={() => ir('cancelar', 'Caso cancelado.')}>Cancelar caso</button>}
              </div>
            </div>))}
      </div>
    </details>
  );
}

function Trilha({ t, editar, fazer, enviando }: { t: Casos['trilhas'][number]; editar: boolean; fazer: Fazer; enviando: boolean }) {
  const { ies } = useSessao();
  const [passos, setPassos] = useState(t.passos.join('\n')); const [prazo, setPrazo] = useState(String(t.prazo_horas)); const [papel, setPapel] = useState(t.papel_responsavel);
  return (
    <div className="rounded-lg border border-linha p-2 text-sm">
      <p className="font-medium">{rotulo(t.motivo)} · {t.nome} <span className="nota">· prazo {t.prazo_horas} h · {rotulo(t.papel_responsavel)}</span></p>
      {!editar ? <ol className="list-decimal pl-5">{t.passos.map((p, i) => <li key={i}>{p}</li>)}</ol> : (
        <div className="mt-1 grid gap-2 sm:grid-cols-4">
          <Campo rotulo="Passos (um por linha)" className="sm:col-span-2"><textarea className="campo" value={passos} onChange={(e) => setPassos(e.target.value)} /></Campo>
          <Campo rotulo="Prazo (horas)"><input className="campo" type="number" min={4} max={720} value={prazo} onChange={(e) => setPrazo(e.target.value)} /></Campo>
          <Campo rotulo="Quem atende"><select className="campo" value={papel} onChange={(e) => setPapel(e.target.value)}>{['secretaria', 'coordenador', 'financeiro', 'gestor'].map((p) => <option key={p} value={p}>{rotulo(p)}</option>)}</select></Campo>
          <div><button className="btn btn-sec btn-peq" disabled={enviando} onClick={() => void fazer(async () => {
            await api.salvarTrilha(ies!, t.motivo, { passos: passos.split('\n').map((x) => x.trim()).filter(Boolean), prazo_horas: Number(prazo), papel_responsavel: papel }); return 'Trilha atualizada.'; })}>Salvar trilha</button></div>
        </div>)}
    </div>
  );
}
