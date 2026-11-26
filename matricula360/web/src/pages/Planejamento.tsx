import { ClipboardList, ExternalLink, Flag, Scale, Target } from 'lucide-react';
import { useState } from 'react';
import { BarraFiltros, useSessao } from '../components/Layout';
import { Aviso, Campo, Cartao, Chip, Detalhes, Estado, Mensagem, Titulo, Valor, Vazio } from '../components/ui';
import { api } from '../lib/api';
import { centavos, dataHora, moeda, ND, num, pct, rotulo } from '../lib/formato';
import { useAcao, useCarregar } from '../lib/hooks';
import type { ErroApi } from '../lib/supabase';
import type { Indicador, Plano } from '../lib/tipos';

const INDICADORES: Indicador[] = ['ingressantes', 'oportunidades', 'matriculas_comerciais', 'conversao', 'cpl_centavos', 'custo_ingressante_centavos'];
export const valorIndicador = (ind: Indicador, v: number | null | undefined) =>
  v == null ? ND : ind.endsWith('centavos') ? moeda(Number(v)) : ind === 'conversao' ? pct(Number(v)) : num(Number(v));
const semMigracao = (e: Error | null) => Boolean(e && ((e as ErroApi).codigo === 'PGRST202'));
const TIPO_STATUS: Record<string, 'ok' | 'pend' | 'erro' | 'tec' | undefined> = { aprovado: 'ok', em_aprovacao: 'pend', em_revisao: 'pend', rascunho: 'tec', encerrado: undefined };

export function Planejamento() {
  const { ies, filtros, tem } = useSessao();
  const coorte = filtros.coorte;
  const [recarga, setRecarga] = useState(0);
  const p = useCarregar(() => (ies && coorte ? api.planejamento(ies, coorte) : Promise.resolve(null)), [ies, coorte, recarga]);
  const acao = useAcao();
  const fazer = (fn: () => Promise<string>) => acao.executar(async () => { const t = await fn(); setRecarga((n) => n + 1); return t; });

  return (
    <>
      <Titulo titulo="Planejamento Estratégico" subtitulo="Plano da coorte: diagnóstico, objetivos com indicador, orçamento e ações 5W2H. O realizado vem dos dados, nunca é digitado." />
      <BarraFiltros completos={false} />
      {semMigracao(p.erro) ? <Vazio texto="Disponível após a migração 12 do banco." /> : <Estado carregando={p.carregando && !p.dados} erro={p.erro} />}
      <Mensagem m={acao.mensagem} />
      {p.dados && (
        <div className="space-y-5">
          {p.dados.pode_editar && <NovoPlano coorte={coorte} fazer={fazer} enviando={acao.enviando} />}
          {!p.dados.planos.length && <Vazio texto={`Nenhum plano para a coorte ${coorte}.`} detalhe={p.dados.pode_editar ? 'Crie o plano acima.' : 'O gestor da instituição cria o plano.'} />}
          {p.dados.planos.map((pl) => <CartaoPlano key={pl.id} pl={pl} podeEditar={p.dados!.pode_editar} podeAprovar={p.dados!.pode_aprovar} fazer={fazer} enviando={acao.enviando} metodo={p.dados!.metodos.realizado} />)}
        </div>
      )}
      {ies && (tem('gestor', 'reitoria', 'coordenador')) && !semMigracao(p.erro) && <Concorrencia />}
    </>
  );
}

// Barra de progresso simples, proporcional ao valor (limitada a 100% no desenho; o rótulo mostra o valor real).
function Barra({ fracao, rotulo: r }: { fracao: number; rotulo: string }) {
  const f = Math.max(0, Math.min(1, fracao));
  return (<div className="min-w-[90px] text-xs"><span>{r}</span><div className="mt-0.5 h-1.5 rounded-full bg-fundo" role="img" aria-label={r}>
    <div className={`h-1.5 rounded-full ${f >= 1 ? 'bg-ok' : f >= 0.5 ? 'bg-tec' : 'bg-alerta'}`} style={{ width: `${f * 100}%` }} /></div></div>);
}

type Fazer = (fn: () => Promise<string>) => Promise<void>;

function NovoPlano({ coorte, fazer, enviando }: { coorte: string; fazer: Fazer; enviando: boolean }) {
  const { ies } = useSessao();
  const [f, setF] = useState({ titulo: '', diagnostico: '', orcamento: '', revisar_em: '' });
  return (
    <Detalhes titulo={`Novo plano para ${coorte}`}>
      <form className="grid gap-2 sm:grid-cols-2" onSubmit={(e) => { e.preventDefault(); void fazer(async () => {
        await api.salvarPlano(ies!, { coorte, titulo: f.titulo, diagnostico: f.diagnostico, orcamento_centavos: f.orcamento ? centavos(f.orcamento) : 0, revisar_em: f.revisar_em });
        setF({ titulo: '', diagnostico: '', orcamento: '', revisar_em: '' }); return 'Plano criado em rascunho.'; }); }}>
        <Campo rotulo="Título"><input className="campo" required minLength={3} maxLength={120} value={f.titulo} onChange={(e) => setF({ ...f, titulo: e.target.value })} /></Campo>
        <Campo rotulo="Orçamento total (R$)"><input className="campo" inputMode="decimal" placeholder="50.000,00" value={f.orcamento} onChange={(e) => setF({ ...f, orcamento: e.target.value })} /></Campo>
        <Campo rotulo="Diagnóstico comercial" className="sm:col-span-2"><textarea className="campo min-h-[70px]" maxLength={4000} value={f.diagnostico} onChange={(e) => setF({ ...f, diagnostico: e.target.value })} /></Campo>
        <Campo rotulo="Revisar em"><input className="campo" type="date" value={f.revisar_em} onChange={(e) => setF({ ...f, revisar_em: e.target.value })} /></Campo>
        <div className="flex items-end"><button className="btn" disabled={enviando}>Criar plano</button></div>
      </form>
    </Detalhes>
  );
}

function CartaoPlano({ pl, podeEditar, podeAprovar, fazer, enviando, metodo }: { pl: Plano; podeEditar: boolean; podeAprovar: boolean; fazer: Fazer; enviando: boolean; metodo: string }) {
  const { estrutura } = useSessao();
  const editavel = podeEditar && ['rascunho', 'em_revisao'].includes(pl.status);
  const status = (acao: string, pede: boolean) => {
    const j = pede ? window.prompt('Justificativa (obrigatória):') : undefined;
    if (pede && !j) return;
    void fazer(async () => { const r = await api.planoStatus(pl.id, acao, j ?? undefined); return `Plano: ${rotulo(r.status)}.`; });
  };
  const [o, setO] = useState({ descricao: '', indicador: 'ingressantes' as Indicador, curso_id: '', meta: '', prazo: '' });
  const [a, setA] = useState({ objetivo_id: '', o_que: '', por_que: '', onde: '', quando: '', quem: '', como: '', quanto: '' });
  return (
    <Cartao titulo={pl.titulo} icone={ClipboardList} acao={<span><Chip tipo={TIPO_STATUS[pl.status]}>{rotulo(pl.status)}</Chip><Chip>versão {pl.versao}</Chip></span>}>
      <p className="nota mb-2">Criado por {pl.criado_por ?? '—'}{pl.aprovado_por ? ` · aprovado por ${pl.aprovado_por} em ${dataHora(pl.aprovado_em)}` : ''}
        {pl.revisar_em ? ` · revisão prevista para ${new Date(`${pl.revisar_em}T12:00:00`).toLocaleDateString('pt-BR')}` : ''}</p>
      {pl.revisao_vencida && <p className="mb-2"><Chip tipo="erro">Revisão periódica vencida</Chip></p>}
      {pl.diagnostico && <p className="mb-3 whitespace-pre-line text-sm">{pl.diagnostico}</p>}
      <div className="mb-3 flex flex-wrap gap-1.5">
        {podeEditar && ['rascunho', 'em_revisao'].includes(pl.status) && <button className="btn btn-peq" disabled={enviando} onClick={() => status('submeter', false)}>Submeter para aprovação</button>}
        {podeAprovar && pl.status === 'em_aprovacao' && (pl.criado_por_mim
          ? <span className="nota">Aprovação por outra pessoa (segregação de funções).</span>
          : <><button className="btn btn-ok btn-peq" disabled={enviando} onClick={() => status('aprovar', false)}>Aprovar</button>
              <button className="btn btn-sec btn-peq" disabled={enviando} onClick={() => status('devolver', true)}>Devolver</button></>)}
        {podeEditar && pl.status === 'aprovado' && <><button className="btn btn-sec btn-peq" disabled={enviando} onClick={() => status('revisar', true)}>Abrir revisão</button>
          <button className="btn btn-sec btn-peq" disabled={enviando} onClick={() => status('encerrar', true)}>Encerrar</button></>}
      </div>
      {pl.orcamento_centavos != null && (
        <div className="mb-4 grid gap-2 sm:grid-cols-3">
          <div><p className="nota">Orçamento</p><p className="font-semibold">{moeda(pl.orcamento_centavos)}</p></div>
          <div><p className="nota">Alocado em campanhas</p><p className="font-semibold">{moeda(pl.orcamento_alocado_centavos ?? 0)}</p></div>
          <div><p className="nota">Gasto lançado</p><p className="font-semibold">{moeda(pl.gasto_centavos ?? 0)}</p>
            {pl.orcamento_centavos > 0 && <Barra fracao={(pl.gasto_centavos ?? 0) / pl.orcamento_centavos} rotulo={`${pct((pl.gasto_centavos ?? 0) / pl.orcamento_centavos)} executado`} />}</div>
        </div>
      )}
      <h3 className="mb-1 flex items-center gap-1.5 font-semibold text-marinho"><Target className="h-4 w-4 text-tec" aria-hidden />Objetivos e indicadores</h3>
      {pl.objetivos.length ? (
        <div className="tabela mb-2"><table>
          <thead><tr>{['Objetivo', 'Indicador', 'Recorte', 'Meta', 'Realizado', 'Atingimento'].map((c) => <th key={c} scope="col">{c}</th>)}</tr></thead>
          <tbody>{pl.objetivos.map((x) => {
            const menorMelhor = x.indicador.endsWith('centavos');
            const at = x.realizado == null || !x.meta ? null : menorMelhor ? Number(x.meta) / Number(x.realizado) : Number(x.realizado) / Number(x.meta);
            return (<tr key={x.id}><td>{x.descricao}{x.prazo && <span className="block text-xs text-suave">prazo {new Date(`${x.prazo}T12:00:00`).toLocaleDateString('pt-BR')}</span>}</td>
              <td>{rotulo(x.indicador)}</td><td>{x.curso ?? 'Instituição'}</td><td>{valorIndicador(x.indicador, x.meta)}</td>
              <td><Valor v={valorIndicador(x.indicador, x.realizado)} /></td>
              <td>{at == null ? <Valor v={ND} /> : <Barra fracao={at} rotulo={pct(at)} />}</td></tr>);
          })}</tbody>
        </table></div>
      ) : <p className="nota mb-2">Nenhum objetivo.</p>}
      <p className="nota mb-3">{metodo} Para custos, atingimento = meta ÷ realizado (menor é melhor).</p>
      {editavel && (
        <form className="mb-4 flex flex-wrap items-end gap-2" onSubmit={(e) => { e.preventDefault(); void fazer(async () => {
          const meta = o.indicador.endsWith('centavos') ? centavos(o.meta) : o.indicador === 'conversao' ? Number(o.meta.replace(',', '.')) / 100 : Number(o.meta);
          await api.salvarObjetivo(pl.id, { descricao: o.descricao, indicador: o.indicador, curso_id: o.curso_id, meta, prazo: o.prazo });
          setO({ ...o, descricao: '', meta: '' }); return 'Objetivo salvo.'; }); }}>
          <Campo rotulo="Novo objetivo" className="grow"><input className="campo" required minLength={3} maxLength={300} value={o.descricao} onChange={(e) => setO({ ...o, descricao: e.target.value })} /></Campo>
          <Campo rotulo="Indicador"><select className="campo" value={o.indicador} onChange={(e) => setO({ ...o, indicador: e.target.value as Indicador })}>{INDICADORES.map((i) => <option key={i} value={i}>{rotulo(i)}</option>)}</select></Campo>
          <Campo rotulo="Recorte"><select className="campo" value={o.curso_id} onChange={(e) => setO({ ...o, curso_id: e.target.value })} disabled={o.indicador.endsWith('centavos')}>
            <option value="">Instituição</option>{estrutura?.cursos.map((c) => <option key={c.id} value={c.id}>{c.nome} · {c.turno}</option>)}</select></Campo>
          <Campo rotulo={o.indicador.endsWith('centavos') ? 'Meta (R$)' : o.indicador === 'conversao' ? 'Meta (%)' : 'Meta'}><input className="campo w-28" required inputMode="decimal" value={o.meta} onChange={(e) => setO({ ...o, meta: e.target.value })} /></Campo>
          <Campo rotulo="Prazo"><input className="campo" type="date" value={o.prazo} onChange={(e) => setO({ ...o, prazo: e.target.value })} /></Campo>
          <button className="btn btn-peq" disabled={enviando}>Adicionar objetivo</button>
        </form>
      )}
      <h3 className="mb-1 flex items-center gap-1.5 font-semibold text-marinho"><Flag className="h-4 w-4 text-tec" aria-hidden />Ações 5W2H</h3>
      {pl.acoes.length ? (
        <div className="tabela mb-2"><table>
          <thead><tr>{['O quê / por quê', 'Onde', 'Quando', 'Quem', 'Como', 'Quanto', 'Status'].map((c) => <th key={c} scope="col">{c}</th>)}</tr></thead>
          <tbody>{pl.acoes.map((x) => (
            <tr key={x.id}><td><strong>{x.o_que}</strong><span className="block text-xs text-suave">{x.por_que}</span></td><td>{x.onde ?? '—'}</td>
              <td>{new Date(`${x.quando}T12:00:00`).toLocaleDateString('pt-BR')}{x.atrasada && <Chip tipo="erro">atrasada</Chip>}</td><td>{x.quem}</td><td>{x.como ?? '—'}</td>
              <td>{x.quanto_centavos == null ? '—' : moeda(x.quanto_centavos)}</td>
              <td>{podeEditar && ['rascunho', 'em_revisao', 'aprovado'].includes(pl.status)
                ? <select className="campo text-xs" aria-label={`Status da ação ${x.o_que}`} value={x.status} disabled={enviando}
                    onChange={(e) => void fazer(async () => { await api.salvarAcao(pl.id, { status: e.target.value }, x.id); return 'Status da ação atualizado.'; })}>
                    {['pendente', 'em_andamento', 'concluida', 'cancelada'].map((s) => <option key={s} value={s}>{rotulo(s)}</option>)}</select>
                : rotulo(x.status)}</td></tr>
          ))}</tbody>
        </table></div>
      ) : <p className="nota mb-2">Nenhuma ação.</p>}
      {editavel && (
        <form className="grid gap-2 sm:grid-cols-4" onSubmit={(e) => { e.preventDefault(); void fazer(async () => {
          await api.salvarAcao(pl.id, { objetivo_id: a.objetivo_id, o_que: a.o_que, por_que: a.por_que, onde: a.onde, quando: a.quando, quem: a.quem, como: a.como, quanto_centavos: a.quanto ? centavos(a.quanto) : 0 });
          setA({ objetivo_id: '', o_que: '', por_que: '', onde: '', quando: '', quem: '', como: '', quanto: '' }); return 'Ação 5W2H adicionada.'; }); }}>
          <Campo rotulo="O quê (What)" className="sm:col-span-2"><input className="campo" required minLength={3} maxLength={200} value={a.o_que} onChange={(e) => setA({ ...a, o_que: e.target.value })} /></Campo>
          <Campo rotulo="Por quê (Why)" className="sm:col-span-2"><input className="campo" required minLength={3} maxLength={400} value={a.por_que} onChange={(e) => setA({ ...a, por_que: e.target.value })} /></Campo>
          <Campo rotulo="Onde (Where)"><input className="campo" value={a.onde} onChange={(e) => setA({ ...a, onde: e.target.value })} /></Campo>
          <Campo rotulo="Quando (When)"><input className="campo" type="date" required value={a.quando} onChange={(e) => setA({ ...a, quando: e.target.value })} /></Campo>
          <Campo rotulo="Quem (Who)"><input className="campo" required minLength={2} maxLength={120} value={a.quem} onChange={(e) => setA({ ...a, quem: e.target.value })} /></Campo>
          <Campo rotulo="Quanto (How much, R$)"><input className="campo" inputMode="decimal" value={a.quanto} onChange={(e) => setA({ ...a, quanto: e.target.value })} /></Campo>
          <Campo rotulo="Como (How)" className="sm:col-span-2"><input className="campo" value={a.como} onChange={(e) => setA({ ...a, como: e.target.value })} /></Campo>
          <Campo rotulo="Objetivo vinculado"><select className="campo" value={a.objetivo_id} onChange={(e) => setA({ ...a, objetivo_id: e.target.value })}>
            <option value="">—</option>{pl.objetivos.map((x) => <option key={x.id} value={x.id}>{x.descricao}</option>)}</select></Campo>
          <div className="flex items-end"><button className="btn btn-peq" disabled={enviando}>Adicionar ação</button></div>
        </form>
      )}
    </Cartao>
  );
}

function Concorrencia() {
  const { ies, tem } = useSessao();
  const [recarga, setRecarga] = useState(0);
  const r = useCarregar(() => api.concorrencia(ies!), [ies, recarga]);
  const acao = useAcao();
  const [f, setF] = useState({ instituicao: '', curso: '', modalidade: '', mensalidade: '', fonte_url: '', coletado_em: '', observacao: '' });
  const fazer = (fn: () => Promise<string>) => acao.executar(async () => { const t = await fn(); setRecarga((n) => n + 1); return t; });
  return (
    <Cartao titulo="Concorrência (somente com fonte verificável)" icone={Scale} className="mt-5">
      <Aviso>Cada registro exige endereço da fonte e data de coleta, e é revisado por pessoa diferente de quem registrou. Não registre ofertas sem fonte.</Aviso>
      <Estado carregando={r.carregando && !r.dados} erro={r.erro} />
      {r.dados?.length ? (
        <div className="tabela my-3"><table>
          <thead><tr>{['Instituição / curso', 'Mensalidade', 'Fonte', 'Coleta', 'Revisão'].map((c) => <th key={c} scope="col">{c}</th>)}</tr></thead>
          <tbody>{r.dados.map((x) => (
            <tr key={x.id}><td><strong>{x.instituicao}</strong><span className="block text-xs">{x.curso}{x.modalidade ? ` · ${rotulo(x.modalidade)}` : ''}</span>
              {x.observacao && <span className="block text-xs text-suave">{x.observacao}</span>}</td>
              <td>{x.mensalidade_centavos == null ? '—' : moeda(x.mensalidade_centavos)}</td>
              <td><a className="inline-flex items-center gap-1 text-tec hover:underline" href={x.fonte_url} target="_blank" rel="noopener noreferrer nofollow">abrir<ExternalLink className="h-3 w-3" aria-hidden /></a></td>
              <td>{new Date(`${x.coletado_em}T12:00:00`).toLocaleDateString('pt-BR')} · {x.registrado_por}{x.desatualizado && <Chip tipo="pend">mais de 180 dias</Chip>}</td>
              <td>{x.revisado_em ? <Chip tipo="ok">revisado por {x.revisado_por}</Chip>
                : tem('gestor') && !x.registrado_por_mim ? <button className="btn btn-peq" disabled={acao.enviando} onClick={() => void fazer(async () => { await api.revisarConcorrencia(x.id); return 'Registro revisado.'; })}>Revisar</button>
                : <Chip tipo="pend">aguardando revisão</Chip>}</td></tr>
          ))}</tbody>
        </table></div>
      ) : r.dados && <p className="nota my-3">Nenhum registro.</p>}
      <Mensagem m={acao.mensagem} />
      {tem('gestor', 'coordenador') && (
        <Detalhes titulo="Registrar oferta concorrente">
          <form className="grid gap-2 sm:grid-cols-3" onSubmit={(e) => { e.preventDefault(); void fazer(async () => {
            await api.registrarConcorrencia(ies!, { ...f, mensalidade_centavos: f.mensalidade ? centavos(f.mensalidade) : '' });
            setF({ instituicao: '', curso: '', modalidade: '', mensalidade: '', fonte_url: '', coletado_em: '', observacao: '' }); return 'Registro incluído; aguarda revisão.'; }); }}>
            <Campo rotulo="Instituição"><input className="campo" required minLength={2} value={f.instituicao} onChange={(e) => setF({ ...f, instituicao: e.target.value })} /></Campo>
            <Campo rotulo="Curso"><input className="campo" required minLength={2} value={f.curso} onChange={(e) => setF({ ...f, curso: e.target.value })} /></Campo>
            <Campo rotulo="Modalidade"><select className="campo" value={f.modalidade} onChange={(e) => setF({ ...f, modalidade: e.target.value })}><option value="">—</option>{['presencial', 'semipresencial', 'ead'].map((m) => <option key={m} value={m}>{rotulo(m)}</option>)}</select></Campo>
            <Campo rotulo="Mensalidade (R$)"><input className="campo" inputMode="decimal" value={f.mensalidade} onChange={(e) => setF({ ...f, mensalidade: e.target.value })} /></Campo>
            <Campo rotulo="Fonte (endereço http/https)"><input className="campo" type="url" required value={f.fonte_url} onChange={(e) => setF({ ...f, fonte_url: e.target.value })} /></Campo>
            <Campo rotulo="Data da coleta"><input className="campo" type="date" required value={f.coletado_em} onChange={(e) => setF({ ...f, coletado_em: e.target.value })} /></Campo>
            <Campo rotulo="Observação" className="sm:col-span-2"><input className="campo" maxLength={500} value={f.observacao} onChange={(e) => setF({ ...f, observacao: e.target.value })} /></Campo>
            <div className="flex items-end"><button className="btn btn-peq" disabled={acao.enviando}>Registrar</button></div>
          </form>
        </Detalhes>
      )}
    </Cartao>
  );
}
