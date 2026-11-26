// Gráficos em SVG próprio: leves, acessíveis (tabela/rotulagem textual) e compatíveis com a CSP estrita.
import { useState } from 'react';
import { pct, rotulo } from '../lib/formato';

// Funil com largura proporcional aos valores reais e conversão entre etapas.
export function Funil({ etapas }: { etapas: { etapa: string; quantidade: number; conversao_da_anterior: number | null }[] }) {
  const max = Math.max(1, ...etapas.map((e) => e.quantidade));
  return (
    <ol className="space-y-1.5" aria-label="Funil comercial">
      {etapas.map((e, i) => (
        <li key={e.etapa} className="grid grid-cols-[minmax(110px,150px)_1fr] items-center gap-3 text-sm">
          <span className="truncate text-suave">{rotulo(e.etapa)}</span>
          <div className="flex items-center gap-2">
            <div className="h-7 rounded-md bg-gradient-to-r from-marinho-600 to-tec transition-all"
              style={{ width: `${Math.max(2, (e.quantidade / max) * 100)}%`, opacity: 1 - i * 0.08 }} aria-hidden />
            <span className="whitespace-nowrap font-semibold text-marinho">{e.quantidade}</span>
            {i > 0 && <span className="whitespace-nowrap text-xs text-suave" title="Conversão a partir da etapa anterior">{pct(e.conversao_da_anterior)}</span>}
          </div>
        </li>
      ))}
    </ol>
  );
}

// Barras horizontais comparativas (ex.: origem, atendente).
export function Barras<T extends { chave: string }>({ dados: origem, valor, sufixo }: { dados: T[]; valor: keyof T & string; sufixo?: (d: Record<string, unknown>) => string }) {
  const dados = origem as unknown as Record<string, unknown>[] & { chave: string }[];
  const max = Math.max(1, ...dados.map((d) => Number(d[valor]) || 0));
  if (!dados.length) return <p className="nd text-sm">Sem dados no recorte.</p>;
  return (
    <ul className="space-y-2">
      {dados.map((d) => (
        <li key={String(d.chave)} className="text-sm">
          <div className="mb-0.5 flex justify-between gap-2"><span className="truncate">{rotulo(String(d.chave))}</span>
            <span className="whitespace-nowrap font-semibold text-marinho">{String(d[valor])}{sufixo ? <span className="ml-1 text-xs font-normal text-suave">{sufixo(d)}</span> : null}</span></div>
          <div className="h-2 rounded-full bg-fundo"><div className="h-2 rounded-full bg-tec" style={{ width: `${((Number(d[valor]) || 0) / max) * 100}%` }} /></div>
        </li>
      ))}
    </ul>
  );
}

// Meta x resultado por item.
export function Progresso({ rotulo: r, atual, meta }: { rotulo: string; atual: number; meta: number | null }) {
  const p = meta && meta > 0 ? Math.min(1, atual / meta) : null;
  return (
    <div className="text-sm">
      <div className="mb-0.5 flex justify-between gap-2"><span className="truncate">{r}</span>
        <span className="whitespace-nowrap text-marinho"><strong>{atual}</strong> / {meta == null ? <span className="nd">N/D</span> : meta}{p != null && <span className="ml-1 text-xs text-suave">{pct(atual / meta!)}</span>}</span></div>
      <div className="h-2 rounded-full bg-fundo">{p != null && <div className={`h-2 rounded-full ${p >= 1 ? 'bg-ok' : p >= 0.5 ? 'bg-tec' : 'bg-alerta'}`} style={{ width: `${p * 100}%` }} />}</div>
    </div>
  );
}

// Linhas semanais com dica ao passar o mouse/toque.
export function Linhas({ pontos, series }: { pontos: Record<string, number | string>[]; series: { chave: string; rotulo: string; cor: string }[] }) {
  const [foco, setFoco] = useState<number | null>(null);
  const L = 600, A = 180, m = { e: 28, d: 8, t: 10, b: 24 };
  const max = Math.max(1, ...pontos.flatMap((p) => series.map((s) => Number(p[s.chave]) || 0)));
  const x = (i: number) => m.e + (i * (L - m.e - m.d)) / Math.max(1, pontos.length - 1);
  const y = (v: number) => A - m.b - (v / max) * (A - m.t - m.b);
  const p = foco != null ? pontos[foco] : null;
  return (
    <div className="relative">
      <svg viewBox={`0 0 ${L} ${A}`} className="h-48 w-full" role="img" aria-label={`Evolução semanal: ${series.map((s) => s.rotulo).join(', ')}`}
        onMouseLeave={() => setFoco(null)}>
        {[0, 0.5, 1].map((t) => <line key={t} x1={m.e} x2={L - m.d} y1={y(max * t)} y2={y(max * t)} stroke="#e3e9f1" />)}
        <text x={2} y={y(max) + 4} fontSize="10" fill="#5b6b80">{max}</text>
        <text x={2} y={y(0) + 4} fontSize="10" fill="#5b6b80">0</text>
        {series.map((s) => (
          <polyline key={s.chave} fill="none" stroke={s.cor} strokeWidth="2.5" strokeLinejoin="round"
            points={pontos.map((pt, i) => `${x(i)},${y(Number(pt[s.chave]) || 0)}`).join(' ')} />
        ))}
        {pontos.map((pt, i) => (
          <g key={i}>
            <rect x={x(i) - 18} y={0} width={36} height={A} fill="transparent" onMouseEnter={() => setFoco(i)} onTouchStart={() => setFoco(i)} />
            {i % 2 === 0 && <text x={x(i)} y={A - 6} fontSize="9" textAnchor="middle" fill="#5b6b80">{String(pt.semana).slice(5)}</text>}
            {foco === i && <line x1={x(i)} x2={x(i)} y1={m.t} y2={A - m.b} stroke="#1d6fe0" strokeDasharray="3 3" />}
          </g>
        ))}
      </svg>
      <div className="mt-1 flex flex-wrap gap-3 text-xs">{series.map((s) => <span key={s.chave} className="flex items-center gap-1"><span className="inline-block h-2 w-3 rounded" style={{ background: s.cor }} />{s.rotulo}</span>)}</div>
      {p && (
        <div className="pointer-events-none absolute right-2 top-0 rounded-lg border border-linha bg-white px-2.5 py-1.5 text-xs shadow-cartao" role="status">
          <strong>Semana de {String(p.semana)}</strong>{series.map((s) => <div key={s.chave}>{s.rotulo}: {String(p[s.chave])}</div>)}
        </div>
      )}
    </div>
  );
}
