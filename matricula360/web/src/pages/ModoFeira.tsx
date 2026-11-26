import { CloudUpload, Wifi, WifiOff } from 'lucide-react';
import { useCallback, useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { useSessao } from '../components/Layout';
import { Campo, Cartao, Chip, Mensagem, Titulo } from '../components/ui';
import { api } from '../lib/api';
import { aplicarResultado, gravarFila, lerFila, novoId, sha256 } from '../lib/fila';
import { rotulo } from '../lib/formato';
import type { LeadCampo } from '../lib/tipos';

export const TERMO_CAMPO = 'Autorizo a instituição a usar meu nome, e-mail e celular para entrar em contato sobre cursos, processo seletivo e matrícula. '
  + 'Posso pedir a exclusão a qualquer momento. Base legal: consentimento (LGPD, art. 7º, I). Versão campo-1.';

// Modo feira (L17): cadastro rápido que funciona sem internet. Os cadastros ficam no aparelho até a sincronização.
export function ModoFeira() {
  const { estrutura, ies } = useSessao();
  const visita = Number(useParams().visita);
  const [fila, setFila] = useState<LeadCampo[]>(() => lerFila(visita));
  const [online, setOnline] = useState(navigator.onLine);
  const [msg, setMsg] = useState<{ tipo: 'ok' | 'erro'; texto: string } | null>(null);
  const [enviando, setEnviando] = useState(false);
  const vazio = { nome: '', telefone: '', email: '', curso_id: String(estrutura?.cursos[0]?.id ?? ''), ok: false };
  const [f, setF] = useState(vazio);
  const coorte = estrutura?.coortes[0] ?? '';
  const salvar = (nova: LeadCampo[]) => { setFila(nova); gravarFila(visita, nova); };

  const sincronizar = useCallback(async () => {
    const atual = lerFila(visita);
    if (!atual.length || !navigator.onLine) return;
    setEnviando(true);
    try {
      const r = await api.captarCampo(visita, atual.map(({ motivo: _m, ...l }) => l));
      const resto = aplicarResultado(atual, r.rejeitados);
      setFila(resto); gravarFila(visita, resto);
      setMsg({ tipo: resto.length ? 'erro' : 'ok', texto: `Sincronizado: ${r.recebidos} novo(s), ${r.contatos_existentes} já eram contatos, ${r.ja_sincronizados} repetido(s).${resto.length ? ` ${resto.length} precisam de correção.` : ''}` });
    } catch (e) { setMsg({ tipo: 'erro', texto: `Não foi possível sincronizar agora (${(e as Error).message}). Os cadastros continuam guardados no aparelho.` }); }
    finally { setEnviando(false); }
  }, [visita]);

  useEffect(() => {
    const on = () => { setOnline(true); void sincronizar(); }; const off = () => setOnline(false);
    window.addEventListener('online', on); window.addEventListener('offline', off);
    const t = window.setInterval(() => { if (navigator.onLine) void sincronizar(); }, 60_000);
    return () => { window.removeEventListener('online', on); window.removeEventListener('offline', off); window.clearInterval(t); };
  }, [sincronizar]);

  async function adicionar() {
    const l: LeadCampo = { id_local: novoId(), nome: f.nome.trim(), telefone: f.telefone.replace(/\D/g, '') || undefined, email: f.email.trim() || undefined,
      curso_id: Number(f.curso_id), coorte, consentimento: true, consentimento_hash: await sha256(TERMO_CAMPO), capturado_em: new Date().toISOString() };
    salvar([...lerFila(visita), l]); setF({ ...vazio, curso_id: f.curso_id });
    setMsg({ tipo: 'ok', texto: `${l.nome} guardado no aparelho.${navigator.onLine ? '' : ' Sem internet: será enviado quando a conexão voltar.'}` });
    if (navigator.onLine) void sincronizar();
  }
  return (
    <>
      <Titulo titulo="Modo feira" subtitulo="Cadastro rápido de interessados. Funciona sem internet: os dados ficam no aparelho e são enviados assim que houver conexão." />
      <p className="mb-3 text-sm"><Link className="text-tec hover:underline" to={`/ies/${ies}/campo`}>← Voltar às visitas</Link> · {online ? <Chip tipo="ok"><Wifi className="inline h-3 w-3" aria-hidden /> conectado</Chip> : <Chip tipo="pend"><WifiOff className="inline h-3 w-3" aria-hidden /> sem internet</Chip>}
        <Chip tipo={fila.length ? 'pend' : 'ok'}>{fila.length} aguardando envio</Chip></p>
      <Mensagem m={msg} />
      <Cartao titulo="Novo interessado">
        <form className="grid gap-2 sm:grid-cols-2" onSubmit={(e) => { e.preventDefault(); void adicionar(); }}>
          <Campo rotulo="Nome completo" className="sm:col-span-2"><input className="campo text-lg" required minLength={3} autoComplete="off" value={f.nome} onChange={(e) => setF({ ...f, nome: e.target.value })} /></Campo>
          <Campo rotulo="Celular (com DDD)"><input className="campo text-lg" inputMode="tel" autoComplete="off" value={f.telefone} onChange={(e) => setF({ ...f, telefone: e.target.value })} /></Campo>
          <Campo rotulo="E-mail"><input className="campo text-lg" type="email" autoComplete="off" value={f.email} onChange={(e) => setF({ ...f, email: e.target.value })} /></Campo>
          <Campo rotulo="Curso de interesse" className="sm:col-span-2"><select className="campo text-lg" value={f.curso_id} onChange={(e) => setF({ ...f, curso_id: e.target.value })}>
            {estrutura?.cursos.map((c) => <option key={c.id} value={c.id}>{c.nome} · {rotulo(c.turno)}</option>)}</select></Campo>
          <label className="flex items-start gap-2 rounded-lg bg-fundo p-2 text-sm sm:col-span-2"><input type="checkbox" checked={f.ok} onChange={(e) => setF({ ...f, ok: e.target.checked })} />
            <span>O interessado leu e aceitou: “{TERMO_CAMPO}”</span></label>
          <div className="sm:col-span-2"><button className="btn w-full sm:w-auto" disabled={!f.ok || f.nome.trim().length < 3 || (!f.telefone && !f.email)}>Guardar cadastro</button></div>
        </form>
      </Cartao>
      {fila.length > 0 && (
        <Cartao titulo={`Aguardando envio (${fila.length})`} className="mt-4"
          acao={<button className="btn btn-sec btn-peq" disabled={enviando || !online} onClick={() => void sincronizar()}><CloudUpload className="h-3.5 w-3.5" aria-hidden />Enviar agora</button>}>
          <ul className="space-y-1 text-sm">{fila.map((l) => (
            <li key={l.id_local} className="flex flex-wrap items-center gap-2">{l.nome} · {l.telefone ?? l.email}{l.motivo && <Chip tipo="erro">{l.motivo}</Chip>}
              {l.motivo && <button className="btn btn-fantasma btn-peq" onClick={() => salvar(fila.filter((x) => x.id_local !== l.id_local))}>Descartar</button>}</li>))}</ul>
          <p className="nota mt-2">Os dados ficam só neste aparelho até o envio e são apagados dele assim que o banco confirma.</p>
        </Cartao>)}
    </>
  );
}
