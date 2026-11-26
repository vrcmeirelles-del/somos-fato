-- Testes das correções da Fase 2 (migração 7). Reproduzem os defeitos do diagnóstico e provam a correção.
\set ON_ERROR_STOP on
set role authenticated;

-- (2) proposta ativa única
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
insert into teste.var values ('f2op', (select min(id) from public.oportunidades where ies_id = 1 and curso_id = 1 and etapa = 'novo'));
select public.rpc_mover_etapa((select v from teste.var where k='f2op'), 'contato', (select versao from public.oportunidades where id = (select v from teste.var where k='f2op')));
select public.rpc_mover_etapa((select v from teste.var where k='f2op'), 'inscrito', (select versao from public.oportunidades where id = (select v from teste.var where k='f2op')));
insert into teste.var values ('f2p1', (public.rpc_criar_proposta((select v from teste.var where k='f2op'), 10)->>'id')::bigint);
insert into teste.var values ('f2p2', (public.rpc_criar_proposta((select v from teste.var where k='f2op'), 20)->>'id')::bigint);
select teste.ok((select status from public.propostas where id = (select v from teste.var where k='f2p1')) = 'substituida', 'nova proposta substitui a anterior ativa');
select teste.ok((select count(*) from public.propostas where oportunidade_id = (select v from teste.var where k='f2op') and status in ('pendente_aprovacao','aprovada')) = 1, 'uma única proposta ativa por oportunidade');
select teste.erro('select public.rpc_aceitar_proposta((select v from teste.var where k=''f2p1''))', '22023', 'proposta substituída não pode ser aceita');
reset role;
select teste.ok((select count(*) from public.auditoria where acao = 'proposta.substituir' and entidade_id = (select v::text from teste.var where k='f2op')) = 1, 'substituição auditada');
set role authenticated;

-- (4) tarefas incompatíveis com a etapa
select teste.ok((select count(*) from public.tarefas where oportunidade_id = (select v from teste.var where k='f2op') and tipo = 'primeiro_contato' and status = 'aberta') = 0,
  'ao sair de "novo", a tarefa de primeiro contato é encerrada');
reset role;
select teste.ok(not exists (select 1 from public.tarefas t join public.oportunidades o on o.id = t.oportunidade_id
                            where t.status = 'aberta' and not privado.tarefa_compativel(t.tipo, o.etapa)), 'nenhuma tarefa aberta incompatível com a etapa');
select teste.ok((select count(*) from public.auditoria where acao = 'tarefa.encerrar_incompativel' and entidade_id = (select v::text from teste.var where k='f2op')) >= 1, 'encerramento automático auditado');
select teste.erro('insert into public.tarefas(ies_id, oportunidade_id, tipo, canal, vence_em) values (1, (select v from teste.var where k=''f2op''), ''primeiro_contato'', ''email'', now())',
  '22023', 'banco recusa criar primeiro contato fora de "novo"');
set role authenticated;

-- (3) projeção com taxa sobre oportunidades decididas
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.ok((select (b->'totais'->>'taxa_conversao_decididas')::numeric
                   = round((b->'totais'->>'ingressantes')::numeric / nullif((b->'totais'->>'ingressantes')::int + (b->'totais'->>'perdidos')::int + (b->'totais'->>'cancelamentos')::int, 0), 4)
                   or (b->'totais'->>'taxa_conversao_decididas') is null
                 from (select public.rpc_bi(1, '2027.1') b) x), 'taxa usa apenas oportunidades decididas');
select teste.ok((public.rpc_bi(1, '2031.1')->'totais'->>'projecao_oportunidades_necessarias') is null, 'sem base decidida a projeção é N/D');
select teste.ok((public.rpc_bi(1, '2027.1')->'totais'->>'projecao_metodo') like 'Oportunidades adicionais%', 'método da projeção explicitado (Bíblia §6)');

-- (5) metas cadastradas legíveis
select teste.ok((select sum((x->>'meta')::int) from jsonb_array_elements(public.rpc_metas(1, '2027.1')) x) = 16, 'metas cadastradas são lidas (10 + 6)');
select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false);
select teste.ok(jsonb_array_length(public.rpc_metas(1, '2027.1')) = 1, 'coordenador lê só a meta do curso autorizado');
select teste.erro('select public.rpc_metas(2, ''2027.1'')', 'P0002', 'metas de IES alheia: não encontrado');
reset role;
do $$ begin raise notice 'OK  fim da bateria da Fase 2'; end $$;
