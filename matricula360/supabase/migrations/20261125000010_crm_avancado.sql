-- Matrícula 360° — migração 10: CRM avançado (Bíblia v0.2 §4, P0).
-- Interações registradas, objeções, agenda comercial, reatribuição com histórico, score explicável
-- (versionado, sem uso para decidir ingresso), SLA e última interação no cartão, busca e filtros combinados,
-- alerta de possível duplicidade com revisão humana (sem fusão automática).

-- ---------------------------------------------------------------- estrutura
alter table public.oportunidades add column if not exists ultima_interacao_em timestamptz;

create table if not exists public.interacoes (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  oportunidade_id bigint not null references public.oportunidades(id),
  tipo text not null check (tipo in ('ligacao','whatsapp_manual','email_manual','visita','reuniao','anotacao')),
  resumo text not null check (length(resumo) between 3 and 1000),
  usuario_id uuid not null references public.usuarios(id),
  em timestamptz not null default now()
);
create index if not exists interacoes_op on public.interacoes(oportunidade_id, em desc);
create index if not exists interacoes_usuario on public.interacoes(usuario_id);
create index if not exists interacoes_ies on public.interacoes(ies_id);

create table if not exists public.objecoes (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  oportunidade_id bigint not null references public.oportunidades(id),
  categoria text not null check (categoria in ('preco','horario','distancia','documentacao','concorrencia','credibilidade','tempo','familia','outra')),
  descricao text not null check (length(descricao) between 3 and 500),
  tratamento text check (tratamento is null or length(tratamento) <= 1000),
  status text not null default 'aberta' check (status in ('aberta','superada','nao_superada')),
  registrado_por uuid not null references public.usuarios(id),
  em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index if not exists objecoes_op on public.objecoes(oportunidade_id);
create index if not exists objecoes_usuario on public.objecoes(registrado_por);
create index if not exists objecoes_ies on public.objecoes(ies_id);

alter table public.interacoes enable row level security;
alter table public.objecoes enable row level security;
revoke all on public.interacoes, public.objecoes from anon, authenticated;
grant select on public.interacoes, public.objecoes to authenticated;
drop policy if exists interacoes_leitura on public.interacoes;
create policy interacoes_leitura on public.interacoes for select to authenticated
  using (privado.ve_oportunidade(oportunidade_id, array['gestor','comercial','secretaria','financeiro']));
drop policy if exists objecoes_leitura on public.objecoes;
create policy objecoes_leitura on public.objecoes for select to authenticated
  using (privado.ve_oportunidade(oportunidade_id, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro']));

-- Agenda comercial: tarefa do tipo "agendamento", com descrição.
alter table public.tarefas add column if not exists descricao text check (descricao is null or length(descricao) <= 300);
alter table public.tarefas drop constraint if exists tarefas_tipo_check;
alter table public.tarefas add constraint tarefas_tipo_check
  check (tipo in ('primeiro_contato','follow_up','pendencia_validacao','recuperacao','agendamento'));
create or replace function privado.tarefa_compativel(p_tipo text, p_etapa text) returns boolean
language sql immutable set search_path = '' as $$
  select case p_tipo
    when 'primeiro_contato' then p_etapa = 'novo'
    when 'follow_up' then p_etapa in ('contato','inscrito','pre_matricula')
    when 'recuperacao' then p_etapa in ('contato','inscrito','pre_matricula')
    when 'pendencia_validacao' then p_etapa = 'matricula_comercial'
    when 'agendamento' then p_etapa in ('novo','contato','inscrito','pre_matricula','matricula_comercial')
    else true end;
$$;
revoke execute on function privado.tarefa_compativel(text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------- score explicável (MAIM Score, regra score-v1)
-- Regra pura e determinística; só prioriza o trabalho comercial. NÃO é usada para negar ou condicionar ingresso.
create or replace function privado.score_oportunidade(p_op bigint) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare o public.oportunidades; p public.pessoas; pts int := 0; r jsonb := '[]'::jsonb; dias numeric; v int;
begin
  select * into o from public.oportunidades where id = p_op;
  if not found then return null; end if;
  select * into p from public.pessoas where id = o.pessoa_id;
  if o.etapa in ('confirmado','perdido','cancelado') then
    return jsonb_build_object('score', null, 'versao', 'score-v1', 'razoes', jsonb_build_array('Etapa encerrada: sem priorização comercial.'),
      'aviso', 'Prioriza o trabalho comercial; não é usado para decidir ingresso.');
  end if;
  v := case o.etapa when 'novo' then 5 when 'contato' then 10 when 'inscrito' then 25 when 'pre_matricula' then 35 when 'matricula_comercial' then 45 else 0 end;
  pts := pts + v; r := r || to_jsonb(format('+%s etapa: %s', v, o.etapa));
  if p.email is not null and p.telefone is not null then pts := pts + 10; r := r || to_jsonb('+10 cadastro com e-mail e telefone'::text); end if;
  dias := extract(epoch from now() - coalesce(o.ultima_interacao_em, o.criado_em)) / 86400;
  if o.ultima_interacao_em is not null and dias <= 3 then pts := pts + 15; r := r || to_jsonb('+15 interação nos últimos 3 dias'::text);
  elsif o.ultima_interacao_em is not null and dias <= 7 then pts := pts + 8; r := r || to_jsonb('+8 interação nos últimos 7 dias'::text);
  elsif dias > 14 then pts := pts - 10; r := r || to_jsonb('-10 sem interação há mais de 14 dias'::text); end if;
  if exists (select 1 from public.propostas x where x.oportunidade_id = p_op and x.status = 'aceita') then
    pts := pts + 15; r := r || to_jsonb('+15 proposta aceita'::text);
  elsif exists (select 1 from public.propostas x where x.oportunidade_id = p_op and x.status in ('aprovada','pendente_aprovacao') and x.validade >= now()) then
    pts := pts + 10; r := r || to_jsonb('+10 proposta ativa'::text);
  end if;
  v := (select count(*) from public.objecoes j where j.oportunidade_id = p_op and j.status = 'aberta');
  if v > 0 then pts := pts - 10 * least(v, 2); r := r || to_jsonb(format('-%s objeção(ões) em aberto', 10 * least(v, 2))); end if;
  if p.optout_email and p.optout_whatsapp and p.optout_telefone then pts := pts - 20; r := r || to_jsonb('-20 opt-out em todos os canais'::text); end if;
  return jsonb_build_object('score', greatest(0, least(100, pts)), 'versao', 'score-v1', 'razoes', r,
    'aviso', 'Prioriza o trabalho comercial; não é usado para decidir ingresso.');
end $$;
revoke execute on function privado.score_oportunidade(bigint) from public, anon, authenticated;

-- Normalização de nomes para alerta de possível duplicidade (sem extensão unaccent).
create or replace function privado.normalizar_nome(t text) returns text
language sql immutable set search_path = '' as $$
  select regexp_replace(lower(translate(coalesce(t, ''), 'ÁÀÂÃÄáàâãäÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÕÖóòôõöÚÙÛÜúùûüÇçÑñ', 'AAAAAaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCcNn')), '\s+', ' ', 'g');
$$;
revoke execute on function privado.normalizar_nome(text) from public, anon, authenticated;
create index if not exists pessoas_nome_norm on public.pessoas(ies_id, privado.normalizar_nome(nome));

-- ---------------------------------------------------------------- escrita
create or replace function public.rpc_registrar_interacao(p_op bigint, p_tipo text, p_resumo text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; v_id bigint;
begin
  o := privado.carregar_op(p_op, array['comercial','gestor']);
  if p_tipo not in ('ligacao','whatsapp_manual','email_manual','visita','reuniao','anotacao') then raise exception 'Tipo de interação inválido' using errcode = '22023'; end if;
  if length(coalesce(trim(p_resumo), '')) not between 3 and 1000 then raise exception 'Resumo da interação obrigatório (3 a 1000 caracteres)' using errcode = '22023'; end if;
  insert into public.interacoes(ies_id, oportunidade_id, tipo, resumo, usuario_id) values (o.ies_id, p_op, p_tipo, trim(p_resumo), (select auth.uid())) returning id into v_id;
  update public.oportunidades set ultima_interacao_em = now() where id = p_op;
  perform privado.auditar(o.ies_id, 'interacao.registrar', 'oportunidade', p_op::text, jsonb_build_object('interacao_id', v_id, 'tipo', p_tipo));
  return jsonb_build_object('id', v_id);
end $$;

create or replace function public.rpc_registrar_objecao(p_op bigint, p_categoria text, p_descricao text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; v_id bigint;
begin
  o := privado.carregar_op(p_op, array['comercial','gestor']);
  if p_categoria not in ('preco','horario','distancia','documentacao','concorrencia','credibilidade','tempo','familia','outra') then raise exception 'Categoria de objeção inválida' using errcode = '22023'; end if;
  if length(coalesce(trim(p_descricao), '')) not between 3 and 500 then raise exception 'Descrição da objeção obrigatória' using errcode = '22023'; end if;
  insert into public.objecoes(ies_id, oportunidade_id, categoria, descricao, registrado_por) values (o.ies_id, p_op, p_categoria, trim(p_descricao), (select auth.uid())) returning id into v_id;
  perform privado.auditar(o.ies_id, 'objecao.registrar', 'oportunidade', p_op::text, jsonb_build_object('objecao_id', v_id, 'categoria', p_categoria));
  return jsonb_build_object('id', v_id);
end $$;

create or replace function public.rpc_tratar_objecao(p_objecao bigint, p_status text, p_tratamento text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare j public.objecoes; o public.oportunidades;
begin
  perform privado.exigir_usuario();
  if p_status not in ('aberta','superada','nao_superada') then raise exception 'Status inválido' using errcode = '22023'; end if;
  if length(coalesce(trim(p_tratamento), '')) < 3 then raise exception 'Descreva o tratamento dado à objeção' using errcode = '22023'; end if;
  select * into j from public.objecoes where id = p_objecao for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  o := privado.carregar_op(j.oportunidade_id, array['comercial','gestor']);
  update public.objecoes set status = p_status, tratamento = trim(p_tratamento), atualizado_em = now() where id = p_objecao;
  perform privado.auditar(o.ies_id, 'objecao.tratar', 'oportunidade', o.id::text, jsonb_build_object('objecao_id', p_objecao, 'status', p_status));
  return jsonb_build_object('id', p_objecao, 'status', p_status);
end $$;

create or replace function public.rpc_agendar(p_op bigint, p_quando timestamptz, p_descricao text, p_canal text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; v_id bigint;
begin
  o := privado.carregar_op(p_op, array['comercial','gestor']);
  if p_quando is null or p_quando < now() - interval '5 minutes' or p_quando > now() + interval '180 days' then
    raise exception 'Data do agendamento deve estar entre agora e 180 dias' using errcode = '22023';
  end if;
  if length(coalesce(trim(p_descricao), '')) not between 3 and 300 then raise exception 'Descrição do agendamento obrigatória' using errcode = '22023'; end if;
  if p_canal is not null and p_canal not in ('email','whatsapp','telefone') then raise exception 'Canal inválido' using errcode = '22023'; end if;
  insert into public.tarefas(ies_id, oportunidade_id, tipo, canal, responsavel_id, vence_em, descricao)
  values (o.ies_id, p_op, 'agendamento', p_canal, (select auth.uid()), p_quando, trim(p_descricao)) returning id into v_id;
  perform privado.auditar(o.ies_id, 'agenda.criar', 'oportunidade', p_op::text, jsonb_build_object('tarefa_id', v_id, 'quando', p_quando));
  return jsonb_build_object('id', v_id);
end $$;

-- Reatribuição pelo gestor, com motivo; o histórico fica na auditoria e as tarefas abertas acompanham.
create or replace function public.rpc_reatribuir(p_op bigint, p_responsavel uuid, p_motivo text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; n int;
begin
  o := privado.carregar_op(p_op, array['gestor']);
  if length(coalesce(trim(p_motivo), '')) < 3 then raise exception 'Motivo da reatribuição obrigatório' using errcode = '22023'; end if;
  if not exists (select 1 from public.escopos e join public.usuarios u on u.id = e.usuario_id
                 where e.usuario_id = p_responsavel and e.ies_id = o.ies_id and e.papel = 'comercial' and e.revogado_em is null
                   and u.revogado_em is null and (e.curso_id is null or e.curso_id = o.curso_id)) then
    raise exception 'O novo responsável precisa ser atendente comercial ativo com escopo neste curso' using errcode = '22023';
  end if;
  if o.responsavel_id is not distinct from p_responsavel then raise exception 'A oportunidade já está com este responsável' using errcode = '22023'; end if;
  update public.oportunidades set responsavel_id = p_responsavel, versao = versao + 1, atualizado_em = now() where id = p_op;
  update public.tarefas set responsavel_id = p_responsavel where oportunidade_id = p_op and status = 'aberta' and tipo <> 'pendencia_validacao';
  get diagnostics n = row_count;
  perform privado.auditar(o.ies_id, 'oportunidade.reatribuir', 'oportunidade', p_op::text,
    jsonb_build_object('de', o.responsavel_id, 'para', p_responsavel, 'motivo', trim(p_motivo), 'tarefas', n));
  return jsonb_build_object('id', p_op, 'responsavel_id', p_responsavel, 'tarefas_transferidas', n);
end $$;

-- Atendentes elegíveis para reatribuição (gestor).
create or replace function public.rpc_atendentes(p_ies bigint, p_curso bigint default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if not privado.tem_acesso_ies(p_ies, array['gestor']) then raise exception 'Seu perfil não tem permissão para esta operação' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(distinct jsonb_build_object('id', u.id, 'nome', u.nome)), '[]'::jsonb)
            from public.escopos e join public.usuarios u on u.id = e.usuario_id
           where e.ies_id = p_ies and e.papel = 'comercial' and e.revogado_em is null and u.revogado_em is null
             and (p_curso is null or e.curso_id is null or e.curso_id = p_curso));
end $$;

-- Agenda do usuário (gestor vê a da IES) num intervalo.
create or replace function public.rpc_agenda(p_ies bigint, p_de timestamptz, p_ate timestamptz)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare gestor boolean;
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if p_ate <= p_de or p_ate - p_de > interval '92 days' then raise exception 'Intervalo inválido (até 92 dias)' using errcode = '22023'; end if;
  gestor := privado.tem_acesso_ies(p_ies, array['gestor']);
  return (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'tipo', t.tipo, 'quando', t.vence_em, 'descricao', t.descricao, 'canal', t.canal,
             'oportunidade_id', o.id, 'nome', p.nome, 'curso', c.nome, 'etapa', o.etapa, 'responsavel', privado.nome_usuario(t.responsavel_id),
             'atrasada', t.vence_em < now()) order by t.vence_em), '[]'::jsonb)
    from public.tarefas t join public.oportunidades o on o.id = t.oportunidade_id
    join public.pessoas p on p.id = o.pessoa_id join public.cursos c on c.id = o.curso_id
   where t.ies_id = p_ies and t.status = 'aberta' and t.vence_em between p_de and p_ate
     and privado.tem_acesso(o.ies_id, o.curso_id, array['gestor','comercial'])
     and (gestor or t.responsavel_id = (select auth.uid())));
end $$;

-- Concluir tarefa também registra a última interação (contato realizado).
create or replace function privado.marcar_interacao_tarefa() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'concluida' and old.status = 'aberta' and new.tipo <> 'pendencia_validacao' then
    update public.oportunidades set ultima_interacao_em = now() where id = new.oportunidade_id;
  end if;
  return new;
end $$;
revoke execute on function privado.marcar_interacao_tarefa() from public, anon, authenticated;
drop trigger if exists tarefa_marca_interacao on public.tarefas;
create trigger tarefa_marca_interacao after update of status on public.tarefas
  for each row execute function privado.marcar_interacao_tarefa();

-- ---------------------------------------------------------------- leitura: lista com busca, filtros, SLA e score
drop function if exists public.rpc_listar_oportunidades(bigint, text, text, int, int, bigint);
create or replace function public.rpc_listar_oportunidades(p_ies bigint, p_etapa text default null, p_coorte text default null,
  p_pagina int default 1, p_por_pagina int default 25, p_curso bigint default null,
  p_busca text default null, p_forma text default null, p_somente_meus boolean default false, p_sla_atrasado boolean default false)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare total bigint; itens jsonb; v_busca text := nullif(trim(coalesce(p_busca, '')), '');
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if p_por_pagina not between 1 and 100 or p_pagina < 1 then raise exception 'Paginação inválida' using errcode = '22023'; end if;
  if v_busca is not null and length(v_busca) > 80 then raise exception 'Busca muito longa' using errcode = '22023'; end if;
  with base as (
    select o.*, c.nome as curso, c.turno, p.nome, p.email, p.telefone, p.origem, r.nome as responsavel,
           privado.tem_acesso(o.ies_id, o.curso_id, array['gestor','comercial','secretaria','financeiro']) as pleno,
           (select min(t.vence_em) from public.tarefas t where t.oportunidade_id = o.id and t.status = 'aberta') as proxima_tarefa
      from public.oportunidades o join public.cursos c on c.id = o.curso_id join public.pessoas p on p.id = o.pessoa_id
      left join public.usuarios r on r.id = o.responsavel_id
     where o.ies_id = p_ies
       and privado.tem_acesso(o.ies_id, o.curso_id, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro'])
       and (p_etapa is null or o.etapa = p_etapa) and (p_coorte is null or o.coorte = p_coorte) and (p_curso is null or o.curso_id = p_curso)
       and (p_forma is null or o.forma_ingresso = p_forma)
       and (not p_somente_meus or o.responsavel_id = (select auth.uid()))
  ), filtrada as (
    select * from base b
     where (v_busca is null
            or privado.normalizar_nome(b.nome) like '%' || privado.normalizar_nome(v_busca) || '%'
            -- contato só é pesquisável por quem pode vê-lo (minimização)
            or (b.pleno and (b.email ilike '%' || v_busca || '%' or b.telefone like '%' || regexp_replace(v_busca, '\D', '', 'g') || '%')
                and length(regexp_replace(v_busca, '\s', '', 'g')) >= 4))
       and (not p_sla_atrasado or b.proxima_tarefa < now())
  )
  select (select count(*) from filtrada),
         coalesce(jsonb_agg(jsonb_build_object(
           'id', f.id, 'etapa', f.etapa, 'versao', f.versao, 'coorte', f.coorte, 'curso_id', f.curso_id, 'curso', f.curso, 'turno', f.turno,
           'forma_ingresso', f.forma_ingresso, 'responsavel', f.responsavel, 'nome', f.nome, 'origem', f.origem,
           'val_documental', f.val_documental, 'val_financeira', f.val_financeira, 'val_academica', f.val_academica,
           'email', case when f.pleno then f.email else privado.mascarar_email(f.email) end,
           'telefone', case when f.pleno then f.telefone else privado.mascarar_tel(f.telefone) end,
           'dados_mascarados', not f.pleno,
           'ultima_interacao_em', f.ultima_interacao_em, 'proxima_tarefa_em', f.proxima_tarefa,
           'sla_atrasado', coalesce(f.proxima_tarefa < now(), false),
           'score', (privado.score_oportunidade(f.id))->'score') order by f.atualizado_em desc, f.id desc), '[]'::jsonb)
    into total, itens
    from (select * from filtrada order by atualizado_em desc, id desc limit p_por_pagina offset (p_pagina - 1) * p_por_pagina) f;
  return jsonb_build_object('itens', itens, 'total', total, 'pagina', p_pagina, 'por_pagina', p_por_pagina);
end $$;

-- ---------------------------------------------------------------- leitura: ficha completa
create or replace function public.rpc_detalhe(p_op bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare o public.oportunidades; p public.pessoas; c public.cursos; pleno boolean; comercial boolean;
  t constant jsonb := '{"novo":["contato","perdido"],"contato":["inscrito","perdido"],"inscrito":["pre_matricula","perdido"],"pre_matricula":["matricula_comercial","perdido"],"perdido":["contato"]}';
begin
  perform privado.exigir_usuario();
  select * into o from public.oportunidades where id = p_op;
  if not found or not privado.tem_acesso(o.ies_id, o.curso_id, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro']) then
    perform privado.erro_http(404, 'P0002', 'Não encontrado');
  end if;
  select * into p from public.pessoas where id = o.pessoa_id;
  select * into c from public.cursos where id = o.curso_id;
  pleno := privado.tem_acesso(o.ies_id, o.curso_id, array['gestor','comercial','secretaria','financeiro']);
  comercial := privado.tem_acesso(o.ies_id, o.curso_id, array['gestor','comercial']);
  return jsonb_build_object(
    'oportunidade', to_jsonb(o) || jsonb_build_object('responsavel', privado.nome_usuario(o.responsavel_id)),
    'curso', jsonb_build_object('id', c.id, 'nome', c.nome, 'turno', c.turno, 'modalidade', c.modalidade,
                                'mensalidade_centavos', c.mensalidade_centavos, 'desconto_max_pct', c.desconto_max_pct),
    'pessoa', jsonb_build_object('id', p.id, 'nome', p.nome,
       'email', case when pleno then p.email else privado.mascarar_email(p.email) end,
       'telefone', case when pleno then p.telefone else privado.mascarar_tel(p.telefone) end,
       'dados_mascarados', not pleno, 'base_legal', p.base_legal, 'origem', p.origem,
       'optout', jsonb_build_object('email', p.optout_email, 'whatsapp', p.optout_whatsapp, 'telefone', p.optout_telefone),
       'anonimizada', p.anonimizada_em is not null),
    'transicoes', coalesce(t->o.etapa, '[]'::jsonb),
    'score', case when comercial then privado.score_oportunidade(o.id) end,
    'validacoes', (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'dimensao', v.dimensao, 'resultado', v.resultado,
                     'evidencia', v.evidencia, 'em', v.em, 'por', privado.nome_usuario(v.usuario_id)) order by v.id), '[]'::jsonb)
                   from public.validacoes v where v.oportunidade_id = o.id),
    'propostas', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'desconto_pct', x.desconto_pct, 'mensalidade_centavos', x.mensalidade_centavos,
                     'valor_final_centavos', x.valor_final_centavos, 'validade', x.validade, 'status', x.status, 'criado_em', x.criado_em,
                     'criado_por', privado.nome_usuario(x.criado_por)) order by x.id desc), '[]'::jsonb)
                  from public.propostas x where x.oportunidade_id = o.id and comercial),
    'tarefas', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'tipo', x.tipo, 'canal', x.canal, 'status', x.status,
                     'vence_em', x.vence_em, 'resultado', x.resultado, 'descricao', x.descricao, 'atrasada', x.status = 'aberta' and x.vence_em < now()) order by x.id desc), '[]'::jsonb)
                from public.tarefas x where x.oportunidade_id = o.id),
    'interacoes', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'tipo', i.tipo, 'resumo', i.resumo, 'em', i.em,
                     'por', privado.nome_usuario(i.usuario_id)) order by i.em desc), '[]'::jsonb)
                   from public.interacoes i where i.oportunidade_id = o.id and pleno),
    'objecoes', (select coalesce(jsonb_agg(jsonb_build_object('id', j.id, 'categoria', j.categoria, 'descricao', j.descricao, 'tratamento', j.tratamento,
                     'status', j.status, 'em', j.em, 'por', privado.nome_usuario(j.registrado_por)) order by j.em desc), '[]'::jsonb)
                 from public.objecoes j where j.oportunidade_id = o.id),
    -- Possível duplicidade: mesmo nome normalizado na IES, outra pessoa. Só sinaliza; a decisão é humana.
    'possiveis_duplicidades', case when pleno then (select coalesce(jsonb_agg(jsonb_build_object('pessoa_id', q.id,
                     'email', privado.mascarar_email(q.email), 'telefone', privado.mascarar_tel(q.telefone),
                     'oportunidades', (select count(*) from public.oportunidades x where x.pessoa_id = q.id))), '[]'::jsonb)
                 from public.pessoas q where q.ies_id = o.ies_id and q.id <> p.id and q.anonimizada_em is null
                   and privado.normalizar_nome(q.nome) = privado.normalizar_nome(p.nome)) else '[]'::jsonb end,
    'historico', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'acao', a.acao, 'dados', a.dados, 'em', a.em,
                     'por', privado.nome_usuario(a.usuario_id)) order by a.id), '[]'::jsonb)
                  from public.auditoria a where a.entidade = 'oportunidade' and a.entidade_id = o.id::text));
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.rpc_registrar_interacao(bigint, text, text), public.rpc_registrar_objecao(bigint, text, text),
  public.rpc_tratar_objecao(bigint, text, text), public.rpc_agendar(bigint, timestamptz, text, text),
  public.rpc_reatribuir(bigint, uuid, text), public.rpc_atendentes(bigint, bigint), public.rpc_agenda(bigint, timestamptz, timestamptz),
  public.rpc_listar_oportunidades(bigint, text, text, int, int, bigint, text, text, boolean, boolean), public.rpc_detalhe(bigint)
to authenticated;
