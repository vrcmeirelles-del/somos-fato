-- Matrícula 360° — migração 26 (Onda A, L22): verificação em duas etapas (TOTP) da equipe.
-- Para o SQL Editor do projeto jbimijcvvekomovodfze. Requer as migrações anteriores aplicadas (aplique na ordem 023 → 030).
-- CONFIRA o projeto na URL antes de executar. Idempotente. Transação única. A última linha deve ser commit;
begin;
-- Matrícula 360° — migração 26 (Onda A, L22): verificação em duas etapas (TOTP) da equipe.
--   * Usa o MFA por aplicativo autenticador do Supabase Auth (TOTP: gratuito e habilitado em todos os projetos, segundo a
--     documentação do Supabase). O cadastro do fator e a verificação do código acontecem no Supabase Auth; o banco só confere
--     o nível da sessão (claim "aal" do JWT).
--   * Regra: quem tem fator verificado só usa o sistema com sessão aal2. Se alguma IES do usuário exigir 2FA e ele ainda não
--     tiver fator, o sistema pede o cadastro antes de qualquer operação.
--   * Aplicada em dois pontos: privado.exigir_usuario() (todas as RPCs da equipe) e política RESTRITIVA em todas as tabelas
--     com RLS (leitura direta pela API). Funções públicas do candidato não mudam.
--   * O gestor liga ou desliga a exigência por IES (auditado). Para desligar, a própria sessão precisa estar em aal2.
-- Idempotente.

alter table public.ies add column if not exists exigir_2fa boolean not null default false;

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('seguranca.2fa', 'Governança Institucional', 'Exigir verificação em duas etapas da equipe da IES', array['gestor'], 'ies', 'rpc_configurar_2fa')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

create or replace function privado.tem_fator() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from auth.mfa_factors f where f.user_id = (select auth.uid()) and f.status = 'verified');
$$;
create or replace function privado.exige_2fa() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.escopos e join public.ies i on i.id = e.ies_id
                  where e.usuario_id = (select auth.uid()) and e.revogado_em is null and i.exigir_2fa);
$$;
create or replace function privado.mfa_ok() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select auth.jwt()->>'aal'), 'aal1') = 'aal2' or (not privado.tem_fator() and not privado.exige_2fa());
$$;
revoke execute on function privado.tem_fator(), privado.exige_2fa(), privado.mfa_ok() from public, anon;
grant execute on function privado.mfa_ok() to authenticated;

create or replace function privado.exigir_usuario() returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare v uuid := (select auth.uid());
begin
  if v is null or not privado.usuario_ativo() then
    raise exception 'Sessão ausente, expirada ou usuário revogado' using errcode = '42501';
  end if;
  if not privado.mfa_ok() then
    if privado.tem_fator() then
      raise exception 'Confirme o código do aplicativo autenticador para continuar' using errcode = 'M3601';
    end if;
    raise exception 'A instituição exige verificação em duas etapas: cadastre o aplicativo autenticador para continuar' using errcode = 'M3602';
  end if;
  return v;
end $$;

-- Política restritiva em todas as tabelas com RLS do esquema public: leitura direta também exige o nível adequado.
do $$
declare t record;
begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity loop
    execute format('drop policy if exists mfa_obrigatorio on public.%I', t.relname);
    execute format('create policy mfa_obrigatorio on public.%I as restrictive for all to authenticated using ((select privado.mfa_ok()))', t.relname);
  end loop;
end $$;

-- Situação da conta (não exige 2FA: é o que a tela de login consulta para decidir o próximo passo).
create or replace function public.rpc_seguranca_conta()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null or not privado.usuario_ativo() then raise exception 'Sessão ausente, expirada ou usuário revogado' using errcode = '42501'; end if;
  return jsonb_build_object('aal', coalesce((select auth.jwt()->>'aal'), 'aal1'), 'tem_fator', privado.tem_fator(), 'exigido', privado.exige_2fa(),
    'ok', privado.mfa_ok(),
    'ies_que_exigem', (select coalesce(jsonb_agg(distinct i.nome), '[]'::jsonb) from public.escopos e join public.ies i on i.id = e.ies_id
                       where e.usuario_id = (select auth.uid()) and e.revogado_em is null and i.exigir_2fa));
end $$;

create or replace function public.rpc_configurar_2fa(p_ies bigint, p_exigir boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare n_sem int;
begin
  perform privado.autorizar(p_ies, 'seguranca.2fa');
  if p_exigir and not privado.tem_fator() then
    raise exception 'Cadastre o seu aplicativo autenticador antes de exigir 2FA da equipe' using errcode = '22023'; end if;
  update public.ies set exigir_2fa = p_exigir where id = p_ies;
  select count(distinct e.usuario_id) into n_sem from public.escopos e
   where e.ies_id = p_ies and e.revogado_em is null and not exists (select 1 from auth.mfa_factors f where f.user_id = e.usuario_id and f.status = 'verified');
  perform privado.auditar(p_ies, 'seguranca.2fa', 'ies', p_ies::text, jsonb_build_object('exigir', p_exigir, 'usuarios_sem_fator', n_sem));
  return jsonb_build_object('exigir_2fa', p_exigir, 'usuarios_sem_fator', n_sem);
end $$;

create or replace function public.rpc_situacao_2fa(p_ies bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.autorizar(p_ies, 'seguranca.2fa');
  return jsonb_build_object('exigir_2fa', (select exigir_2fa from public.ies where id = p_ies),
    'equipe', (select coalesce(jsonb_agg(jsonb_build_object('nome', privado.nome_usuario(u.id), 'com_fator',
                 exists (select 1 from auth.mfa_factors f where f.user_id = u.id and f.status = 'verified')) order by privado.nome_usuario(u.id)), '[]'::jsonb)
               from public.usuarios u where u.revogado_em is null and exists (select 1 from public.escopos e where e.usuario_id = u.id and e.ies_id = p_ies and e.revogado_em is null)));
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.rpc_seguranca_conta(), public.rpc_configurar_2fa(bigint, boolean), public.rpc_situacao_2fa(bigint) to authenticated;
select privado.conceder_publico();

commit;
