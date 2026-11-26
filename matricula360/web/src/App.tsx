import { useCallback, useEffect, useState, type ReactNode } from 'react';
import { Navigate, Route, Routes, useParams, useSearchParams } from 'react-router-dom';
import { DetalheOportunidade } from './components/DetalheOportunidade';
import { Layout, useSessao } from './components/Layout';
import { Carregando, Titulo, Vazio } from './components/ui';
import { api, iniciar } from './lib/api';
import { lerSessao } from './lib/supabase';
import type { Eu } from './lib/tipos';
import { Academia } from './pages/Academia';
import { Agenda } from './pages/Agenda';
import { Auditoria } from './pages/Auditoria';
import { Campanhas } from './pages/Campanhas';
import { Planejamento } from './pages/Planejamento';
import { Central } from './pages/Central';
import { Configuracoes } from './pages/Configuracoes';
import { Crm } from './pages/Crm';
import { Eventos, Formularios } from './pages/Captacao';
import { Comunicacao, Integracoes } from './pages/Comunicacao';
import { Seletivo } from './pages/Seletivo';
import { Bolsas } from './pages/Bolsas';
import { Rematricula } from './pages/Rematricula';
import { SucessoAluno } from './pages/SucessoAluno';
import { Seguranca } from './pages/Seguranca';
import { CampoCaptacao } from './pages/Campo';
import { ModoFeira } from './pages/ModoFeira';
import { Pesquisas } from './pages/Pesquisas';
import { Automacoes } from './pages/Automacoes';
import { BiExecutivo } from './pages/BiExecutivo';
import { Conversas, EgressosPagina, FinanceiroAlunos, Polos } from './pages/OndaC';
import { Funis } from './pages/Funis';
import { Intervencoes } from './pages/Intervencoes';
import { Login } from './pages/Login';
import { Master } from './pages/Master';
import { Matriculas } from './pages/Matriculas';
import { Performance } from './pages/Performance';
import { Permissoes } from './pages/Permissoes';
import { Propostas } from './pages/Propostas';
import { FormularioPublico, Portal } from './pages/Publico';
import { Recuperacao } from './pages/Recuperacao';
import { Relacionamento } from './pages/Relacionamento';

export function App() {
  const [pronto, setPronto] = useState(false);
  const [erroInicio, setErroInicio] = useState<string | null>(null);
  const [eu, setEu] = useState<Eu | null>(null);
  const carregarEu = useCallback(async () => {
    if (!lerSessao()) { setEu(null); return; }
    try { setEu(await api.eu()); } catch { setEu(null); }
  }, []);
  useEffect(() => {
    iniciar().then(carregarEu).catch((e: Error) => setErroInicio(e.message)).finally(() => setPronto(true));
  }, [carregarEu]);

  // Área pública (formulário de captação e portal do candidato) não depende de login nem de rpc_me.
  if (location.pathname.startsWith('/f/') || location.pathname === '/portal') {
    return <Routes><Route path="/f/:slug" element={<FormularioPublico />} /><Route path="/portal" element={<Portal />} /></Routes>;
  }
  if (erroInicio) return <p role="alert" className="p-6 text-erro">{erroInicio}</p>;
  if (!pronto) return <div className="p-6"><Carregando /></div>;
  return (
    <Routes>
      <Route path="/login" element={<Login aoEntrar={carregarEu} />} />
      <Route path="*" element={eu ? <Autenticado eu={eu} /> : <Navigate to="/login" replace />} />
    </Routes>
  );
}

function Autenticado({ eu }: { eu: Eu }) {
  const [detalhe, setDetalhe] = useState<number | null>(null);
  const [versao, setVersao] = useState(0);
  return (
    <Layout eu={eu}>
      <Rotas eu={eu} abrir={setDetalhe} versao={versao} />
      {detalhe != null && <DetalheOportunidade id={detalhe} aoFechar={() => setDetalhe(null)} aoMudar={() => setVersao((v) => v + 1)} />}
    </Layout>
  );
}

function ExigeIes({ children }: { children: ReactNode }) {
  const { ies } = useSessao();
  return ies ? <>{children}</> : <><Titulo titulo="Sem instituição" /><Vazio texto="Seu usuário não possui escopo em nenhuma instituição." detalhe="Peça ao Master a concessão de escopo." /></>;
}

// Endereços da versão anterior continuam válidos.
function Legado({ para }: { para: string }) {
  const { ies } = useParams();
  const [busca] = useSearchParams();
  const alvo = ies ?? busca.get('ies');
  return <Navigate to={alvo ? `/ies/${alvo}/${para}` : '/'} replace />;
}

function Rotas({ eu, abrir, versao }: { eu: Eu; abrir: (id: number) => void; versao: number }) {
  const { ies } = useSessao();
  const inicio = ies ? `/ies/${ies}/inteligencia` : eu.usuario.master ? '/master' : '/sem-acesso';
  return (
    <Routes>
      <Route path="/ies/:ies/inteligencia" element={<ExigeIes><Central /></ExigeIes>} />
      <Route path="/ies/:ies/bi-executivo" element={<ExigeIes><BiExecutivo /></ExigeIes>} />
      <Route path="/ies/:ies/performance" element={<ExigeIes><Performance /></ExigeIes>} />
      <Route path="/ies/:ies/conversas" element={<ExigeIes><Conversas abrirDetalhe={abrir} /></ExigeIes>} />
      <Route path="/ies/:ies/financeiro" element={<ExigeIes><FinanceiroAlunos abrirDetalhe={abrir} /></ExigeIes>} />
      <Route path="/ies/:ies/polos" element={<ExigeIes><Polos /></ExigeIes>} />
      <Route path="/ies/:ies/egressos" element={<ExigeIes><EgressosPagina abrirDetalhe={abrir} /></ExigeIes>} />
      <Route path="/ies/:ies/pesquisas" element={<ExigeIes><Pesquisas /></ExigeIes>} />
      <Route path="/ies/:ies/intervencoes" element={<ExigeIes><Intervencoes abrirDetalhe={abrir} /></ExigeIes>} />
      <Route path="/ies/:ies/planejamento" element={<ExigeIes><Planejamento /></ExigeIes>} />
      <Route path="/ies/:ies/campanhas" element={<ExigeIes><Campanhas /></ExigeIes>} />
      <Route path="/ies/:ies/funis" element={<ExigeIes><Funis /></ExigeIes>} />
      <Route path="/ies/:ies/formularios" element={<ExigeIes><Formularios /></ExigeIes>} />
      <Route path="/ies/:ies/campo" element={<ExigeIes><CampoCaptacao /></ExigeIes>} />
      <Route path="/ies/:ies/campo/:visita/feira" element={<ExigeIes><ModoFeira /></ExigeIes>} />
      <Route path="/ies/:ies/eventos" element={<ExigeIes><Eventos abrirDetalhe={abrir} /></ExigeIes>} />
      <Route path="/ies/:ies/comunicacao" element={<ExigeIes><Comunicacao /></ExigeIes>} />
      <Route path="/ies/:ies/seletivo" element={<ExigeIes><Seletivo abrirDetalhe={abrir} /></ExigeIes>} />
      <Route path="/ies/:ies/integracoes" element={<ExigeIes><Integracoes /></ExigeIes>} />
      <Route path="/ies/:ies/crm" element={<ExigeIes><Crm abrirDetalhe={abrir} versao={versao} /></ExigeIes>} />
      <Route path="/ies/:ies/agenda" element={<ExigeIes><Agenda abrirDetalhe={abrir} versao={versao} /></ExigeIes>} />
      <Route path="/ies/:ies/recuperacao" element={<ExigeIes><Recuperacao abrirDetalhe={abrir} /></ExigeIes>} />
      <Route path="/ies/:ies/academia" element={<ExigeIes><Academia /></ExigeIes>} />
      <Route path="/ies/:ies/relacionamento" element={<ExigeIes><Relacionamento /></ExigeIes>} />
      <Route path="/ies/:ies/sucesso" element={<ExigeIes><SucessoAluno abrirDetalhe={abrir} /></ExigeIes>} />
      <Route path="/ies/:ies/rematricula" element={<ExigeIes><Rematricula abrirDetalhe={abrir} /></ExigeIes>} />
      <Route path="/ies/:ies/matriculas" element={<ExigeIes><Matriculas abrirDetalhe={abrir} /></ExigeIes>} />
      <Route path="/ies/:ies/propostas" element={<ExigeIes><Propostas /></ExigeIes>} />
      <Route path="/ies/:ies/bolsas" element={<ExigeIes><Bolsas abrirDetalhe={abrir} /></ExigeIes>} />
      <Route path="/ies/:ies/configuracoes" element={<ExigeIes><Configuracoes /></ExigeIes>} />
      <Route path="/ies/:ies/permissoes" element={<ExigeIes><Permissoes /></ExigeIes>} />
      <Route path="/ies/:ies/automacoes" element={<ExigeIes><Automacoes /></ExigeIes>} />
      <Route path="/ies/:ies/seguranca" element={<ExigeIes><Seguranca /></ExigeIes>} />
      <Route path="/ies/:ies/auditoria" element={<ExigeIes><Auditoria /></ExigeIes>} />
      <Route path="/master" element={eu.usuario.master ? <Master /> : <><Titulo titulo="Acesso restrito ao Master" /></>} />
      <Route path="/ies/:ies/dashboard" element={<Legado para="inteligencia" />} />
      {(['matriculas', 'propostas', 'configuracoes'] as const).map((p) => <Route key={p} path={`/${p}`} element={<Legado para={p} />} />)}
      <Route path="/sem-acesso" element={<ExigeIes><Navigate to={inicio} replace /></ExigeIes>} />
      <Route path="*" element={<Navigate to={inicio} replace />} />
    </Routes>
  );
}
