-- Testes de Funis Comerciais configuráveis (migração 13).
\set ON_ERROR_STOP on
reset role;
select teste.ok((select count(*) from public.funis where padrao) = (select count(*) from public.ies), 'toda IES tem funil padrão (inclusive as criadas depois da migração)');
select teste.ok((select count(*) from public.oportunidades where funil_versao_id is null) = 0, 'toda oportunidade tem versão de funil fixada');
select teste.ok((select bool_and(o.funil_etapa_ordem is not null) from public.oportunidades o where o.etapa in ('novo','contato','inscrito','pre_matricula','matricula_comercial')),
  'oportunidades abertas posicionadas na subetapa equivalente à etapa oficial');
select teste.ok((select bool_and(o.funil_etapa_ordem is null) from public.oportunidades o where o.etapa in ('confirmado','perdido','cancelado')), 'etapas encerradas ficam sem subetapa');

set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.ok((select jsonb_array_length(f->'versoes'->0->'etapas') = 5 and (f->>'padrao')::boolean from jsonb_array_elements(public.rpc_funis(1)->'funis') f where (f->>'padrao')::boolean),
  'funil padrão replica as 5 etapas oficiais abertas');
select teste.erro('select public.rpc_salvar_funil(1, ''{"nome":"Sem critério"}''::jsonb)', '22023', 'funil específico sem modalidade nem forma recusado');
insert into teste.var values ('funil_ead', (public.rpc_salvar_funil(1, '{"nome":"Funil EAD","modalidade":"ead"}'::jsonb)->>'id')::bigint);
insert into teste.var values ('v_ead', (select (v->>'id')::bigint from jsonb_array_elements(public.rpc_funis(1)->'funis') f, jsonb_array_elements(f->'versoes') v
                                         where (f->>'id')::bigint = (select v from teste.var where k = 'funil_ead')));
select teste.erro('select public.rpc_nova_versao((select v from teste.var where k = ''funil_ead''))', '22023', 'segundo rascunho do mesmo funil recusado');

-- validações estruturais do rascunho
select teste.erro($q$select public.rpc_salvar_versao((select v from teste.var where k = 'v_ead'), '{"etapas":[
  {"ordem":1,"nome":"Novo","etapa_base":"novo"},{"ordem":2,"nome":"Contato","etapa_base":"contato"},{"ordem":3,"nome":"Inscrito","etapa_base":"inscrito"},
  {"ordem":4,"nome":"Pré","etapa_base":"pre_matricula"},{"ordem":5,"nome":"Mais um","etapa_base":"pre_matricula"}]}'::jsonb)$q$, '22023', 'versão sem etapa oficial coberta (matrícula comercial) recusada');
select teste.erro($q$select public.rpc_salvar_versao((select v from teste.var where k = 'v_ead'), '{"etapas":[
  {"ordem":1,"nome":"Novo","etapa_base":"novo"},{"ordem":2,"nome":"Inscrito","etapa_base":"inscrito"},{"ordem":3,"nome":"Contato","etapa_base":"contato"},
  {"ordem":4,"nome":"Pré","etapa_base":"pre_matricula"},{"ordem":5,"nome":"MC","etapa_base":"matricula_comercial"}]}'::jsonb)$q$, '22023', 'ordem incoerente com as etapas oficiais recusada');
select teste.erro($q$select public.rpc_salvar_versao((select v from teste.var where k = 'v_ead'), '{"etapas":[
  {"ordem":1,"nome":"Novo","etapa_base":"novo"},{"ordem":2,"nome":"Contato","etapa_base":"contato"},{"ordem":4,"nome":"Inscrito","etapa_base":"inscrito"},
  {"ordem":5,"nome":"Pré","etapa_base":"pre_matricula"},{"ordem":6,"nome":"MC","etapa_base":"matricula_comercial"}]}'::jsonb)$q$, '22023', 'numeração com lacuna recusada');
select teste.erro($q$select public.rpc_salvar_versao((select v from teste.var where k = 'v_ead'), '{"etapas":[
  {"ordem":1,"nome":"Novo","etapa_base":"novo"},{"ordem":2,"nome":"Contato","etapa_base":"contato"},{"ordem":3,"nome":"Inscrito","etapa_base":"confirmado"},
  {"ordem":4,"nome":"Pré","etapa_base":"pre_matricula"},{"ordem":5,"nome":"MC","etapa_base":"matricula_comercial"}]}'::jsonb)$q$, '22023', 'etapa encerrada (ingresso) não é configurável');
select teste.ok((public.rpc_salvar_versao((select v from teste.var where k = 'v_ead'), '{"notas":"Contato desdobrado para EAD","etapas":[
  {"ordem":1,"nome":"Novo lead EAD","etapa_base":"novo","sla_horas":4,"roteiro":"Apresente-se e confirme o interesse no curso."},
  {"ordem":2,"nome":"1ª tentativa","etapa_base":"contato","sla_horas":24},
  {"ordem":3,"nome":"Demonstração da plataforma","etapa_base":"contato","roteiro":"Mostre o ambiente virtual e a rotina de estudos."},
  {"ordem":4,"nome":"Inscrito","etapa_base":"inscrito"},{"ordem":5,"nome":"Pré-matrícula","etapa_base":"pre_matricula"},
  {"ordem":6,"nome":"Matrícula comercial","etapa_base":"matricula_comercial"}],
  "cadencias":[{"etapa_ordem":2,"passo":1,"dia":0,"canal":"whatsapp","descricao":"Mensagem de boas-vindas (registro manual)"},
               {"etapa_ordem":2,"passo":2,"dia":2,"canal":"telefone","descricao":"Ligação de acompanhamento"}],
  "metas":[{"forma_ingresso":"enem","conversao_meta":0.2},{"forma_ingresso":"vestibular","conversao_meta":0.15}]}'::jsonb)->'etapas'->2->>'nome') = 'Demonstração da plataforma',
  'rascunho salvo com subetapas, roteiro, cadência e metas por forma');
select teste.erro($q$select public.rpc_salvar_versao((select v from teste.var where k = 'v_ead'), '{"etapas":[
  {"ordem":1,"nome":"Novo","etapa_base":"novo"},{"ordem":2,"nome":"Contato","etapa_base":"contato"},{"ordem":3,"nome":"Inscrito","etapa_base":"inscrito"},
  {"ordem":4,"nome":"Pré","etapa_base":"pre_matricula"},{"ordem":5,"nome":"MC","etapa_base":"matricula_comercial"}],
  "metas":[{"forma_ingresso":"enem","conversao_meta":1.5}]}'::jsonb)$q$, '22023', 'meta de conversão acima de 100% recusada (rascunho anterior preservado)');
select teste.ok((select jsonb_array_length(v->'etapas') = 6 from jsonb_array_elements(public.rpc_funis(1)->'funis') f, jsonb_array_elements(f->'versoes') v
                 where (v->>'id')::bigint = (select v from teste.var where k = 'v_ead')), 'falha de validação não altera o rascunho (transação atômica)');

select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro('select public.rpc_publicar_versao((select v from teste.var where k = ''v_ead''))', '42501', 'comercial não publica funil');
select teste.ok(jsonb_array_length(public.rpc_funis(1)->'funis') = 2, 'comercial vê os funis (roteiros e cadências)');
select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false);
select teste.erro('select public.rpc_publicar_versao((select v from teste.var where k = ''v_ead''))', 'P0002', 'gestor de outra IES não alcança o funil');
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.ok((public.rpc_publicar_versao((select v from teste.var where k = 'v_ead'))->>'versao')::int = 1, 'gestor publica o funil EAD');
select teste.erro($q$select public.rpc_salvar_versao((select v from teste.var where k = 'v_ead'), '{"etapas":[]}'::jsonb)$q$, '22023', 'versão publicada é imutável');

-- seleção automática e subetapas
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
insert into teste.var values ('op_ead', (public.rpc_criar_oportunidade(1, jsonb_build_object('nome', 'Lead EAD', 'email', 'lead.ead@exemplo.invalid', 'curso_id', 2,
  'forma_ingresso', 'enem', 'coorte', '2027.1', 'base_legal', 'consentimento', 'origem', 'site'), 'funil-ead-0001')->>'id')::bigint);
select teste.ok((select r->>'funil' = 'Funil EAD' and (r->'atual'->>'nome') = 'Novo lead EAD' and (r->'meta_conversao_forma')::numeric = 0.2
                 from (select public.rpc_funil_oportunidade((select v from teste.var where k = 'op_ead')) r) x), 'curso EAD recebe o funil EAD, com roteiro e meta da forma');
insert into teste.var values ('op_pres', (public.rpc_criar_oportunidade(1, jsonb_build_object('nome', 'Lead Presencial', 'email', 'lead.pres@exemplo.invalid', 'curso_id', 1,
  'forma_ingresso', 'enem', 'coorte', '2027.1', 'base_legal', 'consentimento', 'origem', 'site'), 'funil-pres-0001')->>'id')::bigint);
select teste.ok((public.rpc_funil_oportunidade((select v from teste.var where k = 'op_pres'))->>'funil') = 'Funil padrão institucional', 'curso presencial fica no funil padrão');
select public.rpc_mover_etapa((select v from teste.var where k = 'op_ead'), 'contato', 1, null, 'funil-ead-mover-1');
select teste.ok((select (r->'atual'->>'nome') = '1ª tentativa' and jsonb_array_length(r->'subetapas') = 2 and jsonb_array_length(r->'cadencia') = 2
                 from (select public.rpc_funil_oportunidade((select v from teste.var where k = 'op_ead')) r) x), 'mudança de etapa oficial posiciona na primeira subetapa, com cadência');
select teste.erro('select public.rpc_mover_subetapa((select v from teste.var where k = ''op_ead''), 4, 2)', '22023', 'subetapa de outra etapa oficial recusada');
select teste.erro('select public.rpc_mover_subetapa((select v from teste.var where k = ''op_ead''), 3, 1)', '40001', 'subetapa com versão antiga: conflito');
select teste.ok((public.rpc_mover_subetapa((select v from teste.var where k = 'op_ead'), 3, 2)->>'etapa_ordem')::int = 3, 'subetapa avança dentro da etapa oficial');
select teste.ok((select etapa = 'contato' from public.oportunidades where id = (select v from teste.var where k = 'op_ead')), 'subetapa não altera a etapa oficial');
select teste.ok((public.rpc_detalhe((select v from teste.var where k = 'op_ead'))->'historico') @? '$[*] ? (@.acao == "oportunidade.subetapa")', 'mudança de subetapa auditada');

-- nova versão não altera oportunidades existentes
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
insert into teste.var values ('v_ead2', (public.rpc_nova_versao((select v from teste.var where k = 'funil_ead'))->>'versao_id')::bigint);
select teste.ok((select jsonb_array_length(public.rpc_funis(1)->'funis') = 2), 'nova versão criada como rascunho');
select public.rpc_salvar_versao((select v from teste.var where k = 'v_ead2'), '{"etapas":[
  {"ordem":1,"nome":"Novo","etapa_base":"novo"},{"ordem":2,"nome":"Contato","etapa_base":"contato"},{"ordem":3,"nome":"Inscrito","etapa_base":"inscrito"},
  {"ordem":4,"nome":"Pré","etapa_base":"pre_matricula"},{"ordem":5,"nome":"MC","etapa_base":"matricula_comercial"}]}'::jsonb);
select public.rpc_publicar_versao((select v from teste.var where k = 'v_ead2'));
select teste.ok((select (r->>'versao')::int = 1 and r->>'versao_status' = 'arquivada' and (r->'atual'->>'nome') = 'Demonstração da plataforma'
                 from (select public.rpc_funil_oportunidade((select v from teste.var where k = 'op_ead')) r) x), 'oportunidade antiga continua na versão em que nasceu (histórico preservado)');
select teste.ok((select (v->>'status') = 'arquivada' from jsonb_array_elements(public.rpc_funis(1)->'funis') f, jsonb_array_elements(f->'versoes') v
                 where (v->>'id')::bigint = (select v from teste.var where k = 'v_ead')), 'versão anterior arquivada ao publicar a nova');
select teste.ok((select (d->>'oportunidades')::int >= 1 from jsonb_array_elements(public.rpc_funis(1)->'funis') f, jsonb_array_elements(f->'desempenho') d
                 where f->>'nome' = 'Funil EAD' and d->>'forma_ingresso' = 'enem'), 'desempenho por forma de ingresso calculado');
select teste.erro('select count(*) from public.funis', '42501', 'funis sem leitura direta (só por RPC)');

-- provisionamento cria funil padrão para a nova IES
select set_config('request.jwt.claim.sub', teste.id('master')::text, false);
insert into teste.var values ('ies_nova', (public.rpc_provisionar_ies('Faculdade Gama (fictícia)', 'piloto', 'Campus Único',
  '[{"nome":"Pedagogia","turno":"noturno","modalidade":"ead","mensalidade_centavos":29900}]'::jsonb)->>'id')::bigint);
reset role;
select teste.ok((select count(*) = 1 from public.funis where ies_id = (select v from teste.var where k = 'ies_nova') and padrao), 'instituição nova nasce com funil padrão publicado');
select teste.ok(true, 'fim da bateria de funis');
