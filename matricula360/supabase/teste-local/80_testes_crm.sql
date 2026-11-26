-- Testes do CRM avançado (migração 10).
\set ON_ERROR_STOP on
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
insert into teste.var values ('crm', (select min(id) from public.oportunidades where ies_id = 1 and curso_id = 1 and etapa = 'novo'));

-- interações e última interação
select teste.ok((public.rpc_registrar_interacao((select v from teste.var where k='crm'), 'ligacao', 'Conversa sobre horários do curso')->>'id') is not null, 'interação registrada');
select teste.ok((select ultima_interacao_em is not null from public.oportunidades where id = (select v from teste.var where k='crm')), 'última interação atualizada');
select teste.erro('select public.rpc_registrar_interacao((select v from teste.var where k=''crm''), ''telepatia'', ''x x x'')', '22023', 'tipo de interação inválido recusado');
select teste.erro('select public.rpc_registrar_interacao(9, ''ligacao'', ''tentativa cruzada'')', 'P0002', 'interação em oportunidade de outra IES: não encontrado');

-- objeções
insert into teste.var values ('obj', (public.rpc_registrar_objecao((select v from teste.var where k='crm'), 'preco', 'Mensalidade acima do orçamento da família')->>'id')::bigint);
select teste.ok((public.rpc_detalhe((select v from teste.var where k='crm'))->'objecoes'->0->>'status') = 'aberta', 'objeção registrada em aberto');
select teste.erro('select public.rpc_tratar_objecao((select v from teste.var where k=''obj''), ''superada'', '''')', '22023', 'tratamento sem descrição recusado');
select teste.ok(public.rpc_tratar_objecao((select v from teste.var where k='obj'), 'superada', 'Apresentada bolsa dentro do limite do curso')->>'status' = 'superada', 'objeção tratada');

-- agenda
select teste.ok((public.rpc_agendar((select v from teste.var where k='crm'), now() + interval '2 days', 'Retorno com a família', 'telefone')->>'id') is not null, 'agendamento criado');
select teste.ok(jsonb_array_length(public.rpc_agenda(1, now(), now() + interval '7 days')) >= 1, 'agenda lista o compromisso');
select teste.erro('select public.rpc_agendar((select v from teste.var where k=''crm''), now() - interval ''2 days'', ''no passado'')', '22023', 'agendamento no passado recusado');
select teste.erro('select public.rpc_agenda(1, now(), now() + interval ''200 days'')', '22023', 'intervalo de agenda excessivo recusado');

-- score explicável
select teste.ok((select (s->>'score')::int between 0 and 100 and s->>'versao' = 'score-v1' and jsonb_array_length(s->'razoes') > 0
                        and s->>'aviso' like '%não é usado para decidir ingresso%'
                 from (select public.rpc_detalhe((select v from teste.var where k='crm'))->'score' s) x), 'score versionado, explicado e com a trava de não decidir ingresso');
select teste.ok((public.rpc_listar_oportunidades(1, null, null, 1, 100)->'itens'->0) ? 'score', 'score presente no cartão');

-- busca e filtros
select teste.ok((public.rpc_listar_oportunidades(1, null, null, 1, 100, null, 'cand 2')->>'total')::int >= 1, 'busca por nome, sem acento e sem caixa');
select teste.ok((public.rpc_listar_oportunidades(1, null, null, 1, 100, null, 'a2@exemplo')->>'total')::int = 1, 'comercial busca por e-mail');
select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false);
select teste.ok((public.rpc_listar_oportunidades(1, null, null, 1, 100, null, 'a2@exemplo')->>'total')::int = 0, 'coordenação NÃO consegue buscar por e-mail (minimização)');
select teste.ok(jsonb_array_length(public.rpc_detalhe((select v from teste.var where k='crm'))->'interacoes') = 0, 'coordenação não lê o conteúdo das interações');
select teste.ok((public.rpc_detalhe((select v from teste.var where k='crm'))->'score') = 'null'::jsonb, 'coordenação não vê score comercial');
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.ok((select bool_and((x->>'forma_ingresso') = 'enem') from jsonb_array_elements(public.rpc_listar_oportunidades(1, null, null, 1, 100, null, null, 'enem')->'itens') x), 'filtro por forma de ingresso');
select teste.ok((select bool_and((x->>'sla_atrasado')::boolean) from jsonb_array_elements(public.rpc_listar_oportunidades(1, null, null, 1, 100, null, null, null, false, true)->'itens') x) is not false, 'filtro de SLA atrasado');

-- reatribuição com histórico
select teste.erro('select public.rpc_reatribuir((select v from teste.var where k=''crm''), teste.id(''com_dir_a''), ''troca'')', '42501', 'comercial não reatribui');
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.erro('select public.rpc_reatribuir((select v from teste.var where k=''crm''), teste.id(''secretaria_a''), ''troca'')', '22023', 'não reatribui para quem não é comercial');
select teste.erro('select public.rpc_reatribuir((select v from teste.var where k=''crm''), teste.id(''comercial_b''), ''troca'')', '22023', 'não reatribui para atendente de outra IES');
-- destino = o outro atendente do curso (a distribuição automática pode ter escolhido qualquer um)
select teste.ok((public.rpc_reatribuir((select v from teste.var where k='crm'),
  (select case when responsavel_id = teste.id('com_dir_a') then teste.id('comercial_a') else teste.id('com_dir_a') end from public.oportunidades where id = (select v from teste.var where k='crm')),
  'Rebalanceamento de carteira')->>'tarefas_transferidas')::int >= 1, 'gestor reatribui e as tarefas acompanham');
select teste.erro('select public.rpc_reatribuir((select v from teste.var where k=''crm''), (select responsavel_id from public.oportunidades where id = (select v from teste.var where k=''crm'')), ''de novo'')', '22023', 'reatribuir ao responsável atual é recusado');
select teste.ok((select count(*) from public.auditoria where acao = 'oportunidade.reatribuir' and entidade_id = (select v::text from teste.var where k='crm')) = 1, 'histórico de responsáveis auditado');
select teste.ok(jsonb_array_length(public.rpc_atendentes(1, 1)) >= 2, 'lista de atendentes elegíveis do curso');

-- possível duplicidade: homônimo com contato diferente
reset role;
insert into public.pessoas(ies_id, nome, email, base_legal, origem)
  select 1, upper((select nome from public.pessoas where id = (select pessoa_id from public.oportunidades where id = (select v from teste.var where k='crm')))), 'homonimo@exemplo.invalid', 'consentimento', 'teste';
set role authenticated;
select teste.ok(jsonb_array_length(public.rpc_detalhe((select v from teste.var where k='crm'))->'possiveis_duplicidades') = 1, 'homônimo sinalizado como possível duplicidade (sem fusão)');
select teste.ok((public.rpc_detalhe((select v from teste.var where k='crm'))->'possiveis_duplicidades'->0->>'email') like '%***@%', 'possível duplicidade exibida com contato mascarado');
reset role;
do $$ begin raise notice 'OK  fim da bateria do CRM'; end $$;
