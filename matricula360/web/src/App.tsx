import { useCallback, useEffect, useState, type ReactNode } from 'react';
import { Navigate, Route, Routes, useLocation } from 'react-router-dom';
import { DetalheOportunidade } from './components/DetalheOportunidade';
import { Layout, useSessao } from './components/Layout';
import { api, iniciar } from './lib/api';
import { lerSessao } from './lib/supabase';
import type { Eu } from './lib/tipos';
import { Backlog } from './pages/Backlog';
import { Configuracoes } from './pages/Configuracoes';
import { Crm } from './pages/Crm';
import { Login } from './pages/Login';
import { Master } from './pages/Master';
import { Matriculas } from './pages/Matriculas';
import { Painel } from './pages/Painel';
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
  if (!pronto) return <p className="nota p-6">Carregando…</p>;
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
  const abrir = (id: number) => setDetalhe(id);
  return (
    <Layout eu={eu}>
      <Rotas eu={eu} abrir={abrir} versao={versao} />
      {detalhe != null && <DetalheOportunidade id={detalhe} aoFechar={() => setDetalhe(null)} aoMudar={() => setVersao((v) => v + 1)} />}
    </Layout>
  );
}

function ExigeIes({ children }: { children: ReactNode }) {
  const { ies } = useSessao();
  return ies ? <>{children}</> : <><h1 className="mb-3 text-2xl font-bold">Sem instituição</h1><p>Seu usuário não possui escopo em nenhuma instituição.</p></>;
}

function Rotas({ eu, abrir, versao }: { eu: Eu; abrir: (id: number) => void; versao: number }) {
  const { ies } = useSessao();
  const local = useLocation();
  const inicio = ies ? `/ies/${ies}/dashboard` : eu.usuario.master ? '/master' : '/sem-acesso';
  return (
    <Routes location={local}>
      <Route path="/ies/:ies/dashboard" element={<ExigeIes><Painel abrirDetalhe={abrir} /></ExigeIes>} />
      <Route path="/ies/:ies/crm" element={<ExigeIes><Crm abrirDetalhe={abrir} versao={versao} /></ExigeIes>} />
      <Route path="/matriculas" element={<ExigeIes><Matriculas abrirDetalhe={abrir} /></ExigeIes>} />
      <Route path="/propostas" element={<ExigeIes><Propostas /></ExigeIes>} />
      <Route path="/configuracoes" element={<ExigeIes><Configuracoes /></ExigeIes>} />
      <Route path="/campanhas" element={<Backlog titulo="Campanhas" itens={['Cadastro de campanhas, canais e metas por campanha', 'Atribuição de origem e custo por oportunidade', 'Integrações Meta/Google/TikTok (desligadas por padrão; exigem autorização)']} />} />
      <Route path="/academia" element={<Backlog titulo="Academia" itens={['Trilhas por competência (SDR, Closer, Farmer adaptados à educação)', 'Scripts, rubricas e reavaliação', 'PDI do atendente e registro de treinamento']} />} />
      <Route path="/master" element={eu.usuario.master ? <Master /> : <h1 className="text-2xl font-bold">Acesso restrito ao Master</h1>} />
      <Route path="/sem-acesso" element={<ExigeIes><Navigate to={inicio} replace /></ExigeIes>} />
      <Route path="*" element={<Navigate to={inicio} replace />} />
    </Routes>
  );
}
