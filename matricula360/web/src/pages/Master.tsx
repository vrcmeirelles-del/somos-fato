import { useState } from 'react';
import { Campo, Detalhes, Estado, Mensagem, Titulo } from '../components/ui';
import { api } from '../lib/api';
import { centavos, rotulo } from '../lib/formato';
import { useAcao, useCarregar } from '../lib/hooks';
import type { IesMaster, Papel } from '../lib/tipos';

const PAPEIS: Papel[] = ['gestor', 'reitoria', 'coordenador', 'comercial', 'secretaria', 'financeiro'];

export function Master() {
  const lista = useCarregar(() => api.master.ies(), []);
  const acao = useAcao();
  const [aberta, setAberta] = useState<IesMaster | null>(null);
  const [nome, setNome] = useState(''); const [plano, setPlano] = useState('piloto'); const [campus, setCampus] = useState('Campus Principal'); const [cursos, setCursos] = useState('');

  return (
    <>
      <Titulo titulo="Painel Master" subtitulo="Provisionamento de instituições e concessão de escopos. Sem acesso a candidatos." />
      <p className="nota mb-3">O Master provisiona instituições e concede escopos. Não acessa dados de candidatos sem escopo explícito.</p>
      <Mensagem m={acao.mensagem} />
      <Detalhes titulo="Provisionar instituição">
        <div className="flex flex-wrap items-end gap-2">
          <Campo rotulo="Nome"><input className="campo" maxLength={120} value={nome} onChange={(e) => setNome(e.target.value)} /></Campo>
          <Campo rotulo="Plano"><select className="campo" value={plano} onChange={(e) => setPlano(e.target.value)}>{['piloto', 'essencial', 'completo'].map((p) => <option key={p}>{p}</option>)}</select></Campo>
          <Campo rotulo="Campus"><input className="campo" value={campus} onChange={(e) => setCampus(e.target.value)} /></Campo>
        </div>
        <p className="nota my-2">Cursos: um por linha — nome;turno;modalidade;mensalidade;desconto máximo %</p>
        <textarea className="campo min-h-[90px] w-full" aria-label="Cursos" value={cursos} onChange={(e) => setCursos(e.target.value)} placeholder={'Direito;noturno;presencial;1290,00;30\nAdministração;ead;ead;399,00;40'} />
        <button className="btn mt-2" disabled={acao.enviando} onClick={() => void acao.executar(async () => {
          const lc = cursos.split('\n').map((l) => l.trim()).filter(Boolean).map((l) => {
            const [n, turno, modalidade, mens, desc] = l.split(';').map((x) => x.trim());
            return { nome: n, turno, modalidade, mensalidade_centavos: centavos(mens ?? ''), desconto_max_pct: Number(desc ?? 30) };
          });
          const r = await api.master.provisionar(nome, plano, campus, lc); await lista.recarregar(); return `IES #${r.id} provisionada.`;
        })}>Provisionar</button>
      </Detalhes>
      <Estado carregando={lista.carregando && !lista.dados} erro={lista.erro} />
      <div className="tabela">
        <table>
          <thead><tr>{['IES', 'Plano', 'Status', 'Cursos', 'Usuários', ''].map((c) => <th key={c} scope="col">{c}</th>)}</tr></thead>
          <tbody>{lista.dados?.map((i) => (
            <tr key={i.id}><td>{i.nome}</td><td>{i.plano}</td><td>{i.status}</td><td>{i.cursos}</td><td>{i.usuarios}</td>
              <td><div className="flex flex-wrap gap-1.5">
                <button className="btn btn-peq" onClick={() => setAberta(i)}>Acessos</button>
                <button className="btn btn-sec btn-peq" disabled={acao.enviando} onClick={() => void acao.executar(async () => {
                  await api.master.status(i.id, i.status === 'ativa' ? 'suspensa' : 'ativa'); await lista.recarregar(); return `IES ${i.status === 'ativa' ? 'suspensa' : 'reativada'}.`;
                })}>{i.status === 'ativa' ? 'Suspender' : 'Reativar'}</button>
              </div></td></tr>
          ))}</tbody>
        </table>
      </div>
      {aberta && <Acessos ies={aberta} aoMudar={() => void lista.recarregar()} />}
    </>
  );
}

function Acessos({ ies, aoMudar }: { ies: IesMaster; aoMudar: () => void }) {
  const a = useCarregar(() => api.master.acessos(ies.id), [ies.id]);
  const acao = useAcao();
  const [email, setEmail] = useState(''); const [nome, setNome] = useState(''); const [papel, setPapel] = useState<Papel>('comercial'); const [curso, setCurso] = useState('');
  const fazer = (fn: () => Promise<string>) => acao.executar(async () => { const t = await fn(); await a.recarregar(); aoMudar(); return t; });
  return (
    <section className="mt-8">
      <h2 className="mb-2 text-lg font-semibold">Acessos · {ies.nome}</h2>
      <p className="nota mb-2">A conta é criada por convite no Supabase Auth (Authentication → Users). Aqui o Master concede o escopo a uma conta existente.</p>
      <div className="flex flex-wrap items-end gap-2">
        <Campo rotulo="E-mail"><input className="campo" type="email" value={email} onChange={(e) => setEmail(e.target.value)} /></Campo>
        <Campo rotulo="Nome"><input className="campo" value={nome} onChange={(e) => setNome(e.target.value)} /></Campo>
        <Campo rotulo="Papel"><select className="campo" value={papel} onChange={(e) => setPapel(e.target.value as Papel)}>{PAPEIS.map((p) => <option key={p} value={p}>{rotulo(p)}</option>)}</select></Campo>
        <Campo rotulo="Curso"><select className="campo" value={curso} onChange={(e) => setCurso(e.target.value)}><option value="">Toda a instituição</option>{a.dados?.cursos.map((c) => <option key={c.id} value={c.id}>{c.nome} · {c.turno}</option>)}</select></Campo>
        <button className="btn" disabled={acao.enviando} onClick={() => void fazer(async () => {
          const r = await api.master.conceder(email, nome || email, ies.id, curso ? Number(curso) : null, papel);
          return r.perfil_novo ? 'Escopo concedido e perfil de aplicação criado.' : 'Escopo concedido a usuário existente.';
        })}>Conceder escopo</button>
      </div>
      <Mensagem m={acao.mensagem} />
      <Estado carregando={a.carregando && !a.dados} erro={a.erro} />
      <div className="tabela mt-3">
        <table>
          <thead><tr>{['Usuário', 'Papel', 'Curso', 'Situação', ''].map((c) => <th key={c} scope="col">{c}</th>)}</tr></thead>
          <tbody>{a.dados?.escopos.map((e) => (
            <tr key={e.id}><td>{e.nome}{e.email ? ` (${e.email})` : ''}</td><td>{rotulo(e.papel)}</td><td>{e.curso_nome ?? 'toda a IES'}</td>
              <td>{e.usuario_revogado_em ? 'usuário revogado' : e.revogado_em ? 'escopo revogado' : 'ativo'}</td>
              <td>{!e.revogado_em && !e.usuario_revogado_em && (
                <div className="flex flex-wrap gap-1.5">
                  <button className="btn btn-sec btn-peq" disabled={acao.enviando} onClick={() => void fazer(async () => { await api.master.revogarEscopo(e.id); return 'Escopo revogado.'; })}>Revogar escopo</button>
                  <button className="btn btn-perigo btn-peq" disabled={acao.enviando} onClick={() => {
                    if (!window.confirm(`Revogar o usuário ${e.nome} em todas as instituições?`)) return;
                    void fazer(async () => { await api.master.revogarUsuario(e.usuario_id); return 'Usuário revogado em todas as IES.'; });
                  }}>Revogar usuário</button>
                </div>
              )}</td></tr>
          ))}</tbody>
        </table>
      </div>
    </section>
  );
}
