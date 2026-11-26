// Chamadas tipadas às RPCs. Cada função corresponde a uma RPC homologada no Supabase.
import { criarCliente, type Cliente, type Config, ErroApi } from './supabase';
import type {
  AcessosIes, Bi, Detalhe, Estrutura, Eu, EventoAuditoria, Fila, IesMaster, ItemOportunidade, Pagina, Pendencia, PropostaLista,
  ResultadoMaim, StatusProposta, Etapa, Dimensao, Canal, Papel, Central, ItemAgenda, Permissoes, Exportacao, Planejamento, RegistroConcorrencia, Campanhas,
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
  sair: () => c().sair(),
  eu: () => c().rpc<Eu>('rpc_me'),
  estrutura: (ies: number) => c().rpc<Estrutura>('rpc_estrutura', { p_ies: ies }),
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
