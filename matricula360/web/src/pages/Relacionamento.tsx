import { HeartHandshake, Link2, ShieldAlert, Sparkles, Users } from 'lucide-react';
import { useState } from 'react';
import { BarraFiltros, useSessao } from '../components/Layout';
import { Aviso, Campo, Cartao, Chip, Detalhes, Estado, Kpi, Mensagem, Titulo, Vazio } from '../components/ui';
import { api } from '../lib/api';
import { pct, rotulo } from '../lib/formato';
import { useAcao, useCarregar } from '../lib/hooks';
import type { ErroApi } from '../lib/supabase';
import type { Ingressante, Marco, Relacionamento as TRel } from '../lib/tipos';

const MARCOS: Marco[] = ['d30', 'd90', 'rematricula'];
const SITUACOES = ['ativo', 'trancado', 'evadido', 'transferido'];
type Fazer = (fn: () => Promise<string>) => Promise<void>;

// Relacionamento Estudantil: vínculo nos marcos (sem presumir evasão), onboarding, indicações e embaixadores.
export function Relacionamento() {
  const { ies, filtros } = useSessao();
  const [recarga, setRecarga] = useState(0);
  const r = useCarregar(() => (ies && filtros.coorte ? api.relacionamento(ies, filtros.coorte) : Promise.resolve(null)), [ies, filtros.coorte, recarga]);
  const acao = useAcao();
  const fazer: Fazer = (fn) => acao.executar(async () => { const t = await fn(); setRecarga((n) => n + 1); return t; });
  const d = r.dados;
  return (
    <>
      <Titulo titulo="Relacionamento Estudantil" subtitulo="Acompanhamento dos ingressantes em 30 e 90 dias e na rematrícula, onboarding, indicações e embaixadores." />
      <BarraFiltros completos={false} />
      {(r.erro as ErroApi | null)?.codigo === 'PGRST202' ? <Vazio texto="Disponível após a migração 17 do banco." /> : <Estado carregando={r.carregando && !d} erro={r.erro} />}
      <Mensagem m={acao.mensagem} />
      {d && (
        <div className="space-y-5">
          <Aviso>Sem registro de vínculo, a situação é <strong>desconhecida</strong>: o sistema não presume evasão. {d.metodos.permanencia}</Aviso>
          <div className="kpis grid grid-cols-1 gap-3 md:grid-cols-3">
            {d.permanencia.map((m) => (
              <Kpi key={m.marco} rotulo={`Permanência · ${rotulo(m.marco)}`} valor={pct(m.permanencia)} icone={HeartHandshake}
                detalhe={m.motivo ?? `${m.ativos} ativos de ${m.elegiveis} elegíveis`} />))}
          </div>
          {d.permanencia.some((m) => m.permanencia == null && m.minimo_observado != null) && (
            <p className="nota">Mínimo observado (apenas ativos registrados ÷ elegíveis): {d.permanencia.filter((m) => m.minimo_observado != null).map((m) =>
              `${rotulo(m.marco)} ${pct(m.minimo_observado)} · cobertura ${pct(m.cobertura)}`).join(' | ')}</p>)}
          {d.alertas.length > 0 && (
            <Cartao titulo={`Alertas de permanência (MAIM Retention · ${d.regra})`} icone={ShieldAlert}>
              <ul className="space-y-1 text-sm">{d.alertas.map((a) => <li key={a.regra}><strong>{a.titulo}</strong> <Chip tipo={a.prioridade === 1 ? 'pend' : undefined}>{a.quantidade}</Chip> — {a.proposta}</li>)}</ul>
            </Cartao>)}
          <Cartao titulo="Ingressantes da coorte" icone={Users}>
            {d.ingressantes.length ? d.ingressantes.map((i) => <LinhaIngressante key={i.id} i={i} d={d} fazer={fazer} enviando={acao.enviando} />)
              : <p className="nota">Nenhum ingressante efetivo na coorte {d.coorte}.</p>}
          </Cartao>
          <Indicacoes d={d} fazer={fazer} enviando={acao.enviando} />
          <Embaixadores d={d} fazer={fazer} enviando={acao.enviando} />
        </div>
      )}
    </>
  );
}

function LinhaIngressante({ i, d, fazer, enviando }: { i: Ingressante; d: TRel; fazer: Fazer; enviando: boolean }) {
  const hoje = new Date().toISOString().slice(0, 10);
  const [f, setF] = useState({ marco: 'd30' as Marco, situacao: 'ativo', data: hoje, obs: '' });
  const alcancados = MARCOS.filter((m) => i.dias_desde_ingresso >= d.marcos[m]);
  return (
    <section className="mb-3 rounded-lg border border-linha p-3 text-sm">
      <p className="font-semibold">{i.nome} · {i.curso} <span className="font-normal text-suave">· ingresso há {i.dias_desde_ingresso} dia(s)</span>{i.embaixador && <Chip tipo="tec">embaixador(a)</Chip>}</p>
      <p className="mt-1">{MARCOS.map((m) => {
        const v = i.vinculos[m];
        return <Chip key={m} tipo={v ? (v.situacao === 'ativo' ? 'ok' : 'erro') : i.dias_desde_ingresso >= d.marcos[m] ? 'pend' : undefined}>
          {rotulo(m)}: {v ? `${rotulo(v.situacao)}${v.por ? ` (${v.por})` : ''}` : i.dias_desde_ingresso >= d.marcos[m] ? 'desconhecido' : 'não alcançado'}</Chip>;
      })}</p>
      <div className="mt-2 flex flex-wrap gap-x-3 gap-y-1">{d.onboarding_modelo.map((item) => (
        <label key={item} className="flex items-center gap-1 text-xs"><input type="checkbox" checked={i.onboarding.includes(item)} disabled={!d.pode_registrar || enviando}
          onChange={(e) => void fazer(async () => { await api.onboardingItem(i.id, item, e.target.checked); return 'Onboarding atualizado.'; })} />{item}</label>))}</div>
      {d.pode_registrar && alcancados.length > 0 && (
        <form className="mt-2 flex flex-wrap items-end gap-2" onSubmit={(e) => { e.preventDefault(); void fazer(async () => {
          await api.registrarVinculo(i.id, f.marco, f.situacao, f.data, f.obs || undefined); setF({ ...f, obs: '' }); return `Vínculo de ${i.nome} registrado.`; }); }}>
          <Campo rotulo="Marco"><select className="campo" value={f.marco} onChange={(e) => setF({ ...f, marco: e.target.value as Marco })}>{alcancados.map((m) => <option key={m} value={m}>{rotulo(m)}</option>)}</select></Campo>
          <Campo rotulo="Situação"><select className="campo" value={f.situacao} onChange={(e) => setF({ ...f, situacao: e.target.value })}>{SITUACOES.map((x) => <option key={x} value={x}>{rotulo(x)}</option>)}</select></Campo>
          <Campo rotulo="Data de referência"><input className="campo" type="date" max={hoje} value={f.data} onChange={(e) => setF({ ...f, data: e.target.value })} /></Campo>
          <Campo rotulo="Fonte / observação" className="grow"><input className="campo" required={f.situacao !== 'ativo'} maxLength={500} value={f.obs} onChange={(e) => setF({ ...f, obs: e.target.value })} /></Campo>
          <button className="btn btn-peq" disabled={enviando}>Registrar vínculo</button>
        </form>)}
    </section>
  );
}

function Indicacoes({ d, fazer, enviando }: { d: TRel; fazer: Fazer; enviando: boolean }) {
  const { ies } = useSessao();
  const [f, setF] = useState({ codigo: '', indicador_tipo: 'aluno', indicador_nome: '', embaixador_id: '' });
  return (
    <Cartao titulo="Indicações rastreáveis" icone={Link2}>
      <p className="nota mb-2">{d.metodos.indicacao} Informe o código no cadastro ou na importação do CRM.</p>
      {d.indicacoes.length ? (
        <div className="tabela mb-3"><table>
          <thead><tr>{['Código', 'Indicador', 'Leads', 'Ingressantes'].map((h) => <th key={h} scope="col">{h}</th>)}</tr></thead>
          <tbody>{d.indicacoes.map((i) => <tr key={i.id}><td><code className="text-tec">{i.codigo}</code></td><td>{i.indicador_nome} <Chip>{rotulo(i.indicador_tipo)}</Chip></td><td>{i.leads}</td><td>{i.ingressantes}</td></tr>)}</tbody>
        </table></div>) : <p className="nota mb-2">Nenhum código de indicação.</p>}
      {d.pode_indicar && (
        <form className="flex flex-wrap items-end gap-2" onSubmit={(e) => { e.preventDefault(); void fazer(async () => {
          const r = await api.criarIndicacao(ies!, f); setF({ codigo: '', indicador_tipo: 'aluno', indicador_nome: '', embaixador_id: '' }); return `Código ${r.codigo} criado.`; }); }}>
          <Campo rotulo="Código"><input className="campo" required pattern="[a-z0-9][a-z0-9\-]{3,40}" value={f.codigo} onChange={(e) => setF({ ...f, codigo: e.target.value.toLowerCase() })} /></Campo>
          <Campo rotulo="Embaixador(a)"><select className="campo" value={f.embaixador_id} onChange={(e) => setF({ ...f, embaixador_id: e.target.value })}><option value="">—</option>
            {d.embaixadores.filter((x) => x.status === 'ativo').map((x) => <option key={x.id} value={x.id}>{x.nome}</option>)}</select></Campo>
          {!f.embaixador_id && <>
            <Campo rotulo="Tipo"><select className="campo" value={f.indicador_tipo} onChange={(e) => setF({ ...f, indicador_tipo: e.target.value })}>{['aluno', 'colaborador', 'parceiro'].map((x) => <option key={x} value={x}>{rotulo(x)}</option>)}</select></Campo>
            <Campo rotulo="Nome do indicador"><input className="campo" required minLength={2} value={f.indicador_nome} onChange={(e) => setF({ ...f, indicador_nome: e.target.value })} /></Campo></>}
          <button className="btn btn-peq" disabled={enviando}>Criar código</button>
        </form>)}
    </Cartao>
  );
}

function Embaixadores({ d, fazer, enviando }: { d: TRel; fazer: Fazer; enviando: boolean }) {
  const { ies } = useSessao();
  const [programa, setPrograma] = useState(d.programa_embaixadores ?? '');
  const [modelo, setModelo] = useState(d.onboarding_modelo.join('\n'));
  const [novo, setNovo] = useState({ op: '', aceite: new Date().toISOString().slice(0, 10) });
  return (
    <Cartao titulo="Embaixadores (regras transparentes)" icone={Sparkles}>
      <p className="mb-2 whitespace-pre-line text-sm">{d.programa_embaixadores ?? <span className="nota">Regras do programa ainda não publicadas.</span>}</p>
      {d.embaixadores.length > 0 && (
        <div className="tabela mb-3"><table>
          <thead><tr>{['Embaixador(a)', 'Curso', 'Aceite das regras', 'Indicações', 'Ingressantes indicados', 'Status'].map((h) => <th key={h} scope="col">{h}</th>)}</tr></thead>
          <tbody>{d.embaixadores.map((e) => <tr key={e.id}><td>{e.nome}</td><td>{e.curso}</td>
            <td>{new Date(e.aceite_regras_em).toLocaleDateString('pt-BR')}{!e.regras_atuais && <Chip tipo="pend">regras mudaram: novo aceite</Chip>}</td>
            <td>{e.indicacoes}</td><td>{e.ingressantes_indicados}</td><td>{rotulo(e.status)}</td></tr>)}</tbody>
        </table></div>)}
      {d.pode_gerir && (
        <>
          <Detalhes titulo="Cadastrar embaixador(a)">
            <form className="flex flex-wrap items-end gap-2" onSubmit={(e) => { e.preventDefault(); void fazer(async () => {
              await api.salvarEmbaixador(Number(novo.op), new Date(`${novo.aceite}T12:00:00`).toISOString()); return 'Embaixador(a) cadastrado(a).'; }); }}>
              <Campo rotulo="Ingressante"><select className="campo" required value={novo.op} onChange={(e) => setNovo({ ...novo, op: e.target.value })}><option value="">Selecione…</option>
                {d.ingressantes.filter((i) => !i.embaixador).map((i) => <option key={i.id} value={i.id}>{i.nome}</option>)}</select></Campo>
              <Campo rotulo="Data do aceite das regras"><input className="campo" type="date" required value={novo.aceite} onChange={(e) => setNovo({ ...novo, aceite: e.target.value })} /></Campo>
              <button className="btn btn-peq" disabled={enviando || !d.programa_embaixadores}>Cadastrar</button>
            </form>
          </Detalhes>
          <Detalhes titulo="Regras do programa e modelo de onboarding">
            <Campo rotulo="Regras do programa de embaixadores (visíveis a todos; mudança exige novo aceite)"><textarea className="campo min-h-[80px]" maxLength={3000} value={programa} onChange={(e) => setPrograma(e.target.value)} /></Campo>
            <Campo rotulo="Itens de onboarding (um por linha)" className="mt-2"><textarea className="campo min-h-[80px]" value={modelo} onChange={(e) => setModelo(e.target.value)} /></Campo>
            <button className="btn btn-peq mt-2" disabled={enviando} onClick={() => void fazer(async () => {
              await api.configurarRelacionamento(ies!, modelo.split('\n').map((x) => x.trim()).filter(Boolean), programa || null); return 'Configuração salva.'; })}>Salvar</button>
          </Detalhes>
        </>)}
    </Cartao>
  );
}
