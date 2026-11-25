import { CalendarClock } from 'lucide-react';
import { useState } from 'react';
import { useSessao } from '../components/Layout';
import { Cartao, Chip, Estado, Titulo, Vazio } from '../components/ui';
import { api, temCrmAvancado } from '../lib/api';
import { relativo } from '../lib/crm';
import { rotulo } from '../lib/formato';
import { useCarregar } from '../lib/hooks';

// Agenda comercial: tarefas abertas de 30 dias atrás (atrasadas) até o horizonte escolhido. Gestor vê a da IES; demais, a própria.
export function Agenda({ abrirDetalhe, versao }: { abrirDetalhe: (id: number) => void; versao: number }) {
  const { ies, tem } = useSessao();
  const [dias, setDias] = useState(14);
  const disp = useCarregar(() => (ies ? temCrmAvancado(ies) : Promise.resolve(false)), [ies]);
  const ag = useCarregar(async () => {
    if (!ies || disp.dados !== true) return null;
    const agora = Date.now();
    return api.agenda(ies, new Date(agora - 30 * 86400e3).toISOString(), new Date(agora + dias * 86400e3).toISOString());
  }, [ies, dias, disp.dados, versao]);
  const grupos = new Map<string, NonNullable<typeof ag.dados>>();
  for (const t of ag.dados ?? []) {
    const k = t.atrasada ? 'Atrasadas' : new Date(t.quando).toLocaleDateString('pt-BR', { weekday: 'long', day: '2-digit', month: '2-digit' });
    grupos.set(k, [...(grupos.get(k) ?? []), t]);
  }
  return (
    <>
      <Titulo titulo="Agenda comercial" subtitulo={tem('gestor') ? 'Tarefas abertas de toda a equipe.' : 'Suas tarefas abertas.'}
        acao={<label className="text-sm">Horizonte{' '}<select className="campo" value={dias} onChange={(e) => setDias(Number(e.target.value))}>
          {[7, 14, 30, 60].map((d) => <option key={d} value={d}>{d} dias</option>)}</select></label>} />
      <Estado carregando={(disp.carregando || ag.carregando) && !ag.dados} erro={disp.erro ?? ag.erro} />
      {disp.dados === false && <Vazio texto="Agenda disponível após a migração 10 do banco." />}
      {ag.dados && !ag.dados.length && <Vazio texto="Nenhuma tarefa aberta no período." detalhe="Agende contatos pela ficha da oportunidade." />}
      <div className="grid gap-3 lg:grid-cols-2">
        {[...grupos.entries()].map(([dia, itens]) => (
          <Cartao key={dia} titulo={`${dia} (${itens.length})`} icone={CalendarClock}>
            <ul className="text-sm">{itens.map((t) => (
              <li key={t.id} className={`mb-1.5 border-l-[3px] pl-2.5 ${t.atrasada ? 'border-erro' : 'border-tec-400'}`}>
                <button className="text-left hover:underline" onClick={() => abrirDetalhe(t.oportunidade_id)}>
                  <strong>{new Date(t.quando).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}</strong> · {t.nome} · {t.curso}
                </button>
                <span className="block text-xs text-suave">{rotulo(t.tipo)}{t.canal ? ` · ${t.canal}` : ''} · {rotulo(t.etapa)} · {t.responsavel ?? 'sem responsável'} · {relativo(t.quando)}
                  {t.atrasada && <Chip tipo="erro">atrasada</Chip>}</span>
                {t.descricao && <span className="block text-xs">{t.descricao}</span>}
              </li>))}</ul>
          </Cartao>
        ))}
      </div>
    </>
  );
}
