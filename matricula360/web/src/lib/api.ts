// Chamadas tipadas às RPCs. Cada função corresponde a uma RPC homologada no Supabase.
import { criarCliente, type Cliente, type Config, ErroApi } from './supabase';
import type {
  AcessosIes, Bi, Detalhe, Estrutura, Eu, EventoAuditoria, Fila, IesMaster, ItemOportunidade, Pagina, Pendencia, PropostaLista,
  ResultadoMaim, StatusProposta, Etapa, Dimensao, Canal, Papel, Central, ItemAgenda, Permissoes, Exportacao, Planejamento, RegistroConcorrencia, Campanhas, Funis, FunilOportunidade, VersaoFunil, Performance, Recuperacao, Recuperavel, Academia, Relacionamento, Formulario, SolicitacaoTitular, DocumentosOp, Evento, Seletivo, Comunicacao, FormularioPublico, PortalDados, ItemChecklist, PortalSeletivo, PortalMatricula, Bolsas, PortalBolsas, Rematricula, PortalRematricula, Casos, Campo, LeadCampo, DadosAceite, CodigoAceite, ComprovanteAceite,
} from './tipos';

let cliente: Cliente | null = null;
let configuracao: Config | null = null;

export async function iniciar(): Promise<Config> {
  if (configuracao) return configuracao;
  const r = await fetch('/config.json');
  const cfg = (r.ok && (r.headers.get('content-type') || '').includes('json')
    ? await r.json().catch(() => null)
    : null) as Config | null;
  if (!cfg) throw new ErroApi('Configuração do sistema ausente (config.json). Verifique a publicação.', 500);
  if (cfg.modo !== 'supabase' || !cfg.supabase_url || !cfg.supabase_chave_publicavel) {
    throw new ErroApi('Esta interface exige o modo Supabase (M360_SUPABASE_URL e M360_SUPABASE_CHAVE_PUBLICAVEL).', 500);
  }
  cliente = criarCliente(cfg.supabase_url, cfg.supabase_chave_publicavel);
  configuracao = cfg;
  return cfg;
}
// Sem internet (modo feira), a casca da aplicação usa a última leitura de perfil e estrutura desta aba.
// Só falha de rede usa o cache; erro do banco (permissão, 2FA) nunca é mascarado.
async function comCache<T>(chave: string, fn: () => Promise<T>): Promise<T> {
  try {
    const v = await fn();
    try { sessionStorage.setItem(chave, JSON.stringify(v)); } catch { /* sem storage */ }
    return v;
  } catch (e) {
    if (e instanceof ErroApi) throw e;
    try { const v = sessionStorage.getItem(chave); if (v) return JSON.parse(v) as T; } catch { /* sem storage */ }
    throw e;
  }
}

function c(): Cliente {
  if (!cliente) throw new ErroApi('Cliente não iniciado', 500);
  return cliente;
}
// O banco tem a migração 10 (CRM avançado)? Sonda barata, memorizada por IES. Sem ela, a interface usa o modo básico.
const sondas = new Map<number, Promise<boolean>>();
export function temCrmAvancado(ies: number): Promise<boolean> {
  if (!sondas.has(ies)) {
    sondas.set(ies, c().rpc('rpc_listar_oportunidades', { p_ies: ies, p_pagina: 1, p_por_pagina: 1, p_busca: 'sonda' })
      .then(() => true)
      .catch((e: ErroApi) => { if (e.codigo === 'PGRST202' || e.status === 404) return false; sondas.delete(ies); throw e; }));
  }
  return sondas.get(ies)!;
}
const chave = () => (crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`);

export const api = {
  entrar: (email: string, senha: string) => c().entrar(email, senha),
  sair: () => { try { Object.keys(sessionStorage).filter((k) => k.startsWith('m360_cache_')).forEach((k) => sessionStorage.removeItem(k)); } catch { /* sem storage */ } return c().sair(); },
  eu: () => comCache('m360_cache_eu', () => c().rpc<Eu>('rpc_me')),
  segurancaConta: () => c().rpc<{ aal: string; tem_fator: boolean; exigido: boolean; ok: boolean; ies_que_exigem: string[] }>('rpc_seguranca_conta'),
  fatores: () => c().fatores(),
  cadastrarTotp: () => c().cadastrarTotp(),
  verificarTotp: (fator: string, codigo: string) => c().verificarTotp(fator, codigo),
  removerFator: (fator: string) => c().removerFator(fator),
  situacao2fa: (ies: number) => c().rpc<{ exigir_2fa: boolean; equipe: { nome: string; com_fator: boolean }[] }>('rpc_situacao_2fa', { p_ies: ies }),
  configurar2fa: (ies: number, exigir: boolean) => c().rpc<{ exigir_2fa: boolean; usuarios_sem_fator: number }>('rpc_configurar_2fa', { p_ies: ies, p_exigir: exigir }),
  estrutura: (ies: number) => comCache(`m360_cache_estrutura_${ies}`, () => c().rpc<Estrutura>('rpc_estrutura', { p_ies: ies })),
  central: (ies: number, coorte: string, filtros: Record<string, string>) =>
    c().rpc<Central>('rpc_central', { p_ies: ies, p_coorte: coorte, p_filtros: Object.fromEntries(Object.entries(filtros).filter(([, v]) => v)) }),
  metas: (ies: number, coorte: string) => c().rpc<{ curso_id: number; meta: number }[]>('rpc_metas', { p_ies: ies, p_coorte: coorte }),
  bi: (ies: number, coorte: string, agrupar = 'curso') => c().rpc<Bi>('rpc_bi', { p_ies: ies, p_coorte: coorte, p_agrupar: agrupar }),
  fila: (ies: number) => c().rpc<Fila>('rpc_fila', { p_ies: ies }),
  cicloMaim: (ies: number) => c().rpc<ResultadoMaim>('rpc_ciclo_maim', { p_ies: ies }),
  concluirTarefa: (tarefa: number, resultado: string) => c().rpc<{ id: number; status: string; motivo: string | null }>('rpc_concluir_tarefa', { p_tarefa: tarefa, p_resultado: resultado }),
  dispararTarefa: (tarefa: number) => c().rpc<{ enviado: false; motivo: string; elegivel: boolean }>('rpc_disparar_tarefa', { p_tarefa: tarefa }),
  // Parâmetros novos (migração 10) só são enviados quando usados: a chamada básica funciona também no banco anterior.
  oportunidades: (ies: number, f: { etapa?: Etapa; coorte?: string; curso?: number; pagina?: number; porPagina?: number;
    busca?: string; forma?: string; somenteMeus?: boolean; slaAtrasado?: boolean }) =>
    c().rpc<Pagina<ItemOportunidade>>('rpc_listar_oportunidades', {
      p_ies: ies, p_etapa: f.etapa ?? null, p_coorte: f.coorte ?? null, p_pagina: f.pagina ?? 1, p_por_pagina: f.porPagina ?? 25, p_curso: f.curso ?? null,
      ...(f.busca ? { p_busca: f.busca } : {}), ...(f.forma ? { p_forma: f.forma } : {}),
      ...(f.somenteMeus ? { p_somente_meus: true } : {}), ...(f.slaAtrasado ? { p_sla_atrasado: true } : {}) }),
  criarOportunidade: (ies: number, dados: Record<string, unknown>) =>
    c().rpc<{ id: number; duplicada: boolean; versao: number; etapa: Etapa; repeticao?: boolean }>('rpc_criar_oportunidade', { p_ies: ies, p_dados: dados, p_chave: chave() }),
  detalhe: (op: number) => c().rpc<Detalhe>('rpc_detalhe', { p_op: op }),
  moverEtapa: (op: number, para: Etapa, versao: number, motivo?: string) =>
    c().rpc<{ id: number; etapa: Etapa; versao: number }>('rpc_mover_etapa', { p_op: op, p_para: para, p_versao: versao, p_motivo: motivo ?? null, p_chave: chave() }),
  validar: (op: number, dimensao: Dimensao, resultado: string, evidencia: string, versao: number) =>
    c().rpc<{ versao: number }>('rpc_validar', { p_op: op, p_dimensao: dimensao, p_resultado: resultado, p_evidencia: evidencia, p_versao: versao }),
  confirmar: (op: number, versao: number) => c().rpc<{ versao: number }>('rpc_confirmar', { p_op: op, p_versao: versao }),
  cancelar: (op: number, versao: number, motivo: string) => c().rpc<{ versao: number }>('rpc_cancelar', { p_op: op, p_versao: versao, p_motivo: motivo }),
  criarProposta: (op: number, desconto: number, validadeDias: number) =>
    c().rpc<{ id: number; status: StatusProposta; valor_final_centavos: number; limite_pct: number }>('rpc_criar_proposta', { p_op: op, p_desconto: desconto, p_validade_dias: validadeDias }),
  decidirProposta: (proposta: number, decisao: 'aprovar' | 'rejeitar') => c().rpc<{ id: number; status: StatusProposta }>('rpc_decidir_proposta', { p_proposta: proposta, p_decisao: decisao }),
  aceitarProposta: (proposta: number) => c().rpc<{ id: number; status: StatusProposta }>('rpc_aceitar_proposta', { p_proposta: proposta }),
  propostas: (ies: number, status: StatusProposta) => c().rpc<PropostaLista[]>('rpc_listar_propostas', { p_ies: ies, p_status: status }),
  optout: (op: number, canal: Canal) => c().rpc<{ canal: Canal; tarefas_suprimidas: number }>('rpc_optout', { p_op: op, p_canal: canal }),
  anonimizar: (op: number) => c().rpc<{ anonimizada: true }>('rpc_anonimizar', { p_op: op }),
  registrarInteracao: (op: number, tipo: string, resumo: string) => c().rpc<{ id: number }>('rpc_registrar_interacao', { p_op: op, p_tipo: tipo, p_resumo: resumo }),
  registrarObjecao: (op: number, categoria: string, descricao: string) => c().rpc<{ id: number }>('rpc_registrar_objecao', { p_op: op, p_categoria: categoria, p_descricao: descricao }),
  tratarObjecao: (objecao: number, status: string, tratamento: string) => c().rpc('rpc_tratar_objecao', { p_objecao: objecao, p_status: status, p_tratamento: tratamento }),
  agendar: (op: number, quando: string, descricao: string, canal?: string) => c().rpc<{ id: number }>('rpc_agendar', { p_op: op, p_quando: quando, p_descricao: descricao, p_canal: canal ?? null }),
  agenda: (ies: number, de: string, ate: string) => c().rpc<ItemAgenda[]>('rpc_agenda', { p_ies: ies, p_de: de, p_ate: ate }),
  reatribuir: (op: number, responsavel: string, motivo: string) => c().rpc<{ tarefas_transferidas: number }>('rpc_reatribuir', { p_op: op, p_responsavel: responsavel, p_motivo: motivo }),
  atendentes: (ies: number, curso?: number) => c().rpc<{ id: string; nome: string }[]>('rpc_atendentes', { p_ies: ies, p_curso: curso ?? null }),
  permissoes: (ies: number) => c().rpc<Permissoes>('rpc_permissoes', { p_ies: ies }),
  exportar: (ies: number, coorte?: string, curso?: number) =>
    c().rpc<Exportacao>('rpc_exportar_oportunidades', { p_ies: ies, p_coorte: coorte || null, p_curso: curso ?? null }),
  planejamento: (ies: number, coorte: string) => c().rpc<Planejamento>('rpc_planejamento', { p_ies: ies, p_coorte: coorte }),
  salvarPlano: (ies: number, dados: Record<string, unknown>, id?: number, versao?: number) =>
    c().rpc<{ id: number; versao: number }>('rpc_salvar_plano', { p_ies: ies, p_dados: dados, p_id: id ?? null, p_versao: versao ?? null }),
  planoStatus: (plano: number, acao: string, justificativa?: string) => c().rpc<{ status: string }>('rpc_plano_status', { p_plano: plano, p_acao: acao, p_justificativa: justificativa ?? null }),
  salvarObjetivo: (plano: number, dados: Record<string, unknown>, id?: number) => c().rpc<{ id: number }>('rpc_salvar_objetivo', { p_plano: plano, p_dados: dados, p_id: id ?? null }),
  salvarAcao: (plano: number, dados: Record<string, unknown>, id?: number) => c().rpc<{ id: number }>('rpc_salvar_acao', { p_plano: plano, p_dados: dados, p_id: id ?? null }),
  concorrencia: (ies: number) => c().rpc<RegistroConcorrencia[]>('rpc_concorrencia', { p_ies: ies }),
  registrarConcorrencia: (ies: number, dados: Record<string, unknown>) => c().rpc<{ id: number }>('rpc_registrar_concorrencia', { p_ies: ies, p_dados: dados }),
  revisarConcorrencia: (id: number) => c().rpc('rpc_revisar_concorrencia', { p_id: id }),
  campanhas: (ies: number, coorte: string) => c().rpc<Campanhas>('rpc_campanhas', { p_ies: ies, p_coorte: coorte }),
  salvarCampanha: (ies: number, dados: Record<string, unknown>, id?: number, versao?: number) =>
    c().rpc<{ id: number; versao: number }>('rpc_salvar_campanha', { p_ies: ies, p_dados: dados, p_id: id ?? null, p_versao: versao ?? null }),
  lancarCusto: (campanha: number, data: string, valor: number, descricao: string) =>
    c().rpc<{ id: number; repeticao: boolean }>('rpc_lancar_custo', { p_campanha: campanha, p_data: data, p_valor_centavos: valor, p_descricao: descricao, p_chave: chave() }),
  estornarCusto: (custo: number, motivo: string) => c().rpc('rpc_estornar_custo', { p_custo: custo, p_motivo: motivo }),
  funis: (ies: number) => c().rpc<Funis>('rpc_funis', { p_ies: ies }),
  funilOportunidade: (op: number) => c().rpc<FunilOportunidade>('rpc_funil_oportunidade', { p_op: op }),
  salvarFunil: (ies: number, dados: Record<string, unknown>, id?: number) => c().rpc<{ id: number; versao_id?: number }>('rpc_salvar_funil', { p_ies: ies, p_dados: dados, p_id: id ?? null }),
  novaVersao: (funil: number) => c().rpc<{ versao_id: number; versao: number }>('rpc_nova_versao', { p_funil: funil }),
  salvarVersao: (versao: number, dados: Record<string, unknown>) => c().rpc<VersaoFunil>('rpc_salvar_versao', { p_versao: versao, p_dados: dados }),
  publicarVersao: (versao: number) => c().rpc<{ versao: number; arquivada: number | null }>('rpc_publicar_versao', { p_versao: versao }),
  moverSubetapa: (op: number, ordem: number, versao: number) => c().rpc<{ versao: number }>('rpc_mover_subetapa', { p_op: op, p_ordem: ordem, p_versao: versao }),
  performance: (ies: number, coorte: string, filtros: Record<string, string>) =>
    c().rpc<Performance>('rpc_performance', { p_ies: ies, p_coorte: coorte, p_filtros: Object.fromEntries(Object.entries(filtros).filter(([k, v]) => v && k !== 'campanha_id')) }),
  recuperacao: (ies: number) => c().rpc<Recuperacao>('rpc_recuperacao', { p_ies: ies }),
  recuperaveis: (ies: number, carencia: number, motivo?: string, curso?: number) =>
    c().rpc<Recuperavel[]>('rpc_recuperaveis', { p_ies: ies, p_carencia: carencia, p_motivo: motivo || null, p_curso: curso ?? null }),
  salvarProtocolo: (ies: number, dados: Record<string, unknown>, id?: number) => c().rpc<{ id: number }>('rpc_salvar_protocolo', { p_ies: ies, p_dados: dados, p_id: id ?? null }),
  selecionarRecuperacao: (protocolo: number, ops: number[]) =>
    c().rpc<{ selecionadas: number; recusadas: { id: number; motivo: string }[] }>('rpc_selecionar_recuperacao', { p_protocolo: protocolo, p_ops: ops, p_atribuir: null }),
  tratarRecuperacao: (item: number, acao: string, observacao?: string) =>
    c().rpc<{ oportunidade: number | null }>('rpc_tratar_recuperacao', { p_item: item, p_acao: acao, p_observacao: observacao ?? null }),
  salvarSprint: (ies: number, dados: Record<string, unknown>, id?: number) => c().rpc<{ id: number }>('rpc_salvar_sprint', { p_ies: ies, p_dados: dados, p_id: id ?? null }),
  salvarItemSprint: (sprint: number, dados: Record<string, unknown>, id?: number) => c().rpc<{ id: number }>('rpc_salvar_item_sprint', { p_sprint: sprint, p_dados: dados, p_id: id ?? null }),
  academia: (ies: number) => c().rpc<Academia>('rpc_academia', { p_ies: ies }),
  concluirModulo: (modulo: number) => c().rpc('rpc_concluir_modulo', { p_modulo: modulo }),
  salvarAvaliacao: (ies: number, dados: Record<string, unknown>, finalizar: boolean, id?: number) =>
    c().rpc<{ id: number; status: string; consolidado: number | null }>('rpc_salvar_avaliacao', { p_ies: ies, p_dados: dados, p_id: id ?? null, p_finalizar: finalizar }),
  salvarPdi: (ies: number, dados: Record<string, unknown>, id?: number) => c().rpc<{ id: number }>('rpc_salvar_pdi', { p_ies: ies, p_dados: dados, p_id: id ?? null }),
  salvarRubrica: (ies: number, acao: string, rubrica: number, criterios?: unknown[]) =>
    c().rpc<{ id: number }>('rpc_salvar_rubrica', { p_ies: ies, p_acao: acao, p_rubrica: rubrica, p_criterios: criterios ?? null }),
  salvarCenario: (ies: number, dados: Record<string, unknown>) => c().rpc<{ id: number }>('rpc_salvar_cenario', { p_ies: ies, p_dados: dados }),
  relacionamento: (ies: number, coorte: string) => c().rpc<Relacionamento>('rpc_relacionamento', { p_ies: ies, p_coorte: coorte }),
  registrarVinculo: (op: number, marco: string, situacao: string, data: string, observacao?: string) =>
    c().rpc('rpc_registrar_vinculo', { p_op: op, p_marco: marco, p_situacao: situacao, p_data: data, p_observacao: observacao ?? null }),
  onboardingItem: (op: number, item: string, concluido: boolean) => c().rpc('rpc_onboarding_item', { p_op: op, p_item: item, p_concluido: concluido }),
  configurarRelacionamento: (ies: number, onboarding: string[] | null, programa: string | null) =>
    c().rpc('rpc_configurar_relacionamento', { p_ies: ies, p_onboarding: onboarding, p_programa: programa }),
  salvarEmbaixador: (op: number, aceite: string, status = 'ativo') => c().rpc<{ id: number }>('rpc_salvar_embaixador', { p_op: op, p_aceite_em: aceite, p_status: status }),
  criarIndicacao: (ies: number, dados: Record<string, unknown>) => c().rpc<{ codigo: string }>('rpc_criar_indicacao', { p_ies: ies, p_dados: dados }),
  indicacoes: (ies: number) => c().rpc<{ id: number; codigo: string; indicador_tipo: string; indicador_nome: string; leads: number }[]>('rpc_indicacoes', { p_ies: ies }),
  // P4: captação digital, portal, documentos, eventos, seletivo, matrícula online, comunicação e integrações
  formularios: (ies: number) => c().rpc<Formulario[]>('rpc_formularios', { p_ies: ies }),
  salvarFormulario: (ies: number, dados: Record<string, unknown>, id?: number) => c().rpc<{ id: number }>('rpc_salvar_formulario', { p_ies: ies, p_dados: dados, p_id: id ?? null }),
  vincularEventoFormulario: (form: number, evento: number | null) => c().rpc('rpc_vincular_evento_formulario', { p_formulario: form, p_evento: evento }),
  gerarAcessoPortal: (op: number) => c().rpc<{ token: string; validade_dias: number }>('rpc_gerar_acesso_portal', { p_op: op }),
  solicitacoesTitular: (ies: number) => c().rpc<SolicitacaoTitular[]>('rpc_solicitacoes_titular', { p_ies: ies }),
  tratarSolicitacao: (id: number, status: string, resposta: string) => c().rpc('rpc_tratar_solicitacao', { p_id: id, p_status: status, p_resposta: resposta }),
  documentos: (op: number) => c().rpc<DocumentosOp>('rpc_documentos', { p_op: op }),
  bolsas: (ies: number, op?: number) => c().rpc<Bolsas>('rpc_bolsas', { p_ies: ies, p_op: op ?? null }),
  salvarProgramaBolsa: (ies: number, dados: Record<string, unknown>, id?: number) => c().rpc<{ id: number }>('rpc_salvar_programa_bolsa', { p_ies: ies, p_dados: dados, p_id: id ?? null }),
  solicitarBolsa: (op: number, programa: number, percentual: number, obs?: string) => c().rpc('rpc_solicitar_bolsa', { p_op: op, p_programa: programa, p_percentual: percentual, p_observacao: obs ?? null }),
  decidirBolsa: (id: number, status: string, justificativa: string, percentual?: number) => c().rpc('rpc_decidir_bolsa', { p_id: id, p_status: status, p_justificativa: justificativa, p_percentual: percentual ?? null }),
  etapaBolsa: (id: number, etapa: string) => c().rpc('rpc_etapa_bolsa', { p_id: id, p_etapa: etapa }),
  cancelarBolsa: (id: number, motivo: string) => c().rpc('rpc_cancelar_bolsa', { p_id: id, p_motivo: motivo }),
  rematricula: (ies: number) => c().rpc<Rematricula>('rpc_rematricula', { p_ies: ies }),
  salvarCampanhaRematricula: (ies: number, dados: Record<string, unknown>, id?: number) => c().rpc<{ id: number }>('rpc_salvar_campanha_rematricula', { p_ies: ies, p_dados: dados, p_id: id ?? null }),
  statusCampanhaRematricula: (id: number, status: string) => c().rpc<{ novos_elegiveis: number }>('rpc_status_campanha_rematricula', { p_id: id, p_status: status }),
  tratarRematricula: (id: number, acao: string, motivo?: string, categoria?: string) => c().rpc('rpc_tratar_rematricula', { p_id: id, p_acao: acao, p_motivo: motivo ?? null, p_categoria: categoria ?? null }),
  casos: (ies: number, op?: number) => c().rpc<Casos>('rpc_casos', { p_ies: ies, p_op: op ?? null }),
  abrirCaso: (op: number, motivo: string, descricao: string, prioridade: string) => c().rpc<{ id: number; responsavel: string | null }>('rpc_abrir_caso', { p_op: op, p_motivo: motivo, p_descricao: descricao, p_prioridade: prioridade }),
  atenderCaso: (id: number, acao: string, texto?: string, agendado?: string, responsavel?: string) =>
    c().rpc('rpc_atender_caso', { p_id: id, p_acao: acao, p_texto: texto ?? null, p_agendado_para: agendado ?? null, p_responsavel: responsavel ?? null }),
  salvarTrilha: (ies: number, motivo: string, dados: Record<string, unknown>) => c().rpc('rpc_salvar_trilha', { p_ies: ies, p_motivo: motivo, p_dados: dados }),
  campo: (ies: number) => c().rpc<Campo>('rpc_campo', { p_ies: ies }),
  salvarEscola: (ies: number, dados: Record<string, unknown>, id?: number) => c().rpc<{ id: number }>('rpc_salvar_escola', { p_ies: ies, p_dados: dados, p_id: id ?? null }),
  salvarVisita: (ies: number, dados: Record<string, unknown>, id?: number) => c().rpc<{ id: number; codigo: string }>('rpc_salvar_visita', { p_ies: ies, p_dados: dados, p_id: id ?? null }),
  captarCampo: (visita: number, leads: LeadCampo[]) => c().rpc<{ recebidos: number; ja_sincronizados: number; contatos_existentes: number; rejeitados: { id_local: string; nome: string; motivo: string }[] }>('rpc_captar_campo', { p_visita: visita, p_leads: leads }),
  comprovanteAceite: (op: number) => c().rpc<ComprovanteAceite>('rpc_comprovante_aceite', { p_op: op }),
  enviarDocumento: (op: number, tipo: string, nome: string, base64: string) => c().rpc('rpc_enviar_documento', { p_op: op, p_tipo: tipo, p_nome: nome, p_base64: base64 }),
  baixarDocumento: (doc: number) => c().rpc<{ nome_arquivo: string; mime: string; base64: string }>('rpc_baixar_documento', { p_documento: doc }),
  revisarDocumento: (doc: number, status: string, motivo?: string) => c().rpc('rpc_revisar_documento', { p_documento: doc, p_status: status, p_motivo: motivo ?? null }),
  configurarDocumentos: (ies: number, exigir: boolean | null, item?: Record<string, unknown>) =>
    c().rpc<{ exigir_documentos: boolean; itens: { tipo: string; forma_ingresso: string | null; descricao: string; obrigatorio: boolean; ativo: boolean }[] }>('rpc_configurar_documentos', { p_ies: ies, p_exigir: exigir, p_item: item ?? null }),
  eventos: (ies: number) => c().rpc<Evento[]>('rpc_eventos', { p_ies: ies }),
  salvarEvento: (ies: number, dados: Record<string, unknown>, id?: number) => c().rpc<{ id: number }>('rpc_salvar_evento', { p_ies: ies, p_dados: dados, p_id: id ?? null }),
  inscreverEvento: (evento: number, op: number) => c().rpc('rpc_inscrever_evento', { p_evento: evento, p_op: op }),
  checkin: (inscricao: number, status: string) => c().rpc('rpc_checkin', { p_inscricao: inscricao, p_status: status }),
  seletivo: (ies: number) => c().rpc<Seletivo>('rpc_seletivo', { p_ies: ies }),
  salvarProcesso: (ies: number, dados: Record<string, unknown>, id?: number) => c().rpc<{ id: number }>('rpc_salvar_processo', { p_ies: ies, p_dados: dados, p_id: id ?? null }),
  candidatar: (processo: number, op: number, agenda?: number, enem?: number) => c().rpc('rpc_candidatar', { p_processo: processo, p_op: op, p_agenda: agenda ?? null, p_nota_enem: enem ?? null }),
  avaliarCandidatura: (id: number, dados: Record<string, unknown>) => c().rpc('rpc_avaliar_candidatura', { p_candidatura: id, p_dados: dados }),
  divulgarResultado: (processo: number) => c().rpc('rpc_divulgar_resultado', { p_processo: processo }),
  contratos: (ies: number) => c().rpc<{ aviso: string; versoes: { id: number; versao: number; ativo: boolean; criado_em: string; texto: string; aceites: number }[] }>('rpc_contratos', { p_ies: ies }),
  salvarContrato: (ies: number, texto: string) => c().rpc<{ versao: number }>('rpc_salvar_contrato', { p_ies: ies, p_texto: texto }),
  comunicacao: (ies: number) => c().rpc<Comunicacao>('rpc_comunicacao', { p_ies: ies }),
  salvarModeloMensagem: (ies: number, dados: Record<string, unknown>, id?: number) => c().rpc('rpc_salvar_modelo_mensagem', { p_ies: ies, p_dados: dados, p_id: id ?? null }),
  executarRegua: (ies: number) => c().rpc<{ simuladas: number; bloqueadas: number; enviadas: number }>('rpc_executar_regua', { p_ies: ies }),
  mensagemManual: (op: number, modelo: number) => c().rpc<{ canal: string; assunto: string | null; texto: string }>('rpc_mensagem_manual', { p_op: op, p_modelo: modelo }),
  integracoes: (ies: number, tipo?: string, observacao?: string) =>
    c().rpc<{ aviso: string; itens: { tipo: string; status: string; pedido_por: string | null; pedido_em: string | null; observacao: string | null }[] }>('rpc_integracoes', { p_ies: ies, p_tipo: tipo ?? null, p_observacao: observacao ?? null }),
  importarCustos: (ies: number, linhas: unknown[]) => c().rpc<{ importadas: number; repetidas: number; rejeitadas: { linha: number; motivo: string }[] }>('rpc_importar_custos', { p_ies: ies, p_linhas: linhas }),
  importarVinculos: (ies: number, linhas: unknown[]) => c().rpc<{ importadas: number; rejeitadas: { linha: number; motivo: string }[] }>('rpc_importar_vinculos', { p_ies: ies, p_linhas: linhas }),
  pendencias: (ies: number) => c().rpc<Pendencia[]>('rpc_pendencias', { p_ies: ies }),
  configurar: (ies: number, v: { sla_horas?: number; max_followups?: number; dias_sem_contato?: number; capacidade_atendente?: number; amostra_minima_forecast?: number }) =>
    c().rpc<Record<string, number>>('rpc_configurar', { p_ies: ies, p_sla_horas: v.sla_horas ?? null, p_max_followups: v.max_followups ?? null,
      p_dias_sem_contato: v.dias_sem_contato ?? null, p_capacidade_atendente: v.capacidade_atendente ?? null,
      p_amostra_minima_forecast: v.amostra_minima_forecast ?? null }),
  definirMeta: (ies: number, curso: number, coorte: string, meta: number) => c().rpc('rpc_definir_meta', { p_ies: ies, p_curso: curso, p_coorte: coorte, p_meta: meta }),
  auditoria: (ies: number, pagina = 1) => c().rpc<Pagina<EventoAuditoria>>('rpc_auditoria', { p_ies: ies, p_pagina: pagina }),
  master: {
    ies: () => c().rpc<IesMaster[]>('rpc_master_listar_ies'),
    acessos: (ies: number) => c().rpc<AcessosIes>('rpc_master_acessos', { p_ies: ies }),
    provisionar: (nome: string, plano: string, campus: string, cursos: unknown[]) =>
      c().rpc<{ id: number }>('rpc_provisionar_ies', { p_nome: nome, p_plano: plano, p_campus: campus, p_cursos: cursos }),
    status: (ies: number, status: 'ativa' | 'suspensa') => c().rpc('rpc_alterar_status_ies', { p_ies: ies, p_status: status }),
    // p_campus só é enviado quando usado (compatível com o banco anterior à migração 11).
    conceder: (email: string, nome: string, ies: number, curso: number | null, papel: Papel, campus?: number | null) =>
      c().rpc<{ escopo_id: number; perfil_novo: boolean }>('rpc_conceder_escopo_email', { p_email: email, p_nome: nome, p_ies: ies, p_curso: curso, p_papel: papel,
        ...(campus ? { p_campus: campus } : {}) }),
    revogarEscopo: (escopo: number) => c().rpc('rpc_revogar_escopo', { p_escopo: escopo }),
    revogarUsuario: (usuario: string) => c().rpc('rpc_revogar_usuario', { p_usuario: usuario }),
  },
};

// Área pública (sem login): formulário de captação e portal do candidato.
export const publico = {
  iniciar,
  formulario: (slug: string) => c().rpcPublico<FormularioPublico>('rpc_publico_formulario', { p_slug: slug }),
  inscrever: (slug: string, dados: Record<string, unknown>) => c().rpcPublico<{ status: string; mensagem: string; portal?: string }>('rpc_publico_inscrever', { p_slug: slug, p_dados: dados }),
  portal: (t: string) => c().rpcPublico<PortalDados>('rpc_publico_portal', { p_token: t }),
  optout: (t: string, canal: string) => c().rpcPublico('rpc_publico_portal_optout', { p_token: t, p_canal: canal }),
  solicitar: (t: string, tipo: string, detalhe?: string) => c().rpcPublico('rpc_publico_portal_solicitar', { p_token: t, p_tipo: tipo, p_detalhe: detalhe ?? null }),
  documentos: (t: string) => c().rpcPublico<{ oportunidade_id: number; curso: string; coorte: string; checklist: ItemChecklist[] }[]>('rpc_publico_portal_documentos', { p_token: t }),
  enviarDocumento: (t: string, op: number, tipo: string, nome: string, base64: string) =>
    c().rpcPublico('rpc_publico_enviar_documento', { p_token: t, p_op: op, p_tipo: tipo, p_nome: nome, p_base64: base64 }),
  seletivo: (t: string) => c().rpcPublico<PortalSeletivo>('rpc_publico_portal_seletivo', { p_token: t }),
  candidatar: (t: string, processo: number, op: number, agenda?: number, enem?: number) =>
    c().rpcPublico('rpc_publico_candidatar', { p_token: t, p_processo: processo, p_op: op, p_agenda: agenda ?? null, p_nota_enem: enem ?? null }),
  enviarRedacao: (t: string, candidatura: number, texto: string) => c().rpcPublico('rpc_publico_enviar_redacao', { p_token: t, p_candidatura: candidatura, p_texto: texto }),
  matricula: (t: string) => c().rpcPublico<PortalMatricula[]>('rpc_publico_portal_matricula', { p_token: t }),
  bolsas: (t: string) => c().rpcPublico<PortalBolsas[]>('rpc_publico_portal_bolsas', { p_token: t }),
  solicitarBolsa: (t: string, op: number, programa: number, percentual: number, declaracao?: string) =>
    c().rpcPublico<{ mensagem: string }>('rpc_publico_solicitar_bolsa', { p_token: t, p_op: op, p_programa: programa, p_percentual: percentual, p_declaro: true, p_declaracao: declaracao ?? null }),
  rematricula: (t: string) => c().rpcPublico<PortalRematricula[]>('rpc_publico_portal_rematricula', { p_token: t }),
  responderRematricula: (t: string, id: number, dados: Record<string, unknown>) => c().rpcPublico<{ status: string; mensagem: string }>('rpc_publico_responder_rematricula', { p_token: t, p_id: id, p_dados: dados }),
  vincularVisita: (t: string, codigo: string) => c().rpcPublico<{ vinculadas: number }>('rpc_publico_vincular_visita', { p_token: t, p_codigo: codigo }),
  codigoAceite: (t: string, op: number) => c().rpcPublico<CodigoAceite>('rpc_publico_codigo_aceite', { p_token: t, p_op: op }),
  aceitar: (t: string, op: number, dados: DadosAceite) =>
    c().rpcPublico<{ aceito: boolean; erro?: string; tentativas_restantes?: number; proximo_passo?: string; evidencia_hash?: string }>('rpc_publico_aceitar_matricula', { p_token: t, p_op: op, p_dados: dados }),
  comprovante: (t: string, op: number) => c().rpcPublico<ComprovanteAceite>('rpc_publico_comprovante_aceite', { p_token: t, p_op: op }),
  desistir: (t: string, op: number, motivo?: string) => c().rpcPublico<{ cancelado: boolean; mensagem: string }>('rpc_publico_desistir_matricula', { p_token: t, p_op: op, p_motivo: motivo ?? null }),
};
