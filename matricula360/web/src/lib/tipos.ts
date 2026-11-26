// Formatos devolvidos pelas RPCs do Supabase (migrações 2, 3, 5 e 6).
export type Papel = 'gestor' | 'reitoria' | 'coordenador' | 'comercial' | 'secretaria' | 'financeiro';
export type Etapa = 'novo' | 'contato' | 'inscrito' | 'pre_matricula' | 'matricula_comercial' | 'confirmado' | 'perdido' | 'cancelado';
export type Dimensao = 'documental' | 'financeira' | 'academica';
export type Canal = 'email' | 'whatsapp' | 'telefone';
export type StatusProposta = 'pendente_aprovacao' | 'aprovada' | 'rejeitada' | 'aceita' | 'expirada' | 'substituida';

export type Abrangencia = 'ies' | 'campus' | 'curso';
export interface Escopo { id: number; ies_id: number; ies_nome: string; curso_id: number | null; curso_nome: string | null; papel: Papel;
  abrangencia?: Abrangencia; campus_id?: number | null; campus_nome?: string | null }
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
  origem?: string; ultima_interacao_em?: string | null; proxima_tarefa_em?: string | null; sla_atrasado?: boolean; score?: number | null;
}
export interface ItemAgenda { id: number; tipo: string; quando: string; descricao: string | null; canal: Canal | null; oportunidade_id: number;
  nome: string; curso: string; etapa: Etapa; responsavel: string | null; atrasada: boolean }
export interface Score { score: number | null; versao: string; razoes: string[]; aviso: string }
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
  propostas: { id: number; desconto_pct: number; mensalidade_centavos: number; valor_final_centavos: number; validade: string; status: StatusProposta; criado_em?: string; criado_por?: string | null }[];
  tarefas: { id: number; tipo: string; canal: Canal | null; status: string; vence_em: string; resultado: string | null; descricao?: string | null; atrasada?: boolean }[];
  historico: { id: number; acao: string; dados: Record<string, unknown>; em: string; por: string | null }[];
  score?: Score | null;
  interacoes?: { id: number; tipo: string; resumo: string; em: string; por: string | null }[];
  objecoes?: { id: number; categoria: string; descricao: string; tratamento: string | null; status: 'aberta' | 'superada' | 'nao_superada'; em: string; por: string | null }[];
  possiveis_duplicidades?: { pessoa_id: number; email: string | null; telefone: string | null; oportunidades: number }[];
}

export interface Pendencia { id: number; versao: number; etapa: Etapa; coorte: string; curso: string; nome: string;
  val_documental: boolean; val_financeira: boolean; val_academica: boolean; confirmada_em: string | null; cancelada_em: string | null }

export interface PropostaLista { id: number; oportunidade_id: number; desconto_pct: number; valor_final_centavos: number; mensalidade_centavos: number;
  validade: string; status: StatusProposta; criado_por: string; criado_por_nome: string | null; curso: string; desconto_max_pct: number; nome: string }

export interface EventoAuditoria { id: number; acao: string; entidade: string; entidade_id: string | null; dados: Record<string, unknown>; em: string; por: string | null }

export interface IesMaster { id: number; nome: string; plano: string; status: 'ativa' | 'suspensa'; criado_em: string; cursos: number; usuarios: number }
export interface AcessosIes {
  campi?: { id: number; nome: string }[];
  cursos: { id: number; nome: string; turno: string; modalidade: string; campus: string }[];
  escopos: { id: number; papel: Papel; curso_id: number | null; curso_nome: string | null; abrangencia?: Abrangencia; campus_nome?: string | null; concedido_em: string; revogado_em: string | null;
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
  custo_por_lead_centavos: number | null; custo_por_matricula_centavos: number | null; custo_motivo: string | null;
  custo_atribuido_centavos?: number | null; leads_atribuidos?: number; leads_atribuicao_desconhecida?: number;
  metodos: Record<'conversao' | 'projecao' | 'cenario' | 'receita' | 'funil', string> & { custo?: string };
}
export interface Grupo { chave: string; oportunidades: number; ingressantes: number; matriculas_comerciais?: number; conversao?: number | null; meta?: number | null; atingimento?: number | null; curso_id?: number }
export interface Alerta { tipo: string; prioridade: number; titulo: string; quantidade: number; acao: string }
export interface Central {
  coorte: string; cobertura: 'ies' | 'recorte'; totais: CentralTotais;
  funil: { etapa: string; quantidade: number; conversao_da_anterior: number | null }[];
  evolucao: { semana: string; oportunidades: number; matriculas_comerciais: number; ingressantes: number }[];
  por_origem: Grupo[]; por_campanha?: Grupo[]; por_curso: Grupo[]; por_turno: Grupo[]; por_modalidade: Grupo[]; por_atendente: Grupo[];
  alertas: Alerta[] | null;
  filtros_disponiveis: { campi: { id: number; nome: string }[]; turnos: string[]; modalidades: string[]; campanhas?: { id: number; nome: string }[] };
}

export interface OperacaoMatriz { operacao: string; modulo: string; descricao: string; papeis: Papel[]; abrangencia_minima: 'curso' | 'ies'; permitida: boolean }
export interface Permissoes { escopos: { papel: Papel; abrangencia: Abrangencia; alvo: string }[]; matriz: OperacaoMatriz[] }
export interface LinhaExportacao { id: number; nome: string; email: string | null; telefone: string | null; campus: string; curso: string; turno: string;
  modalidade: string; coorte: string; etapa: Etapa; forma_ingresso: string; origem: string; base_legal: string; responsavel: string | null; criado_em: string }
export interface Exportacao { linhas: LinhaExportacao[]; total: number; contato_completo: boolean; gerado_em: string }

// Planejamento Estratégico e Marketing e Captação (migração 12)
export type Indicador = 'ingressantes' | 'oportunidades' | 'matriculas_comerciais' | 'conversao' | 'cpl_centavos' | 'custo_ingressante_centavos';
export interface Objetivo { id: number; descricao: string; indicador: Indicador; curso_id: number | null; curso: string | null; meta: number; prazo: string | null; realizado: number | null }
export interface Acao { id: number; objetivo_id: number | null; o_que: string; por_que: string; onde: string | null; quando: string; quem: string; como: string | null;
  quanto_centavos: number | null; status: 'pendente' | 'em_andamento' | 'concluida' | 'cancelada'; atrasada: boolean }
export interface Plano { id: number; titulo: string; diagnostico: string | null; status: 'rascunho' | 'em_aprovacao' | 'aprovado' | 'em_revisao' | 'encerrado'; versao: number;
  orcamento_centavos: number | null; orcamento_alocado_centavos: number | null; gasto_centavos: number | null; revisar_em: string | null; revisao_vencida: boolean;
  criado_por: string | null; criado_por_mim: boolean; aprovado_por: string | null; aprovado_em: string | null; objetivos: Objetivo[]; acoes: Acao[] }
export interface Planejamento { coorte: string; pode_editar: boolean; pode_aprovar: boolean; planos: Plano[]; metodos: { realizado: string } }
export interface RegistroConcorrencia { id: number; instituicao: string; curso: string; modalidade: string | null; mensalidade_centavos: number | null; fonte_url: string;
  coletado_em: string; observacao: string | null; registrado_por: string | null; registrado_por_mim: boolean; revisado_por: string | null; revisado_em: string | null; desatualizado: boolean }
export interface CustoCampanha { id: number; data: string; valor_centavos: number; descricao: string; lancado_por: string | null; estornado_em: string | null; motivo_estorno: string | null }
export interface Campanha { id: number; nome: string; codigo: string; canal: string; inicio: string; fim: string; status: 'planejada' | 'ativa' | 'encerrada' | 'cancelada';
  objetivo: string | null; versao: number; plano_id: number | null; vigente: boolean; leads: number; matriculas_comerciais: number; ingressantes: number; conversao: number | null;
  orcamento_centavos: number | null; custo_centavos: number | null; cpl_centavos: number | null; custo_ingressante_centavos: number | null; custos: CustoCampanha[] | null }
export interface Campanhas { coorte: string; ve_custos: boolean; pode_editar: boolean; pode_lancar_custo: boolean; integracoes: Record<string, string>;
  campanhas: Campanha[]; atribuicao_desconhecida: { leads: number; ingressantes: number }; metodos: Record<'atribuicao' | 'cpl' | 'custo_ingressante', string> }

// Funis Comerciais (migração 13)
export type EtapaBase = 'novo' | 'contato' | 'inscrito' | 'pre_matricula' | 'matricula_comercial';
export interface EtapaFunil { ordem: number; nome: string; etapa_base: EtapaBase; sla_horas: number | null; roteiro: string | null }
export interface CadenciaFunil { etapa_ordem: number; passo: number; dia: number; canal: 'telefone' | 'whatsapp' | 'email' | 'presencial'; descricao: string }
export interface MetaFunil { forma_ingresso: string; conversao_meta: number }
export interface VersaoFunil { id: number; versao: number; status: 'rascunho' | 'publicada' | 'arquivada'; notas: string | null; criado_por: string | null; criado_em: string;
  publicada_por: string | null; publicada_em: string | null; oportunidades: number; etapas: EtapaFunil[]; cadencias: CadenciaFunil[]; metas: MetaFunil[] }
export interface Funil { id: number; nome: string; modalidade: string | null; formas: string[] | null; padrao: boolean; ativo: boolean; versoes: VersaoFunil[];
  desempenho: { forma_ingresso: string; oportunidades: number; ingressantes: number; conversao: number | null; meta: number | null }[] }
export interface Funis { pode_editar: boolean; pode_publicar: boolean; regra_selecao: string; funis: Funil[] }
export interface FunilOportunidade { funil: string | null; versao?: number; versao_status?: string; etapa_ordem?: number | null; versao_op?: number;
  atual?: { ordem: number; nome: string; sla_horas: number | null; roteiro: string | null } | null; subetapas?: { ordem: number; nome: string }[];
  cadencia?: { passo: number; dia: number; canal: string; descricao: string }[]; meta_conversao_forma?: number | null }
