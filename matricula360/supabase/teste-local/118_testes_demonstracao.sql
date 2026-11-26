-- Testes do ambiente de demonstração (migração 36).
\set ON_ERROR_STOP on
reset role;
create temp table dm (chave text primary key, v text);
grant all on dm to anon, authenticated;
set role authenticated;
select set_config('request.jwt.claims', '', false);
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.erro($q$select public.rpc_master_criar_demo()$q$, '42501', 'só o Master cria a demonstração');
select teste.erro($q$select public.rpc_restaurar_demo(1)$q$, '42501', 'IES real não pode ser restaurada');
select set_config('request.jwt.claim.sub', teste.id('master')::text, false);
insert into dm select 'r', public.rpc_master_criar_demo()::text;
insert into dm select 'ies', (v::jsonb->>'ies_id') from dm where chave = 'r';
reset role;
select teste.ok((select demonstracao from public.ies where id = (select v::bigint from dm where chave = 'ies')), 'IES criada e marcada como demonstração');
select teste.ok((select count(*) >= 500 from public.oportunidades where ies_id = (select v::bigint from dm where chave = 'ies')), 'carga com centenas de oportunidades');
select teste.ok((select count(distinct coorte) = 4 from public.oportunidades where ies_id = (select v::bigint from dm where chave = 'ies')), 'quatro coortes');
select teste.ok((select count(*) > 0 from public.custos_campanha where ies_id = (select v::bigint from dm where chave = 'ies'))
            and (select count(*) > 0 from public.solicitacoes_bolsa where ies_id = (select v::bigint from dm where chave = 'ies') and status = 'aprovada')
            and (select count(*) > 0 from public.rematriculas where ies_id = (select v::bigint from dm where chave = 'ies'))
            and (select count(*) > 0 from public.vinculos where ies_id = (select v::bigint from dm where chave = 'ies'))
            and (select count(*) > 0 from public.pendencias_financeiras where ies_id = (select v::bigint from dm where chave = 'ies'))
            and (select count(*) > 0 from public.casos where ies_id = (select v::bigint from dm where chave = 'ies'))
            and (select count(*) >= 50 from public.respostas_pesquisa r join public.pesquisas p on p.id = r.pesquisa_id where p.ies_id = (select v::bigint from dm where chave = 'ies')),
  'custos, bolsas, rematrícula, vínculos, pendências, casos e respostas de pesquisa preenchidos');
select teste.ok((select bool_and(email like '%@exemplo.invalid' and nome like '%(fictício)') from public.pessoas where ies_id = (select v::bigint from dm where chave = 'ies')), 'todos os dados pessoais são fictícios');
select teste.ok((select count(*) = 0 from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id where o.ies_id = (select v::bigint from dm where chave = 'ies') and p.ies_id <> o.ies_id), 'nada vaza para outra IES');

-- a equipe entra por convite coletivo e o BI da demonstração funciona
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('master')::text, false);
insert into dm select 'cod', public.rpc_criar_convite((select v::bigint from dm where chave = 'ies'), '{"papel":"gestor","usos_max":30}')->>'codigo';
insert into dm select 'codc', public.rpc_criar_convite((select v::bigint from dm where chave = 'ies'), '{"papel":"comercial","usos_max":30}')->>'codigo';
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select set_config('request.jwt.claims', '{"email":"gestora.alfa@exemplo.invalid"}', false);
select teste.ok((public.rpc_aceitar_convite((select v from dm where chave = 'cod'))->>'papel') = 'gestor', 'gestora real entra na demonstração pelo convite coletivo');
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select public.rpc_aceitar_convite((select v from dm where chave = 'codc'));
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select set_config('request.jwt.claims', '', false);
select teste.ok((select jsonb_array_length(r->'ies') = 1 and (r->'ies'->0->>'ies_id')::bigint = 1 from (select public.rpc_bi_executivo('2027.1') r) x),
  'quem atua em IES real não vê a demonstração no consolidado do BI');
select teste.ok((select (r->'ies'->0->'atual'->>'oportunidades')::int > 100 from (select public.rpc_bi_executivo((select (v::jsonb->'coortes'->>0) from dm where chave = 'r'), array[(select v::bigint from dm where chave = 'ies')]) r) x),
  'BI da demonstração pelo filtro de IES, com a carga da coorte atual');
select teste.ok((public.rpc_estrutura((select v::bigint from dm where chave = 'ies'))->'ies'->>'demonstracao')::boolean, 'estrutura avisa que é demonstração');
-- restaurar: apaga movimento, mantém equipe e recria; atendentes passam a ter leads
insert into dm select 'rest', public.rpc_restaurar_demo((select v::bigint from dm where chave = 'ies'))::text;
reset role;
select teste.ok((select (v::jsonb->>'registros_apagados')::int > 500 and (v::jsonb->>'atendentes_com_leads')::int = 1 from dm where chave = 'rest'), 'restauração apaga e recria; atendente que entrou recebe leads');
select teste.ok((select count(*) > 0 from public.oportunidades where ies_id = (select v::bigint from dm where chave = 'ies') and responsavel_id = teste.id('comercial_a')), 'leads atribuídos ao atendente da demonstração');
select teste.ok((select count(*) = 2 from public.escopos where ies_id = (select v::bigint from dm where chave = 'ies') and revogado_em is null), 'equipe mantida após restaurar');
select teste.ok((select count(*) = 3 from public.programas_bolsa where ies_id = (select v::bigint from dm where chave = 'ies')), 'sem duplicar programas');
select teste.ok((select count(*) >= 2 from public.auditoria where acao in ('demo.criar','demo.restaurar')), 'criação e restauração auditadas');
-- limpa os escopos de teste na demonstração para não afetar outros testes
update public.escopos set revogado_em = now() where ies_id = (select v::bigint from dm where chave = 'ies');
