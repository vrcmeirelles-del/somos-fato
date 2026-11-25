import { ChevronLeft, ChevronRight, LogOut, Menu, X } from 'lucide-react';
import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { Link, NavLink, useLocation, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { api } from '../lib/api';
import { rotulo } from '../lib/formato';
import { useCarregar } from '../lib/hooks';
import { AMBIENTES, trilha } from '../lib/navegacao';
import type { Estrutura, Eu, Papel } from '../lib/tipos';
import { Estado } from './ui';

export interface Filtros { coorte: string; campus_id: string; curso_id: string; turno: string; modalidade: string }
interface Contexto {
  eu: Eu; ies: number | null; estrutura: Estrutura | null; tem: (...p: Papel[]) => boolean; recarregarEstrutura: () => void;
  filtros: Filtros; setFiltro: (k: keyof Filtros, v: string) => void;
}
const Ctx = createContext<Contexto | null>(null);
export function useSessao(): Contexto {
  const c = useContext(Ctx);
  if (!c) throw new Error('Fora do contexto de sessão');
  return c;
}

const CHAVE_IES = 'm360_ies';
const CHAVE_MENU = 'm360_menu_recolhido';
const ler = (k: string) => { try { return localStorage.getItem(k); } catch { return null; } };
const gravar = (k: string, v: string) => { try { localStorage.setItem(k, v); } catch { /* sem storage */ } };

export function Layout({ eu, children }: { eu: Eu; children: ReactNode }) {
  const params = useParams();
  const [busca, setBusca] = useSearchParams();
  const local = useLocation();
  const navegar = useNavigate();
  const iesUnicas = useMemo(() => [...new Map(eu.escopos.map((e) => [e.ies_id, e.ies_nome])).entries()], [eu]);
  const pedida = Number(params.ies) || Number(busca.get('ies')) || Number(ler(CHAVE_IES)) || null;
  const ies = iesUnicas.some(([id]) => id === pedida) ? pedida : (iesUnicas[0]?.[0] ?? null);
  const est = useCarregar(() => (ies ? api.estrutura(ies) : Promise.resolve(null)), [ies]);
  const papeis = est.dados?.papeis ?? [];
  const tem = (...p: Papel[]) => p.some((x) => papeis.includes(x));
  const [recolhido, setRecolhido] = useState(ler(CHAVE_MENU) === '1');
  const [gaveta, setGaveta] = useState(false);
  useEffect(() => { setGaveta(false); }, [local.pathname]);

  const filtros: Filtros = {
    coorte: busca.get('coorte') ?? est.dados?.coortes[0] ?? '', campus_id: busca.get('campus') ?? '', curso_id: busca.get('curso') ?? '',
    turno: busca.get('turno') ?? '', modalidade: busca.get('modalidade') ?? '',
  };
  const setFiltro = (k: keyof Filtros, v: string) => {
    const nome = { coorte: 'coorte', campus_id: 'campus', curso_id: 'curso', turno: 'turno', modalidade: 'modalidade' }[k];
    const n = new URLSearchParams(busca);
    if (v) n.set(nome, v); else n.delete(nome);
    setBusca(n, { replace: true });
  };

  function trocarIes(v: number) {
    gravar(CHAVE_IES, String(v));
    const rota = local.pathname.match(/^\/ies\/\d+\/([\w-]+)/)?.[1] ?? 'inteligencia';
    navegar(`/ies/${v}/${rota}`);
  }
  async function sair() { await api.sair(); navegar('/login'); }
  const meusPapeis = [...new Set(eu.escopos.filter((e) => e.ies_id === ies).map((e) => rotulo(e.papel) + (e.curso_nome ? ` · ${e.curso_nome}` : '')))];
  const migalhas = trilha(local.pathname);

  const menu = (
    <nav aria-label="Ambientes" className="flex flex-col gap-4 px-3 py-4">
      {AMBIENTES.map((a) => {
        const itens = a.itens.filter((i) => (i.master ? eu.usuario.master : true) && (!i.papeis || tem(...i.papeis)) && (i.master || ies || i.fase));
        if (!itens.length) return null;
        return (
          <div key={a.id}>
            <p className={`mb-1 flex items-center gap-2 px-2 text-[11px] font-semibold uppercase tracking-wider text-white/50 ${recolhido ? 'lg:justify-center' : ''}`} title={a.rotulo}>
              <a.icone className="h-3.5 w-3.5 shrink-0" aria-hidden /><span className={recolhido ? 'lg:sr-only' : ''}>{a.rotulo}</span>
            </p>
            <ul className="space-y-0.5">
              {itens.map((i) => i.rota && (ies || i.master) ? (
                <li key={i.rotulo}>
                  <NavLink to={i.rota(ies ?? 0)} title={i.rotulo}
                    className={({ isActive }) => `flex items-center gap-2.5 rounded-lg px-2 py-2 text-sm transition ${isActive ? 'bg-tec text-white shadow' : 'text-white/80 hover:bg-white/10 hover:text-white'} ${recolhido ? 'lg:justify-center' : ''}`}>
                    <i.icone className="h-4 w-4 shrink-0" aria-hidden /><span className={recolhido ? 'lg:sr-only' : ''}>{i.rotulo}</span>
                  </NavLink>
                </li>
              ) : (
                <li key={i.rotulo}>
                  <span aria-disabled="true" title={`${i.rotulo} — planejado (${i.fase})`}
                    className={`flex cursor-not-allowed items-center gap-2.5 rounded-lg px-2 py-2 text-sm text-white/35 ${recolhido ? 'lg:justify-center' : ''}`}>
                    <i.icone className="h-4 w-4 shrink-0" aria-hidden />
                    <span className={recolhido ? 'lg:sr-only' : ''}>{i.rotulo}</span>
                    {!recolhido && <span className="ml-auto rounded bg-white/10 px-1.5 text-[10px] font-semibold text-white/60">{i.fase}</span>}
                  </span>
                </li>
              ))}
            </ul>
          </div>
        );
      })}
    </nav>
  );

  return (
    <Ctx.Provider value={{ eu, ies, estrutura: est.dados, tem, recarregarEstrutura: () => void est.recarregar(), filtros, setFiltro }}>
      <div className="flex min-h-screen bg-fundo">
        {/* Menu lateral: fixo e recolhível no computador; gaveta no celular/tablet */}
        <aside className={`fixed inset-y-0 left-0 z-40 flex w-72 flex-col bg-marinho text-white transition-transform lg:sticky lg:top-0 lg:h-screen lg:translate-x-0 ${gaveta ? 'translate-x-0' : '-translate-x-full'} ${recolhido ? 'lg:w-[72px]' : 'lg:w-72'}`}>
          <div className="flex h-16 shrink-0 items-center justify-between border-b border-white/10 px-4">
            <Link to={ies ? `/ies/${ies}/inteligencia` : '/'} className="flex items-center gap-2 font-semibold tracking-tight">
              <span className="grid h-8 w-8 place-items-center rounded-lg bg-tec text-xs font-bold">360</span>
              <span className={recolhido ? 'lg:hidden' : ''}>Matrícula 360°</span>
            </Link>
            <button className="rounded p-1 text-white/70 hover:bg-white/10 lg:hidden" aria-label="Fechar menu" onClick={() => setGaveta(false)}><X className="h-5 w-5" /></button>
          </div>
          <div className="flex-1 overflow-y-auto">{menu}</div>
          <button className="hidden items-center justify-center gap-2 border-t border-white/10 py-3 text-xs text-white/60 hover:text-white lg:flex"
            onClick={() => { setRecolhido(!recolhido); gravar(CHAVE_MENU, recolhido ? '0' : '1'); }} aria-label={recolhido ? 'Expandir menu' : 'Recolher menu'}>
            {recolhido ? <ChevronRight className="h-4 w-4" /> : <><ChevronLeft className="h-4 w-4" />Recolher menu</>}
          </button>
        </aside>
        {gaveta && <div className="fixed inset-0 z-30 bg-marinho/50 lg:hidden" onClick={() => setGaveta(false)} aria-hidden />}

        <div className="flex min-w-0 flex-1 flex-col">
          <header className="sticky top-0 z-20 flex h-16 items-center gap-3 border-b border-linha bg-white/95 px-4 backdrop-blur sm:px-6">
            <button className="rounded-lg p-1.5 text-marinho hover:bg-fundo lg:hidden" aria-label="Abrir menu" onClick={() => setGaveta(true)}><Menu className="h-5 w-5" /></button>
            {iesUnicas.length > 0 && (
              <>
                <label className="sr-only" htmlFor="seletor-ies">Instituição</label>
                <select id="seletor-ies" className="campo max-w-[200px] font-medium sm:max-w-[280px]" value={ies ?? ''} onChange={(e) => trocarIes(Number(e.target.value))}>
                  {iesUnicas.map(([id, nome]) => <option key={id} value={id}>{nome}</option>)}
                </select>
              </>
            )}
            <span className="faixa hidden rounded-full bg-faixa px-2.5 py-1 text-[11px] font-semibold uppercase tracking-wide text-alerta md:inline">Homologação · dados sintéticos</span>
            <div className="ml-auto flex items-center gap-3">
              <div className="hidden text-right leading-tight sm:block">
                <p className="text-sm font-medium text-marinho">{eu.usuario.nome}</p>
                <p className="text-xs text-suave">{[...meusPapeis, ...(eu.usuario.master ? ['Master'] : [])].join(' · ')}</p>
              </div>
              <button type="button" className="btn btn-sec btn-peq" onClick={() => void sair()}><LogOut className="h-3.5 w-3.5" aria-hidden />Sair</button>
            </div>
          </header>
          <p className="faixa bg-faixa px-4 py-1 text-[11px] text-alerta md:hidden">Homologação · dados sintéticos · IA e envio externo desativados</p>
          <main className="mx-auto w-full max-w-[1400px] flex-1 px-4 py-5 sm:px-6">
            {migalhas.length > 0 && (
              <nav aria-label="Trilha" className="mb-2 text-xs text-suave">
                <ol className="flex flex-wrap items-center gap-1">
                  <li>{est.dados?.ies.nome ?? 'Plataforma'}</li>
                  {migalhas.map((m) => <li key={m} className="flex items-center gap-1"><ChevronRight className="h-3 w-3" aria-hidden />{m}</li>)}
                </ol>
              </nav>
            )}
            {ies && !est.dados ? <Estado carregando={est.carregando} erro={est.erro} /> : children}
          </main>
          <footer className="border-t border-linha px-6 py-3 text-[11px] text-suave">Matrícula 360° · IA desativada · Envio externo desativado</footer>
        </div>
      </div>
    </Ctx.Provider>
  );
}

// Barra de filtros globais (instituição está no cabeçalho). Campanha depende do módulo de Campanhas (P1).
export function BarraFiltros({ campi, completos = true }: { campi?: { id: number; nome: string }[]; completos?: boolean }) {
  const { estrutura, filtros, setFiltro } = useSessao();
  const cursos = estrutura?.cursos ?? [];
  const turnos = [...new Set(cursos.map((c) => c.turno))];
  const modalidades = [...new Set(cursos.map((c) => c.modalidade))];
  const sel = (id: string, rot: string, k: keyof Filtros, ops: [string, string][], todos: string) => (
    <label className="flex flex-col gap-1 text-[11px] font-medium uppercase tracking-wide text-suave" htmlFor={id}>{rot}
      <select id={id} className="campo min-w-[120px]" value={filtros[k]} onChange={(e) => setFiltro(k, e.target.value)}>
        {todos && <option value="">{todos}</option>}
        {ops.map(([v, r]) => <option key={v} value={v}>{r}</option>)}
      </select>
    </label>
  );
  return (
    <div className="mb-5 flex flex-wrap items-end gap-3 rounded-xl border border-linha bg-white p-3 shadow-cartao" role="group" aria-label="Filtros globais">
      {sel('coorte', 'Coorte', 'coorte', (estrutura?.coortes ?? []).map((c) => [c, c]), '')}
      {completos && campi && sel('filtro-campus', 'Campus', 'campus_id', campi.map((c) => [String(c.id), c.nome]), 'Todos')}
      {sel('filtro-curso', 'Curso', 'curso_id', cursos.map((c) => [String(c.id), `${c.nome} · ${c.turno}`]), 'Todos')}
      {completos && sel('filtro-turno', 'Turno', 'turno', turnos.map((t) => [t, rotulo(t)]), 'Todos')}
      {completos && sel('filtro-modalidade', 'Modalidade', 'modalidade', modalidades.map((m) => [m, rotulo(m)]), 'Todas')}
      <label className="flex flex-col gap-1 text-[11px] font-medium uppercase tracking-wide text-suave">Campanha
        <select className="campo min-w-[120px]" disabled title="Disponível com o módulo de Campanhas (P1)"><option>Módulo P1</option></select>
      </label>
    </div>
  );
}
