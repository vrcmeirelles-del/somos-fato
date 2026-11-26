// Regras de apresentação do CRM (puras, testáveis). Nenhuma decisão comercial é tomada aqui: o servidor valida tudo.
import type { Detalhe, Etapa } from './tipos';

export const TIPOS_INTERACAO = ['ligacao', 'whatsapp_manual', 'email_manual', 'visita', 'reuniao', 'anotacao'] as const;
export const CATEGORIAS_OBJECAO = ['preco', 'horario', 'distancia', 'documentacao', 'concorrencia', 'credibilidade', 'tempo', 'familia', 'outra'] as const;
// Etapas em que o arrastar faz sentido (as demais exigem validações em Matrículas).
export const ETAPAS_ARRASTAVEIS: Etapa[] = ['novo', 'contato', 'inscrito', 'pre_matricula', 'matricula_comercial', 'perdido'];

export function relativo(iso: string | null | undefined, agora = Date.now()): string {
  if (!iso) return 'nunca';
  const min = Math.round((agora - new Date(iso).getTime()) / 60000);
  const futuro = min < 0; const m = Math.abs(min);
  const t = m < 60 ? `${m} min` : m < 1440 ? `${Math.round(m / 60)} h` : `${Math.round(m / 1440)} d`;
  return futuro ? `em ${t}` : `há ${t}`;
}

export interface EventoLinha { chave: string; em: string; tipo: 'auditoria' | 'interacao' | 'objecao' | 'proposta'; titulo: string; por: string | null; codigo?: string }

// Linha do tempo única: auditoria (traduzida pelo chamador) + interações + objeções, do mais recente ao mais antigo.
export function linhaDoTempo(d: Detalhe, descrever: (acao: string, dados: Record<string, unknown>) => string): EventoLinha[] {
  const ev: EventoLinha[] = [
    ...d.historico.map((h) => ({ chave: `a${h.id}`, em: h.em, tipo: 'auditoria' as const, titulo: descrever(h.acao, h.dados), por: h.por, codigo: h.acao })),
    ...(d.interacoes ?? []).map((i) => ({ chave: `i${i.id}`, em: i.em, tipo: 'interacao' as const, titulo: i.resumo, por: i.por, codigo: i.tipo })),
    ...(d.objecoes ?? []).map((o) => ({ chave: `o${o.id}`, em: o.em, tipo: 'objecao' as const, titulo: o.descricao, por: o.por, codigo: o.categoria })),
  ];
  return ev.sort((a, b) => (a.em < b.em ? 1 : a.em > b.em ? -1 : a.chave < b.chave ? 1 : -1));
}

// Faixa visual do score (apenas priorização; nunca decide ingresso).
export const faixaScore = (s: number | null | undefined): 'ok' | 'pend' | undefined => (s == null ? undefined : s >= 60 ? 'ok' : s >= 30 ? 'pend' : undefined);
