// Formatação e rótulos. Regra central: indisponível (null) nunca vira zero.
export const ND = 'N/D';

export const moeda = (centavos: number) => (centavos / 100).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
export const pct = (x: number | null | undefined) => (x == null ? ND : `${(x * 100).toFixed(1)}%`);
export const num = (x: number | null | undefined) => (x == null ? ND : String(x));
export const dataHora = (iso: string | null | undefined) =>
  iso ? new Date(iso).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' }) : '';

const ROTULOS: Record<string, string> = {
  // rematrícula (migração 24)
  recusada: 'Recusada', academico: 'Acadêmico',
  // bolsas e financiamento (migração 23)
  prouni: 'ProUni', fies: 'FIES', financiamento_privado: 'Financiamento privado', financiamento_proprio: 'Financiamento próprio', convenio_empresa: 'Convênio com empresa',
  bolsa_institucional: 'Bolsa institucional', solicitada: 'Solicitada', indeferida: 'Indeferida', inscricao: 'Inscrição', pre_selecao: 'Pré-seleção',
  contratado: 'Contratado', nao_contratado: 'Não contratado',
  novo: 'Novo', contato: 'Contato', inscrito: 'Inscrito', pre_matricula: 'Pré-matrícula', matricula_comercial: 'Matrícula comercial',
  confirmado: 'Ingresso efetivo', perdido: 'Perdido', cancelado: 'Cancelado',
  vestibular: 'Vestibular', enem: 'ENEM', transferencia: 'Transferência', segunda_graduacao: '2ª graduação / portador de diploma',
  reingresso: 'Reingresso', indicacao: 'Indicação', convenio: 'Convênio', visita_escolar: 'Visita escolar', evento: 'Evento', pos_graduacao: 'Pós-graduação',
  consentimento: 'Consentimento', procedimentos_preliminares_contrato: 'Procedimentos preliminares de contrato', legitimo_interesse: 'Legítimo interesse',
  documental: 'Documental', financeira: 'Financeira', academica: 'Acadêmica', valida: 'Válida', invalida: 'Inválida', isencao_formal: 'Isenção formal',
  primeiro_contato: 'Primeiro contato', follow_up: 'Follow-up', pendencia_validacao: 'Pendência de validação', recuperacao: 'Recuperação',
  gestor: 'Gestor', reitoria: 'Reitoria', coordenador: 'Coordenação', comercial: 'Comercial', secretaria: 'Secretaria', financeiro: 'Financeiro',
  pendente_aprovacao: 'Pendente de aprovação', aprovada: 'Aprovada', rejeitada: 'Rejeitada', aceita: 'Aceita', expirada: 'Expirada', substituida: 'Substituída',
  presencial: 'Presencial', semipresencial: 'Semipresencial', ead: 'EAD', noturno: 'Noturno', matutino: 'Matutino', vespertino: 'Vespertino', integral: 'Integral',
  agendamento: 'Agendamento', ligacao: 'Ligação', whatsapp_manual: 'WhatsApp (manual)', email_manual: 'E-mail (manual)', visita: 'Visita', reuniao: 'Reunião', anotacao: 'Anotação',
  preco: 'Preço', horario: 'Horário', distancia: 'Distância', documentacao: 'Documentação', concorrencia: 'Concorrência', credibilidade: 'Credibilidade', tempo: 'Tempo', familia: 'Família', outra: 'Outra',
  aberta: 'Aberta', superada: 'Superada', nao_superada: 'Não superada',
  ies: 'Instituição', campus: 'Campus',
  rascunho: 'Rascunho', em_aprovacao: 'Em aprovação', em_revisao: 'Em revisão', encerrado: 'Encerrado', pendente: 'Pendente', em_andamento: 'Em andamento', concluida: 'Concluída', cancelada: 'Cancelada',
  publicada: 'Publicada', arquivada: 'Arquivada', telefone: 'Telefone',
  recuperacao_base: 'Recuperação de base', oferta_educacional: 'Oferta educacional', webinar: 'Webinar', embaixadores: 'Embaixadores', prospeccao_autorizada: 'Prospecção autorizada',
  planejado: 'Planejado', em_execucao: 'Em execução', concluido: 'Concluído', selecionada: 'Selecionada', contatada: 'Contatada', reativada: 'Reativada', descartada: 'Descartada',
  a_fazer: 'A fazer', fazendo: 'Fazendo', feito: 'Feito', impedido: 'Impedido',
  comunicacao: 'Comunicação', escuta: 'Escuta', dominio_tecnico: 'Domínio técnico', negociacao_etica: 'Negociação ética', objecoes: 'Objeções', registro: 'Registro',
  disciplina_operacional: 'Disciplina operacional', roleplay: 'Roleplay', observacao_atendimento: 'Observação de atendimento', finalizada: 'Finalizada', aberto: 'Aberto',
  sdr: 'SDR', closer: 'Closer', farmer: 'Farmer', lideranca: 'Liderança', todos: 'Todos',
  d30: '30 dias', d90: '90 dias', rematricula: 'Rematrícula', ativo: 'Ativo', trancado: 'Trancado', evadido: 'Evadido', transferido: 'Transferido', inativo: 'Inativo',
  aluno: 'Aluno', embaixador: 'Embaixador', colaborador: 'Colaborador', parceiro: 'Parceiro',
  open_house: 'Open house', tour: 'Tour pelo campus', aula_experimental: 'Aula experimental', feira: 'Feira', prova_agendada: 'Prova agendada', analise_curricular: 'Análise curricular',
  presente: 'Presente', ausente: 'Ausente', inscrito_evento: 'Inscrito', aprovado: 'Aprovado', reprovado: 'Reprovado', pendente_resultado: 'Pendente',
  enviado: 'Enviado', recusado: 'Recusado', substituido: 'Substituído', simulada: 'Simulada', bloqueada: 'Bloqueada', copiada_manual: 'Copiada para envio manual',
  etapa_novo: 'Ao entrar em Novo', etapa_contato: 'Ao entrar em Contato', etapa_inscrito: 'Ao entrar em Inscrito', etapa_pre_matricula: 'Ao entrar em Pré-matrícula',
  documento_pendente: 'Documento pendente', evento_inscrito: 'Lembrete de evento', manual: 'Envio manual', sms: 'SMS',
  desligada: 'Desligada', pedido_registrado: 'Pedido registrado', cobranca: 'Cobrança', assinatura_certificada: 'Assinatura certificada', sistema_academico: 'Sistema acadêmico',
  marketplace_bolsas: 'Marketplaces de bolsas', acesso: 'Acesso aos dados', correcao: 'Correção', eliminacao: 'Eliminação', atendida: 'Atendida',
  planejada: 'Planejada', ativa: 'Ativa', encerrada: 'Encerrada',
  ingressantes: 'Ingressantes efetivos', oportunidades: 'Oportunidades', matriculas_comerciais: 'Matrículas comerciais', conversao: 'Conversão',
  cpl_centavos: 'Custo por lead', custo_ingressante_centavos: 'Custo por ingressante',
  meta_ads: 'Meta Ads', google_ads: 'Google Ads', tiktok_ads: 'TikTok Ads', whatsapp: 'WhatsApp', email: 'E-mail', site: 'Site', radio_tv: 'Rádio/TV', impresso: 'Impresso', outro: 'Outro',
  curso: 'Curso', turno: 'Turno', modalidade: 'Modalidade', forma_ingresso: 'Forma de ingresso', atendente: 'Atendente',
};
export const rotulo = (k: string | null | undefined) => (k == null ? '' : ROTULOS[k] ?? k);

// Converte "1.290,00" ou "1290" em centavos inteiros (sem ponto flutuante acumulado).
export function centavos(texto: string): number {
  const limpo = texto.trim().replace(/\./g, '').replace(',', '.');
  const v = Number(limpo);
  if (!Number.isFinite(v) || v <= 0) throw new Error(`Valor inválido: ${texto}`);
  return Math.round(v * 100);
}

// Linha de importação "nome;email;telefone;curso_id;forma;coorte;base_legal;origem[;campanha[;indicacao]]" -> objeto da RPC.
export function linhaImportacao(l: string): Record<string, unknown> {
  const [nome, email, telefone, curso, forma, coorte, base, origem, campanha, indicacao] = l.split(';').map((x) => x.trim());
  const o: Record<string, unknown> = { nome, curso_id: Number(curso), forma_ingresso: forma, coorte, base_legal: base, origem };
  if (email) o.email = email;
  if (telefone) o.telefone = telefone;
  if (campanha) o.campanha = campanha;
  if (indicacao) o.indicacao = indicacao;
  return o;
}

// CSV para planilhas em pt-BR (separador ";", BOM UTF-8). Neutraliza injeção de fórmula (=, +, -, @, tab, CR).
export function paraCsv(linhas: Record<string, unknown>[], colunas: [string, string][]): string {
  const celula = (v: unknown) => {
    let t = v == null ? '' : String(v);
    if (/^[=+\-@\t\r]/.test(t)) t = `'${t}`;
    return /[;"\n\r]/.test(t) ? `"${t.replace(/"/g, '""')}"` : t;
  };
  const cab = colunas.map(([, r]) => celula(r)).join(';');
  return '﻿' + [cab, ...linhas.map((l) => colunas.map(([k]) => celula(l[k])).join(';'))].join('\r\n');
}
