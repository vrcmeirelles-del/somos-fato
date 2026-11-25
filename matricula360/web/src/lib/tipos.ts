// Formatos devolvidos pelas RPCs do Supabase (migrações 2, 3, 5 e 6).
export type Papel = 'gestor' | 'reitoria' | 'coordenador' | 'comercial' | 'secretaria' | 'financeiro';
export type Etapa = 'novo' | 'contato' | 'inscrito' | 'pre_matricula' | 'matricula_comercial' | 'confirmado' | 'perdido' | 'cancelado';
export type Dimensao = 'documental' | 'financeira' | 'academica';
export type Canal = 'email' | 'whatsapp' | 'telefone';
export type StatusProposta = 'pendente_aprovacao' | 'aprovada' | 'rejeitada' | 'aceita' | 'expirada' | 'substituida';

export interface Escopo { id: number; ies_id: number; ies_nome: string; curso_id: number | null; curso_nome: string | null; papel: Papel }
export interface Eu { usuario: { id: string; nome: string; master: boolean; email?: string }; escopos: Escopo[] }

export interface Curso { id: number; nome: string; turno: string; modalidade: string; mensalidade_centavos: number; desconto_max_pct: number; campus?: string }
export interface Estrutura {
  ies: { id: number; nome: string; plano: string; sla_horas: number; max_followups: number; dias_sem_contato: number; capacidade_atendente: number; amostra_minima_forecast: number };
  papeis: Papel[]; acesso_total: boolean; cursos: Curso[]; coortes: string[];
  etapas: Etapa[]; formas_ingresso: string[]; bases_legais: string[]; canais: Canal[];
}

export interface Totais {
  oportunidades: number; matriculas_comerciais: number; ingressantes: number; cancelamentos: number; perdidos: number;
  conversao: number | null; meta: number | null; atingimento: number | null; projecao_oportunidades_necessarias: number | null;
}
export interface LinhaBi { chave: string; curso_id: number | null; oportunidades: number; matriculas_comerciais: number; ingressantes: number;
  cancelamentos: number; perdidos: number; conversao: number | null; meta: number | null; atingimento: number | null }
export interface Bi { coorte: string; agrupar: string; cobertura: 'ies' | 'cursos_autorizados'; totais: Totais; linhas: LinhaBi[] }

export interface ItemOportunidade {
  id: number; etapa: Etapa; versao: number; coorte: string; curso_id: number; curso: string; turno: string; forma_ingresso: string;
  responsavel: string | null; nome: string; email: string | null; telefone: string | null; dados_mascarados: boolean;
}
export interface Pagina<T> { itens: T[]; total: number; pagina: number; por_pagina: number }

export interface Tarefa { id: number; tipo: string; canal: Canal | null; vence_em: string; oportunidade_id: number; responsavel_id: string | null;
  responsavel: string | null; etapa: Etapa; curso: string; nome: string; atrasada: boolean }
export interface Fila { tarefas: Tarefa[]; envio_externo: 'desativado' }

export interface Detalhe {
  oportunidade: {
    id: number; etapa: Etapa; versao: number; coorte: string; forma_ingresso: string; responsavel: string | null; motivo_perda: string | null;
    val_documental: boolean; val_financeira: boolean; val_academica: boolean;
  };
  curso: Curso;
  pessoa: { id: number; nome: string; email: string | null; telefone: string | null; dados_mascarados: boolean; base_legal: string; origem: string;
    optout: Record<Canal, boolean>; anonimizada: boolean };
  transicoes: Etapa[];
  validacoes: { id: number; dimensao: Dimensao; resultado: string; evidencia: string; em: string; por: string | null }[];
  propostas: { id: number; desconto_pct: number; mensalidade_centavos: number; valor_final_centavos: number; validade: string; status: StatusProposta }[];
  tarefas: { id: number; tipo: string; canal: Canal | null; status: string; vence_em: string; resultado: string | null }[];
  historico: { id: number; acao: string; dados: Record<string, unknown>; em: string; por: string | null }[];
}

export interface Pendencia { id: number; versao: number; etapa: Etapa; coorte: string; curso: string; nome: string;
  val_documental: boolean; val_financeira: boolean; val_academica: boolean; confirmada_em: string | null; cancelada_em: string | null }

export interface PropostaLista { id: number; oportunidade_id: number; desconto_pct: number; valor_final_centavos: number; mensalidade_centavos: number;
  validade: string; status: StatusProposta; criado_por: string; criado_por_nome: string | null; curso: string; desconto_max_pct: number; nome: string }

export interface EventoAuditoria { id: number; acao: string; entidade: string; entidade_id: string | null; dados: Record<string, unknown>; em: string; por: string | null }

export interface IesMaster { id: number; nome: string; plano: string; status: 'ativa' | 'suspensa'; criado_em: string; cursos: number; usuarios: number }
export interface AcessosIes {
  cursos: { id: number; nome: string; turno: string; modalidade: string; campus: string }[];
  escopos: { id: number; papel: Papel; curso_id: number | null; curso_nome: string | null; concedido_em: string; revogado_em: string | null;
    usuario_id: string; nome: string; email: string | null; usuario_revogado_em: string | null }[];
}
export interface ResultadoMaim { follow_ups: number; suprimidos_optout: number; limite_atingido: number; pendencias_validacao: number;
  sem_responsavel_redistribuidas: number; atrasadas: number }

export interface CentralTotais {
  oportunidades: number; matriculas_comerciais: number; ingressantes: number; perdidos: number; cancelamentos: number; oportunidades_abertas: number;
  conversao: number | null; meta: number | null; atingimento: number | null; meta_restante: number | null;
  amostra: number; amostra_minima: number; oportunidades_adicionais_projetadas: number | null; forecast_motivo: string | null;
  cenario_pipeline: { rotulo: string; taxa_conversao_decididas: number | null; ingressos_esperados_pipeline: number | null; projecao_ingressos: number | null; novas_oportunidades_necessarias: number | null };
  receita_mensal_ingressantes_centavos: number; receita_mensal_potencial_ofertada_centavos: number; propostas_validas: number;
  custo_por_lead_centavos: number | null; custo_por_matricula_centavos: number | null; custo_motivo: string;
  metodos: Record<'conversao' | 'projecao' | 'cenario' | 'receita' | 'funil', string>;
}
export interface Grupo { chave: string; oportunidades: number; ingressantes: number; matriculas_comerciais?: number; conversao?: number | null; meta?: number | null; atingimento?: number | null; curso_id?: number }
export interface Alerta { tipo: string; prioridade: number; titulo: string; quantidade: number; acao: string }
export interface Central {
  coorte: string; cobertura: 'ies' | 'recorte'; totais: CentralTotais;
  funil: { etapa: string; quantidade: number; conversao_da_anterior: number | null }[];
  evolucao: { semana: string; oportunidades: number; matriculas_comerciais: number; ingressantes: number }[];
  por_origem: Grupo[]; por_curso: Grupo[]; por_turno: Grupo[]; por_modalidade: Grupo[]; por_atendente: Grupo[];
  alertas: Alerta[] | null;
  filtros_disponiveis: { campi: { id: number; nome: string }[]; turnos: string[]; modalidades: string[] };
}
