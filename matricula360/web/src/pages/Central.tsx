import { AlertTriangle, BadgeDollarSign, Megaphone, BarChart3, CheckCircle2, Filter, GraduationCap, Layers, Target, TrendingUp, Users, UserCheck } from 'lucide-react';
import { Link } from 'react-router-dom';
import { BarraFiltros, useSessao } from '../components/Layout';
import { Barras, Funil, Linhas, Progresso } from '../components/graficos';
import { Aviso, Cartao, Chip, Estado, Kpi, Titulo, Valor, Vazio } from '../components/ui';
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
    [ies, coorte, resto.campus_id, resto.curso_id, resto.turno, resto.modalidade, resto.campanha_id]);
  const d = c.dados; const t = d?.totais;
  // Compatível com o banco antes da migração 9 (campos novos ausentes): mostra N/D com o motivo, sem quebrar a tela.
  const semM9 = Boolean(t && t.cenario_pipeline === undefined);
  const legado = t as unknown as Record<string, number | null> | undefined;
  const cen = t?.cenario_pipeline ?? { rotulo: 'Cenário complementar (não é o indicador oficial)', taxa_conversao_decididas: legado?.taxa_conversao_decididas ?? null,
    ingressos_esperados_pipeline: legado?.ingressos_esperados_pipeline ?? null, projecao_ingressos: legado?.projecao_ingressos ?? null,
    novas_oportunidades_necessarias: legado?.novas_oportunidades_necessarias ?? null };
  const moedaOuNd = (v: number | null | undefined) => (v == null ? ND : moeda(v));

  return (
    <>
      <Titulo titulo="Central de Inteligência" subtitulo={`${estrutura?.ies.nome ?? ''} · visão executiva da captação`} />
      <BarraFiltros campi={d?.filtros_disponiveis.campi} campanhas={d?.filtros_disponiveis.campanhas} />
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
                <Kpi rotulo="Conversão da coorte" valor={pct(t.conversao ?? legado?.conversao_geral ?? null)} icone={TrendingUp} detalhe={`Decididas: ${pct(cen.taxa_conversao_decididas)}`} />
                <Kpi rotulo="Custo por lead" valor={moedaOuNd(t.custo_por_lead_centavos)} icone={BadgeDollarSign}
                  detalhe={t.custo_por_lead_centavos != null ? `${t.leads_atribuidos ?? 0} leads atribuídos` : (t.custo_motivo ?? 'Sem custo lançado')} />
                <Kpi rotulo="Custo por ingressante" valor={moedaOuNd(t.custo_por_matricula_centavos)} icone={BadgeDollarSign}
                  detalhe={t.custo_por_matricula_centavos != null ? 'Ingresso efetivo atribuído' : (t.custo_motivo ?? 'Sem custo lançado')} />
              </div>

              <div className="grid gap-4 xl:grid-cols-3">
                <Cartao titulo="Projeção da coorte" icone={BarChart3} className="xl:col-span-1">
                  <dl className="grid grid-cols-2 gap-x-3 gap-y-2 text-sm">
                    <dt className="text-suave">Meta restante</dt><dd className="text-right font-semibold">{num(t.meta_restante ?? legado?.lacuna_meta ?? null)}</dd>
                    <dt className="text-suave">Amostra (oportunidades)</dt><dd className="text-right font-semibold">{t.amostra ?? t.oportunidades} {t.amostra_minima != null && <span className="text-xs font-normal text-suave">mín. {t.amostra_minima}</span>}</dd>
                    <dt className="font-medium text-marinho">Oportunidades adicionais projetadas</dt>
                    <dd className="text-right text-xl font-semibold text-tec"><Valor v={num(semM9 ? null : t.oportunidades_adicionais_projetadas)} /></dd>
                  </dl>
                  {(semM9 || t.forecast_motivo) && <p className="mt-2"><Chip tipo="pend">{semM9 ? 'Indicador oficial disponível após a migração 9 no banco.' : t.forecast_motivo}</Chip></p>}
                  {!semM9 && <p className="nota mt-2">{t.metodos.projecao}</p>}
                  <div className="mt-4 rounded-lg border border-dashed border-linha bg-fundo p-3">
                    <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-suave">{cen.rotulo}</p>
                    <dl className="grid grid-cols-2 gap-x-3 gap-y-1 text-xs">
                      <dt className="text-suave">Oportunidades abertas</dt><dd className="text-right">{t.oportunidades_abertas}</dd>
                      <dt className="text-suave">Ingressos esperados do pipeline</dt><dd className="text-right">{num(cen.ingressos_esperados_pipeline)}</dd>
                      <dt className="text-suave">Novas oportunidades (cenário)</dt><dd className="text-right font-semibold">{num(cen.novas_oportunidades_necessarias)}</dd>
                    </dl>
                    <p className="nota mt-1">{t.metodos.cenario ?? 'Taxa sobre oportunidades decididas aplicada ao pipeline aberto.'}</p>
                  </div>
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
                {d.por_campanha && <Cartao titulo="Captação por campanha (atribuição)" icone={Megaphone}><Barras dados={d.por_campanha} valor="oportunidades" sufixo={(g) => `conv. ${pct(g.conversao as number | null)}`} />
                  {t.metodos.custo && <p className="nota mt-2">{t.metodos.custo}</p>}</Cartao>}
                <Cartao titulo="Desempenho por turno" icone={GraduationCap}><Barras dados={d.por_turno} valor="oportunidades" sufixo={(g) => `${g.ingressantes} ingr.`} /></Cartao>
                <Cartao titulo="Desempenho por modalidade" icone={GraduationCap}><Barras dados={d.por_modalidade} valor="oportunidades" sufixo={(g) => `${g.ingressantes} ingr.`} /></Cartao>
                <Cartao titulo="Desempenho por atendente" icone={UserCheck}><Barras dados={d.por_atendente} valor="oportunidades" sufixo={(g) => `${g.ingressantes} ingr. · ${pct(g.conversao as number | null)}`} /></Cartao>
              </div>

              <div className="grid gap-4 lg:grid-cols-3">
                <Cartao titulo="Receita mensal" icone={BadgeDollarSign}>
                  <dl className="space-y-2 text-sm">
                    <div className="flex justify-between gap-2"><dt className="text-suave">Ingressantes efetivos</dt><dd className="font-semibold">{moeda(t.receita_mensal_ingressantes_centavos)}</dd></div>
                    {t.receita_mensal_potencial_ofertada_centavos != null && <div className="flex justify-between gap-2"><dt className="text-suave">Potencial ofertado ({t.propostas_validas} propostas válidas)</dt><dd className="font-semibold">{moeda(t.receita_mensal_potencial_ofertada_centavos)}</dd></div>}
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
