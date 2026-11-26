import { BookOpen, CheckCircle2, ClipboardCheck, GraduationCap, Lightbulb, Target, Theater } from 'lucide-react';
import { useState } from 'react';
import { useSessao } from '../components/Layout';
import { Campo, Cartao, Chip, Detalhes, Estado, Mensagem, Titulo, Vazio } from '../components/ui';
import { api } from '../lib/api';
import { dataHora, rotulo } from '../lib/formato';
import { useAcao, useCarregar } from '../lib/hooks';
import type { ErroApi } from '../lib/supabase';
import type { Academia as TAcademia, Competencia, Rubrica } from '../lib/tipos';

const COMPETENCIAS: Competencia[] = ['comunicacao', 'escuta', 'dominio_tecnico', 'negociacao_etica', 'objecoes', 'registro', 'disciplina_operacional'];
const dt = (d: string) => new Date(`${d.slice(0, 10)}T12:00:00`).toLocaleDateString('pt-BR');
type Fazer = (fn: () => Promise<string>) => Promise<void>;

export function Academia() {
  const { ies } = useSessao();
  const [recarga, setRecarga] = useState(0);
  const a = useCarregar(() => api.academia(ies!), [ies, recarga]);
  const acao = useAcao();
  const fazer: Fazer = (fn) => acao.executar(async () => { const t = await fn(); setRecarga((n) => n + 1); return t; });
  const d = a.dados;
  return (
    <>
      <Titulo titulo="Academia de Captação" subtitulo="Trilhas, roleplay com cenários sintéticos, avaliação humana por rubrica e plano de desenvolvimento individual (PDI)." />
      {(a.erro as ErroApi | null)?.codigo === 'PGRST202' ? <Vazio texto="Disponível após a migração 16 do banco." /> : <Estado carregando={a.carregando && !d} erro={a.erro} />}
      <Mensagem m={acao.mensagem} />
      {d && (
        <div className="space-y-5">
          <p className="rounded-lg bg-tec-50 px-3 py-2 text-sm text-marinho" role="note">{d.aviso}</p>
          <Lacunas d={d} />
          <Trilhas d={d} fazer={fazer} enviando={acao.enviando} />
          <Avaliacoes d={d} fazer={fazer} enviando={acao.enviando} />
          <Pdis d={d} fazer={fazer} enviando={acao.enviando} />
          <Cenarios d={d} fazer={fazer} enviando={acao.enviando} />
          <Rubricas d={d} fazer={fazer} enviando={acao.enviando} />
        </div>
      )}
    </>
  );
}

function Lacunas({ d }: { d: TAcademia }) {
  return (
    <Cartao titulo={`Lacunas e recomendações (MAIM Learning · ${d.regra})`} icone={Lightbulb}>
      {d.lacunas.length ? (
        <ul className="space-y-2">{d.lacunas.map((l, i) => (
          <li key={i} className="rounded-lg border border-linha p-3 text-sm">
            <p><strong>{d.ve_equipe ? `${l.usuario} · ` : ''}{rotulo(l.competencia)}</strong> <Chip tipo="pend">nível {l.nivel} de 4</Chip>{l.pdi_aberto && <Chip tipo="tec">PDI aberto</Chip>}</p>
            <p className="nota">Evolução: {l.historico.map((h) => `${dt(h.em)}: ${h.nivel}`).join(' → ')}</p>
            {l.recomendados.length > 0 && <p className="mt-1">Recomendado: {l.recomendados.map((m) => `${m.titulo} (${m.trilha})${m.concluido ? ' ✓' : ''}`).join(' · ')}</p>}
          </li>))}</ul>
      ) : <p className="nota">Nenhuma lacuna (nível ≤ 2) na avaliação finalizada mais recente.</p>}
    </Cartao>
  );
}

function Trilhas({ d, fazer, enviando }: { d: TAcademia; fazer: Fazer; enviando: boolean }) {
  return (
    <Cartao titulo="Trilhas" icone={BookOpen}>
      {d.trilhas.map((t) => {
        const feitos = t.modulos.filter((m) => m.concluido).length;
        return (
          <Detalhes key={t.id} titulo={`${t.nome} · ${rotulo(t.papel_alvo)} · ${feitos}/${t.modulos.length} concluídos`}>
            {t.descricao && <p className="nota mb-2">{t.descricao}</p>}
            <ol className="space-y-2">{t.modulos.map((m) => (
              <li key={m.id} className="rounded-lg border border-linha p-3 text-sm">
                <p className="font-semibold">{m.ordem}. {m.titulo} <Chip>{rotulo(m.competencia)}</Chip><Chip>{m.carga_minutos} min</Chip></p>
                <p className="mt-1 whitespace-pre-line">{m.conteudo}</p>
                {m.concluido ? <p className="mt-1 flex items-center gap-1 text-ok"><CheckCircle2 className="h-4 w-4" aria-hidden />Concluído</p>
                  : <button className="btn btn-sec btn-peq mt-2" disabled={enviando} onClick={() => void fazer(async () => { await api.concluirModulo(m.id); return 'Módulo concluído.'; })}>Marcar como concluído</button>}
              </li>))}</ol>
          </Detalhes>);
      })}
    </Cartao>
  );
}

function Avaliacoes({ d, fazer, enviando }: { d: TAcademia; fazer: Fazer; enviando: boolean }) {
  const { ies } = useSessao();
  const publicada = d.rubricas.find((r) => r.status === 'publicada');
  const vazio = { avaliado_id: '', cenario_id: '', tipo: 'roleplay', evidencias: '', comentario: '' };
  const [f, setF] = useState(vazio);
  const [niveis, setNiveis] = useState<Record<string, number>>({});
  const nomeCrit = (r: string, id: string) => d.rubricas.flatMap((x) => x.criterios).find((c) => String(c.id) === id)?.competencia ?? r;
  return (
    <Cartao titulo="Avaliações (humanas, por rubrica)" icone={ClipboardCheck}>
      {d.pode_avaliar && publicada && d.equipe && (
        <Detalhes titulo={`Nova avaliação · rubrica ${publicada.nome} v${publicada.versao}`}>
          <form className="space-y-2" onSubmit={(e) => { e.preventDefault(); const completa = publicada.criterios.every((c) => niveis[c.id]);
            void fazer(async () => { const r = await api.salvarAvaliacao(ies!, { ...f, rubrica_id: publicada.id, niveis }, completa);
              setF(vazio); setNiveis({}); return completa ? `Avaliação finalizada (consolidado ${r.consolidado}).` : 'Rascunho salvo: avalie todos os critérios para finalizar.'; }); }}>
            <div className="flex flex-wrap gap-2">
              <Campo rotulo="Atendente"><select className="campo" required value={f.avaliado_id} onChange={(e) => setF({ ...f, avaliado_id: e.target.value })}>
                <option value="">Selecione…</option>{d.equipe.map((u) => <option key={u.id} value={u.id}>{u.nome}</option>)}</select></Campo>
              <Campo rotulo="Tipo"><select className="campo" value={f.tipo} onChange={(e) => setF({ ...f, tipo: e.target.value })}>
                {['roleplay', 'observacao_atendimento'].map((t) => <option key={t} value={t}>{rotulo(t)}</option>)}</select></Campo>
              {f.tipo === 'roleplay' && <Campo rotulo="Cenário sintético"><select className="campo" value={f.cenario_id} onChange={(e) => setF({ ...f, cenario_id: e.target.value })}>
                <option value="">—</option>{d.cenarios.map((c) => <option key={c.id} value={c.id}>{c.titulo}</option>)}</select></Campo>}
            </div>
            <div className="tabela"><table>
              <thead><tr><th scope="col">Critério</th>{[1, 2, 3, 4].map((n) => <th key={n} scope="col">Nível {n}</th>)}</tr></thead>
              <tbody>{publicada.criterios.map((c) => (
                <tr key={c.id}><td><strong>{rotulo(c.competencia)}</strong>{c.peso > 1 && <Chip>peso {c.peso}</Chip>}<span className="block text-xs text-suave">{c.descricao}</span></td>
                  {c.niveis.map((txt, i) => (
                    <td key={i}><label className="flex items-start gap-1 text-xs"><input type="radio" name={`crit-${c.id}`} checked={niveis[c.id] === i + 1}
                      onChange={() => setNiveis({ ...niveis, [c.id]: i + 1 })} />{txt}</label></td>))}</tr>))}</tbody>
            </table></div>
            <Campo rotulo="Evidências observadas (obrigatório)"><textarea className="campo min-h-[70px]" required minLength={10} maxLength={4000} value={f.evidencias} onChange={(e) => setF({ ...f, evidencias: e.target.value })} /></Campo>
            <Campo rotulo="Comentário para o atendente"><textarea className="campo" maxLength={2000} value={f.comentario} onChange={(e) => setF({ ...f, comentario: e.target.value })} /></Campo>
            <button className="btn btn-peq" disabled={enviando}>{publicada.criterios.every((c) => niveis[c.id]) ? 'Finalizar avaliação' : 'Salvar rascunho'}</button>
            <p className="nota">Finalizada, a avaliação não muda mais. O atendente vê a avaliação completa.</p>
          </form>
        </Detalhes>)}
      {d.avaliacoes.length ? (
        <ul className="space-y-2">{d.avaliacoes.map((x) => (
          <li key={x.id} className="rounded-lg border border-linha p-3 text-sm">
            <p className="font-semibold">{x.avaliado} · {rotulo(x.tipo)}{x.cenario ? ` · ${x.cenario}` : ''} <Chip tipo={x.status === 'finalizada' ? 'ok' : 'pend'}>{rotulo(x.status)}</Chip>
              {x.consolidado != null && <Chip tipo="tec">consolidado {x.consolidado} / 4</Chip>}</p>
            <p className="nota">Avaliador: {x.avaliador} · {x.rubrica} · {dataHora(x.finalizada_em ?? x.criado_em)}</p>
            <p className="mt-1">{Object.entries(x.niveis).map(([k, v]) => `${rotulo(nomeCrit(k, k))}: ${v}`).join(' · ')}</p>
            <p className="mt-1"><strong>Evidências:</strong> {x.evidencias}</p>
            {x.comentario && <p><strong>Comentário:</strong> {x.comentario}</p>}
          </li>))}</ul>
      ) : <p className="nota">Nenhuma avaliação.</p>}
    </Cartao>
  );
}

function Pdis({ d, fazer, enviando }: { d: TAcademia; fazer: Fazer; enviando: boolean }) {
  const { ies } = useSessao();
  const vazio = { usuario_id: '', competencia: 'escuta', objetivo: '', acoes: '', prazo: '', reavaliar_em: '', avaliacao_origem: '' };
  const [f, setF] = useState(vazio);
  return (
    <Cartao titulo="Planos de desenvolvimento individual (PDI)" icone={Target}>
      {d.pode_gerir && d.equipe && (
        <Detalhes titulo="Novo PDI">
          <form className="grid gap-2 sm:grid-cols-3" onSubmit={(e) => { e.preventDefault(); void fazer(async () => { await api.salvarPdi(ies!, f); setF(vazio); return 'PDI criado.'; }); }}>
            <Campo rotulo="Atendente"><select className="campo" required value={f.usuario_id} onChange={(e) => setF({ ...f, usuario_id: e.target.value })}>
              <option value="">Selecione…</option>{d.equipe.map((u) => <option key={u.id} value={u.id}>{u.nome}</option>)}</select></Campo>
            <Campo rotulo="Competência"><select className="campo" value={f.competencia} onChange={(e) => setF({ ...f, competencia: e.target.value })}>{COMPETENCIAS.map((c) => <option key={c} value={c}>{rotulo(c)}</option>)}</select></Campo>
            <Campo rotulo="Avaliação de origem"><select className="campo" value={f.avaliacao_origem} onChange={(e) => setF({ ...f, avaliacao_origem: e.target.value })}><option value="">—</option>
              {d.avaliacoes.filter((a) => a.status === 'finalizada' && a.avaliado_id === f.usuario_id).map((a) => <option key={a.id} value={a.id}>{dataHora(a.finalizada_em)} · {a.rubrica}</option>)}</select></Campo>
            <Campo rotulo="Objetivo" className="sm:col-span-3"><input className="campo" required minLength={3} maxLength={400} value={f.objetivo} onChange={(e) => setF({ ...f, objetivo: e.target.value })} /></Campo>
            <Campo rotulo="Ações combinadas" className="sm:col-span-3"><textarea className="campo" required minLength={3} maxLength={2000} value={f.acoes} onChange={(e) => setF({ ...f, acoes: e.target.value })} /></Campo>
            <Campo rotulo="Prazo"><input className="campo" type="date" required value={f.prazo} onChange={(e) => setF({ ...f, prazo: e.target.value })} /></Campo>
            <Campo rotulo="Reavaliar em"><input className="campo" type="date" value={f.reavaliar_em} onChange={(e) => setF({ ...f, reavaliar_em: e.target.value })} /></Campo>
            <div className="flex items-end"><button className="btn btn-peq" disabled={enviando}>Criar PDI</button></div>
          </form>
        </Detalhes>)}
      {d.pdis.length ? (
        <div className="tabela"><table>
          <thead><tr>{['Atendente', 'Competência', 'Objetivo e ações', 'Prazo', 'Reavaliação', 'Status'].map((h) => <th key={h} scope="col">{h}</th>)}</tr></thead>
          <tbody>{d.pdis.map((p) => (
            <tr key={p.id}><td>{p.usuario}{p.meu && <Chip tipo="tec">você</Chip>}</td><td>{rotulo(p.competencia)}</td><td><strong>{p.objetivo}</strong><span className="block text-xs">{p.acoes}</span></td>
              <td>{dt(p.prazo)}</td><td>{p.reavaliar_em ? dt(p.reavaliar_em) : '—'}{p.reavaliacao_vencida && <Chip tipo="erro">vencida</Chip>}</td>
              <td>{p.meu || d.pode_gerir ? <select className="campo text-xs" aria-label={`Status do PDI ${p.objetivo}`} value={p.status} disabled={enviando}
                onChange={(e) => void fazer(async () => { await api.salvarPdi(ies!, { status: e.target.value }, p.id); return 'PDI atualizado.'; })}>
                {['aberto', 'em_andamento', 'concluido', 'cancelado'].map((s) => <option key={s} value={s}>{rotulo(s)}</option>)}</select> : rotulo(p.status)}</td></tr>))}</tbody>
        </table></div>
      ) : <p className="nota">Nenhum PDI.</p>}
    </Cartao>
  );
}

function Cenarios({ d, fazer, enviando }: { d: TAcademia; fazer: Fazer; enviando: boolean }) {
  const { ies } = useSessao();
  const vazio = { titulo: '', perfil_sintetico: '', objetivo: '', objecoes: '' };
  const [f, setF] = useState(vazio);
  return (
    <Cartao titulo="Cenários de roleplay (sintéticos)" icone={Theater}>
      <ul className="mb-3 space-y-2">{d.cenarios.map((c) => (
        <li key={c.id} className="rounded-lg border border-linha p-3 text-sm"><p className="font-semibold">{c.titulo}{c.etapa_base && <Chip>{rotulo(c.etapa_base)}</Chip>}</p>
          <p>{c.perfil_sintetico}</p><p className="nota">Objetivo: {c.objetivo}{c.objecoes ? ` · Objeções: ${c.objecoes}` : ''}</p></li>))}</ul>
      {d.pode_gerir && (
        <Detalhes titulo="Novo cenário">
          <form className="grid gap-2" onSubmit={(e) => { e.preventDefault(); void fazer(async () => { await api.salvarCenario(ies!, f); setF(vazio); return 'Cenário criado.'; }); }}>
            <Campo rotulo="Título"><input className="campo" required minLength={3} value={f.titulo} onChange={(e) => setF({ ...f, titulo: e.target.value })} /></Campo>
            <Campo rotulo="Perfil fictício (sem dados reais)"><textarea className="campo" required minLength={10} value={f.perfil_sintetico} onChange={(e) => setF({ ...f, perfil_sintetico: e.target.value })} /></Campo>
            <Campo rotulo="Objetivo do exercício"><input className="campo" required minLength={3} value={f.objetivo} onChange={(e) => setF({ ...f, objetivo: e.target.value })} /></Campo>
            <Campo rotulo="Objeções a trabalhar"><input className="campo" value={f.objecoes} onChange={(e) => setF({ ...f, objecoes: e.target.value })} /></Campo>
            <button className="btn btn-peq w-fit" disabled={enviando}>Criar cenário</button>
          </form>
        </Detalhes>)}
    </Cartao>
  );
}

function Rubricas({ d, fazer, enviando }: { d: TAcademia; fazer: Fazer; enviando: boolean }) {
  const { ies } = useSessao();
  return (
    <Cartao titulo="Rubricas (versionadas)" icone={GraduationCap}>
      {d.rubricas.map((r) => <RubricaVisao key={r.id} r={r} gerir={d.pode_gerir} temRascunho={d.rubricas.some((x) => x.nome === r.nome && x.status === 'rascunho')}
        fazer={fazer} enviando={enviando} ies={ies!} />)}
    </Cartao>
  );
}

function RubricaVisao({ r, gerir, temRascunho, fazer, enviando, ies }: { r: Rubrica; gerir: boolean; temRascunho: boolean; fazer: Fazer; enviando: boolean; ies: number }) {
  const [crit, setCrit] = useState(r.criterios);
  const edita = gerir && r.status === 'rascunho';
  return (
    <section className="mb-3">
      <p className="font-semibold text-marinho">{r.nome} v{r.versao} <Chip tipo={r.status === 'publicada' ? 'ok' : 'tec'}>{rotulo(r.status)}</Chip></p>
      <div className="tabela mt-1"><table>
        <thead><tr><th scope="col">Competência</th><th scope="col">Descrição</th><th scope="col">Peso</th>{[1, 2, 3, 4].map((n) => <th key={n} scope="col">Nível {n}</th>)}</tr></thead>
        <tbody>{crit.map((c, i) => (
          <tr key={c.id}><td>{rotulo(c.competencia)}</td>
            <td>{edita ? <input className="campo" aria-label={`Descrição de ${c.competencia}`} value={c.descricao} onChange={(e) => setCrit(crit.map((x, j) => (j === i ? { ...x, descricao: e.target.value } : x)))} /> : c.descricao}</td>
            <td>{edita ? <input className="campo w-14" type="number" min={1} max={5} aria-label={`Peso de ${c.competencia}`} value={c.peso} onChange={(e) => setCrit(crit.map((x, j) => (j === i ? { ...x, peso: Number(e.target.value) } : x)))} /> : c.peso}</td>
            {c.niveis.map((n, k) => <td key={k} className="text-xs">{edita ? <input className="campo text-xs" aria-label={`Nível ${k + 1} de ${c.competencia}`} value={n}
              onChange={(e) => setCrit(crit.map((x, j) => (j === i ? { ...x, niveis: x.niveis.map((y, z) => (z === k ? e.target.value : y)) } : x)))} /> : n}</td>)}</tr>))}</tbody>
      </table></div>
      {gerir && r.status === 'publicada' && !temRascunho && <button className="btn btn-sec btn-peq mt-2" disabled={enviando} onClick={() => void fazer(async () => { await api.salvarRubrica(ies, 'nova_versao', r.id); return 'Nova versão em rascunho criada.'; })}>Nova versão</button>}
      {edita && <div className="mt-2 flex gap-2">
        <button className="btn btn-sec btn-peq" disabled={enviando} onClick={() => void fazer(async () => { await api.salvarRubrica(ies, 'salvar', r.id, crit); return 'Rascunho da rubrica salvo.'; })}>Salvar rascunho</button>
        <button className="btn btn-ok btn-peq" disabled={enviando} onClick={() => { if (!window.confirm('Publicar? A versão atual será arquivada; avaliações já feitas mantêm a versão usada.')) return;
          void fazer(async () => { await api.salvarRubrica(ies, 'salvar', r.id, crit); await api.salvarRubrica(ies, 'publicar', r.id); return 'Rubrica publicada.'; }); }}>Salvar e publicar</button>
      </div>}
    </section>
  );
}
