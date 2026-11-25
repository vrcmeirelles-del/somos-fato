import { AlertTriangle, CheckCircle2, Inbox, Info, Loader2, type LucideIcon } from 'lucide-react';
import type { ReactNode } from 'react';
import { ND } from '../lib/formato';

export function Mensagem({ m }: { m: { tipo: 'ok' | 'erro'; texto: string } | null }) {
  if (!m) return null;
  return m.tipo === 'erro'
    ? <p role="alert" className="my-2 flex items-start gap-2 rounded-lg bg-red-50 px-3 py-2 text-sm text-erro"><AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />{m.texto}</p>
    : <p role="status" className="my-2 flex items-start gap-2 rounded-lg bg-green-50 px-3 py-2 text-sm text-ok"><CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />{m.texto}</p>;
}

// "N/D" (indisponível) é visualmente distinto de zero.
export function Valor({ v, titulo }: { v: string; titulo?: string }) {
  return v === ND ? <span className="nd" title={titulo ?? 'Indisponível: sem base de cálculo ou sem cadastro'}>{ND}</span> : <>{v}</>;
}

export function Kpi({ rotulo, valor, icone: Icone, detalhe, destaque }: { rotulo: string; valor: string; icone?: LucideIcon; detalhe?: ReactNode; destaque?: boolean }) {
  return (
    <div className={`kpi cartao-base flex flex-col gap-1 ${destaque ? 'border-tec-400 bg-tec-50' : ''}`}>
      <span className="flex items-center gap-1.5 text-xs font-medium text-suave">{Icone && <Icone className="h-3.5 w-3.5" aria-hidden />}{rotulo}</span>
      <strong className="text-2xl font-semibold tracking-tight text-marinho"><Valor v={valor} /></strong>
      {detalhe && <span className="nota">{detalhe}</span>}
    </div>
  );
}

export function Cartao({ titulo, icone: Icone, children, acao, className = '' }: { titulo?: string; icone?: LucideIcon; children: ReactNode; acao?: ReactNode; className?: string }) {
  return (
    <section className={`cartao-base ${className}`}>
      {(titulo || acao) && (
        <header className="mb-3 flex flex-wrap items-center justify-between gap-2">
          {titulo && <h2 className="flex items-center gap-2 text-sm font-semibold text-marinho">{Icone && <Icone className="h-4 w-4 text-tec" aria-hidden />}{titulo}</h2>}
          {acao}
        </header>
      )}
      {children}
    </section>
  );
}

export function Campo({ rotulo, children, className = '' }: { rotulo: string; children: ReactNode; className?: string }) {
  return <label className={`flex flex-col gap-1 text-xs font-medium text-suave ${className}`}>{rotulo}{children}</label>;
}

export function Chip({ tipo, children }: { tipo?: 'ok' | 'pend' | 'erro' | 'tec'; children: ReactNode }) {
  return <span className={`chip ${tipo ? `chip-${tipo}` : ''}`}>{children}</span>;
}

export function Carregando({ texto = 'Carregando…' }: { texto?: string }) {
  return <p className="flex items-center gap-2 py-6 text-sm text-suave" aria-live="polite"><Loader2 className="h-4 w-4 animate-spin" aria-hidden />{texto}</p>;
}
export function Vazio({ texto, detalhe }: { texto: string; detalhe?: string }) {
  return (
    <div className="flex flex-col items-center gap-1 rounded-xl border border-dashed border-linha bg-white px-4 py-8 text-center">
      <Inbox className="h-6 w-6 text-suave" aria-hidden />
      <p className="text-sm font-medium text-texto">{texto}</p>
      {detalhe && <p className="nota max-w-md">{detalhe}</p>}
    </div>
  );
}
export function Estado({ carregando, erro }: { carregando: boolean; erro: Error | null }) {
  if (erro) return <Mensagem m={{ tipo: 'erro', texto: erro.message }} />;
  if (carregando) return <Carregando />;
  return null;
}
export function Aviso({ children }: { children: ReactNode }) {
  return <p className="flex items-start gap-2 rounded-lg bg-tec-50 px-3 py-2 text-xs text-marinho"><Info className="mt-0.5 h-3.5 w-3.5 shrink-0 text-tec" aria-hidden />{children}</p>;
}

export function Secao({ titulo, children, acao }: { titulo: string; children: ReactNode; acao?: ReactNode }) {
  return (
    <section className="mt-6">
      <div className="mb-2 flex flex-wrap items-center justify-between gap-2"><h2 className="text-base font-semibold text-marinho">{titulo}</h2>{acao}</div>
      {children}
    </section>
  );
}

export function Detalhes({ titulo, children }: { titulo: string; children: ReactNode }) {
  return (
    <details className="mb-3 rounded-xl border border-linha bg-white px-4 py-2.5 shadow-cartao">
      <summary className="cursor-pointer text-sm font-semibold text-marinho">{titulo}</summary>
      <div className="mt-3">{children}</div>
    </details>
  );
}

export function Titulo({ titulo, subtitulo, acao }: { titulo: string; subtitulo?: string; acao?: ReactNode }) {
  return (
    <div className="mb-4 flex flex-wrap items-end justify-between gap-3">
      <div><h1 className="text-2xl font-semibold tracking-tight text-marinho">{titulo}</h1>{subtitulo && <p className="mt-0.5 text-sm text-suave">{subtitulo}</p>}</div>
      {acao}
    </div>
  );
}
