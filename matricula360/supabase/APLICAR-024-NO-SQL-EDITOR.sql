-- Matrícula 360° — migração 24 (Onda A, L14): rematrícula ativa.
-- Para o SQL Editor do projeto jbimijcvvekomovodfze. Requer as migrações anteriores aplicadas (aplique na ordem 023 → 024 → 025 → 026).
-- CONFIRA o projeto na URL antes de executar. Idempotente. Transação única. A última linha deve ser commit;
begin;
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

commit;
