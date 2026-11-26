import { ShieldCheck } from 'lucide-react';
import { useState } from 'react';
import { DoisFatores } from '../components/DoisFatores';
import { useSessao } from '../components/Layout';
import { Aviso, Cartao, Chip, Estado, Mensagem, Titulo, Vazio } from '../components/ui';
import { api } from '../lib/api';
import { useAcao, useCarregar } from '../lib/hooks';
import type { ErroApi } from '../lib/supabase';

// Verificação em duas etapas: a própria conta (todos) e a exigência para a equipe da IES (gestor).
export function Seguranca() {
  const { ies, tem } = useSessao();
  const [recarga, setRecarga] = useState(0);
  const conta = useCarregar(async () => ({ s: await api.segurancaConta(), f: await api.fatores() }), [recarga]);
  const equipe = useCarregar(() => (tem('gestor') ? api.situacao2fa(ies!) : Promise.resolve(null)), [ies, recarga]);
  const acao = useAcao();
  const [cadastrando, setCadastrando] = useState(false);
  const fazer = (fn: () => Promise<string>) => acao.executar(async () => { const t = await fn(); setRecarga((n) => n + 1); return t; });
  const d = conta.dados;
  const verificado = d?.f.find((f) => f.status === 'verified');
  return (
    <>
      <Titulo titulo="Verificação em duas etapas" subtitulo="Código de um aplicativo autenticador além da senha (TOTP do Supabase Auth, sem custo)." />
      {(conta.erro as ErroApi | null)?.codigo === 'PGRST202' ? <Vazio texto="Disponível após a migração 26 do banco." /> : <Estado carregando={conta.carregando && !d} erro={conta.erro} />}
      <Mensagem m={acao.mensagem} />
      {d && (
        <div className="space-y-4">
          <Cartao titulo="Minha conta" icone={ShieldCheck}>
            <p className="text-sm">{verificado ? <>Aplicativo autenticador ativo <Chip tipo="ok">protegida</Chip></> : <>Sem aplicativo autenticador <Chip tipo="pend">só senha</Chip></>}
              {d.s.exigido && <span className="nota"> · exigido por {d.s.ies_que_exigem.join(', ')}</span>}</p>
            {!verificado && !cadastrando && <button className="btn btn-peq mt-2" onClick={() => setCadastrando(true)}>Ativar verificação em duas etapas</button>}
            {cadastrando && <div className="mt-3 max-w-md"><DoisFatores modo="cadastro" aoConcluir={() => { setCadastrando(false); setRecarga((n) => n + 1); }} aoSair={() => setCadastrando(false)} /></div>}
            {verificado && !d.s.exigido && <button className="btn btn-fantasma btn-peq mt-2" disabled={acao.enviando} onClick={() => {
              if (window.confirm('Remover o aplicativo autenticador? Sua conta voltará a usar só a senha.')) void fazer(async () => { await api.removerFator(verificado.id); return 'Aplicativo autenticador removido.'; }); }}>Remover aplicativo autenticador</button>}
          </Cartao>
          {equipe.dados && (
            <Cartao titulo="Exigência para a equipe da instituição">
              <Aviso>Com a exigência ligada, quem ainda não tem aplicativo autenticador precisa cadastrá-lo no próximo acesso. Para ligar, cadastre o seu primeiro.</Aviso>
              <p className="mt-2 text-sm">Situação: {equipe.dados.exigir_2fa ? <Chip tipo="ok">exigida</Chip> : <Chip>opcional</Chip>}</p>
              <button className="btn btn-peq mt-2" disabled={acao.enviando || (!equipe.dados.exigir_2fa && !verificado)} onClick={() => void fazer(async () => {
                const r = await api.configurar2fa(ies!, !equipe.dados!.exigir_2fa);
                return r.exigir_2fa ? `Exigência ligada. ${r.usuarios_sem_fator} pessoa(s) precisarão cadastrar o aplicativo no próximo acesso.` : 'Exigência desligada.'; })}>
                {equipe.dados.exigir_2fa ? 'Desligar exigência' : 'Exigir de toda a equipe'}</button>
              <ul className="mt-3 grid gap-1 text-sm sm:grid-cols-2">{equipe.dados.equipe.map((p, i) => <li key={i}>{p.nome} {p.com_fator ? <Chip tipo="ok">com 2FA</Chip> : <Chip tipo="pend">sem 2FA</Chip>}</li>)}</ul>
            </Cartao>)}
        </div>)}
    </>
  );
}
