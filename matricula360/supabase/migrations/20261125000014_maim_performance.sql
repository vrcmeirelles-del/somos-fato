-- Matrícula 360° — migração 14: MAIM Performance (Bíblia v0.2 §5, P1).
--   * Por etapa oficial: alcance, avanço, conversão da etapa, perdas, tempo mediano de permanência e parados,
--     sempre com o denominador explícito. Gargalo = menor conversão entre etapas com amostra suficiente.
--   * Por atendente: SLA do primeiro contato, horas até o primeiro contato, interações, matrículas, ingressos.
--     Gestão e reitoria veem a equipe; o atendente vê apenas a própria linha.
--   * Recomendações: regras puras versionadas (performance-v1), com justificativa numérica. Não executam nada.
--   * Aviso obrigatório: apoio à gestão; não usar isoladamente para decisões laborais (Bíblia §5).
-- Idempotente.

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('performance.ver',    'Central de Inteligência', 'Ver gargalos e indicadores por etapa do recorte autorizado', array['gestor','reitoria','coordenador','comercial'], 'curso', 'rpc_performance'),
  ('performance.equipe', 'Central de Inteligência', 'Ver indicadores individuais da equipe comercial',          array['gestor','reitoria'], 'curso', 'rpc_performance')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

create or replace function public.rpc_performance(p_ies bigint, p_coorte text, p_filtros jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  todos constant text[] := array['gestor','reitoria','coordenador','comercial','secretaria','financeiro'];
  amostra_min constant int := 10;  -- regra performance-v1: abaixo disso a conversão da etapa não aponta gargalo
  f_campus bigint := nullif(p_filtros->>'campus_id', '')::bigint;
  f_curso bigint := nullif(p_filtros->>'curso_id', '')::bigint;
  f_turno text := nullif(p_filtros->>'turno', '');
  f_modal text := nullif(p_filtros->>'modalidade', '');
  equipe boolean; cfg public.ies; etapas jsonb; atendentes jsonb; gargalo jsonb; recs jsonb := '[]'::jsonb; sla_eq numeric; v_parados int;
begin
  perform privado.autorizar(p_ies, 'performance.ver');
  if p_coorte !~ '^\d{4}\.[12]$' then raise exception 'Coorte deve ter formato AAAA.1 ou AAAA.2' using errcode = '22023'; end if;
  equipe := privado.pode(p_ies, 'performance.equipe');
  select * into cfg from public.ies where id = p_ies;

  create temp table if not exists pg_temp.perf_ops (id bigint primary key, etapa text, responsavel_id uuid, pessoa_id bigint, criado_em timestamptz,
    matricula_comercial_em timestamptz, confirmada_em timestamptz, atualizado_em timestamptz, alcance int) on commit drop;
  truncate pg_temp.perf_ops;
  insert into pg_temp.perf_ops
  select o.id, o.etapa, o.responsavel_id, o.pessoa_id, o.criado_em, o.matricula_comercial_em, o.confirmada_em, o.atualizado_em,
         greatest(case when o.etapa in ('perdido','cancelado') then 0 else privado.ordem_etapa(o.etapa) end,
                  case when o.confirmada_em is not null then 6 when o.matricula_comercial_em is not null then 5 else 0 end,
                  coalesce((select max(greatest(privado.ordem_etapa(a.dados->>'de'), privado.ordem_etapa(a.dados->>'para')))
                              from public.auditoria a where a.entidade = 'oportunidade' and a.entidade_id = o.id::text and a.acao = 'oportunidade.etapa'), 1))
    from public.oportunidades o join public.cursos c on c.id = o.curso_id
   where o.ies_id = p_ies and o.coorte = p_coorte and privado.tem_acesso(o.ies_id, o.curso_id, todos)
     and (f_campus is null or c.campus_id = f_campus) and (f_curso is null or c.id = f_curso)
     and (f_turno is null or c.turno = f_turno) and (f_modal is null or c.modalidade = f_modal);

  -- Movimentos auditados (entradas e saídas de cada etapa) para medir permanência e perdas por etapa.
  with mov as (
    select a.entidade_id::bigint as op, a.dados->>'de' as de, a.dados->>'para' as para, a.em
      from public.auditoria a join pg_temp.perf_ops p on p.id::text = a.entidade_id
     where a.entidade = 'oportunidade' and a.acao = 'oportunidade.etapa'
  ), entradas as (
    select id as op, 'novo' as etapa, criado_em as em from pg_temp.perf_ops
    union all select op, para, em from mov
  ), permanencia as (
    select e.etapa, extract(epoch from (select min(m.em) from mov m where m.op = e.op and m.de = e.etapa and m.em >= e.em) - e.em) / 3600 as horas
      from entradas e
  ), base as (
    select s.k, s.etapa,
           (select count(*) from pg_temp.perf_ops where alcance >= s.k) as alcancaram,
           (select count(*) from pg_temp.perf_ops where alcance >= s.k + 1) as avancaram,
           (select count(*) from mov where de = s.etapa and para = 'perdido') as perdidos,
           (select percentile_cont(0.5) within group (order by horas) from permanencia where etapa = s.etapa and horas is not null) as horas_mediana,
           (select count(*) from permanencia where etapa = s.etapa and horas is not null) as n_tempo,
           (select count(*) from pg_temp.perf_ops where etapa = s.etapa and atualizado_em < now() - make_interval(days => cfg.dias_sem_contato)) as parados
      from (values (1,'novo'),(2,'contato'),(3,'inscrito'),(4,'pre_matricula'),(5,'matricula_comercial')) s(k, etapa)
  )
  select jsonb_agg(jsonb_build_object('etapa', etapa, 'alcancaram', alcancaram, 'avancaram', avancaram,
           'conversao_etapa', case when alcancaram = 0 then null else round(avancaram::numeric / alcancaram, 4) end,
           'denominador', alcancaram, 'amostra_suficiente', alcancaram >= amostra_min,
           'perdidos_na_etapa', perdidos, 'horas_mediana_na_etapa', round(horas_mediana::numeric, 1), 'medicoes_tempo', n_tempo,
           'parados', parados) order by k)
    into etapas from base;

  select e into gargalo from jsonb_array_elements(etapas) e
   where (e->>'amostra_suficiente')::boolean and e->>'conversao_etapa' is not null
   order by (e->>'conversao_etapa')::numeric, e->>'etapa' limit 1;

  -- Indicadores por atendente (responsável atual). Denominadores explícitos; N/D quando não há base.
  with t as (
    select p.responsavel_id, x.status, x.vence_em, x.encerrada_em, p.criado_em as op_criada
      from pg_temp.perf_ops p join public.tarefas x on x.oportunidade_id = p.id and x.tipo = 'primeiro_contato'
  ), por as (
    select p.responsavel_id, count(*) as oportunidades,
           count(*) filter (where p.matricula_comercial_em is not null) as matriculas_comerciais,
           count(distinct p.pessoa_id) filter (where p.etapa = 'confirmado') as ingressantes,
           (select count(*) from t where t.responsavel_id is not distinct from p.responsavel_id and t.status = 'concluida' and t.encerrada_em <= t.vence_em) as sla_no_prazo,
           (select count(*) from t where t.responsavel_id is not distinct from p.responsavel_id and (t.status = 'concluida' or (t.status = 'aberta' and t.vence_em < now()))) as sla_base,
           (select percentile_cont(0.5) within group (order by extract(epoch from t.encerrada_em - t.op_criada) / 3600) from t
             where t.responsavel_id is not distinct from p.responsavel_id and t.status = 'concluida') as horas_primeiro_contato,
           (select count(*) from public.interacoes i join pg_temp.perf_ops q on q.id = i.oportunidade_id where i.usuario_id = p.responsavel_id) as interacoes,
           (select count(*) from public.tarefas x join pg_temp.perf_ops q on q.id = x.oportunidade_id where x.responsavel_id = p.responsavel_id and x.status = 'aberta' and x.vence_em < now()) as tarefas_atrasadas
      from pg_temp.perf_ops p group by p.responsavel_id
  )
  select jsonb_agg(jsonb_build_object('atendente', coalesce(privado.nome_usuario(responsavel_id), 'Sem responsável'), 'eu', responsavel_id = (select auth.uid()),
           'oportunidades', oportunidades, 'matriculas_comerciais', matriculas_comerciais, 'ingressantes', ingressantes,
           'conversao', case when oportunidades = 0 then null else round(ingressantes::numeric / oportunidades, 4) end,
           'sla_primeiro_contato', case when sla_base = 0 then null else round(sla_no_prazo::numeric / sla_base, 4) end, 'sla_denominador', sla_base,
           'horas_ate_primeiro_contato', round(horas_primeiro_contato::numeric, 1), 'interacoes', interacoes, 'tarefas_atrasadas', tarefas_atrasadas)
           order by oportunidades desc)
    into atendentes from por
   where equipe or responsavel_id = (select auth.uid());

  -- Recomendações (performance-v1): propostas com justificativa; nada é executado.
  if gargalo is not null then
    recs := recs || jsonb_build_object('regra', 'performance-v1/gargalo', 'prioridade', 1,
      'titulo', format('Gargalo na etapa %s', gargalo->>'etapa'),
      'justificativa', format('%s de %s oportunidades avançaram (%s%%), a menor conversão entre as etapas com amostra mínima de %s.',
                              gargalo->>'avancaram', gargalo->>'alcancaram', round((gargalo->>'conversao_etapa')::numeric * 100, 1), amostra_min),
      'proposta', case gargalo->>'etapa'
        when 'novo' then 'Reforçar o primeiro contato: cumprir o SLA e revisar a qualidade dos leads por origem.'
        when 'contato' then 'Revisar roteiro e cadência da etapa de contato no funil e tratar as objeções mais frequentes.'
        when 'inscrito' then 'Acompanhar inscritos até a prova/análise e antecipar a apresentação das condições.'
        when 'pre_matricula' then 'Revisar propostas e bolsas pendentes e o prazo de validade das ofertas.'
        else 'Concluir as validações documental, financeira e acadêmica das matrículas comerciais.' end);
  end if;
  select round(sum((a->>'sla_primeiro_contato')::numeric * (a->>'sla_denominador')::int) / nullif(sum((a->>'sla_denominador')::int), 0), 4)
    into sla_eq from jsonb_array_elements(coalesce(atendentes, '[]'::jsonb)) a where a->>'sla_primeiro_contato' is not null;
  if equipe and sla_eq is not null and sla_eq < 0.8 then
    recs := recs || jsonb_build_object('regra', 'performance-v1/sla', 'prioridade', 1, 'titulo', 'SLA do primeiro contato abaixo de 80%',
      'justificativa', format('Cumprimento da equipe: %s%%.', round(sla_eq * 100, 1)),
      'proposta', 'Rever capacidade por atendente e distribuição nas Configurações; priorizar a fila do MAIM.');
  end if;
  select sum((e->>'parados')::int) into v_parados from jsonb_array_elements(etapas) e;
  if v_parados > 0 then
    recs := recs || jsonb_build_object('regra', 'performance-v1/parados', 'prioridade', 2, 'titulo', 'Oportunidades paradas',
      'justificativa', format('%s oportunidade(s) abertas sem atualização há mais de %s dias.', v_parados, cfg.dias_sem_contato),
      'proposta', 'Executar o ciclo do MAIM para gerar follow-ups ou registrar o contato realizado.');
  end if;

  return jsonb_build_object('coorte', p_coorte, 'regra', 'performance-v1', 'amostra_minima_etapa', amostra_min, 've_equipe', equipe,
    'etapas', coalesce(etapas, '[]'::jsonb), 'gargalo', gargalo, 'atendentes', coalesce(atendentes, '[]'::jsonb),
    'sla_primeiro_contato_equipe', case when equipe then sla_eq end, 'recomendacoes', recs,
    'aviso', 'Indicadores de apoio à gestão comercial. Não devem ser usados isoladamente para decisões laborais nem para decidir ingresso.',
    'metodos', jsonb_build_object(
      'conversao_etapa', 'Oportunidades que alcançaram a etapa seguinte ÷ oportunidades que alcançaram a etapa (alcance reconstruído pelo histórico auditado). Gargalo só com denominador ≥ amostra mínima.',
      'permanencia', 'Mediana das horas entre a entrada e a saída da etapa, a partir dos movimentos auditados; oportunidades ainda na etapa não entram na medição.',
      'sla', 'Tarefas de primeiro contato concluídas no prazo ÷ (concluídas + abertas vencidas).',
      'parados', format('Abertas na etapa sem atualização há mais de %s dias (parâmetro da instituição).', cfg.dias_sem_contato)));
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.rpc_performance(bigint, text, jsonb) to authenticated;
