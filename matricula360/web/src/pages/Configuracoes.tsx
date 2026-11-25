import { Gauge, Save, Target } from 'lucide-react';
import { useEffect, useState } from 'react';
import { useSessao } from '../components/Layout';
import { Campo, Cartao, Estado, Mensagem, Titulo } from '../components/ui';
import { api } from '../lib/api';
import { useAcao, useCarregar } from '../lib/hooks';

const CAMPOS = [
  ['sla_horas', 'SLA do primeiro contato (h)'], ['max_followups', 'Máx. follow-ups'],
  ['dias_sem_contato', 'Dias sem contato p/ follow-up'], ['capacidade_atendente', 'Capacidade por atendente'],
] as const;

export function Configuracoes() {
  const { ies, estrutura, tem, recarregarEstrutura } = useSessao();
  const acao = useAcao();
  const [cfg, setCfg] = useState<Record<string, string>>(() => Object.fromEntries(CAMPOS.map(([k]) => [k, String(estrutura?.ies[k] ?? '')])));
  const [coorte, setCoorte] = useState(estrutura?.coortes[0] ?? '2027.1');
  // Correção da Fase 2 (item 5): os campos carregam as metas já cadastradas da coorte.
  const cadastradas = useCarregar(() => (/^\d{4}\.[12]$/.test(coorte) ? api.metas(ies!, coorte) : Promise.resolve([])), [ies, coorte]);
  const [metas, setMetas] = useState<Record<number, string>>({});
  useEffect(() => { setMetas(Object.fromEntries((cadastradas.dados ?? []).map((m) => [m.curso_id, String(m.meta)]))); }, [cadastradas.dados]);
  if (!tem('gestor')) return <><Titulo titulo="Configurações" /><p>Disponível apenas para gestores da instituição.</p></>;

  return (
    <>
      <Titulo titulo="Configurações e metas" subtitulo="Parâmetros do MAIM, SLA e metas por curso e coorte." />
      <Mensagem m={acao.mensagem} />
      <div className="grid gap-4 lg:grid-cols-2">
        <Cartao titulo="MAIM e SLA" icone={Gauge}>
          <div className="grid grid-cols-2 gap-3">
            {CAMPOS.map(([k, r]) => <Campo key={k} rotulo={r}><input className="campo" type="number" min={0} value={cfg[k]} onChange={(e) => setCfg({ ...cfg, [k]: e.target.value })} /></Campo>)}
          </div>
          <button className="btn mt-4" disabled={acao.enviando} onClick={() => void acao.executar(async () => {
            await api.configurar(ies!, Object.fromEntries(CAMPOS.map(([k]) => [k, Number(cfg[k])])));
            recarregarEstrutura(); return 'Configuração salva.';
          })}><Save className="h-4 w-4" aria-hidden />Salvar parâmetros</button>
        </Cartao>
        <Cartao titulo="Metas por curso" icone={Target}>
          <Campo rotulo="Coorte" className="mb-3 w-32"><input className="campo" aria-label="Coorte da meta" value={coorte} onChange={(e) => setCoorte(e.target.value)} /></Campo>
          <Estado carregando={cadastradas.carregando && !cadastradas.dados} erro={cadastradas.erro} />
          <div className="grid grid-cols-2 gap-3">
            {estrutura?.cursos.map((c) => (
              <Campo key={c.id} rotulo={`${c.nome} · ${c.turno}`}>
                <input className="campo" type="number" min={0} aria-label={`Meta ${c.nome}`} placeholder="sem meta (N/D)" value={metas[c.id] ?? ''} onChange={(e) => setMetas({ ...metas, [c.id]: e.target.value })} />
              </Campo>
            ))}
          </div>
          <button className="btn mt-4" disabled={acao.enviando} onClick={() => void acao.executar(async () => {
            for (const c of estrutura?.cursos ?? []) if ((metas[c.id] ?? '') !== '') await api.definirMeta(ies!, c.id, coorte, Number(metas[c.id]));
            await cadastradas.recarregar(); recarregarEstrutura(); return 'Metas salvas. Cursos sem meta ficam “N/D”, não zero.';
          })}><Save className="h-4 w-4" aria-hidden />Salvar metas</button>
        </Cartao>
      </div>
    </>
  );
}
