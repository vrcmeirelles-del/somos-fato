-- Testes de implantação: convites, campus e cursos, checklist (migração 35).
\set ON_ERROR_STOP on
reset role;
create temp table imp (chave text primary key, v text);
grant all on imp to anon, authenticated;
-- contas novas no Supabase Auth, ainda sem perfil no sistema
insert into auth.users(id, email) values ('00000000-0000-0000-0000-0000000000f1', 'nova.atendente@exemplo.invalid'), ('00000000-0000-0000-0000-0000000000f2', 'intrusa@exemplo.invalid');
set role authenticated;
select set_config('request.jwt.claims', '', false);

select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro($q$select public.rpc_criar_convite(1, '{"email":"x@exemplo.invalid","papel":"comercial"}')$q$, '42501', 'comercial não convida');
select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false);
select teste.erro($q$select public.rpc_criar_convite(1, '{"email":"x@exemplo.invalid","papel":"comercial"}')$q$, '42501', 'gestor de outra IES não convida');
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.erro($q$select public.rpc_criar_convite(1, '{"papel":"comercial","usos_max":5}')$q$, '22023', 'convite coletivo só na demonstração');
select teste.erro($q$select public.rpc_criar_convite(1, '{"papel":"comercial"}')$q$, '22023', 'convite individual exige e-mail');
select teste.erro($q$select public.rpc_criar_convite(1, '{"email":"x@exemplo.invalid","papel":"master"}')$q$, '22023', 'perfil inexistente recusado');
insert into imp select 'cod', public.rpc_criar_convite(1, jsonb_build_object('email','Nova.Atendente@exemplo.invalid','nome','Nova Atendente','papel','comercial','curso_id',1))->>'codigo';
select teste.ok((select length(v) = 64 from imp where chave = 'cod'), 'convite gera código de 64 caracteres');
reset role;
select teste.ok((select count(*) = 1 and bool_and(codigo_hash <> (select v from imp where chave = 'cod')) from public.convites where email = 'nova.atendente@exemplo.invalid'), 'só o hash do código fica no banco');
set role anon;
select teste.ok((select r->>'papel' = 'comercial' and r->>'email' like 'n***@%' and (r->>'email_fixo')::boolean from (select public.rpc_publico_convite((select v from imp where chave = 'cod')) r) x),
  'página pública mostra o convite com e-mail mascarado');
select teste.erro($q$select public.rpc_publico_convite(repeat('b', 64))$q$, 'P0002', 'código inválido: 404');
select teste.erro($q$select public.rpc_aceitar_convite((select v from imp where chave = 'cod'))$q$, '42501', 'anônimo não aceita convite');
reset role; set role authenticated;
-- conta com outro e-mail não aceita
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f2', false);
select set_config('request.jwt.claims', '{"email":"intrusa@exemplo.invalid"}', false);
select teste.erro($q$select public.rpc_aceitar_convite((select v from imp where chave = 'cod'))$q$, '42501', 'e-mail diferente do convite: recusado');
-- a pessoa convidada aceita
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f1', false);
select set_config('request.jwt.claims', '{"email":"nova.atendente@exemplo.invalid"}', false);
select teste.ok((public.rpc_aceitar_convite((select v from imp where chave = 'cod'), 'Nova Atendente Sintética')->>'papel') = 'comercial', 'convidada aceita e recebe o perfil');
select teste.ok((public.rpc_me()->'usuario'->>'nome') = 'Nova Atendente Sintética', 'perfil criado com o nome informado');
select teste.ok((select count(*) = 1 from jsonb_array_elements(public.rpc_me()->'escopos') e where e->>'papel' = 'comercial' and e->>'abrangencia' = 'curso'), 'escopo restrito ao curso do convite');
select teste.erro($q$select public.rpc_aceitar_convite((select v from imp where chave = 'cod'))$q$, 'P0002', 'convite de uso único não serve de novo');
select set_config('request.jwt.claims', '', false);

-- campus, cursos e checklist
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro($q$select public.rpc_salvar_campus(1, 'Campus Norte')$q$, '42501', 'comercial não cadastra campus');
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
insert into imp select 'campus', public.rpc_salvar_campus(1, 'Campus Norte Sintético')->>'id';
select teste.erro($q$select public.rpc_salvar_curso(1, '{"campus_id":999999,"nome":"Enfermagem","turno":"noturno","modalidade":"presencial","mensalidade_centavos":150000}')$q$, '22023', 'curso em campus de outra IES recusado');
select teste.erro($q$select public.rpc_salvar_curso(1, jsonb_build_object('campus_id',(select v from imp where chave = 'campus'),'nome','Enfermagem','turno','madrugada','modalidade','presencial','mensalidade_centavos',150000))$q$, '22023', 'turno inválido recusado');
select teste.ok((public.rpc_salvar_curso(1, jsonb_build_object('campus_id',(select v from imp where chave = 'campus'),'nome','Enfermagem','turno','noturno','modalidade','presencial','mensalidade_centavos',150000))->>'id') is not null, 'gestor cadastra curso');
select teste.ok((select (r->>'total')::int = 14 and (r->>'concluidos')::int between 1 and 14 and jsonb_array_length(r->'cursos') >= 1 and (r->>'pode_gerir')::boolean
                 from (select public.rpc_implantacao(1) r) x), 'checklist com 14 itens e situação calculada');
select teste.ok((select count(*) >= 1 from jsonb_array_elements(public.rpc_convites(1)) c where c->>'situacao' = 'usado' and c->>'aceito_por' like 'Nova Atendente%'), 'lista de convites mostra quem aceitou');
select set_config('request.jwt.claim.sub', teste.id('reitoria_a')::text, false);
select teste.ok(not (public.rpc_implantacao(1)->>'pode_gerir')::boolean, 'reitoria acompanha o checklist sem gerir');
reset role;
select teste.ok((select count(*) >= 4 from public.auditoria where acao in ('convite.criar','convite.aceitar','implantacao.campus','implantacao.curso')), 'implantação auditada');
