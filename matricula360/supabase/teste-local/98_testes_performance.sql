-- Testes do MAIM Performance (migração 14).
\set ON_ERROR_STOP on
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
insert into teste.var values ('perf_ok', 1);
select teste.ok((select jsonb_array_length(r->'etapas') = 5 and r->>'regra' = 'performance-v1' and r->>'aviso' like '%decisões laborais%'
                 from (select public.rpc_performance(1, '2027.1') r) x), 'cinco etapas oficiais, regra versionada e aviso de uso');
select teste.ok((select bool_and((e->>'denominador')::int = (e->>'alcancaram')::int and ((e->>'alcancaram')::int = 0) = (e->'conversao_etapa' = 'null'::jsonb))
                 from jsonb_array_elements(public.rpc_performance(1, '2027.1')->'etapas') e), 'conversão da etapa com denominador explícito; N/D sem base');
select teste.ok((select (e->>'alcancaram')::int = (select count(*) from public.oportunidades where ies_id = 1 and coorte = '2027.1')
                 from jsonb_array_elements(public.rpc_performance(1, '2027.1')->'etapas') e where e->>'etapa' = 'novo'), 'toda oportunidade da coorte alcançou a etapa novo');
select teste.ok((select bool_and((e->>'avancaram')::int <= (e->>'alcancaram')::int) from jsonb_array_elements(public.rpc_performance(1, '2027.1')->'etapas') e), 'avanço nunca excede o alcance');
select teste.ok((select r->'gargalo' = 'null'::jsonb or ((r->'gargalo'->>'alcancaram')::int >= 10) from (select public.rpc_performance(1, '2027.1') r) x), 'gargalo só com amostra mínima');
select teste.ok((select jsonb_array_length(r->'atendentes') >= 2 and (r->>'ve_equipe')::boolean from (select public.rpc_performance(1, '2027.1') r) x), 'gestor vê a equipe');
select teste.ok((select bool_and(a->'sla_primeiro_contato' = 'null'::jsonb or ((a->>'sla_primeiro_contato')::numeric between 0 and 1 and (a->>'sla_denominador')::int > 0))
                 from jsonb_array_elements(public.rpc_performance(1, '2027.1')->'atendentes') a), 'SLA do primeiro contato entre 0 e 1 com denominador');
select teste.ok((select sum((a->>'oportunidades')::int) = (select count(*) from public.oportunidades where ies_id = 1 and coorte = '2027.1')
                 from jsonb_array_elements(public.rpc_performance(1, '2027.1')->'atendentes') a), 'soma por atendente fecha com o total da coorte');
select teste.ok((select bool_and(x->>'regra' like 'performance-v1/%' and length(x->>'justificativa') > 10) from jsonb_array_elements(public.rpc_performance(1, '2027.1')->'recomendacoes') x) is not false,
  'recomendações com regra versionada e justificativa');
select teste.ok((select (e->>'alcancaram')::int <= (select count(*) from public.oportunidades where ies_id = 1 and coorte = '2027.1' and curso_id = 1)
                 from jsonb_array_elements(public.rpc_performance(1, '2027.1', '{"curso_id":"1"}')->'etapas') e where e->>'etapa' = 'novo'), 'filtro de curso aplicado');
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.ok((select (r->>'ve_equipe')::boolean = false and jsonb_array_length(r->'atendentes') <= 1 and coalesce(bool_and((a->>'eu')::boolean), true)
                 from (select public.rpc_performance(1, '2027.1') r) x left join lateral jsonb_array_elements(r->'atendentes') a on true group by r),
  'atendente vê apenas a própria linha');
select teste.ok((public.rpc_performance(1, '2027.1')->'sla_primeiro_contato_equipe') = 'null'::jsonb, 'atendente não vê o SLA consolidado da equipe');
select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false);
select teste.ok((select jsonb_array_length(r->'atendentes') = 0 and (e->>'alcancaram')::int <= (select count(*) from public.oportunidades where ies_id = 1 and coorte = '2027.1' and curso_id = 1)
                 from (select public.rpc_performance(1, '2027.1') r) x, jsonb_array_elements(r->'etapas') e where e->>'etapa' = 'novo'),
  'coordenação vê etapas só do seu curso e nenhum indicador individual');
select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false);
select teste.erro('select public.rpc_performance(1, ''2027.1'')', '42501', 'secretaria não acessa performance comercial');
select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false);
select teste.erro('select public.rpc_performance(1, ''2027.1'')', 'P0002', 'gestor de outra IES: não encontrado');
select teste.erro('select public.rpc_performance(2, ''2027'')', '22023', 'coorte inválida recusada');
reset role;
select teste.ok(true, 'fim da bateria de performance');
