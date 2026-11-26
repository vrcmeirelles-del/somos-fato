import { KeyRound, Loader2, ShieldCheck } from 'lucide-react';
import { useEffect, useState, type FormEvent } from 'react';
import { api } from '../lib/api';

// Passo de verificação em duas etapas: pede o código (quem já tem fator) ou conduz o cadastro do aplicativo autenticador.
export function DoisFatores({ modo, aoConcluir, aoSair }: { modo: 'codigo' | 'cadastro'; aoConcluir: () => Promise<void> | void; aoSair: () => void }) {
  const [fator, setFator] = useState<string | null>(null);
  const [qr, setQr] = useState<{ qr: string; segredo: string } | null>(null);
  const [codigo, setCodigo] = useState('');
  const [erro, setErro] = useState('');
  const [enviando, setEnviando] = useState(false);
  useEffect(() => {
    (async () => {
      try {
        if (modo === 'codigo') { const f = (await api.fatores()).find((x) => x.status === 'verified'); setFator(f?.id ?? null); if (!f) setErro('Nenhum aplicativo autenticador encontrado.'); }
        else { const r = await api.cadastrarTotp(); setFator(r.id); setQr(r); }
      } catch (e) { setErro((e as Error).message); }
    })();
  }, [modo]);
  async function enviar(ev: FormEvent) {
    ev.preventDefault();
    if (!fator) return;
    setErro(''); setEnviando(true);
    try { await api.verificarTotp(fator, codigo); await aoConcluir(); } catch (e) { setErro((e as Error).message); setCodigo(''); } finally { setEnviando(false); }
  }
  return (
    <form onSubmit={enviar} className="space-y-3" aria-labelledby="titulo-2fa">
      <h2 id="titulo-2fa" className="flex items-center gap-2 text-xl font-semibold"><ShieldCheck className="h-5 w-5 text-tec" aria-hidden />Verificação em duas etapas</h2>
      {modo === 'cadastro' ? (<>
        <p className="text-sm">A instituição exige a verificação em duas etapas. Instale um aplicativo autenticador (por exemplo, Google Authenticator, Microsoft Authenticator ou 1Password), leia o QR code e digite o código de 6 dígitos.</p>
        {qr ? (<div className="flex flex-col items-start gap-2">
          <img src={qr.qr} alt="QR code para cadastrar o aplicativo autenticador" className="h-44 w-44 rounded border border-linha bg-white p-1" />
          <p className="text-xs">Sem câmera? Digite a chave no aplicativo: <code className="break-all">{qr.segredo}</code></p>
        </div>) : !erro && <p className="flex items-center gap-2 text-suave"><Loader2 className="h-4 w-4 animate-spin" aria-hidden />Preparando…</p>}
      </>) : <p className="text-sm">Abra o aplicativo autenticador e digite o código de 6 dígitos da Matrícula 360°.</p>}
      <label className="block"><span className="mb-1 block text-sm font-medium">Código de 6 dígitos</span>
        <input className="campo w-40 text-center font-mono text-lg tracking-widest" inputMode="numeric" autoComplete="one-time-code" maxLength={6} required pattern="\d{6}"
          value={codigo} onChange={(e) => setCodigo(e.target.value.replace(/\D/g, ''))} autoFocus /></label>
      {erro && <p role="alert" className="text-sm text-erro">{erro}</p>}
      <div className="flex flex-wrap gap-2">
        <button className="btn" disabled={enviando || codigo.length !== 6 || !fator}><KeyRound className="h-4 w-4" aria-hidden />{modo === 'cadastro' ? 'Ativar e entrar' : 'Confirmar'}</button>
        <button type="button" className="btn btn-fantasma" onClick={aoSair}>Sair</button>
      </div>
    </form>
  );
}
