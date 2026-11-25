import { createContext, useContext, useMemo, type ReactNode } from 'react';
import { NavLink, useLocation, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { api } from '../lib/api';
import { rotulo } from '../lib/formato';
import { useCarregar } from '../lib/hooks';
import type { Estrutura, Eu, Papel } from '../lib/tipos';
import { Estado } from './ui';

interface Contexto { eu: Eu; ies: number | null; estrutura: Estrutura | null; tem: (...p: Papel[]) => boolean; recarregarEstrutura: () => void }
const Ctx = createContext<Contexto | null>(null);
export function useSessao(): Contexto {
  const c = useContext(Ctx);
  if (!c) throw new Error('Fora do contexto de sessão');
  return c;
}

const CHAVE_IES = 'm360_ies';
function lerIesGuardada(): number | null { try { return Number(localStorage.getItem(CHAVE_IES)) || null; } catch { return null; } }
function guardarIes(v: number) { try { localStorage.setItem(CHAVE_IES, String(v)); } catch { /* sem storage */ } }

export function Layout({ eu, children }: { eu: Eu; children: ReactNode }) {
  const params = useParams();
  const [busca] = useSearchParams();
  const local = useLocation();
  const navegar = useNavigate();
  const iesUnicas = useMemo(() => [...new Map(eu.escopos.map((e) => [e.ies_id, e.ies_nome])).entries()], [eu]);
  const pedida = Number(params.ies) || Number(busca.get('ies')) || lerIesGuardada();
  const ies = iesUnicas.some(([id]) => id === pedida) ? pedida : (iesUnicas[0]?.[0] ?? null);
  const est = useCarregar(() => (ies ? api.estrutura(ies) : Promise.resolve(null)), [ies]);
  const papeis = est.dados?.papeis ?? [];
  const tem = (...p: Papel[]) => p.some((x) => papeis.includes(x));

  const meusPapeis = eu.escopos.filter((e) => e.ies_id === ies).map((e) => rotulo(e.papel) + (e.curso_nome ? ` (${e.curso_nome})` : ''));
  const links: [string, string][] = [];
  if (ies) {
    links.push([`/ies/${ies}/dashboard`, 'Painel'], [`/ies/${ies}/crm`, 'CRM']);
    for (const [p, n] of [['matriculas', 'Matrículas'], ['propostas', 'Propostas'], ['campanhas', 'Campanhas'], ['academia', 'Academia'], ['configuracoes', 'Configurações']] as const) {
      links.push([`/${p}?ies=${ies}`, n]);
    }
  }
  if (eu.usuario.master) links.push(['/master', 'Master']);

  function trocarIes(v: number) {
    guardarIes(v);
    const rota = local.pathname.match(/^\/ies\/\d+\/(\w+)/)?.[1];
    navegar(rota ? `/ies/${v}/${rota}` : `${local.pathname}?ies=${v}`);
  }
  async function sair() { await api.sair(); navegar('/login'); }

  return (
    <Ctx.Provider value={{ eu, ies, estrutura: est.dados, tem, recarregarEstrutura: () => void est.recarregar() }}>
      <header className="flex flex-wrap items-center justify-between gap-3 bg-marinho px-4 py-4 text-white sm:px-[5vw]">
        <strong>MATRÍCULA 360° <span className="rounded bg-[#ffd166] px-1.5 py-0.5 align-middle text-[0.7rem] text-marinho">REACT</span></strong>
        <div className="flex flex-wrap items-center gap-2.5">
          {iesUnicas.length > 0 && (
            <label className="sr-only" htmlFor="seletor-ies">Instituição</label>
          )}
          {iesUnicas.length > 0 && (
            <select id="seletor-ies" className="campo max-w-[260px] text-texto" value={ies ?? ''} onChange={(e) => trocarIes(Number(e.target.value))}>
              {iesUnicas.map(([id, nome]) => <option key={id} value={id}>{nome}</option>)}
            </select>
          )}
          <span className="text-sm opacity-90">{eu.usuario.nome}{meusPapeis.length ? ` · ${[...new Set(meusPapeis)].join(', ')}` : ''}{eu.usuario.master ? ' · Master' : ''}</span>
          <button type="button" className="btn btn-sec btn-peq" onClick={() => void sair()}>Sair</button>
        </div>
      </header>
      <nav aria-label="Seções" className="flex gap-1 overflow-x-auto bg-[#e5eff9] px-4 sm:px-[5vw]">
        {links.map(([href, nome]) => (
          <NavLink key={href} to={href} end
            className={({ isActive }) => `whitespace-nowrap border-b-[3px] px-2.5 py-3 text-marinho ${isActive && local.pathname === href.split('?')[0] ? 'border-acao font-semibold' : 'border-transparent'}`}>
            {nome}
          </NavLink>
        ))}
      </nav>
      <p className="faixa bg-faixa px-4 py-1.5 text-sm text-[#5c4400] sm:px-[5vw]">Homologação Supabase · Dados sintéticos · IA desativada · Envio externo desativado</p>
      <main className="px-4 py-6 sm:px-[5vw]">
        {ies && !est.dados ? <Estado carregando={est.carregando} erro={est.erro} /> : children}
      </main>
    </Ctx.Provider>
  );
}
