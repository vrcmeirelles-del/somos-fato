import { AlarmClock, GripVertical, Search } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { useSessao } from '../components/Layout';
import { Campo, Chip, Detalhes, Estado, Mensagem, Titulo, Vazio } from '../components/ui';
import { api, temCrmAvancado } from '../lib/api';
import { ETAPAS_ARRASTAVEIS, faixaScore, relativo } from '../lib/crm';
import { linhaImportacao, rotulo } from '../lib/formato';
import { useAcao, useCarregar } from '../lib/hooks';
import type { Etapa, ItemOportunidade, Pagina } from '../lib/tipos';

interface Arrasto { id: number; versao: number; de: Etapa; nome: string }

export function Crm({ abrirDetalhe, versao }: { abrirDetalhe: (id: number) => void; versao: number }) {
  const { ies, estrutura, tem } = useSessao();
  const [coorte, setCoorte] = useState('');
  const [curso, setCurso] = useState('');
  const [forma, setForma] = useState('');
  const [busca, setBusca] = useState('');
  const [termo, setTermo] = useState('');
  const [meus, setMeus] = useState(false);
  const [sla, setSla] = useState(false);
  const [recarga, setRecarga] = useState(0);
  const avancado = useCarregar(() => (ies ? temCrmAvancado(ies) : Promise.resolve(false)), [ies]);
  const m10 = avancado.dados === true;
  const colunas = useCarregar(async () => {
    const etapas = estrutura?.etapas ?? [];
    const f = { coorte: coorte || undefined, curso: curso ? Number(curso) : undefined, porPagina: 50,
      ...(m10 ? { busca: termo || undefined, forma: forma || undefined, somenteMeus: meus, slaAtrasado: sla } : {}) };
    const r = await Promise.all(etapas.map((e) => api.oportunidades(ies!, { ...f, etapa: e })));
    return etapas.map((e, i) => [e, r[i]!] as [Etapa, Pagina<ItemOportunidade>]);
  }, [ies, estrutura, coorte, curso, forma, termo, meus, sla, m10, recarga, versao]);
  const recarregar = () => setRecarga((n) => n + 1);
  const podeMover = tem('comercial', 'gestor');
  const acao = useAcao();
  const [arrasto, setArrasto] = useState<Arrasto | null>(null);
  const [alvo, setAlvo] = useState<Etapa | null>(null);
  const [perda, setPerda] = useState<Arrasto | null>(null);

  const mover = (a: Arrasto, para: Etapa, motivo?: string) => acao.executar(async () => {
    const r = await api.moverEtapa(a.id, para, a.versao, motivo);
    recarregar();
    return `${a.nome}: ${rotulo(a.de)} → ${rotulo(r.etapa)}.`;
  });
  const soltar = (para: Etapa) => {
    const a = arrasto; setArrasto(null); setAlvo(null);
    if (!a || a.de === para) return;
    if (para === 'perdido') { setPerda(a); return; }
    void mover(a, para);
  };
  const filtrosAtivos = Boolean(termo || forma || meus || sla || coorte || curso);

  return (
    <>
      <Titulo titulo="Pipeline (CRM)" subtitulo={podeMover ? 'Arraste o cartão entre etapas ou abra a ficha. Toda transição é validada no servidor.' : 'Oportunidades por etapa do funil.'} />
      {podeMover && <><NovaOportunidade aoCriar={recarregar} /><Importar aoImportar={recarregar} /></>}
      <div className="mb-4 flex flex-wrap items-end gap-3 rounded-xl border border-linha bg-white p-3 shadow-cartao" role="group" aria-label="Busca e filtros do CRM">
        {m10 && (
          <form className="flex items-end gap-1.5" role="search" onSubmit={(e) => { e.preventDefault(); setTermo(busca.trim()); }}>
            <Campo rotulo="Buscar"><input className="campo w-56" type="search" aria-label="Buscar por nome, e-mail ou telefone" placeholder="Nome, e-mail ou telefone"
              value={busca} onChange={(e) => { setBusca(e.target.value); if (!e.target.value) setTermo(''); }} /></Campo>
            <button className="btn btn-sec" type="submit" aria-label="Buscar"><Search className="h-4 w-4" aria-hidden /></button>
          </form>
        )}
        <label className="flex flex-col gap-1 text-xs font-medium text-suave">Coorte
          <select className="campo" aria-label="Coorte" value={coorte} onChange={(e) => setCoorte(e.target.value)}>
            <option value="">Todas as coortes</option>{estrutura?.coortes.map((c) => <option key={c}>{c}</option>)}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-xs font-medium text-suave">Curso
          <select className="campo" aria-label="Curso" value={curso} onChange={(e) => setCurso(e.target.value)}>
            <option value="">Todos os cursos</option>{estrutura?.cursos.map((c) => <option key={c.id} value={c.id}>{c.nome} · {c.turno}</option>)}
          </select>
        </label>
        {m10 && <>
          <label className="flex flex-col gap-1 text-xs font-medium text-suave">Forma de ingresso
            <select className="campo" aria-label="Forma de ingresso" value={forma} onChange={(e) => setForma(e.target.value)}>
              <option value="">Todas</option>{estrutura?.formas_ingresso.map((x) => <option key={x} value={x}>{rotulo(x)}</option>)}
            </select>
          </label>
          <label className="flex items-center gap-1.5 pb-2 text-sm"><input type="checkbox" checked={meus} onChange={(e) => setMeus(e.target.checked)} />Somente meus</label>
          <label className="flex items-center gap-1.5 pb-2 text-sm"><input type="checkbox" checked={sla} onChange={(e) => setSla(e.target.checked)} />SLA vencido</label>
        </>}
        {filtrosAtivos && <button className="btn btn-fantasma btn-peq mb-1" onClick={() => { setTermo(''); setBusca(''); setForma(''); setMeus(false); setSla(false); setCoorte(''); setCurso(''); }}>Limpar filtros</button>}
        {avancado.dados === false && <p className="nota basis-full">Busca, SLA, score e filtros avançados ficam disponíveis após a migração 10 do banco.</p>}
      </div>
      <Mensagem m={acao.mensagem} />
      <Estado carregando={colunas.carregando && !colunas.dados} erro={colunas.erro} />
      {colunas.dados && filtrosAtivos && colunas.dados.every(([, p]) => p.total === 0) && <Vazio texto="Nenhuma oportunidade com estes filtros." detalhe="Ajuste a busca ou limpe os filtros." />}
      <div role="list" className="grid auto-cols-[minmax(230px,1fr)] grid-flow-col gap-2.5 overflow-x-auto pb-2">
        {colunas.dados?.map(([etapa, pag]) => {
          const aceita = podeMover && arrasto != null && arrasto.de !== etapa && ETAPAS_ARRASTAVEIS.includes(etapa);
          return (
            <section key={etapa} role="listitem" aria-label={rotulo(etapa)}
              className={`coluna min-h-[120px] rounded-xl p-2.5 transition ${alvo === etapa && aceita ? 'bg-tec-100 ring-2 ring-tec-400' : 'bg-[#e8eef5]'}`}
              onDragOver={(e) => { if (aceita) { e.preventDefault(); setAlvo(etapa); } }}
              onDragLeave={() => setAlvo((x) => (x === etapa ? null : x))}
              onDrop={(e) => { e.preventDefault(); soltar(etapa); }}>
              <h2 className="mb-2 flex justify-between text-sm font-semibold"><span>{rotulo(etapa)}</span><span>{pag.total}</span></h2>
              {pag.itens.map((o) => <CartaoOportunidade key={o.id} o={o} arrastavel={podeMover && !acao.enviando}
                aoAbrir={() => abrirDetalhe(o.id)} aoIniciar={() => setArrasto({ id: o.id, versao: o.versao, de: o.etapa, nome: o.nome })}
                aoTerminar={() => { setArrasto(null); setAlvo(null); }} />)}
              {pag.total > pag.itens.length && <p className="nota">Exibindo {pag.itens.length} de {pag.total}. Use os filtros para refinar.</p>}
            </section>
          );
        })}
      </div>
      {perda && <MotivoPerda nome={perda.nome} aoCancelar={() => setPerda(null)} aoConfirmar={(m) => { const a = perda; setPerda(null); void mover(a, 'perdido', m); }} />}
    </>
  );
}

function CartaoOportunidade({ o, arrastavel, aoAbrir, aoIniciar, aoTerminar }: { o: ItemOportunidade; arrastavel: boolean; aoAbrir: () => void; aoIniciar: () => void; aoTerminar: () => void }) {
  return (
    <div role="button" tabIndex={0} className="cartao group mb-2 block w-full cursor-pointer rounded-lg border border-linha bg-white p-2 text-left text-sm hover:border-tec-400 focus:outline-none focus:ring-2 focus:ring-tec-100"
      onClick={aoAbrir} onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); aoAbrir(); } }}
      draggable={arrastavel} onDragStart={(e) => { e.dataTransfer.effectAllowed = 'move'; e.dataTransfer.setData('text/plain', String(o.id)); aoIniciar(); }} onDragEnd={aoTerminar}>
      <span className="flex items-start justify-between gap-1">
        <strong>{o.nome}</strong>
        {arrastavel && <GripVertical className="h-4 w-4 shrink-0 text-suave opacity-0 group-hover:opacity-100" aria-hidden />}
      </span>
      <small className="block text-suave">{o.curso} · {o.turno} · {o.coorte}</small>
      <small className="block text-suave">{rotulo(o.forma_ingresso)} · {o.responsavel ?? 'sem responsável'}</small>
      {'sla_atrasado' in o && (
        <span className="mt-1 flex flex-wrap gap-y-1">
          {o.score != null && <Chip tipo={faixaScore(o.score)}><span title="Score de priorização (score-v1). Não decide ingresso.">score {o.score}</span></Chip>}
          {o.sla_atrasado && <Chip tipo="erro"><AlarmClock className="h-3 w-3" aria-hidden />SLA vencido</Chip>}
          <Chip>contato {relativo(o.ultima_interacao_em)}</Chip>
        </span>
      )}
    </div>
  );
}

function MotivoPerda({ nome, aoCancelar, aoConfirmar }: { nome: string; aoCancelar: () => void; aoConfirmar: (m: string) => void }) {
  const dlg = useRef<HTMLDialogElement>(null);
  const [m, setM] = useState('');
  useEffect(() => { const el = dlg.current; if (el && !el.open) el.showModal(); }, []);
  return (
    <dialog ref={dlg} aria-labelledby="perda-titulo" onCancel={(e) => { e.preventDefault(); aoCancelar(); }} className="w-[min(440px,calc(100vw-24px))] rounded-2xl p-5 backdrop:bg-marinho/45">
      <form onSubmit={(e) => { e.preventDefault(); if (m.trim().length >= 3) aoConfirmar(m.trim()); }}>
        <h2 id="perda-titulo" className="text-lg font-semibold text-marinho">Registrar perda</h2>
        <p className="nota mb-3">{nome}. O motivo é obrigatório e fica na auditoria.</p>
        <Campo rotulo="Motivo da perda"><input className="campo" autoFocus required minLength={3} maxLength={200} value={m} onChange={(e) => setM(e.target.value)} /></Campo>
        <div className="mt-4 flex justify-end gap-2">
          <button type="button" className="btn btn-sec" onClick={aoCancelar}>Cancelar</button>
          <button type="submit" className="btn btn-perigo">Registrar perda</button>
        </div>
      </form>
    </dialog>
  );
}

function NovaOportunidade({ aoCriar }: { aoCriar: () => void }) {
  const { ies, estrutura } = useSessao();
  const acao = useAcao();
  const vazio = { nome: '', email: '', telefone: '', curso_id: String(estrutura?.cursos[0]?.id ?? ''), forma_ingresso: 'vestibular', coorte: estrutura?.coortes[0] ?? '2027.1', base_legal: '', origem: '' };
  const [f, setF] = useState(vazio);
  const campo = (k: keyof typeof vazio) => ({ value: f[k], onChange: (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value }) });
  return (
    <Detalhes titulo="Nova oportunidade">
      <form className="flex flex-wrap items-end gap-2" onSubmit={(ev) => { ev.preventDefault(); void acao.executar(async () => {
        const dados: Record<string, unknown> = { ...f, curso_id: Number(f.curso_id) };
        if (!f.email) delete dados.email; if (!f.telefone) delete dados.telefone;
        const r = await api.criarOportunidade(ies!, dados);
        setF(vazio); aoCriar();
        return r.duplicada ? `Já existia oportunidade para esta pessoa, curso e coorte (#${r.id}). Nada foi duplicado.` : `Oportunidade #${r.id} criada e distribuída.`;
      }); }}>
        <Campo rotulo="Nome"><input className="campo" required maxLength={120} {...campo('nome')} /></Campo>
        <Campo rotulo="E-mail"><input className="campo" type="email" {...campo('email')} /></Campo>
        <Campo rotulo="Telefone"><input className="campo" inputMode="tel" {...campo('telefone')} /></Campo>
        <Campo rotulo="Curso"><select className="campo" {...campo('curso_id')}>{estrutura?.cursos.map((c) => <option key={c.id} value={c.id}>{c.nome} · {c.turno}</option>)}</select></Campo>
        <Campo rotulo="Forma de ingresso"><select className="campo" {...campo('forma_ingresso')}>{estrutura?.formas_ingresso.map((x) => <option key={x} value={x}>{rotulo(x)}</option>)}</select></Campo>
        <Campo rotulo="Coorte"><input className="campo w-24" pattern="\d{4}\.[12]" {...campo('coorte')} /></Campo>
        <Campo rotulo="Base legal (LGPD)"><select className="campo" {...campo('base_legal')}><option value="">Selecione…</option>{estrutura?.bases_legais.map((x) => <option key={x} value={x}>{rotulo(x)}</option>)}</select></Campo>
        <Campo rotulo="Origem"><input className="campo" placeholder="ex.: site, evento escolar" {...campo('origem')} /></Campo>
        <button className="btn" type="submit" disabled={acao.enviando}>Cadastrar</button>
      </form>
      <Mensagem m={acao.mensagem} />
    </Detalhes>
  );
}

function Importar({ aoImportar }: { aoImportar: () => void }) {
  const { ies, estrutura } = useSessao();
  const acao = useAcao();
  const [texto, setTexto] = useState('');
  const [rejeitadas, setRejeitadas] = useState<{ linha: number; motivo: string }[]>([]);
  return (
    <Detalhes titulo="Importar lista (deduplicada)">
      <p className="nota mb-2">Uma linha por candidato: nome;email;telefone;curso_id;forma_ingresso;coorte;base_legal;origem. Cursos: {estrutura?.cursos.map((c) => `${c.id}=${c.nome}`).join(', ')}. Linhas sem origem ou base legal são rejeitadas.</p>
      <textarea className="campo min-h-[110px] w-full" aria-label="Linhas para importar" value={texto} onChange={(e) => setTexto(e.target.value)}
        placeholder="nome;email;telefone;curso_id;forma_ingresso;coorte;base_legal;origem" />
      <button className="btn mt-2" disabled={acao.enviando} onClick={() => void acao.executar(async () => {
        const linhas = texto.split('\n').map((l) => l.trim()).filter(Boolean);
        if (!linhas.length || linhas.length > 500) throw new Error('Envie de 1 a 500 linhas');
        let criadas = 0; let duplicadas = 0; const rej: { linha: number; motivo: string }[] = [];
        for (const [i, l] of linhas.entries()) {
          try { const r = await api.criarOportunidade(ies!, linhaImportacao(l)); if (r.duplicada) duplicadas++; else criadas++; }
          catch (e) { rej.push({ linha: i + 1, motivo: (e as Error).message }); }
        }
        setRejeitadas(rej); aoImportar();
        return `Importação: ${criadas} criadas, ${duplicadas} duplicadas, ${rej.length} rejeitadas.`;
      })}>Importar</button>
      <Mensagem m={acao.mensagem} />
      {rejeitadas.length > 0 && <ul className="text-sm text-erro">{rejeitadas.map((r) => <li key={r.linha}>Linha {r.linha}: {r.motivo}</li>)}</ul>}
    </Detalhes>
  );
}
