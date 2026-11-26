-- Testes de governança (migração 11): abrangência explícita, escopo por campus, matriz × RPCs, exportação, acesso cruzado.
\set ON_ERROR_STOP on
reset role;
-- Estrutura extra: segundo campus na Alfa, com um curso, e dois usuários sem escopo ainda.
insert into public.campus(ies_id, nome) values (1, 'Sul');
insert into public.cursos(ies_id, campus_id, nome, turno, modalidade, mensalidade_centavos, desconto_max_pct)
  values (1, (select id from public.campus where ies_id = 1 and nome = 'Sul'), 'Pedagogia', 'noturno', 'presencial', 89000, 30);
insert into teste.usuario values ('gestor_sul', '00000000-0000-0000-0000-0000000000d1'), ('com_sul', '00000000-0000-0000-0000-0000000000d2');
insert into auth.users(id, email) values ('00000000-0000-0000-0000-0000000000d1', 'gestor.sul@exemplo.invalid'), ('00000000-0000-0000-0000-0000000000d2', 'com.sul@exemplo.invalid');
insert into public.usuarios(id, nome) values ('00000000-0000-0000-0000-0000000000d1', 'gestor_sul'), ('00000000-0000-0000-0000-0000000000d2', 'com_sul');
insert into teste.var values ('sul', (select id from public.campus where ies_id = 1 and nome = 'Sul'));
insert into teste.var values ('ped', (select id from public.cursos where ies_id = 1 and nome = 'Pedagogia'));

-- Tenta uma chamada e devolve 'ok' ou o SQLSTATE lógico; desfaz qualquer efeito da chamada.
create or replace function teste.tenta(p_sql text) returns text language plpgsql as $f$
begin
  begin
    execute p_sql;
    raise exception using errcode = 'T0001';
  exception when others then
    if sqlstate = 'T0001' then return 'ok'; end if;
    if sqlstate = 'PGRST' then return sqlerrm::jsonb->>'code'; end if;
    return sqlstate;
  end;
end $f$;
grant execute on function teste.tenta(text) to authenticated;

-- abrangência é obrigatória e coerente (escrita do dono do banco, sem RPC)
select teste.erro('insert into public.escopos(usuario_id, ies_id, curso_id, papel) values (teste.id(''com_sul''), 1, null, ''comercial'')', '23502', 'escopo sem abrangência declarada é recusado (nulo não é curinga)');
select teste.erro('insert into public.escopos(usuario_id, ies_id, abrangencia, curso_id, papel) values (teste.id(''com_sul''), 1, ''ies'', 1, ''comercial'')', '23514', 'abrangência incoerente com o curso é recusada');
select teste.erro('insert into public.escopos(usuario_id, ies_id, abrangencia, campus_id, papel) values (teste.id(''com_sul''), 1, ''campus'', 2, ''comercial'')', '22023', 'campus de outra IES é recusado');
select teste.ok((select bool_and(abrangencia in ('ies','campus','curso')) from public.escopos), 'todos os escopos existentes têm abrangência explícita');

-- concessão pelo Master
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('master')::text, false);
select teste.erro('select public.rpc_conceder_escopo(teste.id(''com_sul''), 1, 1, ''comercial'', 1)', '22023', 'curso e campus ao mesmo tempo: recusado');
select teste.erro('select public.rpc_conceder_escopo(teste.id(''com_sul''), 1, null, ''coordenador'')', '22023', 'coordenação com abrangência de instituição: recusada');
select teste.ok(public.rpc_conceder_escopo(teste.id('com_sul'), 1, null, 'comercial', (select v from teste.var where k = 'sul'))->>'abrangencia' = 'campus', 'Master concede comercial com abrangência de campus');
select teste.ok(public.rpc_conceder_escopo(teste.id('gestor_sul'), 1, null, 'gestor', (select v from teste.var where k = 'sul'))->>'abrangencia' = 'campus', 'Master concede gestor com abrangência de campus');
select teste.erro('select public.rpc_conceder_escopo(teste.id(''com_sul''), 1, null, ''comercial'', (select v from teste.var where k = ''sul''))', '23505', 'escopo repetido: conflito (409)');
select teste.ok((select count(*) = 1 from jsonb_array_elements(public.rpc_master_acessos(1)->'escopos') e where e->>'abrangencia' = 'campus' and e->>'nome' = 'com_sul'), 'painel do Master mostra a abrangência');

-- escopo por campus: cobre só os cursos do campus
select set_config('request.jwt.claim.sub', teste.id('com_sul')::text, false);
select teste.ok((select array_agg(x->>'nome') = array['Pedagogia'] from jsonb_array_elements(public.rpc_estrutura(1)->'cursos') x), 'comercial do campus Sul vê apenas o curso do campus');
select teste.ok((public.rpc_estrutura(1)->>'acesso_total')::boolean = false, 'escopo de campus não é acesso total');
insert into teste.var values ('op_ped', (public.rpc_criar_oportunidade(1, jsonb_build_object('nome', 'Cand Pedagogia', 'email', 'ped@exemplo.invalid', 'curso_id', (select v from teste.var where k = 'ped'),
  'forma_ingresso', 'enem', 'coorte', '2027.1', 'base_legal', 'consentimento', 'origem', 'teste governança'), 'gov-ped-1')->>'id')::bigint);
select teste.ok((public.rpc_listar_oportunidades(1, null, null, 1, 100)->>'total')::int = 1, 'lista do campus contém só a oportunidade do campus');
select teste.erro('select public.rpc_detalhe((select min(id) from public.oportunidades where ies_id = 1 and curso_id = 1))', 'P0002', 'oportunidade de outro campus: não encontrada');
select teste.erro('select public.rpc_criar_oportunidade(1, jsonb_build_object(''nome'', ''X'', ''curso_id'', 1, ''forma_ingresso'', ''enem'', ''coorte'', ''2027.1'', ''base_legal'', ''consentimento'', ''origem'', ''t''), ''gov-fora-campus-1'')', '42501', 'não cadastra em curso fora do campus');

select set_config('request.jwt.claim.sub', teste.id('gestor_sul')::text, false);
select teste.erro('select public.rpc_configurar(1, 24)', '42501', 'gestor de campus não altera parâmetros da instituição');
select teste.erro('select public.rpc_auditoria(1, 1)', '42501', 'gestor de campus não lê a auditoria da instituição');
select teste.ok((public.rpc_detalhe((select v from teste.var where k = 'op_ped'))->'pessoa'->>'email') = 'ped@exemplo.invalid', 'gestor de campus vê o contato no seu campus');
select teste.erro('select public.rpc_atendentes(1)', '42501', 'gestor de campus não lista atendentes da instituição inteira');
select teste.ok((select bool_or(x->>'nome' = 'com_sul') from jsonb_array_elements(public.rpc_atendentes(1, (select v from teste.var where k = 'ped'))) x), 'gestor de campus lista os atendentes do curso do seu campus');

-- distribuição respeita o campus
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.ok((select o.responsavel_id in (teste.id('com_sul'), teste.id('comercial_a')) from public.oportunidades o where o.id = (select v from teste.var where k = 'op_ped')), 'distribuição só escolhe atendente que cobre o curso');
select teste.ok((select bool_and(x->>'nome' <> 'com_sul') from jsonb_array_elements(public.rpc_atendentes(1, 1)) x), 'atendente do campus Sul não é elegível para curso de outro campus');
select teste.ok((select bool_or(x->>'nome' = 'com_sul') from jsonb_array_elements(public.rpc_atendentes(1, (select v from teste.var where k = 'ped'))) x), 'atendente do campus Sul é elegível no curso do campus');

-- matriz de permissões × comportamento real das RPCs (papéis da Alfa com abrangência de instituição ou curso)
reset role;
create temp table conformidade as
select m.operacao, u.apelido, (e.papel = any (m.papeis)) as esperado, s.sql_teste
  from public.matriz_permissoes m
  join (values
    ('config.alterar',  'select public.rpc_configurar(1, 24)'),
    ('auditoria.ver',   'select public.rpc_auditoria(1, 1)'),
    ('meta.definir',    'select public.rpc_definir_meta(1, 1, ''2027.1'', 10)'),
    ('maim.executar',   'select public.rpc_ciclo_maim(1)'),
    ('fila.ver',        'select public.rpc_fila(1)'),
    ('crm.exportar',    'select public.rpc_exportar_oportunidades(1)'),
    ('painel.ver',      'select public.rpc_central(1, ''2027.1'')')) as s(operacao, sql_teste) on s.operacao = m.operacao
  cross join (values ('gestor_a'), ('reitoria_a'), ('comercial_a'), ('secretaria_a'), ('financeiro_a')) as u(apelido)
  join public.escopos e on e.usuario_id = teste.id(u.apelido) and e.revogado_em is null;
grant select on conformidade to authenticated;
set role authenticated;
do $$
declare r record; got text; n int := 0;
begin
  for r in select * from conformidade loop
    perform set_config('request.jwt.claim.sub', teste.id(r.apelido)::text, false);
    got := teste.tenta(r.sql_teste);
    if r.esperado and got = '42501' then raise exception 'FALHOU: matriz permite % para %, mas a RPC recusou', r.operacao, r.apelido; end if;
    if not r.esperado and got <> '42501' then raise exception 'FALHOU: matriz nega % para %, mas a RPC devolveu %', r.operacao, r.apelido, got; end if;
    n := n + 1;
  end loop;
  if n < 30 then raise exception 'FALHOU: poucas combinações verificadas (%)', n; end if;
end $$;
select teste.ok(true, 'matriz de permissões confere com as RPCs (7 operações × 5 papéis)');

-- permissões efetivas
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.ok((select bool_and(((x->>'permitida')::boolean) = (x->'papeis' ? 'comercial')) from jsonb_array_elements(public.rpc_permissoes(1)->'matriz') x
                 where x->>'abrangencia_minima' = 'curso'), 'permissões efetivas do comercial batem com a matriz');
select set_config('request.jwt.claim.sub', teste.id('gestor_sul')::text, false);
select teste.ok((select bool_and(not (x->>'permitida')::boolean) from jsonb_array_elements(public.rpc_permissoes(1)->'matriz') x where x->>'abrangencia_minima' = 'ies'),
  'gestor de campus não recebe operações de instituição');

-- exportação
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.ok((select (r->>'contato_completo')::boolean and (r->>'total')::int = jsonb_array_length(r->'linhas') and (r->>'total')::int > 0
                 from (select public.rpc_exportar_oportunidades(1, '2027.1') r) x), 'gestor exporta a coorte com contato');
select teste.ok((select count(*) from public.auditoria where acao = 'exportacao.gerar' and not (dados ? 'linhas_exportadas') and dados ? 'linhas') >= 1, 'exportação auditada com volume e sem os dados');
select teste.erro('select public.rpc_exportar_oportunidades(1, ''2027'')', '22023', 'coorte inválida na exportação recusada');
select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false);
select teste.ok((select not (r->>'contato_completo')::boolean and bool_and(l->>'email' is null or l->>'email' like '%*%') and bool_and((l->>'curso') = 'Direito')
                 from (select public.rpc_exportar_oportunidades(1) r) x, jsonb_array_elements(r->'linhas') l group by r), 'coordenação exporta só o seu curso e com contato mascarado');
select teste.erro('select public.rpc_exportar_oportunidades(1, null, 2)', 'P0002', 'coordenação não exporta curso fora do escopo');
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro('select public.rpc_exportar_oportunidades(1)', '42501', 'comercial não exporta');
select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false);
select teste.erro('select public.rpc_exportar_oportunidades(1)', 'P0002', 'gestor de outra IES: exportação não encontrada');

-- R09: acesso cruzado entre instituições pela API, com IDs adulterados
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.erro('select public.rpc_estrutura(2)', 'P0002', 'R09: estrutura da IES 2 recusada ao gestor da IES 1');
select teste.erro('select public.rpc_central(2, ''2027.1'')', 'P0002', 'R09: painel da IES 2 recusado');
select teste.erro('select public.rpc_permissoes(2)', 'P0002', 'R09: permissões da IES 2 recusadas');
select teste.erro('select public.rpc_agenda(2, now(), now() + interval ''1 day'')', 'P0002', 'R09: agenda da IES 2 recusada');
select teste.ok((public.rpc_listar_oportunidades(1, null, null, 1, 100)->'itens') @? '$[*] ? (@.curso == "Psicologia")' = false, 'R09: lista da IES 1 não contém curso da IES 2');
select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false);
select teste.ok((select count(*) from public.oportunidades where curso_id <> 1) = 0, 'R09: coordenação de curso não lê outros cursos nem por tabela direta');


-- visibilidade por atribuição: atendente vê só as suas; chefe do setor (gestor) vê as da equipe
reset role;
insert into teste.var values ('total_a', (select count(*) from public.oportunidades where ies_id = 1));
insert into teste.var values ('op_mov', (select min(id) from public.oportunidades where ies_id = 1 and curso_id = 1
                                          and responsavel_id = teste.id('comercial_a')));
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select public.rpc_reatribuir((select v from teste.var where k = 'op_mov'), teste.id('com_dir_a'), 'teste de visibilidade por atribuição');
select teste.ok((public.rpc_listar_oportunidades(1, null, null, 1, 100)->>'total')::int = (select v from teste.var where k = 'total_a'), 'chefe do setor (gestor) vê todas as oportunidades da equipe');
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.ok((select bool_and(x->>'responsavel' = 'comercial_a') from jsonb_array_elements(public.rpc_listar_oportunidades(1, null, null, 1, 100)->'itens') x), 'atendente lista só as oportunidades atribuídas a si');
select teste.ok((select count(*) from public.oportunidades where responsavel_id is distinct from teste.id('comercial_a')) = 0, 'atendente não lê oportunidades de colegas nem por tabela direta');
select teste.ok((select count(*) from public.pessoas p where not exists (select 1 from public.oportunidades o where o.pessoa_id = p.id)) = 0, 'atendente não lê dados pessoais de candidatos de colegas');
select teste.erro('select public.rpc_detalhe((select v from teste.var where k = ''op_mov''))', 'P0002', 'após reatribuição, o atendente anterior perde o acesso (404)');
select teste.erro('select public.rpc_mover_etapa((select v from teste.var where k = ''op_mov''), ''perdido'', 99, ''x'')', 'P0002', 'atendente não move oportunidade de colega');
select teste.erro('select public.rpc_registrar_interacao((select v from teste.var where k = ''op_mov''), ''ligacao'', ''tentativa'')', 'P0002', 'atendente não registra contato em oportunidade de colega');
select teste.ok((select count(*) from jsonb_array_elements(public.rpc_listar_propostas(1, 'pendente_aprovacao')) x
                 where not exists (select 1 from public.oportunidades o where o.id = (x->>'oportunidade_id')::bigint)) = 0, 'atendente não vê propostas de oportunidades de colegas');
insert into teste.var values ('op_propria', (public.rpc_criar_oportunidade(1, jsonb_build_object('nome', 'Lead do Atendente', 'email', 'lead.atendente@exemplo.invalid', 'curso_id', 1,
  'forma_ingresso', 'vestibular', 'coorte', '2027.1', 'base_legal', 'consentimento', 'origem', 'indicação'), 'gov-lead-atendente-1')->>'id')::bigint);
select teste.ok((select responsavel_id = teste.id('comercial_a') from public.oportunidades where id = (select v from teste.var where k = 'op_propria')), 'quem cadastra como atendente assume o lead');
select set_config('request.jwt.claim.sub', teste.id('com_dir_a')::text, false);
select teste.ok((public.rpc_detalhe((select v from teste.var where k = 'op_mov'))->'oportunidade'->>'id')::bigint = (select v from teste.var where k = 'op_mov'), 'novo responsável passa a ver a oportunidade');
select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false);
select teste.ok((public.rpc_listar_oportunidades(1, null, null, 1, 100)->>'total')::int > 1, 'secretaria mantém a visão do escopo (validações)');
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.ok((select (x->>'permitida')::boolean from jsonb_array_elements(public.rpc_permissoes(1)->'matriz') x where x->>'operacao' = 'crm.ver_equipe'), 'matriz: gestor tem crm.ver_equipe');
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.ok((select not (x->>'permitida')::boolean from jsonb_array_elements(public.rpc_permissoes(1)->'matriz') x where x->>'operacao' = 'crm.ver_equipe'), 'matriz: atendente não tem crm.ver_equipe');

-- revogação do escopo de campus tem efeito imediato
select set_config('request.jwt.claim.sub', teste.id('master')::text, false);
select public.rpc_revogar_escopo((select id from public.escopos where usuario_id = teste.id('com_sul') and revogado_em is null));
select set_config('request.jwt.claim.sub', teste.id('com_sul')::text, false);
select teste.erro('select public.rpc_estrutura(1)', 'P0002', 'escopo de campus revogado: instituição deixa de ser visível');
reset role;
select teste.ok(true, 'fim da bateria de governança');
