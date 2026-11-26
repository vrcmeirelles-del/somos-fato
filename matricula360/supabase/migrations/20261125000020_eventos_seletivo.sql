-- Matrícula 360° — migração 20 (P4): eventos e visitas (L7) e processo seletivo online (L4).
--   * Eventos (open house, tour, aula experimental, webinar, feira, visita escolar) com vagas, inscrição pelo formulário
--     público ou pela equipe, check-in e conversão (presentes que viraram ingressantes).
--   * Processo seletivo: prova agendada, ENEM, análise curricular ou transferência. Candidatura pelo portal ou pela equipe;
--     agenda com vagas; nota do ENEM declarada e conferida por pessoa; redação enviada pelo portal e corrigida por pessoa.
--     O sistema apenas SUGERE o resultado pela nota mínima; a decisão é humana e o candidato só vê após a divulgação.
-- Idempotente.

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('evento.gerir',     'Marketing e Captação',   'Criar eventos e visitas',                                     array['gestor'], 'ies', 'rpc_salvar_evento'),
  ('evento.operar',    'Marketing e Captação',   'Inscrever oportunidades e registrar presença (check-in)',     array['gestor','comercial','secretaria'], 'curso', 'rpc_checkin'),
  ('seletivo.gerir',   'Conversão e Matrículas', 'Criar processos seletivos e agendas de prova',                array['gestor','secretaria'], 'ies', 'rpc_salvar_processo'),
  ('seletivo.avaliar', 'Conversão e Matrículas', 'Conferir ENEM, corrigir redação e decidir o resultado',       array['gestor','secretaria','coordenador'], 'curso', 'rpc_avaliar_candidatura'),
  ('seletivo.divulgar','Conversão e Matrículas', 'Divulgar o resultado do processo seletivo',                   array['gestor','secretaria'], 'ies', 'rpc_divulgar_resultado')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

create table if not exists public.eventos (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  titulo text not null check (length(titulo) between 3 and 120),
  tipo text not null check (tipo in ('open_house','tour','aula_experimental','webinar','feira','visita_escolar','outro')),
  inicio timestamptz not null,
  fim timestamptz not null,
  local text check (length(local) <= 200),
  online boolean not null default false,
  vagas int check (vagas between 1 and 100000),
  campanha_id bigint references public.campanhas(id),
  status text not null default 'aberto' check (status in ('aberto','encerrado','cancelado')),
  criado_por uuid references public.usuarios(id),
  criado_em timestamptz not null default now(),
  check (fim > inicio)
);
create table if not exists public.inscricoes_evento (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  evento_id bigint not null references public.eventos(id),
  pessoa_id bigint not null references public.pessoas(id),
  oportunidade_id bigint references public.oportunidades(id),
  status text not null default 'inscrito' check (status in ('inscrito','presente','ausente','cancelado')),
  inscrito_em timestamptz not null default now(),
  checkin_em timestamptz,
  checkin_por uuid references public.usuarios(id),
  unique (evento_id, pessoa_id)
);
alter table public.formularios add column if not exists evento_id bigint references public.eventos(id);

create table if not exists public.processos_seletivos (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  coorte text not null check (coorte ~ '^\d{4}\.[12]$'),
  nome text not null check (length(nome) between 3 and 120),
  tipo text not null check (tipo in ('prova_agendada','enem','analise_curricular','transferencia')),
  inscricoes_ate date not null,
  nota_minima numeric(6,2) check (nota_minima between 0 and 1000),
  instrucoes text check (length(instrucoes) <= 3000),
  tema_redacao text check (length(tema_redacao) <= 1000),
  status text not null default 'aberto' check (status in ('aberto','encerrado')),
  resultado_divulgado_em timestamptz,
  criado_por uuid references public.usuarios(id),
  criado_em timestamptz not null default now(),
  unique (ies_id, coorte, nome)
);
create table if not exists public.agendas_prova (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  processo_id bigint not null references public.processos_seletivos(id),
  inicio timestamptz not null,
  local text not null check (length(local) between 2 and 200),
  vagas int not null check (vagas between 1 and 10000)
);
create table if not exists public.candidaturas (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  processo_id bigint not null references public.processos_seletivos(id),
  oportunidade_id bigint not null references public.oportunidades(id),
  agenda_id bigint references public.agendas_prova(id),
  nota_enem numeric(6,2) check (nota_enem between 0 and 1000),
  enem_conferido_por uuid references public.usuarios(id),
  enem_conferido_em timestamptz,
  nota_objetiva numeric(6,2) check (nota_objetiva between 0 and 1000),
  redacao text check (length(redacao) <= 12000),
  redacao_enviada_em timestamptz,
  redacao_nota numeric(6,2) check (redacao_nota between 0 and 1000),
  redacao_parecer text check (length(redacao_parecer) <= 2000),
  corrigida_por uuid references public.usuarios(id),
  resultado text not null default 'pendente' check (resultado in ('pendente','aprovado','reprovado','ausente')),
  resultado_justificativa text check (length(resultado_justificativa) <= 1000),
  resultado_por uuid references public.usuarios(id),
  resultado_em timestamptz,
  criado_em timestamptz not null default now(),
  unique (processo_id, oportunidade_id)
);
create index if not exists eventos_ies on public.eventos(ies_id, inicio);
create index if not exists eventos_campanha on public.eventos(campanha_id);
create index if not exists eventos_criado on public.eventos(criado_por);
create index if not exists insc_evento_ies on public.inscricoes_evento(ies_id);
create index if not exists insc_evento_pessoa on public.inscricoes_evento(pessoa_id);
create index if not exists insc_evento_op on public.inscricoes_evento(oportunidade_id);
create index if not exists insc_evento_checkin on public.inscricoes_evento(checkin_por);
create index if not exists formularios_evento on public.formularios(evento_id);
create index if not exists processos_ies on public.processos_seletivos(ies_id);
create index if not exists processos_criado on public.processos_seletivos(criado_por);
create index if not exists agendas_processo on public.agendas_prova(processo_id);
create index if not exists agendas_ies on public.agendas_prova(ies_id);
create index if not exists candidaturas_ies on public.candidaturas(ies_id);
create index if not exists candidaturas_op on public.candidaturas(oportunidade_id);
create index if not exists candidaturas_agenda on public.candidaturas(agenda_id);
create index if not exists candidaturas_enem on public.candidaturas(enem_conferido_por);
create index if not exists candidaturas_corrigida on public.candidaturas(corrigida_por);
create index if not exists candidaturas_resultado on public.candidaturas(resultado_por);
alter table public.eventos enable row level security;
alter table public.inscricoes_evento enable row level security;
alter table public.processos_seletivos enable row level security;
alter table public.agendas_prova enable row level security;
alter table public.candidaturas enable row level security;
revoke all on public.eventos, public.inscricoes_evento, public.processos_seletivos, public.agendas_prova, public.candidaturas from anon, authenticated;

-- ---------------------------------------------------------------- eventos
create or replace function privado.inscrever_em_evento(p_evento bigint, p_pessoa bigint, p_op bigint) returns void
language plpgsql security definer set search_path = '' as $$
declare e public.eventos;
begin
  if p_evento is null then return; end if;
  select * into e from public.eventos where id = p_evento for update;
  if not found or e.status <> 'aberto' or e.fim < now() then return; end if;
  if e.vagas is not null and (select count(*) from public.inscricoes_evento where evento_id = p_evento and status <> 'cancelado') >= e.vagas then return; end if;
  insert into public.inscricoes_evento(ies_id, evento_id, pessoa_id, oportunidade_id) values (e.ies_id, p_evento, p_pessoa, p_op)
  on conflict (evento_id, pessoa_id) do nothing;
end $$;
revoke execute on function privado.inscrever_em_evento(bigint, bigint, bigint) from public, anon, authenticated;

create or replace function public.rpc_salvar_evento(p_ies bigint, p_dados jsonb, p_id bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id bigint; v_camp bigint := nullif(p_dados->>'campanha_id', '')::bigint;
begin
  perform privado.autorizar(p_ies, 'evento.gerir');
  if v_camp is not null and not exists (select 1 from public.campanhas where id = v_camp and ies_id = p_ies) then raise exception 'Campanha não pertence à IES' using errcode = '22023'; end if;
  if p_id is null then
    insert into public.eventos(ies_id, titulo, tipo, inicio, fim, local, online, vagas, campanha_id, criado_por)
    values (p_ies, trim(p_dados->>'titulo'), p_dados->>'tipo', (p_dados->>'inicio')::timestamptz, (p_dados->>'fim')::timestamptz, nullif(trim(p_dados->>'local'), ''),
            coalesce((p_dados->>'online')::boolean, false), nullif(p_dados->>'vagas', '')::int, v_camp, (select auth.uid())) returning id into v_id;
  else
    update public.eventos set titulo = coalesce(trim(p_dados->>'titulo'), titulo), status = coalesce(p_dados->>'status', status),
           local = coalesce(nullif(trim(p_dados->>'local'), ''), local), vagas = coalesce(nullif(p_dados->>'vagas', '')::int, vagas)
     where id = p_id and ies_id = p_ies returning id into v_id;
    if v_id is null then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  end if;
  perform privado.auditar(p_ies, 'evento.salvar', 'evento', v_id::text, jsonb_build_object('status', p_dados->>'status'));
  return jsonb_build_object('id', v_id);
exception when check_violation or not_null_violation then
  raise exception 'Evento inválido: título, tipo, início e fim (fim depois do início) obrigatórios' using errcode = '22023';
end $$;

create or replace function public.rpc_inscrever_evento(p_evento bigint, p_op bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; e public.eventos;
begin
  o := privado.carregar_op(p_op, (select papeis from public.matriz_permissoes where operacao = 'evento.operar'));
  select * into e from public.eventos where id = p_evento and ies_id = o.ies_id;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if e.status <> 'aberto' or e.fim < now() then raise exception 'Evento encerrado' using errcode = '22023'; end if;
  if e.vagas is not null and (select count(*) from public.inscricoes_evento where evento_id = p_evento and status <> 'cancelado') >= e.vagas then
    raise exception 'Evento sem vagas' using errcode = '22023';
  end if;
  insert into public.inscricoes_evento(ies_id, evento_id, pessoa_id, oportunidade_id) values (o.ies_id, p_evento, o.pessoa_id, p_op) on conflict (evento_id, pessoa_id) do nothing;
  perform privado.auditar(o.ies_id, 'evento.inscrever', 'oportunidade', p_op::text, jsonb_build_object('evento_id', p_evento));
  return jsonb_build_object('evento', p_evento, 'oportunidade', p_op);
end $$;

create or replace function public.rpc_checkin(p_inscricao bigint, p_status text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare i public.inscricoes_evento; e public.eventos;
begin
  perform privado.exigir_usuario();
  select * into i from public.inscricoes_evento where id = p_inscricao for update;
  if not found or not privado.ve_ies(i.ies_id) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(i.ies_id, 'evento.operar');
  select * into e from public.eventos where id = i.evento_id;
  if p_status not in ('presente','ausente','cancelado') then raise exception 'Situação inválida' using errcode = '22023'; end if;
  if p_status in ('presente','ausente') and now() < e.inicio - interval '2 hours' then raise exception 'Presença só a partir do início do evento' using errcode = '22023'; end if;
  update public.inscricoes_evento set status = p_status, checkin_em = case when p_status = 'presente' then now() end, checkin_por = (select auth.uid()) where id = p_inscricao;
  perform privado.auditar(i.ies_id, 'evento.checkin', 'evento', i.evento_id::text, jsonb_build_object('inscricao', p_inscricao, 'status', p_status));
  return jsonb_build_object('id', p_inscricao, 'status', p_status);
end $$;

create or replace function public.rpc_eventos(p_ies bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare pleno boolean;
begin
  perform privado.autorizar(p_ies, 'evento.operar');
  return (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'titulo', e.titulo, 'tipo', e.tipo, 'inicio', e.inicio, 'fim', e.fim, 'local', e.local, 'online', e.online,
      'vagas', e.vagas, 'status', e.status, 'campanha_id', e.campanha_id,
      'inscritos', (select count(*) from public.inscricoes_evento i where i.evento_id = e.id and i.status <> 'cancelado'),
      'presentes', (select count(*) from public.inscricoes_evento i where i.evento_id = e.id and i.status = 'presente'),
      'ingressantes_presentes', (select count(distinct i.pessoa_id) from public.inscricoes_evento i join public.oportunidades o on o.pessoa_id = i.pessoa_id and o.ies_id = e.ies_id
                                  where i.evento_id = e.id and i.status = 'presente' and o.etapa = 'confirmado'),
      'inscricoes', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'nome', p.nome, 'status', i.status, 'oportunidade_id', i.oportunidade_id, 'checkin_em', i.checkin_em) order by p.nome), '[]'::jsonb)
                     from public.inscricoes_evento i join public.pessoas p on p.id = i.pessoa_id
                    where i.evento_id = e.id and (i.oportunidade_id is null or exists (select 1 from public.oportunidades o where o.id = i.oportunidade_id
                          and privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, array['gestor','comercial','secretaria'])))))
      order by e.inicio desc), '[]'::jsonb)
    from public.eventos e where e.ies_id = p_ies);
end $$;

-- ---------------------------------------------------------------- processo seletivo (equipe)
create or replace function public.rpc_salvar_processo(p_ies bigint, p_dados jsonb, p_id bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  perform privado.autorizar(p_ies, 'seletivo.gerir');
  if p_id is null then
    insert into public.processos_seletivos(ies_id, coorte, nome, tipo, inscricoes_ate, nota_minima, instrucoes, tema_redacao, criado_por)
    values (p_ies, p_dados->>'coorte', trim(p_dados->>'nome'), p_dados->>'tipo', (p_dados->>'inscricoes_ate')::date, nullif(p_dados->>'nota_minima', '')::numeric,
            nullif(trim(p_dados->>'instrucoes'), ''), nullif(trim(p_dados->>'tema_redacao'), ''), (select auth.uid())) returning id into v_id;
  else
    update public.processos_seletivos set status = coalesce(p_dados->>'status', status), inscricoes_ate = coalesce((p_dados->>'inscricoes_ate')::date, inscricoes_ate),
           instrucoes = coalesce(nullif(trim(p_dados->>'instrucoes'), ''), instrucoes), tema_redacao = coalesce(nullif(trim(p_dados->>'tema_redacao'), ''), tema_redacao)
     where id = p_id and ies_id = p_ies and resultado_divulgado_em is null returning id into v_id;
    if v_id is null then raise exception 'Processo inexistente ou com resultado já divulgado' using errcode = '22023'; end if;
  end if;
  if p_dados ? 'agenda' then
    insert into public.agendas_prova(ies_id, processo_id, inicio, local, vagas)
    values (p_ies, v_id, (p_dados->'agenda'->>'inicio')::timestamptz, trim(p_dados->'agenda'->>'local'), (p_dados->'agenda'->>'vagas')::int);
  end if;
  perform privado.auditar(p_ies, 'seletivo.salvar', 'processo', v_id::text, jsonb_build_object('tipo', p_dados->>'tipo'));
  return jsonb_build_object('id', v_id);
exception
  when unique_violation then perform privado.erro_http(409, '23505', 'Já existe processo com este nome na coorte');
  when check_violation or not_null_violation then raise exception 'Processo inválido: coorte, nome, tipo, prazo de inscrição; nota mínima e notas entre 0 e 1000; agenda com local e vagas' using errcode = '22023';
end $$;

-- Candidatura (comum a portal e equipe). Coloca a oportunidade em "inscrito" quando ela está em "contato".
create or replace function privado.candidatar(p_processo bigint, p_op bigint, p_agenda bigint, p_nota_enem numeric, p_origem text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare pr public.processos_seletivos; o public.oportunidades; ag public.agendas_prova; v_id bigint;
begin
  select * into o from public.oportunidades where id = p_op;
  select * into pr from public.processos_seletivos where id = p_processo and ies_id = o.ies_id;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if pr.status <> 'aberto' or pr.inscricoes_ate < current_date then raise exception 'Inscrições encerradas' using errcode = '22023'; end if;
  if o.etapa in ('perdido','cancelado','confirmado') then raise exception 'Inscrição encerrada ou já confirmada' using errcode = '22023'; end if;
  if pr.tipo = 'prova_agendada' then
    select * into ag from public.agendas_prova where id = p_agenda and processo_id = p_processo for update;
    if not found then raise exception 'Escolha uma data de prova' using errcode = '22023'; end if;
    if ag.inicio < now() then raise exception 'Data de prova já passou' using errcode = '22023'; end if;
    if (select count(*) from public.candidaturas where agenda_id = ag.id) >= ag.vagas then raise exception 'Data de prova sem vagas' using errcode = '22023'; end if;
  end if;
  if pr.tipo = 'enem' and p_nota_enem is null then raise exception 'Informe a nota do ENEM' using errcode = '22023'; end if;
  insert into public.candidaturas(ies_id, processo_id, oportunidade_id, agenda_id, nota_enem)
  values (o.ies_id, p_processo, p_op, case when pr.tipo = 'prova_agendada' then p_agenda end, p_nota_enem) returning id into v_id;
  if o.etapa = 'contato' then
    update public.oportunidades set etapa = 'inscrito', versao = versao + 1, atualizado_em = now() where id = p_op;
    perform privado.auditar(o.ies_id, 'oportunidade.etapa', 'oportunidade', p_op::text, jsonb_build_object('de', 'contato', 'para', 'inscrito', 'motivo', 'Inscrição no processo ' || pr.nome));
  end if;
  perform privado.auditar(o.ies_id, 'seletivo.candidatar', 'oportunidade', p_op::text, jsonb_build_object('processo', pr.nome, 'origem', p_origem));
  return jsonb_build_object('id', v_id);
exception
  when unique_violation then raise exception 'Já inscrito neste processo' using errcode = '22023';
  when check_violation then raise exception 'Nota do ENEM entre 0 e 1000' using errcode = '22023';
end $$;
revoke execute on function privado.candidatar(bigint, bigint, bigint, numeric, text) from public, anon, authenticated;

create or replace function public.rpc_candidatar(p_processo bigint, p_op bigint, p_agenda bigint default null, p_nota_enem numeric default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform privado.carregar_op(p_op, array['gestor','comercial','secretaria']);
  return privado.candidatar(p_processo, p_op, p_agenda, p_nota_enem, 'equipe');
end $$;

create or replace function public.rpc_avaliar_candidatura(p_candidatura bigint, p_dados jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c public.candidaturas; o public.oportunidades; pr public.processos_seletivos;
begin
  perform privado.exigir_usuario();
  select * into c from public.candidaturas where id = p_candidatura for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  select * into o from public.oportunidades where id = c.oportunidade_id;
  if not privado.tem_acesso(o.ies_id, o.curso_id, (select papeis from public.matriz_permissoes where operacao = 'seletivo.avaliar')) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  select * into pr from public.processos_seletivos where id = c.processo_id;
  if pr.resultado_divulgado_em is not null then raise exception 'Resultado já divulgado: avaliação encerrada' using errcode = '22023'; end if;
  if (p_dados->>'conferir_enem')::boolean then
    if c.nota_enem is null then raise exception 'Sem nota do ENEM declarada' using errcode = '22023'; end if;
    update public.candidaturas set enem_conferido_por = (select auth.uid()), enem_conferido_em = now(),
           nota_enem = coalesce(nullif(p_dados->>'nota_enem', '')::numeric, nota_enem) where id = c.id;
  end if;
  if p_dados ? 'nota_objetiva' then update public.candidaturas set nota_objetiva = (p_dados->>'nota_objetiva')::numeric where id = c.id; end if;
  if p_dados ? 'redacao_nota' then
    if c.redacao is null then raise exception 'Candidato ainda não enviou a redação' using errcode = '22023'; end if;
    if length(coalesce(trim(p_dados->>'redacao_parecer'), '')) < 10 then raise exception 'Parecer da correção obrigatório (10+ caracteres)' using errcode = '22023'; end if;
    update public.candidaturas set redacao_nota = (p_dados->>'redacao_nota')::numeric, redacao_parecer = trim(p_dados->>'redacao_parecer'), corrigida_por = (select auth.uid()) where id = c.id;
  end if;
  if p_dados ? 'resultado' then
    if p_dados->>'resultado' not in ('aprovado','reprovado','ausente') then raise exception 'Resultado inválido' using errcode = '22023'; end if;
    if length(coalesce(trim(p_dados->>'justificativa'), '')) < 5 then raise exception 'Justificativa do resultado obrigatória' using errcode = '22023'; end if;
    if pr.tipo = 'enem' and p_dados->>'resultado' = 'aprovado' and (select enem_conferido_em from public.candidaturas where id = c.id) is null then
      raise exception 'Confira a nota do ENEM antes de aprovar' using errcode = '22023';
    end if;
    update public.candidaturas set resultado = p_dados->>'resultado', resultado_justificativa = trim(p_dados->>'justificativa'), resultado_por = (select auth.uid()), resultado_em = now() where id = c.id;
  end if;
  perform privado.auditar(o.ies_id, 'seletivo.avaliar', 'oportunidade', o.id::text, jsonb_build_object('candidatura', c.id, 'campos', (select jsonb_agg(k) from jsonb_object_keys(p_dados) k)));
  return jsonb_build_object('id', c.id);
exception when check_violation or invalid_text_representation then raise exception 'Notas devem estar entre 0 e 1000' using errcode = '22023';
end $$;

create or replace function public.rpc_divulgar_resultado(p_processo bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare pr public.processos_seletivos; pend int;
begin
  perform privado.exigir_usuario();
  select * into pr from public.processos_seletivos where id = p_processo for update;
  if not found or not privado.ve_ies(pr.ies_id) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(pr.ies_id, 'seletivo.divulgar');
  if pr.resultado_divulgado_em is not null then raise exception 'Resultado já divulgado' using errcode = '22023'; end if;
  select count(*) into pend from public.candidaturas where processo_id = p_processo and resultado = 'pendente';
  if pend > 0 then raise exception 'Há % candidatura(s) sem resultado decidido', pend using errcode = '22023'; end if;
  update public.processos_seletivos set resultado_divulgado_em = now(), status = 'encerrado' where id = p_processo;
  perform privado.auditar(pr.ies_id, 'seletivo.divulgar', 'processo', p_processo::text,
    jsonb_build_object('aprovados', (select count(*) from public.candidaturas where processo_id = p_processo and resultado = 'aprovado'),
                       'total', (select count(*) from public.candidaturas where processo_id = p_processo)));
  return jsonb_build_object('id', p_processo, 'divulgado', true);
end $$;

create or replace function public.rpc_seletivo(p_ies bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if not exists (select 1 from public.cursos c where c.ies_id = p_ies and privado.tem_acesso(p_ies, c.id, array['gestor','secretaria','coordenador','comercial'])) then
    raise exception 'Seu perfil não tem permissão para esta operação' using errcode = '42501';
  end if;
  return jsonb_build_object('pode_gerir', privado.pode(p_ies, 'seletivo.gerir'), 'pode_divulgar', privado.pode(p_ies, 'seletivo.divulgar'),
    'aviso', 'O sistema só sugere o resultado pela nota mínima; a decisão é humana e justificada. Redação corrigida por pessoa. O candidato vê o resultado após a divulgação.',
    'processos', (select coalesce(jsonb_agg(jsonb_build_object('id', pr.id, 'nome', pr.nome, 'tipo', pr.tipo, 'coorte', pr.coorte, 'inscricoes_ate', pr.inscricoes_ate,
      'nota_minima', pr.nota_minima, 'instrucoes', pr.instrucoes, 'tema_redacao', pr.tema_redacao, 'status', pr.status, 'resultado_divulgado_em', pr.resultado_divulgado_em,
      'agendas', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'inicio', a.inicio, 'local', a.local, 'vagas', a.vagas,
                    'ocupadas', (select count(*) from public.candidaturas x where x.agenda_id = a.id)) order by a.inicio), '[]'::jsonb) from public.agendas_prova a where a.processo_id = pr.id),
      'candidaturas', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'oportunidade_id', c.oportunidade_id, 'nome', p.nome, 'curso', cu.nome,
          'agenda', (select a.inicio from public.agendas_prova a where a.id = c.agenda_id), 'nota_enem', c.nota_enem, 'enem_conferido', c.enem_conferido_em is not null,
          'nota_objetiva', c.nota_objetiva, 'redacao_enviada', c.redacao_enviada_em is not null, 'redacao', case when privado.tem_acesso(o.ies_id, o.curso_id, array['gestor','secretaria','coordenador']) then c.redacao end,
          'redacao_nota', c.redacao_nota, 'redacao_parecer', c.redacao_parecer, 'corrigida_por', privado.nome_usuario(c.corrigida_por),
          'resultado', c.resultado, 'justificativa', c.resultado_justificativa, 'resultado_por', privado.nome_usuario(c.resultado_por),
          'sugestao', case when pr.nota_minima is null then null
                           when pr.tipo = 'enem' then case when c.nota_enem is null then null when c.nota_enem >= pr.nota_minima then 'aprovado' else 'reprovado' end
                           else case when c.redacao_nota is null and c.nota_objetiva is null then null
                                     when (coalesce(c.redacao_nota, 0) + coalesce(c.nota_objetiva, 0)) / (case when c.redacao_nota is not null and c.nota_objetiva is not null then 2 else 1 end) >= pr.nota_minima then 'aprovado'
                                     else 'reprovado' end end) order by p.nome), '[]'::jsonb)
        from public.candidaturas c join public.oportunidades o on o.id = c.oportunidade_id join public.pessoas p on p.id = o.pessoa_id join public.cursos cu on cu.id = o.curso_id
       where c.processo_id = pr.id and privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, array['gestor','secretaria','coordenador','comercial'])))
      order by pr.criado_em desc), '[]'::jsonb) from public.processos_seletivos pr where pr.ies_id = p_ies));
end $$;

-- ---------------------------------------------------------------- portal (anon, por token)
create or replace function public.rpc_publico_portal_seletivo(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.pessoas;
begin
  p := privado.portal_pessoa(p_token);
  return jsonb_build_object(
    'processos_abertos', (select coalesce(jsonb_agg(jsonb_build_object('id', pr.id, 'nome', pr.nome, 'tipo', pr.tipo, 'coorte', pr.coorte, 'inscricoes_ate', pr.inscricoes_ate,
        'instrucoes', pr.instrucoes, 'agendas', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'inicio', a.inicio, 'local', a.local,
          'vagas_restantes', a.vagas - (select count(*) from public.candidaturas x where x.agenda_id = a.id)) order by a.inicio), '[]'::jsonb)
          from public.agendas_prova a where a.processo_id = pr.id and a.inicio > now()))), '[]'::jsonb)
      from public.processos_seletivos pr where pr.ies_id = p.ies_id and pr.status = 'aberto' and pr.inscricoes_ate >= current_date),
    'candidaturas', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'processo', pr.nome, 'tipo', pr.tipo, 'curso', cu.nome, 'oportunidade_id', o.id,
        'agenda', (select jsonb_build_object('inicio', a.inicio, 'local', a.local) from public.agendas_prova a where a.id = c.agenda_id),
        'tema_redacao', case when pr.tipo = 'prova_agendada' and c.redacao_enviada_em is null then
                          (select case when now() >= a.inicio and now() <= a.inicio + interval '3 hours' then pr.tema_redacao end from public.agendas_prova a where a.id = c.agenda_id) end,
        'redacao_enviada', c.redacao_enviada_em is not null,
        'resultado', case when pr.resultado_divulgado_em is not null then c.resultado end,
        'resultado_divulgado', pr.resultado_divulgado_em is not null)), '[]'::jsonb)
      from public.candidaturas c join public.processos_seletivos pr on pr.id = c.processo_id join public.oportunidades o on o.id = c.oportunidade_id
      join public.cursos cu on cu.id = o.curso_id where o.pessoa_id = p.id),
    'eventos', (select coalesce(jsonb_agg(jsonb_build_object('titulo', e.titulo, 'tipo', e.tipo, 'inicio', e.inicio, 'local', e.local, 'online', e.online, 'status', i.status) order by e.inicio), '[]'::jsonb)
      from public.inscricoes_evento i join public.eventos e on e.id = i.evento_id where i.pessoa_id = p.id));
end $$;

create or replace function public.rpc_publico_candidatar(p_token text, p_processo bigint, p_op bigint, p_agenda bigint default null, p_nota_enem numeric default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.pessoas;
begin
  p := privado.portal_pessoa(p_token);
  if not exists (select 1 from public.oportunidades where id = p_op and pessoa_id = p.id) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  return privado.candidatar(p_processo, p_op, p_agenda, p_nota_enem, 'portal');
end $$;

-- Redação: só dentro da janela de 3 horas a partir do início da prova agendada; envio único.
create or replace function public.rpc_publico_enviar_redacao(p_token text, p_candidatura bigint, p_texto text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.pessoas; c public.candidaturas; a public.agendas_prova;
begin
  p := privado.portal_pessoa(p_token);
  select c2.* into c from public.candidaturas c2 join public.oportunidades o on o.id = c2.oportunidade_id where c2.id = p_candidatura and o.pessoa_id = p.id for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if c.redacao_enviada_em is not null then raise exception 'Redação já enviada' using errcode = '22023'; end if;
  select * into a from public.agendas_prova where id = c.agenda_id;
  if a.id is null or now() < a.inicio or now() > a.inicio + interval '3 hours' then raise exception 'Fora do horário da prova' using errcode = '22023'; end if;
  if length(coalesce(trim(p_texto), '')) not between 200 and 12000 then raise exception 'A redação deve ter entre 200 e 12000 caracteres' using errcode = '22023'; end if;
  update public.candidaturas set redacao = trim(p_texto), redacao_enviada_em = now() where id = c.id;
  perform privado.auditar(c.ies_id, 'seletivo.redacao', 'oportunidade', c.oportunidade_id::text, jsonb_build_object('candidatura', c.id, 'caracteres', length(trim(p_texto))));
  return jsonb_build_object('id', c.id, 'enviada', true);
end $$;

-- ---------------------------------------------------------------- formulário público com evento
create or replace function public.rpc_publico_inscrever(p_slug text, p_dados jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare f public.formularios; v_origem text := privado.origem_hash(); v_email text := nullif(lower(trim(p_dados->>'email')), '');
  v_tel text := nullif(regexp_replace(coalesce(p_dados->>'telefone', ''), '\D', '', 'g'), ''); v_curso bigint := nullif(p_dados->>'curso_id', '')::bigint;
  v_nome text := trim(coalesce(p_dados->>'nome', '')); v_pessoa public.pessoas; v_op public.oportunidades; v_resp uuid; v_canal text; v_sla int;
  v_ehash text; v_token text; neutra constant jsonb := jsonb_build_object('status', 'recebida', 'mensagem', 'Inscrição recebida. A equipe da instituição entrará em contato.');
begin
  select * into f from public.formularios where slug = lower(p_slug) and ativo;
  if not found or not exists (select 1 from public.ies where id = f.ies_id and status = 'ativa') then perform privado.erro_http(404, 'P0002', 'Formulário não encontrado'); end if;
  v_ehash := case when v_email is null then null else encode(sha256(convert_to(v_email, 'UTF8')), 'hex') end;
  -- campo-isca preenchido: robô. Resposta neutra, nada é criado.
  if coalesce(p_dados->>'site', '') <> '' then
    insert into public.inscricoes_publicas(formulario_id, ies_id, origem_hash, resultado) values (f.id, f.ies_id, v_origem, 'isca');
    return neutra;
  end if;
  if coalesce((p_dados->>'tempo_ms')::bigint, 0) < 3000 then
    insert into public.inscricoes_publicas(formulario_id, ies_id, origem_hash, resultado) values (f.id, f.ies_id, v_origem, 'rapida');
    raise exception 'Preenchimento muito rápido. Revise os dados e envie novamente.' using errcode = '22023';
  end if;
  if (select count(*) from public.inscricoes_publicas where origem_hash = v_origem and criado_em > now() - interval '10 minutes') >= 5
     or (select count(*) from public.inscricoes_publicas where formulario_id = f.id and criado_em > now() - interval '1 hour') >= 300
     or (v_ehash is not null and (select count(*) from public.inscricoes_publicas where email_hash = v_ehash and criado_em > now() - interval '1 day') >= 3) then
    insert into public.inscricoes_publicas(formulario_id, ies_id, origem_hash, email_hash, resultado) values (f.id, f.ies_id, v_origem, v_ehash, 'limite');
    perform privado.erro_http(429, '54000', 'Muitas tentativas. Aguarde alguns minutos.');
  end if;
  if coalesce((p_dados->>'aceite')::boolean, false) is not true or coalesce((p_dados->>'versao_consentimento')::int, -1) <> f.versao_consentimento then
    raise exception 'É preciso aceitar o termo de consentimento vigente' using errcode = '22023';
  end if;
  if length(v_nome) not between 3 and 120 then raise exception 'Informe seu nome completo' using errcode = '22023'; end if;
  if v_email is null or v_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' then raise exception 'Informe um e-mail válido' using errcode = '22023'; end if;
  if v_tel is not null and length(v_tel) not between 10 and 13 then raise exception 'Telefone inválido' using errcode = '22023'; end if;
  if v_curso is null or not (v_curso = any (f.cursos)) then raise exception 'Escolha um dos cursos do formulário' using errcode = '22023'; end if;

  select * into v_pessoa from public.pessoas where ies_id = f.ies_id and ((email is not null and email = v_email) or (v_tel is not null and telefone = v_tel)) limit 1 for update;
  if found then
    -- Pessoa já cadastrada: registra novo consentimento só se ela não tiver opt-out; não emite link (evita acesso por terceiros).
    update public.pessoas set consentimento_versao = f.versao_consentimento, consentimento_em = now(), consentimento_hash = encode(sha256(convert_to(f.texto_consentimento, 'UTF8')), 'hex')
     where id = v_pessoa.id and anonimizada_em is null;
    select * into v_op from public.oportunidades where pessoa_id = v_pessoa.id and curso_id = v_curso and coorte = f.coorte;
    if found then
      insert into public.inscricoes_publicas(formulario_id, ies_id, origem_hash, email_hash, resultado, oportunidade_id) values (f.id, f.ies_id, v_origem, v_ehash, 'duplicada', v_op.id);
      perform privado.inscrever_em_evento(f.evento_id, v_pessoa.id, v_op.id);
      return neutra;
    end if;
  else
    insert into public.pessoas(ies_id, nome, email, telefone, base_legal, origem, consentimento_versao, consentimento_em, consentimento_hash)
    values (f.ies_id, v_nome, v_email, v_tel, 'consentimento', 'formulário: ' || f.titulo, f.versao_consentimento, now(),
            encode(sha256(convert_to(f.texto_consentimento, 'UTF8')), 'hex')) returning * into v_pessoa;
    v_token := privado.emitir_acesso(v_pessoa.id, null);
  end if;
  v_resp := privado.distribuir(f.ies_id, v_curso);
  insert into public.oportunidades(ies_id, curso_id, pessoa_id, forma_ingresso, coorte, responsavel_id, campanha_id)
  values (f.ies_id, v_curso, v_pessoa.id, f.forma_ingresso, f.coorte, v_resp, f.campanha_id) returning * into v_op;
  v_canal := case when not v_pessoa.optout_whatsapp and v_pessoa.telefone is not null then 'whatsapp'
                  when not v_pessoa.optout_email and v_pessoa.email is not null then 'email'
                  when not v_pessoa.optout_telefone and v_pessoa.telefone is not null then 'telefone' end;
  if v_canal is not null then
    select sla_horas into v_sla from public.ies where id = f.ies_id;
    insert into public.tarefas(ies_id, oportunidade_id, tipo, canal, responsavel_id, vence_em) values (f.ies_id, v_op.id, 'primeiro_contato', v_canal, v_resp, now() + make_interval(hours => v_sla));
  end if;
  perform privado.auditar(f.ies_id, 'oportunidade.criar', 'oportunidade', v_op.id::text,
    jsonb_build_object('curso_id', v_curso, 'forma_ingresso', f.forma_ingresso, 'coorte', f.coorte, 'origem', 'formulário público', 'formulario_id', f.id,
                       'campanha_id', f.campanha_id, 'consentimento_versao', f.versao_consentimento, 'responsavel_id', v_resp));
  insert into public.inscricoes_publicas(formulario_id, ies_id, origem_hash, email_hash, resultado, oportunidade_id) values (f.id, f.ies_id, v_origem, v_ehash, 'criada', v_op.id);
  perform privado.inscrever_em_evento(f.evento_id, v_pessoa.id, v_op.id);
  return neutra || case when v_token is not null then jsonb_build_object('portal', v_token) else '{}'::jsonb end;
end $$;

create or replace function public.rpc_vincular_evento_formulario(p_formulario bigint, p_evento bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare f public.formularios;
begin
  perform privado.exigir_usuario();
  select * into f from public.formularios where id = p_formulario;
  if not found or not privado.ve_ies(f.ies_id) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(f.ies_id, 'formulario.gerir');
  if p_evento is not null and not exists (select 1 from public.eventos where id = p_evento and ies_id = f.ies_id) then raise exception 'Evento não pertence à IES' using errcode = '22023'; end if;
  update public.formularios set evento_id = p_evento where id = p_formulario;
  perform privado.auditar(f.ies_id, 'formulario.evento', 'formulario', p_formulario::text, jsonb_build_object('evento_id', p_evento));
  return jsonb_build_object('id', p_formulario, 'evento_id', p_evento);
end $$;


revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.rpc_salvar_evento(bigint, jsonb, bigint), public.rpc_inscrever_evento(bigint, bigint), public.rpc_checkin(bigint, text), public.rpc_eventos(bigint),
  public.rpc_salvar_processo(bigint, jsonb, bigint), public.rpc_candidatar(bigint, bigint, bigint, numeric), public.rpc_avaliar_candidatura(bigint, jsonb),
  public.rpc_divulgar_resultado(bigint), public.rpc_seletivo(bigint), public.rpc_vincular_evento_formulario(bigint, bigint)
to authenticated;
select privado.conceder_publico();
