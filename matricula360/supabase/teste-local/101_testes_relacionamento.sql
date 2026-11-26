-- Testes de Relacionamento Estudantil e MAIM Retention (migração 17).
\set ON_ERROR_STOP on
reset role;
-- Dois ingressantes da Alfa (coorte 2027.1) com ingresso confirmado há 100 dias; um há 10 dias.
insert into public.pessoas(ies_id, nome, email, base_legal, origem) values
  (1, 'Ingressante Um', 'ingressante.um@exemplo.invalid', 'consentimento', 'site'), (1, 'Ingressante Dois', 'ingressante.dois@exemplo.invalid', 'consentimento', 'site');
insert into public.oportunidades(ies_id, curso_id, pessoa_id, forma_ingresso, coorte, etapa, val_documental, val_financeira, val_academica, matricula_comercial_em, confirmada_em)
  select 1, 1, p.id, 'vestibular', '2027.1', 'confirmado', true, true, true, now() - interval '101 days', now() - interval '100 days'
    from public.pessoas p where p.email in ('ingressante.um@exemplo.invalid', 'ingressante.dois@exemplo.invalid');
insert into teste.var values ('ing1', (select o.id from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id where p.email = 'ingressante.um@exemplo.invalid'));
insert into teste.var values ('ing2', (select o.id from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id where p.email = 'ingressante.dois@exemplo.invalid'));
select teste.ok((select v from teste.var where k = 'ing1') is not null and (select v from teste.var where k = 'ing2') is not null, 'dois ingressantes efetivos sintéticos');
update public.oportunidades set confirmada_em = now() - interval '10 days' where id = (select v from teste.var where k = 'ing2');
insert into teste.var values ('nao_ing', (select min(id) from public.oportunidades where ies_id = 1 and etapa in ('novo','contato')));

set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false);
select teste.ok((select (m->>'elegiveis')::int >= 1 and m->'permanencia' = 'null'::jsonb and m->>'motivo' like 'Cobertura incompleta%'
                 from jsonb_array_elements(public.rpc_relacionamento(1, '2027.1')->'permanencia') m where m->>'marco' = 'd30'),
  'sem registro de vínculo: permanência N/D com cobertura (não presume evasão)');
select teste.ok((public.rpc_relacionamento(1, '2027.1')->'alertas') @? '$[*] ? (@.regra == "retention-v1/registro_pendente")', 'alerta de registro pendente, não de evasão');
select teste.erro('select public.rpc_registrar_vinculo((select v from teste.var where k = ''ing2''), ''d30'', ''ativo'', current_date)', '22023', 'marco ainda não alcançado é recusado');
select teste.erro('select public.rpc_registrar_vinculo((select v from teste.var where k = ''nao_ing''), ''d30'', ''ativo'', current_date)', '22023', 'vínculo só para ingressante efetivo');
select teste.erro('select public.rpc_registrar_vinculo((select v from teste.var where k = ''ing1''), ''d30'', ''trancado'', current_date)', '22023', 'situação diferente de ativo exige a fonte');
select teste.erro('select public.rpc_registrar_vinculo((select v from teste.var where k = ''ing1''), ''d30'', ''ativo'', current_date + 1)', '22023', 'data futura recusada');
select teste.ok((public.rpc_registrar_vinculo((select v from teste.var where k = 'ing1'), 'd30', 'ativo', current_date)->>'situacao') = 'ativo', 'secretaria registra vínculo ativo no marco de 30 dias');
select teste.ok((public.rpc_registrar_vinculo((select v from teste.var where k = 'ing1'), 'd90', 'trancado', current_date, 'Informado pela coordenação do curso')->>'correcao')::boolean = false,
  'trancamento registrado com a fonte');
select teste.ok((public.rpc_registrar_vinculo((select v from teste.var where k = 'ing1'), 'd90', 'ativo', current_date, 'Destrancou após contato')->>'correcao')::boolean, 'correção do registro é auditada');
select teste.ok((public.rpc_detalhe((select v from teste.var where k = 'ing1'))->'historico') @? '$[*] ? (@.acao == "vinculo.registrar" && @.dados.anterior == "trancado")', 'histórico guarda a situação anterior');

-- onboarding
select teste.erro('select public.rpc_onboarding_item((select v from teste.var where k = ''ing1''), ''Item inventado'')', '22023', 'item fora do modelo recusado');
select teste.ok((public.rpc_onboarding_item((select v from teste.var where k = 'ing1'), 'Calendário acadêmico e horários')->>'concluido')::boolean, 'item de onboarding concluído');
select teste.ok((select jsonb_array_length(i->'onboarding') = 1 from jsonb_array_elements(public.rpc_relacionamento(1, '2027.1')->'ingressantes') i
                 where (i->>'id')::bigint = (select v from teste.var where k = 'ing1')), 'progresso de onboarding visível');

-- embaixadores e indicações
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.erro('select public.rpc_salvar_embaixador((select v from teste.var where k = ''ing1''), now())', '22023', 'embaixador exige regras do programa publicadas');
select public.rpc_configurar_relacionamento(1, null, 'Embaixadores indicam conhecidos com autorização deles; não há pagamento em dinheiro; reconhecimento em evento semestral.');
select teste.erro('select public.rpc_salvar_embaixador((select v from teste.var where k = ''ing1''), now() + interval ''1 day'')', '22023', 'aceite futuro recusado');
insert into teste.var values ('emb', (public.rpc_salvar_embaixador((select v from teste.var where k = 'ing1'), now() - interval '1 day')->>'id')::bigint);
select teste.erro('select public.rpc_salvar_embaixador((select v from teste.var where k = ''nao_ing''), now())', '22023', 'embaixador precisa ser ingressante efetivo');
select teste.ok((public.rpc_criar_indicacao(1, jsonb_build_object('codigo', 'emb-ana-2027', 'embaixador_id', (select v from teste.var where k = 'emb')))->>'codigo') = 'emb-ana-2027', 'código de indicação do embaixador');
select teste.erro('select public.rpc_criar_indicacao(1, ''{"codigo":"emb-ana-2027","indicador_tipo":"aluno","indicador_nome":"Outro"}''::jsonb)', '23505', 'código repetido: conflito');
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.ok((select bool_or(x->>'codigo' = 'emb-ana-2027') from jsonb_array_elements(public.rpc_indicacoes(1)) x), 'comercial vê os códigos de indicação');
select teste.erro('select public.rpc_relacionamento(1, ''2027.1'')', '42501', 'comercial não vê dados de permanência dos alunos');
insert into teste.var values ('op_ind', (public.rpc_criar_oportunidade(1, jsonb_build_object('nome', 'Indicado pela Embaixadora', 'email', 'indicado@exemplo.invalid', 'curso_id', 1,
  'forma_ingresso', 'indicacao', 'coorte', '2027.2', 'base_legal', 'consentimento', 'origem', 'indicação', 'indicacao', 'EMB-ANA-2027'), 'ind-lead-0001')->>'id')::bigint);
select teste.erro($q$select public.rpc_criar_oportunidade(1, jsonb_build_object('nome', 'X', 'email', 'x.ind@exemplo.invalid', 'curso_id', 1, 'forma_ingresso', 'indicacao', 'coorte', '2027.2', 'base_legal', 'consentimento', 'origem', 'x', 'indicacao', 'nao-existe'), 'ind-lead-0002')$q$,
  '22023', 'código de indicação inexistente recusado');
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.ok((select (e->>'indicacoes')::int = 1 and (e->>'regras_atuais')::boolean from jsonb_array_elements(public.rpc_relacionamento(1, '2027.1')->'embaixadores') e),
  'indicação rastreada até a embaixadora, com aceite das regras vigentes');
select public.rpc_configurar_relacionamento(1, null, 'Regras revisadas: reconhecimento anual; sem pagamento em dinheiro.');
select teste.ok((select not (e->>'regras_atuais')::boolean from jsonb_array_elements(public.rpc_relacionamento(1, '2027.1')->'embaixadores') e), 'mudança de regras exige novo aceite (sinalizado)');

-- permanência com cobertura completa e isolamento
reset role;
update public.oportunidades set confirmada_em = now() - interval '100 days' where id = (select v from teste.var where k = 'ing2');
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false);
select public.rpc_registrar_vinculo(o, 'd30', 'ativo', current_date) from unnest(array(select (i->>'id')::bigint from jsonb_array_elements(public.rpc_relacionamento(1, '2027.1')->'ingressantes') i
  where not (i->'vinculos' ? 'd30') and (i->>'dias_desde_ingresso')::int >= 30)) o;
select teste.ok((select (m->>'permanencia')::numeric = 1 and (m->>'cobertura')::numeric = 1 from jsonb_array_elements(public.rpc_relacionamento(1, '2027.1')->'permanencia') m where m->>'marco' = 'd30'),
  'com cobertura completa, permanência 30 dias calculada');
select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false);
select teste.erro('select public.rpc_registrar_vinculo((select v from teste.var where k = ''ing1''), ''d30'', ''evadido'', current_date, ''cruzado'')', 'P0002', 'gestor de outra IES não alcança o aluno');
select teste.ok(jsonb_array_length(public.rpc_relacionamento(2, '2027.1')->'embaixadores') = 0, 'relacionamento isolado por instituição');
select teste.erro('select count(*) from public.vinculos', '42501', 'vínculos sem leitura direta');
reset role;
select teste.ok(true, 'fim da bateria de relacionamento');
