import { Gauge, Lightbulb, ShieldAlert, Users } from 'lucide-react';
import { BarraFiltros, useSessao } from '../components/Layout';
import { Cartao, Chip, Estado, Kpi, Titulo, Valor, Vazio } from '../components/ui';
import { api } from '../lib/api';
import { num, pct, rotulo } from '../lib/formato';
import { useCarregar } from '../lib/hooks';
import type { ErroApi } from '../lib/supabase';

const horas = (h: number | null) => (h == null ? 'N/D' : h < 48 ? `${h} h` : `${Math.round((h / 24) * 10) / 10} d`);

// MAIM Performance: gargalos por etapa e indicadores da equipe, sempre com denominador; recomendações não executam nada.
export function Performance() {
  const { ies, filtros } = useSessao();
  const { coorte, ...resto } = filtros;
  const p = useCarregar(() => (ies && coorte ? api.performance(ies, coorte, resto) : Promise.resolve(null)),
    [ies, coorte, resto.campus_id, resto.curso_id, resto.turno, resto.modalidade]);
  const d = p.dados;
  return (
    <>
      <Titulo titulo="Performance e gargalos (MAIM)" subtitulo="Conversão e permanência por etapa, gargalo do funil e indicadores da equipe, com os denominadores à vista." />
      <BarraFiltros />
      {(p.erro as ErroApi | null)?.codigo === 'PGRST202' ? <Vazio texto="Disponível após a migração 14 do banco." /> : <Estado carregando={p.carregando && !d} erro={p.erro} />}
      {d && (
        <div className="space-y-5">
          <p className="flex items-start gap-2 rounded-lg bg-amber-50 px-3 py-2 text-sm text-alerta" role="note"><ShieldAlert className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />{d.aviso}</p>
          <div className="kpis grid grid-cols-2 gap-3 md:grid-cols-4">
            <Kpi rotulo="Gargalo" valor={d.gargalo ? rotulo(d.gargalo.etapa) : 'N/D'} icone={Gauge}
              detalhe={d.gargalo ? `${d.gargalo.avancaram} de ${d.gargalo.alcancaram} avançaram` : `Nenhuma etapa com amostra ≥ ${d.amostra_minima_etapa}`} destaque />
            <Kpi rotulo="Conversão no gargalo" valor={pct(d.gargalo?.conversao_etapa)} />
            <Kpi rotulo="SLA do 1º contato (equipe)" valor={d.ve_equipe ? pct(d.sla_primeiro_contato_equipe) : 'N/D'} detalhe={d.ve_equipe ? 'Concluídas no prazo' : 'Visível à gestão'} />
            <Kpi rotulo="Parados" valor={num(d.etapas.reduce((s, e) => s + e.parados, 0))} detalhe={d.metodos.parados} />
          </div>
          <Cartao titulo="Etapas do funil" icone={Gauge}>
            <div className="tabela" tabIndex={0} role="region" aria-label="Tabela com rolagem horizontal"><table>
              <thead><tr>{['Etapa', 'Alcançaram', 'Avançaram', 'Conversão da etapa', 'Perdidos na etapa', 'Tempo mediano', 'Parados'].map((h) => <th key={h} scope="col">{h}</th>)}</tr></thead>
              <tbody>{d.etapas.map((e) => (
                <tr key={e.etapa} className={d.gargalo?.etapa === e.etapa ? 'bg-amber-50' : ''}>
                  <td>{rotulo(e.etapa)}{d.gargalo?.etapa === e.etapa && <Chip tipo="pend">gargalo</Chip>}</td><td>{e.alcancaram}</td><td>{e.avancaram}</td>
                  <td><Valor v={pct(e.conversao_etapa)} /> <span className="text-xs text-suave">({e.avancaram}/{e.denominador})</span>{!e.amostra_suficiente && e.denominador > 0 && <Chip>amostra pequena</Chip>}</td>
                  <td>{e.perdidos_na_etapa}</td><td><Valor v={horas(e.horas_mediana_na_etapa)} /> <span className="text-xs text-suave">n={e.medicoes_tempo}</span></td><td>{e.parados}</td></tr>))}</tbody>
            </table></div>
            <p className="nota mt-2">{d.metodos.conversao_etapa} {d.metodos.permanencia} Regra {d.regra}.</p>
          </Cartao>
          <Cartao titulo="Recomendações do MAIM (propostas, nada é executado)" icone={Lightbulb}>
            {d.recomendacoes.length ? <ul className="space-y-2">{d.recomendacoes.map((r) => (
              <li key={r.regra} className="rounded-lg border border-linha p-3"><p className="font-semibold text-marinho">{r.titulo} <Chip tipo={r.prioridade === 1 ? 'pend' : undefined}>prioridade {r.prioridade}</Chip></p>
                <p className="text-sm">{r.proposta}</p><p className="nota">Justificativa: {r.justificativa} · <code>{r.regra}</code></p></li>))}</ul>
              : <p className="nota">Nenhuma recomendação para o recorte.</p>}
          </Cartao>
          <Cartao titulo={d.ve_equipe ? 'Equipe comercial' : 'Seus indicadores'} icone={Users}>
            {d.atendentes.length ? (
              <div className="tabela" tabIndex={0} role="region" aria-label="Tabela com rolagem horizontal"><table>
                <thead><tr>{['Atendente', 'Oportunidades', 'Matr. comerciais', 'Ingressantes', 'Conversão', 'SLA 1º contato', 'Horas até 1º contato', 'Interações', 'Tarefas atrasadas'].map((h) => <th key={h} scope="col">{h}</th>)}</tr></thead>
                <tbody>{d.atendentes.map((a) => (
                  <tr key={a.atendente}><td>{a.atendente}{a.eu && <Chip tipo="tec">você</Chip>}</td><td>{a.oportunidades}</td><td>{a.matriculas_comerciais}</td><td>{a.ingressantes}</td>
                    <td><Valor v={pct(a.conversao)} /></td><td><Valor v={pct(a.sla_primeiro_contato)} /> <span className="text-xs text-suave">n={a.sla_denominador}</span></td>
                    <td><Valor v={horas(a.horas_ate_primeiro_contato)} /></td><td>{a.interacoes}</td><td>{a.tarefas_atrasadas}</td></tr>))}</tbody>
              </table></div>
            ) : <p className="nota">{d.ve_equipe ? 'Sem oportunidades no recorte.' : 'Indicadores individuais da equipe são restritos à gestão.'}</p>}
            <p className="nota mt-2">{d.metodos.sla}</p>
          </Cartao>
        </div>
      )}
    </>
  );
}
