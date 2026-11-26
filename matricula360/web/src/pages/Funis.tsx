import { ArrowDown, ArrowUp, GitBranch, Plus, Trash2, Workflow } from 'lucide-react';
import { useState } from 'react';
import { useSessao } from '../components/Layout';
import { Aviso, Campo, Cartao, Chip, Detalhes, Estado, Mensagem, Titulo, Valor, Vazio } from '../components/ui';
import { api } from '../lib/api';
import { dataHora, pct, rotulo } from '../lib/formato';
import { useAcao, useCarregar } from '../lib/hooks';
import type { ErroApi } from '../lib/supabase';
import type { CadenciaFunil, EtapaBase, EtapaFunil, Funil, MetaFunil, VersaoFunil } from '../lib/tipos';

const BASES: EtapaBase[] = ['novo', 'contato', 'inscrito', 'pre_matricula', 'matricula_comercial'];
const FORMAS = ['vestibular', 'enem', 'transferencia', 'segunda_graduacao', 'reingresso', 'indicacao', 'convenio', 'visita_escolar', 'evento', 'pos_graduacao'];
const CANAIS: CadenciaFunil['canal'][] = ['telefone', 'whatsapp', 'email', 'presencial'];
type Fazer = (fn: () => Promise<string>) => Promise<void>;

export function Funis() {
  const { ies } = useSessao();
  const [recarga, setRecarga] = useState(0);
  const f = useCarregar(() => api.funis(ies!), [ies, recarga]);
  const acao = useAcao();
  const fazer: Fazer = (fn) => acao.executar(async () => { const t = await fn(); setRecarga((n) => n + 1); return t; });
  return (
    <>
      <Titulo titulo="Funis Comerciais" subtitulo="Etapas configuráveis por modalidade e forma de ingresso, com roteiro, SLA, cadência e metas. Versões publicadas são imutáveis." />
      {(f.erro as ErroApi | null)?.codigo === 'PGRST202' ? <Vazio texto="Disponível após a migração 13 do banco." /> : <Estado carregando={f.carregando && !f.dados} erro={f.erro} />}
      <Mensagem m={acao.mensagem} />
      {f.dados && (
        <div className="space-y-5">
          <Aviso>{f.dados.regra_selecao} As etapas configuradas detalham as etapas oficiais do CRM; mudar de etapa oficial continua validado pelo servidor. Cadências são guia de trabalho: nada é enviado automaticamente.</Aviso>
          {f.dados.pode_editar && <NovoFunil fazer={fazer} enviando={acao.enviando} />}
          {f.dados.funis.map((x) => <CartaoFunil key={x.id} f={x} podeEditar={f.dados!.pode_editar} podePublicar={f.dados!.pode_publicar} fazer={fazer} enviando={acao.enviando} />)}
        </div>
      )}
    </>
  );
}

function NovoFunil({ fazer, enviando }: { fazer: Fazer; enviando: boolean }) {
  const { ies } = useSessao();
  const [nome, setNome] = useState(''); const [modalidade, setModalidade] = useState(''); const [formas, setFormas] = useState<string[]>([]);
  return (
    <Detalhes titulo="Novo funil específico">
      <form className="space-y-2" onSubmit={(e) => { e.preventDefault(); void fazer(async () => {
        await api.salvarFunil(ies!, { nome, modalidade, formas }); setNome(''); setModalidade(''); setFormas([]);
        return 'Funil criado com versão 1 em rascunho (copiada do funil padrão).'; }); }}>
        <div className="flex flex-wrap items-end gap-2">
          <Campo rotulo="Nome"><input className="campo" required minLength={3} maxLength={80} value={nome} onChange={(e) => setNome(e.target.value)} /></Campo>
          <Campo rotulo="Modalidade"><select className="campo" value={modalidade} onChange={(e) => setModalidade(e.target.value)}>
            <option value="">Todas</option>{['presencial', 'semipresencial', 'ead'].map((m) => <option key={m} value={m}>{rotulo(m)}</option>)}</select></Campo>
        </div>
        <fieldset className="flex flex-wrap gap-x-3 gap-y-1 text-sm"><legend className="mb-1 text-xs font-medium text-suave">Formas de ingresso (vazio = todas)</legend>
          {FORMAS.map((x) => <label key={x} className="flex items-center gap-1"><input type="checkbox" checked={formas.includes(x)}
            onChange={(e) => setFormas(e.target.checked ? [...formas, x] : formas.filter((y) => y !== x))} />{rotulo(x)}</label>)}
        </fieldset>
        <button className="btn btn-peq" disabled={enviando}>Criar funil</button>
      </form>
    </Detalhes>
  );
}

function CartaoFunil({ f, podeEditar, podePublicar, fazer, enviando }: { f: Funil; podeEditar: boolean; podePublicar: boolean; fazer: Fazer; enviando: boolean }) {
  const { ies } = useSessao();
  const publicada = f.versoes.find((v) => v.status === 'publicada');
  const rascunho = f.versoes.find((v) => v.status === 'rascunho');
  const criterio = f.padrao ? 'Padrão da instituição' : [f.modalidade ? rotulo(f.modalidade) : 'Todas as modalidades', f.formas ? f.formas.map(rotulo).join(', ') : 'todas as formas'].join(' · ');
  return (
    <Cartao titulo={f.nome} icone={Workflow} acao={<span>{publicada ? <Chip tipo="ok">v{publicada.versao} publicada</Chip> : <Chip tipo="pend">sem versão publicada</Chip>}
      {rascunho && <Chip tipo="tec">v{rascunho.versao} em rascunho</Chip>}</span>}>
      <p className="nota mb-3">{criterio}</p>
      {publicada && <VisaoVersao v={publicada} />}
      {f.desempenho.length > 0 && (
        <div className="tabela my-3" tabIndex={0} role="region" aria-label="Tabela com rolagem horizontal"><table>
          <thead><tr>{['Forma de ingresso', 'Oportunidades', 'Ingressantes', 'Conversão', 'Meta'].map((h) => <th key={h} scope="col">{h}</th>)}</tr></thead>
          <tbody>{f.desempenho.map((d) => (
            <tr key={d.forma_ingresso}><td>{rotulo(d.forma_ingresso)}</td><td>{d.oportunidades}</td><td>{d.ingressantes}</td>
              <td><Valor v={pct(d.conversao)} />{d.meta != null && d.conversao != null && <Chip tipo={d.conversao >= d.meta ? 'ok' : 'pend'}>{d.conversao >= d.meta ? 'na meta' : 'abaixo'}</Chip>}</td>
              <td><Valor v={pct(d.meta)} /></td></tr>))}</tbody>
        </table></div>
      )}
      {rascunho && podeEditar ? <EditorVersao v={rascunho} podePublicar={podePublicar} fazer={fazer} enviando={enviando} />
        : podeEditar && <button className="btn btn-sec btn-peq mt-2" disabled={enviando} onClick={() => void fazer(async () => {
            const r = await api.novaVersao(f.id); return `Versão ${r.versao} criada em rascunho, copiada da publicada.`; })}><GitBranch className="h-3.5 w-3.5" aria-hidden />Nova versão</button>}
      {f.versoes.some((v) => v.status === 'arquivada') && (
        <p className="nota mt-2">Arquivadas: {f.versoes.filter((v) => v.status === 'arquivada').map((v) => `v${v.versao} (${v.oportunidades} oportunidades mantidas)`).join(', ')}.</p>)}
      {!f.padrao && podeEditar && (
        <button className="btn btn-fantasma btn-peq mt-2" disabled={enviando} onClick={() => void fazer(async () => {
          await api.salvarFunil(ies!, { ativo: !f.ativo }, f.id); return f.ativo ? 'Funil desativado para novas oportunidades.' : 'Funil reativado.'; })}>
          {f.ativo ? 'Desativar para novas oportunidades' : 'Reativar'}</button>)}
    </Cartao>
  );
}

function VisaoVersao({ v }: { v: VersaoFunil }) {
  return (
    <div>
      <p className="nota mb-2">v{v.versao} publicada por {v.publicada_por ?? 'sistema'} em {dataHora(v.publicada_em)} · {v.oportunidades} oportunidade(s){v.notas ? ` · ${v.notas}` : ''}</p>
      <ol className="flex flex-wrap gap-1.5">{v.etapas.map((e) => (
        <li key={e.ordem} className="rounded-lg border border-linha bg-fundo px-2.5 py-1.5 text-xs">
          <strong>{e.ordem}. {e.nome}</strong><span className="block text-suave">{rotulo(e.etapa_base)}{e.sla_horas ? ` · SLA ${e.sla_horas} h` : ''}
            {v.cadencias.some((c) => c.etapa_ordem === e.ordem) ? ` · ${v.cadencias.filter((c) => c.etapa_ordem === e.ordem).length} contato(s) na cadência` : ''}</span>
        </li>))}</ol>
      {v.metas.length > 0 && <p className="mt-2 text-xs">Metas de conversão: {v.metas.map((m) => `${rotulo(m.forma_ingresso)} ${pct(Number(m.conversao_meta))}`).join(' · ')}</p>}
    </div>
  );
}

function EditorVersao({ v, podePublicar, fazer, enviando }: { v: VersaoFunil; podePublicar: boolean; fazer: Fazer; enviando: boolean }) {
  const [etapas, setEtapas] = useState<EtapaFunil[]>(v.etapas);
  const [cad, setCad] = useState<CadenciaFunil[]>(v.cadencias);
  const [metas, setMetas] = useState<Record<string, string>>(Object.fromEntries(v.metas.map((m: MetaFunil) => [m.forma_ingresso, String(Math.round(Number(m.conversao_meta) * 1000) / 10)])));
  const [notas, setNotas] = useState(v.notas ?? '');
  const renumerar = (l: EtapaFunil[]) => l.map((e, i) => ({ ...e, ordem: i + 1 }));
  const mover = (i: number, d: number) => { const l = [...etapas]; const [x] = l.splice(i, 1); l.splice(i + d, 0, x!); setEtapas(renumerar(l)); };
  const muda = (i: number, k: keyof EtapaFunil, val: string) => setEtapas(etapas.map((e, j) => (j === i ? { ...e, [k]: k === 'sla_horas' ? (val ? Number(val) : null) : val } : e)));
  const dados = () => ({ notas, etapas, cadencias: cad.map((c, i) => ({ ...c, passo: cad.slice(0, i).filter((x) => x.etapa_ordem === c.etapa_ordem).length + 1 })),
    metas: Object.entries(metas).filter(([, x]) => x).map(([forma_ingresso, x]) => ({ forma_ingresso, conversao_meta: Number(x.replace(',', '.')) / 100 })) });
  return (
    <section className="mt-3 rounded-xl border border-dashed border-tec-400 p-3" aria-label={`Rascunho v${v.versao}`}>
      <h3 className="mb-2 font-semibold text-marinho">Rascunho v{v.versao}</h3>
      <div className="tabela" tabIndex={0} role="region" aria-label="Tabela com rolagem horizontal"><table>
        <thead><tr>{['#', 'Etapa do funil', 'Etapa oficial', 'SLA (h)', 'Roteiro', ''].map((h) => <th key={h} scope="col">{h}</th>)}</tr></thead>
        <tbody>{etapas.map((e, i) => (
          <tr key={i}><td>{e.ordem}</td>
            <td><input className="campo w-40" aria-label={`Nome da etapa ${e.ordem}`} value={e.nome} onChange={(x) => muda(i, 'nome', x.target.value)} /></td>
            <td><select className="campo" aria-label={`Etapa oficial da etapa ${e.ordem}`} value={e.etapa_base} onChange={(x) => muda(i, 'etapa_base', x.target.value)}>
              {BASES.map((b) => <option key={b} value={b}>{rotulo(b)}</option>)}</select></td>
            <td><input className="campo w-20" type="number" min={1} max={720} aria-label={`SLA da etapa ${e.ordem}`} value={e.sla_horas ?? ''} onChange={(x) => muda(i, 'sla_horas', x.target.value)} /></td>
            <td><textarea className="campo min-h-[38px] w-64" maxLength={3000} aria-label={`Roteiro da etapa ${e.ordem}`} value={e.roteiro ?? ''} onChange={(x) => muda(i, 'roteiro', x.target.value)} /></td>
            <td className="whitespace-nowrap">
              <button className="btn btn-fantasma btn-peq" aria-label="Subir" disabled={i === 0} onClick={() => mover(i, -1)}><ArrowUp className="h-3.5 w-3.5" /></button>
              <button className="btn btn-fantasma btn-peq" aria-label="Descer" disabled={i === etapas.length - 1} onClick={() => mover(i, 1)}><ArrowDown className="h-3.5 w-3.5" /></button>
              <button className="btn btn-fantasma btn-peq" aria-label="Remover etapa" onClick={() => { setEtapas(renumerar(etapas.filter((_, j) => j !== i))); setCad(cad.filter((c) => c.etapa_ordem !== e.ordem)); }}><Trash2 className="h-3.5 w-3.5" /></button>
            </td></tr>))}</tbody>
      </table></div>
      <button className="btn btn-sec btn-peq mt-2" onClick={() => setEtapas([...etapas, { ordem: etapas.length + 1, nome: `Etapa ${etapas.length + 1}`, etapa_base: 'contato', sla_horas: null, roteiro: null }])}>
        <Plus className="h-3.5 w-3.5" aria-hidden />Adicionar etapa</button>
      <p className="nota mt-1">Regras conferidas no servidor: ordem 1..N, sequência coerente com as etapas oficiais e toda etapa oficial coberta.</p>

      <h4 className="mt-4 mb-1 text-sm font-semibold">Cadência de contatos (guia, sem envio)</h4>
      {cad.map((c, i) => (
        <div key={i} className="mb-1 flex flex-wrap items-center gap-1.5 text-sm">
          <select className="campo" aria-label="Etapa da cadência" value={c.etapa_ordem} onChange={(x) => setCad(cad.map((y, j) => (j === i ? { ...y, etapa_ordem: Number(x.target.value) } : y)))}>
            {etapas.map((e) => <option key={e.ordem} value={e.ordem}>{e.ordem}. {e.nome}</option>)}</select>
          <label className="flex items-center gap-1">dia<input className="campo w-16" type="number" min={0} max={90} value={c.dia} onChange={(x) => setCad(cad.map((y, j) => (j === i ? { ...y, dia: Number(x.target.value) } : y)))} /></label>
          <select className="campo" aria-label="Canal" value={c.canal} onChange={(x) => setCad(cad.map((y, j) => (j === i ? { ...y, canal: x.target.value as CadenciaFunil['canal'] } : y)))}>
            {CANAIS.map((k) => <option key={k} value={k}>{rotulo(k)}</option>)}</select>
          <input className="campo grow" aria-label="Descrição do contato" maxLength={300} value={c.descricao} onChange={(x) => setCad(cad.map((y, j) => (j === i ? { ...y, descricao: x.target.value } : y)))} />
          <button className="btn btn-fantasma btn-peq" aria-label="Remover contato" onClick={() => setCad(cad.filter((_, j) => j !== i))}><Trash2 className="h-3.5 w-3.5" /></button>
        </div>))}
      <button className="btn btn-sec btn-peq" onClick={() => setCad([...cad, { etapa_ordem: etapas.find((e) => e.etapa_base === 'contato')?.ordem ?? 1, passo: 1, dia: 0, canal: 'telefone', descricao: '' }])}>
        <Plus className="h-3.5 w-3.5" aria-hidden />Adicionar contato</button>

      <h4 className="mt-4 mb-1 text-sm font-semibold">Metas de conversão por forma de ingresso (%)</h4>
      <div className="flex flex-wrap gap-2">{FORMAS.map((x) => (
        <Campo key={x} rotulo={rotulo(x)}><input className="campo w-20" inputMode="decimal" value={metas[x] ?? ''} onChange={(e) => setMetas({ ...metas, [x]: e.target.value })} /></Campo>))}</div>
      <Campo rotulo="Notas da versão" className="mt-3"><input className="campo" maxLength={500} value={notas} onChange={(e) => setNotas(e.target.value)} /></Campo>
      <div className="mt-3 flex flex-wrap gap-2">
        <button className="btn btn-peq" disabled={enviando} onClick={() => void fazer(async () => { await api.salvarVersao(v.id, dados()); return 'Rascunho salvo e validado.'; })}>Salvar rascunho</button>
        {podePublicar && <button className="btn btn-ok btn-peq" disabled={enviando} onClick={() => {
          if (!window.confirm(`Publicar a v${v.versao}? A versão publicada fica imutável e passa a valer para novas oportunidades; a anterior é arquivada.`)) return;
          void fazer(async () => { await api.salvarVersao(v.id, dados()); const r = await api.publicarVersao(v.id); return `v${r.versao} publicada${r.arquivada ? `; v${r.arquivada} arquivada` : ''}.`; });
        }}>Salvar e publicar</button>}
      </div>
    </section>
  );
}
