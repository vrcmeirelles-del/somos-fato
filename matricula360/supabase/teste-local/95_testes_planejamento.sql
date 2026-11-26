-- Testes de Planejamento Estratégico e Marketing e Captação (migração 12).
\set ON_ERROR_STOP on
set role authenticated;

-- ---------------------------------------------------------------- planejamento
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
insert into teste.var values ('plano', (public.rpc_salvar_plano(1, '{"coorte":"2027.1","titulo":"Plano de captação 2027.1","diagnostico":"Base sintética","orcamento_centavos":5000000,"revisar_em":"2027-03-01"}'::jsonb)->>'id')::bigint);
select teste.erro('select public.rpc_salvar_plano(1, ''{"coorte":"2027.1","titulo":"Plano de captação 2027.1"}''::jsonb)', '23505', 'título repetido na coorte: conflito');
select teste.erro('select public.rpc_plano_status((select v from teste.var where k = ''plano''), ''submeter'')', '22023', 'plano sem objetivo não é submetido');
insert into teste.var values ('obj_ing', (public.rpc_salvar_objetivo((select v from teste.var where k = 'plano'), '{"descricao":"Ingressantes no Direito","indicador":"ingressantes","curso_id":1,"meta":10}'::jsonb)->>'id')::bigint);
select public.rpc_salvar_objetivo((select v from teste.var where k = 'plano'), '{"descricao":"CPL institucional","indicador":"cpl_centavos","meta":5000}'::jsonb);
select teste.erro('select public.rpc_salvar_objetivo((select v from teste.var where k = ''plano''), ''{"descricao":"Conversão","indicador":"conversao","meta":30}''::jsonb)', '22023', 'meta de conversão acima de 1 recusada');
select teste.erro('select public.rpc_salvar_objetivo((select v from teste.var where k = ''plano''), ''{"descricao":"Curso de outra IES","indicador":"ingressantes","curso_id":3,"meta":5}''::jsonb)', '22023', 'objetivo com curso de outra IES recusado');
insert into teste.var values ('acao', (public.rpc_salvar_acao((select v from teste.var where k = 'plano'), jsonb_build_object('objetivo_id', (select v from teste.var where k = 'obj_ing'),
  'o_que', 'Visitas a escolas de ensino médio', 'por_que', 'Ampliar leads de vestibular', 'onde', 'Região central', 'quando', '2027-01-20',
  'quem', 'Equipe comercial', 'como', 'Agenda com coordenação pedagógica', 'quanto_centavos', 150000))->>'id')::bigint);
select teste.erro('select public.rpc_salvar_plano(1, ''{"titulo":"x"}''::jsonb, (select v from teste.var where k = ''plano''), 99)', '40001', 'edição com versão antiga: conflito');
select teste.ok((public.rpc_plano_status((select v from teste.var where k = 'plano'), 'submeter')->>'status') = 'em_aprovacao', 'plano submetido para aprovação');
select teste.erro('select public.rpc_plano_status((select v from teste.var where k = ''plano''), ''aprovar'')', '42501', 'quem criou o plano não o aprova (segregação)');
select teste.erro('select public.rpc_salvar_objetivo((select v from teste.var where k = ''plano''), ''{"descricao":"Novo","indicador":"oportunidades","meta":100}''::jsonb)', '22023', 'plano em aprovação não aceita novos objetivos');

select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro('select public.rpc_planejamento(1, ''2027.1'')', '42501', 'comercial não vê o planejamento');
select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false);
select teste.ok((select (p->>'orcamento_centavos') is null and jsonb_array_length(p->'objetivos') = 2 from jsonb_array_elements(public.rpc_planejamento(1, '2027.1')->'planos') p),
  'coordenação vê o plano sem valores financeiros');
select teste.erro('select public.rpc_plano_status((select v from teste.var where k = ''plano''), ''aprovar'')', '42501', 'coordenação não aprova plano');
select set_config('request.jwt.claim.sub', teste.id('reitoria_a')::text, false);
select teste.erro('select public.rpc_plano_status((select v from teste.var where k = ''plano''), ''devolver'')', '22023', 'devolução sem justificativa recusada');
select teste.ok((public.rpc_plano_status((select v from teste.var where k = 'plano'), 'aprovar')->>'status') = 'aprovado', 'reitoria aprova o plano criado pelo gestor');
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.erro('select public.rpc_salvar_acao((select v from teste.var where k = ''plano''), ''{"o_que":"Mudança após aprovação"}''::jsonb, (select v from teste.var where k = ''acao''))', '22023', 'plano aprovado preserva o conteúdo das ações');
select teste.ok((public.rpc_salvar_acao((select v from teste.var where k = 'plano'), '{"status":"em_andamento"}'::jsonb, (select v from teste.var where k = 'acao'))->>'id') is not null, 'plano aprovado aceita acompanhamento do status da ação');
select teste.ok((select (o->>'realizado')::numeric = (select count(distinct pessoa_id) from public.oportunidades where ies_id = 1 and coorte = '2027.1' and curso_id = 1 and etapa = 'confirmado')
                 from jsonb_array_elements(public.rpc_planejamento(1, '2027.1')->'planos'->0->'objetivos') o where o->>'indicador' = 'ingressantes'), 'realizado calculado dos dados, não digitado');
select teste.ok((select o->'realizado' = 'null'::jsonb from jsonb_array_elements(public.rpc_planejamento(1, '2027.1')->'planos'->0->'objetivos') o where o->>'indicador' = 'cpl_centavos'), 'CPL sem custo lançado é N/D, não zero');
select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false);
select teste.erro('select public.rpc_plano_status((select v from teste.var where k = ''plano''), ''revisar'', ''tentativa cruzada'')', 'P0002', 'gestor de outra IES não alcança o plano');
select teste.ok(jsonb_array_length(public.rpc_planejamento(2, '2027.1')->'planos') = 0, 'planejamento isolado por instituição');

-- ---------------------------------------------------------------- concorrência
select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false);
select teste.erro('select public.rpc_registrar_concorrencia(1, ''{"instituicao":"Faculdade X","curso":"Direito","fonte_url":"sem fonte","coletado_em":"2026-11-01"}''::jsonb)', '22023', 'concorrência sem fonte verificável recusada');
select teste.erro('select public.rpc_registrar_concorrencia(1, ''{"instituicao":"Faculdade X","curso":"Direito","fonte_url":"https://exemplo.invalid/direito","coletado_em":"2099-01-01"}''::jsonb)', '22023', 'data de coleta futura recusada');
insert into teste.var values ('conc', (public.rpc_registrar_concorrencia(1, jsonb_build_object('instituicao', 'Faculdade X (fictícia)', 'curso', 'Direito', 'modalidade', 'presencial',
  'mensalidade_centavos', 119000, 'fonte_url', 'https://exemplo.invalid/direito', 'coletado_em', current_date - 3))->>'id')::bigint);
select teste.erro('select public.rpc_revisar_concorrencia((select v from teste.var where k = ''conc''))', '42501', 'coordenação não revisa registro de concorrência');
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.ok((public.rpc_revisar_concorrencia((select v from teste.var where k = 'conc'))->>'revisado')::boolean, 'gestor revisa registro feito por outra pessoa');
select teste.ok((public.rpc_concorrencia(1)->0->>'revisado_por') is not null, 'registro mostra quem revisou');

-- ---------------------------------------------------------------- campanhas, custos e atribuição
insert into teste.var values ('camp', (public.rpc_salvar_campanha(1, jsonb_build_object('coorte', '2027.1', 'nome', 'Vestibular de verão', 'codigo', 'verao-2027',
  'canal', 'meta_ads', 'inicio', '2026-11-01', 'fim', '2027-02-28', 'orcamento_centavos', 1200000, 'status', 'ativa', 'plano_id', (select v from teste.var where k = 'plano')))->>'id')::bigint);
select teste.erro('select public.rpc_salvar_campanha(1, ''{"coorte":"2027.1","nome":"Outra","codigo":"verao-2027","canal":"site","inicio":"2026-11-01","fim":"2027-01-01"}''::jsonb)', '23505', 'código de campanha repetido: conflito');
select teste.erro('select public.rpc_salvar_campanha(1, ''{"coorte":"2027.1","nome":"Inválida","codigo":"Código Ruim","canal":"site","inicio":"2026-11-01","fim":"2027-01-01"}''::jsonb)', '22023', 'código de campanha fora do padrão recusado');
select teste.erro('select public.rpc_salvar_campanha(1, ''{"coorte":"2027.1","nome":"Datas","codigo":"datas-ruins","canal":"site","inicio":"2027-02-01","fim":"2027-01-01"}''::jsonb)', '22023', 'fim antes do início recusado');
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro('select public.rpc_salvar_campanha(1, ''{"coorte":"2027.1","nome":"Do atendente","codigo":"do-atendente","canal":"site","inicio":"2026-11-01","fim":"2027-01-01"}''::jsonb)', '42501', 'comercial não cria campanha');
select teste.ok((select c->>'codigo' = 'verao-2027' and c->'custo_centavos' = 'null'::jsonb from jsonb_array_elements(public.rpc_campanhas(1, '2027.1')->'campanhas') c),
  'comercial vê a campanha e o código, sem custos');
insert into teste.var values ('op_camp', (public.rpc_criar_oportunidade(1, jsonb_build_object('nome', 'Lead da Campanha', 'email', 'lead.campanha@exemplo.invalid', 'curso_id', 1,
  'forma_ingresso', 'vestibular', 'coorte', '2027.1', 'base_legal', 'consentimento', 'origem', 'anúncio', 'campanha', 'VERAO-2027'), 'camp-lead-0001')->>'id')::bigint);
select teste.erro('select public.rpc_criar_oportunidade(1, jsonb_build_object(''nome'', ''Lead perdido'', ''email'', ''perdido@exemplo.invalid'', ''curso_id'', 1, ''forma_ingresso'', ''enem'', ''coorte'', ''2027.1'', ''base_legal'', ''consentimento'', ''origem'', ''x'', ''campanha'', ''nao-existe''), ''camp-lead-0002'')',
  '22023', 'código de campanha inexistente é recusado (atribuição não se perde em silêncio)');
select set_config('request.jwt.claim.sub', teste.id('financeiro_a')::text, false);
select teste.erro('select public.rpc_lancar_custo((select v from teste.var where k = ''camp''), current_date + 1, 1000, ''futuro'', ''custo-futuro-1'')', '22023', 'custo com data futura recusado');
insert into teste.var values ('custo', (public.rpc_lancar_custo((select v from teste.var where k = 'camp'), current_date, 300000, 'Impulsionamento novembro', 'custo-nov-0001')->>'id')::bigint);
select teste.ok((public.rpc_lancar_custo((select v from teste.var where k = 'camp'), current_date, 300000, 'Impulsionamento novembro', 'custo-nov-0001')->>'repeticao')::boolean, 'lançamento repetido com a mesma chave não duplica');
insert into teste.var values ('custo_erro', (public.rpc_lancar_custo((select v from teste.var where k = 'camp'), current_date, 99999, 'Lançado por engano', 'custo-erro-0001')->>'id')::bigint);
select teste.erro('select public.rpc_estornar_custo((select v from teste.var where k = ''custo_erro''), '''')', '22023', 'estorno sem motivo recusado');
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.ok((public.rpc_estornar_custo((select v from teste.var where k = 'custo_erro'), 'valor lançado em duplicidade')->>'estornado')::boolean, 'estorno auditado');
select teste.ok((select (c->>'custo_centavos')::bigint = 300000 and (c->>'leads')::int = 1 and (c->>'cpl_centavos')::bigint = 300000
                 from jsonb_array_elements(public.rpc_campanhas(1, '2027.1')->'campanhas') c where c->>'codigo' = 'verao-2027'), 'CPL da campanha = custo sem estornos ÷ leads atribuídos');
select teste.ok((select (c->>'custo_ingressante_centavos') is null from jsonb_array_elements(public.rpc_campanhas(1, '2027.1')->'campanhas') c where c->>'codigo' = 'verao-2027'),
  'custo por ingressante N/D sem ingressante atribuído');
select teste.ok((public.rpc_campanhas(1, '2027.1')->'atribuicao_desconhecida'->>'leads')::int > 0, 'leads sem campanha aparecem como atribuição desconhecida');
select teste.ok((select (t->>'custo_por_lead_centavos')::bigint = 300000 and (t->>'leads_atribuidos')::int = 1 from (select public.rpc_central(1, '2027.1')->'totais' t) x), 'Central mostra CPL com custo lançado');
select teste.ok((public.rpc_central(1, '2027.1', '{"curso_id":"1"}')->'totais'->>'custo_motivo') like '%não é rateado%', 'Central: custo N/D com recorte por curso, com motivo');
select teste.ok((select (t->>'oportunidades')::int = 1 from (select public.rpc_central(1, '2027.1', jsonb_build_object('campanha_id', (select v from teste.var where k = 'camp')::text))->'totais' t) x), 'filtro global de campanha na Central');
select teste.ok((public.rpc_central(1, '2027.1')->'por_campanha') @? '$[*] ? (@.chave == "Atribuição desconhecida")', 'Central separa atribuição desconhecida');
select teste.ok((select (o->>'realizado')::numeric = 300000 from jsonb_array_elements(public.rpc_planejamento(1, '2027.1')->'planos'->0->'objetivos') o where o->>'indicador' = 'cpl_centavos'), 'objetivo de CPL acompanha o custo lançado');
select teste.ok((public.rpc_planejamento(1, '2027.1')->'planos'->0->>'gasto_centavos')::bigint = 300000, 'gasto do plano soma custos das campanhas vinculadas, sem estornos');
select set_config('request.jwt.claim.sub', teste.id('reitoria_a')::text, false);
select teste.ok((select (t->>'custo_por_lead_centavos') is not null from (select public.rpc_central(1, '2027.1')->'totais' t) x), 'reitoria vê custos');
select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false);
select teste.ok((select (t->>'custo_por_lead_centavos') is null and (t->>'custo_motivo') like '%apenas%' from (select public.rpc_central(1, '2027.1')->'totais' t) x), 'coordenação não vê custos, com motivo');
select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false);
select teste.erro('select public.rpc_lancar_custo((select v from teste.var where k = ''camp''), current_date, 100, ''cruzado'', ''custo-cruzado-1'')', 'P0002', 'gestor de outra IES não lança custo na campanha da Alfa');
select teste.ok(jsonb_array_length(public.rpc_campanhas(2, '2027.1')->'campanhas') = 0, 'campanhas isoladas por instituição');
select teste.erro('select public.rpc_criar_oportunidade(2, jsonb_build_object(''nome'', ''Cruzado'', ''email'', ''cruzado@exemplo.invalid'', ''curso_id'', 3, ''forma_ingresso'', ''enem'', ''coorte'', ''2027.1'', ''base_legal'', ''consentimento'', ''origem'', ''x'', ''campanha'', ''verao-2027''), ''camp-cruzada-001'')',
  '22023', 'código de campanha de outra IES não é aceito');
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.erro('select public.rpc_salvar_campanha(1, ''{"codigo":"novo-codigo"}''::jsonb, (select v from teste.var where k = ''camp''), 1)', '22023', 'código não muda com oportunidades atribuídas');

-- tabelas novas só por RPC
select teste.erro('select count(*) from public.campanhas', '42501', 'campanhas sem leitura direta (só por RPC)');
select teste.erro('select count(*) from public.planos', '42501', 'planos sem leitura direta (só por RPC)');
select teste.erro('insert into public.custos_campanha(ies_id, campanha_id, data, valor_centavos, descricao, lancado_por) values (1, 1, current_date, 1, ''x'', auth.uid())', '42501', 'escrita direta em custos bloqueada');
reset role;
select teste.ok(true, 'fim da bateria de planejamento e campanhas');
