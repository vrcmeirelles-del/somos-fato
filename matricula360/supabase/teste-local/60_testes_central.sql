-- Testes da Central de Inteligência (migração 8).
\set ON_ERROR_STOP on
set role anon;
select teste.erro('select public.rpc_central(1, ''2027.1'')', '42501', 'anon não acessa a Central');
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
insert into teste.var values ('c_ops', (public.rpc_central(1, '2027.1')->'totais'->>'oportunidades')::bigint);
select teste.ok((select v from teste.var where k='c_ops') = (public.rpc_bi(1, '2027.1')->'totais'->>'oportunidades')::bigint, 'Central e BI concordam no total de oportunidades');
select teste.ok((public.rpc_central(1, '2027.1')->'totais'->>'ingressantes') = (public.rpc_bi(1, '2027.1')->'totais'->>'ingressantes'), 'Central e BI concordam nos ingressantes');
select teste.ok((public.rpc_central(1, '2027.1')->'funil'->0->>'quantidade')::bigint = (select v from teste.var where k='c_ops'), 'funil começa no total de oportunidades');
select teste.ok((select bool_and(coalesce((x->>'conversao_da_anterior')::numeric, 0) <= 1) from jsonb_array_elements(public.rpc_central(1, '2027.1')->'funil') x), 'funil nunca aumenta entre etapas');
-- O funil conta quem ALCANÇOU a etapa (histórico); ingressantes efetivos excluem quem cancelou após confirmar.
select teste.ok((public.rpc_central(1, '2027.1')->'funil'->5->>'quantidade')::bigint
                 = (select count(*) from public.oportunidades where ies_id = 1 and coorte = '2027.1' and confirmada_em is not null), 'última etapa do funil = oportunidades que alcançaram o ingresso');
select teste.ok((public.rpc_central(1, '2027.1')->'funil'->5->>'quantidade')::int >= (public.rpc_central(1, '2027.1')->'totais'->>'ingressantes')::int, 'alcance do ingresso ≥ ingressantes efetivos (diferença = cancelamentos após confirmar)');
select teste.ok((public.rpc_central(1, '2027.1')->'totais'->>'custo_por_lead_centavos') is null and (public.rpc_central(1, '2027.1')->'totais'->>'custo_motivo') similar to '(Sem investimento cadastrado|Sem custo lançado)%', 'custo por lead N/D com motivo (sem custo lançado)');
select teste.ok((public.rpc_central(1, '2031.1')->'totais'->>'taxa_conversao_decididas') is null and (public.rpc_central(1, '2031.1')->'totais'->>'oportunidades')::int = 0, 'coorte vazia: zero oportunidades e taxa N/D');
select teste.ok(jsonb_array_length(public.rpc_central(1, '2027.1')->'evolucao') = 12, 'evolução cobre 12 semanas');
select teste.ok((select sum((x->>'oportunidades')::int) from jsonb_array_elements(public.rpc_central(1, '2027.1')->'por_origem') x) = (select v from teste.var where k='c_ops'), 'origem soma o total');
select teste.ok((select sum((x->>'oportunidades')::int) from jsonb_array_elements(public.rpc_central(1, '2027.1')->'por_atendente') x) = (select v from teste.var where k='c_ops'), 'atendente soma o total');
-- filtros globais
select teste.ok((public.rpc_central(1, '2027.1', '{"curso_id": 1}')->'totais'->>'oportunidades')::bigint
                 = (select count(*) from public.oportunidades where ies_id = 1 and curso_id = 1 and coorte = '2027.1'), 'filtro de curso restringe o recorte');
select teste.ok(public.rpc_central(1, '2027.1', '{"curso_id": 1}')->>'cobertura' = 'recorte', 'filtro marca cobertura como recorte');
select teste.ok((public.rpc_central(1, '2027.1', '{"modalidade": "ead"}')->'totais'->>'oportunidades')::bigint
                 = (select count(*) from public.oportunidades o join public.cursos c on c.id = o.curso_id where o.ies_id = 1 and c.modalidade = 'ead' and o.coorte = '2027.1'), 'filtro de modalidade');
select teste.ok((public.rpc_central(1, '2027.1', '{"curso_id": 3}')->'totais'->>'oportunidades')::int = 0, 'filtro com curso de outra IES não vaza dados');
-- escopo
select teste.erro('select public.rpc_central(2, ''2027.1'')', 'P0002', 'Central de IES alheia: não encontrado');
select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false);
select teste.ok(public.rpc_central(1, '2027.1')->>'cobertura' = 'recorte'
                and (select bool_and(x->>'chave' like 'Direito%') from jsonb_array_elements(public.rpc_central(1, '2027.1')->'por_curso') x), 'coordenador vê só Direito na Central');
select teste.ok(jsonb_array_length(public.rpc_central(1, '2027.1')->'filtros_disponiveis'->'turnos') = 1, 'filtros disponíveis respeitam o escopo');
select set_config('request.jwt.claim.sub', teste.id('master')::text, false);
select teste.erro('select public.rpc_central(1, ''2027.1'')', 'P0002', 'Master sem escopo não acessa a Central');
reset role;
do $$ begin raise notice 'OK  fim da bateria da Central'; end $$;
