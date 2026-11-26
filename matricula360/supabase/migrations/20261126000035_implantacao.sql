-- Matrícula 360° — migração 35: implantação de novos clientes e entrada da equipe.
--   * Convites: o Master (qualquer IES) ou o gestor (a própria IES) gera um convite com perfil e abrangência; o link é mostrado uma vez
--     (só o hash fica no banco) e a equipe entrega pelo próprio canal. A pessoa cria a conta (ou entra com a que já tem) e aceita;
--     o e-mail da conta precisa ser o do convite. Convite coletivo (vários usos, sem e-mail fixo) só em IES de demonstração.
--   * Cadastro de campus e cursos pelo gestor depois da implantação (antes só o Master, no provisionamento).
--   * Checklist de implantação calculado a partir do que já está configurado, com o caminho de cada tela.
--   * ies.demonstracao: marca a IES de demonstração e treinamento (usada pela migração 36).
-- Idempotente.

alter table public.ies add column if not exists demonstracao boolean not null default false;

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('implantacao.gerir', 'Governança Institucional', 'Convidar a equipe, cadastrar campus e cursos e acompanhar o checklist de implantação', array['gestor'], 'ies', 'rpc_implantacao')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

create table if not exists public.convites (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  codigo_hash text not null unique,
  email text check (email is null or email ~ '^[^\s@]+@[^\s@]+\.[^\s@]+$'),
  nome text check (length(nome) <= 120),
  papel text not null check (papel in ('gestor','reitoria','coordenador','comercial','secretaria','financeiro')),
  abrangencia text not null check (abrangencia in ('ies','campus','curso')),
  campus_id bigint references public.campus(id),
  curso_id bigint references public.cursos(id),
  usos_max int not null default 1 check (usos_max between 1 and 200),
  usos int not null default 0,
  expira_em timestamptz not null,
  revogado_em timestamptz,
  criado_por uuid references public.usuarios(id),
  criado_em timestamptz not null default now(),
  check ((abrangencia = 'ies' and campus_id is null and curso_id is null) or (abrangencia = 'campus' and campus_id is not null and curso_id is null)
         or (abrangencia = 'curso' and curso_id is not null))
);
create table if not exists public.convites_usos (
  convite_id bigint not null references public.convites(id),
  usuario_id uuid not null references public.usuarios(id),
  em timestamptz not null default now(),
  primary key (convite_id, usuario_id)
);
create index if not exists convites_ies on public.convites(ies_id);
create index if not exists convites_campus on public.convites(campus_id);
create index if not exists convites_curso on public.convites(curso_id);
create index if not exists convites_criado on public.convites(criado_por);
create index if not exists convites_usos_usuario on public.convites_usos(usuario_id);
alter table public.convites enable row level security;
alter table public.convites_usos enable row level security;
revoke all on public.convites, public.convites_usos from anon, authenticated;
do $$ begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'privado' and p.proname = 'mfa_ok') then
    execute 'drop policy if exists mfa_obrigatorio on public.convites; create policy mfa_obrigatorio on public.convites as restrictive for all to authenticated using ((select privado.mfa_ok()))';
    execute 'drop policy if exists mfa_obrigatorio on public.convites_usos; create policy mfa_obrigatorio on public.convites_usos as restrictive for all to authenticated using ((select privado.mfa_ok()))';
  end if;
end $$;

-- Quem pode convidar para a IES: Master ou gestor com abrangência da instituição.
create or replace function privado.pode_convidar(p_ies bigint) returns boolean
language sql stable security definer set search_path = '' as $$
  select privado.eh_master() or privado.tem_acesso_ies(p_ies, array['gestor'])
$$;
revoke execute on function privado.pode_convidar(bigint) from public, anon, authenticated;

create or replace function public.rpc_criar_convite(p_ies bigint, p_dados jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare d jsonb := coalesce(p_dados, '{}'::jsonb); cod text := privado.novo_token(); v_id bigint; abr text; demo boolean; usos int;
begin
  perform privado.exigir_usuario();
  if not exists (select 1 from public.ies where id = p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if not privado.pode_convidar(p_ies) then raise exception 'Só o Master ou o gestor da instituição convidam' using errcode = '42501'; end if;
  select demonstracao into demo from public.ies where id = p_ies;
  usos := coalesce((d->>'usos_max')::int, 1);
  if usos > 1 and not demo then raise exception 'Convite coletivo só no ambiente de demonstração' using errcode = '22023'; end if;
  if usos = 1 and nullif(trim(d->>'email'), '') is null then raise exception 'Informe o e-mail da pessoa convidada' using errcode = '22023'; end if;
  abr := case when nullif(d->>'curso_id', '') is not null then 'curso' when nullif(d->>'campus_id', '') is not null then 'campus' else 'ies' end;
  if abr = 'curso' and not exists (select 1 from public.cursos where id = (d->>'curso_id')::bigint and ies_id = p_ies) then raise exception 'Curso fora da instituição' using errcode = '22023'; end if;
  if abr = 'campus' and not exists (select 1 from public.campus where id = (d->>'campus_id')::bigint and ies_id = p_ies) then raise exception 'Campus fora da instituição' using errcode = '22023'; end if;
  insert into public.convites(ies_id, codigo_hash, email, nome, papel, abrangencia, campus_id, curso_id, usos_max, expira_em, criado_por)
  values (p_ies, privado.hash_token(cod), nullif(lower(trim(d->>'email')), ''), nullif(trim(d->>'nome'), ''), d->>'papel', abr,
          case when abr = 'campus' then (d->>'campus_id')::bigint end, case when abr = 'curso' then (d->>'curso_id')::bigint end,
          usos, now() + make_interval(days => least(greatest(coalesce((d->>'validade_dias')::int, 7), 1), 30)), (select auth.uid()))
  returning id into v_id;
  perform privado.auditar(p_ies, 'convite.criar', 'convite', v_id::text, jsonb_build_object('papel', d->>'papel', 'abrangencia', abr, 'usos_max', usos, 'email', privado.mascarar_email(nullif(lower(trim(d->>'email')), ''))));
  return jsonb_build_object('id', v_id, 'codigo', cod, 'aviso', 'Copie o link agora: ele não será exibido de novo. Entregue pelo seu canal (o sistema não envia e-mail).');
exception when check_violation then raise exception 'Dados do convite inválidos (perfil ou e-mail)' using errcode = '22023';
end $$;

create or replace function public.rpc_convites(p_ies bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform privado.exigir_usuario();
  if not privado.pode_convidar(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'email', c.email, 'nome', c.nome, 'papel', c.papel, 'abrangencia', c.abrangencia,
      'alvo', coalesce((select nome from public.cursos where id = c.curso_id), (select nome from public.campus where id = c.campus_id)), 'usos', c.usos, 'usos_max', c.usos_max,
      'expira_em', c.expira_em, 'situacao', case when c.revogado_em is not null then 'revogado' when c.usos >= c.usos_max then 'usado' when c.expira_em < now() then 'expirado' else 'pendente' end,
      'aceito_por', (select string_agg(privado.nome_usuario(u.usuario_id), ', ') from public.convites_usos u where u.convite_id = c.id),
      'criado_por', privado.nome_usuario(c.criado_por), 'criado_em', c.criado_em) order by c.criado_em desc), '[]'::jsonb)
    from public.convites c where c.ies_id = p_ies);
end $$;

create or replace function public.rpc_revogar_convite(p_id bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c public.convites;
begin
  perform privado.exigir_usuario();
  select * into c from public.convites where id = p_id for update;
  if not found or not privado.pode_convidar(c.ies_id) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  update public.convites set revogado_em = now() where id = c.id and revogado_em is null;
  perform privado.auditar(c.ies_id, 'convite.revogar', 'convite', c.id::text, '{}'::jsonb);
  return jsonb_build_object('id', c.id, 'revogado', true);
end $$;

-- Página pública do convite: mostra para onde é o convite, sem dado pessoal além do e-mail mascarado.
create or replace function public.rpc_publico_convite(p_codigo text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c public.convites;
begin
  if p_codigo is null or length(p_codigo) <> 64 then perform privado.erro_http(404, 'P0002', 'Convite inválido ou expirado'); end if;
  select * into c from public.convites where codigo_hash = privado.hash_token(p_codigo);
  if not found or c.revogado_em is not null or c.expira_em < now() or c.usos >= c.usos_max then perform privado.erro_http(404, 'P0002', 'Convite inválido ou expirado'); end if;
  return jsonb_build_object('instituicao', (select nome from public.ies where id = c.ies_id), 'demonstracao', (select demonstracao from public.ies where id = c.ies_id),
    'papel', c.papel, 'alvo', coalesce((select nome from public.cursos where id = c.curso_id), (select nome from public.campus where id = c.campus_id)),
    'email', privado.mascarar_email(c.email), 'email_fixo', c.email is not null, 'nome', c.nome, 'expira_em', c.expira_em);
end $$;

-- Aceite: pessoa autenticada no Supabase Auth (com ou sem perfil no sistema). Não exige perfil prévio.
create or replace function public.rpc_aceitar_convite(p_codigo text, p_nome text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c public.convites; eu uuid := (select auth.uid()); meu_email text; v_nome text;
begin
  if eu is null then raise exception 'Entre com a sua conta para aceitar o convite' using errcode = '42501'; end if;
  if exists (select 1 from public.usuarios where id = eu and revogado_em is not null) then raise exception 'Conta revogada' using errcode = '42501'; end if;
  if p_codigo is null or length(p_codigo) <> 64 then perform privado.erro_http(404, 'P0002', 'Convite inválido ou expirado'); end if;
  select * into c from public.convites where codigo_hash = privado.hash_token(p_codigo) for update;
  if not found or c.revogado_em is not null or c.expira_em < now() or c.usos >= c.usos_max then perform privado.erro_http(404, 'P0002', 'Convite inválido ou expirado'); end if;
  meu_email := lower(coalesce((select auth.jwt()->>'email'), (select email from auth.users where id = eu)));
  if c.email is not null and c.email <> meu_email then raise exception 'Este convite é para outro e-mail. Entre com a conta de %', privado.mascarar_email(c.email) using errcode = '42501'; end if;
  if exists (select 1 from public.convites_usos where convite_id = c.id and usuario_id = eu) then raise exception 'Você já usou este convite' using errcode = '22023'; end if;
  v_nome := coalesce(nullif(trim(p_nome), ''), c.nome, split_part(meu_email, '@', 1));
  if length(v_nome) < 2 then raise exception 'Informe seu nome' using errcode = '22023'; end if;
  insert into public.usuarios(id, nome) values (eu, v_nome) on conflict (id) do nothing;
  if not exists (select 1 from public.escopos e where e.usuario_id = eu and e.ies_id = c.ies_id and e.papel = c.papel and e.revogado_em is null
                   and e.abrangencia = c.abrangencia and e.campus_id is not distinct from c.campus_id and e.curso_id is not distinct from c.curso_id) then
    insert into public.escopos(usuario_id, ies_id, abrangencia, campus_id, curso_id, papel) values (eu, c.ies_id, c.abrangencia, c.campus_id, c.curso_id, c.papel);
  end if;
  insert into public.convites_usos(convite_id, usuario_id) values (c.id, eu);
  update public.convites set usos = usos + 1 where id = c.id;
  perform privado.auditar(c.ies_id, 'convite.aceitar', 'convite', c.id::text, jsonb_build_object('papel', c.papel, 'abrangencia', c.abrangencia));
  return jsonb_build_object('ies_id', c.ies_id, 'papel', c.papel, 'instituicao', (select nome from public.ies where id = c.ies_id));
end $$;

-- ---------------------------------------------------------------- campus e cursos (gestor)
create or replace function public.rpc_salvar_campus(p_ies bigint, p_nome text, p_id bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  perform privado.autorizar(p_ies, 'implantacao.gerir');
  if length(coalesce(trim(p_nome), '')) < 2 then raise exception 'Nome do campus obrigatório' using errcode = '22023'; end if;
  if p_id is null then insert into public.campus(ies_id, nome) values (p_ies, trim(p_nome)) returning id into v_id;
  else update public.campus set nome = trim(p_nome) where id = p_id and ies_id = p_ies returning id into v_id;
    if v_id is null then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  end if;
  perform privado.auditar(p_ies, 'implantacao.campus', 'campus', v_id::text, jsonb_build_object('nome', trim(p_nome), 'novo', p_id is null));
  return jsonb_build_object('id', v_id);
exception when unique_violation then raise exception 'Já existe campus com este nome' using errcode = '22023';
end $$;

create or replace function public.rpc_salvar_curso(p_ies bigint, p_dados jsonb, p_id bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare d jsonb := coalesce(p_dados, '{}'::jsonb); v_id bigint;
begin
  perform privado.autorizar(p_ies, 'implantacao.gerir');
  if nullif(d->>'campus_id', '') is not null and not exists (select 1 from public.campus where id = (d->>'campus_id')::bigint and ies_id = p_ies) then
    raise exception 'Campus fora da instituição' using errcode = '22023'; end if;
  if p_id is null then
    insert into public.cursos(ies_id, campus_id, nome, turno, modalidade, mensalidade_centavos, desconto_max_pct)
    values (p_ies, (d->>'campus_id')::bigint, trim(d->>'nome'), d->>'turno', d->>'modalidade', (d->>'mensalidade_centavos')::int, coalesce((d->>'desconto_max_pct')::numeric, 30))
    returning id into v_id;
  else
    update public.cursos set nome = coalesce(trim(d->>'nome'), nome), mensalidade_centavos = coalesce((d->>'mensalidade_centavos')::int, mensalidade_centavos),
      desconto_max_pct = coalesce((d->>'desconto_max_pct')::numeric, desconto_max_pct)
    where id = p_id and ies_id = p_ies returning id into v_id;
    if v_id is null then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  end if;
  perform privado.auditar(p_ies, 'implantacao.curso', 'curso', v_id::text, jsonb_build_object('nome', d->>'nome', 'novo', p_id is null));
  return jsonb_build_object('id', v_id);
exception when unique_violation then raise exception 'Curso já existe neste campus e turno' using errcode = '22023';
  when check_violation or not_null_violation then raise exception 'Dados do curso inválidos (campus, nome, turno, modalidade e mensalidade)' using errcode = '22023';
end $$;

-- ---------------------------------------------------------------- checklist de implantação
create or replace function public.rpc_implantacao(p_ies bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_coorte text := case when extract(month from current_date) <= 6 then to_char(current_date, 'YYYY') || '.2' else (extract(year from current_date)::int + 1)::text || '.1' end; itens jsonb; i public.ies;
begin
  perform privado.exigir_usuario();
  if not (privado.eh_master() or privado.tem_acesso_ies(p_ies, array['gestor','reitoria'])) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  select * into i from public.ies where id = p_ies;
  itens := jsonb_build_array(
    jsonb_build_object('item', 'Campus e cursos com mensalidade', 'ok', exists (select 1 from public.cursos where ies_id = p_ies), 'onde', 'Governança → Implantação'),
    jsonb_build_object('item', 'Metas da próxima coorte (' || v_coorte || ')', 'ok', exists (select 1 from public.metas m where m.ies_id = p_ies and m.coorte = v_coorte), 'onde', 'Governança → Configurações e metas'),
    jsonb_build_object('item', 'Gestor da instituição', 'ok', exists (select 1 from public.escopos where ies_id = p_ies and papel = 'gestor' and revogado_em is null), 'onde', 'Governança → Implantação (convites)'),
    jsonb_build_object('item', 'Equipe comercial', 'ok', exists (select 1 from public.escopos where ies_id = p_ies and papel = 'comercial' and revogado_em is null), 'onde', 'Governança → Implantação (convites)'),
    jsonb_build_object('item', 'Secretaria', 'ok', exists (select 1 from public.escopos where ies_id = p_ies and papel = 'secretaria' and revogado_em is null), 'onde', 'Governança → Implantação (convites)'),
    jsonb_build_object('item', 'Financeiro', 'ok', exists (select 1 from public.escopos where ies_id = p_ies and papel = 'financeiro' and revogado_em is null), 'onde', 'Governança → Implantação (convites)'),
    jsonb_build_object('item', 'Documentos exigidos revisados', 'ok', exists (select 1 from public.auditoria where ies_id = p_ies and acao = 'documentos.configurar'), 'onde', 'Governança → Integrações e dados'),
    jsonb_build_object('item', 'Contrato da matrícula online publicado (validado pelo jurídico)', 'ok', exists (select 1 from public.contratos_modelo where ies_id = p_ies and ativo), 'onde', 'Governança → Integrações e dados'),
    jsonb_build_object('item', 'Formulário de captação ativo', 'ok', exists (select 1 from public.formularios where ies_id = p_ies and ativo), 'onde', 'Marketing e Captação → Formulários de captação'),
    jsonb_build_object('item', 'Modelos de mensagem da régua', 'ok', exists (select 1 from public.modelos_mensagem where ies_id = p_ies and ativo), 'onde', 'Marketing e Captação → Comunicação e réguas'),
    jsonb_build_object('item', 'Programas de bolsa e financiamento', 'ok', exists (select 1 from public.programas_bolsa where ies_id = p_ies and ativo), 'onde', 'Conversão e Matrículas → Bolsas e financiamento'),
    jsonb_build_object('item', 'Campanha com código e custo', 'ok', exists (select 1 from public.campanhas where ies_id = p_ies), 'onde', 'Marketing e Captação → Campanhas e custos'),
    jsonb_build_object('item', 'Verificação em duas etapas exigida da equipe', 'ok', i.exigir_2fa, 'onde', 'Governança → Verificação em duas etapas'),
    jsonb_build_object('item', 'Automações revisadas', 'ok', exists (select 1 from public.automacoes where ies_id = p_ies and alterada_em is not null), 'onde', 'Governança → Automações'));
  return jsonb_build_object('instituicao', i.nome, 'demonstracao', i.demonstracao, 'pode_gerir', privado.eh_master() or privado.tem_acesso_ies(p_ies, array['gestor']),
    'concluidos', (select count(*) from jsonb_array_elements(itens) x where (x->>'ok')::boolean), 'total', jsonb_array_length(itens), 'itens', itens,
    'campus', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nome', nome) order by nome), '[]'::jsonb) from public.campus where ies_id = p_ies),
    'cursos', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'campus_id', c.campus_id, 'nome', c.nome, 'turno', c.turno, 'modalidade', c.modalidade,
        'mensalidade_centavos', c.mensalidade_centavos, 'desconto_max_pct', c.desconto_max_pct) order by c.nome), '[]'::jsonb) from public.cursos c where c.ies_id = p_ies),
    'equipe', (select coalesce(jsonb_agg(jsonb_build_object('nome', privado.nome_usuario(e.usuario_id), 'papel', e.papel, 'abrangencia', e.abrangencia)
        order by e.papel, privado.nome_usuario(e.usuario_id)), '[]'::jsonb) from public.escopos e where e.ies_id = p_ies and e.revogado_em is null));
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.rpc_criar_convite(bigint, jsonb), public.rpc_convites(bigint), public.rpc_revogar_convite(bigint), public.rpc_aceitar_convite(text, text),
  public.rpc_salvar_campus(bigint, text, bigint), public.rpc_salvar_curso(bigint, jsonb, bigint), public.rpc_implantacao(bigint) to authenticated;
select privado.conceder_publico();
