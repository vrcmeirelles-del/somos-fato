import { CheckCircle2, Circle, Copy, Rocket, RotateCcw, UserPlus } from 'lucide-react';
import { useState } from 'react';
import { useSessao } from '../components/Layout';
import { Campo, Cartao, Chip, Detalhes, Estado, Mensagem, Titulo, Vazio } from '../components/ui';
import { api } from '../lib/api';
import { centavos, dataHora, moeda, rotulo } from '../lib/formato';
import { useAcao, useCarregar } from '../lib/hooks';
import type { ErroApi } from '../lib/supabase';

const PAPEIS = ['gestor', 'reitoria', 'coordenador', 'comercial', 'secretaria', 'financeiro'];
const TURNOS = ['matutino', 'vespertino', 'noturno', 'integral', 'ead'];
const MODALIDADES = ['presencial', 'ead', 'semipresencial'];

// Implantação de cliente: checklist, campus e cursos, convites da equipe; na demonstração, restaurar a carga e convite coletivo.
export function Implantacao() {
  const { ies, recarregarEstrutura } = useSessao();
  const [recarga, setRecarga] = useState(0);
  const r = useCarregar(() => api.implantacao(ies!), [ies, recarga]);
  const conv = useCarregar(() => api.convites(ies!).catch(() => []), [ies, recarga]);
  const acao = useAcao();
  const fazer = (fn: () => Promise<string>) => acao.executar(async () => { const t = await fn(); setRecarga((n) => n + 1); recarregarEstrutura(); return t; });
  const [campus, setCampus] = useState('');
  const vc = { campus_id: '', nome: '', turno: 'noturno', modalidade: 'presencial', mensalidade: '', desconto_max_pct: '30' };
  const [cur, setCur] = useState(vc);
  const vconv = { nome: '', email: '', papel: 'comercial', alvo: '', usos_max: '1', validade_dias: '7' };
  const [cv, setCv] = useState(vconv);
  const [link, setLink] = useState<string | null>(null);
  const d = r.dados;
  return (
    <>
      <Titulo titulo="Implantação" subtitulo="Checklist de implantação, campus e cursos e convites para a equipe entrar no sistema." />
      {(r.erro as ErroApi | null)?.codigo === 'PGRST202' ? <Vazio texto="Disponível após a migração 35 do banco." /> : <Estado carregando={r.carregando && !d} erro={r.erro} />}
      <Mensagem m={acao.mensagem} />
      {d && (
        <div className="space-y-4">
          {d.demonstracao && (
            <Cartao titulo="Ambiente de demonstração e treinamento" icone={RotateCcw}>
              <p className="text-sm">Todos os dados desta instituição são fictícios. Depois de uma demonstração ou de uma turma de treinamento, restaure a carga: os dados de movimento são apagados e recriados; a equipe, os convites e as configurações ficam. Os leads em aberto são distribuídos entre os atendentes comerciais que já entraram.</p>
              {d.pode_gerir && <button className="btn btn-sec btn-peq mt-2" disabled={acao.enviando} onClick={() => { if (window.confirm('Restaurar a demonstração? Todo o movimento atual será apagado e recriado.'))
                void fazer(async () => { const x = await api.restaurarDemo(ies!); return `Demonstração restaurada: ${x.oportunidades} oportunidades recriadas; ${x.atendentes_com_leads} atendente(s) com leads.`; }); }}>
                <RotateCcw className="h-3.5 w-3.5" aria-hidden />Restaurar dados da demonstração</button>}
            </Cartao>)}
          <Cartao titulo={`Checklist de implantação · ${d.concluidos} de ${d.total}`} icone={Rocket}>
            <span className="mb-3 block h-2.5 rounded-full bg-tec-100" role="img" aria-label={`${d.concluidos} de ${d.total} itens concluídos`}>
              <span className="block h-2.5 rounded-full bg-[#257de0]" style={{ width: `${(100 * d.concluidos) / d.total}%` }} /></span>
            <ul className="grid gap-1.5 text-sm md:grid-cols-2">{d.itens.map((i) => (
              <li key={i.item} className="flex items-start gap-2">{i.ok ? <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-ok" aria-label="concluído" /> : <Circle className="mt-0.5 h-4 w-4 shrink-0 text-suave" aria-label="pendente" />}
                <span>{i.item}<span className="nota block">{i.onde}</span></span></li>))}</ul>
          </Cartao>
          <Cartao titulo="Equipe e convites" icone={UserPlus}>
            {d.pode_gerir && (
              <Detalhes titulo="Novo convite">
                <form className="grid gap-2 sm:grid-cols-3" onSubmit={(e) => { e.preventDefault(); void fazer(async () => {
                  const [tipo, id] = cv.alvo.split(':');
                  const x = await api.criarConvite(ies!, { nome: cv.nome || null, email: Number(cv.usos_max) > 1 ? null : cv.email, papel: cv.papel, usos_max: Number(cv.usos_max),
                    validade_dias: Number(cv.validade_dias), campus_id: tipo === 'campus' ? Number(id) : null, curso_id: tipo === 'curso' ? Number(id) : null });
                  setLink(`${location.origin}/convite#${x.codigo}`); setCv(vconv); return 'Convite criado. Copie o link abaixo: ele não será exibido de novo.'; }); }}>
                  <Campo rotulo="Perfil"><select className="campo" value={cv.papel} onChange={(e) => setCv({ ...cv, papel: e.target.value })}>{PAPEIS.map((p) => <option key={p} value={p}>{rotulo(p)}</option>)}</select></Campo>
                  <Campo rotulo="Abrangência"><select className="campo" value={cv.alvo} onChange={(e) => setCv({ ...cv, alvo: e.target.value })}><option value="">Toda a instituição</option>
                    {d.campus.map((c) => <option key={`c${c.id}`} value={`campus:${c.id}`}>Campus {c.nome}</option>)}
                    {d.cursos.map((c) => <option key={`u${c.id}`} value={`curso:${c.id}`}>{c.nome} · {rotulo(c.turno)}</option>)}</select></Campo>
                  {d.demonstracao && <Campo rotulo="Quantas pessoas (convite coletivo)"><input className="campo" type="number" min={1} max={200} value={cv.usos_max} onChange={(e) => setCv({ ...cv, usos_max: e.target.value })} /></Campo>}
                  {Number(cv.usos_max) <= 1 && <>
                    <Campo rotulo="Nome"><input className="campo" value={cv.nome} onChange={(e) => setCv({ ...cv, nome: e.target.value })} /></Campo>
                    <Campo rotulo="E-mail da pessoa"><input className="campo" type="email" required value={cv.email} onChange={(e) => setCv({ ...cv, email: e.target.value })} /></Campo></>}
                  <Campo rotulo="Validade (dias, até 30)"><input className="campo" type="number" min={1} max={30} value={cv.validade_dias} onChange={(e) => setCv({ ...cv, validade_dias: e.target.value })} /></Campo>
                  <div className="sm:col-span-3"><button className="btn btn-peq" disabled={acao.enviando}>Gerar convite</button></div>
                </form>
                <p className="nota mt-1">O sistema não envia e-mail: copie o link e envie pelo seu canal. A pessoa cria a conta (ou entra com a que já tem) e o acesso é liberado com o perfil escolhido.</p>
              </Detalhes>)}
            {link && <p className="mt-2 break-all rounded bg-fundo p-2 text-xs">{link} <button className="btn btn-fantasma btn-peq" onClick={() => void navigator.clipboard?.writeText(link)}><Copy className="h-3 w-3" aria-hidden />Copiar</button></p>}
            <h3 className="mt-3 text-sm font-semibold">Equipe ativa ({d.equipe.length})</h3>
            <ul className="mt-1 grid gap-1 text-sm sm:grid-cols-2">{d.equipe.map((p, i) => <li key={i}>{p.nome} <Chip>{rotulo(p.papel)}</Chip>{p.abrangencia !== 'ies' && <span className="nota"> ({p.abrangencia})</span>}</li>)}</ul>
            {(conv.dados?.length ?? 0) > 0 && (<>
              <h3 className="mt-3 text-sm font-semibold">Convites</h3>
              <ul className="mt-1 space-y-1 text-sm">{conv.dados!.map((c) => (
                <li key={c.id} className="flex flex-wrap items-center gap-2">
                  <span>{c.email ?? `coletivo (${c.usos}/${c.usos_max})`} · {rotulo(c.papel)}{c.alvo ? ` · ${c.alvo}` : ''}</span>
                  <Chip tipo={c.situacao === 'usado' ? 'ok' : c.situacao === 'pendente' ? 'pend' : undefined}>{c.situacao}</Chip>
                  {c.aceito_por && <span className="nota">aceito por {c.aceito_por}</span>}
                  <span className="nota">expira {dataHora(c.expira_em)}</span>
                  {d.pode_gerir && c.situacao === 'pendente' && <button className="btn btn-fantasma btn-peq" disabled={acao.enviando} onClick={() => void fazer(async () => { await api.revogarConvite(c.id); return 'Convite revogado.'; })}>Revogar</button>}
                </li>))}</ul></>)}
          </Cartao>
          <Cartao titulo="Campus e cursos">
            <ul className="space-y-2 text-sm">{d.campus.map((c) => (
              <li key={c.id}><strong>{c.nome}</strong>
                <ul className="ml-4 list-disc">{d.cursos.filter((x) => x.campus_id === c.id).map((x) => <li key={x.id}>{x.nome} · {rotulo(x.turno)} · {rotulo(x.modalidade)} · {moeda(x.mensalidade_centavos)} · desconto máx. {x.desconto_max_pct}%</li>)}</ul></li>))}</ul>
            {d.pode_gerir && (
              <div className="mt-3 grid gap-3 lg:grid-cols-2">
                <form className="flex flex-wrap items-end gap-2" onSubmit={(e) => { e.preventDefault(); void fazer(async () => { await api.salvarCampus(ies!, campus); setCampus(''); return 'Campus cadastrado.'; }); }}>
                  <Campo rotulo="Novo campus"><input className="campo" required minLength={2} value={campus} onChange={(e) => setCampus(e.target.value)} /></Campo>
                  <button className="btn btn-sec btn-peq" disabled={acao.enviando}>Cadastrar campus</button>
                </form>
                <form className="grid gap-2 sm:grid-cols-3" onSubmit={(e) => { e.preventDefault(); void fazer(async () => {
                  await api.salvarCurso(ies!, { campus_id: Number(cur.campus_id), nome: cur.nome, turno: cur.turno, modalidade: cur.modalidade, mensalidade_centavos: centavos(cur.mensalidade), desconto_max_pct: Number(cur.desconto_max_pct) });
                  setCur(vc); return 'Curso cadastrado.'; }); }}>
                  <Campo rotulo="Campus"><select className="campo" required value={cur.campus_id} onChange={(e) => setCur({ ...cur, campus_id: e.target.value })}><option value="">Escolher…</option>{d.campus.map((c) => <option key={c.id} value={c.id}>{c.nome}</option>)}</select></Campo>
                  <Campo rotulo="Curso" className="sm:col-span-2"><input className="campo" required minLength={2} value={cur.nome} onChange={(e) => setCur({ ...cur, nome: e.target.value })} /></Campo>
                  <Campo rotulo="Turno"><select className="campo" value={cur.turno} onChange={(e) => setCur({ ...cur, turno: e.target.value })}>{TURNOS.map((t) => <option key={t} value={t}>{rotulo(t)}</option>)}</select></Campo>
                  <Campo rotulo="Modalidade"><select className="campo" value={cur.modalidade} onChange={(e) => setCur({ ...cur, modalidade: e.target.value })}>{MODALIDADES.map((t) => <option key={t} value={t}>{rotulo(t)}</option>)}</select></Campo>
                  <Campo rotulo="Mensalidade (R$)"><input className="campo" required inputMode="decimal" value={cur.mensalidade} onChange={(e) => setCur({ ...cur, mensalidade: e.target.value })} /></Campo>
                  <Campo rotulo="Desconto máximo (%)"><input className="campo" type="number" min={0} max={100} value={cur.desconto_max_pct} onChange={(e) => setCur({ ...cur, desconto_max_pct: e.target.value })} /></Campo>
                  <div className="sm:col-span-2 self-end"><button className="btn btn-sec btn-peq" disabled={acao.enviando}>Cadastrar curso</button></div>
                </form>
              </div>)}
          </Cartao>
        </div>)}
    </>
  );
}
