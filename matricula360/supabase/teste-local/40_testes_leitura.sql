-- Testes das RPCs de leitura (migração 5). Roda depois de 30_testes_complementares.sql.
\set ON_ERROR_STOP on

set role anon;
select teste.erro('select public.rpc_me()', '42501', 'anon não chama rpc_me');
select teste.erro('select public.rpc_detalhe(1)', '42501', 'anon não chama rpc_detalhe');
reset role;

set role authenticated;
-- identidade
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.ok(jsonb_array_length(public.rpc_me()->'escopos') = 1 and public.rpc_me()->'escopos'->0->>'papel' = 'gestor', 'rpc_me devolve só os próprios escopos');
select set_config('request.jwt.claim.sub', teste.id('revogado_a')::text, false);
select teste.erro('select public.rpc_me()', '42501', 'usuário revogado não obtém identidade');

-- estrutura respeita curso autorizado
select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false);
select teste.ok(jsonb_array_length(public.rpc_estrutura(1)->'cursos') = 1 and public.rpc_estrutura(1)->'cursos'->0->>'nome' = 'Direito', 'estrutura do coordenador lista só Direito');
select teste.ok((public.rpc_estrutura(1)->>'acesso_total')::boolean = false, 'coordenador sem acesso total');
select teste.erro('select public.rpc_estrutura(2)', 'P0002', 'estrutura de IES alheia => não encontrado');

-- detalhe: minimização e escopo
select teste.ok((select (d->'pessoa'->>'dados_mascarados')::boolean and d->'pessoa'->>'email' like '%***@%'
                        and d->'pessoa'->>'email' <> (select p.email from public.pessoas p where p.id = (d->'pessoa'->>'id')::bigint union all select '' limit 1)
                 from (select public.rpc_detalhe((select min(id) from public.oportunidades where curso_id = 1 and etapa = 'novo')) d) x),
  'detalhe para coordenador vem com contato mascarado');
select teste.ok(jsonb_array_length(public.rpc_detalhe((select min(id) from public.oportunidades where curso_id = 1))->'propostas') = 0,
  'coordenador não vê propostas no detalhe');
reset role;
insert into teste.var values ('adm', (select min(id) from public.oportunidades where ies_id = 1 and curso_id = 2));
insert into teste.var values ('beta', (select min(id) from public.oportunidades where ies_id = 2));
set role authenticated;
select teste.erro('select public.rpc_detalhe((select v from teste.var where k=''adm''))', 'P0002', 'detalhe de curso não autorizado => não encontrado');
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.ok((select (d->'pessoa'->>'dados_mascarados')::boolean = false and jsonb_array_length(d->'historico') >= 1
                 from (select public.rpc_detalhe((select v from teste.var where k='adm')) d) x), 'gestor vê contato pleno e histórico');
select teste.erro('select public.rpc_detalhe((select v from teste.var where k=''beta''))', 'P0002', 'detalhe de outra IES => não encontrado');
select set_config('request.jwt.claim.sub', teste.id('master')::text, false);
select teste.erro('select public.rpc_detalhe((select v from teste.var where k=''adm''))', 'P0002', 'Master não lê detalhe de candidato');

-- listas
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.ok((select bool_and((x->>'curso_id')::int = 2) from jsonb_array_elements(public.rpc_listar_oportunidades(1, null, null, 1, 100, 2)->'itens') x), 'filtro por curso');
select teste.ok((public.rpc_listar_oportunidades(1, null, null, 1, 100, 2)->>'total')::int = (select count(*) from public.oportunidades where ies_id = 1 and curso_id = 2), 'total do filtro por curso correto');
select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false);
select teste.ok((public.rpc_listar_oportunidades(1, null, null, 1, 100, 2)->>'total')::int = 0, 'coordenador filtrando curso alheio recebe zero itens');
select teste.erro('select public.rpc_listar_propostas(1)', '42501', 'coordenador não lista propostas');
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.ok(jsonb_typeof(public.rpc_listar_propostas(1, 'aceita')) = 'array', 'comercial lista propostas');
select teste.ok((select bool_and(x ? 'nome' and x ? 'responsavel') from jsonb_array_elements(public.rpc_fila(1)->'tarefas') x) is not false, 'fila traz nome e responsável');

-- BI com agrupamento
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.ok((select sum((x->>'oportunidades')::int) from jsonb_array_elements(public.rpc_bi(1, '2027.1', 'turno')->'linhas') x)
                = (public.rpc_bi(1, '2027.1', 'turno')->'totais'->>'oportunidades')::int, 'BI por turno soma o total');
select teste.ok((public.rpc_bi(1, '2035.2', 'atendente')->'totais'->>'conversao') is null, 'BI agrupado mantém N/D em coorte vazia');
select teste.erro('select public.rpc_bi(1, ''2027.1'', ''pessoa'')', '22023', 'agrupamento inválido recusado');

-- auditoria
select teste.ok((public.rpc_auditoria(1)->>'total')::int > 0, 'gestor lê auditoria');
select teste.ok(not (public.rpc_auditoria(1)::text ~ '@exemplo\.invalid'), 'auditoria exibida sem e-mails');
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro('select public.rpc_auditoria(1)', '42501', 'comercial não lê auditoria');

-- Master
select teste.erro('select public.rpc_master_listar_ies()', '42501', 'não Master não lista IES');
select set_config('request.jwt.claim.sub', teste.id('master')::text, false);
select teste.ok(jsonb_array_length(public.rpc_master_listar_ies()) = 2, 'Master lista as IES');
select teste.ok(jsonb_array_length(public.rpc_master_acessos(1)->'escopos') >= 7, 'Master vê acessos da IES');
select teste.erro('select public.rpc_conceder_escopo_email(''ninguem@exemplo.invalid'', ''X'', 1, null, ''comercial'')', '22023', 'e-mail sem conta no Auth recusado');
reset role;
insert into auth.users(id, email) values ('00000000-0000-0000-0000-0000000000c1', 'novo.atendente@exemplo.invalid');
set role authenticated;
select teste.ok((public.rpc_conceder_escopo_email('NOVO.Atendente@exemplo.invalid', 'Novo Atendente', 1, 1, 'comercial')->>'perfil_novo')::boolean, 'Master concede escopo por e-mail e cria perfil');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
select teste.ok((select count(*) from public.oportunidades) = (select count(*) from public.oportunidades where curso_id = 1) and (select count(*) from public.oportunidades) > 0,
  'novo atendente enxerga só o curso concedido');
reset role;
do $$ begin raise notice 'OK  fim da bateria de leitura'; end $$;
