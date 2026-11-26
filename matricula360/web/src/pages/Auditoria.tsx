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
    case 'exportacao.gerar': return `Exportação de ${s('linhas')} oportunidade(s)${s('coorte') ? ` da coorte ${s('coorte')}` : ''}${d.contato_completo ? ', com contato' : ', com contato mascarado'}.`;
    case 'escopo.conceder': if (s('abrangencia') === 'campus') return `Escopo de ${rotulo(s('papel')).toLowerCase()} concedido no campus #${s('campus_id')}.`; return `Escopo de ${rotulo(s('papel')).toLowerCase()} concedido${s('curso_id') ? ` no curso #${s('curso_id')}` : ''}.`;
    case 'escopo.revogar': return `Escopo #${e.entidade_id} revogado.`;
    case 'usuario.convidar': return 'Perfil de usuário criado.';
    case 'interacao.registrar': return `Interação registrada (${rotulo(s('tipo')).toLowerCase()}).`;
    case 'objecao.registrar': return `Objeção registrada: ${rotulo(s('categoria')).toLowerCase()}.`;
    case 'objecao.tratar': return `Objeção #${s('objecao_id')} marcada como ${rotulo(s('status')).toLowerCase()}.`;
    case 'agenda.criar': return `Agendamento criado para ${s('quando') ? new Date(s('quando')).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' }) : '—'}.`;
    case 'oportunidade.reatribuir': return `Responsável alterado — motivo: ${s('motivo')} (${s('tarefas')} tarefa(s) transferida(s)).`;
    // Planejamento, campanhas e concorrência (migração 12)
    case 'plano.criar': return `Plano estratégico criado para a coorte ${s('coorte')}.`;
    case 'plano.editar': return `Plano estratégico editado (versão ${s('versao')}).`;
    case 'plano.submeter': return 'Plano submetido para aprovação.';
    case 'plano.aprovar': return 'Plano aprovado.';
    case 'plano.devolver': return `Plano devolvido para revisão — ${s('justificativa')}.`;
    case 'plano.revisar': return `Plano reaberto para revisão — ${s('justificativa')}.`;
    case 'plano.encerrar': return `Plano encerrado — ${s('justificativa')}.`;
    case 'objetivo.salvar': return `Objetivo do plano salvo (${rotulo(s('indicador')).toLowerCase()}).`;
    case 'acao.salvar': return `Ação 5W2H salva${s('status') ? ` (${rotulo(s('status')).toLowerCase()})` : ''}.`;
    case 'concorrencia.registrar': return 'Oferta concorrente registrada com fonte.';
    case 'concorrencia.revisar': return 'Registro de concorrência revisado.';
    case 'campanha.criar': return `Campanha criada (código ${s('codigo')}, canal ${rotulo(s('canal'))}).`;
    case 'campanha.editar': return `Campanha editada${s('status') ? ` (${rotulo(s('status')).toLowerCase()})` : ''}.`;
    case 'custo.lancar': return `Custo de campanha lançado (${(Number(s('valor_centavos')) / 100).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })}).`;
    case 'custo.estornar': return `Custo estornado — ${s('motivo')}.`;
    // Funis (migração 13)
    case 'funil.criar': return 'Funil comercial criado.';
    case 'funil.editar': return 'Funil comercial editado.';
    case 'funil.nova_versao': return `Nova versão ${s('versao')} do funil criada em rascunho.`;
    case 'funil.salvar_versao': return `Rascunho da versão ${s('versao')} do funil salvo.`;
    case 'funil.publicar': return `Versão ${s('versao')} do funil publicada${s('arquivada') ? `; versão ${s('arquivada')} arquivada` : ''}.`;
    case 'oportunidade.subetapa': return `Subetapa alterada: ${s('de')} → ${s('para')}.`;
    // Recuperação e sprints (migração 15)
    case 'protocolo.criar': return `Protocolo de ${rotulo(s('tipo')).toLowerCase()} criado.`;
    case 'protocolo.editar': return `Protocolo atualizado${s('status') ? ` (${rotulo(s('status')).toLowerCase()})` : ''}.`;
    case 'recuperacao.selecionar': return `${s('selecionadas')} oportunidade(s) incluída(s) no protocolo; ${s('recusadas')} recusada(s) pela elegibilidade.`;
    case 'recuperacao.contatada': return 'Contato de recuperação registrado.';
    case 'recuperacao.reativar': return 'Oportunidade reativada pelo protocolo de recuperação.';
    case 'recuperacao.descartada': return 'Item de recuperação descartado.';
    case 'sprint.criar': return 'Sprint de aceleração criada.';
    case 'sprint.editar': return `Sprint atualizada${s('status') ? ` (${rotulo(s('status')).toLowerCase()})` : ''}.`;
    case 'sprint.item': return 'Entrega da sprint atualizada.';
    // Academia (migração 16)
    case 'academia.modulo': return 'Módulo da trilha concluído.';
    case 'academia.conteudo': return 'Conteúdo de módulo editado.';
    case 'academia.cenario': return 'Cenário sintético de roleplay criado.';
    case 'rubrica.nova_versao': return 'Nova versão de rubrica criada em rascunho.';
    case 'rubrica.salvar': return 'Rascunho de rubrica salvo.';
    case 'rubrica.publicar': return 'Rubrica publicada.';
    case 'avaliacao.salvar': return 'Avaliação em rascunho salva.';
    case 'avaliacao.finalizar': return `Avaliação (${rotulo(s('tipo')).toLowerCase()}) finalizada.`;
    case 'pdi.salvar': return `PDI salvo${s('status') ? ` (${rotulo(s('status')).toLowerCase()})` : ''}.`;
    // Relacionamento (migração 17)
    case 'vinculo.registrar': return `Vínculo ${rotulo(s('marco')).toLowerCase()} registrado como ${rotulo(s('situacao')).toLowerCase()}${s('anterior') ? ` (antes: ${rotulo(s('anterior')).toLowerCase()})` : ''}.`;
    case 'onboarding.item': return `Onboarding: "${s('item')}" ${d.concluido ? 'concluído' : 'desmarcado'}.`;
    case 'relacionamento.configurar': return 'Modelo de onboarding ou regras de embaixadores atualizados.';
    case 'embaixador.salvar': return `Embaixador(a) ${rotulo(s('status')).toLowerCase()}.`;
    case 'indicacao.criar': return 'Código de indicação criado.';
    // Captação pública, portal e titulares (migração 18)
    case 'formulario.salvar': return 'Formulário público de captação salvo.';
    case 'formulario.evento': return 'Formulário vinculado a evento.';
    case 'portal.gerar_acesso': return `Link do portal gerado para envio manual (válido por ${s('validade_dias')} dias).`;
    case 'titular.solicitar': return `Titular solicitou ${rotulo(s('tipo')).toLowerCase()} pelo portal.`;
    case 'titular.tratar': return `Solicitação de ${rotulo(s('tipo')).toLowerCase()} ${rotulo(s('status')).toLowerCase()}.`;
    // Documentos (migração 19)
    case 'documento.enviar': return `Documento enviado pelo ${s('origem') === 'candidato' ? 'candidato' : 'atendimento'} (${s('tipo')}).`;
    case 'documento.baixar': return `Documento baixado (${s('tipo')}).`;
    case 'documento.revisar': return `Documento ${s('tipo')} ${rotulo(s('status')).toLowerCase()}.`;
    case 'documentos.configurar': return 'Checklist ou exigência de documentos atualizado.';
    // Eventos e processo seletivo (migração 20)
    case 'evento.salvar': return 'Evento salvo.';
    case 'evento.inscrever': return 'Oportunidade inscrita em evento.';
    case 'evento.checkin': return `Presença em evento registrada: ${rotulo(s('status')).toLowerCase()}.`;
    case 'seletivo.salvar': return 'Processo seletivo salvo.';
    case 'seletivo.candidatar': return `Inscrição no processo ${s('processo')} (${s('origem')}).`;
    case 'seletivo.redacao': return 'Redação enviada pelo candidato.';
    case 'seletivo.avaliar': return 'Candidatura avaliada (conferência, correção ou decisão).';
    case 'seletivo.divulgar': return `Resultado do processo seletivo divulgado (${s('aprovados')} aprovado(s) de ${s('total')}).`;
    // Matrícula online, comunicação e integrações (migração 21)
    case 'contrato.publicar': return `Contrato de matrícula versão ${s('versao')} publicado.`;
    case 'matricula.aceite': return `Matrícula aceita no portal (contrato versão ${s('contrato_versao')})${d.menor_de_18 ? ' com representante legal' : ''}${d.confirmacao === 'simulacao' ? '; código em modo simulação' : ''}.`;
    // Pesquisas (migração 28)
    case 'pesquisa.salvar': return d.status ? `Pesquisa ${s('status') === 'ativa' ? 'ativada' : 'encerrada'}.` : `Pesquisa ${d.novo ? 'criada' : 'editada'}${s('nome') ? `: ${s('nome')}` : ''}.`;
    // Captação em campo (migração 27)
    case 'campo.escola': return `Escola ${d.novo ? 'cadastrada' : 'atualizada'}${s('nome') ? `: ${s('nome')}` : ''}.`;
    case 'campo.visita': return `Visita ${d.novo ? 'agendada' : 'atualizada'}${s('titulo') ? `: ${s('titulo')}` : ''}${s('status') ? ` (${rotulo(s('status')).toLowerCase()})` : ''}.`;
    case 'campo.sincronizar': return `Modo feira sincronizado: ${s('recebidos')} cadastro(s), ${s('contatos_existentes')} contato(s) já existente(s), ${s('rejeitados')} rejeitado(s).`;
    case 'campo.qr': return `Inscrição pelo QR code vinculada à visita (${s('vinculadas')}).`;
    // Verificação em duas etapas (migração 26)
    case 'seguranca.2fa': return d.exigir ? `Verificação em duas etapas passou a ser exigida da equipe (${s('usuarios_sem_fator')} sem aplicativo no momento).` : 'Exigência de verificação em duas etapas desligada.';
    // Sucesso do aluno (migração 25)
    case 'caso.abrir': return `Caso do aluno aberto: ${rotulo(s('motivo')).toLowerCase()}${s('origem') === 'rematricula' ? ' (automático, recusa de rematrícula)' : ''}${d.roteado ? '' : '; sem responsável disponível'}.`;
    case 'caso.atender': return `Caso do aluno: ${({ assumir: 'assumido', nota: 'nota registrada', passo: 'passo da trilha concluído', agendar: 'atendimento agendado', encaminhar: 'encaminhado', resolver: 'resolvido', cancelar: 'cancelado' } as Record<string, string>)[s('acao')] ?? s('acao')}.`;
    case 'caso.trilha': return `Trilha de intervenção "${rotulo(s('motivo'))}" atualizada.`;
    // Rematrícula (migração 24)
    case 'rematricula.campanha': return `Campanha de rematrícula ${s('periodo')} ${d.novo ? 'criada' : 'atualizada'}.`;
    case 'rematricula.status': return `Campanha de rematrícula ${s('periodo')} ${s('status') === 'aberta' ? `aberta (${s('novos_elegiveis')} novo(s) elegível(is))` : 'encerrada'}.`;
    case 'rematricula.tratar': return `Rematrícula ${s('periodo')}: ${({ bloquear: `bloqueada (${rotulo(s('categoria')).toLowerCase()})`, desbloquear: 'desbloqueada', aceita: 'aceite presencial registrado', recusada: 'recusa presencial registrada' } as Record<string, string>)[s('acao')] ?? s('acao')}.`;
    case 'rematricula.resposta': return `Rematrícula ${s('periodo')} ${s('resposta') === 'aceita' ? 'aceita' : 'recusada'} pelo aluno no portal.`;
    // Bolsas e financiamento (migração 23)
    case 'bolsa.programa': return `Programa de bolsa ${d.novo ? 'criado' : 'atualizado'}${s('nome') ? `: ${s('nome')}` : ''}.`;
    case 'bolsa.solicitar': return `Bolsa solicitada (${s('programa')}, ${s('percentual')}%) ${s('origem') === 'portal' ? 'pelo candidato no portal' : 'pela equipe'}.`;
    case 'bolsa.decidir': return `Bolsa ${s('status') === 'aprovada' ? 'aprovada' : 'indeferida'}: ${s('programa')} (${s('percentual')}%).`;
    case 'bolsa.etapa': return `Etapa externa de ${s('programa')}: ${rotulo(s('etapa')).toLowerCase()}.`;
    case 'bolsa.cancelar': return `Benefício cancelado (motivo: ${s('motivo')}).`;
    // Aceite reforçado (migração 22)
    case 'matricula.codigo': return `Código de confirmação da matrícula gerado (${rotulo(s('canal'))}${s('modo') === 'simulacao' ? ', modo simulação' : ''}).`;
    case 'matricula.comprovante_ver': return 'Comprovante do aceite consultado pela equipe.';
    case 'matricula.arrependimento': return `Desistência no prazo de arrependimento, pelo portal (motivo: ${s('motivo')}).`;
    case 'comunicacao.modelo': return 'Modelo de mensagem salvo.';
    case 'comunicacao.regua': return `Régua executada em simulação: ${s('simuladas')} simulada(s), ${s('bloqueadas')} bloqueada(s).`;
    case 'integracao.pedido': return `Pedido de ativação registrado: ${rotulo(s('tipo'))}.`;
    case 'importacao.custos': return `Importação de custos: ${s('importadas')} importado(s), ${s('rejeitadas')} rejeitado(s).`;
    case 'importacao.vinculos': return `Importação de vínculos: ${s('importadas')} importado(s), ${s('rejeitadas')} rejeitado(s).`;
    case 'manutencao.limpeza_testes': return `Limpeza dos dados de teste: ${s('oportunidades_apagadas')} oportunidade(s) e ${s('pessoas_apagadas')} pessoa(s) de teste removidas; ${s('propostas_de_teste_em_leads_da_semente')} proposta(s) e ${s('validacoes_de_teste_em_leads_da_semente')} validação(ões) de teste retiradas de leads da semente.`;
    case 'usuario.revogar': return 'Usuário revogado em todas as instituições.';
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
