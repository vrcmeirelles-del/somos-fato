// Seções do CRM avançado na ficha da oportunidade (migração 10). Só aparecem quando o banco devolve os campos novos.
import { AlertTriangle, CalendarClock, FileText, Gauge, Link2, MessageSquarePlus, ShieldQuestion, UserCog, Workflow } from 'lucide-react';
import { baixarBase64, lerBase64 } from '../lib/arquivo';
import { useState } from 'react';
import { descreverEvento } from '../pages/Auditoria';
import { api } from '../lib/api';
import { CATEGORIAS_OBJECAO, TIPOS_INTERACAO, linhaDoTempo, relativo } from '../lib/crm';
import { dataHora, pct, rotulo } from '../lib/formato';
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

// Funil da oportunidade (migração 13): versão fixa, subetapa atual, roteiro, SLA, cadência e meta da forma de ingresso.
export function FunilNaFicha({ op, versaoOp, podeEditar, fazer, enviando }: { op: number; versaoOp: number; podeEditar: boolean; fazer: Fazer; enviando: boolean }) {
  const f = useCarregar(() => api.funilOportunidade(op).catch(() => null), [op, versaoOp]);
  const d = f.dados;
  if (!d?.funil) return null;
  return (
    <section aria-label="Funil comercial" className="mt-4 rounded-xl border border-linha p-3">
      <H icone={Workflow}>Funil comercial</H>
      <p className="nota mb-1">{d.funil} · versão {d.versao}{d.versao_status === 'arquivada' ? ' (arquivada: a oportunidade segue a versão em que nasceu)' : ''}
        {d.meta_conversao_forma != null && ` · meta de conversão da forma de ingresso: ${pct(Number(d.meta_conversao_forma))}`}</p>
      {d.atual ? (
        <>
          <p className="text-sm">Etapa atual: <strong>{d.atual.nome}</strong>{d.atual.sla_horas ? <Chip>SLA {d.atual.sla_horas} h</Chip> : null}</p>
          {(d.subetapas?.length ?? 0) > 1 && (
            <div className="my-2 flex flex-wrap gap-1.5" role="group" aria-label="Subetapas">
              {d.subetapas!.map((s) => (
                <button key={s.ordem} className={`btn btn-peq ${s.ordem === d.etapa_ordem ? '' : 'btn-sec'}`} aria-pressed={s.ordem === d.etapa_ordem}
                  disabled={!podeEditar || enviando || s.ordem === d.etapa_ordem}
                  onClick={() => void fazer(async () => { await api.moverSubetapa(op, s.ordem, d.versao_op!); return `Subetapa: ${s.nome}.`; })}>{s.nome}</button>))}
            </div>)}
          {d.atual.roteiro && <div className="my-2 rounded-lg bg-tec-50 px-3 py-2 text-sm"><span className="text-xs font-semibold uppercase tracking-wide text-tec-600">Roteiro</span>
            <p className="whitespace-pre-line">{d.atual.roteiro}</p></div>}
          {(d.cadencia?.length ?? 0) > 0 && (
            <ol className="text-xs text-suave">{d.cadencia!.map((c) => <li key={c.passo}>Contato {c.passo} · dia {c.dia} · {rotulo(c.canal)}: {c.descricao}</li>)}</ol>)}
          {(d.cadencia?.length ?? 0) > 0 && <p className="nota mt-1">Cadência é guia de trabalho: registre cada contato em "Registrar contato"; nada é enviado automaticamente.</p>}
        </>
      ) : <p className="nota">Etapa encerrada: sem subetapa.</p>}
    </section>
  );
}

// P4 na ficha: documentos (checklist, envio, download auditado, revisão), link do portal e mensagem para envio manual.
export function DocumentosNaFicha({ op, fazer, enviando }: { op: number; fazer: Fazer; enviando: boolean }) {
  const [recarga, setRecarga] = useState(0);
  const d = useCarregar(() => api.documentos(op).catch(() => null), [op, recarga]);
  if (!d.dados) return null;
  const f2: Fazer = (fn) => fazer(async () => { const t = await fn(); setRecarga((n) => n + 1); return t; });
  return (
    <section aria-label="Documentos" className="mt-4 rounded-xl border border-linha p-3">
      <H icone={FileText}>Documentos</H>
      <p className="nota mb-1">{d.dados.completo ? 'Checklist obrigatório aprovado.' : 'Checklist obrigatório incompleto.'}{d.dados.exigido_para_validar ? ' A validação documental exige o checklist aprovado.' : ''}</p>
      <ul className="space-y-1 text-sm">{d.dados.checklist.map((i) => (
        <li key={i.tipo} className="flex flex-wrap items-center gap-2">
          <span>{i.descricao}{i.obrigatorio ? '' : ' (opcional)'}</span>
          {i.documento ? <Chip tipo={i.documento.status === 'aprovado' ? 'ok' : i.documento.status === 'recusado' ? 'erro' : 'pend'}>{rotulo(i.documento.status)} · {i.documento.enviado_por_tipo}</Chip> : <Chip>não enviado</Chip>}
          {i.documento && d.dados!.pode_revisar && <>
            <button className="btn btn-fantasma btn-peq" disabled={enviando} onClick={() => void f2(async () => { const r = await api.baixarDocumento(i.documento!.id); baixarBase64(r.nome_arquivo, r.mime, r.base64); return 'Download registrado na auditoria.'; })}>Baixar</button>
            {i.documento.status === 'enviado' && <>
              <button className="btn btn-ok btn-peq" disabled={enviando} onClick={() => void f2(async () => { await api.revisarDocumento(i.documento!.id, 'aprovado'); return 'Documento aprovado.'; })}>Aprovar</button>
              <button className="btn btn-sec btn-peq" disabled={enviando} onClick={() => { const m = window.prompt('Motivo da recusa (o candidato verá):'); if (m) void f2(async () => { await api.revisarDocumento(i.documento!.id, 'recusado', m); return 'Documento recusado.'; }); }}>Recusar</button></>}</>}
          {i.documento?.status !== 'aprovado' && (
            <label className="btn btn-sec btn-peq cursor-pointer">Enviar<input type="file" className="sr-only" accept="application/pdf,image/jpeg,image/png" disabled={enviando} onChange={(e) => {
              const arq = e.target.files?.[0]; if (!arq) return; void f2(async () => { await api.enviarDocumento(op, i.tipo, arq.name, await lerBase64(arq)); return 'Documento enviado.'; }); }} /></label>)}
        </li>))}</ul>
    </section>
  );
}

export function AcoesCandidato({ op, ies, fazer, enviando }: { op: number; ies: number; fazer: Fazer; enviando: boolean }) {
  const [link, setLink] = useState<string | null>(null);
  const [texto, setTexto] = useState<string | null>(null);
  const modelos = useCarregar(() => api.comunicacao(ies).then((c) => c.modelos.filter((m) => m.ativo)).catch(() => []), [ies]);
  return (
    <section aria-label="Contato com o candidato" className="mt-4 rounded-xl border border-linha p-3">
      <H icone={Link2}>Portal e mensagens</H>
      <div className="flex flex-wrap items-end gap-2">
        <button className="btn btn-sec btn-peq" disabled={enviando} onClick={() => { if (window.confirm('Gerar novo link do portal? O link anterior deixa de funcionar.'))
          void fazer(async () => { const r = await api.gerarAcessoPortal(op); setLink(`${location.origin}/portal#${r.token}`); return `Link gerado (válido por ${r.validade_dias} dias). Envie você mesmo ao candidato.`; }); }}>Gerar link do portal</button>
        {(modelos.dados?.length ?? 0) > 0 && <Campo rotulo="Mensagem para envio manual"><select className="campo" defaultValue="" onChange={(e) => { const id = Number(e.target.value); if (!id) return;
          void fazer(async () => { const r = await api.mensagemManual(op, id); setTexto(`${r.assunto ? `${r.assunto}\n\n` : ''}${r.texto}`); return `Texto pronto para ${rotulo(r.canal)} (envio manual).`; }); }}>
          <option value="">Escolher modelo…</option>{modelos.dados!.map((m) => <option key={m.id} value={m.id}>{m.nome} · {rotulo(m.canal)}</option>)}</select></Campo>}
      </div>
      {link && <p className="mt-2 break-all rounded bg-fundo p-2 text-xs">{link} <button className="btn btn-fantasma btn-peq" onClick={() => void navigator.clipboard?.writeText(link)}>Copiar</button></p>}
      {texto && <p className="mt-2 whitespace-pre-line rounded bg-fundo p-2 text-xs">{texto} <button className="btn btn-fantasma btn-peq" onClick={() => void navigator.clipboard?.writeText(texto)}>Copiar</button></p>}
      <p className="nota mt-1">O sistema não envia mensagens: o link e o texto são copiados e enviados pela equipe pelo canal autorizado pelo titular.</p>
    </section>
  );
}
