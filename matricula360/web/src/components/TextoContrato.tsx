import { partesContrato } from '../lib/contrato';

// Texto do contrato com as cláusulas marcadas com **…** em destaque (CDC, art. 54, §4º) e fonte de 16px.
export function TextoContrato({ texto, className = '' }: { texto: string; className?: string }) {
  return (
    <div className={`whitespace-pre-line text-base leading-relaxed ${className}`}>
      {partesContrato(texto).map((p, i) => (p.destaque
        ? <strong key={i} className="rounded bg-amber-100 px-0.5 font-bold text-marinho">{p.texto}</strong>
        : <span key={i}>{p.texto}</span>))}
    </div>
  );
}
