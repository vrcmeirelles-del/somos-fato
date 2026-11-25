import { useState, type FormEvent } from 'react';
import { useNavigate } from 'react-router-dom';
import { api } from '../lib/api';

export function Login({ aoEntrar }: { aoEntrar: () => Promise<void> }) {
  const [email, setEmail] = useState('');
  const [senha, setSenha] = useState('');
  const [erro, setErro] = useState('');
  const [enviando, setEnviando] = useState(false);
  const navegar = useNavigate();

  async function enviar(ev: FormEvent) {
    ev.preventDefault();
    setErro(''); setEnviando(true);
    try {
      await api.entrar(email, senha);
      const eu = await api.eu();
      await aoEntrar();
      const primeira = eu.escopos[0];
      navegar(primeira ? `/ies/${primeira.ies_id}/dashboard` : eu.usuario.master ? '/master' : '/sem-acesso');
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
        <form onSubmit={(e) => void enviar(e)} className="cartao-base grid gap-3" noValidate>
          <label className="grid gap-1">E-mail<input id="email" className="campo" type="email" autoComplete="username" required value={email} onChange={(e) => setEmail(e.target.value)} /></label>
          <label className="grid gap-1">Senha<input id="senha" className="campo" type="password" autoComplete="current-password" required value={senha} onChange={(e) => setSenha(e.target.value)} /></label>
          <button className="btn" type="submit" disabled={enviando}>{enviando ? 'Entrando…' : 'Entrar'}</button>
          {erro && <p role="alert" className="text-erro">{erro}</p>}
        </form>
      </main>
    </>
  );
}
