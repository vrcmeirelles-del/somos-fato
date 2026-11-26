import { GraduationCap, Loader2, UserPlus } from 'lucide-react';
import { useEffect, useState, type FormEvent } from 'react';
import { api, publico } from '../lib/api';
import { rotulo } from '../lib/formato';
import { useCarregar } from '../lib/hooks';
import { lerSessao } from '../lib/supabase';

// Página pública do convite: a pessoa cria a conta (ou entra com a que já tem) e aceita o acesso à instituição.
export function Convite() {
  const codigo = typeof location !== 'undefined' ? location.hash.replace(/^#/, '') : '';
  const c = useCarregar(async () => { await publico.iniciar(); return publico.convite(codigo); }, [codigo]);
  const [modo, setModo] = useState<'criar' | 'entrar'>('criar');
  const [f, setF] = useState({ nome: '', email: '', senha: '' });
  const [erro, setErro] = useState(''); const [aviso, setAviso] = useState(''); const [enviando, setEnviando] = useState(false);
  const temSessao = !!lerSessao();
  useEffect(() => { document.title = 'Convite · Matrícula 360°'; }, []);
  useEffect(() => { if (c.dados?.nome) setF((x) => ({ ...x, nome: x.nome || c.dados!.nome! })); }, [c.dados]);

  async function aceitar() {
    const r = await api.aceitarConvite(codigo, f.nome || undefined);
    setAviso(`Pronto! Você entrou em ${r.instituicao} como ${rotulo(r.papel).toLowerCase()}. Abrindo o sistema…`);
    setTimeout(() => { location.href = '/'; }, 1500);
  }
  async function enviar(ev: FormEvent) {
    ev.preventDefault(); setErro(''); setAviso(''); setEnviando(true);
    try {
      if (modo === 'criar') {
        if (f.senha.length < 8) throw new Error('A senha precisa ter pelo menos 8 caracteres.');
        const r = await api.cadastrar(f.email.trim(), f.senha);
        if (r === 'confirmar_email') { setAviso('Conta criada. Confirme o e-mail que você vai receber e depois volte a este mesmo link para entrar.'); return; }
      } else {
        await api.entrar(f.email.trim(), f.senha);
      }
      await aceitar();
    } catch (e) { setErro((e as Error).message); } finally { setEnviando(false); }
  }
  const d = c.dados;
  return (
    <div className="min-h-screen bg-fundo">
      <header className="bg-marinho px-4 py-4 text-white"><div className="mx-auto flex max-w-md items-center gap-2"><GraduationCap className="h-5 w-5" aria-hidden />
        <span className="font-semibold">Matrícula 360°</span></div></header>
      <main className="mx-auto max-w-md px-4 py-6">
        {!codigo ? <p>Abra o link completo do convite que você recebeu.</p>
          : c.erro ? <p role="alert" className="text-erro">{c.erro.message}. Peça um novo convite a quem enviou.</p>
          : !d ? <p className="flex items-center gap-2 text-suave"><Loader2 className="h-4 w-4 animate-spin" aria-hidden />Carregando…</p> : (
          <div className="cartao-base space-y-4">
            <h1 className="flex items-center gap-2 text-xl font-semibold text-marinho"><UserPlus className="h-5 w-5" aria-hidden />Convite para {d.instituicao}</h1>
            <p className="text-sm">Perfil: <strong>{rotulo(d.papel)}</strong>{d.alvo ? ` · ${d.alvo}` : ' · toda a instituição'}{d.email ? ` · para ${d.email}` : ''}</p>
            {d.demonstracao && <p className="rounded bg-faixa px-3 py-2 text-xs text-alerta">Ambiente de demonstração e treinamento: todos os dados são fictícios.</p>}
            {temSessao && <button className="btn w-full" disabled={enviando} onClick={() => { setEnviando(true); void aceitar().catch((e: Error) => setErro(e.message)).finally(() => setEnviando(false)); }}>Aceitar com a conta já conectada</button>}
            <div className="flex gap-2 text-sm" role="tablist">
              <button role="tab" aria-selected={modo === 'criar'} className={`btn btn-peq ${modo === 'criar' ? '' : 'btn-sec'}`} onClick={() => setModo('criar')}>Criar minha conta</button>
              <button role="tab" aria-selected={modo === 'entrar'} className={`btn btn-peq ${modo === 'entrar' ? '' : 'btn-sec'}`} onClick={() => setModo('entrar')}>Já tenho conta</button>
            </div>
            <form className="grid gap-3" onSubmit={(e) => void enviar(e)}>
              <label className="grid gap-1 text-sm">Seu nome completo<input className="campo" required minLength={2} autoComplete="name" value={f.nome} onChange={(e) => setF({ ...f, nome: e.target.value })} /></label>
              <label className="grid gap-1 text-sm">E-mail{d.email_fixo ? ' (o mesmo do convite)' : ''}<input className="campo" type="email" required autoComplete="username" value={f.email} onChange={(e) => setF({ ...f, email: e.target.value })} /></label>
              <label className="grid gap-1 text-sm">Senha{modo === 'criar' ? ' (mínimo de 8 caracteres)' : ''}<input className="campo" type="password" required autoComplete={modo === 'criar' ? 'new-password' : 'current-password'} value={f.senha} onChange={(e) => setF({ ...f, senha: e.target.value })} /></label>
              <button className="btn" disabled={enviando}>{enviando ? 'Aguarde…' : modo === 'criar' ? 'Criar conta e aceitar' : 'Entrar e aceitar'}</button>
            </form>
            {erro && <p role="alert" className="text-sm text-erro">{erro}</p>}
            {aviso && <p role="status" className="text-sm text-ok">{aviso}</p>}
            <p className="nota">Convite válido até {new Date(d.expira_em).toLocaleString('pt-BR')}. Seus dados de acesso ficam no Supabase Auth; a instituição só vê seu nome e perfil.</p>
          </div>)}
      </main>
    </div>
  );
}
