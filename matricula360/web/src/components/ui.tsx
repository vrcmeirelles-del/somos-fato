import type { ReactNode } from 'react';
import { ND } from '../lib/formato';

export function Mensagem({ m }: { m: { tipo: 'ok' | 'erro'; texto: string } | null }) {
  if (!m) return null;
  return m.tipo === 'erro'
    ? <p role="alert" className="my-2 text-erro">{m.texto}</p>
    : <p role="status" className="my-2 text-ok">{m.texto}</p>;
}

export function Valor({ v }: { v: string }) {
  return v === ND ? <span className="nd" title="Indisponível: sem denominador ou sem meta">{ND}</span> : <>{v}</>;
}

export function Kpi({ rotulo, valor }: { rotulo: string; valor: string }) {
  return (
    <div className="kpi cartao-base p-3.5">
      <span className="block text-xs text-suave">{rotulo}</span>
      <strong className="text-xl sm:text-2xl"><Valor v={valor} /></strong>
    </div>
  );
}

export function Campo({ rotulo, children, className = '' }: { rotulo: string; children: ReactNode; className?: string }) {
  return <label className={`flex flex-col gap-1 text-sm ${className}`}>{rotulo}{children}</label>;
}

export function Chip({ tipo, children }: { tipo?: 'ok' | 'pend' | 'erro'; children: ReactNode }) {
  return <span className={`chip ${tipo === 'ok' ? 'chip-ok' : tipo === 'pend' ? 'chip-pend' : tipo === 'erro' ? 'chip-erro' : ''}`}>{children}</span>;
}

export function Estado({ carregando, erro }: { carregando: boolean; erro: Error | null }) {
  if (erro) return <p role="alert" className="text-erro">{erro.message}</p>;
  if (carregando) return <p className="nota" aria-live="polite">Carregando…</p>;
  return null;
}

export function Secao({ titulo, children, acao }: { titulo: string; children: ReactNode; acao?: ReactNode }) {
  return (
    <section className="mt-8">
      <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
        <h2 className="text-lg font-semibold">{titulo}</h2>
        {acao}
      </div>
      {children}
    </section>
  );
}

export function Detalhes({ titulo, children }: { titulo: string; children: ReactNode }) {
  return (
    <details className="mb-3 rounded-xl border border-linha bg-white px-4 py-2.5">
      <summary className="cursor-pointer font-semibold">{titulo}</summary>
      <div className="mt-3">{children}</div>
    </details>
  );
}
