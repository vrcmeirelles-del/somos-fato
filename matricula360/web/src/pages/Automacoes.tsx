import { Bot, Play } from 'lucide-react';
import { useState } from 'react';
import { useSessao } from '../components/Layout';
import { Aviso, Campo, Cartao, Chip, Estado, Mensagem, Titulo, Vazio } from '../components/ui';
import { api } from '../lib/api';
import { dataHora } from '../lib/formato';
import { useAcao, useCarregar } from '../lib/hooks';
import type { ErroApi } from '../lib/supabase';

export const REGRAS: Record<string, { nome: string; descricao: string; parametro?: { chave: string; rotulo: string } ; sensivel?: boolean }> = {
  ciclo_maim: { nome: 'Cadência comercial (MAIM)', descricao: 'Cria follow-ups para leads parados, respeitando o opt-out e o limite de tentativas; cria pendências de validação; redistribui tarefas sem dono.' },
  regua: { nome: 'Régua de comunicação', descricao: 'Gera as mensagens dos modelos ativos por etapa, documento pendente e evento. Modo simulação: nada é enviado até a integração ser contratada.' },
  expirar_propostas: { nome: 'Expirar propostas vencidas', descricao: 'Propostas aprovadas ou pendentes com validade vencida passam a expiradas.' },
  rematricula: { nome: 'Rematrícula', descricao: 'Inclui novos elegíveis nas campanhas abertas e encerra campanhas que passaram do prazo.' },
  escalonar_casos: { nome: 'Escalonar casos do aluno', descricao: 'Roteia casos sem responsável e eleva a prioridade de casos vencidos.', parametro: { chave: 'horas_vencido', rotulo: 'Horas de atraso para escalonar' } },
  casos_financeiros: { nome: 'Casos financeiros', descricao: 'Abre caso de apoio para aluno com pendência aberta vencida (oferecer negociação, bolsa ou financiamento).', parametro: { chave: 'dias_atraso', rotulo: 'Dias de atraso' } },
  bloqueio_inadimplentes: { nome: 'Bloqueio de rematrícula por inadimplência', descricao: 'Bloqueia a rematrícula pendente de quem tem pendência aberta vencida. Afeta direito do aluno: nasce desligada.', parametro: { chave: 'dias_atraso', rotulo: 'Dias de atraso' }, sensivel: true },
  limpeza_tecnica: { nome: 'Limpeza técnica', descricao: 'Apaga códigos de confirmação expirados.' },
};
const resumo = (r: Record<string, unknown> | null | undefined) => !r ? '—' : Object.entries(r).map(([k, v]) => `${k.replace(/_/g, ' ')}: ${String(v)}`).join(' · ');

// Central de automações: algoritmo determinístico, sem IA e sem envio externo (diretriz de 26/11/2026).
export function Automacoes() {
  const { ies } = useSessao();
  const [recarga, setRecarga] = useState(0);
  const r = useCarregar(() => api.automacoes(ies!), [ies, recarga]);
  const acao = useAcao();
  const fazer = (fn: () => Promise<string>) => acao.executar(async () => { const t = await fn(); setRecarga((n) => n + 1); return t; });
  const d = r.dados;
  return (
    <>
      <Titulo titulo="Automações" subtitulo="Rotinas que o sistema executa sozinho, de hora em hora: algoritmo determinístico, sem IA e sem envio externo." />
      {(r.erro as ErroApi | null)?.codigo === 'PGRST202' ? <Vazio texto="Disponível após a migração 31 do banco." /> : <Estado carregando={r.carregando && !d} erro={r.erro} />}
      <Mensagem m={acao.mensagem} />
      {d && (
        <div className="space-y-4">
          <Aviso>{d.aviso} {d.agendador ? 'Agendador ativo: execução automática a cada hora (minuto 17).' : 'Agendador indisponível neste banco: use “Executar agora”.'}</Aviso>
          {d.pode_gerir && <button className="btn btn-peq" disabled={acao.enviando} onClick={() => void fazer(async () => {
            const x = await api.executarAutomacoes(ies!); return `Executado agora: ${Object.entries(x ?? {}).map(([k, v]) => `${REGRAS[k]?.nome ?? k} (${resumo(v as Record<string, unknown>)})`).join('; ') || 'nenhuma regra ativa'}.`; })}>
            <Play className="h-3.5 w-3.5" aria-hidden />Executar agora</button>}
          <div className="grid gap-3 lg:grid-cols-2">{d.regras.map((g) => {
            const def = REGRAS[g.codigo]; const p = def?.parametro;
            return (
              <Cartao key={g.codigo} titulo={def?.nome ?? g.codigo} icone={Bot} acao={<Chip tipo={g.ativa ? 'ok' : undefined}>{g.ativa ? 'ligada' : 'desligada'}</Chip>}>
                <p className="text-sm">{def?.descricao}</p>
                {def?.sensivel && <p className="mt-1 text-xs text-alerta">Atenção: decide sobre direito do aluno. Recomendo validação jurídica antes de ligar.</p>}
                <p className="nota mt-1">Última execução: {g.ultima_execucao ? dataHora(g.ultima_execucao) : 'nunca'} · {resumo(g.ultimo_resultado)}</p>
                {g.alterada_por && <p className="nota">Alterada por {g.alterada_por} em {g.alterada_em ? dataHora(g.alterada_em) : ''}</p>}
                {d.pode_gerir && <Controle ativa={g.ativa} parametro={p} valor={p ? g.parametros[p.chave] : undefined} enviando={acao.enviando}
                  salvar={(ativa, valor) => void fazer(async () => { await api.configurarAutomacao(ies!, g.codigo, ativa, p && valor ? { [p.chave]: valor } : undefined); return `${def?.nome ?? g.codigo}: ${ativa ? 'ligada' : 'desligada'}.`; })} />}
              </Cartao>);
          })}</div>
          <Cartao titulo="Últimas execuções">
            {!d.execucoes.length ? <Vazio texto="Nenhuma execução ainda." /> : (
              <ul className="space-y-1 text-xs">{d.execucoes.map((e, i) => <li key={i}>{dataHora(e.inicio)} · {e.origem === 'agendador' ? 'agendador' : 'manual'} · {Object.entries(e.resultado ?? {}).map(([k, v]) => `${REGRAS[k]?.nome ?? k}: ${resumo(v)}`).join(' | ')}</li>)}</ul>)}
          </Cartao>
        </div>)}
    </>
  );
}

function Controle({ ativa, parametro, valor, enviando, salvar }: { ativa: boolean; parametro?: { chave: string; rotulo: string }; valor?: number; enviando: boolean; salvar: (ativa: boolean, valor?: number) => void }) {
  const [v, setV] = useState(valor ? String(valor) : '');
  return (
    <div className="mt-2 flex flex-wrap items-end gap-2">
      {parametro && <Campo rotulo={parametro.rotulo}><input className="campo w-24" type="number" min={1} max={365} value={v} onChange={(e) => setV(e.target.value)} /></Campo>}
      {parametro && <button className="btn btn-sec btn-peq" disabled={enviando || !v} onClick={() => salvar(ativa, Number(v))}>Salvar parâmetro</button>}
      <button className={`btn btn-peq ${ativa ? 'btn-sec' : 'btn-ok'}`} disabled={enviando} onClick={() => salvar(!ativa, v ? Number(v) : undefined)}>{ativa ? 'Desligar' : 'Ligar'}</button>
    </div>
  );
}
