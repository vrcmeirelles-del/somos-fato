-- Testes da verificação em duas etapas (migração 26). O nível da sessão vem do claim "aal" (request.jwt.claims).
\set ON_ERROR_STOP on
reset role;
select set_config('request.jwt.claims', '', false);
select teste.ok((select count(*) = 0 from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
                   and not exists (select 1 from pg_policy p where p.polrelid = c.oid and p.polname = 'mfa_obrigatorio' and not p.polpermissive)),
  'toda tabela com RLS tem a política restritiva de 2FA');

set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false);
select teste.ok((public.rpc_seguranca_conta()->>'ok')::boolean and (public.rpc_me()->'usuario'->>'id') is not null, 'sem fator e sem exigência: acesso normal');
reset role;
insert into auth.mfa_factors(user_id, status) values (teste.id('secretaria_a'), 'verified');
set role authenticated;
select teste.erro($q$select public.rpc_me()$q$, 'M3601', 'com fator verificado e sessão aal1: pede o código');
select teste.ok((select count(*) = 0 from public.oportunidades), 'leitura direta da tabela também bloqueada em aal1');
select teste.ok((select r->>'aal' = 'aal1' and (r->>'tem_fator')::boolean and not (r->>'ok')::boolean from (select public.rpc_seguranca_conta() r) x), 'situação da conta responde mesmo sem o código');
select set_config('request.jwt.claims', '{"aal":"aal2"}', false);
select teste.ok((public.rpc_me()->'usuario'->>'id') is not null and (select count(*) > 0 from public.oportunidades), 'sessão aal2 libera RPC e leitura');
select set_config('request.jwt.claims', '', false);

-- exigência por IES
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.erro($q$select public.rpc_configurar_2fa(1, true)$q$, '22023', 'gestor sem fator não exige 2FA da equipe');
reset role;
insert into auth.mfa_factors(user_id, status) values (teste.id('gestor_a'), 'verified');
set role authenticated;
select teste.erro($q$select public.rpc_configurar_2fa(1, true)$q$, 'M3601', 'gestor com fator precisa estar em aal2');
select set_config('request.jwt.claims', '{"aal":"aal2"}', false);
select teste.ok((select (r->>'exigir_2fa')::boolean and (r->>'usuarios_sem_fator')::int >= 1 from (select public.rpc_configurar_2fa(1, true) r) x), 'gestor em aal2 exige 2FA e vê quantos ainda não têm fator');
select teste.ok((select (s->>'exigir_2fa')::boolean and exists (select 1 from jsonb_array_elements(s->'equipe') e where not (e->>'com_fator')::boolean) from (select public.rpc_situacao_2fa(1) s) x),
  'painel mostra quem ainda não tem fator');
select set_config('request.jwt.claims', '', false);
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro($q$select public.rpc_me()$q$, 'M3602', 'IES exige 2FA e o usuário não tem fator: pede o cadastro');
select teste.ok((select (r->>'exigido')::boolean and not (r->>'tem_fator')::boolean and r->'ies_que_exigem' ? 'Faculdade Alfa' from (select public.rpc_seguranca_conta() r) x)
  or (select (r->>'exigido')::boolean from (select public.rpc_seguranca_conta() r) x), 'situação da conta indica a exigência');
select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false);
select teste.ok((public.rpc_me()->'usuario'->>'id') is not null, 'equipe de outra IES não é afetada');
select teste.erro($q$select public.rpc_configurar_2fa(1, false)$q$, 'P0002', 'outra IES não muda a exigência');
-- desliga e limpa para os testes seguintes
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select set_config('request.jwt.claims', '{"aal":"aal2"}', false);
select teste.ok(not (public.rpc_configurar_2fa(1, false)->>'exigir_2fa')::boolean, 'gestor desliga a exigência');
select set_config('request.jwt.claims', '', false);
reset role;
select teste.ok((select count(*) = 2 from public.auditoria where acao = 'seguranca.2fa'), 'mudanças de exigência auditadas');
delete from auth.mfa_factors;
