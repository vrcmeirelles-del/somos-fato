import { Activity, BellOff, Play } from 'lucide-react';
import { useState } from 'react';
import { useSessao } from '../components/Layout';
import { Aviso, Cartao, Chip, Estado, Mensagem, Titulo, Vazio } from '../components/ui';
import { api } from '../lib/api';
import { dataHora, rotulo } from '../lib/formato';
import { useAcao, useCarregar } from '../lib/hooks';

export function Intervencoes({ abrirDetalhe }: { abrirDetalhe: (id: number) => void }) {
  const { ies, tem } = useSessao();
  const fila = useCarregar(() => api.fila(ies!), [ies]);
  const acao = useAcao();
  const [resultados, setResultados] = useState<Record<number, string>>({});
  const tarefas = fila.dados?.tarefas ?? [];
  const atrasadas = tarefas.filter((t) => t.atrasada).length;

  return (
    <>
      <Titulo titulo="Fila de intervenções (MAIM)" subtitulo="Tarefas internas com SLA, distribuídas por escopo e capacidade."
        acao={tem('gestor') && (
          <button className="btn" disabled={acao.enviando} onClick={() => void acao.executar(async () => {
            const r = await api.cicloMaim(ies!); await fila.recarregar();
            return `Ciclo MAIM executado: ${r.follow_ups} follow-ups, ${r.pendencias_validacao} pendências de validação, ${r.suprimidos_optout} suprimidos por opt-out, ${r.limite_atingido} no limite, ${r.atrasadas} tarefas atrasadas.`;
          })}><Play className="h-4 w-4" aria-hidden />Executar ciclo MAIM</button>
        )} />
      <div className="mb-4 flex flex-wrap items-center gap-2">
        <Chip tipo="tec">{tarefas.length} tarefa(s) aberta(s)</Chip>
        <Chip tipo={atrasadas ? 'erro' : 'ok'}>{atrasadas} atrasada(s) no SLA</Chip>
        <Chip><BellOff className="h-3 w-3" aria-hidden />Envio externo desativado</Chip>
      </div>
      <Aviso>Comunicação externa (WhatsApp, e-mail) está desativada por política da plataforma. O contato é feito fora do sistema e registrado aqui; o registro revalida etapa e opt-out antes de concluir.</Aviso>
      <Mensagem m={acao.mensagem} />
      <Estado carregando={fila.carregando && !fila.dados} erro={fila.erro} />
      {fila.dados && !tarefas.length && <div className="mt-4"><Vazio texto="Nenhuma tarefa aberta" detalhe="Novas tarefas surgem com novas oportunidades, com o ciclo MAIM e com pendências de validação." /></div>}
      {tarefas.length > 0 && (
        <Cartao titulo="Tarefas abertas por vencimento" icone={Activity} className="mt-4 p-0">
          <div className="tabela rounded-none border-0 shadow-none">
            <table>
              <thead><tr>{['Vence', 'Tipo', 'Candidato', 'Etapa', 'Curso', 'Canal', 'Responsável', 'Registrar contato'].map((c) => <th key={c} scope="col">{c}</th>)}</tr></thead>
              <tbody>
                {tarefas.map((t) => (
                  <tr key={t.id}>
                    <td className={t.atrasada ? 'font-semibold text-erro' : ''}>{dataHora(t.vence_em)}{t.atrasada ? ' · atrasada' : ''}</td>
                    <td>{rotulo(t.tipo)}</td>
                    <td><button className="font-medium text-tec hover:underline" onClick={() => abrirDetalhe(t.oportunidade_id)}>{t.nome}</button></td>
                    <td>{rotulo(t.etapa)}</td><td>{t.curso}</td><td>{t.canal ?? '—'}</td>
                    <td>{t.responsavel ?? <span className="nd">sem responsável</span>}</td>
                    <td>
                      {t.tipo === 'pendencia_validacao' ? <span className="nota">Validar em Conversão e Matrículas</span> : (
                        <div className="flex flex-wrap items-center gap-1.5">
                          <input className="campo w-44" aria-label={`Resultado do contato da tarefa ${t.id}`} placeholder="Resultado do contato" maxLength={300}
                            value={resultados[t.id] ?? ''} onChange={(e) => setResultados({ ...resultados, [t.id]: e.target.value })} />
                          <button className="btn btn-peq" disabled={acao.enviando} onClick={() => void acao.executar(async () => {
                            const r = await api.concluirTarefa(t.id, resultados[t.id] ?? ''); await fila.recarregar();
                            return `Tarefa ${r.status}${r.motivo ? ' — ' + r.motivo : ''}.`;
                          })}>Registrar contato</button>
                        </div>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Cartao>
      )}
    </>
  );
}
