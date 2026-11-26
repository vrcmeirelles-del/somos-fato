// Cursos para provisionar uma instituição: leitura de planilha (CSV, texto colado do Excel ou .xlsx), normalização e validação.
export const TURNOS = ['matutino', 'vespertino', 'noturno', 'integral', 'ead'] as const;
export const MODALIDADES = ['presencial', 'ead', 'semipresencial'] as const;
export interface LinhaCurso { nome: string; turno: string; modalidade: string; mensalidade: string; desconto: string }
export const CABECALHO_MODELO = 'curso;turno;modalidade;mensalidade;desconto_maximo';

const semAcento = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();
const SINON_TURNO: Record<string, string> = { manha: 'matutino', matutino: 'matutino', tarde: 'vespertino', vespertino: 'vespertino', noite: 'noturno', noturno: 'noturno',
  integral: 'integral', ead: 'ead', 'a distancia': 'ead', distancia: 'ead', online: 'ead' };
const SINON_MODAL: Record<string, string> = { presencial: 'presencial', ead: 'ead', 'a distancia': 'ead', distancia: 'ead', online: 'ead', semipresencial: 'semipresencial',
  hibrido: 'semipresencial', 'semi-presencial': 'semipresencial' };
export const normTurno = (s: string) => SINON_TURNO[semAcento(s)] ?? semAcento(s);
export const normModalidade = (s: string) => SINON_MODAL[semAcento(s)] ?? semAcento(s);

// "1.290,00", "1290", "R$ 1.290,50", "1290.5" (Excel) -> centavos; null se inválido.
export function paraCentavos(v: string): number | null {
  let t = String(v ?? '').replace(/r\$|\s/gi, '');
  if (!t) return null;
  if (t.includes(',')) t = t.replace(/\./g, '').replace(',', '.');
  else if (/^\d{1,3}(\.\d{3})+$/.test(t)) t = t.replace(/\./g, '');
  const n = Number(t);
  return Number.isFinite(n) && n > 0 ? Math.round(n * 100) : null;
}

// Linhas de texto (CSV com ; ou , e texto colado do Excel com tabulação). Ignora cabeçalho reconhecível e linhas vazias.
export function lerLinhasTexto(texto: string): string[][] {
  const linhas = texto.replace(/^﻿/, '').split(/\r?\n/).filter((l) => l.trim());
  if (!linhas.length) return [];
  const sep = linhas[0]!.includes('\t') ? '\t' : linhas[0]!.includes(';') ? ';' : ',';
  return linhas.map((l) => l.split(sep).map((x) => x.trim().replace(/^"|"$/g, '')));
}

export function paraLinhas(celulas: (string | number | null | undefined)[][]): LinhaCurso[] {
  const txt = celulas.map((r) => r.map((c) => (c == null ? '' : String(c).trim())));
  const corpo = txt.length && /curso|nome/i.test(txt[0]![0] ?? '') && /turno/i.test(txt[0]!.join(' ')) ? txt.slice(1) : txt;
  return corpo.filter((r) => r.some(Boolean)).map(([nome = '', turno = '', modalidade = '', mensalidade = '', desconto = '']) => ({
    nome, turno: normTurno(turno), modalidade: normModalidade(modalidade), mensalidade, desconto: desconto || '30' }));
}

export function errosLinha(l: LinhaCurso, todas: LinhaCurso[], i: number): string[] {
  const e: string[] = [];
  if (l.nome.trim().length < 2) e.push('nome');
  if (!(TURNOS as readonly string[]).includes(l.turno)) e.push('turno');
  if (!(MODALIDADES as readonly string[]).includes(l.modalidade)) e.push('modalidade');
  if (paraCentavos(l.mensalidade) == null) e.push('mensalidade');
  const d = Number(String(l.desconto).replace(',', '.'));
  if (!Number.isFinite(d) || d < 0 || d > 100) e.push('desconto');
  if (todas.some((o, j) => j < i && semAcento(o.nome) === semAcento(l.nome) && o.turno === l.turno)) e.push('repetido');
  return e;
}

export const paraRpc = (l: LinhaCurso) => ({ nome: l.nome.trim(), turno: l.turno, modalidade: l.modalidade, mensalidade_centavos: paraCentavos(l.mensalidade)!,
  desconto_max_pct: Number(String(l.desconto).replace(',', '.')) });
