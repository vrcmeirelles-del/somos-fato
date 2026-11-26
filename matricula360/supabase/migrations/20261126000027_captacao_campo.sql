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
