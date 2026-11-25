-- Matrícula 360° — migração 9: conformidade com a Bíblia-Mestra v0.2, §6 (divergências D1, D2 e D3).
-- Decisão do responsável (25/11/2026):
--   (D1) indicador oficial = ⌈meta restante ÷ conversão observada⌉, em aritmética exata (corrige o artefato
--        R03: 169 → 168); o método por pipeline fica como "cenário complementar" identificado;
--   amostra mínima configurável por IES, padrão 30 (abaixo dela: N/D com motivo);
--   (D2) receita potencial = soma das mensalidades ofertadas válidas;
--   (D3) conversão de destaque = ingressantes ÷ oportunidades da coorte.

alter table public.ies add column if not exists amostra_minima_forecast int not null default 30
  check (amostra_minima_forecast between 1 and 10000);

create or replace function public.rpc_central(p_ies bigint, p_coorte text, p_filtros jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  todos constant text[] := array['gestor','reitoria','coordenador','comercial','secretaria','financeiro'];
  f_campus bigint := nullif(p_filtros->>'campus_id', '')::bigint;
  f_curso bigint := nullif(p_filtros->>'curso_id', '')::bigint;
  f_turno text := nullif(p_filtros->>'turno', '');
  f_modal text := nullif(p_filtros->>'modalidade', '');
  cfg public.ies; r jsonb;
  v_min int;
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if p_coorte !~ '^\d{4}\.[12]$' then raise exception 'Coorte deve ter formato AAAA.1 ou AAAA.2' using errcode = '22023'; end if;
  select * into cfg from public.ies where id = p_ies;
  v_min := cfg.amostra_minima_forecast;

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
           coalesce(sum(coalesce(valor_aceito, mensalidade_centavos)) filter (where etapa not in ('confirmado','perdido','cancelado')), 0) as receita_pipeline_bruta,
           -- Bíblia §6 (D2): receita potencial = soma das mensalidades ofertadas válidas (proposta ativa ou aceita, dentro da validade)
           (select coalesce(sum(x.valor_final_centavos), 0) from public.propostas x join ops o2 on o2.id = x.oportunidade_id
             where o2.etapa not in ('perdido','cancelado')
               and (x.status = 'aceita' or (x.status in ('aprovada','pendente_aprovacao') and x.validade >= now()))) as receita_ofertada,
           (select count(*) from public.propostas x join ops o2 on o2.id = x.oportunidade_id
             where o2.etapa not in ('perdido','cancelado')
               and (x.status = 'aceita' or (x.status in ('aprovada','pendente_aprovacao') and x.validade >= now()))) as n_ofertas
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
        -- Bíblia §6 (D3): conversão = ingressantes efetivos ÷ oportunidades da mesma coorte
        'conversao', case when b.oportunidades = 0 then null else round(b.ingressantes::numeric / b.oportunidades, 4) end,
        'meta', case when b.n_metas = 0 then null else b.meta end,
        'atingimento', case when b.n_metas = 0 or b.meta = 0 then null else round(b.ingressantes::numeric / b.meta, 4) end,
        'meta_restante', case when b.n_metas = 0 then null else greatest(b.meta - b.ingressantes, 0) end,
        'amostra', b.oportunidades, 'amostra_minima', v_min,
        -- Bíblia §6 (D1): ceil(meta restante ÷ conversão observada NÃO arredondada), em aritmética inteira exata:
        -- meta_restante ÷ (ingressantes ÷ oportunidades) = meta_restante × oportunidades ÷ ingressantes
        'oportunidades_adicionais_projetadas', case
          when b.n_metas = 0 then null
          when greatest(b.meta - b.ingressantes, 0) = 0 then 0
          when b.ingressantes = 0 or b.oportunidades < v_min then null
          else (greatest(b.meta - b.ingressantes, 0)::bigint * b.oportunidades + b.ingressantes - 1) / b.ingressantes end,
        'forecast_motivo', case
          when b.n_metas = 0 then 'Sem meta cadastrada no recorte.'
          when greatest(b.meta - b.ingressantes, 0) = 0 then 'Meta cumprida: necessidade adicional zero.'
          when b.ingressantes = 0 then 'Conversão observada zero: projeção indisponível.'
          when b.oportunidades < v_min then format('Amostra insuficiente: %s oportunidades (mínimo configurado: %s).', b.oportunidades, v_min)
          else null end,
        'cenario_pipeline', jsonb_build_object(
          'rotulo', 'Cenário complementar (não é o indicador oficial)',
          'taxa_conversao_decididas', round(b.taxa, 4),
          'ingressos_esperados_pipeline', case when b.taxa is null then null else round(b.abertas * b.taxa, 1) end,
          'projecao_ingressos', case when b.taxa is null then null else round(b.ingressantes + b.abertas * b.taxa, 1) end,
          'novas_oportunidades_necessarias', case when b.n_metas = 0 or b.taxa is null or b.taxa = 0 then null
            else greatest(ceil((b.meta - b.ingressantes - b.abertas * b.taxa) / b.taxa), 0) end),
        'receita_mensal_ingressantes_centavos', b.receita_ingressos,
        'receita_mensal_potencial_ofertada_centavos', b.receita_ofertada,
        'propostas_validas', b.n_ofertas,
        'custo_por_lead_centavos', null, 'custo_por_matricula_centavos', null,
        'custo_motivo', 'Sem investimento cadastrado: disponível com o módulo de Campanhas (P1).',
        'metodos', jsonb_build_object(
          'conversao', 'Ingressantes efetivos (pessoas distintas) ÷ oportunidades da mesma coorte (Bíblia §6).',
          'projecao', 'Oportunidades adicionais = ⌈meta restante ÷ conversão observada⌉, com a conversão não arredondada (Bíblia §6). N/D com conversão zero ou amostra abaixo do mínimo configurado; zero com a meta cumprida.',
          'cenario', 'Cenário complementar: taxa sobre oportunidades decididas (ingresso, perda ou cancelamento) aplicada ao pipeline aberto. Não substitui o indicador oficial.',
          'receita', 'Receita potencial = soma das mensalidades ofertadas válidas (propostas ativas dentro da validade ou aceitas), valor mensal, natureza de projeção (Bíblia §6). Ingressantes: mensalidade da proposta aceita ou mensalidade cheia do curso.',
          'funil', 'Oportunidades que ALCANÇARAM cada etapa, reconstruído pelo histórico auditado. Quem confirmou e depois cancelou conta no alcance do ingresso, mas não entre os ingressantes efetivos.'))
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

create or replace function public.rpc_bi(p_ies bigint, p_coorte text, p_agrupar text default 'curso')
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare t record; v_meta bigint; v_metas int; linhas jsonb; v_total boolean;
  todos text[] := array['gestor','reitoria','coordenador','comercial','secretaria','financeiro'];
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if p_coorte !~ '^\d{4}\.[12]$' then raise exception 'Coorte deve ter formato AAAA.1 ou AAAA.2' using errcode = '22023'; end if;
  if p_agrupar not in ('curso','turno','modalidade','forma_ingresso','atendente') then raise exception 'Agrupamento inválido' using errcode = '22023'; end if;
  v_total := privado.tem_acesso_ies(p_ies, todos);
  select count(*) as oportunidades,
         count(*) filter (where o.matricula_comercial_em is not null) as matriculas_comerciais,
         count(distinct o.pessoa_id) filter (where o.etapa = 'confirmado') as ingressantes,
         count(*) filter (where o.etapa = 'cancelado') as cancelamentos,
         count(*) filter (where o.etapa = 'perdido') as perdidos
    into t
    from public.oportunidades o
   where o.ies_id = p_ies and o.coorte = p_coorte and privado.tem_acesso(o.ies_id, o.curso_id, todos);
  select count(*), sum(m.meta) into v_metas, v_meta from public.metas m
   where m.ies_id = p_ies and m.coorte = p_coorte and privado.tem_acesso(m.ies_id, m.curso_id, todos);
  if v_metas = 0 then v_meta := null; end if;
  select coalesce(jsonb_agg(jsonb_build_object('chave', x.chave, 'curso_id', x.curso_id, 'oportunidades', x.n,
           'matriculas_comerciais', x.mc, 'ingressantes', x.ing, 'cancelamentos', x.canc, 'perdidos', x.perd,
           'conversao', case when x.n = 0 then null else round(x.ing::numeric / x.n, 4) end,
           'meta', m.meta,
           'atingimento', case when m.meta is null or m.meta = 0 then null else round(x.ing::numeric / m.meta, 4) end) order by x.chave), '[]'::jsonb)
    into linhas
    from (select case p_agrupar when 'curso' then c.nome || ' · ' || c.turno when 'turno' then c.turno when 'modalidade' then c.modalidade
                   when 'forma_ingresso' then o.forma_ingresso else coalesce(r.nome, 'Sem responsável') end as chave,
                 case when p_agrupar = 'curso' then c.id end as curso_id,
                 count(*) as n,
                 count(*) filter (where o.matricula_comercial_em is not null) as mc,
                 count(distinct o.pessoa_id) filter (where o.etapa = 'confirmado') as ing,
                 count(*) filter (where o.etapa = 'cancelado') as canc,
                 count(*) filter (where o.etapa = 'perdido') as perd
            from public.oportunidades o join public.cursos c on c.id = o.curso_id left join public.usuarios r on r.id = o.responsavel_id
           where o.ies_id = p_ies and o.coorte = p_coorte and privado.tem_acesso(o.ies_id, o.curso_id, todos)
           group by 1, 2) x
    left join public.metas m on x.curso_id is not null and m.ies_id = p_ies and m.curso_id = x.curso_id and m.coorte = p_coorte;
  return jsonb_build_object(
    'coorte', p_coorte, 'agrupar', p_agrupar, 'cobertura', case when v_total then 'ies' else 'cursos_autorizados' end,
    'totais', jsonb_build_object(
      'oportunidades', t.oportunidades, 'matriculas_comerciais', t.matriculas_comerciais, 'ingressantes', t.ingressantes,
      'cancelamentos', t.cancelamentos, 'perdidos', t.perdidos,
      'conversao', case when t.oportunidades = 0 then null else round(t.ingressantes::numeric / t.oportunidades, 4) end,
      'meta', v_meta,
      'atingimento', case when v_meta is null or v_meta = 0 then null else round(t.ingressantes::numeric / v_meta, 4) end,
      -- Projeção (migração 7): taxa sobre oportunidades DECIDIDAS (ingresso, perda ou cancelamento).
      -- A coorte em andamento não entra no denominador. Sem base decidida => N/D.
      'oportunidades_abertas', t.oportunidades - t.ingressantes - t.perdidos - t.cancelamentos,
      'taxa_conversao_decididas', case when (t.ingressantes + t.perdidos + t.cancelamentos) = 0 then null
        else round(t.ingressantes::numeric / (t.ingressantes + t.perdidos + t.cancelamentos), 4) end,
      'ingressos_esperados_pipeline', case when (t.ingressantes + t.perdidos + t.cancelamentos) = 0 then null
        else round((t.oportunidades - t.ingressantes - t.perdidos - t.cancelamentos)
                   * t.ingressantes::numeric / (t.ingressantes + t.perdidos + t.cancelamentos), 1) end,
      'lacuna_meta', case when v_meta is null then null else greatest(v_meta - t.ingressantes, 0) end,
      'projecao_oportunidades_necessarias', case
        when v_meta is null then null
        when greatest(v_meta - t.ingressantes, 0) = 0 then 0
        when t.ingressantes = 0 or t.oportunidades < (select amostra_minima_forecast from public.ies where id = p_ies) then null
        else (greatest(v_meta - t.ingressantes, 0)::bigint * t.oportunidades + t.ingressantes - 1) / t.ingressantes end,
      'projecao_metodo', 'Oportunidades adicionais = ⌈meta restante ÷ conversão observada⌉ em aritmética exata (Bíblia §6); N/D com conversão zero ou amostra abaixo do mínimo.'),
    'linhas', linhas);
end $$;

create or replace function public.rpc_estrutura(p_ies bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare i public.ies;
  todos text[] := array['gestor','reitoria','coordenador','comercial','secretaria','financeiro'];
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  select * into i from public.ies where id = p_ies;
  return jsonb_build_object(
    'ies', jsonb_build_object('id', i.id, 'nome', i.nome, 'plano', i.plano, 'sla_horas', i.sla_horas, 'max_followups', i.max_followups,
                              'dias_sem_contato', i.dias_sem_contato, 'capacidade_atendente', i.capacidade_atendente, 'amostra_minima_forecast', i.amostra_minima_forecast),
    'papeis', (select coalesce(jsonb_agg(distinct e.papel), '[]'::jsonb) from public.escopos e
               where e.usuario_id = (select auth.uid()) and e.ies_id = p_ies and e.revogado_em is null),
    'acesso_total', privado.tem_acesso_ies(p_ies, todos),
    'cursos', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.nome, 'turno', c.turno, 'modalidade', c.modalidade,
                 'mensalidade_centavos', c.mensalidade_centavos, 'desconto_max_pct', c.desconto_max_pct, 'campus', cp.nome) order by c.nome), '[]'::jsonb)
               from public.cursos c join public.campus cp on cp.id = c.campus_id
               where c.ies_id = p_ies and privado.tem_acesso(p_ies, c.id, todos)),
    'coortes', (select coalesce(jsonb_agg(x.coorte order by x.coorte desc), '[]'::jsonb) from (
                 select distinct o.coorte from public.oportunidades o where o.ies_id = p_ies and privado.tem_acesso(o.ies_id, o.curso_id, todos)
                 union select distinct m.coorte from public.metas m where m.ies_id = p_ies and privado.tem_acesso(m.ies_id, m.curso_id, todos)) x),
    'etapas', '["novo","contato","inscrito","pre_matricula","matricula_comercial","confirmado","perdido","cancelado"]'::jsonb,
    'formas_ingresso', '["vestibular","enem","transferencia","segunda_graduacao","reingresso","indicacao","convenio","visita_escolar","evento","pos_graduacao"]'::jsonb,
    'bases_legais', '["consentimento","procedimentos_preliminares_contrato","legitimo_interesse"]'::jsonb,
    'canais', '["email","whatsapp","telefone"]'::jsonb);
end $$;

drop function if exists public.rpc_configurar(bigint, int, int, int, int);
create or replace function public.rpc_configurar(p_ies bigint, p_sla_horas int default null, p_max_followups int default null,
  p_dias_sem_contato int default null, p_capacidade_atendente int default null,
  p_amostra_minima_forecast int default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.ies;
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if not privado.tem_acesso_ies(p_ies, array['gestor']) then raise exception 'Seu perfil não tem permissão para esta operação' using errcode = '42501'; end if;
  if coalesce(p_sla_horas, p_max_followups, p_dias_sem_contato, p_capacidade_atendente, p_amostra_minima_forecast) is null then
    raise exception 'Nada a alterar' using errcode = '22023';
  end if;
  update public.ies set
    sla_horas = coalesce(p_sla_horas, sla_horas),
    max_followups = coalesce(p_max_followups, max_followups),
    dias_sem_contato = coalesce(p_dias_sem_contato, dias_sem_contato),
    capacidade_atendente = coalesce(p_capacidade_atendente, capacidade_atendente),
    amostra_minima_forecast = coalesce(p_amostra_minima_forecast, amostra_minima_forecast)
   where id = p_ies returning * into r;
  perform privado.auditar(p_ies, 'ies.configurar', 'ies', p_ies::text, jsonb_build_object(
    'sla_horas', r.sla_horas, 'max_followups', r.max_followups, 'dias_sem_contato', r.dias_sem_contato, 'capacidade_atendente', r.capacidade_atendente, 'amostra_minima_forecast', r.amostra_minima_forecast));
  return jsonb_build_object('sla_horas', r.sla_horas, 'max_followups', r.max_followups,
    'dias_sem_contato', r.dias_sem_contato, 'capacidade_atendente', r.capacidade_atendente, 'amostra_minima_forecast', r.amostra_minima_forecast);
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.rpc_central(bigint, text, jsonb), public.rpc_bi(bigint, text, text),
  public.rpc_estrutura(bigint), public.rpc_configurar(bigint, int, int, int, int, int) to authenticated;
