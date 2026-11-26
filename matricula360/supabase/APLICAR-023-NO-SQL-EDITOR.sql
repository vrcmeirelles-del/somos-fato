-- Matrícula 360° — migração 23 (Onda A, L12): bolsas, descontos institucionais e financiamento estudantil.
-- Para o SQL Editor do projeto jbimijcvvekomovodfze. Requer as migrações anteriores aplicadas (aplique na ordem 023 → 030).
-- CONFIRA o projeto na URL antes de executar. Idempotente. Transação única. A última linha deve ser commit;
begin;
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

commit;
