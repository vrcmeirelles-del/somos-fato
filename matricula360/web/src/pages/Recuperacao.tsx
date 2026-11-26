import { ListChecks, RefreshCcw, Timer, UserSearch } from 'lucide-react';
import { useState } from 'react';
import { useSessao } from '../components/Layout';
import { Aviso, Campo, Cartao, Chip, Detalhes, Estado, Mensagem, Titulo, Valor, Vazio } from '../components/ui';
import { api } from '../lib/api';
import { centavos, moeda, ND, pct, rotulo } from '../lib/formato';
import { useAcao, useCarregar } from '../lib/hooks';
import type { ErroApi } from '../lib/supabase';
import type { Protocolo, Sprint } from '../lib/tipos';

const TIPOS = ['recuperacao_base', 'reingresso', 'oferta_educacional', 'convenio', 'webinar', 'evento', 'indicacao', 'embaixadores', 'prospeccao_autorizada'];
const dt = (d: string) => new Date(`${d.slice(0, 10)}T12:00:00`).toLocaleDateString('pt-BR');
type Fazer = (fn: () => Promise<string>) => Promise<void>;

export function Recuperacao({ abrirDetalhe }: { abrirDetalhe: (id: number) => void }) {
  const { ies } = useSessao();
  const [recarga, setRecarga] = useState(0);
  const r = useCarregar(() => api.recuperacao(ies!), [ies, recarga]);
  const acao = useAcao();
  const fazer: Fazer = (fn) => acao.executar(async () => { const t = await fn(); setRecarga((n) => n + 1); return t; });
  const d = r.dados;
  return (
    <>
      <Titulo titulo="Recuperação e Aceleração" subtitulo="Protocolos de recuperação da base perdida, reingresso e ações de aceleração, com sprints e reavaliação." />
      {(r.erro as ErroApi | null)?.codigo === 'PGRST202' ? <Vazio texto="Disponível após a migração 15 do banco." /> : <Estado carregando={r.carregando && !d} erro={r.erro} />}
      <Mensagem m={acao.mensagem} />
      {d && (
        <div className="space-y-5">
          <Aviso>Elegibilidade ({d.regra}): {d.elegibilidade} Nada é enviado automaticamente: cada contato é registrado pelo atendente.</Aviso>
          {d.pode_gerir && <NovoProtocolo sprints={d.sprints} fazer={fazer} enviando={acao.enviando} />}
          {d.pode_gerir && d.protocolos.some((p) => ['planejado', 'em_execucao'].includes(p.status)) && <SelecionarBase protocolos={d.protocolos} fazer={fazer} enviando={acao.enviando} />}
          {!d.protocolos.length && <Vazio texto="Nenhum protocolo." detalhe={d.pode_gerir ? 'Crie um protocolo e selecione a base elegível.' : 'O gestor cria os protocolos e atribui a base.'} />}
          {d.protocolos.map((p) => <CartaoProtocolo key={p.id} p={p} gerir={d.pode_gerir} fazer={fazer} enviando={acao.enviando} abrirDetalhe={abrirDetalhe} />)}
          <Sprints sprints={d.sprints} gerir={d.pode_gerir} fazer={fazer} enviando={acao.enviando} />
        </div>
      )}
    </>
  );
}

function NovoProtocolo({ sprints, fazer, enviando }: { sprints: Sprint[]; fazer: Fazer; enviando: boolean }) {
  const { ies, estrutura } = useSessao();
  const vazio = { nome: '', tipo: 'recuperacao_base', responsavel: '', prazo: '', meta: '', custo: '', coorte_destino: estrutura?.coortes[0] ?? '', carencia_dias: '30', checklist: '', sprint_id: '' };
  const [f, setF] = useState(vazio);
  return (
    <Detalhes titulo="Novo protocolo">
      <form className="grid gap-2 sm:grid-cols-4" onSubmit={(e) => { e.preventDefault(); void fazer(async () => {
        await api.salvarProtocolo(ies!, { ...f, meta: Number(f.meta), custo_centavos: f.custo ? centavos(f.custo) : 0, carencia_dias: Number(f.carencia_dias),
          checklist: f.checklist.split('\n').map((x) => x.trim()).filter(Boolean) });
        setF(vazio); return 'Protocolo criado.'; }); }}>
        <Campo rotulo="Nome" className="sm:col-span-2"><input className="campo" required minLength={3} maxLength={100} value={f.nome} onChange={(e) => setF({ ...f, nome: e.target.value })} /></Campo>
        <Campo rotulo="Tipo"><select className="campo" value={f.tipo} onChange={(e) => setF({ ...f, tipo: e.target.value })}>{TIPOS.map((t) => <option key={t} value={t}>{rotulo(t)}</option>)}</select></Campo>
        <Campo rotulo="Responsável"><input className="campo" required minLength={2} value={f.responsavel} onChange={(e) => setF({ ...f, responsavel: e.target.value })} /></Campo>
        <Campo rotulo="Prazo"><input className="campo" type="date" required value={f.prazo} onChange={(e) => setF({ ...f, prazo: e.target.value })} /></Campo>
        <Campo rotulo="Meta (reativações)"><input className="campo" type="number" min={1} required value={f.meta} onChange={(e) => setF({ ...f, meta: e.target.value })} /></Campo>
        <Campo rotulo="Custo previsto (R$)"><input className="campo" inputMode="decimal" value={f.custo} onChange={(e) => setF({ ...f, custo: e.target.value })} /></Campo>
        <Campo rotulo="Coorte de destino"><input className="campo" pattern="\d{4}\.[12]" required value={f.coorte_destino} onChange={(e) => setF({ ...f, coorte_destino: e.target.value })} /></Campo>
        <Campo rotulo="Carência após a perda (dias)"><input className="campo" type="number" min={0} max={365} value={f.carencia_dias} onChange={(e) => setF({ ...f, carencia_dias: e.target.value })} /></Campo>
        <Campo rotulo="Sprint"><select className="campo" value={f.sprint_id} onChange={(e) => setF({ ...f, sprint_id: e.target.value })}><option value="">—</option>
          {sprints.filter((s) => s.status !== 'encerrada').map((s) => <option key={s.id} value={s.id}>{s.nome}</option>)}</select></Campo>
        <Campo rotulo="Checklist (um item por linha)" className="sm:col-span-2"><textarea className="campo min-h-[60px]" value={f.checklist} onChange={(e) => setF({ ...f, checklist: e.target.value })} /></Campo>
        <div className="flex items-end"><button className="btn" disabled={enviando}>Criar protocolo</button></div>
      </form>
    </Detalhes>
  );
}

function SelecionarBase({ protocolos, fazer, enviando }: { protocolos: Protocolo[]; fazer: Fazer; enviando: boolean }) {
  const { ies } = useSessao();
  const abertos = protocolos.filter((p) => ['planejado', 'em_execucao'].includes(p.status));
  const [prot, setProt] = useState(String(abertos[0]?.id ?? ''));
  const [motivo, setMotivo] = useState('');
  const [marcados, setMarcados] = useState<number[]>([]);
  const p = abertos.find((x) => String(x.id) === prot);
  const base = useCarregar(() => (p ? api.recuperaveis(ies!, p.carencia_dias, motivo || undefined) : Promise.resolve([])), [ies, prot, motivo]);
  return (
    <Cartao titulo="Selecionar base perdida (MAIM Recovery)" icone={UserSearch}>
      <div className="mb-2 flex flex-wrap items-end gap-2">
        <Campo rotulo="Protocolo"><select className="campo" value={prot} onChange={(e) => { setProt(e.target.value); setMarcados([]); }}>{abertos.map((x) => <option key={x.id} value={x.id}>{x.nome}</option>)}</select></Campo>
        <Campo rotulo="Motivo da perda contém"><input className="campo" value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="ex.: mensalidade" /></Campo>
      </div>
      <Estado carregando={base.carregando && !base.dados} erro={base.erro} />
      {base.dados?.length ? (
        <div className="tabela max-h-80 overflow-y-auto"><table>
          <thead><tr>{['', 'Candidato', 'Curso / coorte', 'Motivo da perda', 'Perdida há', 'Elegibilidade'].map((h) => <th key={h} scope="col">{h}</th>)}</tr></thead>
          <tbody>{base.dados.map((x) => (
            <tr key={x.id} className={x.elegivel ? '' : 'text-suave'}>
              <td><input type="checkbox" aria-label={`Selecionar ${x.nome}`} disabled={!x.elegivel || x.em_protocolo} checked={marcados.includes(x.id)}
                onChange={(e) => setMarcados(e.target.checked ? [...marcados, x.id] : marcados.filter((y) => y !== x.id))} /></td>
              <td>{x.nome}</td><td>{x.curso} · {x.coorte}</td><td>{x.motivo_perda ?? '—'}</td><td>{x.dias_desde_perda} dia(s)</td>
              <td>{x.em_protocolo ? <Chip tipo="tec">em protocolo</Chip> : x.elegivel ? <Chip tipo="ok">elegível</Chip> : <span className="text-xs">{x.motivo_inelegivel}</span>}</td></tr>))}</tbody>
        </table></div>
      ) : base.dados && <p className="nota">Nenhuma oportunidade perdida no filtro.</p>}
      <button className="btn btn-peq mt-2" disabled={enviando || !marcados.length || !p} onClick={() => void fazer(async () => {
        const r = await api.selecionarRecuperacao(p!.id, marcados); setMarcados([]);
        return `${r.selecionadas} selecionada(s)${r.recusadas.length ? `; ${r.recusadas.length} recusada(s): ${r.recusadas.map((x) => x.motivo).join('; ')}` : ''}.`; })}>
        Incluir {marcados.length || ''} no protocolo</button>
    </Cartao>
  );
}

function CartaoProtocolo({ p, gerir, fazer, enviando, abrirDetalhe }: { p: Protocolo; gerir: boolean; fazer: Fazer; enviando: boolean; abrirDetalhe: (id: number) => void }) {
  const { ies } = useSessao();
  const tratar = (item: number, acao: string, pede: string | null) => {
    const obs = pede ? window.prompt(pede) : undefined;
    if (pede && !obs) return;
    void fazer(async () => { await api.tratarRecuperacao(item, acao, obs ?? undefined); return acao === 'reativar' ? 'Oportunidade reativada; tarefa de recuperação criada.' : `Item ${rotulo(acao === 'contatada' ? 'contatada' : 'descartada').toLowerCase()}.`; });
  };
  return (
    <Cartao titulo={p.nome} icone={RefreshCcw} acao={<span><Chip>{rotulo(p.tipo)}</Chip><Chip tipo={p.status === 'concluido' ? 'ok' : p.vencido ? 'erro' : 'tec'}>{p.vencido ? 'prazo vencido' : rotulo(p.status)}</Chip></span>}>
      <p className="nota mb-2">Responsável: {p.responsavel} · prazo {dt(p.prazo)} · destino {p.coorte_destino} · carência {p.carencia_dias} dia(s)</p>
      <div className="mb-3 grid grid-cols-2 gap-2 text-sm sm:grid-cols-6">
        {[['Selecionadas', p.selecionadas], ['Contatadas', p.contatadas], ['Reativadas', p.reativadas], ['Descartadas', p.descartadas], ['Ingressantes', p.ingressantes]].map(([r, v]) =>
          <div key={r as string}><p className="nota">{r}</p><p className="font-semibold">{v}</p></div>)}
        <div><p className="nota">Meta ({p.meta})</p><p className="font-semibold">{pct(p.atingimento_meta)}</p></div>
      </div>
      {p.custo_centavos != null && <p className="mb-2 text-sm">Custo {moeda(p.custo_centavos)} · por reativação <Valor v={p.custo_por_reativacao_centavos == null ? ND : moeda(p.custo_por_reativacao_centavos)} /></p>}
      {p.checklist.length > 0 && <ul className="mb-3 flex flex-wrap gap-1.5 text-xs">{p.checklist.map((c) => <li key={c} className="flex items-center gap-1 rounded-full bg-fundo px-2 py-0.5"><ListChecks className="h-3 w-3" aria-hidden />{c}</li>)}</ul>}
      {p.itens.length ? (
        <div className="tabela"><table>
          <thead><tr>{['Candidato', 'Curso', 'Motivo da perda', 'Atendente', 'Situação', ''].map((h) => <th key={h} scope="col">{h}</th>)}</tr></thead>
          <tbody>{p.itens.map((i) => (
            <tr key={i.id}><td>{i.nome}</td><td>{i.curso} · {i.coorte_origem}</td><td>{i.motivo_perda ?? '—'}</td><td>{i.atribuido_a ?? '—'}{i.meu && <Chip tipo="tec">você</Chip>}</td>
              <td><Chip tipo={i.status === 'reativada' ? 'ok' : i.status === 'descartada' ? undefined : 'pend'}>{rotulo(i.status)}</Chip>{i.observacao && <span className="block text-xs text-suave">{i.observacao}</span>}</td>
              <td className="whitespace-nowrap">{(i.meu || gerir) && ['selecionada', 'contatada'].includes(i.status) && <>
                <button className="btn btn-sec btn-peq" disabled={enviando} onClick={() => tratar(i.id, 'contatada', 'Resumo do contato:')}>Contato</button>{' '}
                <button className="btn btn-ok btn-peq" disabled={enviando} onClick={() => { if (window.confirm(`Reativar ${i.nome}?`)) tratar(i.id, 'reativar', null); }}>Reativar</button>{' '}
                <button className="btn btn-fantasma btn-peq" disabled={enviando} onClick={() => tratar(i.id, 'descartada', 'Motivo do descarte:')}>Descartar</button></>}
                {i.oportunidade_nova_id && <button className="btn btn-fantasma btn-peq" onClick={() => abrirDetalhe(i.oportunidade_nova_id!)}>Abrir ficha</button>}</td></tr>))}</tbody>
        </table></div>
      ) : <p className="nota">{gerir ? 'Nenhum item: selecione a base elegível acima.' : 'Nenhum item atribuído a você.'}</p>}
      {gerir && ['planejado', 'em_execucao'].includes(p.status) && (
        <div className="mt-3 flex flex-wrap gap-2">
          <button className="btn btn-sec btn-peq" disabled={enviando} onClick={() => {
            const res = window.prompt('Resultado do protocolo (obrigatório para concluir):', p.resultado ?? ''); if (!res) return;
            void fazer(async () => { await api.salvarProtocolo(ies!, { resultado: res, status: 'concluido' }, p.id); return 'Protocolo concluído.'; });
          }}>Concluir com resultado</button>
        </div>)}
    </Cartao>
  );
}

function Sprints({ sprints, gerir, fazer, enviando }: { sprints: Sprint[]; gerir: boolean; fazer: Fazer; enviando: boolean }) {
  const { ies } = useSessao();
  const [f, setF] = useState({ nome: '', objetivo: '', inicio: '', fim: '' });
  const [item, setItem] = useState<Record<number, { entrega: string; responsavel: string }>>({});
  return (
    <Cartao titulo="Sprints de aceleração" icone={Timer}>
      {gerir && (
        <form className="mb-3 flex flex-wrap items-end gap-2" onSubmit={(e) => { e.preventDefault(); void fazer(async () => { await api.salvarSprint(ies!, f); setF({ nome: '', objetivo: '', inicio: '', fim: '' }); return 'Sprint criada.'; }); }}>
          <Campo rotulo="Nova sprint"><input className="campo" required minLength={3} value={f.nome} onChange={(e) => setF({ ...f, nome: e.target.value })} /></Campo>
          <Campo rotulo="Objetivo" className="grow"><input className="campo" required minLength={3} value={f.objetivo} onChange={(e) => setF({ ...f, objetivo: e.target.value })} /></Campo>
          <Campo rotulo="Início"><input className="campo" type="date" required value={f.inicio} onChange={(e) => setF({ ...f, inicio: e.target.value })} /></Campo>
          <Campo rotulo="Fim"><input className="campo" type="date" required value={f.fim} onChange={(e) => setF({ ...f, fim: e.target.value })} /></Campo>
          <button className="btn btn-peq" disabled={enviando}>Criar</button>
        </form>)}
      {!sprints.length && <p className="nota">Nenhuma sprint.</p>}
      {sprints.map((s) => (
        <section key={s.id} className="mb-3 rounded-lg border border-linha p-3">
          <p className="font-semibold text-marinho">{s.nome} <Chip tipo={s.status === 'encerrada' ? 'ok' : 'tec'}>{rotulo(s.status)}</Chip>{s.impedimentos > 0 && <Chip tipo="erro">{s.impedimentos} impedimento(s)</Chip>}</p>
          <p className="nota">{s.objetivo} · {dt(s.inicio)} – {dt(s.fim)}</p>
          {s.reavaliacao && <p className="mt-1 text-sm"><strong>Reavaliação:</strong> {s.reavaliacao}</p>}
          <ul className="mt-2 text-sm">{s.itens.map((i) => (
            <li key={i.id} className="mb-1 flex flex-wrap items-center gap-2">
              {gerir && s.status !== 'encerrada' ? <select className="campo text-xs" aria-label={`Status de ${i.entrega}`} value={i.status} disabled={enviando} onChange={(e) => {
                const st = e.target.value; const imp = st === 'impedido' ? window.prompt('Descreva o impedimento:') : null; if (st === 'impedido' && !imp) return;
                void fazer(async () => { await api.salvarItemSprint(s.id, { status: st, impedimento: imp }, i.id); return 'Entrega atualizada.'; }); }}>
                {['a_fazer', 'fazendo', 'feito', 'impedido'].map((x) => <option key={x} value={x}>{rotulo(x)}</option>)}</select> : <Chip>{rotulo(i.status)}</Chip>}
              <span>{i.entrega} · {i.responsavel}</span>{i.impedimento && <span className="text-xs text-erro">Impedimento: {i.impedimento}</span>}
            </li>))}</ul>
          {gerir && s.status !== 'encerrada' && (
            <div className="mt-2 flex flex-wrap items-end gap-2">
              <input className="campo" aria-label="Nova entrega" placeholder="Entrega" value={item[s.id]?.entrega ?? ''} onChange={(e) => setItem({ ...item, [s.id]: { entrega: e.target.value, responsavel: item[s.id]?.responsavel ?? '' } })} />
              <input className="campo" aria-label="Responsável pela entrega" placeholder="Responsável" value={item[s.id]?.responsavel ?? ''} onChange={(e) => setItem({ ...item, [s.id]: { entrega: item[s.id]?.entrega ?? '', responsavel: e.target.value } })} />
              <button className="btn btn-sec btn-peq" disabled={enviando} onClick={() => void fazer(async () => { await api.salvarItemSprint(s.id, item[s.id] ?? {}); setItem({ ...item, [s.id]: { entrega: '', responsavel: '' } }); return 'Entrega adicionada.'; })}>Adicionar entrega</button>
              {s.status === 'planejada' && <button className="btn btn-sec btn-peq" disabled={enviando} onClick={() => void fazer(async () => { await api.salvarSprint(ies!, { status: 'em_andamento' }, s.id); return 'Sprint iniciada.'; })}>Iniciar</button>}
              <button className="btn btn-peq" disabled={enviando} onClick={() => {
                const r = window.prompt('Reavaliação (o que funcionou, o que não funcionou, próximos passos):'); if (!r) return;
                void fazer(async () => { await api.salvarSprint(ies!, { status: 'encerrada', reavaliacao: r }, s.id); return 'Sprint encerrada com reavaliação.'; });
              }}>Encerrar com reavaliação</button>
            </div>)}
        </section>))}
    </Cartao>
  );
}
