// Matrícula 360° — motor de regras puras (sem I/O).
// Reconstruído na v0.2 a partir do contrato usado pela demo v0.1
// (stages, transitions, move, conversion, forecast). O original não veio no pacote.
// IMPORTANTE: este motor é usado pelo servidor para validar regras. O navegador
// pode importá-lo para simulações, mas nunca para autorização.

export const stages = ['novo', 'contato', 'inscrito', 'pre_matricula', 'matricula_comercial', 'confirmado'];
export const terminais = ['perdido', 'cancelado'];
export const todasEtapas = [...stages, ...terminais];

// "confirmado" (ingresso efetivo) NÃO é alcançável por transição comum:
// exige confirmação com as três validações (documental, financeira, acadêmica).
// "cancelado" só por operação de cancelamento. "perdido" -> "contato" é recuperação.
export const transitions = {
  novo: ['contato', 'perdido'],
  contato: ['inscrito', 'perdido'],
  inscrito: ['pre_matricula', 'perdido'],
  pre_matricula: ['matricula_comercial', 'perdido'],
  matricula_comercial: [],
  confirmado: [],
  perdido: ['contato'],
  cancelado: [],
};

export const DIMENSOES = ['documental', 'financeira', 'academica'];

export const FORMAS_INGRESSO = [
  'vestibular', 'enem', 'transferencia',
  // "portador de diploma" e "segunda graduação" tratados como uma só categoria
  // para evitar dupla contagem no BI (Bíblia-Mestra, Funis).
  'segunda_graduacao',
  'reingresso', 'indicacao', 'convenio', 'visita_escolar', 'evento', 'pos_graduacao',
];

export const BASES_LEGAIS = ['consentimento', 'procedimentos_preliminares_contrato', 'legitimo_interesse'];
export const CANAIS = ['email', 'whatsapp', 'telefone'];

export class RegraViolada extends Error {
  constructor(msg) { super(msg); this.name = 'RegraViolada'; }
}

export function podeTransitar(de, para) {
  return Array.isArray(transitions[de]) && transitions[de].includes(para);
}

export function move(lead, next) {
  if (next === 'confirmado') return confirm(lead);
  if (!podeTransitar(lead.stage, next)) {
    throw new RegraViolada(`Transição inválida: ${lead.stage} → ${next}`);
  }
  return { ...lead, stage: next };
}

export function faltantes(lead) {
  return DIMENSOES.filter((d) => lead[d] !== true);
}

export function confirm(lead) {
  if (lead.stage !== 'matricula_comercial') {
    throw new RegraViolada('Confirmação exige matrícula comercial registrada');
  }
  const f = faltantes(lead);
  if (f.length) throw new RegraViolada(`Confirmação incompleta: falta validação ${f.join(', ')}`);
  return { ...lead, stage: 'confirmado' };
}

// Taxa com denominador explícito. Denominador zero => null (indisponível), nunca 0.
export function taxa(numerador, denominador) {
  if (!Number.isFinite(numerador) || !Number.isFinite(denominador) || numerador < 0 || denominador < 0) {
    throw new RegraViolada('Taxa com valores inválidos');
  }
  if (denominador === 0) return null;
  return numerador / denominador;
}

export function conversion(leads) {
  return taxa(leads.filter((l) => l.stage === 'confirmado').length, leads.length);
}

export function forecast(meta, rates) {
  if (!Number.isInteger(meta) || meta < 0) throw new RegraViolada('Meta deve ser inteiro não negativo');
  if (!Array.isArray(rates) || !rates.length || rates.some((r) => !(r > 0 && r <= 1))) {
    throw new RegraViolada('Taxas devem estar entre 0 (exclusivo) e 1');
  }
  const p = rates.reduce((a, r) => a * r, 1);
  return Math.max(0, Math.ceil(meta / p - 1e-9)) + 0;
}

// Proposta comercial. Valores em centavos (inteiros) para evitar erro de ponto flutuante.
export function calcularProposta({ mensalidadeCentavos, descontoPct, descontoMaxPct }) {
  if (!Number.isInteger(mensalidadeCentavos) || mensalidadeCentavos <= 0) {
    throw new RegraViolada('Mensalidade inválida');
  }
  if (typeof descontoPct !== 'number' || !Number.isFinite(descontoPct) || descontoPct < 0 || descontoPct > 100) {
    throw new RegraViolada('Desconto deve estar entre 0 e 100');
  }
  if (Math.round(descontoPct * 100) !== descontoPct * 100) {
    throw new RegraViolada('Desconto aceita no máximo duas casas decimais');
  }
  const valorFinalCentavos = Math.round(mensalidadeCentavos * (1 - descontoPct / 100));
  return {
    mensalidadeCentavos,
    descontoPct,
    valorFinalCentavos,
    descontoCentavos: mensalidadeCentavos - valorFinalCentavos,
    exigeAprovacao: descontoPct > descontoMaxPct,
  };
}

export function normalizarEmail(email) {
  if (email == null || email === '') return null;
  const e = String(email).trim().toLowerCase();
  if (e.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e)) throw new RegraViolada('E-mail inválido');
  return e;
}

export function normalizarTelefone(tel) {
  if (tel == null || tel === '') return null;
  const d = String(tel).replace(/\D/g, '');
  if (d.length < 10 || d.length > 13) throw new RegraViolada('Telefone inválido');
  return d;
}

export function mascararEmail(e) {
  if (!e) return null;
  const [u, d] = e.split('@');
  return `${u[0]}***@${d}`;
}

export function mascararTelefone(t) {
  if (!t) return null;
  return `***${t.slice(-4)}`;
}
