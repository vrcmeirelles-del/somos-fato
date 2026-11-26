-- Testes da Academia de Captação (migração 16).
\set ON_ERROR_STOP on
reset role;
select teste.ok((select count(*) from public.trilhas where ies_id = 1) = 5 and (select count(*) from public.rubricas where ies_id = 1 and status = 'publicada') = 1,
  'conteúdo inicial próprio: 5 trilhas e rubrica publicada');
select teste.ok((select count(*) from public.rubrica_criterios c join public.rubricas r on r.id = c.rubrica_id where r.ies_id = 1) = 7, 'rubrica cobre as 7 competências da Bíblia');
insert into teste.var values ('rub', (select id from public.rubricas where ies_id = 1 and status = 'publicada'));
insert into teste.var values ('crit_escuta', (select c.id from public.rubrica_criterios c where c.rubrica_id = (select v from teste.var where k = 'rub') and c.competencia = 'escuta'));
insert into teste.var values ('cenario', (select min(id) from public.cenarios where ies_id = 1));
insert into teste.var values ('mod_escuta', (select m.id from public.modulos m join public.trilhas t on t.id = m.trilha_id where t.ies_id = 1 and m.competencia = 'escuta' limit 1));

set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.ok((select jsonb_array_length(r->'trilhas') = 5 and (r->>'ve_equipe')::boolean = false and r->>'aviso' like '%Nenhuma nota automática%'
                 from (select public.rpc_academia(1) r) x), 'atendente vê trilhas e o aviso de avaliação humana');
select teste.ok((public.rpc_concluir_modulo((select v from teste.var where k = 'mod_escuta'))->>'concluido')::boolean, 'atendente conclui módulo');
select teste.ok((public.rpc_concluir_modulo((select v from teste.var where k = 'mod_escuta'))->>'concluido')::boolean, 'conclusão repetida é idempotente');
select teste.erro('select public.rpc_salvar_avaliacao(1, jsonb_build_object(''avaliado_id'', teste.id(''com_dir_a''), ''rubrica_id'', 1, ''tipo'', ''roleplay'', ''evidencias'', ''tentativa de avaliar colega''))', '42501', 'atendente não avalia');

-- avaliação humana pelo gestor
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.erro($q$select public.rpc_salvar_avaliacao(1, jsonb_build_object('avaliado_id', teste.id('gestor_a'), 'rubrica_id', (select v from teste.var where k = 'rub'), 'tipo', 'roleplay', 'evidencias', 'autoavaliação indevida'))$q$, '42501', 'ninguém avalia a si mesmo');
select teste.erro($q$select public.rpc_salvar_avaliacao(1, jsonb_build_object('avaliado_id', teste.id('secretaria_a'), 'rubrica_id', (select v from teste.var where k = 'rub'), 'tipo', 'roleplay', 'evidencias', 'secretaria não é alvo'))$q$, '22023', 'avaliado precisa ser atendente comercial');
select teste.erro($q$select public.rpc_salvar_avaliacao(1, jsonb_build_object('avaliado_id', teste.id('comercial_a'), 'rubrica_id', (select v from teste.var where k = 'rub'), 'tipo', 'roleplay', 'evidencias', 'curta'))$q$, '22023', 'evidência obrigatória (10+ caracteres)');
insert into teste.var values ('aval', (public.rpc_salvar_avaliacao(1, jsonb_build_object('avaliado_id', teste.id('comercial_a'), 'rubrica_id', (select v from teste.var where k = 'rub'),
  'cenario_id', (select v from teste.var where k = 'cenario'), 'tipo', 'roleplay', 'evidencias', 'Roleplay do cenário EAD: não confirmou o entendimento do objetivo do candidato.',
  'niveis', jsonb_build_object((select v from teste.var where k = 'crit_escuta')::text, 2)))->>'id')::bigint);
select teste.erro($q$select public.rpc_salvar_avaliacao(1, jsonb_build_object('niveis', jsonb_build_object((select v from teste.var where k = 'crit_escuta')::text, 7)), (select v from teste.var where k = 'aval'))$q$, '22023', 'nível fora de 1 a 4 recusado');
select teste.erro($q$select public.rpc_salvar_avaliacao(1, '{}'::jsonb, (select v from teste.var where k = 'aval'), true)$q$, '22023', 'finalizar exige todos os critérios');
select teste.ok(public.rpc_salvar_avaliacao(1,
    jsonb_build_object('niveis', (select jsonb_object_agg(c->>'id', case when c->>'competencia' = 'escuta' then 2 else 3 end)
                                    from jsonb_array_elements(public.rpc_academia(1)->'rubricas') r, jsonb_array_elements(r->'criterios') c
                                   where (r->>'id')::bigint = (select v from teste.var where k = 'rub'))),
    (select v from teste.var where k = 'aval'), true)->>'status' = 'finalizada', 'gestor finaliza a avaliação com todos os critérios');
select teste.erro($q$select public.rpc_salvar_avaliacao(1, '{"comentario":"mudança posterior"}'::jsonb, (select v from teste.var where k = 'aval'))$q$, '22023', 'avaliação finalizada é imutável');
select teste.ok((select (a->>'consolidado')::numeric between 2 and 3 from jsonb_array_elements(public.rpc_academia(1)->'avaliacoes') a where (a->>'id')::bigint = (select v from teste.var where k = 'aval')),
  'consolidação = média ponderada dos níveis humanos');
select teste.ok((select l->>'competencia' = 'escuta' and (l->>'nivel')::int = 2 and jsonb_array_length(l->'recomendados') >= 1 and (l->'recomendados'->0->>'concluido')::boolean
                 from jsonb_array_elements(public.rpc_academia(1)->'lacunas') l where l->>'usuario' = 'comercial_a'), 'MAIM Learning: lacuna em escuta com módulo recomendado (já concluído pela pessoa)');

-- PDI
select teste.erro($q$select public.rpc_salvar_pdi(1, jsonb_build_object('usuario_id', teste.id('comercial_a'), 'competencia', 'escuta', 'objetivo', 'x', 'acoes', 'y', 'prazo', '2027-03-01'))$q$, '22023', 'PDI com objetivo e ações insuficientes recusado');
insert into teste.var values ('pdi', (public.rpc_salvar_pdi(1, jsonb_build_object('usuario_id', teste.id('comercial_a'), 'competencia', 'escuta',
  'objetivo', 'Confirmar o entendimento do objetivo do candidato em todo diagnóstico', 'acoes', 'Refazer o módulo de diagnóstico; dois roleplays acompanhados',
  'prazo', '2027-03-01', 'reavaliar_em', '2027-03-15', 'avaliacao_origem', (select v from teste.var where k = 'aval')))->>'id')::bigint);
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.ok((select count(*) = 1 from jsonb_array_elements(public.rpc_academia(1)->'avaliacoes') a where (a->>'avaliado_id')::uuid = teste.id('comercial_a')), 'avaliado vê integralmente a própria avaliação');
select teste.ok((public.rpc_salvar_pdi(1, '{"status":"em_andamento"}'::jsonb, (select v from teste.var where k = 'pdi'))->>'id')::bigint = (select v from teste.var where k = 'pdi'), 'atendente atualiza o andamento do próprio PDI');
select teste.erro('select public.rpc_salvar_pdi(1, ''{"objetivo":"Outro objetivo definido pelo atendente"}''::jsonb, (select v from teste.var where k = ''pdi''))', '42501', 'atendente não reescreve objetivo do PDI');
select set_config('request.jwt.claim.sub', teste.id('com_dir_a')::text, false);
select teste.ok((select jsonb_array_length(r->'avaliacoes') = 0 and jsonb_array_length(r->'pdis') = 0 and jsonb_array_length(r->'lacunas') = 0 from (select public.rpc_academia(1) r) x),
  'colega não vê avaliação, PDI nem lacunas de outro atendente');
select teste.erro('select public.rpc_salvar_pdi(1, ''{"status":"concluido"}''::jsonb, (select v from teste.var where k = ''pdi''))', 'P0002', 'colega não altera PDI alheio');

-- rubrica versionada e cenário sintético
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
insert into teste.var values ('rub2', (public.rpc_salvar_rubrica(1, 'nova_versao', (select v from teste.var where k = 'rub'))->>'id')::bigint);
select teste.erro($q$select public.rpc_salvar_rubrica(1, 'salvar', (select v from teste.var where k = 'rub'), '[]'::jsonb)$q$, '22023', 'rubrica publicada é imutável');
select teste.erro($q$select public.rpc_salvar_rubrica(1, 'salvar', (select v from teste.var where k = 'rub2'), '[{"competencia":"escuta","descricao":"Escuta","niveis":["a","b","c"]}]'::jsonb)$q$, '22023', 'critério com menos de 4 níveis recusado');
select public.rpc_salvar_rubrica(1, 'publicar', (select v from teste.var where k = 'rub2'));
select teste.ok((select a->>'rubrica' like '%v1' from jsonb_array_elements(public.rpc_academia(1)->'avaliacoes') a where (a->>'id')::bigint = (select v from teste.var where k = 'aval')),
  'avaliação antiga mantém a versão de rubrica usada');
select teste.erro($q$select public.rpc_salvar_cenario(1, '{"titulo":"Com dado real","perfil_sintetico":"Candidata com e-mail maria@empresa.com.br quer mudar de curso","objetivo":"Testar"}'::jsonb)$q$, '22023', 'cenário com e-mail recusado (sintético)');
select teste.ok((public.rpc_salvar_cenario(1, '{"titulo":"Transferência de outra instituição","perfil_sintetico":"Pessoa fictícia no 3º semestre em outra instituição, insatisfeita com o horário.","objetivo":"Explicar aproveitamento de disciplinas."}'::jsonb)->>'id') is not null, 'cenário sintético criado');

-- isolamento
select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false);
select teste.ok((select jsonb_array_length(public.rpc_academia(2)->'avaliacoes') = 0), 'avaliações isoladas por instituição');
select teste.erro('select public.rpc_concluir_modulo((select v from teste.var where k = ''mod_escuta''))', 'P0002', 'módulo de outra IES não alcançável');
select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false);
select teste.erro('select public.rpc_academia(1)', '42501', 'coordenação acadêmica fora da Academia comercial');
select teste.erro('select count(*) from public.avaliacoes', '42501', 'avaliações sem leitura direta');
reset role;
select teste.ok((select status = 'arquivada' from public.rubricas where id = (select v from teste.var where k = 'rub')), 'versão anterior da rubrica arquivada');
select teste.ok((select count(*) = 1 from public.trilhas where ies_id = (select v from teste.var where k = 'ies_nova') and nome = 'Ética e LGPD na captação') or not exists (select 1 from teste.var where k = 'ies_nova'),
  'instituição nova recebe a Academia inicial');
select teste.ok(true, 'fim da bateria da academia');
