// Formatação e rótulos. Regra central: indisponível (null) nunca vira zero.
export const ND = 'N/D';

export const moeda = (centavos: number) => (centavos / 100).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
export const pct = (x: number | null | undefined) => (x == null ? ND : `${(x * 100).toFixed(1)}%`);
export const num = (x: number | null | undefined) => (x == null ? ND : String(x));
export const dataHora = (iso: string | null | undefined) =>
  iso ? new Date(iso).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' }) : '';

const ROTULOS: Record<string, string> = {
  novo: 'Novo', contato: 'Contato', inscrito: 'Inscrito', pre_matricula: 'Pré-matrícula', matricula_comercial: 'Matrícula comercial',
  confirmado: 'Ingresso efetivo', perdido: 'Perdido', cancelado: 'Cancelado',
  vestibular: 'Vestibular', enem: 'ENEM', transferencia: 'Transferência', segunda_graduacao: '2ª graduação / portador de diploma',
  reingresso: 'Reingresso', indicacao: 'Indicação', convenio: 'Convênio', visita_escolar: 'Visita escolar', evento: 'Evento', pos_graduacao: 'Pós-graduação',
  consentimento: 'Consentimento', procedimentos_preliminares_contrato: 'Procedimentos preliminares de contrato', legitimo_interesse: 'Legítimo interesse',
  documental: 'Documental', financeira: 'Financeira', academica: 'Acadêmica', valida: 'Válida', invalida: 'Inválida', isencao_formal: 'Isenção formal',
  primeiro_contato: 'Primeiro contato', follow_up: 'Follow-up', pendencia_validacao: 'Pendência de validação', recuperacao: 'Recuperação',
  gestor: 'Gestor', reitoria: 'Reitoria', coordenador: 'Coordenação', comercial: 'Comercial', secretaria: 'Secretaria', financeiro: 'Financeiro',
  pendente_aprovacao: 'Pendente de aprovação', aprovada: 'Aprovada', rejeitada: 'Rejeitada', aceita: 'Aceita', expirada: 'Expirada',
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

// Linha de importação "nome;email;telefone;curso_id;forma;coorte;base_legal;origem" -> objeto da RPC.
export function linhaImportacao(l: string): Record<string, unknown> {
  const [nome, email, telefone, curso, forma, coorte, base, origem] = l.split(';').map((x) => x.trim());
  const o: Record<string, unknown> = { nome, curso_id: Number(curso), forma_ingresso: forma, coorte, base_legal: base, origem };
  if (email) o.email = email;
  if (telefone) o.telefone = telefone;
  return o;
}
