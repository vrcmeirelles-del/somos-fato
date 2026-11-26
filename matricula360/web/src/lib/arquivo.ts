// Arquivos no navegador: leitura para base64 (envio) e download a partir de base64 (sem guardar em disco do servidor).
export const LIMITE_ARQUIVO = 3 * 1024 * 1024;

export function lerBase64(arquivo: File): Promise<string> {
  if (arquivo.size > LIMITE_ARQUIVO) return Promise.reject(new Error('Arquivo acima de 3 MB'));
  return new Promise((ok, falha) => {
    const r = new FileReader();
    r.onload = () => ok(String(r.result).split(',')[1] ?? '');
    r.onerror = () => falha(new Error('Não foi possível ler o arquivo'));
    r.readAsDataURL(arquivo);
  });
}

export function baixarBase64(nome: string, mime: string, base64: string): void {
  const bin = atob(base64); const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  const url = URL.createObjectURL(new Blob([bytes], { type: mime }));
  const a = document.createElement('a'); a.href = url; a.download = nome; a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

// Linhas CSV com ";" (planilhas pt-BR) -> objetos pelo cabeçalho. Aspas simples tratadas.
export function lerCsv(texto: string): Record<string, string>[] {
  const linhas = texto.replace(/^﻿/, '').split(/\r?\n/).filter((l) => l.trim());
  const [cab, ...resto] = linhas;
  if (!cab) return [];
  const sep = cab.includes(';') ? ';' : ',';
  const campos = cab.split(sep).map((c) => c.trim().toLowerCase());
  return resto.map((l) => Object.fromEntries(l.split(sep).map((v, i) => [campos[i] ?? `c${i}`, v.trim().replace(/^"|"$/g, '')])));
}
