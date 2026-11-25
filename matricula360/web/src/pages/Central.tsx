import { AlertTriangle, BadgeDollarSign, BarChart3, CheckCircle2, Filter, GraduationCap, Layers, Target, TrendingUp, Users, UserCheck } from 'lucide-react';
import { Link } from 'react-router-dom';
import { BarraFiltros, useSessao } from '../components/Layout';
import { Barras, Funil, Linhas, Progresso } from '../components/graficos';
import { Aviso, Cartao, Estado, Kpi, Titulo, Vazio } from '../components/ui';
import { api } from '../lib/api';
import { ND, moeda, num, pct, rotulo } from '../lib/formato';
import { useCarregar } from '../lib/hooks';

const DESTINO_ALERTA: Record<string, string> = {
  sla_vencido: 'intervencoes', parada: 'intervencoes', sem_responsavel: 'intervencoes',
  pendencia_validacao: 'matriculas', proposta_aprovacao: 'propostas', proposta_vencendo: 'propostas',
};

export function Central() {
  const { ies, estrutura, filtros } = useSessao();
  const { coorte, ...resto } = filtros;
  const c = useCarregar(() => (ies && coorte ? api.central(ies, coorte, resto) : Promise.resolve(null)),
    [ies, coorte, resto.campus_id, resto.curso_id, resto.turno, resto.modalidade]);
  const d = c.dados; const t = d?.totais;
  const moedaOuNd = (v: number | null | undefined) => (v == null ? ND : moeda(v));

  return (
    <>
      <Titulo titulo="Central de Inteligência" subtitulo={`${estrutura?.ies.nome ?? ''} · visão executiva da captação`} />
      <BarraFiltros campi={d?.filtros_disponiveis.campi} />
      {!coorte ? <Vazio texto="Sem coortes com dados ou metas" detalhe="Os indicadores ficam indisponíveis (N/D) até existir uma coorte com oportunidades ou metas cadastradas." /> : (
        <>
          <Estado carregando={c.carregando && !d} erro={c.erro} />
          {d && t && (
            <div className="space-y-5">
              <p className="nota flex items-center gap-1.5"><Filter className="h-3.5 w-3.5" aria-hidden />
                Cobertura: {estrutura?.acesso_total ? (d.cobertura === 'ies' ? 'instituição inteira' : 'recorte filtrado') : 'somente cursos autorizados'} · coorte {d.coorte} ·
                N/D = indisponível (sem base de cálculo ou sem cadastro), distinto de zero.</p>

              <div className="kpis grid grid-cols-2 gap-3 md:grid-cols-4 xl:grid-cols-8">
                <Kpi rotulo="Oportunidades" valor={num(t.oportunidades)} icone={Users} />
                <Kpi rotulo="Matrículas comerciais" valor={num(t.matriculas_comerciais)} icone={Layers} />
                <Kpi rotulo="Ingressantes efetivos" valor={num(t.ingressantes)} icone={UserCheck} destaque />
                <Kpi rotulo="Meta" valor={num(t.meta)} icone={Target} />
                <Kpi rotulo="Atingimento" valor={pct(t.atingimento)} icone={CheckCircle2} />
                <Kpi rotulo="Conversão (decididas)" valor={pct(t.taxa_conversao_decididas)} icone={TrendingUp} detalhe={`Geral: ${pct(t.conversao_geral)}`} />
                <Kpi rotulo="Custo por lead" valor={moedaOuNd(t.custo_por_lead_centavos)} icone={BadgeDollarSign} detalhe="Sem investimento cadastrado" />
                <Kpi rotulo="Custo por matrícula" valor={moedaOuNd(t.custo_por_matricula_centavos)} icone={BadgeDollarSign} detalhe="Módulo Campanhas (P1)" />
              </div>

              <div className="grid gap-4 xl:grid-cols-3">
                <Cartao titulo="Projeção da coorte (estimativa)" icone={BarChart3} className="xl:col-span-1">
                  <dl className="grid grid-cols-2 gap-x-3 gap-y-2 text-sm">
                    <dt className="text-suave">Oportunidades abertas</dt><dd className="text-right font-semibold">{t.oportunidades_abertas}</dd>
                    <dt className="text-suave">Ingressos esperados do pipeline</dt><dd className="text-right font-semibold">{num(t.ingressos_esperados_pipeline)}</dd>
                    <dt className="text-suave">Projeção de ingressos</dt><dd className="text-right font-semibold">{num(t.projecao_ingressos)}</dd>
                    <dt className="text-suave">Lacuna para a meta</dt><dd className="text-right font-semibold">{num(t.lacuna_meta)}</dd>
                    <dt className="text-suave">Novas oportunidades necessárias</dt><dd className="text-right text-lg font-semibold text-tec">{num(t.novas_oportunidades_necessarias)}</dd>
                  </dl>
                  <p className="nota mt-3">{t.metodos.projecao} {t.metodos.novas} Taxa: {t.metodos.taxa}</p>
                </Cartao>
                <Cartao titulo="Funil comercial (alcance por etapa)" icone={Layers} className="xl:col-span-2">
                  <Funil etapas={d.funil} />
                  <p className="nota mt-2">{t.metodos.funil}</p>
                </Cartao>
              </div>

              <div className="grid gap-4 lg:grid-cols-2">
                <Cartao titulo="Metas versus resultados por curso" icone={Target}>
                  <div className="space-y-3">{d.por_curso.map((g) => <Progresso key={g.chave} rotulo={g.chave} atual={g.ingressantes} meta={g.meta ?? null} />)}</div>
                  <p className="nota mt-2">Ingressantes efetivos sobre a meta da coorte. Curso sem meta cadastrada: N/D.</p>
                </Cartao>
                <Cartao titulo="Evolução semanal (12 semanas)" icone={TrendingUp}>
                  <Linhas pontos={d.evolucao as unknown as Record<string, number | string>[]} series={[
                    { chave: 'oportunidades', rotulo: 'Oportunidades', cor: '#1d6fe0' },
                    { chave: 'matriculas_comerciais', rotulo: 'Matrículas comerciais', cor: '#14b8c4' },
                    { chave: 'ingressantes', rotulo: 'Ingressos', cor: '#0b2545' }]} />
                </Cartao>
              </div>

              <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
                <Cartao titulo="Captação por origem" icone={Users}><Barras dados={d.por_origem} valor="oportunidades" sufixo={(g) => `conv. ${pct(g.conversao as number | null)}`} /></Cartao>
                <Cartao titulo="Desempenho por turno" icone={GraduationCap}><Barras dados={d.por_turno} valor="oportunidades" sufixo={(g) => `${g.ingressantes} ingr.`} /></Cartao>
                <Cartao titulo="Desempenho por modalidade" icone={GraduationCap}><Barras dados={d.por_modalidade} valor="oportunidades" sufixo={(g) => `${g.ingressantes} ingr.`} /></Cartao>
                <Cartao titulo="Desempenho por atendente" icone={UserCheck}><Barras dados={d.por_atendente} valor="oportunidades" sufixo={(g) => `${g.ingressantes} ingr. · ${pct(g.conversao as number | null)}`} /></Cartao>
              </div>

              <div className="grid gap-4 lg:grid-cols-3">
                <Cartao titulo="Receita mensal" icone={BadgeDollarSign}>
                  <dl className="space-y-2 text-sm">
                    <div className="flex justify-between gap-2"><dt className="text-suave">Ingressantes efetivos</dt><dd className="font-semibold">{moeda(t.receita_mensal_ingressantes_centavos)}</dd></div>
                    <div className="flex justify-between gap-2"><dt className="text-suave">Potencial do pipeline (estimativa)</dt><dd className="font-semibold">{moedaOuNd(t.receita_mensal_potencial_pipeline_centavos)}</dd></div>
                  </dl>
                  <p className="nota mt-2">{t.metodos.receita}</p>
                </Cartao>
                <Cartao titulo="Alertas e intervenções do MAIM" icone={AlertTriangle} className="lg:col-span-2">
                  {d.alertas?.length ? (
                    <ul className="divide-y divide-linha">
                      {d.alertas.map((a) => (
                        <li key={a.tipo} className="flex flex-wrap items-center gap-3 py-2.5">
                          <span className={`grid h-8 min-w-8 place-items-center rounded-lg px-2 text-sm font-bold ${a.prioridade === 1 ? 'bg-red-50 text-erro' : a.prioridade === 2 ? 'bg-amber-50 text-alerta' : 'bg-fundo text-suave'}`}>{a.quantidade}</span>
                          <div className="min-w-0 flex-1"><p className="text-sm font-medium">{a.titulo}</p><p className="nota">{a.acao}</p></div>
                          {DESTINO_ALERTA[a.tipo] && <Link className="btn btn-fantasma btn-peq" to={`/ies/${ies}/${DESTINO_ALERTA[a.tipo]}`}>Abrir</Link>}
                        </li>
                      ))}
                    </ul>
                  ) : <Aviso>Nenhum alerta no recorte atual.</Aviso>}
                </Cartao>
              </div>
              <p className="nota">Agrupamentos por {['curso', 'turno', 'modalidade', 'atendente'].map(rotulo).join(', ').toLowerCase()} e origem somam o total do recorte; ingressantes contam pessoas distintas.</p>
            </div>
          )}
        </>
      )}
    </>
  );
}
