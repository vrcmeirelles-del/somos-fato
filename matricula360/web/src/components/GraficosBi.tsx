// Gráficos do BI em SVG puro (sem biblioteca): marcas finas, grade discreta, legenda e rótulos diretos,
// leitura ao passar o mouse e tabela para leitores de tela. Cores validadas (guia de visualização):
// azul #257de0 e laranja #f47230 para séries; rampa ordinal de azul para faixas ordenadas.
import { useEffect, useRef, useState, type ReactNode } from 'react';

// Largura real do gráfico: o SVG é desenhado nessa largura, então o texto mantém o tamanho legível no celular.
function useLargura(padrao = 600): [React.RefObject<HTMLElement>, number] {
  const ref = useRef<HTMLElement>(null);
  const [w, setW] = useState(padrao);
  useEffect(() => {
    const el = ref.current; if (!el || typeof ResizeObserver === 'undefined') return;
    const ro = new ResizeObserver(([e]) => { const x = Math.round(e!.contentRect.width); if (x > 0) setW(Math.max(280, x)); });
    ro.observe(el); return () => ro.disconnect();
  }, []);
  return [ref, w];
}

export const COR_SERIE = ['#257de0', '#f47230'];
export const RAMPA_ORDINAL = ['#84b9f3', '#338ced', '#1b64be', '#0e3d7e'];
const GRADE = '#e5e7eb';
const TEXTO2 = '#5b6472';

function teto(v: number): number {
  if (v <= 0) return 1;
  const p = 10 ** Math.floor(Math.log10(v)); const n = v / p;
  return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10) * p;
}

function TabelaDados({ cab, linhas }: { cab: string[]; linhas: (string | number)[][] }) {
  return (
    <details className="mt-1 text-xs"><summary className="cursor-pointer text-suave">Ver dados em tabela</summary>
      <div className="tabela mt-1" tabIndex={0} role="region" aria-label="Dados do gráfico"><table><thead><tr>{cab.map((c) => <th key={c}>{c}</th>)}</tr></thead>
        <tbody>{linhas.map((l, i) => <tr key={i}>{l.map((v, j) => <td key={j} className="tabular-nums">{v}</td>)}</tr>)}</tbody></table></div>
    </details>
  );
}

function Legenda({ itens }: { itens: { nome: string; cor: string; tipo?: 'linha' | 'bloco' | 'marca' }[] }) {
  return (
    <ul className="mb-1 flex flex-wrap gap-x-4 gap-y-1 text-xs" aria-hidden>{itens.map((i) => (
      <li key={i.nome} className="flex items-center gap-1.5">
        {i.tipo === 'marca' ? <span className="inline-block h-0.5 w-4" style={{ background: i.cor }} /> : i.tipo === 'linha'
          ? <span className="inline-block h-0.5 w-4 rounded" style={{ background: i.cor }} /> : <span className="inline-block h-2.5 w-2.5 rounded-sm" style={{ background: i.cor }} />}
        <span className="text-texto">{i.nome}</span></li>))}</ul>
  );
}

function Dica({ x, y, children }: { x: number; y: number; children: ReactNode }) {
  return <div className="pointer-events-none absolute z-10 -translate-x-1/2 -translate-y-full rounded-md border border-linha bg-white px-2 py-1 text-xs shadow" style={{ left: `${x}%`, top: y }}>{children}</div>;
}

// Linhas ao longo do tempo: até 2 séries, uma escala só, cruz de leitura e dica ao passar o mouse.
export function GraficoLinhas({ titulo, x, series, formatar = (v) => v.toLocaleString('pt-BR') }:
  { titulo: string; x: string[]; series: { nome: string; valores: number[] }[]; formatar?: (v: number) => string }) {
  const [foco, setFoco] = useState<number | null>(null);
  const [ref, W] = useLargura();
  const H = 220, E = 40, D = W < 420 ? 64 : 104, T = 10, B = 24;
  const max = teto(Math.max(0, ...series.flatMap((s) => s.valores)));
  const px = (i: number) => E + (x.length <= 1 ? 0 : (i * (W - E - D)) / (x.length - 1));
  const py = (v: number) => T + (H - T - B) * (1 - v / max);
  if (!x.length) return <p className="nota">Sem dados no período.</p>;
  return (
    <figure ref={ref as React.RefObject<HTMLElement>} className="relative" aria-label={titulo}>
      <Legenda itens={series.map((s, i) => ({ nome: s.nome, cor: COR_SERIE[i]!, tipo: 'linha' }))} />
      <svg viewBox={`0 0 ${W} ${H}`} className="h-auto w-full" role="img" aria-label={`${titulo}. Detalhes na tabela abaixo.`} onMouseLeave={() => setFoco(null)}>
        {[0, 0.5, 1].map((f) => (<g key={f}><line x1={E} x2={W - D} y1={py(max * f)} y2={py(max * f)} stroke={GRADE} strokeWidth={1} />
          <text x={E - 6} y={py(max * f) + 4} textAnchor="end" fontSize={11} fill={TEXTO2}>{formatar(max * f)}</text></g>))}
        {x.map((r, i) => (i === 0 || i === x.length - 1 || x.length <= Math.floor(W / 70) || i % Math.ceil(x.length / Math.max(2, Math.floor(W / 90))) === 0) &&
          <text key={r} x={px(i)} y={H - 6} textAnchor="middle" fontSize={11} fill={TEXTO2}>{r}</text>)}
        {foco != null && <line x1={px(foco)} x2={px(foco)} y1={T} y2={H - B} stroke={TEXTO2} strokeWidth={1} strokeDasharray="3 3" />}
        {series.map((s, k) => (<g key={s.nome}>
          <polyline fill="none" stroke={COR_SERIE[k]} strokeWidth={2} strokeLinejoin="round" strokeLinecap="round" points={s.valores.map((v, i) => `${px(i)},${py(v)}`).join(' ')} />
          {foco != null && <circle cx={px(foco)} cy={py(s.valores[foco] ?? 0)} r={4} fill={COR_SERIE[k]} stroke="#fff" strokeWidth={2} />}
          <text x={px(s.valores.length - 1) + 6} y={py(s.valores[s.valores.length - 1] ?? 0) + 4} fontSize={11} fill="#1f2937">{W < 420 ? '' : `${s.nome} `}{formatar(s.valores[s.valores.length - 1] ?? 0)}</text>
        </g>))}
        {x.map((r, i) => <rect key={r} x={px(i) - (W - E - D) / Math.max(1, x.length - 1) / 2} y={T} width={(W - E - D) / Math.max(1, x.length - 1)} height={H - T - B} fill="transparent" onMouseEnter={() => setFoco(i)} />)}
      </svg>
      {foco != null && <Dica x={(px(foco) / W) * 100} y={20}><strong>{x[foco]}</strong>{series.map((s) => <div key={s.nome}>{s.nome}: {formatar(s.valores[foco] ?? 0)}</div>)}</Dica>}
      <TabelaDados cab={['Período', ...series.map((s) => s.nome)]} linhas={x.map((r, i) => [r, ...series.map((s) => formatar(s.valores[i] ?? 0))])} />
    </figure>
  );
}

// Colunas de uma série (magnitude, uma cor), com marca de referência opcional (ex.: meta) e valor escrito.
export function GraficoColunas({ titulo, itens, nomeValor, nomeReferencia, formatar = (v) => v.toLocaleString('pt-BR') }:
  { titulo: string; itens: { rotulo: string; valor: number; referencia?: number | null }[]; nomeValor: string; nomeReferencia?: string; formatar?: (v: number) => string }) {
  const [foco, setFoco] = useState<number | null>(null);
  const [ref, W] = useLargura();
  const H = 220, E = 40, T = 18, B = 24;
  const max = teto(Math.max(0, ...itens.map((i) => Math.max(i.valor, i.referencia ?? 0))));
  const larg = (W - E) / Math.max(1, itens.length); const barra = Math.min(56, larg * 0.6);
  const py = (v: number) => T + (H - T - B) * (1 - v / max);
  const temRef = itens.some((i) => i.referencia != null);
  return (
    <figure ref={ref as React.RefObject<HTMLElement>} className="relative" aria-label={titulo}>
      <Legenda itens={[{ nome: nomeValor, cor: COR_SERIE[0]! }, ...(temRef && nomeReferencia ? [{ nome: nomeReferencia, cor: '#111827', tipo: 'marca' as const }] : [])]} />
      <svg viewBox={`0 0 ${W} ${H}`} className="h-auto w-full" role="img" aria-label={`${titulo}. Detalhes na tabela abaixo.`} onMouseLeave={() => setFoco(null)}>
        {[0, 0.5, 1].map((f) => (<g key={f}><line x1={E} x2={W} y1={py(max * f)} y2={py(max * f)} stroke={GRADE} strokeWidth={1} />
          <text x={E - 6} y={py(max * f) + 4} textAnchor="end" fontSize={11} fill={TEXTO2}>{formatar(max * f)}</text></g>))}
        {itens.map((it, i) => {
          const cx = E + larg * i + larg / 2; const y = py(it.valor); const h = H - B - y;
          return (<g key={it.rotulo} onMouseEnter={() => setFoco(i)}>
            <rect x={E + larg * i} y={T} width={larg} height={H - T - B} fill="transparent" />
            {h > 0 && <path d={`M${cx - barra / 2},${H - B} V${y + Math.min(4, h)} Q${cx - barra / 2},${y} ${cx - barra / 2 + Math.min(4, h)},${y} H${cx + barra / 2 - Math.min(4, h)} Q${cx + barra / 2},${y} ${cx + barra / 2},${y + Math.min(4, h)} V${H - B} Z`}
              fill={COR_SERIE[0]} opacity={foco == null || foco === i ? 1 : 0.55} />}
            {it.referencia != null && <line x1={cx - barra / 2 - 6} x2={cx + barra / 2 + 6} y1={py(it.referencia)} y2={py(it.referencia)} stroke="#111827" strokeWidth={2} />}
            <text x={cx} y={(it.referencia != null && Math.abs(py(it.referencia) - y) < 14 ? Math.min(y, py(it.referencia)) : y) - 5} textAnchor="middle" fontSize={11} fill="#1f2937">{formatar(it.valor)}</text>
            <text x={cx} y={H - 6} textAnchor="middle" fontSize={11} fill={TEXTO2}>{it.rotulo}</text>
          </g>);
        })}
      </svg>
      {foco != null && itens[foco] && <Dica x={((E + larg * foco + larg / 2) / W) * 100} y={14}><strong>{itens[foco]!.rotulo}</strong><div>{nomeValor}: {formatar(itens[foco]!.valor)}</div>
        {itens[foco]!.referencia != null && <div>{nomeReferencia}: {formatar(itens[foco]!.referencia!)}</div>}</Dica>}
      <TabelaDados cab={['Período', nomeValor, ...(temRef && nomeReferencia ? [nomeReferencia] : [])]}
        linhas={itens.map((i) => [i.rotulo, formatar(i.valor), ...(temRef ? [i.referencia == null ? 'N/D' : formatar(i.referencia)] : [])])} />
    </figure>
  );
}

// Barra segmentada para partes ordenadas (faixas): rampa de um só azul, legenda com nome e valor de cada parte.
export function BarraSegmentada({ titulo, partes, formatar = (v) => v.toLocaleString('pt-BR') }:
  { titulo: string; partes: { rotulo: string; valor: number; detalhe?: string }[]; formatar?: (v: number) => string }) {
  const total = partes.reduce((a, p) => a + p.valor, 0);
  if (!total) return <p className="nota">Nada em aberto.</p>;
  return (
    <figure aria-label={titulo}>
      <div className="flex h-4 w-full gap-[2px] overflow-hidden rounded" role="img" aria-label={`${titulo}: ${partes.map((p) => `${p.rotulo} ${formatar(p.valor)}`).join(', ')}`}>
        {partes.map((p, i) => p.valor > 0 && <span key={p.rotulo} title={`${p.rotulo}: ${formatar(p.valor)}${p.detalhe ? ` · ${p.detalhe}` : ''}`}
          style={{ width: `${(100 * p.valor) / total}%`, background: RAMPA_ORDINAL[i % RAMPA_ORDINAL.length] }} />)}
      </div>
      <ul className="mt-2 grid gap-1 text-xs sm:grid-cols-2">{partes.map((p, i) => (
        <li key={p.rotulo} className="flex items-center gap-1.5"><span className="inline-block h-2.5 w-2.5 shrink-0 rounded-sm" style={{ background: RAMPA_ORDINAL[i % RAMPA_ORDINAL.length] }} />
          <span>{p.rotulo}: <strong className="tabular-nums">{formatar(p.valor)}</strong>{p.detalhe ? ` · ${p.detalhe}` : ''}</span></li>))}</ul>
    </figure>
  );
}
