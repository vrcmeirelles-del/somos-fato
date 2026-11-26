-- Testes do BI da alta gestão (migração 32).
\set ON_ERROR_STOP on
reset role;
select teste.ok(privado.coorte_anterior('2027.1') = '2026.2' and privado.coorte_anterior('2027.2') = '2027.1', 'coorte anterior');
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro($q$select public.rpc_bi_executivo('2027.1')$q$, '42501', 'comercial não acessa o BI da alta gestão');
select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false);
select teste.erro($q$select public.rpc_bi_executivo('2027.1')$q$, '42501', 'coordenação de curso não acessa');
select set_config('request.jwt.claim.sub', teste.id('reitoria_a')::text, false);
select teste.erro($q$select public.rpc_bi_executivo('2027-1')$q$, '22023', 'coorte inválida recusada');
select teste.ok((select jsonb_array_length(r->'ies') = 1 and r->'ies'->0->>'nome' is not null and r->>'coorte_anterior' = '2026.2'
                   and r->'ies'->0->'atual' ? 'conversao' and r->'ies'->0 ? 'bolsas' and r->'ies'->0 ? 'inadimplencia' and r->'metodos' ? 'payback'
                 from (select public.rpc_bi_executivo('2027.1') r) x), 'reitoria vê só a sua IES, com captação, bolsas, inadimplência e métodos');
select teste.ok((select (r->'ies'->0->'atual'->>'ingressantes')::int = (public.rpc_central(1, '2027.1')->'totais'->>'ingressantes')::int
                 from (select public.rpc_bi_executivo('2027.1') r) x), 'captação idêntica à da Central');
select teste.ok((select (r->'ies'->0->'atual'->>'ingressantes')::int = 0 or (r->'ies'->0->'receita'->>'ticket_medio_centavos')::numeric
                   = round((r->'ies'->0->'atual'->>'receita_mensal_ingressantes_centavos')::numeric / (r->'ies'->0->'atual'->>'ingressantes')::int)
                 from (select public.rpc_bi_executivo('2027.1') r) x), 'ticket médio na mesma base da receita');
select teste.ok((select r->'consolidado'->>'ingressantes' = r->'ies'->0->'atual'->>'ingressantes' from (select public.rpc_bi_executivo('2027.1') r) x), 'consolidado de uma IES = a própria IES');
select teste.ok((select (r->'ies'->0->'inadimplencia'->>'inadimplentes')::int >= 1 and jsonb_typeof(r->'ies'->0->'alertas') = 'array'
                 from (select public.rpc_bi_executivo('2027.1') r) x), 'inadimplência conta a pendência vencida e há lista de alertas');
select teste.ok((select jsonb_array_length(g->'serie_coortes') = 4 and g->'serie_coortes'->3->>'coorte' = '2027.1' and g->'serie_coortes'->0->>'coorte' = '2025.2'
                   and (g->'serie_coortes'->3->>'meta')::int = 16 and jsonb_array_length(g->'aging') = 4 and jsonb_typeof(g->'evolucao') = 'array'
                   and jsonb_typeof(g->'perdas') = 'array' and jsonb_typeof(g->'funil') = 'array'
                 from (select public.rpc_bi_executivo('2027.1')->'ies'->0->'graficos' g) x), 'gráficos: 4 coortes com meta, faixas de atraso, evolução, perdas e funil');
select teste.ok((select (select sum((a->>'quantidade')::int) from jsonb_array_elements(g->'aging') a) >= 1
                 from (select public.rpc_bi_executivo('2027.1')->'ies'->0->'graficos' g) x), 'faixas de atraso contam as pendências vencidas');
-- mantenedora: gestora com as duas IES vê o consolidado
reset role;
insert into public.escopos(usuario_id, ies_id, abrangencia, papel) values (teste.id('gestor_a'), 2, 'ies', 'gestor');
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.ok((select jsonb_array_length(r->'ies') = 2
                   and (r->'consolidado'->>'oportunidades')::int = (r->'ies'->0->'atual'->>'oportunidades')::int + (r->'ies'->1->'atual'->>'oportunidades')::int
                   and (r->'consolidado'->>'ingressantes')::int = (r->'ies'->0->'atual'->>'ingressantes')::int + (r->'ies'->1->'atual'->>'ingressantes')::int
                 from (select public.rpc_bi_executivo('2027.1') r) x), 'com as duas IES: consolidado soma as instituições');
select teste.ok((select r->'consolidado'->'meta' = 'null'::jsonb and r->'consolidado'->'atingimento' = 'null'::jsonb
                 from (select public.rpc_bi_executivo('2027.1') r) x), 'meta consolidada N/D quando uma IES não tem meta');
select teste.ok((select exists (select 1 from jsonb_array_elements(r->'ies') i, jsonb_array_elements(i->'alertas') a where a->>'texto' like 'Coorte sem meta%')
                 from (select public.rpc_bi_executivo('2027.1') r) x), 'alerta de IES sem meta');
select teste.ok((select jsonb_array_length(r->'ies') = 1 from (select public.rpc_bi_executivo('2027.1', array[1::bigint]) r) x), 'filtro por IES');
select teste.ok((select jsonb_array_length(r->'ies') = 1 from (select public.rpc_bi_executivo('2027.1', array[1::bigint, 999]) r) x), 'IES sem acesso no filtro é ignorada');
reset role;
delete from public.escopos where usuario_id = teste.id('gestor_a') and ies_id = 2;
select teste.ok((select count(*) = 0 from public.automacoes_execucoes where fim < inicio), 'automações: fim nunca antes do início');
