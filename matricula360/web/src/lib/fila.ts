// Fila local do modo feira: cadastros guardados no aparelho até a sincronização (LGPD: apagados assim que o banco confirma).
import type { LeadCampo } from './tipos';

const chave = (visita: number) => `m360_fila_campo_${visita}`;
export function lerFila(visita: number): LeadCampo[] {
  try { return JSON.parse(localStorage.getItem(chave(visita)) || '[]') as LeadCampo[]; } catch { return []; }
}
export function gravarFila(visita: number, fila: LeadCampo[]): void {
  try { if (fila.length) localStorage.setItem(chave(visita), JSON.stringify(fila)); else localStorage.removeItem(chave(visita)); } catch { /* sem storage */ }
}
export async function sha256(texto: string): Promise<string> {
  const h = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(texto));
  return Array.from(new Uint8Array(h)).map((b) => b.toString(16).padStart(2, '0')).join('');
}
export function novoId(): string {
  if (crypto.randomUUID) return crypto.randomUUID();
  const b = crypto.getRandomValues(new Uint8Array(16)); b[6] = (b[6]! & 0x0f) | 0x40; b[8] = (b[8]! & 0x3f) | 0x80;
  const h = Array.from(b).map((x) => x.toString(16).padStart(2, '0')).join('');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}
// Remove da fila o que o banco recebeu ou já tinha; mantém rejeitados com o motivo para correção.
export function aplicarResultado(fila: LeadCampo[], rejeitados: { id_local: string; motivo: string }[]): LeadCampo[] {
  const rej = new Map(rejeitados.map((r) => [r.id_local, r.motivo]));
  return fila.filter((l) => rej.has(l.id_local)).map((l) => ({ ...l, motivo: rej.get(l.id_local) }));
}
