import qrcode from 'qrcode-generator';
import { MapPin, QrCode, School, WifiOff } from 'lucide-react';
import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useSessao } from '../components/Layout';
import { Campo as CampoForm, Cartao, Chip, Detalhes, Estado, Mensagem, Titulo, Vazio } from '../components/ui';
import { api } from '../lib/api';
import { rotulo } from '../lib/formato';
import { useAcao, useCarregar } from '../lib/hooks';
import type { ErroApi } from '../lib/supabase';
import type { Visita } from '../lib/tipos';

const TIPOS = ['visita', 'palestra', 'feira', 'aula_aberta'];
export function qrSvg(texto: string): string {
  const q = qrcode(0, 'M'); q.addData(texto); q.make();
  return q.createSvgTag({ cellSize: 4, margin: 2, scalable: true });
}

// Captação em campo (L17): escolas, visitas e feiras, QR code para inscrição pelo celular do aluno e modo feira sem internet.
export function CampoCaptacao() {
  const { ies } = useSessao();
  const [recarga, setRecarga] = useState(0);
  const r = useCarregar(() => api.campo(ies!), [ies, recarga]);
  const forms = useCarregar(() => api.formularios(ies!).catch(() => []), [ies]);
  const acao = useAcao();
  const fazer = (fn: () => Promise<string>) => acao.executar(async () => { const t = await fn(); setRecarga((n) => n + 1); return t; });
  const ve = { nome: '', rede: 'publica', cidade: '', uf: '', inep: '', contato: '' };
  const [e, setE] = useState(ve);
  const vv = { titulo: '', tipo: 'visita', data: '', escola_id: '', publico_estimado: '', campanha: '' };
  const [v, setV] = useState(vv);
  const d = r.dados;
  return (
    <>
      <Titulo titulo="Escolas, visitas e feiras" subtitulo="Captação em campo: agenda de visitas, QR code para inscrição pelo celular do aluno e modo feira que funciona sem internet." />
      {(r.erro as ErroApi | null)?.codigo === 'PGRST202' ? <Vazio texto="Disponível após a migração 27 do banco." /> : <Estado carregando={r.carregando && !d} erro={r.erro} />}
      <Mensagem m={acao.mensagem} />
      {d && (
        <div className="space-y-4">
          {d.pode_registrar && (
            <div className="grid gap-3 lg:grid-cols-2">
              <Detalhes titulo="Nova escola">
                <form className="grid gap-2 sm:grid-cols-2" onSubmit={(x) => { x.preventDefault(); void fazer(async () => { await api.salvarEscola(ies!, e); setE(ve); return 'Escola cadastrada.'; }); }}>
                  <CampoForm rotulo="Nome" className="sm:col-span-2"><input className="campo" required minLength={3} value={e.nome} onChange={(x) => setE({ ...e, nome: x.target.value })} /></CampoForm>
                  <CampoForm rotulo="Rede"><select className="campo" value={e.rede} onChange={(x) => setE({ ...e, rede: x.target.value })}><option value="publica">Pública</option><option value="privada">Privada</option></select></CampoForm>
                  <CampoForm rotulo="INEP (opcional)"><input className="campo" inputMode="numeric" pattern="\d{8}" value={e.inep} onChange={(x) => setE({ ...e, inep: x.target.value })} /></CampoForm>
                  <CampoForm rotulo="Cidade"><input className="campo" required value={e.cidade} onChange={(x) => setE({ ...e, cidade: x.target.value })} /></CampoForm>
                  <CampoForm rotulo="UF"><input className="campo" required maxLength={2} value={e.uf} onChange={(x) => setE({ ...e, uf: x.target.value.toUpperCase() })} /></CampoForm>
                  <CampoForm rotulo="Contato institucional (cargo, telefone da escola)" className="sm:col-span-2"><input className="campo" value={e.contato} onChange={(x) => setE({ ...e, contato: x.target.value })} /></CampoForm>
                  <div><button className="btn btn-peq" disabled={acao.enviando}>Cadastrar escola</button></div>
                </form>
              </Detalhes>
              <Detalhes titulo="Nova visita, palestra ou feira">
                <form className="grid gap-2 sm:grid-cols-2" onSubmit={(x) => { x.preventDefault(); void fazer(async () => {
                  const res = await api.salvarVisita(ies!, { ...v, escola_id: v.escola_id || null, publico_estimado: v.publico_estimado || null, campanha: v.campanha || null }); setV(vv); return `Visita agendada (código ${res.codigo}).`; }); }}>
                  <CampoForm rotulo="Título" className="sm:col-span-2"><input className="campo" required minLength={3} value={v.titulo} onChange={(x) => setV({ ...v, titulo: x.target.value })} /></CampoForm>
                  <CampoForm rotulo="Tipo"><select className="campo" value={v.tipo} onChange={(x) => setV({ ...v, tipo: x.target.value })}>{TIPOS.map((t) => <option key={t} value={t}>{rotulo(t)}</option>)}</select></CampoForm>
                  <CampoForm rotulo="Data"><input className="campo" type="date" required value={v.data} onChange={(x) => setV({ ...v, data: x.target.value })} /></CampoForm>
                  <CampoForm rotulo="Escola (opcional)"><select className="campo" value={v.escola_id} onChange={(x) => setV({ ...v, escola_id: x.target.value })}><option value="">Sem escola</option>
                    {d.escolas.filter((s) => s.ativa).map((s) => <option key={s.id} value={s.id}>{s.nome} · {s.cidade}</option>)}</select></CampoForm>
                  <CampoForm rotulo="Público estimado"><input className="campo" type="number" min={0} value={v.publico_estimado} onChange={(x) => setV({ ...v, publico_estimado: x.target.value })} /></CampoForm>
                  <CampoForm rotulo="Código da campanha (opcional)"><input className="campo" value={v.campanha} onChange={(x) => setV({ ...v, campanha: x.target.value })} /></CampoForm>
                  <div className="sm:col-span-2"><button className="btn btn-peq" disabled={acao.enviando}>Agendar</button></div>
                </form>
              </Detalhes>
            </div>)}
          <Cartao titulo="Visitas e feiras" icone={MapPin}>
            {!d.visitas.length ? <Vazio texto="Nenhuma visita agendada." /> : <div className="space-y-2">{d.visitas.map((x) => <LinhaVisita key={x.id} x={x} ies={ies!} slugs={(forms.dados ?? []).filter((f) => f.ativo).map((f) => ({ slug: f.slug, titulo: f.titulo }))} podeRegistrar={d.pode_registrar} />)}</div>}
          </Cartao>
          <Cartao titulo="Escolas" icone={School}>
            {!d.escolas.length ? <Vazio texto="Nenhuma escola cadastrada." /> : (
              <div className="tabela" tabIndex={0} role="region" aria-label="Tabela com rolagem horizontal"><table><thead><tr><th>Escola</th><th>Rede</th><th>Cidade</th><th>Visitas realizadas</th><th>Leads</th><th>Ingressos</th></tr></thead>
                <tbody>{d.escolas.map((s) => <tr key={s.id}><td>{s.nome}{s.inep && <span className="nota"> · INEP {s.inep}</span>}</td><td>{rotulo(s.rede)}</td><td>{s.cidade}/{s.uf}</td><td>{s.visitas}</td><td>{s.leads}</td><td>{s.ingressos}</td></tr>)}</tbody></table></div>)}
          </Cartao>
        </div>)}
    </>
  );
}

function LinhaVisita({ x, ies, slugs, podeRegistrar }: { x: Visita; ies: number; slugs: { slug: string; titulo: string }[]; podeRegistrar: boolean }) {
  const [slug, setSlug] = useState(slugs[0]?.slug ?? '');
  const url = slug ? `${location.origin}/f/${slug}?v=${x.codigo}` : '';
  return (
    <div className="rounded-lg border border-linha p-3 text-sm">
      <p className="font-medium">{x.titulo} · {rotulo(x.tipo)} · {new Date(`${x.data}T12:00:00`).toLocaleDateString('pt-BR')}
        <Chip tipo={x.status === 'realizada' ? 'ok' : x.status === 'planejada' ? 'tec' : undefined}>{rotulo(x.status)}</Chip></p>
      <p className="nota">{x.escola ?? 'Sem escola'} · {x.responsavel ?? '—'}{x.campanha ? ` · campanha ${x.campanha}` : ''} · código {x.codigo}</p>
      <p>Leads {x.leads} · inscritos em diante {x.inscritos} · ingressos {x.ingressos}{x.publico_estimado ? ` · público estimado ${x.publico_estimado}` : ''}</p>
      {podeRegistrar && x.status !== 'cancelada' && (
        <div className="mt-2 flex flex-wrap items-end gap-2">
          <Link className="btn btn-peq" to={`/ies/${ies}/campo/${x.id}/feira`}><WifiOff className="h-3.5 w-3.5" aria-hidden />Modo feira</Link>
          {slugs.length > 0 && <details><summary className="btn btn-sec btn-peq cursor-pointer list-none"><QrCode className="h-3.5 w-3.5" aria-hidden />QR code para inscrição</summary>
            <div className="mt-2 rounded-lg border border-linha p-2">
              <CampoForm rotulo="Formulário"><select className="campo" value={slug} onChange={(e) => setSlug(e.target.value)}>{slugs.map((s) => <option key={s.slug} value={s.slug}>{s.titulo}</option>)}</select></CampoForm>
              {url && <><div className="mt-2 w-48" role="img" aria-label={`QR code para ${url}`} dangerouslySetInnerHTML={{ __html: qrSvg(url) }} /><p className="break-all text-xs">{url}</p></>}
            </div></details>}
        </div>)}
    </div>
  );
}
