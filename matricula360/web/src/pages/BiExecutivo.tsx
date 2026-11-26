import { AlertOctagon, AlertTriangle, Building2, Download, Printer, TrendingDown, TrendingUp } from 'lucide-react';
import { useState } from 'react';
import { useSessao } from '../components/Layout';
import { Cartao, Detalhes, Estado, Titulo, Vazio } from '../components/ui';
import { api } from '../lib/api';
import { baixarTexto } from '../lib/contrato';
import { moeda } from '../lib/formato';
import { useCarregar } from '../lib/hooks';
import type { ErroApi } from '../lib/supabase';
import type { BiIes } from '../lib/tipos';

const ND = 'N/D';
const fmtPct = (x: number | null | undefined, ja100 = false) => (x == null ? ND : `${(ja100 ? x : x * 100).toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%`);
const fmtMoeda = (c: number | null | undefined) => (c == null ? ND : moeda(c));
const fmtN = (x: number | null | undefined) => (x == null ? ND : x.toLocaleString('pt-BR'));

// Variação contra a coorte anterior: sinal, seta e texto (nunca só cor).
function Delta({ atual, anterior }: { atual: number | null | undefined; anterior: number | null | undefined }) {
  if (atual == null || anterior == null || anterior === 0) return <span className="nota">sem base de comparação</span>;
  const v = ((atual - anterior) / anterior) * 100;
  const Icone = v >= 0 ? TrendingUp : TrendingDown;
  return <span className={`inline-flex items-center gap-1 text-xs ${v >= 0 ? 'text-ok' : 'text-erro'}`}><Icone className="h-3 w-3" aria-hidden />{v >= 0 ? '+' : ''}{v.toFixed(1)}% vs coorte anterior</span>;
}

function Tile({ rotulo, valor, detalhe }: { rotulo: string; valor: string; detalhe?: React.ReactNode }) {
  return (
    <div className="cartao-base flex flex-col gap-1">
      <span className="text-xs font-medium text-suave">{rotulo}</span>
      <strong className="text-2xl font-semibold tracking-tight text-marinho">{valor}</strong>
      {detalhe && <span className="text-xs">{detalhe}</span>}
    </div>
  );
}

// Barra de progresso contra um limite (meter): trilho e preenchimento da mesma família de cor, número sempre escrito.
function Medidor({ rotulo, valor, max, texto }: { rotulo: string; valor: number | null; max: number; texto: string }) {
  const p = valor == null ? 0 : Math.min(100, (valor / max) * 100);
  return (
    <li className="grid grid-cols-[minmax(0,10rem)_1fr_auto] items-center gap-2 text-sm">
      <span className="truncate" title={rotulo}>{rotulo}</span>
      <span className="h-2.5 rounded-full bg-tec-100" role="img" aria-label={`${rotulo}: ${texto}`} title={`${rotulo}: ${texto}`}>
        <span className="block h-2.5 rounded-full bg-tec" style={{ width: `${p}%` }} /></span>
      <span className="tabular-nums">{texto}</span>
    </li>
  );
}

// Ranking em barras horizontais, uma cor (magnitude), maior primeiro, valor escrito ao lado.
function Ranking({ itens }: { itens: { rotulo: string; valor: number; texto: string }[] }) {
  const max = Math.max(1, ...itens.map((i) => i.valor));
  return (
    <ul className="space-y-1.5">{[...itens].sort((a, b) => b.valor - a.valor).map((i) => (
      <li key={i.rotulo} className="grid grid-cols-[minmax(0,10rem)_1fr_auto] items-center gap-2 text-sm">
        <span className="truncate" title={i.rotulo}>{i.rotulo}</span>
        <span className="h-3" title={`${i.rotulo}: ${i.texto}`}><span className="block h-3 rounded-r bg-tec" style={{ width: `${(100 * i.valor) / max}%`, minWidth: i.valor ? 3 : 0 }} /></span>
        <span className="tabular-nums">{i.texto}</span>
      </li>))}</ul>
  );
}

function Alertas({ lista }: { lista: { nivel: string; texto: string; ies?: string }[] }) {
  if (!lista.length) return <p className="text-sm text-ok">Nenhum alerta pelas regras executivas.</p>;
  return (
    <ul className="space-y-1 text-sm">{lista.map((a, i) => (
      <li key={i} className="flex items-start gap-2">
        {a.nivel === 'critico' ? <AlertOctagon className="mt-0.5 h-4 w-4 shrink-0 text-erro" aria-hidden /> : <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-alerta" aria-hidden />}
        <span><strong className={a.nivel === 'critico' ? 'text-erro' : 'text-alerta'}>{a.nivel === 'critico' ? 'Crítico' : 'Atenção'}:</strong> {a.ies ? `${a.ies} — ` : ''}{a.texto}</span>
      </li>))}</ul>
  );
}

function csv(ies: BiIes[], coorte: string): string {
  const cab = ['IES', 'Coorte', 'Oportunidades', 'Matrículas comerciais', 'Ingressos', 'Meta', 'Atingimento %', 'Conversão %', 'Custo por lead (R$)', 'Custo por ingresso (R$)',
    'Payback (mensalidades)', 'Receita mensal dos ingressos (R$)', 'Ticket médio (R$)', 'Desconto médio %', 'Renúncia mensal estimada (R$)', 'Ingressos com benefício %',
    'Inadimplência %', 'Rematrícula %', 'Casos abertos', 'Casos vencidos', 'NPS', 'Alertas'];
  const n = (x: number | null | undefined, f = 1) => (x == null ? '' : String(Math.round(x * f * 100) / 100).replace('.', ','));
  const linhas = ies.map((i) => [i.nome, coorte, i.atual.oportunidades, i.atual.matriculas_comerciais, i.atual.ingressantes, i.atual.meta ?? '', n(i.atual.atingimento, 100), n(i.atual.conversao, 100),
    n(i.atual.custo_por_lead_centavos, 0.01), n(i.atual.custo_por_matricula_centavos, 0.01), n(i.payback_mensalidades), n(i.atual.receita_mensal_ingressantes_centavos, 0.01),
    n(i.receita.ticket_medio_centavos, 0.01), n(i.receita.desconto_medio_pct), n(i.bolsas.renuncia_mensal_estimada_centavos, 0.01), n(i.bolsas.ingressos_com_beneficio_pct),
    n(i.inadimplencia.pct), n(i.rematricula?.taxa_pct), i.casos?.abertos ?? 0, i.casos?.vencidos ?? 0, i.nps?.nps ?? '', i.alertas.map((a) => a.texto).join(' | ')]);
  return '﻿' + [cab, ...linhas].map((l) => l.map((v) => `"${String(v).replace(/"/g, '""')}"`).join(';')).join('\r\n');
}

// BI da alta gestão: consolidado da mantenedora e ciclo completo por IES, só com números agregados.
export function BiExecutivo() {
  const { estrutura } = useSessao();
  const [coorte, setCoorte] = useState(estrutura?.coortes[0] ?? '');
  const r = useCarregar(() => (coorte ? api.biExecutivo(coorte) : Promise.resolve(null)), [coorte]);
  const d = r.dados;
  const t = d?.consolidado;
  const alertas = (d?.ies ?? []).flatMap((i) => i.alertas.map((a) => ({ ...a, ies: d!.ies.length > 1 ? i.nome : undefined }))).sort((a, b) => (a.nivel === b.nivel ? 0 : a.nivel === 'critico' ? -1 : 1));
  return (
    <>
      <Titulo titulo="BI da alta gestão" subtitulo="Consolidado das instituições e ciclo completo: captação, receita, bolsas, eficiência, retenção, inadimplência e satisfação." />
      <div className="mb-4 flex flex-wrap items-end gap-2 print:hidden">
        <label className="text-sm">Coorte <select className="campo ml-1 w-auto" value={coorte} onChange={(e) => setCoorte(e.target.value)}>{estrutura?.coortes.map((c) => <option key={c} value={c}>{c}</option>)}</select></label>
        {d && <button className="btn btn-sec btn-peq" onClick={() => baixarTexto(`bi-alta-gestao-${d.coorte}.csv`, 'text/csv', csv(d.ies, d.coorte))}><Download className="h-3.5 w-3.5" aria-hidden />Exportar CSV</button>}
        {d && <button className="btn btn-sec btn-peq" onClick={() => window.print()}><Printer className="h-3.5 w-3.5" aria-hidden />Imprimir ou salvar em PDF</button>}
      </div>
      {(r.erro as ErroApi | null)?.codigo === 'PGRST202' ? <Vazio texto="Disponível após a migração 32 do banco." /> : <Estado carregando={r.carregando && !d} erro={r.erro} />}
      {d && t && (
        <div className="space-y-4">
          <p className="nota">Coorte {d.coorte}, comparada a {d.coorte_anterior} · {d.ies.length} instituição(ões): {d.ies.map((i) => i.nome).join(', ')}</p>
          <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
            <Tile rotulo="Ingressos efetivos" valor={fmtN(t.ingressantes)} detalhe={<>{t.meta != null ? `meta ${t.meta} · atingimento ${fmtPct(t.atingimento)} · ` : 'meta consolidada N/D · '}<Delta atual={t.ingressantes} anterior={t.anterior_ingressantes} /></>} />
            <Tile rotulo="Receita mensal dos ingressos" valor={fmtMoeda(t.receita_mensal_ingressantes_centavos)} detalhe={<Delta atual={t.receita_mensal_ingressantes_centavos} anterior={t.anterior_receita_mensal_ingressantes_centavos} />} />
            <Tile rotulo="Oportunidades (leads)" valor={fmtN(t.oportunidades)} detalhe={<>{fmtN(t.matriculas_comerciais)} matrículas comerciais · <Delta atual={t.oportunidades} anterior={t.anterior_oportunidades} /></>} />
            <Tile rotulo="Renúncia mensal estimada (bolsas)" valor={fmtMoeda(t.renuncia_mensal_estimada_centavos)} detalhe="estimativa pelo valor de tabela" />
            <Tile rotulo="Inadimplência (> 30 dias)" valor={fmtPct(t.inadimplencia_pct, true)} detalhe={`${fmtN(t.inadimplentes)} de ${fmtN(t.alunos)} aluno(s)`} />
            <Tile rotulo="Casos do aluno abertos" valor={fmtN(t.casos_abertos)} detalhe={`${fmtN(t.casos_vencidos)} vencido(s)`} />
            <Tile rotulo="Cancelamentos na coorte" valor={fmtN(t.cancelamentos)} />
            <Tile rotulo="Alertas executivos" valor={fmtN(t.alertas)} />
          </div>
          <Cartao titulo="Alertas executivos (regras fixas)"><Alertas lista={alertas} /></Cartao>
          {d.ies.length > 1 && (
            <div className="grid gap-4 lg:grid-cols-2">
              <Cartao titulo="Atingimento da meta por instituição">
                <ul className="space-y-2">{d.ies.map((i) => <Medidor key={i.ies_id} rotulo={i.nome} valor={i.atual.atingimento} max={1}
                  texto={i.atual.meta == null ? 'sem meta' : `${fmtPct(i.atual.atingimento)} (${i.atual.ingressantes}/${i.atual.meta})`} />)}</ul>
              </Cartao>
              <Cartao titulo="Receita mensal dos ingressos por instituição">
                <Ranking itens={d.ies.map((i) => ({ rotulo: i.nome, valor: i.atual.receita_mensal_ingressantes_centavos, texto: fmtMoeda(i.atual.receita_mensal_ingressantes_centavos) }))} />
              </Cartao>
            </div>)}
          {d.ies.map((i) => <CartaoIes key={i.ies_id} i={i} />)}
          {d.ies.length > 1 && (
            <Cartao titulo="Comparativo da mantenedora" icone={Building2}>
              <div className="tabela" tabIndex={0} role="region" aria-label="Tabela com rolagem horizontal"><table>
                <thead><tr><th>Indicador</th>{d.ies.map((i) => <th key={i.ies_id}>{i.nome}</th>)}</tr></thead>
                <tbody>{([
                  ['Ingressos', (i: BiIes) => fmtN(i.atual.ingressantes)], ['Atingimento', (i: BiIes) => fmtPct(i.atual.atingimento)], ['Conversão', (i: BiIes) => fmtPct(i.atual.conversao)],
                  ['Custo por ingresso', (i: BiIes) => fmtMoeda(i.atual.custo_por_matricula_centavos)], ['Payback (mensalidades)', (i: BiIes) => (i.payback_mensalidades == null ? ND : String(i.payback_mensalidades))],
                  ['Ticket médio', (i: BiIes) => fmtMoeda(i.receita.ticket_medio_centavos)], ['Desconto médio', (i: BiIes) => fmtPct(i.receita.desconto_medio_pct, true)],
                  ['Ingressos com benefício', (i: BiIes) => fmtPct(i.bolsas.ingressos_com_beneficio_pct, true)], ['Inadimplência', (i: BiIes) => fmtPct(i.inadimplencia.pct, true)],
                  ['Rematrícula', (i: BiIes) => fmtPct(i.rematricula?.taxa_pct, true)], ['NPS', (i: BiIes) => (i.nps ? String(i.nps.nps) : ND)],
                ] as [string, (i: BiIes) => string][]).map(([rot, f]) => <tr key={rot}><td>{rot}</td>{d.ies.map((i) => <td key={i.ies_id} className="tabular-nums">{f(i)}</td>)}</tr>)}</tbody>
              </table></div>
            </Cartao>)}
          <Detalhes titulo="Como cada número é calculado">
            <ul className="list-disc space-y-1 pl-5 text-sm">{Object.entries(d.metodos).map(([k, v]) => <li key={k}>{v}</li>)}</ul>
          </Detalhes>
        </div>)}
    </>
  );
}

function CartaoIes({ i }: { i: BiIes }) {
  const a = i.atual; const p = i.anterior;
  const funil = [{ rotulo: 'Oportunidades', valor: a.oportunidades }, { rotulo: 'Matrículas comerciais', valor: a.matriculas_comerciais }, { rotulo: 'Ingressos efetivos', valor: a.ingressantes }];
  return (
    <Cartao titulo={i.nome} icone={Building2}>
      <div className="grid gap-4 lg:grid-cols-3">
        <section aria-label="Captação">
          <h3 className="mb-2 text-sm font-semibold">Captação</h3>
          <Ranking itens={funil.map((f) => ({ ...f, texto: fmtN(f.valor) }))} />
          <p className="mt-2 text-xs">Conversão {fmtPct(a.conversao)} · atingimento {fmtPct(a.atingimento)}{a.meta != null ? ` (meta ${a.meta})` : ''}</p>
          <p className="text-xs">Projeção: {a.cenario_pipeline?.projecao_ingressos != null ? `${a.cenario_pipeline.projecao_ingressos} ingressos` : ND}{a.forecast_motivo ? ` — ${a.forecast_motivo}` : ''}</p>
          <p className="text-xs">Ingressos <Delta atual={a.ingressantes} anterior={p.ingressantes} /></p>
        </section>
        <section aria-label="Receita e eficiência">
          <h3 className="mb-2 text-sm font-semibold">Receita e eficiência</h3>
          <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-sm">
            <dt className="text-suave">Receita mensal dos ingressos</dt><dd className="tabular-nums">{fmtMoeda(a.receita_mensal_ingressantes_centavos)}</dd>
            <dt className="text-suave">Ticket médio</dt><dd className="tabular-nums">{fmtMoeda(i.receita.ticket_medio_centavos)}</dd>
            <dt className="text-suave">Desconto médio</dt><dd className="tabular-nums">{fmtPct(i.receita.desconto_medio_pct, true)}</dd>
            <dt className="text-suave">Custo por lead</dt><dd className="tabular-nums">{fmtMoeda(a.custo_por_lead_centavos)}</dd>
            <dt className="text-suave">Custo por ingresso</dt><dd className="tabular-nums">{fmtMoeda(a.custo_por_matricula_centavos)}</dd>
            <dt className="text-suave">Payback</dt><dd className="tabular-nums">{i.payback_mensalidades == null ? ND : `${i.payback_mensalidades} mensalidade(s)`}</dd>
            <dt className="text-suave">Bolsas</dt><dd className="tabular-nums">{i.bolsas.beneficios_aprovados} aprovada(s) · {fmtPct(i.bolsas.ingressos_com_beneficio_pct, true)} dos ingressos · renúncia {fmtMoeda(i.bolsas.renuncia_mensal_estimada_centavos)}/mês</dd>
          </dl>
          {a.custo_motivo && <p className="nota mt-1">{a.custo_motivo}</p>}
        </section>
        <section aria-label="Retenção e experiência">
          <h3 className="mb-2 text-sm font-semibold">Retenção e experiência</h3>
          <ul className="space-y-2">
            {(i.permanencia ?? []).map((m) => <Medidor key={m.marco} rotulo={`Permanência ${m.marco === 'd30' ? '30 dias' : m.marco === 'd90' ? '90 dias' : 'rematrícula'}`} valor={m.permanencia} max={1} texto={m.permanencia == null ? ND : fmtPct(m.permanencia)} />)}
            {i.rematricula && <Medidor rotulo={`Rematrícula ${i.rematricula.periodo}`} valor={i.rematricula.taxa_pct} max={100} texto={`${fmtPct(i.rematricula.taxa_pct, true)}${i.rematricula.meta_pct ? ` (meta ${i.rematricula.meta_pct}%)` : ''}`} />}
            <Medidor rotulo="Inadimplência" valor={i.inadimplencia.pct} max={100} texto={fmtPct(i.inadimplencia.pct, true)} />
          </ul>
          <p className="mt-2 text-sm">Casos: {i.casos?.abertos ?? 0} aberto(s), {i.casos?.vencidos ?? 0} vencido(s){i.casos?.horas_medias_resolucao != null ? ` · resolução média ${i.casos.horas_medias_resolucao} h` : ''}</p>
          <p className="text-sm">NPS: {i.nps ? <><strong>{i.nps.nps}</strong> <span className="nota">({i.nps.pesquisa}, {i.nps.respostas} respostas)</span></> : <span className="nota">N/D (sem pesquisa com respostas suficientes)</span>}</p>
        </section>
      </div>
      {i.alertas.length > 0 && <div className="mt-3 border-t border-linha pt-2"><Alertas lista={i.alertas} /></div>}
    </Cartao>
  );
}
