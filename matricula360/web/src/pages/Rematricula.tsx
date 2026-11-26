import { RotateCw } from 'lucide-react';
import { useState } from 'react';
import { useSessao } from '../components/Layout';
import { TextoContrato } from '../components/TextoContrato';
import { Aviso, Campo, Cartao, Chip, Detalhes, Estado, Kpi, Mensagem, Titulo, Vazio } from '../components/ui';
import { api } from '../lib/api';
import { contarDestaques } from '../lib/contrato';
import { dataHora, rotulo } from '../lib/formato';
import { useAcao, useCarregar } from '../lib/hooks';
import type { ErroApi } from '../lib/supabase';
import type { AlunoRematricula, CampanhaRematricula } from '../lib/tipos';

type Fazer = (fn: () => Promise<string>) => Promise<void>;
const CATEGORIAS = ['financeiro', 'documental', 'academico', 'outro'];

// Rematrícula ativa (L14): campanha por período, elegíveis fotografados, bloqueios, aceite pelo portal e indicadores.
export function Rematricula({ abrirDetalhe }: { abrirDetalhe: (id: number) => void }) {
  const { ies, estrutura } = useSessao();
  const [recarga, setRecarga] = useState(0);
  const r = useCarregar(() => api.rematricula(ies!), [ies, recarga]);
  const acao = useAcao();
  const fazer: Fazer = (fn) => acao.executar(async () => { const t = await fn(); setRecarga((n) => n + 1); return t; });
  const vazio = { periodo: '', abre_em: '', fecha_em: '', meta_pct: '', termo: '', coortes: [] as string[] };
  const [n, setN] = useState(vazio);
  const d = r.dados;
  const dz = contarDestaques(n.termo);
  return (
    <>
      <Titulo titulo="Rematrícula" subtitulo="Campanha por período, elegíveis, bloqueios com motivo, aceite pelo portal e taxa de rematrícula." />
      {(r.erro as ErroApi | null)?.codigo === 'PGRST202' ? <Vazio texto="Disponível após a migração 24 do banco." /> : <Estado carregando={r.carregando && !d} erro={r.erro} />}
      <Mensagem m={acao.mensagem} />
      {d && (
        <div className="space-y-4">
          <Aviso>{d.aviso}</Aviso>
          {d.pode_gerir && (
            <Detalhes titulo="Nova campanha">
              <form className="grid gap-2 sm:grid-cols-4" onSubmit={(e) => { e.preventDefault(); void fazer(async () => {
                await api.salvarCampanhaRematricula(ies!, { ...n, meta_pct: n.meta_pct || null, coortes: n.coortes.length ? n.coortes : null }); setN(vazio); return 'Campanha criada em rascunho.'; }); }}>
                <Campo rotulo="Período (ex.: 2027.2)"><input className="campo" required pattern="\d{4}\.[12]" value={n.periodo} onChange={(e) => setN({ ...n, periodo: e.target.value })} /></Campo>
                <Campo rotulo="Abre em"><input className="campo" type="date" required value={n.abre_em} onChange={(e) => setN({ ...n, abre_em: e.target.value })} /></Campo>
                <Campo rotulo="Fecha em"><input className="campo" type="date" required value={n.fecha_em} onChange={(e) => setN({ ...n, fecha_em: e.target.value })} /></Campo>
                <Campo rotulo="Meta (%)"><input className="campo" inputMode="decimal" value={n.meta_pct} onChange={(e) => setN({ ...n, meta_pct: e.target.value })} /></Campo>
                <Campo rotulo="Coortes de ingresso (nenhuma = todas)"><select className="campo" multiple value={n.coortes} onChange={(e) => setN({ ...n, coortes: Array.from(e.target.selectedOptions).map((o) => o.value) })}>
                  {estrutura?.coortes.map((c) => <option key={c} value={c}>{c}</option>)}</select></Campo>
                <Campo rotulo="Termo de rematrícula (cláusulas limitativas entre ** e **)" className="sm:col-span-3"><textarea className="campo min-h-[120px]" required minLength={100} value={n.termo} onChange={(e) => setN({ ...n, termo: e.target.value })} /></Campo>
                {n.termo && <p className={`text-xs sm:col-span-4 ${dz.balanceado ? 'text-suave' : 'text-alerta'}`}>{dz.balanceado ? `${dz.total} cláusula(s) em destaque.` : 'Há um ** sem fechamento.'}</p>}
                <div className="sm:col-span-4"><button className="btn btn-peq" disabled={acao.enviando || !dz.balanceado}>Criar campanha</button></div>
              </form>
            </Detalhes>)}
          {!d.campanhas.length && <Vazio texto="Nenhuma campanha de rematrícula." />}
          {d.campanhas.map((c) => <CartaoCampanha key={c.id} c={c} podeGerir={d.pode_gerir} podeTratar={d.pode_tratar} fazer={fazer} enviando={acao.enviando} abrirDetalhe={abrirDetalhe} />)}
        </div>)}
    </>
  );
}

function CartaoCampanha({ c, podeGerir, podeTratar, fazer, enviando, abrirDetalhe }: { c: CampanhaRematricula; podeGerir: boolean; podeTratar: boolean; fazer: Fazer; enviando: boolean; abrirDetalhe: (id: number) => void }) {
  const [filtro, setFiltro] = useState('');
  const t = c.totais;
  const alunos = c.alunos.filter((a) => !filtro || a.status === filtro);
  const data = (s: string) => new Date(`${s}T12:00:00`).toLocaleDateString('pt-BR');
  return (
    <Cartao titulo={`Rematrícula ${c.periodo}`} icone={RotateCw} acao={<Chip tipo={c.status === 'aberta' ? 'ok' : c.status === 'rascunho' ? 'tec' : undefined}>{rotulo(c.status)}</Chip>}>
      <p className="nota">{data(c.abre_em)} a {data(c.fecha_em)}{c.coortes ? ` · coortes ${c.coortes.join(', ')}` : ' · todas as coortes'}</p>
      <div className="mt-2 grid gap-3 sm:grid-cols-5">
        <Kpi rotulo="Elegíveis" valor={String(t.elegiveis)} />
        <Kpi rotulo="Taxa de rematrícula" valor={t.taxa_pct == null ? 'N/D' : `${t.taxa_pct}%`} detalhe={c.meta_pct ? `meta ${c.meta_pct}%` : undefined} destaque />
        <Kpi rotulo="Aceitas" valor={String(t.aceitas)} /><Kpi rotulo="Pendentes" valor={String(t.pendentes)} /><Kpi rotulo="Bloqueadas / recusadas" valor={`${t.bloqueadas} / ${t.recusadas}`} />
      </div>
      <Detalhes titulo="Termo de rematrícula"><TextoContrato texto={c.termo} className="max-h-72 overflow-y-auto rounded-lg bg-fundo p-3" /></Detalhes>
      {podeGerir && c.status !== 'encerrada' && (
        <div className="mt-2 flex flex-wrap gap-2">
          <button className="btn btn-peq" disabled={enviando} onClick={() => void fazer(async () => { const r = await api.statusCampanhaRematricula(c.id, 'aberta');
            return c.status === 'rascunho' ? `Campanha aberta: ${r.novos_elegiveis} elegível(is).` : `${r.novos_elegiveis} novo(s) elegível(is) incluído(s).`; })}>{c.status === 'rascunho' ? 'Abrir campanha' : 'Atualizar elegíveis'}</button>
          {c.status === 'aberta' && <button className="btn btn-sec btn-peq" disabled={enviando} onClick={() => { if (window.confirm('Encerrar a campanha? Ela não poderá ser reaberta.')) void fazer(async () => { await api.statusCampanhaRematricula(c.id, 'encerrada'); return 'Campanha encerrada.'; }); }}>Encerrar</button>}
        </div>)}
      {c.alunos.length > 0 && (
        <div className="mt-3">
          <Campo rotulo="Situação" className="max-w-xs"><select className="campo" value={filtro} onChange={(e) => setFiltro(e.target.value)}>
            <option value="">Todas</option>{['pendente', 'aceita', 'recusada', 'bloqueada'].map((s) => <option key={s} value={s}>{rotulo(s)}</option>)}</select></Campo>
          <ul className="mt-2 space-y-2">{alunos.map((a) => <LinhaAluno key={a.id} a={a} aberta={c.status === 'aberta'} podeTratar={podeTratar} fazer={fazer} enviando={enviando} abrirDetalhe={abrirDetalhe} />)}</ul>
        </div>)}
    </Cartao>
  );
}

function LinhaAluno({ a, aberta, podeTratar, fazer, enviando, abrirDetalhe }: { a: AlunoRematricula; aberta: boolean; podeTratar: boolean; fazer: Fazer; enviando: boolean; abrirDetalhe: (id: number) => void }) {
  const [cat, setCat] = useState('financeiro'); const [mot, setMot] = useState('');
  return (
    <li className="rounded-lg border border-linha p-2 text-sm">
      <p><button className="font-medium text-tec hover:underline" onClick={() => abrirDetalhe(a.oportunidade_id)}>{a.nome}</button> · {a.curso} · ingresso {a.coorte}
        <Chip tipo={a.status === 'aceita' ? 'ok' : a.status === 'pendente' ? 'pend' : a.status === 'bloqueada' ? 'erro' : undefined}>{rotulo(a.status)}</Chip>
        {a.categoria && <Chip>{rotulo(a.categoria)}</Chip>}</p>
      {(a.motivo || a.respondido_em) && <p className="text-xs">{a.motivo}{a.respondido_em ? ` · ${a.origem === 'portal' ? 'pelo portal' : `pela secretaria (${a.tratado_por})`} em ${dataHora(a.respondido_em)}` : a.tratado_por ? ` · ${a.tratado_por}` : ''}</p>}
      {podeTratar && aberta && (a.status === 'pendente' ? (
        <div className="mt-1 flex flex-wrap items-end gap-2">
          <Campo rotulo="Motivo ou registro"><input className="campo" value={mot} onChange={(e) => setMot(e.target.value)} /></Campo>
          <Campo rotulo="Categoria do bloqueio"><select className="campo" value={cat} onChange={(e) => setCat(e.target.value)}>{CATEGORIAS.map((x) => <option key={x} value={x}>{rotulo(x)}</option>)}</select></Campo>
          <button className="btn btn-sec btn-peq" disabled={enviando || mot.trim().length < 5} onClick={() => void fazer(async () => { await api.tratarRematricula(a.id, 'bloquear', mot, cat); return 'Rematrícula bloqueada.'; })}>Bloquear</button>
          <button className="btn btn-ok btn-peq" disabled={enviando || mot.trim().length < 5} onClick={() => void fazer(async () => { await api.tratarRematricula(a.id, 'aceita', mot); return 'Rematrícula presencial registrada.'; })}>Registrar aceite presencial</button>
          <button className="btn btn-fantasma btn-peq" disabled={enviando || mot.trim().length < 5} onClick={() => void fazer(async () => { await api.tratarRematricula(a.id, 'recusada', mot); return 'Recusa registrada.'; })}>Registrar recusa</button>
        </div>
      ) : a.status === 'bloqueada' && <button className="btn btn-sec btn-peq mt-1" disabled={enviando} onClick={() => void fazer(async () => { await api.tratarRematricula(a.id, 'desbloquear'); return 'Pendência resolvida: aluno liberado.'; })}>Desbloquear</button>)}
    </li>
  );
}
