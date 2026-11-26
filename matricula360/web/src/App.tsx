import { useCallback, useEffect, useState, type ReactNode } from 'react';
import { Navigate, Route, Routes, useParams, useSearchParams } from 'react-router-dom';
import { DetalheOportunidade } from './components/DetalheOportunidade';
import { Layout, useSessao } from './components/Layout';
import { Carregando, Titulo, Vazio } from './components/ui';
import { api, iniciar } from './lib/api';
import { lerSessao } from './lib/supabase';
import type { Eu } from './lib/tipos';
import { Agenda } from './pages/Agenda';
import { Auditoria } from './pages/Auditoria';
import { Campanhas } from './pages/Campanhas';
import { Planejamento } from './pages/Planejamento';
import { Central } from './pages/Central';
import { Configuracoes } from './pages/Configuracoes';
import { Crm } from './pages/Crm';
import { Funis } from './pages/Funis';
import { Intervencoes } from './pages/Intervencoes';
import { Login } from './pages/Login';
import { Master } from './pages/Master';
import { Matriculas } from './pages/Matriculas';
import { Performance } from './pages/Performance';
import { Permissoes } from './pages/Permissoes';
import { Propostas } from './pages/Propostas';

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
      <Route path="/ies/:ies/performance" element={<ExigeIes><Performance /></ExigeIes>} />
      <Route path="/ies/:ies/intervencoes" element={<ExigeIes><Intervencoes abrirDetalhe={abrir} /></ExigeIes>} />
      <Route path="/ies/:ies/planejamento" element={<ExigeIes><Planejamento /></ExigeIes>} />
      <Route path="/ies/:ies/campanhas" element={<ExigeIes><Campanhas /></ExigeIes>} />
      <Route path="/ies/:ies/funis" element={<ExigeIes><Funis /></ExigeIes>} />
      <Route path="/ies/:ies/crm" element={<ExigeIes><Crm abrirDetalhe={abrir} versao={versao} /></ExigeIes>} />
      <Route path="/ies/:ies/agenda" element={<ExigeIes><Agenda abrirDetalhe={abrir} versao={versao} /></ExigeIes>} />
      <Route path="/ies/:ies/matriculas" element={<ExigeIes><Matriculas abrirDetalhe={abrir} /></ExigeIes>} />
      <Route path="/ies/:ies/propostas" element={<ExigeIes><Propostas /></ExigeIes>} />
      <Route path="/ies/:ies/configuracoes" element={<ExigeIes><Configuracoes /></ExigeIes>} />
      <Route path="/ies/:ies/permissoes" element={<ExigeIes><Permissoes /></ExigeIes>} />
      <Route path="/ies/:ies/auditoria" element={<ExigeIes><Auditoria /></ExigeIes>} />
      <Route path="/master" element={eu.usuario.master ? <Master /> : <><Titulo titulo="Acesso restrito ao Master" /></>} />
      <Route path="/ies/:ies/dashboard" element={<Legado para="inteligencia" />} />
      {(['matriculas', 'propostas', 'configuracoes'] as const).map((p) => <Route key={p} path={`/${p}`} element={<Legado para={p} />} />)}
      <Route path="/sem-acesso" element={<ExigeIes><Navigate to={inicio} replace /></ExigeIes>} />
      <Route path="*" element={<Navigate to={inicio} replace />} />
    </Routes>
  );
}
