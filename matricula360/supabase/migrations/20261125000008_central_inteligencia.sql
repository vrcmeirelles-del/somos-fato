-- Matrícula 360° — migração 8: Central de Inteligência (BI executivo) com filtros globais.
-- Uma RPC somente leitura devolve todos os blocos do painel, sob as mesmas regras de escopo.
-- Regras: indisponível (null) ≠ zero; estimativas sempre identificadas e com método; nada é inventado.
-- Custo por lead/matrícula exige investimento cadastrado (módulo Campanhas, P1): até lá, N/D com motivo.

create or replace function privado.ordem_etapa(p text) returns int
language sql immutable set search_path = '' as $$
  select case p when 'novo' then 1 when 'contato' then 2 when 'inscrito' then 3 when 'pre_matricula' then 4
                when 'matricula_comercial' then 5 when 'confirmado' then 6 else 0 end;
$$;
revoke execute on function privado.ordem_etapa(text) from public, anon, authenticated;

create or replace function public.rpc_central(p_ies bigint, p_coorte text, p_filtros jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  todos constant text[] := array['gestor','reitoria','coordenador','comercial','secretaria','financeiro'];
  f_campus bigint := nullif(p_filtros->>'campus_id', '')::bigint;
  f_curso bigint := nullif(p_filtros->>'curso_id', '')::bigint;
  f_turno text := nullif(p_filtros->>'turno', '');
  f_modal text := nullif(p_filtros->>'modalidade', '');
  cfg public.ies; r jsonb;
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if p_coorte !~ '^\d{4}\.[12]$' then raise exception 'Coorte deve ter formato AAAA.1 ou AAAA.2' using errcode = '22023'; end if;
  select * into cfg from public.ies where id = p_ies;

  with cursos_ok as (
    select c.*, cp.nome as campus_nome from public.cursos c join public.campus cp on cp.id = c.campus_id
     where c.ies_id = p_ies and privado.tem_acesso(p_ies, c.id, todos)
       and (f_campus is null or c.campus_id = f_campus) and (f_curso is null or c.id = f_curso)
       and (f_turno is null or c.turno = f_turno) and (f_modal is null or c.modalidade = f_modal)
  ), ops as (
    select o.*, c.nome as curso, c.turno, c.modalidade, c.mensalidade_centavos, c.campus_nome, p.origem,
           coalesce(u.nome, 'Sem responsável') as atendente,
           greatest(
             case when o.etapa in ('perdido','cancelado') then 0 else privado.ordem_etapa(o.etapa) end,
             case when o.confirmada_em is not null then 6 when o.matricula_comercial_em is not null then 5 else 0 end,
             coalesce((select max(greatest(privado.ordem_etapa(a.dados->>'de'), privado.ordem_etapa(a.dados->>'para')))
                         from public.auditoria a where a.entidade = 'oportunidade' and a.entidade_id = o.id::text
                          and a.acao = 'oportunidade.etapa'), 1)) as alcance,
           (select x.valor_final_centavos from public.propostas x where x.oportunidade_id = o.id and x.status = 'aceita' order by x.id desc limit 1) as valor_aceito
      from public.oportunidades o join cursos_ok c on c.id = o.curso_id join public.pessoas p on p.id = o.pessoa_id
      left join public.usuarios u on u.id = o.responsavel_id
     where o.ies_id = p_ies and o.coorte = p_coorte
  ), tot as (
    select count(*) as oportunidades,
           count(*) filter (where matricula_comercial_em is not null) as matriculas_comerciais,
           count(distinct pessoa_id) filter (where etapa = 'confirmado') as ingressantes,
           count(*) filter (where etapa = 'perdido') as perdidos,
           count(*) filter (where etapa = 'cancelado') as cancelamentos,
           count(*) filter (where etapa not in ('confirmado','perdido','cancelado')) as abertas,
           coalesce(sum(coalesce(valor_aceito, mensalidade_centavos)) filter (where etapa = 'confirmado'), 0) as receita_ingressos,
           coalesce(sum(coalesce(valor_aceito, mensalidade_centavos)) filter (where etapa not in ('confirmado','perdido','cancelado')), 0) as receita_pipeline_bruta
      from ops
  ), metas_f as (
    select sum(m.meta) as meta, count(*) as n from public.metas m join cursos_ok c on c.id = m.curso_id
     where m.ies_id = p_ies and m.coorte = p_coorte
  ), base as (
    select t.*, mf.meta, mf.n as n_metas,
           (t.ingressantes + t.perdidos + t.cancelamentos) as decididas,
           case when (t.ingressantes + t.perdidos + t.cancelamentos) = 0 then null
                else t.ingressantes::numeric / (t.ingressantes + t.perdidos + t.cancelamentos) end as taxa
      from tot t, metas_f mf
  )
  select jsonb_build_object(
    'coorte', p_coorte, 'filtros', p_filtros,
    'cobertura', case when privado.tem_acesso_ies(p_ies, todos) and f_campus is null and f_curso is null and f_turno is null and f_modal is null then 'ies' else 'recorte' end,
    'totais', (select jsonb_build_object(
        'oportunidades', b.oportunidades, 'matriculas_comerciais', b.matriculas_comerciais, 'ingressantes', b.ingressantes,
        'perdidos', b.perdidos, 'cancelamentos', b.cancelamentos, 'oportunidades_abertas', b.abertas,
        'conversao_geral', case when b.oportunidades = 0 then null else round(b.ingressantes::numeric / b.oportunidades, 4) end,
        'taxa_conversao_decididas', round(b.taxa, 4),
        'meta', case when b.n_metas = 0 then null else b.meta end,
        'atingimento', case when b.n_metas = 0 or b.meta = 0 then null else round(b.ingressantes::numeric / b.meta, 4) end,
        'ingressos_esperados_pipeline', case when b.taxa is null then null else round(b.abertas * b.taxa, 1) end,
        'projecao_ingressos', case when b.taxa is null then null else round(b.ingressantes + b.abertas * b.taxa, 1) end,
        'lacuna_meta', case when b.n_metas = 0 then null else greatest(b.meta - b.ingressantes, 0) end,
        'novas_oportunidades_necessarias', case when b.n_metas = 0 or b.taxa is null or b.taxa = 0 then null
          else greatest(ceil((b.meta - b.ingressantes - b.abertas * b.taxa) / b.taxa), 0) end,
        'receita_mensal_ingressantes_centavos', b.receita_ingressos,
        'receita_mensal_potencial_pipeline_centavos', case when b.taxa is null then null else round(b.receita_pipeline_bruta * b.taxa) end,
        'custo_por_lead_centavos', null, 'custo_por_matricula_centavos', null,
        'custo_motivo', 'Sem investimento cadastrado: disponível com o módulo de Campanhas (P1).',
        'metodos', jsonb_build_object(
          'taxa', 'Ingressantes ÷ oportunidades decididas (ingresso, perda ou cancelamento) da coorte.',
          'projecao', 'Ingressantes + oportunidades abertas × taxa das decididas.',
          'novas', '(Meta − ingressantes − ingressos esperados do pipeline) ÷ taxa das decididas.',
          'funil', 'Oportunidades que ALCANÇARAM cada etapa, reconstruído pelo histórico auditado. Quem confirmou e depois cancelou conta no alcance do ingresso, mas não entre os ingressantes efetivos.',
          'receita', 'Mensalidade do valor final da proposta aceita; sem proposta aceita, mensalidade cheia do curso. Pipeline ponderado pela taxa das decididas (estimativa).'))
      from base b),
    'funil', (select coalesce(jsonb_agg(jsonb_build_object('etapa', e.etapa, 'quantidade', e.q,
                'conversao_da_anterior', case when e.ant is null or e.ant = 0 then null else round(e.q::numeric / e.ant, 4) end) order by e.k), '[]'::jsonb)
              from (select k, etapa, q, lag(q) over (order by k) as ant from (
                      select s.k, s.etapa, (select count(*) from ops where alcance >= s.k) as q
                        from (values (1,'novo'),(2,'contato'),(3,'inscrito'),(4,'pre_matricula'),(5,'matricula_comercial'),(6,'confirmado')) s(k, etapa)) z) e),
    'evolucao', (select coalesce(jsonb_agg(jsonb_build_object('semana', w.semana, 'oportunidades', w.ops, 'matriculas_comerciais', w.mc, 'ingressantes', w.ing) order by w.semana), '[]'::jsonb)
                 from (select to_char(sem, 'YYYY-MM-DD') as semana,
                              (select count(*) from ops where date_trunc('week', criado_em) = sem) as ops,
                              (select count(*) from ops where date_trunc('week', matricula_comercial_em) = sem) as mc,
                              (select count(*) from ops where date_trunc('week', confirmada_em) = sem) as ing
                         from generate_series(date_trunc('week', now()) - interval '11 weeks', date_trunc('week', now()), interval '1 week') sem) w),
    'por_origem', (select coalesce(jsonb_agg(jsonb_build_object('chave', x.chave, 'oportunidades', x.n, 'ingressantes', x.ing,
                     'conversao', case when x.n = 0 then null else round(x.ing::numeric / x.n, 4) end) order by x.n desc), '[]'::jsonb)
                   from (select origem as chave, count(*) as n, count(distinct pessoa_id) filter (where etapa = 'confirmado') as ing from ops group by 1) x),
    'por_curso', (select coalesce(jsonb_agg(jsonb_build_object('chave', x.chave, 'curso_id', x.curso_id, 'oportunidades', x.n, 'ingressantes', x.ing,
                    'matriculas_comerciais', x.mc, 'meta', x.meta,
                    'atingimento', case when x.meta is null or x.meta = 0 then null else round(x.ing::numeric / x.meta, 4) end,
                    'conversao', case when x.n = 0 then null else round(x.ing::numeric / x.n, 4) end) order by x.chave), '[]'::jsonb)
                  from (select c.nome || ' · ' || c.turno as chave, c.id as curso_id, count(o.id) as n,
                               count(distinct o.pessoa_id) filter (where o.etapa = 'confirmado') as ing,
                               count(o.id) filter (where o.matricula_comercial_em is not null) as mc,
                               (select m.meta from public.metas m where m.ies_id = p_ies and m.curso_id = c.id and m.coorte = p_coorte) as meta
                          from cursos_ok c left join ops o on o.curso_id = c.id group by c.id, c.nome, c.turno) x),
    'por_turno', (select coalesce(jsonb_agg(jsonb_build_object('chave', turno, 'oportunidades', n, 'ingressantes', ing) order by turno), '[]'::jsonb)
                  from (select turno, count(*) n, count(distinct pessoa_id) filter (where etapa = 'confirmado') ing from ops group by 1) x),
    'por_modalidade', (select coalesce(jsonb_agg(jsonb_build_object('chave', modalidade, 'oportunidades', n, 'ingressantes', ing) order by modalidade), '[]'::jsonb)
                       from (select modalidade, count(*) n, count(distinct pessoa_id) filter (where etapa = 'confirmado') ing from ops group by 1) x),
    'por_atendente', (select coalesce(jsonb_agg(jsonb_build_object('chave', atendente, 'oportunidades', n, 'matriculas_comerciais', mc, 'ingressantes', ing,
                        'conversao', case when n = 0 then null else round(ing::numeric / n, 4) end) order by n desc), '[]'::jsonb)
                      from (select atendente, count(*) n, count(*) filter (where matricula_comercial_em is not null) mc,
                                   count(distinct pessoa_id) filter (where etapa = 'confirmado') ing from ops group by 1) x),
    'alertas', (select jsonb_agg(a order by (a->>'prioridade')::int, a->>'tipo') from (
        select jsonb_build_object('tipo', 'sla_vencido', 'prioridade', 1, 'titulo', 'Tarefas com SLA vencido',
               'quantidade', count(*), 'acao', 'Priorizar contato na fila do MAIM') as a
          from public.tarefas t join ops o on o.id = t.oportunidade_id where t.status = 'aberta' and t.vence_em < now()
        union all
        select jsonb_build_object('tipo', 'pendencia_validacao', 'prioridade', 1, 'titulo', 'Matrículas comerciais aguardando validação há mais de 48h',
               'quantidade', count(*), 'acao', 'Secretaria e financeiro: concluir validações em Conversão e Matrículas')
          from ops where etapa = 'matricula_comercial' and matricula_comercial_em < now() - interval '48 hours'
        union all
        select jsonb_build_object('tipo', 'proposta_aprovacao', 'prioridade', 2, 'titulo', 'Propostas aguardando aprovação do gestor',
               'quantidade', count(*), 'acao', 'Decidir em Conversão e Matrículas → Propostas')
          from public.propostas x join ops o on o.id = x.oportunidade_id where x.status = 'pendente_aprovacao'
        union all
        select jsonb_build_object('tipo', 'proposta_vencendo', 'prioridade', 2, 'titulo', 'Propostas aprovadas que vencem em até 48h',
               'quantidade', count(*), 'acao', 'Contatar o candidato para registrar o aceite')
          from public.propostas x join ops o on o.id = x.oportunidade_id
         where x.status = 'aprovada' and x.validade between now() and now() + interval '48 hours'
        union all
        select jsonb_build_object('tipo', 'parada', 'prioridade', 2, 'titulo', 'Oportunidades paradas sem tarefa aberta',
               'quantidade', count(*), 'acao', 'Executar o ciclo MAIM ou registrar contato')
          from ops o where o.etapa in ('contato','inscrito','pre_matricula')
           and o.atualizado_em < now() - make_interval(days => cfg.dias_sem_contato)
           and not exists (select 1 from public.tarefas t where t.oportunidade_id = o.id and t.status = 'aberta')
        union all
        select jsonb_build_object('tipo', 'sem_responsavel', 'prioridade', 3, 'titulo', 'Oportunidades abertas sem responsável',
               'quantidade', count(*), 'acao', 'Rever capacidade dos atendentes e redistribuir')
          from ops where etapa not in ('confirmado','perdido','cancelado') and responsavel_id is null
      ) z where (a->>'quantidade')::int > 0),
    'filtros_disponiveis', (select jsonb_build_object(
        'campi', (select coalesce(jsonb_agg(distinct jsonb_build_object('id', cp.id, 'nome', cp.nome)), '[]'::jsonb)
                    from public.cursos c join public.campus cp on cp.id = c.campus_id where c.ies_id = p_ies and privado.tem_acesso(p_ies, c.id, todos)),
        'turnos', (select coalesce(jsonb_agg(distinct c.turno), '[]'::jsonb) from public.cursos c where c.ies_id = p_ies and privado.tem_acesso(p_ies, c.id, todos)),
        'modalidades', (select coalesce(jsonb_agg(distinct c.modalidade), '[]'::jsonb) from public.cursos c where c.ies_id = p_ies and privado.tem_acesso(p_ies, c.id, todos))))
  ) into r;
  return r;
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.rpc_central(bigint, text, jsonb) to authenticated;
