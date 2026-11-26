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
