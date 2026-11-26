import { Megaphone, PlugZap, ReceiptText } from 'lucide-react';
import { useState } from 'react';
import { BarraFiltros, useSessao } from '../components/Layout';
import { Aviso, Campo, Cartao, Chip, Detalhes, Estado, Kpi, Mensagem, Titulo, Valor, Vazio } from '../components/ui';
import { api } from '../lib/api';
import { centavos, moeda, ND, num, pct, rotulo } from '../lib/formato';
import { useAcao, useCarregar } from '../lib/hooks';
import type { ErroApi } from '../lib/supabase';
import type { Campanha } from '../lib/tipos';

const CANAIS = ['meta_ads', 'google_ads', 'tiktok_ads', 'whatsapp', 'email', 'site', 'evento', 'visita_escolar', 'indicacao', 'convenio', 'radio_tv', 'impresso', 'outro'];
const mo = (v: number | null | undefined) => (v == null ? ND : moeda(v));
const dt = (d: string) => new Date(`${d}T12:00:00`).toLocaleDateString('pt-BR');

export function Campanhas() {
  const { ies, filtros } = useSessao();
  const coorte = filtros.coorte;
  const [recarga, setRecarga] = useState(0);
  const c = useCarregar(() => (ies && coorte ? api.campanhas(ies, coorte) : Promise.resolve(null)), [ies, coorte, recarga]);
  const planos = useCarregar(() => (ies && coorte ? api.planejamento(ies, coorte).catch(() => null) : Promise.resolve(null)), [ies, coorte]);
  const acao = useAcao();
  const fazer = (fn: () => Promise<string>) => acao.executar(async () => { const t = await fn(); setRecarga((n) => n + 1); return t; });
  const d = c.dados;
  const tot = d?.campanhas.reduce((s, k) => ({ leads: s.leads + k.leads, ing: s.ing + k.ingressantes, custo: s.custo + (k.custo_centavos ?? 0) }), { leads: 0, ing: 0, custo: 0 });

  return (
    <>
      <Titulo titulo="Marketing e Captação" subtitulo="Campanhas da coorte, código de atribuição, custos e resultados atribuídos. Integrações externas desligadas." />
      <BarraFiltros completos={false} />
      {(c.erro as ErroApi | null)?.codigo === 'PGRST202' ? <Vazio texto="Disponível após a migração 12 do banco." /> : <Estado carregando={c.carregando && !d} erro={c.erro} />}
      <Mensagem m={acao.mensagem} />
      {d && tot && (
        <div className="space-y-5">
          <div className="kpis grid grid-cols-2 gap-3 md:grid-cols-5">
            <Kpi rotulo="Campanhas" valor={num(d.campanhas.length)} icone={Megaphone} />
            <Kpi rotulo="Leads atribuídos" valor={num(tot.leads)} />
            <Kpi rotulo="Atribuição desconhecida" valor={num(d.atribuicao_desconhecida.leads)} detalhe="Leads sem código de campanha" />
            <Kpi rotulo="Custo lançado" valor={d.ve_custos ? moeda(tot.custo) : ND} detalhe={d.ve_custos ? 'Sem estornos' : 'Restrito à gestão e ao financeiro'} />
            <Kpi rotulo="CPL consolidado" valor={d.ve_custos && tot.custo > 0 && tot.leads > 0 ? moeda(Math.round(tot.custo / tot.leads)) : ND} detalhe={d.metodos.cpl} />
          </div>
          <Aviso>{d.metodos.atribuicao} No cadastro e na importação do CRM, informe o código da campanha.</Aviso>
          {d.pode_editar && <NovaCampanha coorte={coorte} planos={planos.dados?.planos.map((p) => ({ id: p.id, titulo: p.titulo })) ?? []} fazer={fazer} enviando={acao.enviando} />}
          {!d.campanhas.length ? <Vazio texto={`Nenhuma campanha na coorte ${coorte}.`} /> : (
            <div className="tabela"><table>
              <thead><tr>{['Campanha', 'Canal', 'Vigência', 'Status', 'Leads', 'Ingressantes', 'Conversão', 'Orçamento', 'Custo', 'CPL', 'Custo/ingressante'].map((h) => <th key={h} scope="col">{h}</th>)}</tr></thead>
              <tbody>{d.campanhas.map((k) => (
                <tr key={k.id}><td><strong>{k.nome}</strong><code className="block text-xs text-tec">{k.codigo}</code></td><td>{rotulo(k.canal)}</td>
                  <td className="whitespace-nowrap">{dt(k.inicio)} – {dt(k.fim)}{k.vigente && <Chip tipo="ok">vigente</Chip>}</td>
                  <td>{d.pode_editar ? (
                    <select className="campo text-xs" aria-label={`Status da campanha ${k.nome}`} value={k.status} disabled={acao.enviando}
                      onChange={(e) => void fazer(async () => { await api.salvarCampanha(ies!, { status: e.target.value }, k.id, k.versao); return 'Status da campanha atualizado.'; })}>
                      {['planejada', 'ativa', 'encerrada', 'cancelada'].map((s) => <option key={s} value={s}>{rotulo(s)}</option>)}</select>) : rotulo(k.status)}</td>
                  <td>{k.leads}</td><td>{k.ingressantes}</td><td><Valor v={pct(k.conversao)} /></td>
                  <td>{d.ve_custos ? mo(k.orcamento_centavos) : '—'}</td><td>{d.ve_custos ? mo(k.custo_centavos) : '—'}</td>
                  <td><Valor v={d.ve_custos ? mo(k.cpl_centavos) : ND} /></td><td><Valor v={d.ve_custos ? mo(k.custo_ingressante_centavos) : ND} /></td></tr>
              ))}</tbody>
            </table></div>
          )}
          {d.ve_custos && d.campanhas.length > 0 && <Custos campanhas={d.campanhas} podeLancar={d.pode_lancar_custo} fazer={fazer} enviando={acao.enviando} />}
          <Cartao titulo="Integrações de mídia e mensageria" icone={PlugZap}>
            <p className="mb-2">{Object.entries(d.integracoes).map(([k, v]) => <Chip key={k}>{rotulo(k)}: {v}</Chip>)}</p>
            <p className="nota">Opt-in e desligadas por padrão (Bíblia §7). Nenhum dado sai do sistema e nenhum custo é importado automaticamente; os canais acima servem só para classificar campanhas.</p>
          </Cartao>
        </div>
      )}
    </>
  );
}

type Fazer = (fn: () => Promise<string>) => Promise<void>;

function NovaCampanha({ coorte, planos, fazer, enviando }: { coorte: string; planos: { id: number; titulo: string }[]; fazer: Fazer; enviando: boolean }) {
  const { ies } = useSessao();
  const vazio = { nome: '', codigo: '', canal: 'meta_ads', inicio: '', fim: '', orcamento: '', objetivo: '', plano_id: '' };
  const [f, setF] = useState(vazio);
  return (
    <Detalhes titulo={`Nova campanha em ${coorte}`}>
      <form className="grid gap-2 sm:grid-cols-4" onSubmit={(e) => { e.preventDefault(); void fazer(async () => {
        await api.salvarCampanha(ies!, { coorte, nome: f.nome, codigo: f.codigo, canal: f.canal, inicio: f.inicio, fim: f.fim,
          orcamento_centavos: f.orcamento ? centavos(f.orcamento) : 0, objetivo: f.objetivo, plano_id: f.plano_id, status: 'planejada' });
        setF(vazio); return 'Campanha criada.'; }); }}>
        <Campo rotulo="Nome" className="sm:col-span-2"><input className="campo" required minLength={3} maxLength={120} value={f.nome} onChange={(e) => setF({ ...f, nome: e.target.value })} /></Campo>
        <Campo rotulo="Código de atribuição"><input className="campo" required pattern="[a-z0-9][a-z0-9\-]{2,40}" title="letras minúsculas, números e hífen" placeholder="vestibular-verao"
          value={f.codigo} onChange={(e) => setF({ ...f, codigo: e.target.value.toLowerCase() })} /></Campo>
        <Campo rotulo="Canal"><select className="campo" value={f.canal} onChange={(e) => setF({ ...f, canal: e.target.value })}>{CANAIS.map((x) => <option key={x} value={x}>{rotulo(x)}</option>)}</select></Campo>
        <Campo rotulo="Início"><input className="campo" type="date" required value={f.inicio} onChange={(e) => setF({ ...f, inicio: e.target.value })} /></Campo>
        <Campo rotulo="Fim"><input className="campo" type="date" required value={f.fim} onChange={(e) => setF({ ...f, fim: e.target.value })} /></Campo>
        <Campo rotulo="Orçamento (R$)"><input className="campo" inputMode="decimal" value={f.orcamento} onChange={(e) => setF({ ...f, orcamento: e.target.value })} /></Campo>
        <Campo rotulo="Plano"><select className="campo" value={f.plano_id} onChange={(e) => setF({ ...f, plano_id: e.target.value })}><option value="">—</option>{planos.map((p) => <option key={p.id} value={p.id}>{p.titulo}</option>)}</select></Campo>
        <Campo rotulo="Objetivo da campanha" className="sm:col-span-3"><input className="campo" maxLength={300} value={f.objetivo} onChange={(e) => setF({ ...f, objetivo: e.target.value })} /></Campo>
        <div className="flex items-end"><button className="btn" disabled={enviando}>Criar campanha</button></div>
      </form>
    </Detalhes>
  );
}

function Custos({ campanhas, podeLancar, fazer, enviando }: { campanhas: Campanha[]; podeLancar: boolean; fazer: Fazer; enviando: boolean }) {
  const hoje = new Date().toISOString().slice(0, 10);
  const [f, setF] = useState({ campanha: String(campanhas[0]?.id ?? ''), data: hoje, valor: '', descricao: '' });
  const lancamentos = campanhas.flatMap((k) => (k.custos ?? []).map((x) => ({ ...x, campanha: k.nome })));
  return (
    <Cartao titulo="Custos lançados" icone={ReceiptText}>
      {podeLancar && (
        <form className="mb-3 flex flex-wrap items-end gap-2" onSubmit={(e) => { e.preventDefault(); void fazer(async () => {
          const r = await api.lancarCusto(Number(f.campanha), f.data, centavos(f.valor), f.descricao);
          setF({ ...f, valor: '', descricao: '' }); return r.repeticao ? 'Lançamento já registrado (nada duplicado).' : 'Custo lançado.'; }); }}>
          <Campo rotulo="Campanha"><select className="campo" value={f.campanha} onChange={(e) => setF({ ...f, campanha: e.target.value })}>{campanhas.map((k) => <option key={k.id} value={k.id}>{k.nome}</option>)}</select></Campo>
          <Campo rotulo="Data"><input className="campo" type="date" max={hoje} required value={f.data} onChange={(e) => setF({ ...f, data: e.target.value })} /></Campo>
          <Campo rotulo="Valor (R$)"><input className="campo w-28" required inputMode="decimal" value={f.valor} onChange={(e) => setF({ ...f, valor: e.target.value })} /></Campo>
          <Campo rotulo="Descrição" className="grow"><input className="campo" required minLength={3} maxLength={200} value={f.descricao} onChange={(e) => setF({ ...f, descricao: e.target.value })} /></Campo>
          <button className="btn btn-peq" disabled={enviando}>Lançar custo</button>
        </form>
      )}
      {lancamentos.length ? (
        <div className="tabela"><table>
          <thead><tr>{['Data', 'Campanha', 'Descrição', 'Valor', 'Lançado por', ''].map((h) => <th key={h} scope="col">{h}</th>)}</tr></thead>
          <tbody>{lancamentos.map((x) => (
            <tr key={x.id} className={x.estornado_em ? 'text-suave line-through' : ''}><td>{dt(x.data)}</td><td>{x.campanha}</td><td>{x.descricao}
              {x.estornado_em && <span className="block text-xs no-underline">Estornado: {x.motivo_estorno}</span>}</td><td>{moeda(x.valor_centavos)}</td><td>{x.lancado_por}</td>
              <td>{podeLancar && !x.estornado_em && <button className="btn btn-sec btn-peq" disabled={enviando} onClick={() => {
                const m = window.prompt('Motivo do estorno (obrigatório):'); if (!m) return;
                void fazer(async () => { await api.estornarCusto(x.id, m); return 'Custo estornado.'; });
              }}>Estornar</button>}</td></tr>
          ))}</tbody>
        </table></div>
      ) : <p className="nota">Nenhum custo lançado.</p>}
    </Cartao>
  );
}
