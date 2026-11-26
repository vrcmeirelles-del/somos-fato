import { CalendarDays, ClipboardList, ExternalLink, Link2 } from 'lucide-react';
import { useState } from 'react';
import { useSessao } from '../components/Layout';
import { Aviso, Campo, Cartao, Chip, Detalhes, Estado, Mensagem, Titulo, Vazio } from '../components/ui';
import { api } from '../lib/api';
import { rotulo } from '../lib/formato';
import { useAcao, useCarregar } from '../lib/hooks';
import type { ErroApi } from '../lib/supabase';

const TIPOS_EVENTO = ['open_house', 'tour', 'aula_experimental', 'webinar', 'feira', 'visita_escolar', 'outro'];
const semMig = (e: Error | null, n: number) => (e as ErroApi | null)?.codigo === 'PGRST202' ? <Vazio texto={`Disponível após a migração ${n} do banco.`} /> : null;

// Formulários públicos de captação (L1).
export function Formularios() {
  const { ies, estrutura } = useSessao();
  const [recarga, setRecarga] = useState(0);
  const f = useCarregar(() => api.formularios(ies!), [ies, recarga]);
  const ev = useCarregar(() => api.eventos(ies!).catch(() => []), [ies, recarga]);
  const acao = useAcao();
  const fazer = (fn: () => Promise<string>) => acao.executar(async () => { const t = await fn(); setRecarga((n) => n + 1); return t; });
  const vazio = { slug: '', titulo: '', descricao: '', coorte: estrutura?.coortes[0] ?? '', forma_ingresso: 'vestibular', cursos: [] as number[],
    texto_consentimento: 'Autorizo a instituição a usar meus dados de contato para falar sobre o processo seletivo e os cursos de meu interesse, conforme a LGPD. Posso revogar este consentimento a qualquer momento pelo meu link pessoal.', pede_telefone: true };
  const [n, setN] = useState(vazio);
  return (
    <>
      <Titulo titulo="Formulários de captação" subtitulo="Páginas públicas em que o candidato se inscreve sozinho, com consentimento LGPD versionado e atribuição de campanha." />
      {semMig(f.erro, 18) ?? <Estado carregando={f.carregando && !f.dados} erro={f.erro} />}
      <Mensagem m={acao.mensagem} />
      {f.dados && (
        <div className="space-y-4">
          <Aviso>Proteção sem serviço externo: campo-isca, tempo mínimo de preenchimento e limites por origem, formulário e e-mail. A resposta não revela se a pessoa já tem cadastro; o link do portal só é mostrado em cadastro novo.</Aviso>
          <Detalhes titulo="Novo formulário">
            <form className="grid gap-2 sm:grid-cols-3" onSubmit={(e) => { e.preventDefault(); void fazer(async () => { await api.salvarFormulario(ies!, n); setN(vazio); return 'Formulário publicado.'; }); }}>
              <Campo rotulo="Título"><input className="campo" required minLength={3} value={n.titulo} onChange={(e) => setN({ ...n, titulo: e.target.value })} /></Campo>
              <Campo rotulo="Endereço (/f/...)"><input className="campo" required pattern="[a-z0-9][a-z0-9\-]{3,60}" value={n.slug} onChange={(e) => setN({ ...n, slug: e.target.value.toLowerCase() })} /></Campo>
              <Campo rotulo="Coorte"><input className="campo" required pattern="\d{4}\.[12]" value={n.coorte} onChange={(e) => setN({ ...n, coorte: e.target.value })} /></Campo>
              <Campo rotulo="Forma de ingresso"><select className="campo" value={n.forma_ingresso} onChange={(e) => setN({ ...n, forma_ingresso: e.target.value })}>
                {estrutura?.formas_ingresso.map((x) => <option key={x} value={x}>{rotulo(x)}</option>)}</select></Campo>
              <Campo rotulo="Descrição" className="sm:col-span-2"><input className="campo" value={n.descricao} onChange={(e) => setN({ ...n, descricao: e.target.value })} /></Campo>
              <fieldset className="sm:col-span-3 flex flex-wrap gap-x-3 text-sm"><legend className="text-xs font-medium text-suave">Cursos oferecidos</legend>
                {estrutura?.cursos.map((c) => <label key={c.id} className="flex items-center gap-1"><input type="checkbox" checked={n.cursos.includes(c.id)}
                  onChange={(e) => setN({ ...n, cursos: e.target.checked ? [...n.cursos, c.id] : n.cursos.filter((x) => x !== c.id) })} />{c.nome} · {rotulo(c.turno)}</label>)}</fieldset>
              <Campo rotulo="Termo de consentimento (alterar gera nova versão)" className="sm:col-span-3"><textarea className="campo min-h-[70px]" required minLength={40} value={n.texto_consentimento} onChange={(e) => setN({ ...n, texto_consentimento: e.target.value })} /></Campo>
              <div><button className="btn btn-peq" disabled={acao.enviando || !n.cursos.length}>Publicar</button></div>
            </form>
          </Detalhes>
          {!f.dados.length && <Vazio texto="Nenhum formulário publicado." />}
          {f.dados.map((x) => {
            const link = `${location.origin}/f/${x.slug}`;
            const r = x.resultados ?? {};
            return (
              <Cartao key={x.id} titulo={x.titulo} icone={ClipboardList} acao={<Chip tipo={x.ativo ? 'ok' : undefined}>{x.ativo ? 'publicado' : 'desativado'}</Chip>}>
                <p className="text-sm"><a className="inline-flex items-center gap-1 text-tec underline" href={link} target="_blank" rel="noopener noreferrer">{link}<ExternalLink className="h-3 w-3" aria-hidden /></a>
                  <button className="btn btn-fantasma btn-peq ml-2" onClick={() => void navigator.clipboard?.writeText(link)}>Copiar</button></p>
                <p className="nota mt-1">Coorte {x.coorte} · {rotulo(x.forma_ingresso)} · {x.cursos.length} curso(s) · termo v{x.versao_consentimento}</p>
                <p className="mt-2 text-sm">Inscrições criadas: <strong>{r.criada ?? 0}</strong> · já cadastrados: {r.duplicada ?? 0} · robôs bloqueados: {r.isca ?? 0}</p>
                <div className="mt-2 flex flex-wrap items-end gap-2">
                  <Campo rotulo="Inscrever também no evento"><select className="campo" defaultValue="" onChange={(e) => void fazer(async () => {
                    await api.vincularEventoFormulario(x.id, e.target.value ? Number(e.target.value) : null); return 'Vínculo com evento atualizado.'; })}>
                    <option value="">—</option>{(ev.dados ?? []).filter((v) => v.status === 'aberto').map((v) => <option key={v.id} value={v.id}>{v.titulo}</option>)}</select></Campo>
                  <button className="btn btn-sec btn-peq" disabled={acao.enviando} onClick={() => void fazer(async () => { await api.salvarFormulario(ies!, { ativo: !x.ativo }, x.id); return x.ativo ? 'Formulário desativado.' : 'Formulário reativado.'; })}>
                    {x.ativo ? 'Desativar' : 'Reativar'}</button>
                </div>
              </Cartao>);
          })}
        </div>)}
    </>
  );
}

// Eventos e visitas (L7).
export function Eventos({ abrirDetalhe }: { abrirDetalhe: (id: number) => void }) {
  const { ies, tem } = useSessao();
  const [recarga, setRecarga] = useState(0);
  const e = useCarregar(() => api.eventos(ies!), [ies, recarga]);
  const acao = useAcao();
  const fazer = (fn: () => Promise<string>) => acao.executar(async () => { const t = await fn(); setRecarga((n) => n + 1); return t; });
  const vazio = { titulo: '', tipo: 'open_house', inicio: '', fim: '', local: '', online: false, vagas: '' };
  const [n, setN] = useState(vazio);
  return (
    <>
      <Titulo titulo="Eventos e visitas" subtitulo="Open house, tours, aulas experimentais e visitas escolares, com inscrição, presença e conversão." />
      {semMig(e.erro, 20) ?? <Estado carregando={e.carregando && !e.dados} erro={e.erro} />}
      <Mensagem m={acao.mensagem} />
      {e.dados && (
        <div className="space-y-4">
          {tem('gestor') && (
            <Detalhes titulo="Novo evento">
              <form className="grid gap-2 sm:grid-cols-4" onSubmit={(x) => { x.preventDefault(); void fazer(async () => {
                await api.salvarEvento(ies!, { ...n, inicio: new Date(n.inicio).toISOString(), fim: new Date(n.fim).toISOString(), vagas: n.vagas || null }); setN(vazio); return 'Evento criado.'; }); }}>
                <Campo rotulo="Título" className="sm:col-span-2"><input className="campo" required minLength={3} value={n.titulo} onChange={(x) => setN({ ...n, titulo: x.target.value })} /></Campo>
                <Campo rotulo="Tipo"><select className="campo" value={n.tipo} onChange={(x) => setN({ ...n, tipo: x.target.value })}>{TIPOS_EVENTO.map((t) => <option key={t} value={t}>{rotulo(t)}</option>)}</select></Campo>
                <Campo rotulo="Vagas"><input className="campo" type="number" min={1} value={n.vagas} onChange={(x) => setN({ ...n, vagas: x.target.value })} /></Campo>
                <Campo rotulo="Início"><input className="campo" type="datetime-local" required value={n.inicio} onChange={(x) => setN({ ...n, inicio: x.target.value })} /></Campo>
                <Campo rotulo="Fim"><input className="campo" type="datetime-local" required value={n.fim} onChange={(x) => setN({ ...n, fim: x.target.value })} /></Campo>
                <Campo rotulo="Local ou link"><input className="campo" value={n.local} onChange={(x) => setN({ ...n, local: x.target.value })} /></Campo>
                <label className="flex items-end gap-1 pb-2 text-sm"><input type="checkbox" checked={n.online} onChange={(x) => setN({ ...n, online: x.target.checked })} />On-line</label>
                <div><button className="btn btn-peq" disabled={acao.enviando}>Criar evento</button></div>
              </form>
            </Detalhes>)}
          {!e.dados.length && <Vazio texto="Nenhum evento." />}
          {e.dados.map((v) => (
            <Cartao key={v.id} titulo={v.titulo} icone={CalendarDays} acao={<span><Chip>{rotulo(v.tipo)}</Chip><Chip tipo={v.status === 'aberto' ? 'ok' : undefined}>{rotulo(v.status)}</Chip></span>}>
              <p className="nota">{new Date(v.inicio).toLocaleString('pt-BR')} – {new Date(v.fim).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}{v.local ? ` · ${v.local}` : ''}{v.online ? ' · on-line' : ''}</p>
              <p className="mt-1 text-sm">Inscritos <strong>{v.inscritos}</strong>{v.vagas ? ` de ${v.vagas}` : ''} · presentes <strong>{v.presentes}</strong>
                {v.inscritos > 0 && ` (${Math.round((v.presentes / v.inscritos) * 100)}%)`} · presentes que ingressaram <strong>{v.ingressantes_presentes}</strong></p>
              {v.inscricoes.length > 0 && (
                <div className="tabela mt-2"><table>
                  <thead><tr>{['Pessoa', 'Situação', ''].map((h) => <th key={h} scope="col">{h}</th>)}</tr></thead>
                  <tbody>{v.inscricoes.map((i) => (
                    <tr key={i.id}><td>{i.oportunidade_id ? <button className="text-tec hover:underline" onClick={() => abrirDetalhe(i.oportunidade_id!)}>{i.nome}</button> : i.nome}</td>
                      <td><Chip tipo={i.status === 'presente' ? 'ok' : i.status === 'ausente' ? 'erro' : undefined}>{rotulo(i.status === 'inscrito' ? 'inscrito_evento' : i.status)}</Chip></td>
                      <td className="whitespace-nowrap">{i.status === 'inscrito' && <>
                        <button className="btn btn-ok btn-peq" disabled={acao.enviando} onClick={() => void fazer(async () => { await api.checkin(i.id, 'presente'); return 'Presença registrada.'; })}>Presente</button>{' '}
                        <button className="btn btn-sec btn-peq" disabled={acao.enviando} onClick={() => void fazer(async () => { await api.checkin(i.id, 'ausente'); return 'Ausência registrada.'; })}>Ausente</button></>}</td></tr>))}</tbody>
                </table></div>)}
              {tem('gestor') && v.status === 'aberto' && <button className="btn btn-fantasma btn-peq mt-2" disabled={acao.enviando} onClick={() => void fazer(async () => { await api.salvarEvento(ies!, { status: 'encerrado' }, v.id); return 'Evento encerrado.'; })}>
                <Link2 className="h-3.5 w-3.5" aria-hidden />Encerrar inscrições</button>}
            </Cartao>))}
        </div>)}
    </>
  );
}
