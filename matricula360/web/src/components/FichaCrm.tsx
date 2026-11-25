// Seções do CRM avançado na ficha da oportunidade (migração 10). Só aparecem quando o banco devolve os campos novos.
import { AlertTriangle, CalendarClock, Gauge, MessageSquarePlus, ShieldQuestion, UserCog } from 'lucide-react';
import { useState } from 'react';
import { descreverEvento } from '../pages/Auditoria';
import { api } from '../lib/api';
import { CATEGORIAS_OBJECAO, TIPOS_INTERACAO, linhaDoTempo, relativo } from '../lib/crm';
import { dataHora, rotulo } from '../lib/formato';
import { useCarregar } from '../lib/hooks';
import type { Detalhe } from '../lib/tipos';
import { useSessao } from './Layout';
import { Campo, Chip } from './ui';

type Fazer = (fn: () => Promise<string>) => Promise<void>;
const H = ({ icone: I, children }: { icone: typeof Gauge; children: string }) => (
  <h3 className="mb-1.5 flex items-center gap-1.5 font-semibold text-marinho"><I className="h-4 w-4 text-tec" aria-hidden />{children}</h3>
);
// datetime-local exige horário local sem fuso; o servidor recebe ISO com fuso.
const localPadrao = () => { const d = new Date(Date.now() + 24 * 3600e3); d.setMinutes(0, 0, 0); return new Date(d.getTime() - d.getTimezoneOffset() * 60e3).toISOString().slice(0, 16); };

export function PainelScore({ d }: { d: Detalhe }) {
  if (!d.score) return null;
  return (
    <section aria-label="Score de priorização" className="rounded-xl border border-linha bg-fundo p-3">
      <H icone={Gauge}>Score de priorização</H>
      <p><strong className="text-2xl text-marinho">{d.score.score ?? '—'}</strong><span className="nota"> /100 · regra {d.score.versao}</span></p>
      <ul className="mt-1 text-xs text-suave">{d.score.razoes.map((r) => <li key={r}>{r}</li>)}</ul>
      <p className="nota mt-1 italic">{d.score.aviso}</p>
    </section>
  );
}

export function AlertaDuplicidade({ d }: { d: Detalhe }) {
  const dup = d.possiveis_duplicidades ?? [];
  if (!dup.length) return null;
  return (
    <p role="alert" className="my-2 flex items-start gap-2 rounded-lg bg-amber-50 px-3 py-2 text-sm text-alerta">
      <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />
      <span>Possível duplicidade: {dup.length} outro(s) cadastro(s) com o mesmo nome ({dup.map((x) => [x.email, x.telefone].filter(Boolean).join(' / ') || `pessoa #${x.pessoa_id}`).join('; ')}). Nada foi mesclado: confira antes de seguir.</span>
    </p>
  );
}

export function Relacionamento({ d, fazer, enviando, podeEditar }: { d: Detalhe; fazer: Fazer; enviando: boolean; podeEditar: boolean }) {
  const op = d.oportunidade.id;
  const [tipo, setTipo] = useState<string>('ligacao'); const [resumo, setResumo] = useState('');
  const [cat, setCat] = useState<string>('preco'); const [desc, setDesc] = useState('');
  const [quando, setQuando] = useState(localPadrao); const [agDesc, setAgDesc] = useState(''); const [canal, setCanal] = useState('');
  const [trat, setTrat] = useState<Record<number, string>>({});
  const abertas = d.tarefas.filter((t) => t.status === 'aberta');
  return (
    <div className="grid gap-4 sm:grid-cols-2">
      <section>
        <H icone={MessageSquarePlus}>Registrar contato</H>
        {podeEditar ? (
          <form className="flex flex-col gap-2" onSubmit={(e) => { e.preventDefault(); void fazer(async () => { await api.registrarInteracao(op, tipo, resumo); setResumo(''); return 'Interação registrada.'; }); }}>
            <Campo rotulo="Tipo"><select className="campo" value={tipo} onChange={(e) => setTipo(e.target.value)}>{TIPOS_INTERACAO.map((t) => <option key={t} value={t}>{rotulo(t)}</option>)}</select></Campo>
            <Campo rotulo="Resumo do contato"><textarea className="campo min-h-[60px]" required minLength={3} maxLength={1000} value={resumo} onChange={(e) => setResumo(e.target.value)} /></Campo>
            <button className="btn btn-peq self-start" disabled={enviando}>Registrar interação</button>
            <p className="nota">Registro interno. Nenhuma mensagem é enviada ao candidato.</p>
          </form>
        ) : <p className="nota">Seu perfil não registra contatos.</p>}
        <H icone={CalendarClock}>Agenda</H>
        {abertas.length ? <ul className="mb-2 text-sm">{abertas.map((t) => (
          <li key={t.id} className={`border-l-[3px] pl-2.5 ${t.atrasada ? 'border-erro' : 'border-linha'}`}>
            {rotulo(t.tipo)}{t.canal ? ` · ${t.canal}` : ''} · {dataHora(t.vence_em)} ({relativo(t.vence_em)}){t.atrasada && <Chip tipo="erro">atrasada</Chip>}
            {t.descricao && <span className="block text-xs text-suave">{t.descricao}</span>}
          </li>))}</ul> : <p className="nota mb-2">Nenhuma tarefa aberta.</p>}
        {podeEditar && (
          <form className="flex flex-wrap items-end gap-2" onSubmit={(e) => { e.preventDefault(); void fazer(async () => {
            await api.agendar(op, new Date(quando).toISOString(), agDesc, canal || undefined); setAgDesc(''); return 'Agendamento criado.'; }); }}>
            <Campo rotulo="Quando"><input className="campo" type="datetime-local" required value={quando} onChange={(e) => setQuando(e.target.value)} /></Campo>
            <Campo rotulo="Canal"><select className="campo" value={canal} onChange={(e) => setCanal(e.target.value)}><option value="">—</option>{['telefone', 'whatsapp', 'email'].map((c) => <option key={c}>{c}</option>)}</select></Campo>
            <Campo rotulo="O que fazer" className="grow"><input className="campo" required minLength={3} maxLength={300} value={agDesc} onChange={(e) => setAgDesc(e.target.value)} /></Campo>
            <button className="btn btn-peq" disabled={enviando}>Agendar</button>
          </form>
        )}
      </section>
      <section>
        <H icone={ShieldQuestion}>Objeções</H>
        {(d.objecoes ?? []).length ? <ul className="mb-2 text-sm">{d.objecoes!.map((o) => (
          <li key={o.id} className="mb-2 border-l-[3px] border-linha pl-2.5">
            <Chip tipo={o.status === 'superada' ? 'ok' : o.status === 'aberta' ? 'pend' : 'erro'}>{rotulo(o.status)}</Chip><strong>{rotulo(o.categoria)}</strong>: {o.descricao}
            {o.tratamento && <span className="block text-xs text-suave">Tratamento: {o.tratamento}</span>}
            {podeEditar && o.status === 'aberta' && (
              <span className="mt-1 flex flex-wrap gap-1.5">
                <input className="campo grow text-xs" aria-label={`Tratamento da objeção ${o.id}`} placeholder="Como foi tratada" value={trat[o.id] ?? ''} onChange={(e) => setTrat({ ...trat, [o.id]: e.target.value })} />
                {(['superada', 'nao_superada'] as const).map((st) => (
                  <button key={st} className={`btn btn-peq ${st === 'superada' ? 'btn-ok' : 'btn-sec'}`} disabled={enviando || (trat[o.id] ?? '').trim().length < 3}
                    onClick={() => void fazer(async () => { await api.tratarObjecao(o.id, st, trat[o.id] ?? ''); return `Objeção marcada como ${rotulo(st).toLowerCase()}.`; })}>{rotulo(st)}</button>
                ))}
              </span>
            )}
          </li>))}</ul> : <p className="nota mb-2">Nenhuma objeção registrada.</p>}
        {podeEditar && (
          <form className="flex flex-wrap items-end gap-2" onSubmit={(e) => { e.preventDefault(); void fazer(async () => { await api.registrarObjecao(op, cat, desc); setDesc(''); return 'Objeção registrada.'; }); }}>
            <Campo rotulo="Categoria"><select className="campo" value={cat} onChange={(e) => setCat(e.target.value)}>{CATEGORIAS_OBJECAO.map((c) => <option key={c} value={c}>{rotulo(c)}</option>)}</select></Campo>
            <Campo rotulo="Objeção" className="grow"><input className="campo" required minLength={3} maxLength={500} value={desc} onChange={(e) => setDesc(e.target.value)} /></Campo>
            <button className="btn btn-peq" disabled={enviando}>Registrar objeção</button>
          </form>
        )}
      </section>
    </div>
  );
}

export function Reatribuir({ d, fazer, enviando }: { d: Detalhe; fazer: Fazer; enviando: boolean }) {
  const { ies } = useSessao();
  const at = useCarregar(() => api.atendentes(ies!, d.curso.id), [ies, d.curso.id]);
  const [para, setPara] = useState(''); const [motivo, setMotivo] = useState('');
  const opcoes = (at.dados ?? []).filter((a) => a.nome !== d.oportunidade.responsavel);
  return (
    <section className="mt-4">
      <H icone={UserCog}>Reatribuir responsável</H>
      {at.erro ? <p className="nota">{at.erro.message}</p> : (
        <form className="flex flex-wrap items-end gap-2" onSubmit={(e) => { e.preventDefault(); void fazer(async () => {
          const r = await api.reatribuir(d.oportunidade.id, para, motivo); setPara(''); setMotivo('');
          return `Responsável alterado; ${r.tarefas_transferidas} tarefa(s) transferida(s).`; }); }}>
          <Campo rotulo="Novo responsável"><select className="campo" required value={para} onChange={(e) => setPara(e.target.value)}>
            <option value="">Selecione…</option>{opcoes.map((a) => <option key={a.id} value={a.id}>{a.nome}</option>)}</select></Campo>
          <Campo rotulo="Motivo" className="grow"><input className="campo" required minLength={3} maxLength={200} value={motivo} onChange={(e) => setMotivo(e.target.value)} /></Campo>
          <button className="btn btn-peq btn-sec" disabled={enviando || !para}>Reatribuir</button>
        </form>
      )}
    </section>
  );
}

const COR = { auditoria: 'border-linha', interacao: 'border-tec-400', objecao: 'border-alerta', proposta: 'border-ok' } as const;
const TIPO = { auditoria: 'Sistema', interacao: 'Contato', objecao: 'Objeção', proposta: 'Proposta' } as const;
export function LinhaDoTempo({ d }: { d: Detalhe }) {
  const ev = linhaDoTempo(d, (acao, dados) => descreverEvento({ acao, dados, entidade: 'oportunidade', entidade_id: String(d.oportunidade.id) }));
  return (
    <section className="mt-4">
      <h3 className="font-semibold">Linha do tempo</h3>
      <ol className="text-sm">{ev.map((e) => (
        <li key={e.chave} className={`mb-1.5 border-l-[3px] pl-2.5 ${COR[e.tipo]}`}>
          <span className="text-xs text-suave">{dataHora(e.em)} · {e.por ?? 'sistema'} · {TIPO[e.tipo]}{e.tipo !== 'auditoria' && e.codigo ? ` (${rotulo(e.codigo)})` : ''}</span>
          <span className="block">{e.titulo}{e.tipo === 'auditoria' && <code className="ml-1.5 text-[10px] text-suave">{e.codigo}</code>}</span>
        </li>))}</ol>
    </section>
  );
}
