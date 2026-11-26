import { Building, GraduationCap, MessageCircleReply, Wallet } from 'lucide-react';
import { useState } from 'react';
import { useSessao } from '../components/Layout';
import { Aviso, Campo, Cartao, Chip, Detalhes, Estado, Kpi, Mensagem, Titulo, Vazio } from '../components/ui';
import { api } from '../lib/api';
import { lerCsv } from '../lib/arquivo';
import { dataHora, moeda, rotulo } from '../lib/formato';
import { useAcao, useCarregar } from '../lib/hooks';
import type { ErroApi } from '../lib/supabase';

const pendente = (e: unknown, n: number) => (e as ErroApi | null)?.codigo === 'PGRST202' ? <Vazio texto={`Disponível após a migração ${n} do banco.`} /> : null;

// L21: fila de mensagens recebidas aguardando resposta (integração real com WhatsApp/SMS desligada).
export function Conversas({ abrirDetalhe }: { abrirDetalhe: (id: number) => void }) {
  const { ies } = useSessao();
  const r = useCarregar(() => api.conversas(ies!), [ies]);
  const d = r.dados;
  return (
    <>
      <Titulo titulo="Conversas aguardando resposta" subtitulo="Mensagens recebidas registradas pela equipe, ordenadas pela espera. Registre a mensagem recebida e a resposta na ficha do lead." />
      {pendente(r.erro, 30) ?? <Estado carregando={r.carregando && !d} erro={r.erro} />}
      {d && (
        <div className="space-y-4">
          <Aviso>{d.aviso}</Aviso>
          <Cartao titulo={`Fila (${d.fila.length})`} icone={MessageCircleReply}>
            {!d.fila.length ? <Vazio texto="Ninguém aguardando resposta." /> : (
              <ul className="space-y-2 text-sm">{d.fila.map((f) => (
                <li key={f.oportunidade_id} className={`rounded-lg border p-2 ${f.horas > d.sla_horas ? 'border-erro/50' : 'border-linha'}`}>
                  <p><button className="font-medium text-tec hover:underline" onClick={() => abrirDetalhe(f.oportunidade_id)}>{f.nome}</button> · {f.curso} · {rotulo(f.etapa)}
                    <Chip tipo={f.horas > d.sla_horas ? 'erro' : 'pend'}>{f.horas} h aguardando</Chip><span className="nota"> · {rotulo(f.tipo)} · {f.responsavel ?? 'sem responsável'}</span></p>
                  <p className="text-xs">“{f.texto}” · {dataHora(f.recebida_em)}</p>
                </li>))}</ul>)}
          </Cartao>
        </div>)}
    </>
  );
}

// L13: pendências financeiras por planilha, inadimplência, negociação e bloqueio de rematrícula sob comando.
export function FinanceiroAlunos({ abrirDetalhe }: { abrirDetalhe: (id: number) => void }) {
  const { ies } = useSessao();
  const [recarga, setRecarga] = useState(0);
  const [dias, setDias] = useState(30);
  const r = useCarregar(() => api.financeiro(ies!, dias), [ies, dias, recarga]);
  const camp = useCarregar(() => api.rematricula(ies!).then((x) => x.campanhas.filter((c) => c.status === 'aberta')).catch(() => []), [ies, recarga]);
  const acao = useAcao();
  const fazer = (fn: () => Promise<string>) => acao.executar(async () => { const t = await fn(); setRecarga((n) => n + 1); return t; });
  const [filtro, setFiltro] = useState('aberta');
  const d = r.dados;
  return (
    <>
      <Titulo titulo="Financeiro dos alunos" subtitulo="Pendências importadas da planilha do financeiro, inadimplência, negociação e bloqueio de rematrícula sob comando." />
      {pendente(r.erro, 30) ?? <Estado carregando={r.carregando && !d} erro={r.erro} />}
      <Mensagem m={acao.mensagem} />
      {d && (
        <div className="space-y-4">
          <Aviso>{d.aviso}</Aviso>
          <div className="grid gap-3 sm:grid-cols-4">
            <Kpi rotulo={`Inadimplência (> ${d.dias_atraso} dias)`} valor={d.indicadores.inadimplencia_pct == null ? 'N/D' : `${d.indicadores.inadimplencia_pct}%`} detalhe={`${d.indicadores.inadimplentes} de ${d.indicadores.alunos} aluno(s)`} destaque />
            <Kpi rotulo="Em aberto" valor={moeda(d.indicadores.em_aberto_centavos)} />
            <Kpi rotulo="Negociadas" valor={String(d.indicadores.negociadas)} />
            <Campo rotulo="Atraso considerado (dias)"><input className="campo" type="number" min={1} value={dias} onChange={(e) => setDias(Math.max(1, Number(e.target.value)))} /></Campo>
          </div>
          {d.pode_gerir && (
            <Detalhes titulo="Importar pendências (CSV) e bloquear rematrícula">
              <p className="nota">Colunas: <code>email;competencia;valor;vencimento;situacao</code> (ou <code>oportunidade_id</code> no lugar de e-mail). Competência AAAA-MM; situação aberta, paga, negociada ou cancelada. Reimportar atualiza.</p>
              <input type="file" accept=".csv,text/csv" className="mt-1 text-sm" aria-label="Arquivo CSV de pendências" disabled={acao.enviando} onChange={(e) => { const a = e.target.files?.[0]; if (!a) return;
                void fazer(async () => { const x = await api.importarPendencias(ies!, lerCsv(await a.text())); return `${x.importadas} importada(s)${x.rejeitadas.length ? `; rejeitadas: ${x.rejeitadas.map((j) => `linha ${j.linha} (${j.motivo})`).join('; ')}` : ''}.`; }); }} />
              {(camp.dados ?? []).map((c) => (
                <button key={c.id} className="btn btn-sec btn-peq mt-2 mr-2" disabled={acao.enviando} onClick={() => {
                  if (window.confirm(`Bloquear a rematrícula ${c.periodo} de quem tem pendência aberta vencida há mais de ${dias} dias?`))
                    void fazer(async () => `${(await api.bloquearInadimplentes(c.id, dias)).bloqueadas} rematrícula(s) bloqueada(s).`); }}>Bloquear rematrícula {c.periodo} de inadimplentes</button>))}
            </Detalhes>)}
          <Cartao titulo="Pendências" icone={Wallet} acao={<select aria-label="Situação" className="campo w-auto" value={filtro} onChange={(e) => setFiltro(e.target.value)}>
            {['aberta', 'negociada', 'paga', 'cancelada', ''].map((s) => <option key={s} value={s}>{s ? rotulo(s) : 'Todas'}</option>)}</select>}>
            {!d.pendencias.length ? <Vazio texto="Nenhuma pendência importada." /> : (
              <ul className="space-y-1 text-sm">{d.pendencias.filter((p) => !filtro || p.situacao === filtro).map((p) => (
                <li key={p.id} className="flex flex-wrap items-center gap-2 border-b border-linha py-1">
                  <button className="font-medium text-tec hover:underline" onClick={() => abrirDetalhe(p.oportunidade_id)}>{p.nome}</button>
                  <span>{p.competencia} · {moeda(p.valor_centavos)} · vence {new Date(`${p.vencimento}T12:00:00`).toLocaleDateString('pt-BR')}</span>
                  <Chip tipo={p.situacao === 'paga' ? 'ok' : p.situacao === 'aberta' && p.dias_atraso > dias ? 'erro' : 'pend'}>{rotulo(p.situacao)}{p.situacao === 'aberta' && p.dias_atraso ? ` · ${p.dias_atraso} dias` : ''}</Chip>
                  {p.rematricula_pendente && <Chip tipo="tec">rematrícula pendente</Chip>}
                  {p.acordo && <span className="nota">{p.acordo}</span>}
                  {d.pode_gerir && p.situacao === 'aberta' && <button className="btn btn-fantasma btn-peq" disabled={acao.enviando} onClick={() => { const t = window.prompt('Descreva o acordo (parcelas, datas):');
                    if (t) void fazer(async () => { await api.negociarPendencia(p.id, 'negociada', t); return 'Negociação registrada.'; }); }}>Registrar negociação</button>}
                </li>))}</ul>)}
          </Cartao>
        </div>)}
    </>
  );
}

// L18: painel por unidade (sede, polo próprio, polo parceiro); repasse só como regra textual.
export function Polos() {
  const { ies, estrutura } = useSessao();
  const [recarga, setRecarga] = useState(0);
  const [coorte, setCoorte] = useState('');
  const r = useCarregar(() => api.polos(ies!, coorte || undefined), [ies, coorte, recarga]);
  const acao = useAcao();
  const d = r.dados;
  return (
    <>
      <Titulo titulo="Polos e parceiros" subtitulo="Funil, ingressos, meta e receita mensal por unidade. O parceiro acessa com escopo restrito ao seu polo (Perfis e permissões)." />
      {pendente(r.erro, 30) ?? <Estado carregando={r.carregando && !d} erro={r.erro} />}
      <Mensagem m={acao.mensagem} />
      {d && (
        <div className="space-y-4">
          <Aviso>{d.aviso}</Aviso>
          <Campo rotulo="Coorte" className="max-w-xs"><select className="campo" value={coorte} onChange={(e) => setCoorte(e.target.value)}><option value="">Todas</option>{estrutura?.coortes.map((c) => <option key={c} value={c}>{c}</option>)}</select></Campo>
          <div className="grid gap-3 lg:grid-cols-2">{d.unidades.map((u) => <CartaoUnidade key={u.id} u={u} podeGerir={d.pode_gerir} aoSalvar={() => setRecarga((n) => n + 1)} executar={acao.executar} enviando={acao.enviando} />)}</div>
        </div>)}
    </>
  );
}

function CartaoUnidade({ u, podeGerir, aoSalvar, executar, enviando }: { u: NonNullable<ReturnType<typeof useCarregar<Awaited<ReturnType<typeof api.polos>>>>['dados']>['unidades'][number];
  podeGerir: boolean; aoSalvar: () => void; executar: (fn: () => Promise<string>) => Promise<void>; enviando: boolean }) {
  const { ies } = useSessao();
  const [f, setF] = useState({ tipo: u.tipo, parceiro: u.parceiro ?? '', regra_repasse: u.regra_repasse ?? '', meta_ingressos: u.meta_ingressos == null ? '' : String(u.meta_ingressos) });
  return (
    <Cartao titulo={u.nome} icone={Building} acao={<Chip tipo={u.tipo === 'polo_parceiro' ? 'tec' : undefined}>{rotulo(u.tipo)}</Chip>}>
      {u.parceiro && <p className="nota">Parceiro: {u.parceiro}</p>}
      <div className="mt-2 grid gap-2 sm:grid-cols-3">
        <Kpi rotulo="Leads" valor={String(u.leads)} /><Kpi rotulo="Ingressos" valor={String(u.ingressos)} detalhe={u.meta_ingressos != null ? `meta ${u.meta_ingressos}` : undefined} />
        <Kpi rotulo="Conversão" valor={u.conversao_pct == null ? 'N/D' : `${u.conversao_pct}%`} />
      </div>
      <p className="mt-2 text-sm">Inscritos {u.inscritos} · matrículas {u.matriculas} · receita mensal dos ingressos {moeda(u.receita_mensal_centavos)}</p>
      {u.regra_repasse && <p className="text-xs">Regra de repasse (contrato): {u.regra_repasse}</p>}
      {podeGerir && (
        <Detalhes titulo="Editar unidade">
          <div className="grid gap-2 sm:grid-cols-2">
            <Campo rotulo="Tipo"><select className="campo" value={f.tipo} onChange={(e) => setF({ ...f, tipo: e.target.value })}>{['sede', 'polo_proprio', 'polo_parceiro'].map((t) => <option key={t} value={t}>{rotulo(t)}</option>)}</select></Campo>
            <Campo rotulo="Meta de ingressos"><input className="campo" type="number" min={0} value={f.meta_ingressos} onChange={(e) => setF({ ...f, meta_ingressos: e.target.value })} /></Campo>
            <Campo rotulo="Parceiro" className="sm:col-span-2"><input className="campo" value={f.parceiro} onChange={(e) => setF({ ...f, parceiro: e.target.value })} /></Campo>
            <Campo rotulo="Regra de repasse (texto do contrato)" className="sm:col-span-2"><textarea className="campo" value={f.regra_repasse} onChange={(e) => setF({ ...f, regra_repasse: e.target.value })} /></Campo>
          </div>
          <button className="btn btn-sec btn-peq mt-2" disabled={enviando} onClick={() => void executar(async () => { await api.salvarPolo(ies!, u.id, f); aoSalvar(); return 'Unidade atualizada.'; })}>Salvar</button>
        </Detalhes>)}
    </Cartao>
  );
}

// L20: egressos com consentimento e oferta de pós-graduação ou segunda graduação.
export function EgressosPagina({ abrirDetalhe }: { abrirDetalhe: (id: number) => void }) {
  const { ies, estrutura } = useSessao();
  const [recarga, setRecarga] = useState(0);
  const r = useCarregar(() => api.egressos(ies!), [ies, recarga]);
  const acao = useAcao();
  const fazer = (fn: () => Promise<string>) => acao.executar(async () => { const t = await fn(); setRecarga((n) => n + 1); return t; });
  const [of, setOf] = useState({ curso: String(estrutura?.cursos[0]?.id ?? ''), coorte: estrutura?.coortes[0] ?? '', forma: 'pos_graduacao' });
  const d = r.dados;
  return (
    <>
      <Titulo titulo="Egressos" subtitulo="Quem concluiu o curso: consentimento de contato, interesses e ofertas de pós-graduação ou segunda graduação. Registre a conclusão na ficha do aluno." />
      {pendente(r.erro, 30) ?? <Estado carregando={r.carregando && !d} erro={r.erro} />}
      <Mensagem m={acao.mensagem} />
      {d && (
        <div className="space-y-4">
          <div className="grid gap-3 sm:grid-cols-3">
            <Kpi rotulo="Egressos" valor={String(d.egressos.length)} />
            <Kpi rotulo="Com consentimento de contato" valor={String(d.egressos.filter((e) => e.consentimento).length)} />
            <Kpi rotulo="Ofertas que viraram ingresso" valor={String(d.egressos.reduce((a, e) => a + e.ofertas_convertidas, 0))} />
          </div>
          {d.pode_ofertar && (
            <Cartao titulo="Oferta">
              <div className="flex flex-wrap items-end gap-2">
                <Campo rotulo="Curso ofertado"><select className="campo" value={of.curso} onChange={(e) => setOf({ ...of, curso: e.target.value })}>{estrutura?.cursos.map((c) => <option key={c.id} value={c.id}>{c.nome} · {rotulo(c.turno)}</option>)}</select></Campo>
                <Campo rotulo="Coorte"><input className="campo w-24" pattern="\d{4}\.[12]" value={of.coorte} onChange={(e) => setOf({ ...of, coorte: e.target.value })} /></Campo>
                <Campo rotulo="Forma"><select className="campo" value={of.forma} onChange={(e) => setOf({ ...of, forma: e.target.value })}><option value="pos_graduacao">Pós-graduação</option><option value="segunda_graduacao">Segunda graduação</option></select></Campo>
              </div>
              <p className="nota mt-1">Use “Ofertar” em cada egresso com consentimento. A oferta cria uma oportunidade no CRM (sem duplicar).</p>
            </Cartao>)}
          <Cartao titulo="Egressos" icone={GraduationCap}>
            {!d.egressos.length ? <Vazio texto="Nenhum egresso registrado." /> : (
              <ul className="space-y-1 text-sm">{d.egressos.map((e) => (
                <li key={e.id} className="flex flex-wrap items-center gap-2 border-b border-linha py-1">
                  <button className="font-medium text-tec hover:underline" onClick={() => abrirDetalhe(e.oportunidade_id)}>{e.nome}</button>
                  <span>{e.curso} · concluiu em {new Date(`${e.conclusao}T12:00:00`).toLocaleDateString('pt-BR')}</span>
                  {e.consentimento ? <Chip tipo="ok">aceita contato</Chip> : <Chip>sem consentimento</Chip>}
                  {e.interesses.map((i) => <Chip key={i} tipo="tec">{rotulo(i)}</Chip>)}
                  {e.ofertas > 0 && <span className="nota">{e.ofertas} oferta(s)</span>}
                  {d.pode_ofertar && e.consentimento && <button className="btn btn-sec btn-peq" disabled={acao.enviando || !of.curso || !of.coorte} onClick={() => void fazer(async () => {
                    const x = await api.ofertarEgresso(e.id, Number(of.curso), of.coorte, of.forma); return x.duplicada ? 'Já havia oportunidade para este curso e coorte.' : 'Oportunidade criada no CRM.'; })}>Ofertar</button>}
                </li>))}</ul>)}
          </Cartao>
        </div>)}
    </>
  );
}
