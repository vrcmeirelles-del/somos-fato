// Contrato da matrícula online: cláusulas em destaque (**texto**) e comprovante do aceite (HTML autocontido para guardar ou imprimir).
import { moeda } from './formato';
import type { ComprovanteAceite } from './tipos';

export interface Parte { texto: string; destaque: boolean }

// Divide o texto nos trechos marcados com **…**. Marcação aberta (ímpar) fica como texto comum.
export function partesContrato(texto: string): Parte[] {
  const pedacos = texto.split('**');
  if (pedacos.length % 2 === 0) return [{ texto, destaque: false }];
  return pedacos.map((t, i) => ({ texto: t, destaque: i % 2 === 1 })).filter((p) => p.texto.length > 0);
}

export function contarDestaques(texto: string): { total: number; balanceado: boolean } {
  const marcas = texto.split('**').length - 1;
  return { total: Math.floor(marcas / 2), balanceado: marcas % 2 === 0 };
}

const esc = (s: unknown) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);
const data = (s: string | null | undefined) => (s ? new Date(s).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo' }) + ' (horário de Brasília)' : '—');
const cpf = (s: unknown) => { const d = String(s ?? ''); return d.length === 11 ? `${d.slice(0, 3)}.${d.slice(3, 6)}.${d.slice(6, 9)}-${d.slice(9)}` : esc(d) || '—'; };
const VINCULO: Record<string, string> = { mae: 'mãe', pai: 'pai', tutor: 'tutor(a) legal' };

export function comprovanteHtml(c: ComprovanteAceite): string {
  const ev = (c.evidencia ?? {}) as Record<string, Record<string, unknown> | null | string>;
  const cand = (ev.candidato ?? {}) as Record<string, unknown>;
  const rep = ev.representante_legal as Record<string, unknown> | null | undefined;
  const cond = (ev.condicoes ?? {}) as Record<string, unknown>;
  const conf = (ev.confirmacao ?? {}) as Record<string, unknown>;
  const contrato = partesContrato(c.contrato_texto).map((p) => (p.destaque ? `<strong class="d">${esc(p.texto)}</strong>` : esc(p.texto))).join('');
  const integridade = c.evidencia_integra === null ? 'Aceite registrado antes do procedimento reforçado: sem evidência consolidada.'
    : c.evidencia_integra && c.contrato_integro ? 'Íntegra: os hashes recalculados no banco conferem com os registrados no aceite.'
      : 'ATENÇÃO: os hashes recalculados NÃO conferem com os registrados. Procure a instituição.';
  return `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Comprovante de aceite da matrícula</title>
<style>body{font:16px/1.5 system-ui,sans-serif;max-width:820px;margin:24px auto;padding:0 16px;color:#13233a}h1{font-size:22px}h2{font-size:17px;margin-top:24px;border-bottom:1px solid #ccd}
table{border-collapse:collapse;width:100%}td{border:1px solid #dde;padding:6px;vertical-align:top}td:first-child{width:38%;color:#445}
.contrato{white-space:pre-wrap;font-size:16px;border:1px solid #dde;padding:12px}.d{background:#fff3c4;font-weight:700}
code{word-break:break-all}pre{white-space:pre-wrap;word-break:break-all;font-size:12px;background:#f4f5f8;padding:8px}.alerta{padding:8px;background:#fff3c4}</style></head><body>
<h1>Comprovante de aceite da matrícula</h1>
<p>${esc(c.instituicao)} · ${esc(c.curso)} · ingresso ${esc(c.coorte)}</p>
${c.desistencia_em ? `<p class="alerta"><strong>Desistência registrada em ${data(c.desistencia_em)}</strong> — motivo: ${esc(c.desistencia_motivo)}. A matrícula foi cancelada.</p>` : ''}
<h2>Aceite</h2><table>
<tr><td>Aceito em</td><td>${data(c.aceito_em)}</td></tr>
<tr><td>Candidato</td><td>${esc(cand.nome ?? c.nome_confirmado)}${cand.cpf ? ` · CPF ${cpf(cand.cpf)}` : ''}${cand.nascimento ? ` · nascimento ${esc(new Date(`${cand.nascimento}T12:00:00`).toLocaleDateString('pt-BR'))}` : ''}</td></tr>
${rep ? `<tr><td>Representante legal</td><td>${esc(rep.nome)} · CPF ${cpf(rep.cpf)} · ${esc(VINCULO[String(rep.vinculo)] ?? rep.vinculo)} · declarou representar ou assistir o candidato</td></tr>` : ''}
<tr><td>Condições aceitas</td><td>${cond.mensalidade_centavos != null ? `mensalidade ${moeda(Number(cond.mensalidade_centavos))}, desconto ${esc(cond.desconto_pct)}%, valor final <strong>${moeda(Number(cond.valor_final_centavos))}/mês</strong> (proposta nº ${esc(cond.proposta_id)})` : '—'}</td></tr>
<tr><td>Declarações</td><td>${ev.declaracoes ? 'Li o contrato · Concordo com as condições da proposta · Estou ciente do prazo de 7 dias para desistir' : 'Li o contrato e concordo com a proposta (procedimento anterior)'}</td></tr>
<tr><td>Confirmação</td><td>${conf.canal ? `código enviado por ${esc(conf.canal === 'email' ? 'e-mail' : 'SMS')} para ${esc(conf.destino)}${conf.modo === 'simulacao' ? ' — <strong>modo simulação</strong> (envio desligado; código exibido no portal)' : ''}` : 'nome completo digitado'}</td></tr>
<tr><td>Prazo para desistir pelo portal</td><td>até ${data(c.arrependimento_ate)}</td></tr>
</table>
<h2>Integridade</h2><table>
<tr><td>Situação</td><td>${esc(integridade)}</td></tr>
<tr><td>Contrato (versão ${esc(c.contrato_versao)}) — SHA-256</td><td><code>${esc(c.contrato_hash)}</code></td></tr>
<tr><td>Evidência consolidada — SHA-256</td><td><code>${esc(c.evidencia_hash ?? '—')}</code></td></tr>
</table>
${c.evidencia_texto ? `<p>O SHA-256 do texto abaixo, exatamente como está (UTF-8, sem quebra de linha final), é o hash da evidência.</p><pre>${esc(c.evidencia_texto)}</pre>` : ''}
<h2>Contrato aceito (versão ${esc(c.contrato_versao)})</h2>
<div class="contrato">${contrato}</div>
<p style="font-size:13px;color:#556">Gerado pelo Matrícula 360° em ${data(new Date().toISOString())}. Ambiente de homologação com dados sintéticos.</p>
</body></html>`;
}

export function baixarTexto(nome: string, mime: string, conteudo: string): void {
  const url = URL.createObjectURL(new Blob([conteudo], { type: `${mime};charset=utf-8` }));
  const a = document.createElement('a'); a.href = url; a.download = nome; a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export const nomeComprovante = (c: ComprovanteAceite) => `comprovante-matricula-${(c.evidencia_hash ?? c.contrato_hash).slice(0, 12)}.html`;
