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

// MAIM Performance (migração 14)
export interface EtapaPerformance { etapa: string; alcancaram: number; avancaram: number; conversao_etapa: number | null; denominador: number; amostra_suficiente: boolean;
  perdidos_na_etapa: number; horas_mediana_na_etapa: number | null; medicoes_tempo: number; parados: number }
export interface AtendentePerformance { atendente: string; eu: boolean | null; oportunidades: number; matriculas_comerciais: number; ingressantes: number; conversao: number | null;
  sla_primeiro_contato: number | null; sla_denominador: number; horas_ate_primeiro_contato: number | null; interacoes: number; tarefas_atrasadas: number }
export interface Performance { coorte: string; regra: string; amostra_minima_etapa: number; ve_equipe: boolean; etapas: EtapaPerformance[]; gargalo: EtapaPerformance | null;
  atendentes: AtendentePerformance[]; sla_primeiro_contato_equipe: number | null; recomendacoes: { regra: string; prioridade: number; titulo: string; justificativa: string; proposta: string }[];
  aviso: string; metodos: Record<'conversao_etapa' | 'permanencia' | 'sla' | 'parados', string> }

// Recuperação e Aceleração (migração 15)
export interface ItemRecuperacao { id: number; status: 'selecionada' | 'contatada' | 'reativada' | 'descartada'; observacao: string | null; atribuido_a: string | null; meu: boolean;
  oportunidade_origem_id: number; oportunidade_nova_id: number | null; nome: string; curso: string; coorte_origem: string; motivo_perda: string | null }
export interface Protocolo { id: number; nome: string; tipo: string; responsavel: string; prazo: string; checklist: string[]; meta: number; custo_centavos: number | null;
  coorte_destino: string; carencia_dias: number; status: 'planejado' | 'em_execucao' | 'concluido' | 'cancelado'; resultado: string | null; sprint_id: number | null; vencido: boolean;
  selecionadas: number; contatadas: number; reativadas: number; descartadas: number; ingressantes: number; atingimento_meta: number; custo_por_reativacao_centavos: number | null; itens: ItemRecuperacao[] }
export interface Sprint { id: number; nome: string; objetivo: string; inicio: string; fim: string; status: 'planejada' | 'em_andamento' | 'encerrada'; reavaliacao: string | null; impedimentos: number;
  itens: { id: number; entrega: string; responsavel: string; status: 'a_fazer' | 'fazendo' | 'feito' | 'impedido'; impedimento: string | null }[] }
export interface Recuperacao { pode_gerir: boolean; regra: string; elegibilidade: string; protocolos: Protocolo[]; sprints: Sprint[] }
export interface Recuperavel { id: number; nome: string; curso: string; coorte: string; forma_ingresso: string; motivo_perda: string | null; perdida_em: string; dias_desde_perda: number;
  elegivel: boolean; motivo_inelegivel: string | null; em_protocolo: boolean }

// Academia de Captação (migração 16)
export type Competencia = 'comunicacao' | 'escuta' | 'dominio_tecnico' | 'negociacao_etica' | 'objecoes' | 'registro' | 'disciplina_operacional';
export interface Modulo { id: number; ordem: number; titulo: string; conteudo: string; competencia: Competencia; carga_minutos: number; concluido: boolean }
export interface Trilha { id: number; nome: string; papel_alvo: string; descricao: string | null; modulos: Modulo[] }
export interface Criterio { id: number; competencia: Competencia; descricao: string; niveis: string[]; peso: number }
export interface Rubrica { id: number; nome: string; versao: number; status: 'rascunho' | 'publicada'; criterios: Criterio[] }
export interface Cenario { id: number; titulo: string; perfil_sintetico: string; objetivo: string; objecoes: string | null; etapa_base: string | null }
export interface Avaliacao { id: number; avaliado: string; avaliado_id: string; avaliador: string; meu_rascunho: boolean; rubrica: string; rubrica_id: number; cenario: string | null;
  tipo: 'roleplay' | 'observacao_atendimento'; niveis: Record<string, number>; evidencias: string; comentario: string | null; status: 'rascunho' | 'finalizada';
  criado_em: string; finalizada_em: string | null; consolidado: number | null }
export interface Pdi { id: number; usuario: string; meu: boolean; competencia: Competencia; objetivo: string; acoes: string; prazo: string; reavaliar_em: string | null;
  status: 'aberto' | 'em_andamento' | 'concluido' | 'cancelado'; reavaliacao_vencida: boolean }
export interface Lacuna { usuario: string; meu: boolean; competencia: Competencia; nivel: number; avaliada_em: string; historico: { em: string; nivel: number }[];
  recomendados: { modulo_id: number; titulo: string; trilha: string; concluido: boolean }[]; pdi_aberto: boolean }
export interface Academia { regra: string; ve_equipe: boolean; pode_avaliar: boolean; pode_gerir: boolean; aviso: string; trilhas: Trilha[]; rubricas: Rubrica[];
  cenarios: Cenario[]; equipe: { id: string; nome: string }[] | null; avaliacoes: Avaliacao[]; pdis: Pdi[]; lacunas: Lacuna[] }

// Relacionamento Estudantil (migração 17)
export type Marco = 'd30' | 'd90' | 'rematricula';
export interface Permanencia { marco: Marco; elegiveis: number; registrados: number; ativos: number; desconhecidos: number; cobertura: number | null;
  permanencia: number | null; minimo_observado: number | null; motivo: string | null }
export interface Ingressante { id: number; nome: string; curso: string; confirmada_em: string; dias_desde_ingresso: number;
  vinculos: Partial<Record<Marco, { situacao: string; data: string; observacao: string | null; por: string | null }>>; onboarding: string[]; embaixador: boolean }
export interface Relacionamento { coorte: string; regra: string; pode_registrar: boolean; pode_gerir: boolean; pode_indicar: boolean; marcos: Record<Marco, number>;
  onboarding_modelo: string[]; programa_embaixadores: string | null; permanencia: Permanencia[];
  alertas: { regra: string; prioridade: number; titulo: string; quantidade: number; proposta: string }[]; ingressantes: Ingressante[];
  embaixadores: { id: number; nome: string; curso: string; status: string; aceite_regras_em: string; regras_atuais: boolean; indicacoes: number; ingressantes_indicados: number }[];
  indicacoes: { id: number; codigo: string; indicador_tipo: string; indicador_nome: string; leads: number; ingressantes: number }[]; metodos: Record<string, string> }

// P4 (migrações 18–21)
export interface Formulario { id: number; slug: string; titulo: string; descricao: string | null; cursos: number[]; coorte: string; forma_ingresso: string; campanha_id: number | null;
  texto_consentimento: string; versao_consentimento: number; pede_telefone: boolean; ativo: boolean; resultados: Record<string, number> | null }
export interface FormularioPublico { titulo: string; descricao: string | null; instituicao: string; pede_telefone: boolean; texto_consentimento: string; versao_consentimento: number;
  cursos: { id: number; nome: string; turno: string; modalidade: string; campus: string }[] }
export interface PortalDados { nome: string; email: string | null; telefone: string | null; instituicao: string; optout: Record<'email' | 'whatsapp' | 'telefone', boolean>;
  consentimento: { versao: number | null; em: string | null; base_legal: string };
  inscricoes: { id: number; curso: string; turno: string; modalidade: string; coorte: string; situacao: string; etapa: string; validacoes: Record<string, boolean> | null;
    proposta: { valor_final_centavos: number; validade: string; status: string } | null }[];
  solicitacoes: { tipo: string; status: string; resposta: string | null; criado_em: string }[] }
export interface ItemChecklist { tipo: string; descricao: string; obrigatorio: boolean;
  documento: { id: number; nome_arquivo: string; mime: string; tamanho: number; status: string; motivo_recusa: string | null; enviado_em: string; enviado_por_tipo: string } | null }
export interface DocumentosOp { checklist: ItemChecklist[]; completo: boolean; exigido_para_validar: boolean; pode_revisar: boolean;
  historico: { id: number; tipo: string; nome_arquivo: string; status: string; enviado_em: string; enviado_por: string; revisado_por: string | null; motivo_recusa: string | null; sha256: string }[] }
export interface PortalSeletivo {
  processos_abertos: { id: number; nome: string; tipo: string; coorte: string; inscricoes_ate: string; instrucoes: string | null; agendas: { id: number; inicio: string; local: string; vagas_restantes: number }[] }[];
  candidaturas: { id: number; processo: string; tipo: string; curso: string; oportunidade_id: number; agenda: { inicio: string; local: string } | null; tema_redacao: string | null;
    redacao_enviada: boolean; resultado: string | null; resultado_divulgado: boolean }[];
  eventos: { titulo: string; tipo: string; inicio: string; local: string | null; online: boolean; status: string }[] }
export interface PortalMatricula { oportunidade_id: number; curso: string; coorte: string; etapa: string;
  procedimento?: string; prazo_arrependimento_dias?: number; confirmacao?: { canal: string; destino: string };
  proposta: { id: number; mensalidade_centavos: number; desconto_pct: number; valor_final_centavos: number; validade: string; status: string } | null;
  contrato: { versao: number; texto: string } | null;
  aceite: { aceito_em: string; contrato_versao: number; evidencia_hash?: string | null; arrependimento_ate?: string; desistencia_em?: string | null; pode_desistir?: boolean } | null;
  pagamento: string }
export interface DadosAceite { contrato_versao: number; proposta_id: number; li_contrato: boolean; concordo_condicoes: boolean; ciente_arrependimento: boolean;
  nome: string; cpf: string; nascimento: string; codigo: string;
  responsavel?: { nome: string; cpf: string; nascimento: string; vinculo: string; declaro: boolean } }
export interface CodigoAceite { canal: string; destino: string; expira_em: string; modo: string; codigo_simulacao?: string; aviso: string }
export interface ComprovanteAceite { instituicao: string; curso: string; coorte: string; aceito_em: string; procedimento: string;
  evidencia: Record<string, unknown> | null; evidencia_texto: string | null; evidencia_hash: string | null; evidencia_integra: boolean | null;
  contrato_versao: number; contrato_texto: string; contrato_hash: string; contrato_integro: boolean; nome_confirmado: string;
  arrependimento_ate: string; desistencia_em: string | null; desistencia_motivo: string | null }
export interface SolicitacaoTitular { id: number; tipo: string; detalhe: string | null; status: string; resposta: string | null; criado_em: string; nome: string; pessoa_id: number; prazo: string; oportunidade_id: number | null }
export interface Evento { id: number; titulo: string; tipo: string; inicio: string; fim: string; local: string | null; online: boolean; vagas: number | null; status: string; campanha_id: number | null;
  inscritos: number; presentes: number; ingressantes_presentes: number; inscricoes: { id: number; nome: string; status: string; oportunidade_id: number | null; checkin_em: string | null }[] }
export interface Candidatura { id: number; oportunidade_id: number; nome: string; curso: string; agenda: string | null; nota_enem: number | null; enem_conferido: boolean; nota_objetiva: number | null;
  redacao_enviada: boolean; redacao: string | null; redacao_nota: number | null; redacao_parecer: string | null; corrigida_por: string | null; resultado: string; justificativa: string | null;
  resultado_por: string | null; sugestao: string | null }
export interface Seletivo { pode_gerir: boolean; pode_divulgar: boolean; aviso: string;
  processos: { id: number; nome: string; tipo: string; coorte: string; inscricoes_ate: string; nota_minima: number | null; instrucoes: string | null; tema_redacao: string | null; status: string;
    resultado_divulgado_em: string | null; agendas: { id: number; inicio: string; local: string; vagas: number; ocupadas: number }[]; candidaturas: Candidatura[] }[] }
export interface Comunicacao { modo: string; pode_gerir: boolean; aviso: string;
  modelos: { id: number; nome: string; canal: string; gatilho: string; assunto: string | null; corpo: string; ativo: boolean; simuladas: number; bloqueadas: number; copiadas: number; abertura: null; clique: null }[];
  recentes: { id: number; canal: string; destino: string | null; status: string; motivo: string | null; em: string; nome: string; corpo: string }[] | null }

// Bolsas e financiamento (migração 23)
export interface ProgramaBolsa { id: number; nome: string; tipo: string; percentual_max: number; cursos: number[] | null; vagas: number | null; cumulativo: boolean;
  validade_ate: string | null; requisitos: string | null; documentos: string[]; visivel_portal: boolean; ativo: boolean;
  solicitadas: number; aprovadas: number; confirmados: number; percentual_medio: number | null }
export interface SolicitacaoBolsa { id: number; oportunidade_id: number; nome: string; curso: string; etapa: string; programa: string; tipo: string; percentual: number;
  status: string; etapa_externa: string | null; origem: string; declaracao: string | null; solicitado_em: string; solicitado_por: string | null;
  decidido_por: string | null; decidido_em: string | null; justificativa: string | null; decide_proprio: boolean }
export interface Bolsas { pode_gerir: boolean; pode_decidir: boolean; pode_solicitar: boolean; aviso: string; programas: ProgramaBolsa[]; solicitacoes: SolicitacaoBolsa[] }
export interface PortalBolsas { oportunidade_id: number; curso: string;
  programas: { id: number; nome: string; tipo: string; percentual_max: number; requisitos: string | null; documentos: string[]; validade_ate: string | null }[];
  solicitacoes: { id: number; programa: string; percentual: number; status: string; etapa_externa: string | null; justificativa: string | null }[] }

// Rematrícula (migração 24)
export interface AlunoRematricula { id: number; oportunidade_id: number; nome: string; curso: string; coorte: string; status: string; categoria: string | null;
  motivo: string | null; origem: string | null; respondido_em: string | null; tratado_por: string | null; evidencia_hash: string | null }
export interface CampanhaRematricula { id: number; periodo: string; abre_em: string; fecha_em: string; coortes: string[] | null; termo: string; meta_pct: number | null; status: string;
  totais: { elegiveis: number; aceitas: number; recusadas: number; bloqueadas: number; pendentes: number; taxa_pct: number | null }; alunos: AlunoRematricula[] }
export interface Rematricula { pode_gerir: boolean; pode_tratar: boolean; aviso: string; campanhas: CampanhaRematricula[] }
export interface PortalRematricula { id: number; periodo: string; curso: string; abre_em: string; fecha_em: string; aberta_agora: boolean; termo: string; status: string;
  bloqueio: string | null; respondido_em: string | null; evidencia_hash: string | null; exige_representante: boolean; cpf_no_aceite: boolean }
