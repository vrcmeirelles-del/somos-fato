import { HandCoins } from 'lucide-react';
import { useState } from 'react';
import { useSessao } from '../components/Layout';
import { Aviso, Campo, Cartao, Chip, Detalhes, Estado, Kpi, Mensagem, Titulo, Vazio } from '../components/ui';
import { api } from '../lib/api';
import { dataHora, rotulo } from '../lib/formato';
import { useAcao, useCarregar } from '../lib/hooks';
import type { ErroApi } from '../lib/supabase';
import type { SolicitacaoBolsa } from '../lib/tipos';

const TIPOS = ['bolsa_institucional', 'convenio_empresa', 'prouni', 'fies', 'financiamento_privado', 'financiamento_proprio'];
const ETAPAS = ['inscricao', 'pre_selecao', 'documentacao', 'contratado', 'nao_contratado'];
type Fazer = (fn: () => Promise<string>) => Promise<void>;

// Bolsas, convênios e financiamento estudantil (L12): programas, solicitações e decisão humana segregada.
export function Bolsas({ abrirDetalhe }: { abrirDetalhe: (id: number) => void }) {
  const { ies, estrutura } = useSessao();
  const [recarga, setRecarga] = useState(0);
  const b = useCarregar(() => api.bolsas(ies!), [ies, recarga]);
  const acao = useAcao();
  const fazer: Fazer = (fn) => acao.executar(async () => { const t = await fn(); setRecarga((n) => n + 1); return t; });
  const vazio = { nome: '', tipo: 'bolsa_institucional', percentual_max: '', vagas: '', validade_ate: '', requisitos: '', documentos: '', cumulativo: false, cursos: [] as number[] };
  const [n, setN] = useState(vazio);
  const d = b.dados;
  const pendentes = d?.solicitacoes.filter((s) => s.status === 'solicitada') ?? [];
  return (
    <>
      <Titulo titulo="Bolsas e financiamento" subtitulo="ProUni, FIES, financiamento, convênios e bolsas institucionais: programas, solicitações e decisão humana segregada." />
      {(b.erro as ErroApi | null)?.codigo === 'PGRST202' ? <Vazio texto="Disponível após a migração 23 do banco." /> : <Estado carregando={b.carregando && !d} erro={b.erro} />}
      <Mensagem m={acao.mensagem} />
      {d && (
        <div className="space-y-4">
          <Aviso>{d.aviso}</Aviso>
          <div className="grid gap-3 sm:grid-cols-4">
            <Kpi rotulo="Programas ativos" valor={String(d.programas.filter((p) => p.ativo).length)} />
            <Kpi rotulo="Aguardando decisão" valor={String(pendentes.length)} destaque={pendentes.length > 0} />
            <Kpi rotulo="Benefícios aprovados" valor={String(d.programas.reduce((a, p) => a + p.aprovadas, 0))} />
            <Kpi rotulo="Ingressos com benefício" valor={String(d.programas.reduce((a, p) => a + p.confirmados, 0))} />
          </div>
          {d.pode_gerir && (
            <Detalhes titulo="Novo programa">
              <form className="grid gap-2 sm:grid-cols-3" onSubmit={(e) => { e.preventDefault(); void fazer(async () => {
                await api.salvarProgramaBolsa(ies!, { ...n, percentual_max: Number(n.percentual_max.replace(',', '.')), vagas: n.vagas || null, validade_ate: n.validade_ate || null,
                  cursos: n.cursos.length ? n.cursos : null, documentos: n.documentos.split(',').map((x) => x.trim()).filter(Boolean) });
                setN(vazio); return 'Programa criado.'; }); }}>
                <Campo rotulo="Nome"><input className="campo" required minLength={3} value={n.nome} onChange={(e) => setN({ ...n, nome: e.target.value })} /></Campo>
                <Campo rotulo="Tipo"><select className="campo" value={n.tipo} onChange={(e) => setN({ ...n, tipo: e.target.value })}>{TIPOS.map((t) => <option key={t} value={t}>{rotulo(t)}</option>)}</select></Campo>
                <Campo rotulo={n.tipo === 'prouni' ? 'Percentual máximo (50 ou 100)' : 'Percentual máximo (%)'}><input className="campo" required inputMode="decimal" value={n.percentual_max} onChange={(e) => setN({ ...n, percentual_max: e.target.value })} /></Campo>
                <Campo rotulo="Vagas (vazio = sem limite)"><input className="campo" type="number" min={1} value={n.vagas} onChange={(e) => setN({ ...n, vagas: e.target.value })} /></Campo>
                <Campo rotulo="Válido até"><input className="campo" type="date" value={n.validade_ate} onChange={(e) => setN({ ...n, validade_ate: e.target.value })} /></Campo>
                <Campo rotulo="Cursos (nenhum = todos)"><select className="campo" multiple value={n.cursos.map(String)} onChange={(e) => setN({ ...n, cursos: Array.from(e.target.selectedOptions).map((o) => Number(o.value)) })}>
                  {estrutura?.cursos.map((c) => <option key={c.id} value={c.id}>{c.nome} · {rotulo(c.turno)}</option>)}</select></Campo>
                <Campo rotulo="Requisitos" className="sm:col-span-2"><textarea className="campo" value={n.requisitos} onChange={(e) => setN({ ...n, requisitos: e.target.value })} /></Campo>
                <Campo rotulo="Documentos exigidos (separe por vírgula)"><input className="campo" value={n.documentos} onChange={(e) => setN({ ...n, documentos: e.target.value })} /></Campo>
                <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={n.cumulativo} onChange={(e) => setN({ ...n, cumulativo: e.target.checked })} />Cumulativo com outros benefícios cumulativos</label>
                <div className="sm:col-span-3"><button className="btn btn-peq" disabled={acao.enviando}>Criar programa</button></div>
              </form>
            </Detalhes>)}
          <Cartao titulo="Programas" icone={HandCoins}>
            {!d.programas.length ? <Vazio texto="Nenhum programa cadastrado." /> : (
              <div className="tabela" tabIndex={0} role="region" aria-label="Tabela com rolagem horizontal"><table><thead><tr><th>Programa</th><th>Tipo</th><th>Máx.</th><th>Vagas</th><th>Pendentes</th><th>Aprovadas</th><th>Ingressos</th><th>% médio</th><th /></tr></thead>
                <tbody>{d.programas.map((p) => (
                  <tr key={p.id} className={p.ativo ? '' : 'opacity-60'}>
                    <td>{p.nome}{p.cumulativo && <Chip tipo="tec">cumulativo</Chip>}{p.validade_ate && <span className="nota"> · até {new Date(`${p.validade_ate}T12:00:00`).toLocaleDateString('pt-BR')}</span>}</td>
                    <td>{rotulo(p.tipo)}</td><td>{p.percentual_max}%</td><td>{p.vagas ?? '—'}</td><td>{p.solicitadas}</td><td>{p.aprovadas}</td><td>{p.confirmados}</td><td>{p.percentual_medio ?? 'N/D'}</td>
                    <td>{d.pode_gerir && <button className="btn btn-fantasma btn-peq" disabled={acao.enviando} onClick={() => void fazer(async () => {
                      await api.salvarProgramaBolsa(ies!, { ativo: !p.ativo }, p.id); return p.ativo ? 'Programa desativado.' : 'Programa reativado.'; })}>{p.ativo ? 'Desativar' : 'Reativar'}</button>}</td>
                  </tr>))}</tbody></table></div>)}
          </Cartao>
          <Cartao titulo="Solicitações">
            {!d.solicitacoes.length ? <Vazio texto="Nenhuma solicitação." /> : <div className="space-y-2">{d.solicitacoes.map((s) => <LinhaSolicitacao key={s.id} s={s} podeDecidir={d.pode_decidir} fazer={fazer} enviando={acao.enviando} abrirDetalhe={abrirDetalhe} />)}</div>}
          </Cartao>
        </div>)}
    </>
  );
}

export function LinhaSolicitacao({ s, podeDecidir, fazer, enviando, abrirDetalhe }: { s: SolicitacaoBolsa; podeDecidir: boolean; fazer: Fazer; enviando: boolean; abrirDetalhe?: (id: number) => void }) {
  const [just, setJust] = useState('');
  const [pct, setPct] = useState(String(s.percentual));
  return (
    <div className="rounded-lg border border-linha p-3 text-sm">
      <p className="font-medium">{abrirDetalhe ? <button className="text-tec hover:underline" onClick={() => abrirDetalhe(s.oportunidade_id)}>{s.nome}</button> : s.nome} · {s.curso}
        <Chip tipo={s.status === 'aprovada' ? 'ok' : s.status === 'solicitada' ? 'pend' : s.status === 'indeferida' ? 'erro' : undefined}>{rotulo(s.status)}</Chip>
        {s.etapa_externa && <Chip tipo="tec">{rotulo(s.etapa_externa)}</Chip>}</p>
      <p>{s.programa} ({rotulo(s.tipo)}) · {s.percentual}% · pedido {s.origem === 'portal' ? 'pelo candidato no portal' : `por ${s.solicitado_por ?? '—'}`} em {dataHora(s.solicitado_em)}</p>
      {s.declaracao && <p className="text-xs">“{s.declaracao}”</p>}
      {s.justificativa && <p className="text-xs">Decisão: {s.justificativa} · {s.decidido_por} · {s.decidido_em ? dataHora(s.decidido_em) : ''}</p>}
      {podeDecidir && s.status === 'solicitada' && (s.decide_proprio
        ? <p className="nota mt-1">Você solicitou: outra pessoa decide.</p>
        : <div className="mt-2 flex flex-wrap items-end gap-2">
            <Campo rotulo="Percentual"><input className="campo w-20" inputMode="decimal" value={pct} onChange={(e) => setPct(e.target.value)} /></Campo>
            <Campo rotulo="Justificativa" className="grow"><input className="campo" value={just} onChange={(e) => setJust(e.target.value)} /></Campo>
            <button className="btn btn-ok btn-peq" disabled={enviando || just.trim().length < 5} onClick={() => void fazer(async () => { await api.decidirBolsa(s.id, 'aprovada', just, Number(pct.replace(',', '.'))); return 'Benefício aprovado.'; })}>Aprovar</button>
            <button className="btn btn-sec btn-peq" disabled={enviando || just.trim().length < 5} onClick={() => void fazer(async () => { await api.decidirBolsa(s.id, 'indeferida', just); return 'Solicitação indeferida.'; })}>Indeferir</button>
          </div>)}
      {podeDecidir && ['prouni', 'fies', 'financiamento_privado'].includes(s.tipo) && s.status !== 'cancelada' && (
        <Campo rotulo="Etapa externa (informada pela instituição)" className="mt-2 max-w-xs"><select className="campo" value={s.etapa_externa ?? ''} disabled={enviando}
          onChange={(e) => void fazer(async () => { await api.etapaBolsa(s.id, e.target.value); return 'Etapa externa registrada.'; })}>{ETAPAS.map((x) => <option key={x} value={x}>{rotulo(x)}</option>)}</select></Campo>)}
      {podeDecidir && s.status === 'aprovada' && <button className="btn btn-fantasma btn-peq mt-1" disabled={enviando} onClick={() => { const m = window.prompt('Motivo do cancelamento do benefício:');
        if (m) void fazer(async () => { await api.cancelarBolsa(s.id, m); return 'Benefício cancelado; a vaga foi liberada.'; }); }}>Cancelar benefício</button>}
    </div>
  );
}
