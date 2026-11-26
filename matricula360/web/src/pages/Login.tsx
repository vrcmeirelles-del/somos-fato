import { useEffect, useState, type FormEvent } from 'react';
import { useNavigate } from 'react-router-dom';
import { DoisFatores } from '../components/DoisFatores';
import { api } from '../lib/api';
import { lerSessao, type ErroApi } from '../lib/supabase';
import type { Eu } from '../lib/tipos';

export function Login({ aoEntrar }: { aoEntrar: () => Promise<void> }) {
  const [email, setEmail] = useState('');
  const [senha, setSenha] = useState('');
  const [erro, setErro] = useState('');
  const [enviando, setEnviando] = useState(false);
  const navegar = useNavigate();
  const [etapa2fa, setEtapa2fa] = useState<'codigo' | 'cadastro' | null>(null);
  const modo2fa = (e: unknown) => ((e as ErroApi).codigo === 'M3601' ? 'codigo' : (e as ErroApi).codigo === 'M3602' ? 'cadastro' : null);
  const seguir = async (eu: Eu) => {
    await aoEntrar();
    const primeira = eu.escopos[0];
    navegar(primeira ? `/ies/${primeira.ies_id}/inteligencia` : eu.usuario.master ? '/master' : '/sem-acesso');
  };
  // Sessão aberta, mas aguardando a segunda etapa (ex.: recarregou a página): retoma o passo pendente.
  useEffect(() => {
    if (!lerSessao()) return;
    api.eu().then(seguir).catch((e) => setEtapa2fa(modo2fa(e)));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function enviar(ev: FormEvent) {
    ev.preventDefault();
    setErro(''); setEnviando(true);
    try {
      await api.entrar(email, senha);
      let eu;
      try {
        eu = await api.eu();
      } catch (e) {
        const m = modo2fa(e);
        if (m) { setEtapa2fa(m); return; }
        // Credenciais válidas no Supabase Auth, mas sem perfil/escopo no sistema (ou revogado).
        await api.sair();
        if ((e as { status?: number }).status === 403) throw new Error('Login aceito, mas sua conta ainda não tem acesso liberado ao sistema. Peça ao Master a concessão de escopo.');
        throw e;
      }
      await seguir(eu);
    } catch (e) {
      setErro((e as Error).message);
    } finally {
      setEnviando(false);
    }
  }

  return (
    <>
      <header className="bg-marinho px-4 py-4 text-white sm:px-[5vw]"><strong>MATRÍCULA 360° | HOMOLOGAÇÃO</strong></header>
      <main className="mx-auto max-w-md px-4 py-8">
        <h1 className="mb-3 text-3xl font-bold">Entrar</h1>
        <p className="mb-4 rounded-lg bg-faixa px-3.5 py-2.5">Homologação conectada ao Supabase, com dados <strong>sintéticos</strong>. Não insira dados reais de candidatos.</p>
        {etapa2fa ? <div className="cartao-base"><DoisFatores modo={etapa2fa} aoConcluir={async () => seguir(await api.eu())} aoSair={() => { void api.sair(); setEtapa2fa(null); }} /></div> : (
        <form onSubmit={(e) => void enviar(e)} className="cartao-base grid gap-3" noValidate>
          <label className="grid gap-1">E-mail<input id="email" className="campo" type="email" autoComplete="username" required value={email} onChange={(e) => setEmail(e.target.value)} /></label>
          <label className="grid gap-1">Senha<input id="senha" className="campo" type="password" autoComplete="current-password" required value={senha} onChange={(e) => setSenha(e.target.value)} /></label>
          <button className="btn" type="submit" disabled={enviando}>{enviando ? 'Entrando…' : 'Entrar'}</button>
          {erro && <p role="alert" className="text-erro">{erro}</p>}
        </form>)}
      </main>
    </>
  );
}
