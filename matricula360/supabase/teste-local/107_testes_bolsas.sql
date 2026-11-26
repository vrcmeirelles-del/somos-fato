-- Testes de bolsas e financiamento (migração 23).
\set ON_ERROR_STOP on
reset role;
create temp table bol (chave text primary key, v text);
grant all on bol to anon, authenticated;
-- oportunidade do comercial_a (visível a ele) e outra para o portal
insert into bol select 'op', o.id::text from public.oportunidades o where o.ies_id = 1 and o.responsavel_id = teste.id('comercial_a') and o.etapa in ('novo','contato','inscrito') order by o.id limit 1;
insert into bol select 'curso', curso_id::text from public.oportunidades where id = (select v::bigint from bol where chave = 'op');
insert into bol select 'outro_curso', c.id::text from public.cursos c where c.ies_id = 1 and c.id <> (select v::bigint from bol where chave = 'curso') order by c.id limit 1;
insert into bol select 'op_portal', o.id::text from public.oportunidades o where o.ies_id = 1 and o.etapa in ('novo','contato','inscrito')
  and o.id <> (select v::bigint from bol where chave = 'op') and o.curso_id = (select v::bigint from bol where chave = 'curso') order by o.id desc limit 1;
set role authenticated;

-- ---------------------------------------------------------------- programas
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro($q$select public.rpc_salvar_programa_bolsa(1, '{"nome":"Bolsa X","tipo":"bolsa_institucional","percentual_max":30}')$q$, '42501', 'comercial não cria programa');
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.erro($q$select public.rpc_salvar_programa_bolsa(1, '{"nome":"ProUni errado","tipo":"prouni","percentual_max":70}')$q$, '22023', 'ProUni só com 50% ou 100%');
select teste.erro($q$select public.rpc_salvar_programa_bolsa(1, '{"nome":"Fora","tipo":"bolsa_institucional","percentual_max":20,"cursos":[999999]}')$q$, '22023', 'curso de outra IES recusado');
insert into bol select 'prouni', public.rpc_salvar_programa_bolsa(1, '{"nome":"ProUni 2027","tipo":"prouni","percentual_max":100,"requisitos":"Renda per capita conforme edital","documentos":["comprovante_renda"]}')->>'id';
insert into bol select 'merito', public.rpc_salvar_programa_bolsa(1, jsonb_build_object('nome','Bolsa Mérito ENEM','tipo','bolsa_institucional','percentual_max',30,'vagas',1,
  'cursos', jsonb_build_array((select v::bigint from bol where chave = 'curso'))))->>'id';
insert into bol select 'convenio', public.rpc_salvar_programa_bolsa(1, '{"nome":"Convênio Empresa Sintética","tipo":"convenio_empresa","percentual_max":15,"cumulativo":true}')->>'id';
insert into bol select 'restrito', public.rpc_salvar_programa_bolsa(1, jsonb_build_object('nome','Bolsa só outro curso','tipo','bolsa_institucional','percentual_max',10,
  'cursos', jsonb_build_array((select v::bigint from bol where chave = 'outro_curso'))))->>'id';
select teste.ok((select count(*) = 4 from jsonb_array_elements(public.rpc_bolsas(1)->'programas')), 'gestor vê os quatro programas');
select teste.erro($q$select public.rpc_salvar_programa_bolsa(1, '{"nome":"ProUni 2027","tipo":"prouni","percentual_max":50}')$q$, '22023', 'nome repetido recusado');
select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false);
select teste.erro($q$select public.rpc_bolsas(1)$q$, 'P0002', 'outra IES não vê os programas');

-- ---------------------------------------------------------------- solicitação pela equipe
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro($q$select public.rpc_solicitar_bolsa((select v::bigint from bol where chave = 'op'), (select v::bigint from bol where chave = 'prouni'), 70)$q$, '22023', 'ProUni de 70% recusado');
select teste.erro($q$select public.rpc_solicitar_bolsa((select v::bigint from bol where chave = 'op'), (select v::bigint from bol where chave = 'merito'), 40)$q$, '22023', 'acima do percentual máximo recusado');
select teste.erro($q$select public.rpc_solicitar_bolsa((select v::bigint from bol where chave = 'op'), (select v::bigint from bol where chave = 'restrito'), 10)$q$, '22023', 'programa de outro curso recusado');
insert into bol select 's_merito', public.rpc_solicitar_bolsa((select v::bigint from bol where chave = 'op'), (select v::bigint from bol where chave = 'merito'), 30, 'Nota ENEM alta')->>'id';
insert into bol select 's_prouni', public.rpc_solicitar_bolsa((select v::bigint from bol where chave = 'op'), (select v::bigint from bol where chave = 'prouni'), 100)->>'id';
select teste.erro($q$select public.rpc_solicitar_bolsa((select v::bigint from bol where chave = 'op'), (select v::bigint from bol where chave = 'merito'), 20)$q$, '22023', 'solicitação repetida do mesmo programa recusada');
select teste.erro($q$select public.rpc_decidir_bolsa((select v::bigint from bol where chave = 's_merito'), 'aprovada', 'Aprovo minha própria')$q$, '42501', 'comercial não decide');
reset role;
select teste.ok((select count(*) = 2 and bool_and(etapa_externa is null or etapa_externa = 'inscricao') from public.solicitacoes_bolsa where oportunidade_id = (select v::bigint from bol where chave = 'op')),
  'solicitações registradas; ProUni começa na etapa de inscrição');
set role authenticated;

-- ---------------------------------------------------------------- decisão segregada
select set_config('request.jwt.claim.sub', teste.id('financeiro_a')::text, false);
select teste.erro($q$select public.rpc_decidir_bolsa((select v::bigint from bol where chave = 's_merito'), 'aprovada', 'ok')$q$, '22023', 'justificativa curta recusada');
select teste.ok((public.rpc_decidir_bolsa((select v::bigint from bol where chave = 's_merito'), 'aprovada', 'Nota acima do corte do edital interno')->>'status') = 'aprovada', 'financeiro aprova a bolsa mérito');
select teste.erro($q$select public.rpc_decidir_bolsa((select v::bigint from bol where chave = 's_prouni'), 'aprovada', 'ProUni deferido no sistema do MEC')$q$, '22023',
  'ProUni não cumulativo com mérito já aprovado: recusado');
select teste.ok((public.rpc_decidir_bolsa((select v::bigint from bol where chave = 's_prouni'), 'indeferida', 'Não cumulativo com a bolsa mérito')->>'status') = 'indeferida', 'indeferimento com justificativa');
select teste.erro($q$select public.rpc_decidir_bolsa((select v::bigint from bol where chave = 's_prouni'), 'aprovada', 'Mudança de ideia')$q$, '22023', 'decisão não muda depois de tomada');
-- convênio cumulativo, pedido pelo financeiro: não pode decidir o próprio
insert into bol select 's_conv', public.rpc_solicitar_bolsa((select v::bigint from bol where chave = 'op'), (select v::bigint from bol where chave = 'convenio'), 15)->>'id'
  where false;  -- financeiro não tem bolsa.solicitar; abaixo pelo gestor
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
insert into bol select 's_conv', public.rpc_solicitar_bolsa((select v::bigint from bol where chave = 'op'), (select v::bigint from bol where chave = 'convenio'), 15)->>'id';
select teste.erro($q$select public.rpc_decidir_bolsa((select v::bigint from bol where chave = 's_conv'), 'aprovada', 'Convênio vigente com a empresa')$q$, '42501', 'quem solicitou não decide');
select teste.ok((select (s->>'decide_proprio')::boolean from jsonb_array_elements(public.rpc_bolsas(1)->'solicitacoes') s where (s->>'id')::bigint = (select v::bigint from bol where chave = 's_conv')),
  'painel sinaliza a solicitação que o usuário não pode decidir');
select set_config('request.jwt.claim.sub', teste.id('financeiro_a')::text, false);
select teste.erro($q$select public.rpc_decidir_bolsa((select v::bigint from bol where chave = 's_conv'), 'aprovada', 'Convênio vigente com a empresa')$q$, '22023',
  'convênio cumulativo, mas a bolsa mérito não é: recusado');
-- vagas: a bolsa mérito tem 1 vaga, já usada
reset role;
insert into bol select 'op2', o.id::text from public.oportunidades o where o.ies_id = 1 and o.curso_id = (select v::bigint from bol where chave = 'curso')
  and o.etapa in ('novo','contato','inscrito') and o.id not in ((select v::bigint from bol where chave = 'op'), (select v::bigint from bol where chave = 'op_portal')) order by o.id limit 1;
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
insert into bol select 's_merito2', public.rpc_solicitar_bolsa((select v::bigint from bol where chave = 'op2'), (select v::bigint from bol where chave = 'merito'), 20)->>'id';
select set_config('request.jwt.claim.sub', teste.id('financeiro_a')::text, false);
select teste.erro($q$select public.rpc_decidir_bolsa((select v::bigint from bol where chave = 's_merito2'), 'aprovada', 'Segunda bolsa mérito')$q$, '22023', 'vagas esgotadas: recusado');
select teste.ok((select (g->>'aprovadas')::int = 1 and (g->>'solicitadas')::int = 1 and (g->>'percentual_medio')::numeric = 30
                 from jsonb_array_elements(public.rpc_bolsas(1)->'programas') g where (g->>'id')::bigint = (select v::bigint from bol where chave = 'merito')), 'painel conta aprovadas, pendentes e percentual médio');
select teste.ok((public.rpc_cancelar_bolsa((select v::bigint from bol where chave = 's_merito'), 'Candidato desistiu da bolsa')->>'status') = 'cancelada', 'cancelamento com motivo libera a vaga');
select teste.ok((public.rpc_decidir_bolsa((select v::bigint from bol where chave = 's_merito2'), 'aprovada', 'Vaga liberada')->>'status') = 'aprovada', 'vaga liberada pode ser usada');
select teste.ok((public.rpc_etapa_bolsa((select v::bigint from bol where chave = 's_prouni'), 'pre_selecao')->>'etapa_externa') = 'pre_selecao', 'etapa externa do ProUni registrada');
select teste.erro($q$select public.rpc_etapa_bolsa((select v::bigint from bol where chave = 's_merito2'), 'contratado')$q$, '22023', 'etapa externa só para programas externos');
reset role;
select teste.ok((select count(*) >= 6 from public.auditoria where acao like 'bolsa.%'), 'operações de bolsa auditadas');

-- ---------------------------------------------------------------- comercial vê só as próprias oportunidades
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.ok((select bool_and((s->>'oportunidade_id')::bigint in (select o.id from public.oportunidades o where o.responsavel_id = teste.id('comercial_a')))
                 from jsonb_array_elements(public.rpc_bolsas(1)->'solicitacoes') s), 'comercial só vê solicitações das suas oportunidades');

-- ---------------------------------------------------------------- portal
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
insert into bol select 'tok', public.rpc_gerar_acesso_portal((select v::bigint from bol where chave = 'op_portal'))->>'token';
reset role; set role anon;
select teste.ok((select count(*) = 3 and bool_and(g->>'nome' <> 'Bolsa só outro curso')
                 from jsonb_array_elements(public.rpc_publico_portal_bolsas((select v from bol where chave = 'tok'))) x, jsonb_array_elements(x->'programas') g
                 where (x->>'oportunidade_id')::bigint = (select v::bigint from bol where chave = 'op_portal')), 'portal mostra só os programas do curso do candidato');
select teste.erro($q$select public.rpc_publico_solicitar_bolsa((select v from bol where chave = 'tok'), (select v::bigint from bol where chave = 'op_portal'), (select v::bigint from bol where chave = 'convenio'), 10, false)$q$,
  '22023', 'portal exige declaração de veracidade');
select teste.ok((public.rpc_publico_solicitar_bolsa((select v from bol where chave = 'tok'), (select v::bigint from bol where chave = 'op_portal'), (select v::bigint from bol where chave = 'convenio'), 10, true, 'Trabalho na empresa conveniada')->>'status') = 'solicitada',
  'candidato solicita bolsa pelo portal');
select teste.erro($q$select public.rpc_publico_solicitar_bolsa((select v from bol where chave = 'tok'), (select v::bigint from bol where chave = 'op'), (select v::bigint from bol where chave = 'convenio'), 10, true)$q$,
  'P0002', 'portal não solicita para oportunidade de outra pessoa');
select teste.ok((select count(*) = 1 from jsonb_array_elements(public.rpc_publico_portal_bolsas((select v from bol where chave = 'tok'))) x, jsonb_array_elements(x->'solicitacoes') s
                 where s->>'status' = 'solicitada'), 'candidato acompanha a solicitação no portal');
reset role;
