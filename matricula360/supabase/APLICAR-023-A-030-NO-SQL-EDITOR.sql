-- Matrícula 360° — migrações 23 a 30 (Ondas A, B e C) em um só arquivo para o SQL Editor do projeto jbimijcvvekomovodfze.
-- Requer as migrações 1 a 22 aplicadas. CONFIRA o projeto na URL antes de executar. Idempotente. Transação única. A última linha deve ser commit;
begin;
-- ===================== supabase/migrations/20261126000023_bolsas_financiamento.sql
-- Matrícula 360° — migração 23 (Onda A, L12): bolsas, descontos institucionais e financiamento estudantil.
--   * Programas por IES: ProUni (50% ou 100%), FIES, financiamento privado ou próprio, convênio com empresa e bolsa institucional;
--     cursos atendidos, percentual máximo, vagas, cumulatividade, validade, requisitos e documentos exigidos (informativos).
--   * Solicitação pela equipe ou pelo candidato no portal (com declaração de veracidade).
--   * Decisão humana e segregada: quem solicitou não decide; justificativa obrigatória; vagas e cumulatividade conferidas
--     com bloqueio de concorrência. Programas externos (ProUni, FIES, financiamento) registram a etapa informada pela instituição;
--     não há consulta aos sistemas do MEC ou de bancos.
--   * Painel: solicitações, aprovações, vagas restantes, percentual médio e confirmados com benefício.
--   [Não verificado] Regras dos programas federais mudam por edital; a instituição confere a cada processo.
-- Idempotente.

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('bolsa.ver',       'Conversão e Matrículas', 'Ver programas de bolsa e financiamento e as solicitações', array['gestor','financeiro','comercial','secretaria','coordenador','reitoria'], 'curso', 'rpc_bolsas'),
  ('bolsa.gerir',     'Conversão e Matrículas', 'Criar e editar programas de bolsa e financiamento',        array['gestor','financeiro'], 'ies', 'rpc_salvar_programa_bolsa'),
  ('bolsa.solicitar', 'Conversão e Matrículas', 'Registrar solicitação de bolsa para um candidato',         array['gestor','comercial','secretaria'], 'curso', 'rpc_solicitar_bolsa'),
  ('bolsa.decidir',   'Conversão e Matrículas', 'Aprovar ou indeferir bolsa (nunca a que solicitou)',      array['gestor','financeiro'], 'ies', 'rpc_decidir_bolsa')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

create table if not exists public.programas_bolsa (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  nome text not null check (length(nome) between 3 and 100),
  tipo text not null check (tipo in ('prouni','fies','financiamento_privado','financiamento_proprio','convenio_empresa','bolsa_institucional')),
  percentual_max numeric(5,2) not null check (percentual_max > 0 and percentual_max <= 100),
  cursos bigint[],
  vagas int check (vagas is null or vagas > 0),
  cumulativo boolean not null default false,
  validade_ate date,
  requisitos text check (length(requisitos) <= 2000),
  documentos text[] not null default '{}',
  visivel_portal boolean not null default true,
  ativo boolean not null default true,
  criado_por uuid references public.usuarios(id),
  criado_em timestamptz not null default now(),
  unique (ies_id, nome)
);
create table if not exists public.solicitacoes_bolsa (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  oportunidade_id bigint not null references public.oportunidades(id),
  programa_id bigint not null references public.programas_bolsa(id),
  percentual numeric(5,2) not null check (percentual > 0 and percentual <= 100),
  status text not null default 'solicitada' check (status in ('solicitada','aprovada','indeferida','cancelada')),
  etapa_externa text check (etapa_externa in ('inscricao','pre_selecao','documentacao','contratado','nao_contratado')),
  origem text not null check (origem in ('equipe','portal')),
  declaracao text check (length(declaracao) <= 1000),
  solicitado_por uuid references public.usuarios(id),
  solicitado_em timestamptz not null default now(),
  decidido_por uuid references public.usuarios(id),
  decidido_em timestamptz,
  justificativa text
);
create unique index if not exists bolsa_ativa_unica on public.solicitacoes_bolsa(oportunidade_id, programa_id) where status in ('solicitada','aprovada');
create index if not exists programas_bolsa_criado on public.programas_bolsa(criado_por);
create index if not exists solic_bolsa_ies on public.solicitacoes_bolsa(ies_id);
create index if not exists solic_bolsa_programa on public.solicitacoes_bolsa(programa_id);
create index if not exists solic_bolsa_solic on public.solicitacoes_bolsa(solicitado_por);
create index if not exists solic_bolsa_decid on public.solicitacoes_bolsa(decidido_por);
alter table public.programas_bolsa enable row level security;
alter table public.solicitacoes_bolsa enable row level security;
revoke all on public.programas_bolsa, public.solicitacoes_bolsa from anon, authenticated;

-- Oportunidade visível ao usuário para a operação da matriz (404 se não vê; 42501 se vê mas o perfil não permite).
create or replace function privado.op_operacao(p_op bigint, p_operacao text) returns public.oportunidades
language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades;
begin
  perform privado.exigir_usuario();
  select * into o from public.oportunidades where id = p_op for update;
  if not found or not privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro']) then
    perform privado.erro_http(404, 'P0002', 'Não encontrado');
  end if;
  if not privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, (select papeis from public.matriz_permissoes where operacao = p_operacao)) then
    raise exception 'Seu perfil não tem permissão para esta operação' using errcode = '42501';
  end if;
  return o;
end $$;
revoke execute on function privado.op_operacao(bigint, text) from public, anon, authenticated;

-- Regras do programa para uma oportunidade e um percentual (lança 22023 com a razão).
create or replace function privado.validar_bolsa(o public.oportunidades, g public.programas_bolsa, p_percentual numeric) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if g.ies_id <> o.ies_id or not g.ativo then perform privado.erro_http(404, 'P0002', 'Programa não encontrado'); end if;
  if g.validade_ate is not null and g.validade_ate < current_date then raise exception 'Programa encerrado em %', to_char(g.validade_ate, 'DD/MM/YYYY') using errcode = '22023'; end if;
  if g.cursos is not null and not (o.curso_id = any (g.cursos)) then raise exception 'O programa não atende este curso' using errcode = '22023'; end if;
  if o.etapa in ('perdido','cancelado') then raise exception 'Oportunidade encerrada' using errcode = '22023'; end if;
  if p_percentual is null or p_percentual <= 0 or p_percentual > g.percentual_max then
    raise exception 'Percentual deve ficar entre 0 e % %%', g.percentual_max using errcode = '22023'; end if;
  if g.tipo = 'prouni' and p_percentual not in (50, 100) then raise exception 'ProUni: bolsa integral (100%%) ou parcial (50%%)' using errcode = '22023'; end if;
end $$;
revoke execute on function privado.validar_bolsa(public.oportunidades, public.programas_bolsa, numeric) from public, anon, authenticated;

-- ---------------------------------------------------------------- programas
create or replace function public.rpc_salvar_programa_bolsa(p_ies bigint, p_dados jsonb, p_id bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id bigint; d jsonb := coalesce(p_dados, '{}'::jsonb); v_cursos bigint[];
begin
  perform privado.autorizar(p_ies, 'bolsa.gerir');
  if d ? 'cursos' and jsonb_typeof(d->'cursos') = 'array' and jsonb_array_length(d->'cursos') > 0 then
    select array_agg(x::bigint) into v_cursos from jsonb_array_elements_text(d->'cursos') x;
    if exists (select 1 from unnest(v_cursos) c where not exists (select 1 from public.cursos k where k.id = c and k.ies_id = p_ies)) then
      raise exception 'Curso fora da instituição' using errcode = '22023'; end if;
  end if;
  if coalesce(d->>'tipo', '') = 'prouni' and coalesce((d->>'percentual_max')::numeric, 0) not in (50, 100) then
    raise exception 'ProUni: percentual máximo 50 ou 100' using errcode = '22023'; end if;
  if p_id is null then
    insert into public.programas_bolsa(ies_id, nome, tipo, percentual_max, cursos, vagas, cumulativo, validade_ate, requisitos, documentos, visivel_portal, criado_por)
    values (p_ies, trim(d->>'nome'), d->>'tipo', (d->>'percentual_max')::numeric, v_cursos, nullif(d->>'vagas', '')::int, coalesce((d->>'cumulativo')::boolean, false),
            nullif(d->>'validade_ate', '')::date, nullif(trim(d->>'requisitos'), ''),
            coalesce((select array_agg(trim(x)) from jsonb_array_elements_text(coalesce(d->'documentos', '[]'::jsonb)) x where trim(x) <> ''), '{}'),
            coalesce((d->>'visivel_portal')::boolean, true), (select auth.uid()))
    returning id into v_id;
  else
    update public.programas_bolsa set
      nome = coalesce(trim(d->>'nome'), nome), percentual_max = coalesce((d->>'percentual_max')::numeric, percentual_max),
      cursos = case when d ? 'cursos' then v_cursos else programas_bolsa.cursos end,
      vagas = case when d ? 'vagas' then nullif(d->>'vagas', '')::int else vagas end,
      cumulativo = coalesce((d->>'cumulativo')::boolean, cumulativo),
      validade_ate = case when d ? 'validade_ate' then nullif(d->>'validade_ate', '')::date else validade_ate end,
      requisitos = case when d ? 'requisitos' then nullif(trim(d->>'requisitos'), '') else requisitos end,
      visivel_portal = coalesce((d->>'visivel_portal')::boolean, visivel_portal), ativo = coalesce((d->>'ativo')::boolean, ativo)
    where id = p_id and ies_id = p_ies returning id into v_id;
    if v_id is null then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  end if;
  perform privado.auditar(p_ies, 'bolsa.programa', 'programa_bolsa', v_id::text, jsonb_build_object('nome', d->>'nome', 'tipo', d->>'tipo', 'novo', p_id is null));
  return jsonb_build_object('id', v_id);
exception when unique_violation then raise exception 'Já existe programa com este nome' using errcode = '22023';
end $$;

-- ---------------------------------------------------------------- solicitação pela equipe
create or replace function public.rpc_solicitar_bolsa(p_op bigint, p_programa bigint, p_percentual numeric, p_observacao text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; g public.programas_bolsa; v_id bigint;
begin
  o := privado.op_operacao(p_op, 'bolsa.solicitar');
  select * into g from public.programas_bolsa where id = p_programa;
  if not found then perform privado.erro_http(404, 'P0002', 'Programa não encontrado'); end if;
  perform privado.validar_bolsa(o, g, p_percentual);
  insert into public.solicitacoes_bolsa(ies_id, oportunidade_id, programa_id, percentual, origem, declaracao, solicitado_por, etapa_externa)
  values (o.ies_id, o.id, g.id, p_percentual, 'equipe', nullif(trim(p_observacao), ''), (select auth.uid()),
          case when g.tipo in ('prouni','fies','financiamento_privado') then 'inscricao' end)
  returning id into v_id;
  perform privado.auditar(o.ies_id, 'bolsa.solicitar', 'oportunidade', o.id::text, jsonb_build_object('programa', g.nome, 'percentual', p_percentual, 'origem', 'equipe'));
  return jsonb_build_object('id', v_id, 'status', 'solicitada');
exception when unique_violation then raise exception 'Já há solicitação aberta ou aprovada deste programa' using errcode = '22023';
end $$;

-- ---------------------------------------------------------------- decisão (segregada) e etapa externa
create or replace function public.rpc_decidir_bolsa(p_id bigint, p_status text, p_justificativa text, p_percentual numeric default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare s public.solicitacoes_bolsa; g public.programas_bolsa; o public.oportunidades; pct numeric; usadas int;
begin
  perform privado.exigir_usuario();
  select * into s from public.solicitacoes_bolsa where id = p_id for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(s.ies_id, 'bolsa.decidir');
  if s.status <> 'solicitada' then raise exception 'Solicitação já decidida' using errcode = '22023'; end if;
  if p_status not in ('aprovada','indeferida') then raise exception 'Decisão inválida' using errcode = '22023'; end if;
  if length(coalesce(trim(p_justificativa), '')) < 5 then raise exception 'Justificativa obrigatória' using errcode = '22023'; end if;
  if s.solicitado_por = (select auth.uid()) then raise exception 'Quem solicitou não decide a própria solicitação' using errcode = '42501'; end if;
  select * into g from public.programas_bolsa where id = s.programa_id for update;
  select * into o from public.oportunidades where id = s.oportunidade_id;
  pct := coalesce(p_percentual, s.percentual);
  if p_status = 'aprovada' then
    perform privado.validar_bolsa(o, g, pct);
    select count(*) into usadas from public.solicitacoes_bolsa where programa_id = g.id and status = 'aprovada';
    if g.vagas is not null and usadas >= g.vagas then raise exception 'Vagas do programa esgotadas (% de %)', usadas, g.vagas using errcode = '22023'; end if;
    if exists (select 1 from public.solicitacoes_bolsa x join public.programas_bolsa y on y.id = x.programa_id
               where x.oportunidade_id = o.id and x.status = 'aprovada' and x.id <> s.id and (not y.cumulativo or not g.cumulativo)) then
      raise exception 'Benefício não cumulativo com outro já aprovado' using errcode = '22023'; end if;
  end if;
  update public.solicitacoes_bolsa set status = p_status, percentual = pct, justificativa = trim(p_justificativa),
    decidido_por = (select auth.uid()), decidido_em = now() where id = s.id;
  perform privado.auditar(s.ies_id, 'bolsa.decidir', 'oportunidade', o.id::text, jsonb_build_object('programa', g.nome, 'status', p_status, 'percentual', pct));
  return jsonb_build_object('id', s.id, 'status', p_status, 'percentual', pct);
end $$;

create or replace function public.rpc_etapa_bolsa(p_id bigint, p_etapa text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare s public.solicitacoes_bolsa; g public.programas_bolsa;
begin
  perform privado.exigir_usuario();
  select * into s from public.solicitacoes_bolsa where id = p_id for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(s.ies_id, 'bolsa.decidir');
  select * into g from public.programas_bolsa where id = s.programa_id;
  if g.tipo not in ('prouni','fies','financiamento_privado') then raise exception 'Etapa externa só para ProUni, FIES e financiamento privado' using errcode = '22023'; end if;
  if p_etapa not in ('inscricao','pre_selecao','documentacao','contratado','nao_contratado') then raise exception 'Etapa inválida' using errcode = '22023'; end if;
  update public.solicitacoes_bolsa set etapa_externa = p_etapa where id = s.id;
  perform privado.auditar(s.ies_id, 'bolsa.etapa', 'oportunidade', s.oportunidade_id::text, jsonb_build_object('programa', g.nome, 'etapa', p_etapa));
  return jsonb_build_object('id', s.id, 'etapa_externa', p_etapa);
end $$;

create or replace function public.rpc_cancelar_bolsa(p_id bigint, p_motivo text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare s public.solicitacoes_bolsa;
begin
  perform privado.exigir_usuario();
  select * into s from public.solicitacoes_bolsa where id = p_id for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(s.ies_id, 'bolsa.decidir');
  if s.status not in ('solicitada','aprovada') then raise exception 'Nada a cancelar' using errcode = '22023'; end if;
  if length(coalesce(trim(p_motivo), '')) < 5 then raise exception 'Motivo obrigatório' using errcode = '22023'; end if;
  update public.solicitacoes_bolsa set status = 'cancelada', justificativa = trim(p_motivo), decidido_por = (select auth.uid()), decidido_em = now() where id = s.id;
  perform privado.auditar(s.ies_id, 'bolsa.cancelar', 'oportunidade', s.oportunidade_id::text, jsonb_build_object('motivo', trim(p_motivo)));
  return jsonb_build_object('id', s.id, 'status', 'cancelada');
end $$;

-- ---------------------------------------------------------------- leitura
create or replace function public.rpc_bolsas(p_ies bigint, p_op bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare papeis text[] := (select papeis from public.matriz_permissoes where operacao = 'bolsa.ver');
begin
  perform privado.autorizar(p_ies, 'bolsa.ver');
  return jsonb_build_object(
    'pode_gerir', privado.pode(p_ies, 'bolsa.gerir'), 'pode_decidir', privado.pode(p_ies, 'bolsa.decidir'), 'pode_solicitar', privado.pode(p_ies, 'bolsa.solicitar'),
    'aviso', 'Decisão humana e segregada. ProUni, FIES e financiamento: a etapa externa é informada pela instituição; o sistema não consulta MEC nem bancos. [Não verificado] Regras federais mudam por edital.',
    'programas', (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'nome', g.nome, 'tipo', g.tipo, 'percentual_max', g.percentual_max, 'cursos', g.cursos,
        'vagas', g.vagas, 'cumulativo', g.cumulativo, 'validade_ate', g.validade_ate, 'requisitos', g.requisitos, 'documentos', g.documentos,
        'visivel_portal', g.visivel_portal, 'ativo', g.ativo,
        'solicitadas', (select count(*) from public.solicitacoes_bolsa s where s.programa_id = g.id and s.status = 'solicitada'),
        'aprovadas', (select count(*) from public.solicitacoes_bolsa s where s.programa_id = g.id and s.status = 'aprovada'),
        'confirmados', (select count(*) from public.solicitacoes_bolsa s join public.oportunidades o on o.id = s.oportunidade_id where s.programa_id = g.id and s.status = 'aprovada' and o.etapa = 'confirmado'),
        'percentual_medio', (select round(avg(s.percentual), 1) from public.solicitacoes_bolsa s where s.programa_id = g.id and s.status = 'aprovada')
      ) order by g.ativo desc, g.nome), '[]'::jsonb) from public.programas_bolsa g where g.ies_id = p_ies),
    'solicitacoes', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'oportunidade_id', o.id, 'nome', p.nome, 'curso', c.nome || ' · ' || c.turno, 'etapa', o.etapa,
        'programa', g.nome, 'tipo', g.tipo, 'percentual', s.percentual, 'status', s.status, 'etapa_externa', s.etapa_externa, 'origem', s.origem,
        'declaracao', s.declaracao, 'solicitado_em', s.solicitado_em, 'solicitado_por', privado.nome_usuario(s.solicitado_por),
        'decidido_por', privado.nome_usuario(s.decidido_por), 'decidido_em', s.decidido_em, 'justificativa', s.justificativa,
        'decide_proprio', s.solicitado_por = (select auth.uid())) order by (s.status = 'solicitada') desc, s.id desc), '[]'::jsonb)
      from public.solicitacoes_bolsa s join public.oportunidades o on o.id = s.oportunidade_id join public.pessoas p on p.id = o.pessoa_id
      join public.cursos c on c.id = o.curso_id join public.programas_bolsa g on g.id = s.programa_id
      where s.ies_id = p_ies and (p_op is null or s.oportunidade_id = p_op) and privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, papeis)));
end $$;

-- ---------------------------------------------------------------- portal do candidato
create or replace function public.rpc_publico_portal_bolsas(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.pessoas;
begin
  p := privado.portal_pessoa(p_token);
  return (select coalesce(jsonb_agg(jsonb_build_object('oportunidade_id', o.id, 'curso', c.nome || ' · ' || c.turno,
      'programas', (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'nome', g.nome, 'tipo', g.tipo, 'percentual_max', g.percentual_max,
                      'requisitos', g.requisitos, 'documentos', g.documentos, 'validade_ate', g.validade_ate) order by g.nome), '[]'::jsonb)
                    from public.programas_bolsa g where g.ies_id = o.ies_id and g.ativo and g.visivel_portal
                      and (g.validade_ate is null or g.validade_ate >= current_date) and (g.cursos is null or o.curso_id = any (g.cursos))),
      'solicitacoes', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'programa', g.nome, 'percentual', s.percentual, 'status', s.status,
                      'etapa_externa', s.etapa_externa, 'justificativa', case when s.status <> 'solicitada' then s.justificativa end) order by s.id desc), '[]'::jsonb)
                    from public.solicitacoes_bolsa s join public.programas_bolsa g on g.id = s.programa_id where s.oportunidade_id = o.id)
    ) order by o.id), '[]'::jsonb)
    from public.oportunidades o join public.cursos c on c.id = o.curso_id where o.pessoa_id = p.id and o.etapa not in ('perdido','cancelado'));
end $$;

create or replace function public.rpc_publico_solicitar_bolsa(p_token text, p_op bigint, p_programa bigint, p_percentual numeric, p_declaro boolean, p_declaracao text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.pessoas; o public.oportunidades; g public.programas_bolsa; v_id bigint;
begin
  p := privado.portal_pessoa(p_token);
  select * into o from public.oportunidades where id = p_op and pessoa_id = p.id for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  select * into g from public.programas_bolsa where id = p_programa and visivel_portal;
  if not found then perform privado.erro_http(404, 'P0002', 'Programa não encontrado'); end if;
  if not coalesce(p_declaro, false) then raise exception 'Confirme que as informações são verdadeiras' using errcode = '22023'; end if;
  if (select count(*) from public.solicitacoes_bolsa where oportunidade_id = o.id and origem = 'portal' and solicitado_em > now() - interval '1 day') >= 5 then
    perform privado.erro_http(429, '54000', 'Muitas solicitações hoje. Tente amanhã.'); end if;
  perform privado.validar_bolsa(o, g, p_percentual);
  insert into public.solicitacoes_bolsa(ies_id, oportunidade_id, programa_id, percentual, origem, declaracao, etapa_externa)
  values (o.ies_id, o.id, g.id, p_percentual, 'portal', nullif(left(trim(coalesce(p_declaracao, '')), 1000), ''),
          case when g.tipo in ('prouni','fies','financiamento_privado') then 'inscricao' end)
  returning id into v_id;
  perform privado.auditar(o.ies_id, 'bolsa.solicitar', 'oportunidade', o.id::text, jsonb_build_object('programa', g.nome, 'percentual', p_percentual, 'origem', 'portal'));
  return jsonb_build_object('id', v_id, 'status', 'solicitada', 'mensagem', 'Solicitação registrada. A instituição analisará e responderá por aqui.');
exception when unique_violation then raise exception 'Você já tem uma solicitação deste programa' using errcode = '22023';
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.rpc_salvar_programa_bolsa(bigint, jsonb, bigint), public.rpc_solicitar_bolsa(bigint, bigint, numeric, text),
  public.rpc_decidir_bolsa(bigint, text, text, numeric), public.rpc_etapa_bolsa(bigint, text), public.rpc_cancelar_bolsa(bigint, text),
  public.rpc_bolsas(bigint, bigint) to authenticated;
select privado.conceder_publico();

-- ===================== supabase/migrations/20261126000024_rematricula.sql
-- Matrícula 360° — migração 24 (Onda A, L14): rematrícula ativa.
--   * Campanha por período ("2027.2"): janela, coortes de ingresso atendidas, termo de rematrícula versionado pela campanha
--     (cláusulas em destaque com **), meta percentual.
--   * Ao abrir, o sistema fotografa os elegíveis: ingressantes efetivos cujo último vínculo registrado não é evadido nem transferido.
--     Pode ser repetido para incluir novos elegíveis (idempotente).
--   * Bloqueio com categoria (financeiro, documental, acadêmico, outro) e motivo, por quem trata; o aluno vê só a categoria e a
--     orientação de procurar a secretaria.
--   * Aceite pelo portal: CPF conferido com o do aceite da matrícula (quando houver), representante legal se o aluno ainda for
--     menor, declarações, evidência com SHA-256. Recusa com motivo pelo portal. Registro presencial pela secretaria.
--   * A rematrícula aceita NÃO grava vínculo acadêmico: o vínculo continua sendo um fato registrado pela secretaria ou importado.
--   * Indicadores: elegíveis, aceitas, recusadas, bloqueadas, pendentes, taxa (N/D sem elegíveis) e meta.
-- Idempotente.

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('rematricula.ver',    'Relacionamento Estudantil', 'Ver campanhas e situação da rematrícula',            array['gestor','secretaria','financeiro','coordenador','reitoria'], 'curso', 'rpc_rematricula'),
  ('rematricula.gerir',  'Relacionamento Estudantil', 'Criar, abrir e encerrar campanhas de rematrícula',   array['gestor','secretaria'], 'ies', 'rpc_salvar_campanha_rematricula'),
  ('rematricula.tratar', 'Relacionamento Estudantil', 'Bloquear, desbloquear e registrar rematrícula presencial', array['gestor','secretaria','financeiro'], 'curso', 'rpc_tratar_rematricula')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

create table if not exists public.campanhas_rematricula (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  periodo text not null check (periodo ~ '^\d{4}\.[12]$'),
  abre_em date not null,
  fecha_em date not null,
  coortes text[],
  termo text not null check (length(termo) between 100 and 10000),
  meta_pct numeric(5,2) check (meta_pct is null or (meta_pct > 0 and meta_pct <= 100)),
  status text not null default 'rascunho' check (status in ('rascunho','aberta','encerrada')),
  criado_por uuid references public.usuarios(id),
  criado_em timestamptz not null default now(),
  unique (ies_id, periodo),
  check (fecha_em >= abre_em)
);
create table if not exists public.rematriculas (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  campanha_id bigint not null references public.campanhas_rematricula(id),
  oportunidade_id bigint not null references public.oportunidades(id),
  status text not null default 'pendente' check (status in ('pendente','aceita','recusada','bloqueada')),
  bloqueio_categoria text check (bloqueio_categoria in ('financeiro','documental','academico','outro')),
  motivo text check (length(motivo) <= 500),
  origem text check (origem in ('portal','secretaria')),
  evidencia jsonb,
  evidencia_hash text,
  respondido_em timestamptz,
  tratado_por uuid references public.usuarios(id),
  atualizado_em timestamptz not null default now(),
  unique (campanha_id, oportunidade_id)
);
create index if not exists campanhas_remat_criado on public.campanhas_rematricula(criado_por);
create index if not exists remat_ies on public.rematriculas(ies_id);
create index if not exists remat_op on public.rematriculas(oportunidade_id);
create index if not exists remat_tratado on public.rematriculas(tratado_por);
alter table public.campanhas_rematricula enable row level security;
alter table public.rematriculas enable row level security;
revoke all on public.campanhas_rematricula, public.rematriculas from anon, authenticated;

-- ---------------------------------------------------------------- campanhas
create or replace function public.rpc_salvar_campanha_rematricula(p_ies bigint, p_dados jsonb, p_id bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare d jsonb := coalesce(p_dados, '{}'::jsonb); v_id bigint; c public.campanhas_rematricula; t text := trim(coalesce(p_dados->>'termo', ''));
begin
  perform privado.autorizar(p_ies, 'rematricula.gerir');
  if t <> '' and ((length(t) - length(replace(t, '**', ''))) / 2) % 2 <> 0 then
    raise exception 'Marcação de destaque incompleta: cada ** aberto precisa ser fechado' using errcode = '22023'; end if;
  if p_id is null then
    insert into public.campanhas_rematricula(ies_id, periodo, abre_em, fecha_em, coortes, termo, meta_pct, criado_por)
    values (p_ies, d->>'periodo', (d->>'abre_em')::date, (d->>'fecha_em')::date,
            (select array_agg(x) from jsonb_array_elements_text(case when jsonb_typeof(d->'coortes') = 'array' then d->'coortes' else '[]'::jsonb end) x),
            t, nullif(d->>'meta_pct', '')::numeric, (select auth.uid()))
    returning id into v_id;
  else
    select * into c from public.campanhas_rematricula where id = p_id and ies_id = p_ies for update;
    if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
    if c.status <> 'rascunho' and (d ? 'termo' or d ? 'periodo' or d ? 'coortes') then
      raise exception 'Campanha aberta ou encerrada: termo, período e coortes não mudam (aceites já dados valem pelo texto aceito)' using errcode = '22023'; end if;
    update public.campanhas_rematricula set
      periodo = coalesce(d->>'periodo', periodo), abre_em = coalesce((d->>'abre_em')::date, abre_em), fecha_em = coalesce((d->>'fecha_em')::date, fecha_em),
      termo = case when t <> '' then t else termo end, meta_pct = case when d ? 'meta_pct' then nullif(d->>'meta_pct', '')::numeric else meta_pct end,
      coortes = case when d ? 'coortes' then (select array_agg(x) from jsonb_array_elements_text(case when jsonb_typeof(d->'coortes') = 'array' then d->'coortes' else '[]'::jsonb end) x) else coortes end
    where id = p_id returning id into v_id;
  end if;
  perform privado.auditar(p_ies, 'rematricula.campanha', 'campanha_rematricula', v_id::text, jsonb_build_object('periodo', coalesce(d->>'periodo', c.periodo), 'novo', p_id is null));
  return jsonb_build_object('id', v_id);
exception when unique_violation then raise exception 'Já existe campanha para este período' using errcode = '22023';
end $$;

-- Elegíveis: ingressante efetivo, coorte atendida, último vínculo registrado não é evadido nem transferido.
create or replace function privado.elegiveis_rematricula(c public.campanhas_rematricula) returns setof bigint
language sql stable security definer set search_path = '' as $$
  select o.id from public.oportunidades o
   where o.ies_id = c.ies_id and o.etapa = 'confirmado' and (c.coortes is null or o.coorte = any (c.coortes))
     and coalesce((select v.situacao from public.vinculos v where v.oportunidade_id = o.id order by v.data_referencia desc, v.id desc limit 1), 'ativo')
         not in ('evadido','transferido')
$$;
revoke execute on function privado.elegiveis_rematricula(public.campanhas_rematricula) from public, anon, authenticated;

create or replace function public.rpc_status_campanha_rematricula(p_id bigint, p_status text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c public.campanhas_rematricula; n int := 0;
begin
  perform privado.exigir_usuario();
  select * into c from public.campanhas_rematricula where id = p_id for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(c.ies_id, 'rematricula.gerir');
  if p_status = 'aberta' then
    if c.status = 'encerrada' then raise exception 'Campanha encerrada não reabre' using errcode = '22023'; end if;
    insert into public.rematriculas(ies_id, campanha_id, oportunidade_id)
    select c.ies_id, c.id, e from privado.elegiveis_rematricula(c) e
    on conflict (campanha_id, oportunidade_id) do nothing;
    get diagnostics n = row_count;
  elsif p_status = 'encerrada' then
    if c.status <> 'aberta' then raise exception 'Só campanha aberta pode ser encerrada' using errcode = '22023'; end if;
  else raise exception 'Status inválido' using errcode = '22023';
  end if;
  update public.campanhas_rematricula set status = p_status where id = c.id;
  perform privado.auditar(c.ies_id, 'rematricula.status', 'campanha_rematricula', c.id::text, jsonb_build_object('periodo', c.periodo, 'status', p_status, 'novos_elegiveis', n));
  return jsonb_build_object('id', c.id, 'status', p_status, 'novos_elegiveis', n);
end $$;

-- ---------------------------------------------------------------- tratamento pela equipe
create or replace function public.rpc_tratar_rematricula(p_id bigint, p_acao text, p_motivo text default null, p_categoria text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.rematriculas; c public.campanhas_rematricula; novo text;
begin
  perform privado.exigir_usuario();
  select * into r from public.rematriculas where id = p_id for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.op_operacao(r.oportunidade_id, 'rematricula.tratar');
  select * into c from public.campanhas_rematricula where id = r.campanha_id;
  if c.status <> 'aberta' then raise exception 'Campanha não está aberta' using errcode = '22023'; end if;
  if p_acao = 'bloquear' then
    if r.status <> 'pendente' then raise exception 'Só rematrícula pendente pode ser bloqueada' using errcode = '22023'; end if;
    if p_categoria not in ('financeiro','documental','academico','outro') or length(coalesce(trim(p_motivo), '')) < 5 then
      raise exception 'Informe a categoria e o motivo do bloqueio' using errcode = '22023'; end if;
    novo := 'bloqueada';
  elsif p_acao = 'desbloquear' then
    if r.status <> 'bloqueada' then raise exception 'Não está bloqueada' using errcode = '22023'; end if;
    novo := 'pendente';
  elsif p_acao in ('aceita','recusada') then
    if r.status not in ('pendente') then raise exception 'Só rematrícula pendente pode ser registrada' using errcode = '22023'; end if;
    if length(coalesce(trim(p_motivo), '')) < 5 then raise exception 'Descreva o registro presencial (documento, atendimento)' using errcode = '22023'; end if;
    novo := p_acao;
  else raise exception 'Ação inválida' using errcode = '22023';
  end if;
  update public.rematriculas set status = novo, tratado_por = (select auth.uid()), atualizado_em = now(),
    bloqueio_categoria = case when novo = 'bloqueada' then p_categoria end,
    motivo = case when novo = 'pendente' then null else trim(p_motivo) end,
    origem = case when novo in ('aceita','recusada') then 'secretaria' else origem end,
    respondido_em = case when novo in ('aceita','recusada') then now() else respondido_em end
  where id = r.id;
  perform privado.auditar(r.ies_id, 'rematricula.tratar', 'oportunidade', r.oportunidade_id::text,
    jsonb_build_object('periodo', c.periodo, 'acao', p_acao, 'categoria', p_categoria));
  return jsonb_build_object('id', r.id, 'status', novo);
end $$;

-- ---------------------------------------------------------------- leitura e indicadores
create or replace function public.rpc_rematricula(p_ies bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare papeis text[] := (select papeis from public.matriz_permissoes where operacao = 'rematricula.ver');
begin
  perform privado.autorizar(p_ies, 'rematricula.ver');
  return jsonb_build_object('pode_gerir', privado.pode(p_ies, 'rematricula.gerir'), 'pode_tratar', privado.pode(p_ies, 'rematricula.tratar'),
    'aviso', 'A rematrícula aceita é o compromisso do aluno; o vínculo acadêmico continua sendo registrado pela secretaria ou importado do sistema acadêmico.',
    'campanhas', (select coalesce(jsonb_agg(x order by x->>'periodo' desc), '[]'::jsonb) from (
      select jsonb_build_object('id', c.id, 'periodo', c.periodo, 'abre_em', c.abre_em, 'fecha_em', c.fecha_em, 'coortes', c.coortes, 'termo', c.termo,
        'meta_pct', c.meta_pct, 'status', c.status,
        'totais', (select jsonb_build_object('elegiveis', count(*), 'aceitas', count(*) filter (where r.status = 'aceita'),
                     'recusadas', count(*) filter (where r.status = 'recusada'), 'bloqueadas', count(*) filter (where r.status = 'bloqueada'),
                     'pendentes', count(*) filter (where r.status = 'pendente'),
                     'taxa_pct', case when count(*) = 0 then null else round(100.0 * count(*) filter (where r.status = 'aceita') / count(*), 1) end)
                   from public.rematriculas r join public.oportunidades o on o.id = r.oportunidade_id
                   where r.campanha_id = c.id and privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, papeis)),
        'alunos', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'oportunidade_id', o.id, 'nome', p.nome, 'curso', k.nome || ' · ' || k.turno, 'coorte', o.coorte,
                     'status', r.status, 'categoria', r.bloqueio_categoria, 'motivo', r.motivo, 'origem', r.origem, 'respondido_em', r.respondido_em,
                     'tratado_por', privado.nome_usuario(r.tratado_por), 'evidencia_hash', r.evidencia_hash) order by r.status, p.nome), '[]'::jsonb)
                   from public.rematriculas r join public.oportunidades o on o.id = r.oportunidade_id join public.pessoas p on p.id = o.pessoa_id
                   join public.cursos k on k.id = o.curso_id
                   where r.campanha_id = c.id and privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, papeis))) x
      from public.campanhas_rematricula c where c.ies_id = p_ies) z));
end $$;

-- ---------------------------------------------------------------- portal do aluno
create or replace function public.rpc_publico_portal_rematricula(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.pessoas;
begin
  p := privado.portal_pessoa(p_token);
  return (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'periodo', c.periodo, 'curso', k.nome || ' · ' || k.turno, 'abre_em', c.abre_em, 'fecha_em', c.fecha_em,
      'aberta_agora', c.status = 'aberta' and current_date between c.abre_em and c.fecha_em, 'termo', c.termo, 'status', r.status,
      'bloqueio', case when r.status = 'bloqueada' then r.bloqueio_categoria end, 'respondido_em', r.respondido_em, 'evidencia_hash', r.evidencia_hash,
      'exige_representante', coalesce((select a.nascimento_candidato > current_date - interval '18 years' from public.aceites_matricula a where a.oportunidade_id = o.id), false),
      'cpf_no_aceite', exists (select 1 from public.aceites_matricula a where a.oportunidade_id = o.id and a.cpf_candidato is not null)) order by c.periodo desc), '[]'::jsonb)
    from public.rematriculas r join public.campanhas_rematricula c on c.id = r.campanha_id join public.oportunidades o on o.id = r.oportunidade_id
    join public.cursos k on k.id = o.curso_id
    where o.pessoa_id = p.id and c.status in ('aberta','encerrada'));
end $$;

create or replace function public.rpc_publico_responder_rematricula(p_token text, p_id bigint, p_dados jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.pessoas; r public.rematriculas; c public.campanhas_rematricula; o public.oportunidades; a public.aceites_matricula;
  cpf text := regexp_replace(coalesce(p_dados->>'cpf', ''), '\D', '', 'g'); resp text := p_dados->>'resposta';
  menor boolean := false; r_cpf text; ev jsonb; h text; t_hash text;
begin
  p := privado.portal_pessoa(p_token);
  select * into r from public.rematriculas where id = p_id for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  select * into o from public.oportunidades where id = r.oportunidade_id;
  if o.pessoa_id <> p.id then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  select * into c from public.campanhas_rematricula where id = r.campanha_id;
  if c.status <> 'aberta' or current_date not between c.abre_em and c.fecha_em then raise exception 'Rematrícula fora do prazo: fale com a secretaria' using errcode = '22023'; end if;
  if r.status = 'bloqueada' then raise exception 'Há uma pendência: procure a secretaria' using errcode = '22023'; end if;
  if r.status <> 'pendente' then raise exception 'Rematrícula já respondida' using errcode = '22023'; end if;
  if resp not in ('aceita','recusada') then raise exception 'Resposta inválida' using errcode = '22023'; end if;
  if privado.nome_norm(p_dados->>'nome') <> privado.nome_norm(p.nome) then raise exception 'Digite seu nome completo como no cadastro' using errcode = '22023'; end if;
  if not privado.cpf_valido(cpf) then raise exception 'CPF inválido' using errcode = '22023'; end if;
  select * into a from public.aceites_matricula where oportunidade_id = o.id;
  if found and a.cpf_candidato is not null and a.cpf_candidato <> cpf then raise exception 'CPF diferente do informado na matrícula' using errcode = '22023'; end if;
  if resp = 'recusada' then
    if length(coalesce(trim(p_dados->>'motivo'), '')) < 3 then raise exception 'Conte o motivo; isso ajuda a instituição a melhorar' using errcode = '22023'; end if;
  else
    if not (coalesce((p_dados->>'li_termo')::boolean, false) and coalesce((p_dados->>'concordo')::boolean, false)) then
      raise exception 'Marque as duas declarações' using errcode = '22023'; end if;
    menor := coalesce(a.nascimento_candidato > current_date - interval '18 years', false);
    if menor then
      r_cpf := regexp_replace(coalesce(p_dados->'responsavel'->>'cpf', ''), '\D', '', 'g');
      if a.responsavel_cpf is null or r_cpf <> a.responsavel_cpf or not coalesce((p_dados->'responsavel'->>'declaro')::boolean, false) then
        raise exception 'Aluno menor de 18 anos: o representante legal da matrícula precisa confirmar com o CPF dele' using errcode = '22023'; end if;
    end if;
  end if;
  t_hash := encode(sha256(convert_to(c.termo, 'UTF8')), 'hex');
  ev := jsonb_build_object('procedimento', 'rematricula-v1', 'periodo', c.periodo, 'oportunidade_id', o.id, 'resposta', resp,
    'aluno', jsonb_build_object('nome', p.nome, 'cpf', cpf, 'cpf_conferido_com_matricula', a.cpf_candidato is not null),
    'representante_legal', case when menor then jsonb_build_object('nome', a.responsavel_nome, 'cpf', a.responsavel_cpf) end,
    'termo_sha256', case when resp = 'aceita' then t_hash end,
    'motivo', case when resp = 'recusada' then left(trim(p_dados->>'motivo'), 500) end,
    'origem_hash', privado.origem_hash(), 'respondido_em', privado.utc(now()));
  h := encode(sha256(convert_to(ev::text, 'UTF8')), 'hex');
  update public.rematriculas set status = resp, origem = 'portal', evidencia = ev, evidencia_hash = h, respondido_em = now(), atualizado_em = now(),
    motivo = case when resp = 'recusada' then left(trim(p_dados->>'motivo'), 500) end where id = r.id;
  perform privado.auditar(r.ies_id, 'rematricula.resposta', 'oportunidade', o.id::text, jsonb_build_object('periodo', c.periodo, 'resposta', resp, 'evidencia_sha256', h));
  return jsonb_build_object('status', resp, 'evidencia_hash', h,
    'mensagem', case when resp = 'aceita' then 'Rematrícula confirmada. A secretaria concluirá o registro acadêmico.' else 'Resposta registrada. A instituição pode entrar em contato para ajudar.' end);
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.rpc_salvar_campanha_rematricula(bigint, jsonb, bigint), public.rpc_status_campanha_rematricula(bigint, text),
  public.rpc_tratar_rematricula(bigint, text, text, text), public.rpc_rematricula(bigint) to authenticated;
select privado.conceder_publico();

-- ===================== supabase/migrations/20261126000025_sucesso_aluno.sql
-- Matrícula 360° — migração 25 (Onda A, L15): sucesso do aluno — casos, trilhas de intervenção e agendamento.
--   * Trilha por motivo (frequência, desempenho, financeiro, adaptação, pessoal, rematrícula recusada, outro): passos, prazo e
--     papel responsável. Trilhas padrão criadas por IES; o gestor edita.
--   * Caso do aluno (ingressante efetivo): aberto pela equipe ou automaticamente quando o aluno recusa a rematrícula pelo portal.
--     Roteamento para quem tem o papel da trilha no curso, com menos casos abertos; sem ninguém, fica na fila sem dono.
--   * Atendimento: nota, passo concluído, agendamento, encaminhamento, resolução (texto obrigatório) e cancelamento (gestor).
--   * Indicadores: abertos, vencidos, sem dono, tempo médio de resolução, por motivo; agenda dos próximos atendimentos.
--   * LGPD: não registrar dado sensível (saúde, religião, etc.; art. 11). Nada é enviado ao aluno.
-- Idempotente.

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('caso.ver',     'Relacionamento Estudantil', 'Ver casos de sucesso do aluno e a agenda de atendimentos', array['gestor','secretaria','coordenador','financeiro','reitoria'], 'curso', 'rpc_casos'),
  ('caso.atender', 'Relacionamento Estudantil', 'Abrir e atender casos do aluno',                           array['gestor','secretaria','coordenador','financeiro'], 'curso', 'rpc_atender_caso'),
  ('caso.trilhas', 'Relacionamento Estudantil', 'Editar trilhas de intervenção',                            array['gestor'], 'ies', 'rpc_salvar_trilha')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

create table if not exists public.trilhas_intervencao (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  motivo text not null check (motivo in ('frequencia','desempenho','financeiro','adaptacao','pessoal','rematricula_recusada','outro')),
  nome text not null check (length(nome) between 3 and 100),
  passos text[] not null check (cardinality(passos) between 1 and 10),
  prazo_horas int not null check (prazo_horas between 4 and 720),
  papel_responsavel text not null check (papel_responsavel in ('gestor','secretaria','coordenador','financeiro')),
  unique (ies_id, motivo)
);
create table if not exists public.casos (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  oportunidade_id bigint not null references public.oportunidades(id),
  motivo text not null,
  origem text not null check (origem in ('equipe','rematricula')),
  prioridade text not null default 'media' check (prioridade in ('baixa','media','alta')),
  status text not null default 'aberto' check (status in ('aberto','em_atendimento','resolvido','cancelado')),
  descricao text not null check (length(descricao) between 5 and 1000),
  trilha_id bigint references public.trilhas_intervencao(id),
  passos_concluidos int not null default 0,
  responsavel_id uuid references public.usuarios(id),
  prazo timestamptz not null,
  resolucao text,
  aberto_por uuid references public.usuarios(id),
  aberto_em timestamptz not null default now(),
  encerrado_em timestamptz
);
create unique index if not exists caso_aberto_unico on public.casos(oportunidade_id, motivo) where status in ('aberto','em_atendimento');
create table if not exists public.casos_eventos (
  id bigint generated always as identity primary key,
  caso_id bigint not null references public.casos(id),
  tipo text not null check (tipo in ('abertura','nota','passo','agendamento','encaminhamento','resolucao','cancelamento')),
  texto text not null check (length(texto) between 2 and 1000),
  agendado_para timestamptz,
  por uuid references public.usuarios(id),
  em timestamptz not null default now()
);
create index if not exists casos_ies on public.casos(ies_id);
create index if not exists casos_op on public.casos(oportunidade_id);
create index if not exists casos_resp on public.casos(responsavel_id);
create index if not exists casos_trilha on public.casos(trilha_id);
create index if not exists casos_aberto_por on public.casos(aberto_por);
create index if not exists casos_ev_caso on public.casos_eventos(caso_id);
create index if not exists casos_ev_por on public.casos_eventos(por);
alter table public.trilhas_intervencao enable row level security;
alter table public.casos enable row level security;
alter table public.casos_eventos enable row level security;
revoke all on public.trilhas_intervencao, public.casos, public.casos_eventos from anon, authenticated;

-- Trilhas padrão (adaptáveis pelo gestor).
create or replace function privado.trilhas_padrao(p_ies bigint) returns void
language sql security definer set search_path = '' as $$
  insert into public.trilhas_intervencao(ies_id, motivo, nome, passos, prazo_horas, papel_responsavel) values
    (p_ies, 'frequencia', 'Faltas recorrentes', array['Contato com o aluno para entender as ausências','Conversa com a coordenação do curso','Plano de recuperação de frequência combinado com o aluno'], 72, 'coordenador'),
    (p_ies, 'desempenho', 'Desempenho acadêmico', array['Conversa com o aluno sobre as disciplinas em risco','Encaminhamento a monitoria ou nivelamento','Acompanhamento após a próxima avaliação'], 120, 'coordenador'),
    (p_ies, 'financeiro', 'Dificuldade financeira', array['Atendimento para entender a situação','Apresentar opções de negociação, bolsas e financiamento vigentes','Registrar o acordo ou o encaminhamento'], 72, 'financeiro'),
    (p_ies, 'adaptacao', 'Adaptação à vida acadêmica', array['Acolhimento e escuta','Apresentar serviços de apoio da instituição','Retorno em duas semanas'], 120, 'secretaria'),
    (p_ies, 'pessoal', 'Questão pessoal', array['Acolhimento (sem registrar dado sensível)','Encaminhamento ao serviço adequado da instituição'], 48, 'secretaria'),
    (p_ies, 'rematricula_recusada', 'Recusa de rematrícula', array['Contato para entender o motivo da recusa','Apresentar alternativas (trancamento, bolsa, mudança de turno)','Registrar a decisão final do aluno'], 48, 'secretaria'),
    (p_ies, 'outro', 'Outro motivo', array['Entender a demanda','Encaminhar e registrar o desfecho'], 96, 'secretaria')
  on conflict (ies_id, motivo) do nothing;
$$;
revoke execute on function privado.trilhas_padrao(bigint) from public, anon, authenticated;
select privado.trilhas_padrao(id) from public.ies;

create or replace function privado.ies_trilhas() returns trigger language plpgsql security definer set search_path = '' as $$
begin perform privado.trilhas_padrao(new.id); return new; end $$;
drop trigger if exists ies_trilhas on public.ies;
create trigger ies_trilhas after insert on public.ies for each row execute function privado.ies_trilhas();

-- Quem atende: tem o papel da trilha com escopo sobre o curso, menos casos abertos; empate pelo id.
create or replace function privado.rotear_caso(p_ies bigint, p_curso bigint, p_papel text) returns uuid
language sql stable security definer set search_path = '' as $$
  select e.usuario_id from public.escopos e join public.usuarios u on u.id = e.usuario_id
   where e.ies_id = p_ies and e.papel = p_papel and e.revogado_em is null and u.revogado_em is null
     and privado.escopo_cobre(e.abrangencia, e.campus_id, e.curso_id, p_curso)
   group by e.usuario_id
   order by (select count(*) from public.casos c where c.responsavel_id = e.usuario_id and c.status in ('aberto','em_atendimento')), e.usuario_id
   limit 1
$$;

create or replace function privado.abrir_caso(o public.oportunidades, p_motivo text, p_origem text, p_prioridade text, p_descricao text, p_por uuid) returns bigint
language plpgsql security definer set search_path = '' as $$
declare t public.trilhas_intervencao; v_id bigint; resp uuid;
begin
  select * into t from public.trilhas_intervencao where ies_id = o.ies_id and motivo = p_motivo;
  if not found then raise exception 'Motivo inválido' using errcode = '22023'; end if;
  resp := privado.rotear_caso(o.ies_id, o.curso_id, t.papel_responsavel);
  insert into public.casos(ies_id, oportunidade_id, motivo, origem, prioridade, descricao, trilha_id, responsavel_id, prazo, aberto_por)
  values (o.ies_id, o.id, p_motivo, p_origem, p_prioridade, p_descricao, t.id, resp,
          now() + make_interval(hours => case p_prioridade when 'alta' then greatest(4, t.prazo_horas / 2) else t.prazo_horas end), p_por)
  returning id into v_id;
  insert into public.casos_eventos(caso_id, tipo, texto, por) values (v_id, 'abertura', p_descricao, p_por);
  perform privado.auditar(o.ies_id, 'caso.abrir', 'oportunidade', o.id::text, jsonb_build_object('caso', v_id, 'motivo', p_motivo, 'origem', p_origem, 'roteado', resp is not null));
  return v_id;
end $$;
revoke execute on function privado.rotear_caso(bigint, bigint, text), privado.abrir_caso(public.oportunidades, text, text, text, text, uuid), privado.ies_trilhas() from public, anon, authenticated;

-- Trilha automática: recusa de rematrícula pelo portal abre caso (se já não houver um aberto).
create or replace function privado.caso_recusa_rematricula() returns trigger language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades;
begin
  if new.status = 'recusada' and new.origem = 'portal' and old.status <> 'recusada' then
    select * into o from public.oportunidades where id = new.oportunidade_id;
    if not exists (select 1 from public.casos where oportunidade_id = o.id and motivo = 'rematricula_recusada' and status in ('aberto','em_atendimento')) then
      perform privado.abrir_caso(o, 'rematricula_recusada', 'rematricula', 'alta', 'Recusou a rematrícula pelo portal. Motivo informado: ' || coalesce(new.motivo, 'não informado'), null);
    end if;
  end if;
  return new;
end $$;
revoke execute on function privado.caso_recusa_rematricula() from public, anon, authenticated;
drop trigger if exists rematricula_caso on public.rematriculas;
create trigger rematricula_caso after update of status on public.rematriculas for each row execute function privado.caso_recusa_rematricula();

-- ---------------------------------------------------------------- operações
create or replace function public.rpc_abrir_caso(p_op bigint, p_motivo text, p_descricao text, p_prioridade text default 'media')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; v_id bigint;
begin
  o := privado.op_operacao(p_op, 'caso.atender');
  if o.etapa <> 'confirmado' then raise exception 'Casos são para alunos (ingresso efetivo)' using errcode = '22023'; end if;
  if p_prioridade not in ('baixa','media','alta') then raise exception 'Prioridade inválida' using errcode = '22023'; end if;
  if length(coalesce(trim(p_descricao), '')) < 5 then raise exception 'Descreva a situação' using errcode = '22023'; end if;
  v_id := privado.abrir_caso(o, p_motivo, 'equipe', p_prioridade, trim(p_descricao), (select auth.uid()));
  return jsonb_build_object('id', v_id, 'responsavel', privado.nome_usuario((select responsavel_id from public.casos where id = v_id)));
exception when unique_violation then raise exception 'Já há caso aberto deste motivo para o aluno' using errcode = '22023';
end $$;

create or replace function public.rpc_atender_caso(p_id bigint, p_acao text, p_texto text default null, p_agendado_para timestamptz default null, p_responsavel uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c public.casos; o public.oportunidades; t public.trilhas_intervencao; eu uuid := (select auth.uid()); txt text := trim(coalesce(p_texto, ''));
  gestor boolean; novo_status text;
begin
  perform privado.exigir_usuario();
  select * into c from public.casos where id = p_id for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  o := privado.op_operacao(c.oportunidade_id, 'caso.atender');
  if c.status not in ('aberto','em_atendimento') then raise exception 'Caso encerrado' using errcode = '22023'; end if;
  gestor := privado.tem_acesso(o.ies_id, o.curso_id, array['gestor']);
  if p_acao <> 'assumir' and c.responsavel_id is distinct from eu and not gestor then
    raise exception 'Só o responsável pelo caso ou a gestão atende; assuma o caso antes' using errcode = '42501'; end if;
  select * into t from public.trilhas_intervencao where id = c.trilha_id;
  novo_status := 'em_atendimento';
  if p_acao = 'assumir' then
    if c.responsavel_id = eu then raise exception 'O caso já é seu' using errcode = '22023'; end if;
    if c.responsavel_id is not null and not gestor then raise exception 'Caso com responsável: peça o encaminhamento' using errcode = '42501'; end if;
    update public.casos set responsavel_id = eu where id = c.id;
    txt := 'Assumiu o caso';
    insert into public.casos_eventos(caso_id, tipo, texto, por) values (c.id, 'encaminhamento', txt, eu);
  elsif p_acao = 'nota' then
    if length(txt) < 2 then raise exception 'Escreva a nota' using errcode = '22023'; end if;
    insert into public.casos_eventos(caso_id, tipo, texto, por) values (c.id, 'nota', txt, eu);
  elsif p_acao = 'passo' then
    if c.passos_concluidos >= cardinality(t.passos) then raise exception 'Todos os passos da trilha já foram concluídos' using errcode = '22023'; end if;
    if length(txt) < 5 then raise exception 'Registre o que foi feito neste passo' using errcode = '22023'; end if;
    update public.casos set passos_concluidos = passos_concluidos + 1 where id = c.id;
    insert into public.casos_eventos(caso_id, tipo, texto, por) values (c.id, 'passo', t.passos[c.passos_concluidos + 1] || ': ' || txt, eu);
  elsif p_acao = 'agendar' then
    if p_agendado_para is null or p_agendado_para < now() then raise exception 'Informe data e hora futuras' using errcode = '22023'; end if;
    insert into public.casos_eventos(caso_id, tipo, texto, agendado_para, por) values (c.id, 'agendamento', coalesce(nullif(txt, ''), 'Atendimento agendado'), p_agendado_para, eu);
  elsif p_acao = 'encaminhar' then
    if p_responsavel is null or not exists (select 1 from public.escopos e where e.usuario_id = p_responsavel and e.ies_id = o.ies_id and e.revogado_em is null
        and e.papel in (select unnest(mp.papeis) from public.matriz_permissoes mp where mp.operacao = 'caso.atender') and privado.escopo_cobre(e.abrangencia, e.campus_id, e.curso_id, o.curso_id)) then
      raise exception 'Destino sem permissão para atender casos deste curso' using errcode = '22023'; end if;
    if length(txt) < 5 then raise exception 'Explique o encaminhamento' using errcode = '22023'; end if;
    update public.casos set responsavel_id = p_responsavel where id = c.id;
    insert into public.casos_eventos(caso_id, tipo, texto, por) values (c.id, 'encaminhamento', 'Para ' || privado.nome_usuario(p_responsavel) || ': ' || txt, eu);
  elsif p_acao = 'resolver' then
    if length(txt) < 10 then raise exception 'Descreva o desfecho (mínimo 10 caracteres)' using errcode = '22023'; end if;
    novo_status := 'resolvido';
    update public.casos set resolucao = txt, encerrado_em = now() where id = c.id;
    insert into public.casos_eventos(caso_id, tipo, texto, por) values (c.id, 'resolucao', txt, eu);
  elsif p_acao = 'cancelar' then
    if not gestor then raise exception 'Só a gestão cancela caso' using errcode = '42501'; end if;
    if length(txt) < 5 then raise exception 'Motivo do cancelamento obrigatório' using errcode = '22023'; end if;
    novo_status := 'cancelado';
    update public.casos set resolucao = txt, encerrado_em = now() where id = c.id;
    insert into public.casos_eventos(caso_id, tipo, texto, por) values (c.id, 'cancelamento', txt, eu);
  else raise exception 'Ação inválida' using errcode = '22023';
  end if;
  update public.casos set status = novo_status where id = c.id;
  perform privado.auditar(c.ies_id, 'caso.atender', 'oportunidade', c.oportunidade_id::text, jsonb_build_object('caso', c.id, 'acao', p_acao));
  return jsonb_build_object('id', c.id, 'status', novo_status);
end $$;

create or replace function public.rpc_salvar_trilha(p_ies bigint, p_motivo text, p_dados jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare d jsonb := coalesce(p_dados, '{}'::jsonb); v_id bigint;
begin
  perform privado.autorizar(p_ies, 'caso.trilhas');
  update public.trilhas_intervencao set
    nome = coalesce(trim(d->>'nome'), nome),
    passos = case when jsonb_typeof(d->'passos') = 'array' then (select array_agg(trim(x)) from jsonb_array_elements_text(d->'passos') x where length(trim(x)) >= 3) else passos end,
    prazo_horas = coalesce((d->>'prazo_horas')::int, prazo_horas),
    papel_responsavel = coalesce(d->>'papel_responsavel', papel_responsavel)
  where ies_id = p_ies and motivo = p_motivo returning id into v_id;
  if v_id is null then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.auditar(p_ies, 'caso.trilha', 'trilha', v_id::text, jsonb_build_object('motivo', p_motivo));
  return jsonb_build_object('id', v_id);
end $$;

-- ---------------------------------------------------------------- leitura
create or replace function public.rpc_casos(p_ies bigint, p_op bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare papeis text[] := (select papeis from public.matriz_permissoes where operacao = 'caso.ver'); eu uuid := (select auth.uid());
begin
  perform privado.autorizar(p_ies, 'caso.ver');
  return (with vis as (
      select c.*, o.curso_id, o.responsavel_id as resp_op from public.casos c join public.oportunidades o on o.id = c.oportunidade_id
       where c.ies_id = p_ies and (p_op is null or c.oportunidade_id = p_op) and privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, papeis))
    select jsonb_build_object(
      'pode_atender', privado.pode(p_ies, 'caso.atender'), 'pode_trilhas', privado.pode(p_ies, 'caso.trilhas'), 'eu', eu,
      'aviso', 'Não registre dado sensível (saúde, religião, orientação, etc.; LGPD art. 11). Nada é enviado ao aluno.',
      'indicadores', (select jsonb_build_object('abertos', count(*) filter (where status in ('aberto','em_atendimento')),
          'vencidos', count(*) filter (where status in ('aberto','em_atendimento') and prazo < now()),
          'sem_dono', count(*) filter (where status in ('aberto','em_atendimento') and responsavel_id is null),
          'meus', count(*) filter (where status in ('aberto','em_atendimento') and responsavel_id = eu),
          'resolvidos', count(*) filter (where status = 'resolvido'),
          'horas_medias_resolucao', round(avg(extract(epoch from encerrado_em - aberto_em) / 3600) filter (where status = 'resolvido'), 1),
          'por_motivo', (select coalesce(jsonb_object_agg(m, n), '{}'::jsonb) from (select motivo m, count(*) n from vis where status in ('aberto','em_atendimento') group by motivo) q))
        from vis),
      'trilhas', (select coalesce(jsonb_agg(jsonb_build_object('motivo', t.motivo, 'nome', t.nome, 'passos', t.passos, 'prazo_horas', t.prazo_horas, 'papel_responsavel', t.papel_responsavel) order by t.motivo), '[]'::jsonb)
                  from public.trilhas_intervencao t where t.ies_id = p_ies),
      'agenda', (select coalesce(jsonb_agg(jsonb_build_object('caso', v.id, 'nome', p.nome, 'quando', e.agendado_para, 'texto', e.texto, 'por', privado.nome_usuario(e.por)) order by e.agendado_para), '[]'::jsonb)
                 from vis v join public.casos_eventos e on e.caso_id = v.id join public.oportunidades o on o.id = v.oportunidade_id join public.pessoas p on p.id = o.pessoa_id
                 where e.tipo = 'agendamento' and e.agendado_para >= now() and v.status in ('aberto','em_atendimento')),
      'casos', (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'oportunidade_id', v.oportunidade_id, 'nome', p.nome, 'curso', k.nome || ' · ' || k.turno,
          'motivo', v.motivo, 'origem', v.origem, 'prioridade', v.prioridade, 'status', v.status, 'descricao', v.descricao, 'prazo', v.prazo,
          'vencido', v.status in ('aberto','em_atendimento') and v.prazo < now(), 'responsavel_id', v.responsavel_id, 'responsavel', privado.nome_usuario(v.responsavel_id),
          'passos', t.passos, 'passos_concluidos', v.passos_concluidos, 'resolucao', v.resolucao, 'aberto_em', v.aberto_em, 'encerrado_em', v.encerrado_em,
          'eventos', (select coalesce(jsonb_agg(jsonb_build_object('tipo', e.tipo, 'texto', e.texto, 'agendado_para', e.agendado_para, 'por', coalesce(privado.nome_usuario(e.por), 'sistema'), 'em', e.em) order by e.id), '[]'::jsonb)
                      from public.casos_eventos e where e.caso_id = v.id))
          order by (v.status in ('aberto','em_atendimento')) desc, (v.prazo < now()) desc, case v.prioridade when 'alta' then 0 when 'media' then 1 else 2 end, v.prazo), '[]'::jsonb)
        from vis v join public.oportunidades o on o.id = v.oportunidade_id join public.pessoas p on p.id = o.pessoa_id join public.cursos k on k.id = o.curso_id
        left join public.trilhas_intervencao t on t.id = v.trilha_id),
      'equipe', (select coalesce(jsonb_agg(distinct jsonb_build_object('id', e.usuario_id, 'nome', privado.nome_usuario(e.usuario_id))), '[]'::jsonb)
                 from public.escopos e where e.ies_id = p_ies and e.revogado_em is null and e.papel in (select unnest(mp.papeis) from public.matriz_permissoes mp where mp.operacao = 'caso.atender')))
    from (select 1) um);
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.rpc_abrir_caso(bigint, text, text, text), public.rpc_atender_caso(bigint, text, text, timestamptz, uuid),
  public.rpc_salvar_trilha(bigint, text, jsonb), public.rpc_casos(bigint, bigint) to authenticated;
select privado.conceder_publico();

-- ===================== supabase/migrations/20261126000026_dois_fatores.sql
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

-- ===================== supabase/migrations/20261126000027_captacao_campo.sql
-- Matrícula 360° — migração 27 (Onda B, L17): captação em campo — escolas, visitas e feiras, modo feira sem internet.
--   * Cadastro de escolas de ensino médio (pública/privada, cidade, UF, INEP opcional, contato institucional).
--   * Visitas a escolas, feiras, palestras e aulas abertas: data, responsável, status, público estimado e código para QR.
--   * Captação em lote pela equipe ("modo feira"): o aparelho guarda os cadastros sem internet e sincroniza depois; cada cadastro
--     traz consentimento LGPD com a versão do texto e um identificador local que torna a sincronização idempotente.
--     Usa a mesma criação de oportunidade do CRM (deduplicação, distribuição, campanha).
--   * Indicadores por visita e por escola: leads, inscritos em diante, ingressos efetivos.
-- Idempotente.

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('campo.ver',       'Marketing e Captação', 'Ver escolas, visitas e resultados da captação em campo', array['gestor','comercial','coordenador','reitoria'], 'curso', 'rpc_campo'),
  ('campo.registrar', 'Marketing e Captação', 'Cadastrar escolas e visitas e sincronizar o modo feira', array['gestor','comercial'], 'curso', 'rpc_captar_campo')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

create table if not exists public.escolas (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  nome text not null check (length(nome) between 3 and 150),
  rede text not null check (rede in ('publica','privada')),
  cidade text not null check (length(cidade) between 2 and 80),
  uf text not null check (uf ~ '^[A-Z]{2}$'),
  inep text check (inep ~ '^\d{8}$'),
  contato text check (length(contato) <= 200),
  observacao text check (length(observacao) <= 1000),
  ativa boolean not null default true,
  criado_por uuid references public.usuarios(id),
  unique (ies_id, nome, cidade)
);
create table if not exists public.visitas_escola (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  escola_id bigint references public.escolas(id),
  titulo text not null check (length(titulo) between 3 and 150),
  tipo text not null check (tipo in ('visita','palestra','feira','aula_aberta')),
  data date not null,
  responsavel_id uuid references public.usuarios(id),
  status text not null default 'planejada' check (status in ('planejada','realizada','cancelada')),
  publico_estimado int check (publico_estimado is null or publico_estimado >= 0),
  codigo text not null check (codigo ~ '^[a-z0-9-]{4,40}$'),
  campanha_id bigint references public.campanhas(id),
  observacao text check (length(observacao) <= 1000),
  unique (ies_id, codigo)
);
create table if not exists public.captacoes_campo (
  id_local uuid primary key,
  ies_id bigint not null references public.ies(id),
  visita_id bigint not null references public.visitas_escola(id),
  oportunidade_id bigint references public.oportunidades(id),
  consentimento_hash text not null,
  capturado_em timestamptz not null,
  sincronizado_em timestamptz not null default now(),
  por uuid references public.usuarios(id)
);
alter table public.oportunidades add column if not exists visita_id bigint references public.visitas_escola(id);
create index if not exists escolas_criado on public.escolas(criado_por);
create index if not exists visitas_escola_escola on public.visitas_escola(escola_id);
create index if not exists visitas_escola_resp on public.visitas_escola(responsavel_id);
create index if not exists visitas_escola_camp on public.visitas_escola(campanha_id);
create index if not exists capt_campo_ies on public.captacoes_campo(ies_id);
create index if not exists capt_campo_visita on public.captacoes_campo(visita_id);
create index if not exists capt_campo_op on public.captacoes_campo(oportunidade_id);
create index if not exists capt_campo_por on public.captacoes_campo(por);
create index if not exists oportunidades_visita on public.oportunidades(visita_id);
alter table public.escolas enable row level security;
alter table public.visitas_escola enable row level security;
alter table public.captacoes_campo enable row level security;
revoke all on public.escolas, public.visitas_escola, public.captacoes_campo from anon, authenticated;
do $$ begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'privado' and p.proname = 'mfa_ok') then
    execute 'drop policy if exists mfa_obrigatorio on public.escolas; create policy mfa_obrigatorio on public.escolas as restrictive for all to authenticated using ((select privado.mfa_ok()))';
    execute 'drop policy if exists mfa_obrigatorio on public.visitas_escola; create policy mfa_obrigatorio on public.visitas_escola as restrictive for all to authenticated using ((select privado.mfa_ok()))';
    execute 'drop policy if exists mfa_obrigatorio on public.captacoes_campo; create policy mfa_obrigatorio on public.captacoes_campo as restrictive for all to authenticated using ((select privado.mfa_ok()))';
  end if;
end $$;

create or replace function public.rpc_salvar_escola(p_ies bigint, p_dados jsonb, p_id bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare d jsonb := coalesce(p_dados, '{}'::jsonb); v_id bigint;
begin
  perform privado.autorizar(p_ies, 'campo.registrar');
  if p_id is null then
    insert into public.escolas(ies_id, nome, rede, cidade, uf, inep, contato, observacao, criado_por)
    values (p_ies, trim(d->>'nome'), d->>'rede', trim(d->>'cidade'), upper(trim(d->>'uf')), nullif(trim(d->>'inep'), ''), nullif(trim(d->>'contato'), ''),
            nullif(trim(d->>'observacao'), ''), (select auth.uid()))
    returning id into v_id;
  else
    update public.escolas set nome = coalesce(trim(d->>'nome'), nome), rede = coalesce(d->>'rede', rede), cidade = coalesce(trim(d->>'cidade'), cidade),
      uf = coalesce(upper(trim(d->>'uf')), uf), inep = case when d ? 'inep' then nullif(trim(d->>'inep'), '') else inep end,
      contato = case when d ? 'contato' then nullif(trim(d->>'contato'), '') else contato end,
      observacao = case when d ? 'observacao' then nullif(trim(d->>'observacao'), '') else observacao end, ativa = coalesce((d->>'ativa')::boolean, ativa)
    where id = p_id and ies_id = p_ies returning id into v_id;
    if v_id is null then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  end if;
  perform privado.auditar(p_ies, 'campo.escola', 'escola', v_id::text, jsonb_build_object('nome', d->>'nome', 'novo', p_id is null));
  return jsonb_build_object('id', v_id);
exception when unique_violation then raise exception 'Escola já cadastrada nesta cidade' using errcode = '22023';
end $$;

create or replace function public.rpc_salvar_visita(p_ies bigint, p_dados jsonb, p_id bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare d jsonb := coalesce(p_dados, '{}'::jsonb); v_id bigint; v_camp bigint; v_codigo text;
begin
  perform privado.autorizar(p_ies, 'campo.registrar');
  if nullif(d->>'escola_id', '') is not null and not exists (select 1 from public.escolas where id = (d->>'escola_id')::bigint and ies_id = p_ies) then
    raise exception 'Escola não encontrada' using errcode = '22023'; end if;
  if nullif(trim(coalesce(d->>'campanha', '')), '') is not null then
    select id into v_camp from public.campanhas where ies_id = p_ies and codigo = lower(trim(d->>'campanha')) and status <> 'cancelada';
    if v_camp is null then raise exception 'Campanha não encontrada: %', d->>'campanha' using errcode = '22023'; end if;
  end if;
  if p_id is null then
    v_codigo := coalesce(nullif(lower(trim(d->>'codigo')), ''), 'v-' || substr(md5(gen_random_uuid()::text), 1, 8));
    insert into public.visitas_escola(ies_id, escola_id, titulo, tipo, data, responsavel_id, publico_estimado, codigo, campanha_id, observacao)
    values (p_ies, nullif(d->>'escola_id', '')::bigint, trim(d->>'titulo'), d->>'tipo', (d->>'data')::date, (select auth.uid()),
            nullif(d->>'publico_estimado', '')::int, v_codigo, v_camp, nullif(trim(d->>'observacao'), ''))
    returning id into v_id;
  else
    update public.visitas_escola set titulo = coalesce(trim(d->>'titulo'), titulo), data = coalesce((d->>'data')::date, data),
      status = coalesce(d->>'status', status), publico_estimado = case when d ? 'publico_estimado' then nullif(d->>'publico_estimado', '')::int else publico_estimado end,
      observacao = case when d ? 'observacao' then nullif(trim(d->>'observacao'), '') else observacao end
    where id = p_id and ies_id = p_ies returning id into v_id;
    if v_id is null then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  end if;
  perform privado.auditar(p_ies, 'campo.visita', 'visita', v_id::text, jsonb_build_object('titulo', d->>'titulo', 'status', d->>'status', 'novo', p_id is null));
  return jsonb_build_object('id', v_id, 'codigo', (select codigo from public.visitas_escola where id = v_id));
exception when unique_violation then raise exception 'Código de visita já usado' using errcode = '22023';
end $$;

-- Modo feira: sincroniza cadastros capturados no aparelho (com ou sem internet). Idempotente por id_local.
create or replace function public.rpc_captar_campo(p_visita bigint, p_leads jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v public.visitas_escola; l jsonb; r jsonb; ok int := 0; rep int := 0; dup int := 0; rej jsonb := '[]'::jsonb; idl uuid; camp text;
begin
  perform privado.exigir_usuario();
  select * into v from public.visitas_escola where id = p_visita;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(v.ies_id, 'campo.registrar');
  if v.status = 'cancelada' then raise exception 'Visita cancelada' using errcode = '22023'; end if;
  if jsonb_typeof(p_leads) <> 'array' or jsonb_array_length(p_leads) > 200 then raise exception 'Envie até 200 cadastros por vez' using errcode = '22023'; end if;
  camp := (select codigo from public.campanhas where id = v.campanha_id);
  for l in select * from jsonb_array_elements(p_leads) loop
    begin
      idl := (l->>'id_local')::uuid;
      if exists (select 1 from public.captacoes_campo where id_local = idl) then rep := rep + 1; continue; end if;
      if not coalesce((l->>'consentimento')::boolean, false) or length(coalesce(l->>'consentimento_hash', '')) <> 64 then
        raise exception 'Sem consentimento registrado' using errcode = '22023'; end if;
      r := public.rpc_criar_oportunidade(v.ies_id, jsonb_build_object('nome', l->>'nome', 'email', l->>'email', 'telefone', l->>'telefone', 'curso_id', l->>'curso_id',
             'coorte', l->>'coorte', 'forma_ingresso', case when v.tipo = 'feira' then 'evento' else 'visita_escolar' end, 'base_legal', 'consentimento',
             'origem', left('campo: ' || v.titulo, 80), 'campanha', camp), 'campo-' || idl::text);
      if (r->>'duplicada')::boolean then dup := dup + 1; else
        update public.oportunidades set visita_id = v.id where id = (r->>'id')::bigint and visita_id is null;
      end if;
      insert into public.captacoes_campo(id_local, ies_id, visita_id, oportunidade_id, consentimento_hash, capturado_em, por)
      values (idl, v.ies_id, v.id, (r->>'id')::bigint, l->>'consentimento_hash', coalesce((l->>'capturado_em')::timestamptz, now()), (select auth.uid()));
      ok := ok + 1;
    exception when others then
      rej := rej || jsonb_build_object('id_local', l->>'id_local', 'nome', l->>'nome', 'motivo', case when sqlstate = 'PGRST' then sqlerrm::jsonb->>'message' else sqlerrm end);
    end;
  end loop;
  if v.status = 'planejada' and ok > 0 then update public.visitas_escola set status = 'realizada' where id = v.id; end if;
  perform privado.auditar(v.ies_id, 'campo.sincronizar', 'visita', v.id::text, jsonb_build_object('recebidos', ok, 'ja_sincronizados', rep, 'contatos_existentes', dup, 'rejeitados', jsonb_array_length(rej)));
  return jsonb_build_object('recebidos', ok, 'ja_sincronizados', rep, 'contatos_existentes', dup, 'rejeitados', rej);
end $$;

create or replace function public.rpc_campo(p_ies bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare papeis text[] := (select papeis from public.matriz_permissoes where operacao = 'campo.ver');
begin
  perform privado.autorizar(p_ies, 'campo.ver');
  return jsonb_build_object('pode_registrar', privado.pode(p_ies, 'campo.registrar'),
    'escolas', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'nome', e.nome, 'rede', e.rede, 'cidade', e.cidade, 'uf', e.uf, 'inep', e.inep, 'contato', e.contato,
        'observacao', e.observacao, 'ativa', e.ativa,
        'visitas', (select count(*) from public.visitas_escola v where v.escola_id = e.id and v.status = 'realizada'),
        'leads', (select count(*) from public.oportunidades o join public.visitas_escola v on v.id = o.visita_id where v.escola_id = e.id and privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, papeis)),
        'ingressos', (select count(*) from public.oportunidades o join public.visitas_escola v on v.id = o.visita_id where v.escola_id = e.id and o.etapa = 'confirmado' and privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, papeis))
      ) order by e.nome), '[]'::jsonb) from public.escolas e where e.ies_id = p_ies),
    'visitas', (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'titulo', v.titulo, 'tipo', v.tipo, 'data', v.data, 'status', v.status, 'codigo', v.codigo,
        'escola', (select nome || ' · ' || cidade from public.escolas where id = v.escola_id), 'responsavel', privado.nome_usuario(v.responsavel_id),
        'publico_estimado', v.publico_estimado, 'campanha', (select codigo from public.campanhas where id = v.campanha_id),
        'leads', (select count(*) from public.oportunidades o where o.visita_id = v.id and privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, papeis)),
        'inscritos', (select count(*) from public.oportunidades o where o.visita_id = v.id and o.etapa in ('inscrito','pre_matricula','matricula_comercial','confirmado') and privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, papeis)),
        'ingressos', (select count(*) from public.oportunidades o where o.visita_id = v.id and o.etapa = 'confirmado' and privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, papeis)),
        'capturados', (select count(*) from public.captacoes_campo c where c.visita_id = v.id)
      ) order by v.data desc, v.id desc), '[]'::jsonb) from public.visitas_escola v where v.ies_id = p_ies));
end $$;

-- QR code da visita: o aluno se inscreve no formulário público pelo próprio celular; logo depois, com o link pessoal recebido,
-- a página vincula a inscrição recém-criada à visita (só oportunidades sem origem de visita e criadas há até 30 minutos).
create or replace function public.rpc_publico_vincular_visita(p_token text, p_codigo text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.pessoas; v public.visitas_escola; n int;
begin
  p := privado.portal_pessoa(p_token);
  select * into v from public.visitas_escola where ies_id = p.ies_id and codigo = lower(trim(coalesce(p_codigo, ''))) and status <> 'cancelada';
  if not found then return jsonb_build_object('vinculadas', 0); end if;
  update public.oportunidades set visita_id = v.id where pessoa_id = p.id and visita_id is null and criado_em > now() - interval '30 minutes';
  get diagnostics n = row_count;
  if n > 0 then
    if v.status = 'planejada' then update public.visitas_escola set status = 'realizada' where id = v.id; end if;
    perform privado.auditar(p.ies_id, 'campo.qr', 'visita', v.id::text, jsonb_build_object('vinculadas', n));
  end if;
  return jsonb_build_object('vinculadas', n);
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.rpc_salvar_escola(bigint, jsonb, bigint), public.rpc_salvar_visita(bigint, jsonb, bigint),
  public.rpc_captar_campo(bigint, jsonb), public.rpc_campo(bigint) to authenticated;
select privado.conceder_publico();

-- ===================== supabase/migrations/20261126000028_pesquisas.sql
-- Matrícula 360° — migração 28 (Onda B, L16): pesquisas de pulso e satisfação.
--   * Pesquisa por público: candidato em andamento, ingressante (até 120 dias do ingresso), aluno, ou quem desistiu/se perdeu
--     ("por que não nos escolheu"). Perguntas: NPS (0–10), escala 1–5, opção única e texto livre (até 15 perguntas).
--   * Resposta pelo portal do candidato/aluno, uma por pesquisa e oportunidade; nada é enviado (convite pelo link do portal).
--   * Resultados agregados: taxa de resposta sobre elegíveis, NPS (promotores − detratores), distribuição por pergunta e comentários
--     SEM identificação. Abaixo do mínimo de respostas (padrão 5) os resultados ficam N/D para não expor ninguém.
-- Idempotente.

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('pesquisa.ver',   'Central de Inteligência', 'Ver resultados agregados das pesquisas (sem identificação)', array['gestor','reitoria','coordenador'], 'ies', 'rpc_pesquisas'),
  ('pesquisa.gerir', 'Central de Inteligência', 'Criar, ativar e encerrar pesquisas',                          array['gestor'], 'ies', 'rpc_salvar_pesquisa')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

create table if not exists public.pesquisas (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  nome text not null check (length(nome) between 3 and 120),
  publico text not null check (publico in ('candidato','ingressante','aluno','perdido')),
  introducao text check (length(introducao) <= 1000),
  perguntas jsonb not null check (jsonb_typeof(perguntas) = 'array' and jsonb_array_length(perguntas) between 1 and 15),
  min_respostas int not null default 5 check (min_respostas between 3 and 100),
  status text not null default 'rascunho' check (status in ('rascunho','ativa','encerrada')),
  criado_por uuid references public.usuarios(id),
  criado_em timestamptz not null default now(),
  unique (ies_id, nome)
);
create table if not exists public.respostas_pesquisa (
  id bigint generated always as identity primary key,
  pesquisa_id bigint not null references public.pesquisas(id),
  oportunidade_id bigint not null references public.oportunidades(id),
  respostas jsonb not null,
  nps int check (nps between 0 and 10),
  respondido_em timestamptz not null default now(),
  unique (pesquisa_id, oportunidade_id)
);
create index if not exists pesquisas_criado on public.pesquisas(criado_por);
create index if not exists respostas_pesquisa_op on public.respostas_pesquisa(oportunidade_id);
alter table public.pesquisas enable row level security;
alter table public.respostas_pesquisa enable row level security;
revoke all on public.pesquisas, public.respostas_pesquisa from anon, authenticated;
do $$ begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'privado' and p.proname = 'mfa_ok') then
    execute 'drop policy if exists mfa_obrigatorio on public.pesquisas; create policy mfa_obrigatorio on public.pesquisas as restrictive for all to authenticated using ((select privado.mfa_ok()))';
    execute 'drop policy if exists mfa_obrigatorio on public.respostas_pesquisa; create policy mfa_obrigatorio on public.respostas_pesquisa as restrictive for all to authenticated using ((select privado.mfa_ok()))';
  end if;
end $$;

-- Perguntas válidas: id único, tipo conhecido, texto, opções para "opcao".
create or replace function privado.validar_perguntas(p jsonb) returns void
language plpgsql immutable set search_path = '' as $$
declare q jsonb; ids text[] := '{}';
begin
  if jsonb_typeof(p) <> 'array' or jsonb_array_length(p) not between 1 and 15 then raise exception 'Entre 1 e 15 perguntas' using errcode = '22023'; end if;
  for q in select * from jsonb_array_elements(p) loop
    if coalesce(q->>'id', '') !~ '^[a-z0-9_]{1,20}$' or (q->>'id') = any (ids) then raise exception 'Identificador de pergunta inválido ou repetido' using errcode = '22023'; end if;
    ids := ids || (q->>'id');
    if coalesce(q->>'tipo', '') not in ('nps','escala5','opcao','texto') then raise exception 'Tipo de pergunta inválido' using errcode = '22023'; end if;
    if length(coalesce(trim(q->>'texto'), '')) not between 3 and 300 then raise exception 'Texto da pergunta entre 3 e 300 caracteres' using errcode = '22023'; end if;
    if q->>'tipo' = 'opcao' and (jsonb_typeof(q->'opcoes') <> 'array' or jsonb_array_length(q->'opcoes') not between 2 and 12) then
      raise exception 'Pergunta de opção precisa de 2 a 12 opções' using errcode = '22023'; end if;
  end loop;
  if (select count(*) from jsonb_array_elements(p) x where x->>'tipo' = 'nps') > 1 then raise exception 'No máximo uma pergunta NPS' using errcode = '22023'; end if;
end $$;

-- Oportunidade faz parte do público da pesquisa?
create or replace function privado.no_publico(o public.oportunidades, p_publico text) returns boolean
language sql stable set search_path = '' as $$
  select case p_publico
    when 'candidato' then o.etapa in ('novo','contato','inscrito','pre_matricula','matricula_comercial')
    when 'ingressante' then o.etapa = 'confirmado' and o.confirmada_em > now() - interval '120 days'
    when 'aluno' then o.etapa = 'confirmado'
    when 'perdido' then o.etapa in ('perdido','cancelado')
    else false end
$$;
revoke execute on function privado.validar_perguntas(jsonb), privado.no_publico(public.oportunidades, text) from public, anon, authenticated;

create or replace function public.rpc_salvar_pesquisa(p_ies bigint, p_dados jsonb, p_id bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare d jsonb := coalesce(p_dados, '{}'::jsonb); v_id bigint; atual public.pesquisas;
begin
  perform privado.autorizar(p_ies, 'pesquisa.gerir');
  if p_id is null then
    perform privado.validar_perguntas(d->'perguntas');
    insert into public.pesquisas(ies_id, nome, publico, introducao, perguntas, min_respostas, criado_por)
    values (p_ies, trim(d->>'nome'), d->>'publico', nullif(trim(d->>'introducao'), ''), d->'perguntas', coalesce((d->>'min_respostas')::int, 5), (select auth.uid()))
    returning id into v_id;
  else
    select * into atual from public.pesquisas where id = p_id and ies_id = p_ies for update;
    if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
    if d ? 'status' then
      if not ((atual.status = 'rascunho' and d->>'status' = 'ativa') or (atual.status = 'ativa' and d->>'status' = 'encerrada')) then
        raise exception 'Transição de status inválida' using errcode = '22023'; end if;
      update public.pesquisas set status = d->>'status' where id = p_id;
    else
      if atual.status <> 'rascunho' then raise exception 'Só a pesquisa em rascunho pode ser editada (respostas valem pelas perguntas publicadas)' using errcode = '22023'; end if;
      if d ? 'perguntas' then perform privado.validar_perguntas(d->'perguntas'); end if;
      update public.pesquisas set nome = coalesce(trim(d->>'nome'), nome), publico = coalesce(d->>'publico', publico),
        introducao = case when d ? 'introducao' then nullif(trim(d->>'introducao'), '') else introducao end,
        perguntas = coalesce(d->'perguntas', perguntas), min_respostas = coalesce((d->>'min_respostas')::int, min_respostas) where id = p_id;
    end if;
    v_id := p_id;
  end if;
  perform privado.auditar(p_ies, 'pesquisa.salvar', 'pesquisa', v_id::text, jsonb_build_object('nome', coalesce(d->>'nome', atual.nome), 'status', d->>'status', 'novo', p_id is null));
  return jsonb_build_object('id', v_id);
exception when unique_violation then raise exception 'Já existe pesquisa com este nome' using errcode = '22023';
end $$;

create or replace function public.rpc_pesquisas(p_ies bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform privado.autorizar(p_ies, 'pesquisa.ver');
  return jsonb_build_object('pode_gerir', privado.pode(p_ies, 'pesquisa.gerir'),
    'aviso', 'Resultados agregados e sem identificação. Abaixo do mínimo de respostas, N/D. Convide pelo link do portal (nada é enviado pelo sistema).',
    'pesquisas', (select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'nome', q.nome, 'publico', q.publico, 'introducao', q.introducao, 'perguntas', q.perguntas,
        'min_respostas', q.min_respostas, 'status', q.status, 'criado_em', q.criado_em, 'resultado', privado.resultado_pesquisa(q)) order by q.status = 'encerrada', q.id desc), '[]'::jsonb)
      from public.pesquisas q where q.ies_id = p_ies));
end $$;

create or replace function privado.resultado_pesquisa(q public.pesquisas) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare n int; eleg int; r jsonb := '{}'::jsonb; p jsonb; dist jsonb;
begin
  select count(*) into n from public.respostas_pesquisa where pesquisa_id = q.id;
  select count(*) into eleg from public.oportunidades o where o.ies_id = q.ies_id and (privado.no_publico(o, q.publico) or exists (select 1 from public.respostas_pesquisa x where x.pesquisa_id = q.id and x.oportunidade_id = o.id));
  if n < q.min_respostas then
    return jsonb_build_object('respostas', n, 'elegiveis', eleg, 'taxa_pct', case when eleg = 0 then null else round(100.0 * n / eleg, 1) end, 'suficiente', false,
      'motivo', format('N/D: %s resposta(s), mínimo %s para exibir', n, q.min_respostas));
  end if;
  for p in select * from jsonb_array_elements(q.perguntas) loop
    if p->>'tipo' = 'texto' then
      dist := (select coalesce(jsonb_agg(x.respostas->>(p->>'id') order by random()), '[]'::jsonb) from public.respostas_pesquisa x
                where x.pesquisa_id = q.id and length(coalesce(x.respostas->>(p->>'id'), '')) > 0);
    else
      dist := (select coalesce(jsonb_object_agg(v, c), '{}'::jsonb) from (select x.respostas->>(p->>'id') v, count(*) c from public.respostas_pesquisa x
                where x.pesquisa_id = q.id and x.respostas ? (p->>'id') group by 1) z);
    end if;
    r := r || jsonb_build_object(p->>'id', dist);
  end loop;
  return jsonb_build_object('respostas', n, 'elegiveis', eleg, 'taxa_pct', case when eleg = 0 then null else round(100.0 * n / eleg, 1) end, 'suficiente', true,
    'nps', (select case when count(nps) = 0 then null else round(100.0 * (count(*) filter (where nps >= 9) - count(*) filter (where nps <= 6)) / count(nps)) end
            from public.respostas_pesquisa where pesquisa_id = q.id and nps is not null),
    'por_pergunta', r);
end $$;
revoke execute on function privado.resultado_pesquisa(public.pesquisas) from public, anon, authenticated;

-- ---------------------------------------------------------------- portal
create or replace function public.rpc_publico_portal_pesquisas(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.pessoas;
begin
  p := privado.portal_pessoa(p_token);
  return (select coalesce(jsonb_agg(jsonb_build_object('pesquisa_id', q.id, 'oportunidade_id', o.id, 'curso', c.nome || ' · ' || c.turno, 'nome', q.nome,
      'introducao', q.introducao, 'perguntas', q.perguntas) order by q.id), '[]'::jsonb)
    from public.oportunidades o join public.cursos c on c.id = o.curso_id join public.pesquisas q on q.ies_id = o.ies_id and q.status = 'ativa'
    where o.pessoa_id = p.id and privado.no_publico(o, q.publico)
      and not exists (select 1 from public.respostas_pesquisa x where x.pesquisa_id = q.id and x.oportunidade_id = o.id));
end $$;

create or replace function public.rpc_publico_responder_pesquisa(p_token text, p_pesquisa bigint, p_op bigint, p_respostas jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.pessoas; o public.oportunidades; q public.pesquisas; pq jsonb; v text; limpo jsonb := '{}'::jsonb; v_nps int;
begin
  p := privado.portal_pessoa(p_token);
  select * into o from public.oportunidades where id = p_op and pessoa_id = p.id;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  select * into q from public.pesquisas where id = p_pesquisa and ies_id = o.ies_id and status = 'ativa';
  if not found or not privado.no_publico(o, q.publico) then perform privado.erro_http(404, 'P0002', 'Pesquisa indisponível'); end if;
  if jsonb_typeof(p_respostas) <> 'object' then raise exception 'Respostas inválidas' using errcode = '22023'; end if;
  for pq in select * from jsonb_array_elements(q.perguntas) loop
    v := nullif(trim(p_respostas->>(pq->>'id')), '');
    continue when v is null;
    if pq->>'tipo' = 'nps' then
      if v !~ '^\d{1,2}$' or v::int > 10 then raise exception 'Nota de 0 a 10' using errcode = '22023'; end if; v_nps := v::int;
    elsif pq->>'tipo' = 'escala5' then
      if v !~ '^[1-5]$' then raise exception 'Escala de 1 a 5' using errcode = '22023'; end if;
    elsif pq->>'tipo' = 'opcao' then
      if not (pq->'opcoes' ? v) then raise exception 'Opção inválida' using errcode = '22023'; end if;
    else v := left(v, 1000);
    end if;
    limpo := limpo || jsonb_build_object(pq->>'id', v);
  end loop;
  if limpo = '{}'::jsonb then raise exception 'Responda pelo menos uma pergunta' using errcode = '22023'; end if;
  insert into public.respostas_pesquisa(pesquisa_id, oportunidade_id, respostas, nps) values (q.id, o.id, limpo, v_nps);
  return jsonb_build_object('mensagem', 'Obrigado! Sua resposta foi registrada.');
exception when unique_violation then raise exception 'Você já respondeu esta pesquisa' using errcode = '22023';
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.rpc_salvar_pesquisa(bigint, jsonb, bigint), public.rpc_pesquisas(bigint) to authenticated;
select privado.conceder_publico();

-- ===================== supabase/migrations/20261126000029_banca_aproveitamento.sql
-- Matrícula 360° — migração 29 (Onda B, L19): avaliação por banca e aproveitamento de estudos.
--   * Banca no processo seletivo: rubrica com critérios e pesos, número mínimo de avaliadores e divergência máxima.
--     Cada avaliador registra notas por critério e parecer sem ver as notas dos outros (avaliação às cegas) até registrar a sua.
--     Divergência acima do limite exige mais um avaliador. A decisão final continua humana e justificada (rpc_avaliar_candidatura);
--     um gatilho impede decidir antes de a banca estar completa.
--   * Aproveitamento de estudos (transferência, segunda graduação, reingresso): disciplinas de origem, equivalência, carga
--     aproveitada, parecer e semestre de ingresso sugerido. O candidato vê o resultado no portal depois da conclusão.
-- Idempotente.

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('aproveitamento.analisar', 'Conversão e Matrículas', 'Analisar aproveitamento de estudos (transferência, segunda graduação, reingresso)',
   array['gestor','coordenador','secretaria'], 'curso', 'rpc_salvar_aproveitamento')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

alter table public.processos_seletivos
  add column if not exists rubrica jsonb,
  add column if not exists avaliadores_minimos int not null default 0 check (avaliadores_minimos between 0 and 5),
  add column if not exists divergencia_max numeric(6,2) check (divergencia_max is null or divergencia_max > 0);

create table if not exists public.avaliacoes_banca (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  candidatura_id bigint not null references public.candidaturas(id),
  avaliador_id uuid not null references public.usuarios(id),
  notas jsonb not null,
  nota_final numeric(6,2) not null check (nota_final between 0 and 1000),
  parecer text not null check (length(parecer) between 10 and 2000),
  em timestamptz not null default now(),
  unique (candidatura_id, avaliador_id)
);
create table if not exists public.aproveitamentos (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  oportunidade_id bigint not null unique references public.oportunidades(id),
  instituicao_origem text not null check (length(instituicao_origem) between 3 and 200),
  curso_origem text not null check (length(curso_origem) between 3 and 200),
  disciplinas jsonb not null default '[]'::jsonb check (jsonb_typeof(disciplinas) = 'array'),
  status text not null default 'em_analise' check (status in ('em_analise','concluida')),
  carga_aproveitada int not null default 0,
  semestre_sugerido int check (semestre_sugerido between 1 and 12),
  parecer text check (length(parecer) <= 3000),
  analisado_por uuid references public.usuarios(id),
  concluida_em timestamptz,
  atualizado_em timestamptz not null default now()
);
create index if not exists banca_ies on public.avaliacoes_banca(ies_id);
create index if not exists banca_avaliador on public.avaliacoes_banca(avaliador_id);
create index if not exists aprov_ies on public.aproveitamentos(ies_id);
create index if not exists aprov_analisado on public.aproveitamentos(analisado_por);
alter table public.avaliacoes_banca enable row level security;
alter table public.aproveitamentos enable row level security;
revoke all on public.avaliacoes_banca, public.aproveitamentos from anon, authenticated;
do $$ begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'privado' and p.proname = 'mfa_ok') then
    execute 'drop policy if exists mfa_obrigatorio on public.avaliacoes_banca; create policy mfa_obrigatorio on public.avaliacoes_banca as restrictive for all to authenticated using ((select privado.mfa_ok()))';
    execute 'drop policy if exists mfa_obrigatorio on public.aproveitamentos; create policy mfa_obrigatorio on public.aproveitamentos as restrictive for all to authenticated using ((select privado.mfa_ok()))';
  end if;
end $$;

-- ---------------------------------------------------------------- banca
create or replace function public.rpc_configurar_banca(p_processo bigint, p_rubrica jsonb, p_minimos int, p_divergencia numeric default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare pr public.processos_seletivos; c jsonb; soma numeric := 0;
begin
  perform privado.exigir_usuario();
  select * into pr from public.processos_seletivos where id = p_processo for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(pr.ies_id, 'seletivo.gerir');
  if pr.resultado_divulgado_em is not null then raise exception 'Resultado já divulgado' using errcode = '22023'; end if;
  if exists (select 1 from public.avaliacoes_banca b join public.candidaturas x on x.id = b.candidatura_id where x.processo_id = pr.id) then
    raise exception 'A banca já começou a avaliar: a rubrica não muda' using errcode = '22023'; end if;
  if p_minimos not between 1 and 5 then raise exception 'Entre 1 e 5 avaliadores' using errcode = '22023'; end if;
  if jsonb_typeof(p_rubrica) <> 'array' or jsonb_array_length(p_rubrica) not between 1 and 10 then raise exception 'Rubrica com 1 a 10 critérios' using errcode = '22023'; end if;
  for c in select * from jsonb_array_elements(p_rubrica) loop
    if coalesce(c->>'id', '') !~ '^[a-z0-9_]{1,20}$' or length(coalesce(c->>'texto', '')) < 3 or coalesce((c->>'peso')::numeric, 0) <= 0 then
      raise exception 'Critério inválido: id, texto e peso positivo' using errcode = '22023'; end if;
    soma := soma + (c->>'peso')::numeric;
  end loop;
  if (select count(distinct x->>'id') from jsonb_array_elements(p_rubrica) x) <> jsonb_array_length(p_rubrica) then raise exception 'Critério repetido' using errcode = '22023'; end if;
  update public.processos_seletivos set rubrica = p_rubrica, avaliadores_minimos = p_minimos, divergencia_max = p_divergencia where id = pr.id;
  perform privado.auditar(pr.ies_id, 'seletivo.banca', 'processo', pr.id::text, jsonb_build_object('criterios', jsonb_array_length(p_rubrica), 'avaliadores', p_minimos, 'divergencia', p_divergencia));
  return jsonb_build_object('id', pr.id, 'soma_pesos', soma);
end $$;

-- Situação da banca: avaliações, divergência e se já pode decidir.
create or replace function privado.situacao_banca(p_candidatura bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('minimos', pr.avaliadores_minimos, 'avaliacoes', count(b.id), 'media', round(avg(b.nota_final), 2),
    'divergencia', max(b.nota_final) - min(b.nota_final),
    'exige_mais_um', pr.divergencia_max is not null and count(b.id) >= pr.avaliadores_minimos and max(b.nota_final) - min(b.nota_final) > pr.divergencia_max
                     and count(b.id) < pr.avaliadores_minimos + 1,
    'completa', count(b.id) >= pr.avaliadores_minimos and not (pr.divergencia_max is not null and max(b.nota_final) - min(b.nota_final) > pr.divergencia_max
                     and count(b.id) < pr.avaliadores_minimos + 1))
  from public.candidaturas c join public.processos_seletivos pr on pr.id = c.processo_id left join public.avaliacoes_banca b on b.candidatura_id = c.id
  where c.id = p_candidatura group by pr.avaliadores_minimos, pr.divergencia_max
$$;
revoke execute on function privado.situacao_banca(bigint) from public, anon, authenticated;

create or replace function public.rpc_avaliar_banca(p_candidatura bigint, p_notas jsonb, p_parecer text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c public.candidaturas; o public.oportunidades; pr public.processos_seletivos; cr jsonb; v numeric; total numeric := 0; pesos numeric := 0; limpo jsonb := '{}'::jsonb;
begin
  perform privado.exigir_usuario();
  select * into c from public.candidaturas where id = p_candidatura for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  select * into o from public.oportunidades where id = c.oportunidade_id;
  if not privado.tem_acesso(o.ies_id, o.curso_id, (select papeis from public.matriz_permissoes where operacao = 'seletivo.avaliar')) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  select * into pr from public.processos_seletivos where id = c.processo_id;
  if pr.rubrica is null or pr.avaliadores_minimos = 0 then raise exception 'Processo sem banca configurada' using errcode = '22023'; end if;
  if c.resultado <> 'pendente' or pr.resultado_divulgado_em is not null then raise exception 'Candidatura já decidida' using errcode = '22023'; end if;
  if length(coalesce(trim(p_parecer), '')) < 10 then raise exception 'Parecer obrigatório (10+ caracteres)' using errcode = '22023'; end if;
  for cr in select * from jsonb_array_elements(pr.rubrica) loop
    begin v := (p_notas->>(cr->>'id'))::numeric; exception when others then v := null; end;
    if v is null or v < 0 or v > 10 then raise exception 'Nota de 0 a 10 para o critério "%"', cr->>'texto' using errcode = '22023'; end if;
    limpo := limpo || jsonb_build_object(cr->>'id', v);
    total := total + v * (cr->>'peso')::numeric; pesos := pesos + (cr->>'peso')::numeric;
  end loop;
  insert into public.avaliacoes_banca(ies_id, candidatura_id, avaliador_id, notas, nota_final, parecer)
  values (o.ies_id, c.id, (select auth.uid()), limpo, round(100 * total / pesos, 2), trim(p_parecer));
  perform privado.auditar(o.ies_id, 'seletivo.banca_avaliar', 'oportunidade', o.id::text, jsonb_build_object('candidatura', c.id, 'nota', round(100 * total / pesos, 2)));
  return jsonb_build_object('nota_final', round(100 * total / pesos, 2), 'banca', privado.situacao_banca(c.id));
exception when unique_violation then raise exception 'Você já avaliou esta candidatura' using errcode = '22023';
end $$;

-- Avaliação às cegas: antes de registrar a própria nota, o avaliador só vê quantas avaliações existem.
create or replace function public.rpc_banca(p_candidatura bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c public.candidaturas; o public.oportunidades; pr public.processos_seletivos; minha boolean;
begin
  perform privado.exigir_usuario();
  select * into c from public.candidaturas where id = p_candidatura;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  select * into o from public.oportunidades where id = c.oportunidade_id;
  if not privado.tem_acesso(o.ies_id, o.curso_id, (select papeis from public.matriz_permissoes where operacao = 'seletivo.avaliar')) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  select * into pr from public.processos_seletivos where id = c.processo_id;
  minha := exists (select 1 from public.avaliacoes_banca where candidatura_id = c.id and avaliador_id = (select auth.uid()));
  return jsonb_build_object('rubrica', pr.rubrica, 'situacao', privado.situacao_banca(c.id), 'ja_avaliei', minha,
    'avaliacoes', case when minha or c.resultado <> 'pendente' then (select coalesce(jsonb_agg(jsonb_build_object('avaliador', privado.nome_usuario(b.avaliador_id), 'notas', b.notas,
        'nota_final', b.nota_final, 'parecer', b.parecer, 'em', b.em) order by b.em), '[]'::jsonb) from public.avaliacoes_banca b where b.candidatura_id = c.id) end);
end $$;

-- Gatilho: decisão (aprovado/reprovado) só com a banca completa, quando o processo exige banca.
create or replace function privado.exigir_banca() returns trigger language plpgsql security definer set search_path = '' as $$
declare s jsonb;
begin
  if new.resultado in ('aprovado','reprovado') and old.resultado = 'pendente' then
    s := privado.situacao_banca(new.id);
    if (s->>'minimos')::int > 0 and not (s->>'completa')::boolean then
      raise exception 'Banca incompleta: % de % avaliação(ões)%', s->>'avaliacoes', s->>'minimos',
        case when (s->>'exige_mais_um')::boolean then '; divergência acima do limite exige mais um avaliador' else '' end using errcode = '22023';
    end if;
  end if;
  return new;
end $$;
revoke execute on function privado.exigir_banca() from public, anon, authenticated;
drop trigger if exists candidatura_banca on public.candidaturas;
create trigger candidatura_banca before update of resultado on public.candidaturas for each row execute function privado.exigir_banca();

-- ---------------------------------------------------------------- aproveitamento de estudos
create or replace function public.rpc_salvar_aproveitamento(p_op bigint, p_dados jsonb, p_concluir boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; a public.aproveitamentos; d jsonb := coalesce(p_dados, '{}'::jsonb); disc jsonb; x jsonb; carga int := 0; limpo jsonb := '[]'::jsonb; cg int; ca int;
begin
  o := privado.op_operacao(p_op, 'aproveitamento.analisar');
  if o.forma_ingresso not in ('transferencia','segunda_graduacao','reingresso') then
    raise exception 'Aproveitamento só para transferência, segunda graduação ou reingresso' using errcode = '22023'; end if;
  select * into a from public.aproveitamentos where oportunidade_id = o.id for update;
  if found and a.status = 'concluida' then raise exception 'Análise concluída não muda' using errcode = '22023'; end if;
  disc := coalesce(d->'disciplinas', a.disciplinas, '[]'::jsonb);
  if jsonb_typeof(disc) <> 'array' or jsonb_array_length(disc) > 80 then raise exception 'Até 80 disciplinas' using errcode = '22023'; end if;
  for x in select * from jsonb_array_elements(disc) loop
    begin cg := (x->>'carga')::int; ca := coalesce(nullif(x->>'carga_aproveitada', '')::int, 0); exception when others then raise exception 'Carga horária inválida' using errcode = '22023'; end;
    if length(coalesce(trim(x->>'nome'), '')) < 2 or cg is null or cg not between 1 and 1000 or ca not between 0 and cg then
      raise exception 'Disciplina inválida: nome, carga (1–1000 h) e carga aproveitada até a carga' using errcode = '22023'; end if;
    if coalesce(x->>'situacao', 'pendente') not in ('pendente','aproveitada','parcial','nao_aproveitada') then raise exception 'Situação inválida' using errcode = '22023'; end if;
    if x->>'situacao' = 'aproveitada' then ca := cg; elsif x->>'situacao' in ('nao_aproveitada','pendente') then ca := 0; end if;
    if x->>'situacao' in ('aproveitada','parcial') and length(coalesce(trim(x->>'equivalente'), '')) < 2 then
      raise exception 'Informe a disciplina equivalente de "%"', x->>'nome' using errcode = '22023'; end if;
    limpo := limpo || jsonb_build_array(jsonb_build_object('nome', trim(x->>'nome'), 'carga', cg, 'nota', nullif(x->>'nota', ''), 'equivalente', nullif(trim(coalesce(x->>'equivalente', '')), ''),
      'situacao', coalesce(x->>'situacao', 'pendente'), 'carga_aproveitada', ca));
    carga := carga + ca;
  end loop;
  if p_concluir then
    if exists (select 1 from jsonb_array_elements(limpo) z where z->>'situacao' = 'pendente') or jsonb_array_length(limpo) = 0 then
      raise exception 'Decida todas as disciplinas antes de concluir' using errcode = '22023'; end if;
    if length(coalesce(trim(d->>'parecer'), a.parecer, '')) < 10 or coalesce(nullif(d->>'semestre_sugerido', '')::int, a.semestre_sugerido) is null then
      raise exception 'Parecer e semestre sugerido obrigatórios para concluir' using errcode = '22023'; end if;
  end if;
  insert into public.aproveitamentos(ies_id, oportunidade_id, instituicao_origem, curso_origem, disciplinas, carga_aproveitada, semestre_sugerido, parecer, analisado_por, status, concluida_em)
  values (o.ies_id, o.id, coalesce(trim(d->>'instituicao_origem'), a.instituicao_origem), coalesce(trim(d->>'curso_origem'), a.curso_origem), limpo, carga,
          coalesce(nullif(d->>'semestre_sugerido', '')::int, a.semestre_sugerido), coalesce(nullif(trim(d->>'parecer'), ''), a.parecer), (select auth.uid()),
          case when p_concluir then 'concluida' else 'em_analise' end, case when p_concluir then now() end)
  on conflict (oportunidade_id) do update set instituicao_origem = excluded.instituicao_origem, curso_origem = excluded.curso_origem, disciplinas = excluded.disciplinas,
    carga_aproveitada = excluded.carga_aproveitada, semestre_sugerido = excluded.semestre_sugerido, parecer = excluded.parecer, analisado_por = excluded.analisado_por,
    status = excluded.status, concluida_em = excluded.concluida_em, atualizado_em = now();
  perform privado.auditar(o.ies_id, 'aproveitamento.salvar', 'oportunidade', o.id::text, jsonb_build_object('disciplinas', jsonb_array_length(limpo), 'carga', carga, 'concluida', p_concluir));
  return jsonb_build_object('carga_aproveitada', carga, 'status', case when p_concluir then 'concluida' else 'em_analise' end);
exception when check_violation then raise exception 'Dados inválidos (instituição e curso de origem com 3+ caracteres, semestre 1–12)' using errcode = '22023';
  when not_null_violation then raise exception 'Informe instituição e curso de origem' using errcode = '22023';
end $$;

create or replace function public.rpc_aproveitamento(p_op bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades;
begin
  perform privado.exigir_usuario();
  select * into o from public.oportunidades where id = p_op;
  if not found or not privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro']) then
    perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  return jsonb_build_object('aplicavel', o.forma_ingresso in ('transferencia','segunda_graduacao','reingresso'),
    'pode_analisar', privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, (select papeis from public.matriz_permissoes where operacao = 'aproveitamento.analisar')),
    'analise', (select jsonb_build_object('instituicao_origem', a.instituicao_origem, 'curso_origem', a.curso_origem, 'disciplinas', a.disciplinas, 'status', a.status,
        'carga_aproveitada', a.carga_aproveitada, 'semestre_sugerido', a.semestre_sugerido, 'parecer', a.parecer, 'analisado_por', privado.nome_usuario(a.analisado_por),
        'concluida_em', a.concluida_em) from public.aproveitamentos a where a.oportunidade_id = o.id));
end $$;

create or replace function public.rpc_publico_portal_aproveitamento(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.pessoas;
begin
  p := privado.portal_pessoa(p_token);
  return (select coalesce(jsonb_agg(jsonb_build_object('curso', c.nome || ' · ' || c.turno, 'status', a.status,
      'carga_aproveitada', case when a.status = 'concluida' then a.carga_aproveitada end, 'semestre_sugerido', case when a.status = 'concluida' then a.semestre_sugerido end,
      'disciplinas', case when a.status = 'concluida' then a.disciplinas end, 'parecer', case when a.status = 'concluida' then a.parecer end)), '[]'::jsonb)
    from public.aproveitamentos a join public.oportunidades o on o.id = a.oportunidade_id join public.cursos c on c.id = o.curso_id where o.pessoa_id = p.id);
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.rpc_configurar_banca(bigint, jsonb, int, numeric), public.rpc_avaliar_banca(bigint, jsonb, text), public.rpc_banca(bigint),
  public.rpc_salvar_aproveitamento(bigint, jsonb, boolean), public.rpc_aproveitamento(bigint) to authenticated;
select privado.conceder_publico();

-- ===================== supabase/migrations/20261126000030_onda_c_interna.sql
-- Matrícula 360° — migração 30 (Onda C, partes sem custo): conversas (L21), pendências financeiras (L13), polos e parceiros (L18) e egressos (L20).
--   * L21 Conversas: registro de mensagem RECEBIDA (WhatsApp, e-mail, ligação) colada pela equipe; fila "aguardando resposta" com tempo
--     desde a entrada; a resposta é a interação de saída já existente. Integração real com WhatsApp/SMS continua desligada (custo).
--   * L13 Financeiro: pendências por aluno e competência importadas por planilha (idempotente), negociação registrada, indicadores de
--     inadimplência e bloqueio da rematrícula SOB COMANDO de quem trata (nunca automático). Cobrança real continua desligada.
--   * L18 Polos e parceiros: tipo de unidade (sede, polo próprio, polo parceiro), parceiro e meta de ingressos; painel por unidade.
--     O acesso do parceiro usa o escopo por campus que já existe. Repasse: regra contratual descrita em texto, SEM cálculo de pagamento.
--   * L20 Egressos: registro de conclusão com consentimento de contato e interesses; oferta de pós-graduação ou segunda graduação
--     cria nova oportunidade (deduplicada) só com consentimento.
-- Idempotente.

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('conversa.registrar', 'CRM Educacional', 'Registrar mensagem recebida e ver a fila de respostas', array['gestor','comercial'], 'curso', 'rpc_conversas'),
  ('financeiro.ver',     'Relacionamento Estudantil', 'Ver pendências financeiras e inadimplência', array['gestor','financeiro','secretaria','reitoria'], 'curso', 'rpc_financeiro'),
  ('financeiro.gerir',   'Relacionamento Estudantil', 'Importar pendências, registrar negociação e bloquear rematrícula de inadimplentes', array['gestor','financeiro'], 'ies', 'rpc_importar_pendencias'),
  ('polo.gerir',         'Governança Institucional', 'Cadastrar polos e parceiros e suas metas', array['gestor'], 'ies', 'rpc_salvar_polo'),
  ('polo.ver',           'Central de Inteligência', 'Ver o painel por unidade (sede e polos)', array['gestor','reitoria','coordenador','comercial'], 'curso', 'rpc_polos'),
  ('egresso.gerir',      'Relacionamento Estudantil', 'Registrar conclusão de curso (egresso)', array['gestor','secretaria'], 'curso', 'rpc_registrar_egresso'),
  ('egresso.ofertar',    'Relacionamento Estudantil', 'Ofertar pós-graduação ou segunda graduação a egressos', array['gestor','comercial'], 'curso', 'rpc_ofertar_egresso')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

-- ================================================================ L21 conversas
alter table public.interacoes add column if not exists direcao text not null default 'saida' check (direcao in ('saida','entrada'));

create or replace function public.rpc_registrar_recebida(p_op bigint, p_tipo text, p_texto text, p_recebida_em timestamptz default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; v_id bigint; quando timestamptz := coalesce(p_recebida_em, now());
begin
  o := privado.op_operacao(p_op, 'conversa.registrar');
  if p_tipo not in ('ligacao','whatsapp_manual','email_manual') then raise exception 'Canal inválido' using errcode = '22023'; end if;
  if length(coalesce(trim(p_texto), '')) not between 3 and 1000 then raise exception 'Texto da mensagem recebida obrigatório (3 a 1000 caracteres)' using errcode = '22023'; end if;
  if quando > now() + interval '5 minutes' or quando < now() - interval '30 days' then raise exception 'Data de recebimento inválida' using errcode = '22023'; end if;
  insert into public.interacoes(ies_id, oportunidade_id, tipo, resumo, usuario_id, em, direcao) values (o.ies_id, o.id, p_tipo, trim(p_texto), (select auth.uid()), quando, 'entrada')
  returning id into v_id;
  perform privado.auditar(o.ies_id, 'conversa.recebida', 'oportunidade', o.id::text, jsonb_build_object('interacao_id', v_id, 'tipo', p_tipo));
  return jsonb_build_object('id', v_id);
end $$;

create or replace function public.rpc_conversas(p_ies bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare papeis text[] := (select papeis from public.matriz_permissoes where operacao = 'conversa.registrar');
begin
  perform privado.autorizar(p_ies, 'conversa.registrar');
  return jsonb_build_object('aviso', 'Integração com WhatsApp e SMS desligada: cole aqui a mensagem recebida e responda pelo seu canal; registre a resposta na ficha. A fila mostra quem aguarda resposta.',
    'sla_horas', (select sla_horas from public.ies where id = p_ies),
    'fila', (select coalesce(jsonb_agg(x order by x->>'recebida_em'), '[]'::jsonb) from (
      select jsonb_build_object('oportunidade_id', o.id, 'nome', p.nome, 'curso', c.nome || ' · ' || c.turno, 'etapa', o.etapa, 'responsavel', privado.nome_usuario(o.responsavel_id),
        'tipo', u.tipo, 'texto', u.resumo, 'recebida_em', u.em, 'horas', round(extract(epoch from now() - u.em) / 3600, 1)) x
      from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id join public.cursos c on c.id = o.curso_id
      join lateral (select i.* from public.interacoes i where i.oportunidade_id = o.id order by i.em desc, i.id desc limit 1) u on true
      where o.ies_id = p_ies and u.direcao = 'entrada' and o.etapa not in ('perdido','cancelado') and privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, papeis)) z));
end $$;

-- ================================================================ L13 pendências financeiras
create table if not exists public.pendencias_financeiras (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  oportunidade_id bigint not null references public.oportunidades(id),
  competencia text not null check (competencia ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  valor_centavos int not null check (valor_centavos > 0),
  vencimento date not null,
  situacao text not null check (situacao in ('aberta','paga','negociada','cancelada')),
  acordo text check (length(acordo) <= 1000),
  atualizado_por uuid references public.usuarios(id),
  atualizado_em timestamptz not null default now(),
  unique (oportunidade_id, competencia)
);
create index if not exists pend_fin_ies on public.pendencias_financeiras(ies_id);
create index if not exists pend_fin_usuario on public.pendencias_financeiras(atualizado_por);
alter table public.pendencias_financeiras enable row level security;
revoke all on public.pendencias_financeiras from anon, authenticated;

-- Linhas: { "oportunidade_id" ou "email", "competencia": "2026-11", "valor": "1290,00", "vencimento": "2026-11-10", "situacao": "aberta" }
create or replace function public.rpc_importar_pendencias(p_ies bigint, p_linhas jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare l jsonb; v_op bigint; ok int := 0; rej jsonb := '[]'::jsonb; n int := 0; v_val int;
begin
  perform privado.autorizar(p_ies, 'financeiro.gerir');
  if jsonb_typeof(p_linhas) <> 'array' or jsonb_array_length(p_linhas) > 5000 then raise exception 'Envie até 5000 linhas' using errcode = '22023'; end if;
  for l in select * from jsonb_array_elements(p_linhas) loop
    n := n + 1;
    begin
      if nullif(l->>'oportunidade_id', '') is not null then
        select id into v_op from public.oportunidades where id = (l->>'oportunidade_id')::bigint and ies_id = p_ies and etapa = 'confirmado';
      else
        select o.id into v_op from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id
         where o.ies_id = p_ies and o.etapa = 'confirmado' and p.email = lower(trim(l->>'email')) order by o.confirmada_em desc limit 1;
      end if;
      if v_op is null then raise exception 'Aluno (ingresso efetivo) não encontrado'; end if;
      v_val := round(replace(replace(coalesce(l->>'valor', ''), '.', ''), ',', '.')::numeric * 100);
      insert into public.pendencias_financeiras(ies_id, oportunidade_id, competencia, valor_centavos, vencimento, situacao, atualizado_por)
      values (p_ies, v_op, l->>'competencia', v_val, (l->>'vencimento')::date, coalesce(nullif(l->>'situacao', ''), 'aberta'), (select auth.uid()))
      on conflict (oportunidade_id, competencia) do update set valor_centavos = excluded.valor_centavos, vencimento = excluded.vencimento,
        situacao = excluded.situacao, atualizado_por = excluded.atualizado_por, atualizado_em = now();
      ok := ok + 1;
    exception when others then rej := rej || jsonb_build_object('linha', n, 'motivo', sqlerrm);
    end;
    v_op := null;
  end loop;
  perform privado.auditar(p_ies, 'financeiro.importar', 'ies', p_ies::text, jsonb_build_object('importadas', ok, 'rejeitadas', jsonb_array_length(rej)));
  return jsonb_build_object('importadas', ok, 'rejeitadas', rej);
end $$;

create or replace function public.rpc_negociar_pendencia(p_id bigint, p_situacao text, p_acordo text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare pf public.pendencias_financeiras;
begin
  perform privado.exigir_usuario();
  select * into pf from public.pendencias_financeiras where id = p_id for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(pf.ies_id, 'financeiro.gerir');
  if p_situacao not in ('paga','negociada','cancelada','aberta') then raise exception 'Situação inválida' using errcode = '22023'; end if;
  if length(coalesce(trim(p_acordo), '')) < 5 then raise exception 'Descreva o acordo ou a baixa' using errcode = '22023'; end if;
  update public.pendencias_financeiras set situacao = p_situacao, acordo = trim(p_acordo), atualizado_por = (select auth.uid()), atualizado_em = now() where id = pf.id;
  perform privado.auditar(pf.ies_id, 'financeiro.negociar', 'oportunidade', pf.oportunidade_id::text, jsonb_build_object('competencia', pf.competencia, 'situacao', p_situacao));
  return jsonb_build_object('id', pf.id, 'situacao', p_situacao);
end $$;

create or replace function public.rpc_financeiro(p_ies bigint, p_dias int default 30)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare papeis text[] := (select papeis from public.matriz_permissoes where operacao = 'financeiro.ver');
begin
  perform privado.autorizar(p_ies, 'financeiro.ver');
  return (with vis as (select f.*, o.curso_id, o.responsavel_id, p.nome, c.nome || ' · ' || c.turno curso
                         from public.pendencias_financeiras f join public.oportunidades o on o.id = f.oportunidade_id join public.pessoas p on p.id = o.pessoa_id
                         join public.cursos c on c.id = o.curso_id where f.ies_id = p_ies and privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, papeis)),
               alunos as (select count(*) n from public.oportunidades o where o.ies_id = p_ies and o.etapa = 'confirmado' and privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, papeis))
    select jsonb_build_object('pode_gerir', privado.pode(p_ies, 'financeiro.gerir'), 'dias_atraso', p_dias,
      'aviso', 'Cobrança real desligada. Pendências vêm da planilha do financeiro. O bloqueio da rematrícula é sempre decisão de quem trata.',
      'indicadores', jsonb_build_object('alunos', (select n from alunos),
        'inadimplentes', (select count(distinct oportunidade_id) from vis where situacao = 'aberta' and vencimento < current_date - p_dias),
        'inadimplencia_pct', case when (select n from alunos) = 0 then null else round(100.0 * (select count(distinct oportunidade_id) from vis where situacao = 'aberta' and vencimento < current_date - p_dias) / (select n from alunos), 1) end,
        'em_aberto_centavos', (select coalesce(sum(valor_centavos), 0) from vis where situacao = 'aberta'),
        'negociadas', (select count(*) from vis where situacao = 'negociada')),
      'pendencias', (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'oportunidade_id', v.oportunidade_id, 'nome', v.nome, 'curso', v.curso, 'competencia', v.competencia,
          'valor_centavos', v.valor_centavos, 'vencimento', v.vencimento, 'situacao', v.situacao, 'acordo', v.acordo, 'dias_atraso', greatest(0, current_date - v.vencimento),
          'rematricula_pendente', exists (select 1 from public.rematriculas r join public.campanhas_rematricula k on k.id = r.campanha_id
                                          where r.oportunidade_id = v.oportunidade_id and r.status = 'pendente' and k.status = 'aberta'))
          order by v.situacao = 'aberta' desc, v.vencimento), '[]'::jsonb) from vis v))
    from (select 1) um);
end $$;

-- Bloqueio sob comando: rematrículas pendentes de alunos com pendência aberta vencida há mais de N dias.
create or replace function public.rpc_bloquear_inadimplentes(p_campanha bigint, p_dias int default 30)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c public.campanhas_rematricula; n int;
begin
  perform privado.exigir_usuario();
  select * into c from public.campanhas_rematricula where id = p_campanha;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(c.ies_id, 'financeiro.gerir');
  if c.status <> 'aberta' then raise exception 'Campanha não está aberta' using errcode = '22023'; end if;
  if p_dias < 1 then raise exception 'Dias de atraso inválidos' using errcode = '22023'; end if;
  update public.rematriculas r set status = 'bloqueada', bloqueio_categoria = 'financeiro', tratado_por = (select auth.uid()), atualizado_em = now(),
    motivo = 'Pendência financeira vencida há mais de ' || p_dias || ' dias (bloqueio em lote pelo financeiro)'
   where r.campanha_id = c.id and r.status = 'pendente'
     and exists (select 1 from public.pendencias_financeiras f where f.oportunidade_id = r.oportunidade_id and f.situacao = 'aberta' and f.vencimento < current_date - p_dias);
  get diagnostics n = row_count;
  perform privado.auditar(c.ies_id, 'financeiro.bloquear_lote', 'campanha_rematricula', c.id::text, jsonb_build_object('periodo', c.periodo, 'bloqueadas', n, 'dias', p_dias));
  return jsonb_build_object('bloqueadas', n);
end $$;

-- ================================================================ L18 polos e parceiros
alter table public.campus
  add column if not exists tipo text not null default 'sede' check (tipo in ('sede','polo_proprio','polo_parceiro')),
  add column if not exists parceiro text check (length(parceiro) <= 200),
  add column if not exists regra_repasse text check (length(regra_repasse) <= 2000),
  add column if not exists meta_ingressos int check (meta_ingressos is null or meta_ingressos >= 0);

create or replace function public.rpc_salvar_polo(p_ies bigint, p_campus bigint, p_dados jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare d jsonb := coalesce(p_dados, '{}'::jsonb); v_id bigint;
begin
  perform privado.autorizar(p_ies, 'polo.gerir');
  if coalesce(d->>'tipo', 'sede') = 'polo_parceiro' and length(coalesce(trim(d->>'parceiro'), '')) < 3 then
    raise exception 'Polo parceiro exige o nome do parceiro' using errcode = '22023'; end if;
  update public.campus set tipo = coalesce(d->>'tipo', tipo), parceiro = case when d ? 'parceiro' then nullif(trim(d->>'parceiro'), '') else parceiro end,
    regra_repasse = case when d ? 'regra_repasse' then nullif(trim(d->>'regra_repasse'), '') else regra_repasse end,
    meta_ingressos = case when d ? 'meta_ingressos' then nullif(d->>'meta_ingressos', '')::int else meta_ingressos end
  where id = p_campus and ies_id = p_ies returning id into v_id;
  if v_id is null then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.auditar(p_ies, 'polo.salvar', 'campus', v_id::text, jsonb_build_object('tipo', d->>'tipo', 'parceiro', d->>'parceiro'));
  return jsonb_build_object('id', v_id);
end $$;

create or replace function public.rpc_polos(p_ies bigint, p_coorte text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare papeis text[] := (select papeis from public.matriz_permissoes where operacao = 'polo.ver');
begin
  perform privado.autorizar(p_ies, 'polo.ver');
  return jsonb_build_object('pode_gerir', privado.pode(p_ies, 'polo.gerir'),
    'aviso', 'Repasse a parceiros: a regra contratual aparece como texto; o sistema não calcula pagamento. Receita mensal = soma das propostas aceitas dos ingressos.',
    'unidades', (select coalesce(jsonb_agg(u order by u->>'tipo', u->>'nome'), '[]'::jsonb) from (
      select jsonb_build_object('id', k.id, 'nome', k.nome, 'tipo', k.tipo, 'parceiro', k.parceiro, 'regra_repasse', k.regra_repasse, 'meta_ingressos', k.meta_ingressos,
        'leads', count(o.id), 'inscritos', count(o.id) filter (where o.etapa in ('inscrito','pre_matricula','matricula_comercial','confirmado')),
        'matriculas', count(o.id) filter (where o.etapa in ('matricula_comercial','confirmado')), 'ingressos', count(o.id) filter (where o.etapa = 'confirmado'),
        'conversao_pct', case when count(o.id) = 0 then null else round(100.0 * count(o.id) filter (where o.etapa = 'confirmado') / count(o.id), 1) end,
        'receita_mensal_centavos', (select coalesce(sum(pr.valor_final_centavos), 0) from public.propostas pr join public.oportunidades x on x.id = pr.oportunidade_id
                                     join public.cursos y on y.id = x.curso_id where y.campus_id = k.id and x.etapa = 'confirmado' and pr.status = 'aceita'
                                       and (p_coorte is null or x.coorte = p_coorte))) u
      from public.campus k left join public.cursos c on c.campus_id = k.id
      left join public.oportunidades o on o.curso_id = c.id and (p_coorte is null or o.coorte = p_coorte) and privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, papeis)
      where k.ies_id = p_ies group by k.id) z));
end $$;

-- ================================================================ L20 egressos
create table if not exists public.egressos (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  oportunidade_id bigint not null unique references public.oportunidades(id),
  conclusao date not null,
  consentimento_contato boolean not null default false,
  interesses text[] not null default '{}',
  observacao text check (length(observacao) <= 500),
  registrado_por uuid references public.usuarios(id),
  registrado_em timestamptz not null default now()
);
create index if not exists egressos_ies on public.egressos(ies_id);
create index if not exists egressos_reg on public.egressos(registrado_por);
alter table public.egressos enable row level security;
revoke all on public.egressos from anon, authenticated;
alter table public.oportunidades add column if not exists egresso_origem_id bigint references public.egressos(id);
create index if not exists oportunidades_egresso on public.oportunidades(egresso_origem_id);

create or replace function public.rpc_registrar_egresso(p_op bigint, p_conclusao date, p_consentimento boolean, p_interesses text[] default '{}', p_observacao text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; v_id bigint;
begin
  o := privado.op_operacao(p_op, 'egresso.gerir');
  if o.etapa <> 'confirmado' then raise exception 'Egresso precisa ter sido aluno (ingresso efetivo)' using errcode = '22023'; end if;
  if p_conclusao is null or p_conclusao > current_date or p_conclusao < o.confirmada_em::date then raise exception 'Data de conclusão entre o ingresso e hoje' using errcode = '22023'; end if;
  if exists (select 1 from unnest(coalesce(p_interesses, '{}')) i where i not in ('pos_graduacao','segunda_graduacao','extensao')) then raise exception 'Interesse inválido' using errcode = '22023'; end if;
  insert into public.egressos(ies_id, oportunidade_id, conclusao, consentimento_contato, interesses, observacao, registrado_por)
  values (o.ies_id, o.id, p_conclusao, coalesce(p_consentimento, false), coalesce(p_interesses, '{}'), nullif(trim(p_observacao), ''), (select auth.uid()))
  on conflict (oportunidade_id) do update set conclusao = excluded.conclusao, consentimento_contato = excluded.consentimento_contato, interesses = excluded.interesses,
    observacao = excluded.observacao, registrado_por = excluded.registrado_por, registrado_em = now()
  returning id into v_id;
  perform privado.auditar(o.ies_id, 'egresso.registrar', 'oportunidade', o.id::text, jsonb_build_object('conclusao', p_conclusao, 'consentimento', p_consentimento));
  return jsonb_build_object('id', v_id);
end $$;

create or replace function public.rpc_ofertar_egresso(p_egresso bigint, p_curso bigint, p_coorte text, p_forma text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare e public.egressos; o public.oportunidades; p public.pessoas; r jsonb;
begin
  perform privado.exigir_usuario();
  select * into e from public.egressos where id = p_egresso;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(e.ies_id, 'egresso.ofertar');
  if not e.consentimento_contato then raise exception 'Egresso sem consentimento para contato comercial' using errcode = '22023'; end if;
  if p_forma not in ('pos_graduacao','segunda_graduacao') then raise exception 'Oferta: pós-graduação ou segunda graduação' using errcode = '22023'; end if;
  select * into o from public.oportunidades where id = e.oportunidade_id;
  select * into p from public.pessoas where id = o.pessoa_id;
  if p.anonimizada_em is not null then raise exception 'Titular anonimizado' using errcode = '22023'; end if;
  r := public.rpc_criar_oportunidade(e.ies_id, jsonb_build_object('nome', p.nome, 'email', p.email, 'telefone', p.telefone, 'curso_id', p_curso, 'coorte', p_coorte,
         'forma_ingresso', p_forma, 'base_legal', 'consentimento', 'origem', 'egresso'), 'egresso-' || e.id || '-' || p_curso || '-' || p_coorte);
  if not (r->>'duplicada')::boolean then update public.oportunidades set egresso_origem_id = e.id where id = (r->>'id')::bigint; end if;
  perform privado.auditar(e.ies_id, 'egresso.ofertar', 'oportunidade', r->>'id', jsonb_build_object('egresso', e.id, 'forma', p_forma, 'duplicada', r->'duplicada'));
  return r;
end $$;

create or replace function public.rpc_egressos(p_ies bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare papeis text[] := array['gestor','secretaria','comercial','coordenador','reitoria'];
begin
  perform privado.exigir_usuario();
  if not (privado.pode(p_ies, 'egresso.gerir') or privado.pode(p_ies, 'egresso.ofertar')) then raise exception 'Seu perfil não tem permissão para esta operação' using errcode = '42501'; end if;
  return jsonb_build_object('pode_gerir', privado.pode(p_ies, 'egresso.gerir'), 'pode_ofertar', privado.pode(p_ies, 'egresso.ofertar'),
    'egressos', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'oportunidade_id', o.id, 'nome', p.nome, 'curso', c.nome || ' · ' || c.turno, 'conclusao', e.conclusao,
        'consentimento', e.consentimento_contato, 'interesses', e.interesses, 'observacao', e.observacao,
        'ofertas', (select count(*) from public.oportunidades x where x.egresso_origem_id = e.id),
        'ofertas_convertidas', (select count(*) from public.oportunidades x where x.egresso_origem_id = e.id and x.etapa = 'confirmado')) order by e.conclusao desc), '[]'::jsonb)
      from public.egressos e join public.oportunidades o on o.id = e.oportunidade_id join public.pessoas p on p.id = o.pessoa_id join public.cursos c on c.id = o.curso_id
      where e.ies_id = p_ies and privado.tem_acesso(o.ies_id, o.curso_id, papeis)));
end $$;

do $$ begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'privado' and p.proname = 'mfa_ok') then
    execute 'drop policy if exists mfa_obrigatorio on public.pendencias_financeiras; create policy mfa_obrigatorio on public.pendencias_financeiras as restrictive for all to authenticated using ((select privado.mfa_ok()))';
    execute 'drop policy if exists mfa_obrigatorio on public.egressos; create policy mfa_obrigatorio on public.egressos as restrictive for all to authenticated using ((select privado.mfa_ok()))';
  end if;
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.rpc_registrar_recebida(bigint, text, text, timestamptz), public.rpc_conversas(bigint),
  public.rpc_importar_pendencias(bigint, jsonb), public.rpc_negociar_pendencia(bigint, text, text), public.rpc_financeiro(bigint, int), public.rpc_bloquear_inadimplentes(bigint, int),
  public.rpc_salvar_polo(bigint, bigint, jsonb), public.rpc_polos(bigint, text),
  public.rpc_registrar_egresso(bigint, date, boolean, text[], text), public.rpc_ofertar_egresso(bigint, bigint, text, text), public.rpc_egressos(bigint) to authenticated;
select privado.conceder_publico();

commit;
