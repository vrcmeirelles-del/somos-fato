import { ScrollText } from 'lucide-react';
import { useState } from 'react';
import { useSessao } from '../components/Layout';
import { Cartao, Estado, Titulo } from '../components/ui';
import { api } from '../lib/api';
import { dataHora, rotulo } from '../lib/formato';
import { useCarregar } from '../lib/hooks';
import type { EventoAuditoria } from '../lib/tipos';

// Tradução dos eventos técnicos para linguagem institucional. O registro técnico continua visível.
export function descreverEvento(e: Pick<EventoAuditoria, 'acao' | 'dados' | 'entidade' | 'entidade_id'>): string {
  const d = e.dados as Record<string, unknown>;
  const s = (k: string) => (d[k] == null ? '' : String(d[k]));
  switch (e.acao) {
    case 'oportunidade.criar': return `Oportunidade #${e.entidade_id} criada (${rotulo(s('forma_ingresso'))}, coorte ${s('coorte')}, origem: ${s('origem')}).`;
    case 'oportunidade.etapa': return `Oportunidade #${e.entidade_id} movida de ${rotulo(s('de'))} para ${rotulo(s('para'))}${s('motivo') ? ` — motivo: ${s('motivo')}` : ''}.`;
    case 'oportunidade.validar': return `Validação ${rotulo(s('dimensao')).toLowerCase()} registrada como ${rotulo(s('resultado')).toLowerCase()} na oportunidade #${e.entidade_id}.`;
    case 'oportunidade.confirmar': return `Ingresso efetivo confirmado na oportunidade #${e.entidade_id}.`;
    case 'oportunidade.cancelar': return `Matrícula da oportunidade #${e.entidade_id} cancelada — motivo: ${s('motivo')}.`;
    case 'proposta.criar': return `Proposta #${s('proposta_id')} emitida com ${s('desconto_pct')}% de desconto (limite ${s('limite_pct')}%): ${rotulo(s('status')).toLowerCase()}.`;
    case 'proposta.decidir': return `Proposta #${s('proposta_id')} ${rotulo(s('status')).toLowerCase()} pelo gestor.`;
    case 'proposta.aceitar': return `Aceite registrado na proposta #${s('proposta_id')}.`;
    case 'proposta.substituir': return `Proposta #${s('proposta_id')} substituída (${s('motivo')}).`;
    case 'proposta.expirar': return `Proposta #${s('proposta_id')} expirou.`;
    case 'pessoa.optout': return `Opt-out do canal ${s('canal')} registrado; ${s('tarefas_suprimidas')} tarefa(s) suprimida(s).`;
    case 'pessoa.anonimizar': return `Titular da oportunidade #${e.entidade_id} anonimizado (LGPD).`;
    case 'tarefa.concluida': return `Contato registrado (tarefa #${s('tarefa_id')}, ${rotulo(s('tipo')).toLowerCase()}).`;
    case 'tarefa.suprimida': return `Tarefa #${s('tarefa_id')} suprimida na revalidação (opt-out).`;
    case 'tarefa.cancelada': return `Tarefa #${s('tarefa_id')} cancelada na revalidação (etapa encerrada).`;
    case 'tarefa.encerrar_incompativel': return `${s('tarefas')} tarefa(s) encerrada(s) automaticamente por incompatibilidade com a etapa ${rotulo(s('etapa'))}.`;
    case 'envio_externo.bloqueado': return `Tentativa de envio externo bloqueada (envio desativado) na tarefa #${s('tarefa_id')}.`;
    case 'maim.ciclo': return `Ciclo MAIM: ${s('follow_ups')} follow-ups, ${s('pendencias_validacao')} pendências, ${s('suprimidos_optout')} supressões.`;
    case 'meta.definir': return `Meta do curso #${e.entidade_id} na coorte ${s('coorte')} definida em ${s('meta')}.`;
    case 'ies.configurar': return 'Parâmetros do MAIM/SLA da instituição alterados.';
    case 'ies.provisionar': return `Instituição provisionada (plano ${s('plano')}).`;
    case 'ies.status': return `Status da instituição alterado para ${s('status')}.`;
    case 'escopo.conceder': return `Escopo de ${rotulo(s('papel')).toLowerCase()} concedido${s('curso_id') ? ` no curso #${s('curso_id')}` : ''}.`;
    case 'escopo.revogar': return `Escopo #${e.entidade_id} revogado.`;
    case 'usuario.convidar': return 'Perfil de usuário criado.';
    default: return `${e.acao} (${e.entidade} ${e.entidade_id ?? ''})`;
  }
}

export function Auditoria() {
  const { ies } = useSessao();
  const [pagina, setPagina] = useState(1);
  const aud = useCarregar(() => api.auditoria(ies!, pagina), [ies, pagina]);
  const total = aud.dados?.total ?? 0;
  return (
    <>
      <Titulo titulo="Auditoria" subtitulo="Registro imutável. Cada evento aparece em linguagem institucional, com o registro técnico preservado." />
      <Estado carregando={aud.carregando && !aud.dados} erro={aud.erro} />
      {aud.dados && (
        <Cartao titulo={`Eventos (${total})`} icone={ScrollText}>
          <ul className="divide-y divide-linha">
            {aud.dados.itens.map((x) => (
              <li key={x.id} className="py-2.5 text-sm">
                <p><span className="text-suave">{dataHora(x.em)} · {x.por ?? 'sistema'} —</span> {descreverEvento(x)}</p>
                <details className="mt-1"><summary className="cursor-pointer text-xs text-suave">Registro técnico</summary>
                  <code className="mt-1 block break-all rounded bg-fundo p-2 text-[11px]">{x.acao} · {x.entidade} {x.entidade_id ?? ''} · {JSON.stringify(x.dados)}</code></details>
              </li>
            ))}
          </ul>
          <div className="mt-3 flex items-center justify-between text-xs text-suave">
            <span>Página {pagina} de {Math.max(1, Math.ceil(total / 50))}</span>
            <div className="flex gap-2">
              <button className="btn btn-sec btn-peq" disabled={pagina === 1} onClick={() => setPagina(pagina - 1)}>Anterior</button>
              <button className="btn btn-sec btn-peq" disabled={pagina * 50 >= total} onClick={() => setPagina(pagina + 1)}>Próxima</button>
            </div>
          </div>
        </Cartao>
      )}
    </>
  );
}
