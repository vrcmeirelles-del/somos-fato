-- Matrícula 360° — migração 15: Recuperação e Aceleração (E07) e MAIM Recovery. Bíblia v0.2 §2, §5 e §7.
--   * Elegibilidade (regra recovery-v1): perdida há pelo menos a carência e no máximo 730 dias; base legal que permite
--     novo contato (consentimento ou legítimo interesse); titular não anonimizado; ao menos um canal sem opt-out;
--     sem oportunidade aberta da mesma pessoa no mesmo curso.
--   * Protocolos próprios (Bíblia §7): tipo, responsável, prazo, checklist, meta, custo, resultado.
--   * Reativação preserva o histórico: mesma coorte → transição oficial perdido → contato (auditada);
--     outra coorte → nova oportunidade vinculada à de origem. Tarefa de recuperação para o responsável.
--   * Sprints com entregas, impedimentos e reavaliação obrigatória no encerramento.
-- Nada é enviado: contatos são registrados manualmente. Idempotente.

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('recuperacao.ver',      'Recuperação e Aceleração', 'Ver protocolos, sprints e resultados (atendente: só os itens atribuídos a si)', array['gestor','reitoria','coordenador','comercial'], 'curso', 'rpc_recuperacao'),
  ('recuperacao.gerir',    'Recuperação e Aceleração', 'Criar protocolos e sprints, selecionar a base elegível e atribuir', array['gestor'], 'ies', 'rpc_salvar_protocolo'),
  ('recuperacao.executar', 'Recuperação e Aceleração', 'Registrar contato, reativar ou descartar item atribuído',      array['gestor','comercial'], 'curso', 'rpc_tratar_recuperacao')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

create table if not exists public.sprints (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  nome text not null check (length(nome) between 3 and 100),
  objetivo text not null check (length(objetivo) between 3 and 400),
  inicio date not null,
  fim date not null,
  status text not null default 'planejada' check (status in ('planejada','em_andamento','encerrada')),
  reavaliacao text check (length(reavaliacao) <= 2000),
  criado_por uuid references public.usuarios(id),
  criado_em timestamptz not null default now(),
  check (fim >= inicio)
);
create table if not exists public.sprint_itens (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  sprint_id bigint not null references public.sprints(id),
  entrega text not null check (length(entrega) between 3 and 200),
  responsavel text not null check (length(responsavel) between 2 and 120),
  status text not null default 'a_fazer' check (status in ('a_fazer','fazendo','feito','impedido')),
  impedimento text check (length(impedimento) <= 400),
  atualizado_em timestamptz not null default now(),
  check (status <> 'impedido' or length(coalesce(impedimento, '')) >= 3)
);
create table if not exists public.protocolos (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  sprint_id bigint references public.sprints(id),
  nome text not null check (length(nome) between 3 and 100),
  tipo text not null check (tipo in ('recuperacao_base','reingresso','oferta_educacional','convenio','webinar','evento','indicacao','embaixadores','prospeccao_autorizada')),
  responsavel text not null check (length(responsavel) between 2 and 120),
  prazo date not null,
  checklist jsonb not null default '[]'::jsonb check (jsonb_typeof(checklist) = 'array'),
  meta int not null check (meta between 1 and 100000),
  custo_centavos bigint not null default 0 check (custo_centavos >= 0),
  coorte_destino text not null check (coorte_destino ~ '^\d{4}\.[12]$'),
  carencia_dias int not null default 30 check (carencia_dias between 0 and 365),
  status text not null default 'planejado' check (status in ('planejado','em_execucao','concluido','cancelado')),
  resultado text check (length(resultado) <= 2000),
  criado_por uuid references public.usuarios(id),
  criado_em timestamptz not null default now(),
  unique (ies_id, nome)
);
create table if not exists public.recuperacoes (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  protocolo_id bigint not null references public.protocolos(id),
  oportunidade_origem_id bigint not null references public.oportunidades(id),
  oportunidade_nova_id bigint references public.oportunidades(id),
  atribuido_a uuid references public.usuarios(id),
  status text not null default 'selecionada' check (status in ('selecionada','contatada','reativada','descartada')),
  observacao text check (length(observacao) <= 500),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (protocolo_id, oportunidade_origem_id)
);
alter table public.oportunidades add column if not exists recuperada_de bigint references public.oportunidades(id);

create index if not exists sprints_ies on public.sprints(ies_id);
create index if not exists sprints_criado on public.sprints(criado_por);
create index if not exists sprint_itens_sprint on public.sprint_itens(sprint_id);
create index if not exists sprint_itens_ies on public.sprint_itens(ies_id);
create index if not exists protocolos_ies on public.protocolos(ies_id);
create index if not exists protocolos_sprint on public.protocolos(sprint_id);
create index if not exists protocolos_criado on public.protocolos(criado_por);
create index if not exists recuperacoes_protocolo on public.recuperacoes(protocolo_id);
create index if not exists recuperacoes_origem on public.recuperacoes(oportunidade_origem_id);
create index if not exists recuperacoes_nova on public.recuperacoes(oportunidade_nova_id);
create index if not exists recuperacoes_atribuido on public.recuperacoes(atribuido_a);
create index if not exists recuperacoes_ies on public.recuperacoes(ies_id);
create index if not exists oportunidades_recuperada on public.oportunidades(recuperada_de);

alter table public.sprints enable row level security;
alter table public.sprint_itens enable row level security;
alter table public.protocolos enable row level security;
alter table public.recuperacoes enable row level security;
revoke all on public.sprints, public.sprint_itens, public.protocolos, public.recuperacoes from anon, authenticated;

-- ---------------------------------------------------------------- elegibilidade (recovery-v1)
create or replace function privado.perdida_em(p_op bigint) returns timestamptz
language sql stable security definer set search_path = '' as $$
  select coalesce((select max(a.em) from public.auditoria a where a.entidade = 'oportunidade' and a.entidade_id = p_op::text
                     and a.acao = 'oportunidade.etapa' and a.dados->>'para' = 'perdido'),
                  (select atualizado_em from public.oportunidades where id = p_op));
$$;
revoke execute on function privado.perdida_em(bigint) from public, anon, authenticated;

create or replace function privado.motivo_inelegivel(p_op bigint, p_carencia int) returns text
language plpgsql stable security definer set search_path = '' as $$
declare o public.oportunidades; p public.pessoas; dias numeric;
begin
  select * into o from public.oportunidades where id = p_op;
  if o.etapa <> 'perdido' then return 'Oportunidade não está perdida'; end if;
  select * into p from public.pessoas where id = o.pessoa_id;
  if p.anonimizada_em is not null then return 'Titular anonimizado (LGPD)'; end if;
  if p.base_legal not in ('consentimento','legitimo_interesse') then return 'Base legal não permite novo contato após a perda'; end if;
  if (p.optout_email or p.email is null) and (p.optout_whatsapp or p.telefone is null) and (p.optout_telefone or p.telefone is null) then
    return 'Sem canal disponível (opt-out ou contato ausente)';
  end if;
  dias := extract(epoch from now() - privado.perdida_em(p_op)) / 86400;
  if dias < p_carencia then return format('Em carência: perdida há %s dia(s); mínimo %s', floor(dias), p_carencia); end if;
  if dias > 730 then return 'Perdida há mais de 2 anos'; end if;
  if exists (select 1 from public.oportunidades x where x.pessoa_id = o.pessoa_id and x.curso_id = o.curso_id and x.id <> o.id
             and x.etapa not in ('perdido','cancelado','confirmado')) then
    return 'Já existe oportunidade aberta da mesma pessoa neste curso';
  end if;
  return null;
end $$;
revoke execute on function privado.motivo_inelegivel(bigint, int) from public, anon, authenticated;

-- Base perdida com a avaliação de elegibilidade (gestor). Contato mascarado: a seleção não precisa dele.
create or replace function public.rpc_recuperaveis(p_ies bigint, p_carencia int default 30, p_motivo text default null, p_curso bigint default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.autorizar(p_ies, 'recuperacao.gerir');
  if p_carencia not between 0 and 365 then raise exception 'Carência entre 0 e 365 dias' using errcode = '22023'; end if;
  return (select coalesce(jsonb_agg(x.j order by x.elegivel desc, x.perdida desc), '[]'::jsonb) from (
    select privado.motivo_inelegivel(o.id, p_carencia) is null as elegivel, privado.perdida_em(o.id) as perdida,
      jsonb_build_object('id', o.id, 'nome', p.nome, 'curso', c.nome || ' · ' || c.turno, 'coorte', o.coorte, 'forma_ingresso', o.forma_ingresso,
        'motivo_perda', o.motivo_perda, 'perdida_em', privado.perdida_em(o.id),
        'dias_desde_perda', floor(extract(epoch from now() - privado.perdida_em(o.id)) / 86400),
        'elegivel', privado.motivo_inelegivel(o.id, p_carencia) is null, 'motivo_inelegivel', privado.motivo_inelegivel(o.id, p_carencia),
        'em_protocolo', exists (select 1 from public.recuperacoes r where r.oportunidade_origem_id = o.id and r.status in ('selecionada','contatada'))) as j
      from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id join public.cursos c on c.id = o.curso_id
     where o.ies_id = p_ies and o.etapa = 'perdido' and (p_curso is null or o.curso_id = p_curso)
       and (p_motivo is null or o.motivo_perda ilike '%' || p_motivo || '%')
     limit 500) x);
end $$;

-- ---------------------------------------------------------------- protocolos e sprints
create or replace function public.rpc_salvar_protocolo(p_ies bigint, p_dados jsonb, p_id bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id bigint; v_sprint bigint := nullif(p_dados->>'sprint_id', '')::bigint;
begin
  perform privado.autorizar(p_ies, 'recuperacao.gerir');
  if v_sprint is not null and not exists (select 1 from public.sprints where id = v_sprint and ies_id = p_ies) then
    raise exception 'Sprint não pertence à IES' using errcode = '22023';
  end if;
  if p_id is null then
    insert into public.protocolos(ies_id, sprint_id, nome, tipo, responsavel, prazo, checklist, meta, custo_centavos, coorte_destino, carencia_dias, criado_por)
    values (p_ies, v_sprint, trim(p_dados->>'nome'), p_dados->>'tipo', trim(p_dados->>'responsavel'), (p_dados->>'prazo')::date,
            coalesce(p_dados->'checklist', '[]'::jsonb), (p_dados->>'meta')::int, coalesce((p_dados->>'custo_centavos')::bigint, 0),
            p_dados->>'coorte_destino', coalesce((p_dados->>'carencia_dias')::int, 30), (select auth.uid()))
    returning id into v_id;
    perform privado.auditar(p_ies, 'protocolo.criar', 'protocolo', v_id::text, jsonb_build_object('tipo', p_dados->>'tipo'));
  else
    update public.protocolos set
      sprint_id = case when p_dados ? 'sprint_id' then v_sprint else sprint_id end,
      responsavel = coalesce(trim(p_dados->>'responsavel'), responsavel), prazo = coalesce((p_dados->>'prazo')::date, prazo),
      checklist = coalesce(p_dados->'checklist', checklist), meta = coalesce((p_dados->>'meta')::int, meta),
      custo_centavos = coalesce((p_dados->>'custo_centavos')::bigint, custo_centavos),
      status = coalesce(p_dados->>'status', status), resultado = coalesce(nullif(trim(p_dados->>'resultado'), ''), resultado)
     where id = p_id and ies_id = p_ies returning id into v_id;
    if v_id is null then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
    if p_dados->>'status' = 'concluido' and not exists (select 1 from public.protocolos where id = v_id and length(coalesce(resultado, '')) >= 3) then
      raise exception 'Registre o resultado antes de concluir o protocolo' using errcode = '22023';
    end if;
    perform privado.auditar(p_ies, 'protocolo.editar', 'protocolo', v_id::text, jsonb_build_object('status', p_dados->>'status'));
  end if;
  return jsonb_build_object('id', v_id);
exception
  when unique_violation then perform privado.erro_http(409, '23505', 'Já existe protocolo com este nome');
  when check_violation or not_null_violation then
    raise exception 'Protocolo inválido: confira tipo, responsável, prazo, meta (1 a 100000), coorte de destino e carência (0 a 365 dias)' using errcode = '22023';
end $$;

-- Seleciona oportunidades elegíveis para o protocolo e atribui (padrão: responsável original, se ainda ativo; senão distribuição).
create or replace function public.rpc_selecionar_recuperacao(p_protocolo bigint, p_ops bigint[], p_atribuir uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare pr public.protocolos; o public.oportunidades; v_resp uuid; n_ok int := 0; recusadas jsonb := '[]'::jsonb; mot text; op bigint;
begin
  perform privado.exigir_usuario();
  select * into pr from public.protocolos where id = p_protocolo;
  if not found or not privado.ve_ies(pr.ies_id) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(pr.ies_id, 'recuperacao.gerir');
  if pr.status in ('concluido','cancelado') then raise exception 'Protocolo encerrado' using errcode = '22023'; end if;
  if cardinality(p_ops) not between 1 and 500 then raise exception 'Selecione de 1 a 500 oportunidades' using errcode = '22023'; end if;
  foreach op in array p_ops loop
    select * into o from public.oportunidades where id = op and ies_id = pr.ies_id;
    if not found then recusadas := recusadas || jsonb_build_object('id', op, 'motivo', 'Não encontrada'); continue; end if;
    mot := privado.motivo_inelegivel(op, pr.carencia_dias);
    if mot is not null then recusadas := recusadas || jsonb_build_object('id', op, 'motivo', mot); continue; end if;
    v_resp := coalesce(p_atribuir,
      case when exists (select 1 from public.escopos e join public.usuarios u on u.id = e.usuario_id where e.usuario_id = o.responsavel_id and e.ies_id = o.ies_id
                         and e.papel = 'comercial' and e.revogado_em is null and u.revogado_em is null and privado.escopo_cobre(e.abrangencia, e.campus_id, e.curso_id, o.curso_id))
           then o.responsavel_id else privado.distribuir(o.ies_id, o.curso_id) end);
    if p_atribuir is not null and not exists (select 1 from public.escopos e join public.usuarios u on u.id = e.usuario_id where e.usuario_id = p_atribuir and e.ies_id = o.ies_id
                         and e.papel = 'comercial' and e.revogado_em is null and u.revogado_em is null and privado.escopo_cobre(e.abrangencia, e.campus_id, e.curso_id, o.curso_id)) then
      recusadas := recusadas || jsonb_build_object('id', op, 'motivo', 'Atendente sem escopo comercial neste curso'); continue;
    end if;
    insert into public.recuperacoes(ies_id, protocolo_id, oportunidade_origem_id, atribuido_a) values (pr.ies_id, p_protocolo, op, v_resp)
      on conflict (protocolo_id, oportunidade_origem_id) do nothing;
    if found then n_ok := n_ok + 1; else recusadas := recusadas || jsonb_build_object('id', op, 'motivo', 'Já está neste protocolo'); end if;
  end loop;
  if pr.status = 'planejado' and n_ok > 0 then update public.protocolos set status = 'em_execucao' where id = p_protocolo; end if;
  perform privado.auditar(pr.ies_id, 'recuperacao.selecionar', 'protocolo', p_protocolo::text, jsonb_build_object('selecionadas', n_ok, 'recusadas', jsonb_array_length(recusadas)));
  return jsonb_build_object('selecionadas', n_ok, 'recusadas', recusadas);
end $$;

-- Tratamento do item pelo atendente atribuído (ou gestor): contatada, reativada ou descartada.
create or replace function public.rpc_tratar_recuperacao(p_item bigint, p_acao text, p_observacao text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.recuperacoes; pr public.protocolos; o public.oportunidades; v_nova bigint; mot text; gestor boolean;
begin
  perform privado.exigir_usuario();
  select * into r from public.recuperacoes where id = p_item for update;
  if not found or not privado.ve_ies(r.ies_id) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  select * into o from public.oportunidades where id = r.oportunidade_origem_id for update;
  gestor := privado.tem_acesso(o.ies_id, o.curso_id, array['gestor']);
  if not gestor and r.atribuido_a is distinct from (select auth.uid()) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if not privado.tem_acesso(o.ies_id, o.curso_id, array['gestor','comercial']) then
    raise exception 'Seu perfil não tem permissão para esta operação' using errcode = '42501';
  end if;
  select * into pr from public.protocolos where id = r.protocolo_id;
  if r.status in ('reativada','descartada') then raise exception 'Item já encerrado' using errcode = '22023'; end if;
  if p_acao = 'contatada' then
    if length(coalesce(trim(p_observacao), '')) < 3 then raise exception 'Registre o resumo do contato' using errcode = '22023'; end if;
    update public.recuperacoes set status = 'contatada', observacao = trim(p_observacao), atualizado_em = now() where id = p_item;
  elsif p_acao = 'descartada' then
    if length(coalesce(trim(p_observacao), '')) < 3 then raise exception 'Motivo do descarte obrigatório' using errcode = '22023'; end if;
    update public.recuperacoes set status = 'descartada', observacao = trim(p_observacao), atualizado_em = now() where id = p_item;
  elsif p_acao = 'reativar' then
    mot := privado.motivo_inelegivel(o.id, 0);  -- revalida no momento da reativação (opt-out, anonimização, duplicidade)
    if mot is not null then raise exception 'Reativação bloqueada: %', mot using errcode = '22023'; end if;
    if o.coorte = pr.coorte_destino then
      -- Mesma coorte: transição oficial perdido → contato, auditada como movimento de etapa.
      update public.oportunidades set etapa = 'contato', responsavel_id = coalesce(r.atribuido_a, responsavel_id), versao = versao + 1, atualizado_em = now() where id = o.id;
      perform privado.auditar(o.ies_id, 'oportunidade.etapa', 'oportunidade', o.id::text,
        jsonb_build_object('de', 'perdido', 'para', 'contato', 'motivo', 'Reativação pelo protocolo ' || pr.nome));
      v_nova := o.id;
    else
      insert into public.oportunidades(ies_id, curso_id, pessoa_id, forma_ingresso, coorte, etapa, responsavel_id, recuperada_de)
      values (o.ies_id, o.curso_id, o.pessoa_id, o.forma_ingresso, pr.coorte_destino, 'contato', coalesce(r.atribuido_a, privado.distribuir(o.ies_id, o.curso_id)), o.id)
      returning id into v_nova;
      perform privado.auditar(o.ies_id, 'oportunidade.criar', 'oportunidade', v_nova::text,
        jsonb_build_object('curso_id', o.curso_id, 'forma_ingresso', o.forma_ingresso, 'coorte', pr.coorte_destino, 'origem', 'recuperação', 'recuperada_de', o.id));
    end if;
    insert into public.tarefas(ies_id, oportunidade_id, tipo, canal, responsavel_id, vence_em, descricao)
    values (o.ies_id, v_nova, 'recuperacao', null, coalesce(r.atribuido_a, (select responsavel_id from public.oportunidades where id = v_nova)),
            now() + interval '2 days', 'Retomar contato (protocolo ' || pr.nome || ')');
    update public.recuperacoes set status = 'reativada', oportunidade_nova_id = v_nova, observacao = coalesce(nullif(trim(p_observacao), ''), observacao), atualizado_em = now() where id = p_item;
  else
    raise exception 'Ação inválida' using errcode = '22023';
  end if;
  perform privado.auditar(r.ies_id, 'recuperacao.' || p_acao, 'protocolo', r.protocolo_id::text, jsonb_build_object('item', p_item, 'oportunidade', o.id, 'nova', v_nova));
  return jsonb_build_object('id', p_item, 'acao', p_acao, 'oportunidade', v_nova);
exception when unique_violation then
  raise exception 'Reativação bloqueada: já existe oportunidade desta pessoa neste curso na coorte de destino' using errcode = '22023';
end $$;

create or replace function public.rpc_salvar_sprint(p_ies bigint, p_dados jsonb, p_id bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id bigint; s public.sprints;
begin
  perform privado.autorizar(p_ies, 'recuperacao.gerir');
  if p_id is null then
    insert into public.sprints(ies_id, nome, objetivo, inicio, fim, criado_por)
    values (p_ies, trim(p_dados->>'nome'), trim(p_dados->>'objetivo'), (p_dados->>'inicio')::date, (p_dados->>'fim')::date, (select auth.uid())) returning id into v_id;
    perform privado.auditar(p_ies, 'sprint.criar', 'sprint', v_id::text);
    return jsonb_build_object('id', v_id);
  end if;
  select * into s from public.sprints where id = p_id and ies_id = p_ies for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if s.status = 'encerrada' then raise exception 'Sprint encerrada' using errcode = '22023'; end if;
  if p_dados->>'status' = 'encerrada' and length(coalesce(trim(p_dados->>'reavaliacao'), '')) < 10 then
    raise exception 'Reavaliação obrigatória para encerrar a sprint (o que funcionou, o que não funcionou, próximos passos)' using errcode = '22023';
  end if;
  update public.sprints set status = coalesce(p_dados->>'status', status), reavaliacao = coalesce(nullif(trim(p_dados->>'reavaliacao'), ''), reavaliacao) where id = p_id;
  perform privado.auditar(p_ies, 'sprint.editar', 'sprint', p_id::text, jsonb_build_object('status', p_dados->>'status'));
  return jsonb_build_object('id', p_id);
exception when check_violation or not_null_violation then
  raise exception 'Sprint inválida: nome, objetivo e datas obrigatórios; fim não anterior ao início' using errcode = '22023';
end $$;

create or replace function public.rpc_salvar_item_sprint(p_sprint bigint, p_dados jsonb, p_id bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare s public.sprints; v_id bigint;
begin
  perform privado.exigir_usuario();
  select * into s from public.sprints where id = p_sprint;
  if not found or not privado.ve_ies(s.ies_id) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(s.ies_id, 'recuperacao.gerir');
  if s.status = 'encerrada' then raise exception 'Sprint encerrada' using errcode = '22023'; end if;
  if p_id is null then
    insert into public.sprint_itens(ies_id, sprint_id, entrega, responsavel) values (s.ies_id, p_sprint, trim(p_dados->>'entrega'), trim(p_dados->>'responsavel')) returning id into v_id;
  else
    update public.sprint_itens set status = coalesce(p_dados->>'status', status),
           impedimento = case when coalesce(p_dados->>'status', status) = 'impedido' then nullif(trim(p_dados->>'impedimento'), '') else null end, atualizado_em = now()
     where id = p_id and sprint_id = p_sprint returning id into v_id;
    if v_id is null then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  end if;
  perform privado.auditar(s.ies_id, 'sprint.item', 'sprint', p_sprint::text, jsonb_build_object('item', v_id, 'status', p_dados->>'status'));
  return jsonb_build_object('id', v_id);
exception when check_violation or not_null_violation then
  raise exception 'Item inválido: entrega e responsável obrigatórios; impedimento exige descrição' using errcode = '22023';
end $$;

-- ---------------------------------------------------------------- leitura consolidada
create or replace function public.rpc_recuperacao(p_ies bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare gerir boolean; ve_custo boolean;
begin
  perform privado.autorizar(p_ies, 'recuperacao.ver');
  gerir := privado.pode(p_ies, 'recuperacao.gerir');
  ve_custo := privado.pode(p_ies, 'campanha.custos_ver');
  return jsonb_build_object('pode_gerir', gerir, 'regra', 'recovery-v1',
    'elegibilidade', 'Perdida há pelo menos a carência do protocolo e no máximo 2 anos; base legal de consentimento ou legítimo interesse; titular não anonimizado; ao menos um canal sem opt-out; sem oportunidade aberta da mesma pessoa no curso. Revalidada no momento da reativação.',
    'protocolos', (select coalesce(jsonb_agg(jsonb_build_object('id', pr.id, 'nome', pr.nome, 'tipo', pr.tipo, 'responsavel', pr.responsavel, 'prazo', pr.prazo,
        'checklist', pr.checklist, 'meta', pr.meta, 'custo_centavos', case when ve_custo then pr.custo_centavos end, 'coorte_destino', pr.coorte_destino,
        'carencia_dias', pr.carencia_dias, 'status', pr.status, 'resultado', pr.resultado, 'sprint_id', pr.sprint_id,
        'vencido', pr.prazo < current_date and pr.status in ('planejado','em_execucao'),
        'selecionadas', m.sel, 'contatadas', m.cont, 'reativadas', m.reat, 'descartadas', m.desc_, 'ingressantes', m.ing,
        'atingimento_meta', round(m.reat::numeric / pr.meta, 4),
        'custo_por_reativacao_centavos', case when ve_custo and pr.custo_centavos > 0 and m.reat > 0 then round(pr.custo_centavos::numeric / m.reat) end,
        'itens', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'status', r.status, 'observacao', r.observacao, 'atribuido_a', privado.nome_usuario(r.atribuido_a),
                    'meu', r.atribuido_a = (select auth.uid()), 'oportunidade_origem_id', r.oportunidade_origem_id, 'oportunidade_nova_id', r.oportunidade_nova_id,
                    'nome', p.nome, 'curso', c.nome || ' · ' || c.turno, 'coorte_origem', o.coorte, 'motivo_perda', o.motivo_perda) order by r.status, r.id), '[]'::jsonb)
                  from public.recuperacoes r join public.oportunidades o on o.id = r.oportunidade_origem_id
                  join public.pessoas p on p.id = o.pessoa_id join public.cursos c on c.id = o.curso_id
                 where r.protocolo_id = pr.id and (gerir or r.atribuido_a = (select auth.uid())) and privado.tem_acesso(o.ies_id, o.curso_id, array['gestor','reitoria','coordenador','comercial'])))
        order by pr.status = 'concluido', pr.prazo), '[]'::jsonb)
      from public.protocolos pr
      cross join lateral (select count(*) as sel, count(*) filter (where r.status = 'contatada') as cont, count(*) filter (where r.status = 'reativada') as reat,
                                 count(*) filter (where r.status = 'descartada') as desc_,
                                 count(*) filter (where exists (select 1 from public.oportunidades n where n.id = r.oportunidade_nova_id and n.etapa = 'confirmado')) as ing
                            from public.recuperacoes r where r.protocolo_id = pr.id) m
     where pr.ies_id = p_ies),
    'sprints', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'nome', s.nome, 'objetivo', s.objetivo, 'inicio', s.inicio, 'fim', s.fim, 'status', s.status,
        'reavaliacao', s.reavaliacao, 'impedimentos', (select count(*) from public.sprint_itens i where i.sprint_id = s.id and i.status = 'impedido'),
        'itens', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'entrega', i.entrega, 'responsavel', i.responsavel, 'status', i.status, 'impedimento', i.impedimento) order by i.id), '[]'::jsonb)
                  from public.sprint_itens i where i.sprint_id = s.id)) order by s.status = 'encerrada', s.inicio desc), '[]'::jsonb)
      from public.sprints s where s.ies_id = p_ies));
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.rpc_recuperaveis(bigint, int, text, bigint), public.rpc_salvar_protocolo(bigint, jsonb, bigint), public.rpc_selecionar_recuperacao(bigint, bigint[], uuid),
  public.rpc_tratar_recuperacao(bigint, text, text), public.rpc_salvar_sprint(bigint, jsonb, bigint), public.rpc_salvar_item_sprint(bigint, jsonb, bigint),
  public.rpc_recuperacao(bigint)
to authenticated;
