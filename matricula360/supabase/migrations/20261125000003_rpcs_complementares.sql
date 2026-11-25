-- Matrícula 360° — migração 3: RPCs complementares (paridade com o piloto local).
-- MAIM (fila, ciclo, conclusão e disparo bloqueado), aceite de proposta, anonimização,
-- configurações, metas, pendências e status da IES. Mesmos princípios da migração 2.

-- ---------------------------------------------------------------- Master
create or replace function public.rpc_alterar_status_ies(p_ies bigint, p_status text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform privado.exigir_usuario();
  if not privado.eh_master() then raise exception 'Operação restrita ao Master' using errcode = '42501'; end if;
  if p_status not in ('ativa','suspensa') then raise exception 'Status inválido' using errcode = '22023'; end if;
  update public.ies set status = p_status where id = p_ies;
  if not found then raise exception 'Não encontrado' using errcode = 'P0002'; end if;
  perform privado.auditar(p_ies, 'ies.status', 'ies', p_ies::text, jsonb_build_object('status', p_status));
  return jsonb_build_object('id', p_ies, 'status', p_status);
end $$;

-- ---------------------------------------------------------------- configuração e metas (gestor)
create or replace function public.rpc_configurar(p_ies bigint, p_sla_horas int default null, p_max_followups int default null,
  p_dias_sem_contato int default null, p_capacidade_atendente int default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.ies;
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then raise exception 'Não encontrado' using errcode = 'P0002'; end if;
  if not privado.tem_acesso_ies(p_ies, array['gestor']) then raise exception 'Seu perfil não tem permissão para esta operação' using errcode = '42501'; end if;
  if coalesce(p_sla_horas, p_max_followups, p_dias_sem_contato, p_capacidade_atendente) is null then
    raise exception 'Nada a alterar' using errcode = '22023';
  end if;
  update public.ies set
    sla_horas = coalesce(p_sla_horas, sla_horas),
    max_followups = coalesce(p_max_followups, max_followups),
    dias_sem_contato = coalesce(p_dias_sem_contato, dias_sem_contato),
    capacidade_atendente = coalesce(p_capacidade_atendente, capacidade_atendente)
   where id = p_ies returning * into r;
  perform privado.auditar(p_ies, 'ies.configurar', 'ies', p_ies::text, jsonb_build_object(
    'sla_horas', r.sla_horas, 'max_followups', r.max_followups, 'dias_sem_contato', r.dias_sem_contato, 'capacidade_atendente', r.capacidade_atendente));
  return jsonb_build_object('sla_horas', r.sla_horas, 'max_followups', r.max_followups,
    'dias_sem_contato', r.dias_sem_contato, 'capacidade_atendente', r.capacidade_atendente);
end $$;

create or replace function public.rpc_definir_meta(p_ies bigint, p_curso bigint, p_coorte text, p_meta int)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform privado.exigir_usuario();
  if not exists (select 1 from public.cursos where id = p_curso and ies_id = p_ies)
     or not privado.tem_acesso(p_ies, p_curso, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro']) then
    raise exception 'Não encontrado' using errcode = 'P0002';
  end if;
  if not privado.tem_acesso(p_ies, p_curso, array['gestor']) then raise exception 'Seu perfil não tem permissão para esta operação' using errcode = '42501'; end if;
  if p_coorte !~ '^\d{4}\.[12]$' then raise exception 'Coorte deve ter formato AAAA.1 ou AAAA.2' using errcode = '22023'; end if;
  if p_meta is null or p_meta not between 0 and 100000 then raise exception 'Meta inválida' using errcode = '22023'; end if;
  insert into public.metas(ies_id, curso_id, coorte, meta) values (p_ies, p_curso, p_coorte, p_meta)
  on conflict (ies_id, curso_id, coorte) do update set meta = excluded.meta;
  perform privado.auditar(p_ies, 'meta.definir', 'curso', p_curso::text, jsonb_build_object('coorte', p_coorte, 'meta', p_meta));
  return jsonb_build_object('curso_id', p_curso, 'coorte', p_coorte, 'meta', p_meta);
end $$;

-- ---------------------------------------------------------------- propostas
create or replace function public.rpc_aceitar_proposta(p_proposta bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.propostas; o public.oportunidades;
begin
  perform privado.exigir_usuario();
  select * into p from public.propostas where id = p_proposta for update;
  if not found then raise exception 'Não encontrado' using errcode = 'P0002'; end if;
  o := privado.carregar_op(p.oportunidade_id, array['comercial','gestor']);
  if p.status <> 'aprovada' then raise exception 'Só propostas aprovadas podem ser aceitas' using errcode = '22023'; end if;
  if p.validade < now() then
    update public.propostas set status = 'expirada' where id = p_proposta;
    perform privado.auditar(o.ies_id, 'proposta.expirar', 'oportunidade', o.id::text, jsonb_build_object('proposta_id', p_proposta));
    return jsonb_build_object('id', p_proposta, 'status', 'expirada');
  end if;
  update public.propostas set status = 'aceita' where id = p_proposta;
  perform privado.auditar(o.ies_id, 'proposta.aceitar', 'oportunidade', o.id::text, jsonb_build_object('proposta_id', p_proposta));
  return jsonb_build_object('id', p_proposta, 'status', 'aceita');
end $$;

-- ---------------------------------------------------------------- LGPD
create or replace function public.rpc_anonimizar(p_op bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades;
begin
  o := privado.carregar_op(p_op, array['gestor']);
  update public.pessoas set nome = 'Titular anonimizado', email = null, telefone = null,
    optout_email = true, optout_whatsapp = true, optout_telefone = true, anonimizada_em = now()
   where id = o.pessoa_id;
  update public.tarefas set status = 'cancelada', encerrada_em = now(), resultado = 'titular anonimizado'
   where status = 'aberta' and oportunidade_id in (select id from public.oportunidades where pessoa_id = o.pessoa_id);
  perform privado.auditar(o.ies_id, 'pessoa.anonimizar', 'oportunidade', p_op::text);
  return jsonb_build_object('anonimizada', true);
end $$;

-- ---------------------------------------------------------------- MAIM
create or replace function privado.canal_permitido(p_pessoa bigint) returns text
language sql stable security definer set search_path = '' as $$
  select case when not p.optout_whatsapp and p.telefone is not null then 'whatsapp'
              when not p.optout_email and p.email is not null then 'email'
              when not p.optout_telefone and p.telefone is not null then 'telefone' end
    from public.pessoas p where p.id = p_pessoa;
$$;

-- Fila: gestor vê tudo; comercial (sem outro papel operacional) vê só as próprias tarefas.
create or replace function public.rpc_fila(p_ies bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare so_minhas boolean; r jsonb;
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then raise exception 'Não encontrado' using errcode = 'P0002'; end if;
  if not exists (select 1 from public.escopos e where e.usuario_id = (select auth.uid()) and e.ies_id = p_ies and e.revogado_em is null
                 and e.papel in ('gestor','comercial','secretaria','financeiro')) then
    raise exception 'Seu perfil não tem permissão para esta operação' using errcode = '42501';
  end if;
  so_minhas := not exists (select 1 from public.escopos e where e.usuario_id = (select auth.uid()) and e.ies_id = p_ies
                           and e.revogado_em is null and e.papel in ('gestor','secretaria','financeiro'));
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'tipo', t.tipo, 'canal', t.canal, 'vence_em', t.vence_em,
           'oportunidade_id', t.oportunidade_id, 'responsavel_id', t.responsavel_id, 'etapa', o.etapa, 'curso', c.nome,
           'atrasada', t.vence_em < now()) order by t.vence_em), '[]'::jsonb)
    into r
    from (select * from public.tarefas where ies_id = p_ies and status = 'aberta' order by vence_em limit 200) t
    join public.oportunidades o on o.id = t.oportunidade_id
    join public.cursos c on c.id = o.curso_id
   where privado.tem_acesso(o.ies_id, o.curso_id, array['gestor','comercial','secretaria','financeiro'])
     and (not so_minhas or t.responsavel_id = (select auth.uid()));
  return jsonb_build_object('tarefas', r, 'envio_externo', 'desativado');
end $$;

create or replace function public.rpc_ciclo_maim(p_ies bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare cfg public.ies; o record; v_canal text; n_follow int; rel jsonb;
  c_follow int := 0; c_supr int := 0; c_lim int := 0; c_pend int := 0; c_redis int := 0; c_atras int;
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then raise exception 'Não encontrado' using errcode = 'P0002'; end if;
  if not privado.tem_acesso_ies(p_ies, array['gestor']) then raise exception 'Seu perfil não tem permissão para esta operação' using errcode = '42501'; end if;
  select * into cfg from public.ies where id = p_ies for update; -- serializa ciclos concorrentes da mesma IES
  for o in select op.* from public.oportunidades op
            where op.ies_id = p_ies and op.etapa in ('contato','inscrito','pre_matricula')
              and op.atualizado_em < now() - make_interval(days => cfg.dias_sem_contato)
              and not exists (select 1 from public.tarefas t where t.oportunidade_id = op.id and t.status = 'aberta') loop
    select count(*) into n_follow from public.tarefas where oportunidade_id = o.id and tipo = 'follow_up';
    if n_follow >= cfg.max_followups then c_lim := c_lim + 1; continue; end if;
    v_canal := privado.canal_permitido(o.pessoa_id);
    if v_canal is null then c_supr := c_supr + 1; continue; end if;
    insert into public.tarefas(ies_id, oportunidade_id, tipo, canal, responsavel_id, vence_em)
    values (p_ies, o.id, 'follow_up', v_canal, coalesce(o.responsavel_id, privado.distribuir(p_ies, o.curso_id)), now() + interval '24 hours');
    c_follow := c_follow + 1;
  end loop;
  insert into public.tarefas(ies_id, oportunidade_id, tipo, vence_em)
  select p_ies, op.id, 'pendencia_validacao', now() + interval '48 hours' from public.oportunidades op
   where op.ies_id = p_ies and op.etapa = 'matricula_comercial'
     and not (op.val_documental and op.val_financeira and op.val_academica)
     and not exists (select 1 from public.tarefas t where t.oportunidade_id = op.id and t.status = 'aberta' and t.tipo = 'pendencia_validacao');
  get diagnostics c_pend = row_count;
  with orfas as (
    select t.id, privado.distribuir(p_ies, op.curso_id) as resp from public.tarefas t join public.oportunidades op on op.id = t.oportunidade_id
     where t.ies_id = p_ies and t.status = 'aberta' and t.responsavel_id is null and t.tipo <> 'pendencia_validacao')
  update public.tarefas t set responsavel_id = orfas.resp from orfas where t.id = orfas.id and orfas.resp is not null;
  get diagnostics c_redis = row_count;
  select count(*) into c_atras from public.tarefas where ies_id = p_ies and status = 'aberta' and vence_em < now();
  rel := jsonb_build_object('follow_ups', c_follow, 'suprimidos_optout', c_supr, 'limite_atingido', c_lim,
    'pendencias_validacao', c_pend, 'sem_responsavel_redistribuidas', c_redis, 'atrasadas', c_atras);
  perform privado.auditar(p_ies, 'maim.ciclo', 'ies', p_ies::text, rel);
  return rel;
end $$;

-- Carrega tarefa: pendência de validação é da secretaria/financeiro/gestor; contato é do responsável ou gestor.
create or replace function privado.carregar_tarefa(p_tarefa bigint) returns public.tarefas
language plpgsql security definer set search_path = '' as $$
declare t public.tarefas; o public.oportunidades;
begin
  select * into t from public.tarefas where id = p_tarefa for update;
  if not found then raise exception 'Não encontrado' using errcode = 'P0002'; end if;
  o := privado.carregar_op(t.oportunidade_id, case when t.tipo = 'pendencia_validacao'
         then array['gestor','secretaria','financeiro'] else array['gestor','comercial'] end);
  if t.tipo <> 'pendencia_validacao' and not privado.tem_acesso(o.ies_id, o.curso_id, array['gestor'])
     and t.responsavel_id is distinct from (select auth.uid()) then
    raise exception 'Tarefa atribuída a outro atendente' using errcode = '42501';
  end if;
  return t;
end $$;

-- Revalidação na execução: etapa encerrada ou opt-out suprimem a tarefa.
create or replace function privado.revalidar_tarefa(t public.tarefas) returns text[]
language plpgsql stable security definer set search_path = '' as $$
declare o public.oportunidades; p public.pessoas;
begin
  select * into o from public.oportunidades where id = t.oportunidade_id;
  if o.etapa in ('perdido','cancelado','confirmado') then return array['cancelada','etapa encerrada']; end if;
  if t.canal is not null then
    select * into p from public.pessoas where id = o.pessoa_id;
    if p.anonimizada_em is not null
       or (t.canal = 'email' and p.optout_email) or (t.canal = 'whatsapp' and p.optout_whatsapp) or (t.canal = 'telefone' and p.optout_telefone) then
      return array['suprimida', 'opt-out ' || t.canal];
    end if;
  end if;
  return null;
end $$;

create or replace function public.rpc_concluir_tarefa(p_tarefa bigint, p_resultado text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare t public.tarefas; b text[]; v_status text;
begin
  perform privado.exigir_usuario();
  if length(coalesce(trim(p_resultado), '')) not between 3 and 300 then raise exception 'Resultado do contato obrigatório' using errcode = '22023'; end if;
  t := privado.carregar_tarefa(p_tarefa);
  if t.status <> 'aberta' then raise exception 'Tarefa já encerrada' using errcode = '22023'; end if;
  b := privado.revalidar_tarefa(t);
  v_status := coalesce(b[1], 'concluida');
  update public.tarefas set status = v_status, resultado = coalesce(b[2], trim(p_resultado)), encerrada_em = now() where id = p_tarefa;
  perform privado.auditar(t.ies_id, 'tarefa.' || v_status, 'oportunidade', t.oportunidade_id::text,
    jsonb_build_object('tarefa_id', p_tarefa, 'tipo', t.tipo, 'canal', t.canal));
  return jsonb_build_object('id', p_tarefa, 'status', v_status, 'motivo', b[2]);
end $$;

-- Envio externo permanece DESLIGADO: revalida, audita e devolve enviado=false. Nada sai do banco.
create or replace function public.rpc_disparar_tarefa(p_tarefa bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare t public.tarefas; b text[];
begin
  perform privado.exigir_usuario();
  t := privado.carregar_tarefa(p_tarefa);
  b := privado.revalidar_tarefa(t);
  perform privado.auditar(t.ies_id, 'envio_externo.bloqueado', 'oportunidade', t.oportunidade_id::text,
    jsonb_build_object('tarefa_id', p_tarefa, 'canal', t.canal, 'revalidacao', coalesce(b[2], 'elegivel')));
  return jsonb_build_object('enviado', false, 'motivo', 'Envio externo desativado', 'elegivel', b is null);
end $$;

create or replace function public.rpc_pendencias(p_ies bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare r jsonb;
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then raise exception 'Não encontrado' using errcode = 'P0002'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'versao', o.versao, 'etapa', o.etapa, 'coorte', o.coorte, 'curso', c.nome,
           'val_documental', o.val_documental, 'val_financeira', o.val_financeira, 'val_academica', o.val_academica,
           'confirmada_em', o.confirmada_em, 'cancelada_em', o.cancelada_em)
           order by o.etapa = 'matricula_comercial' desc, o.atualizado_em desc), '[]'::jsonb)
    into r
    from (select * from public.oportunidades where ies_id = p_ies and etapa in ('matricula_comercial','confirmado','cancelado')
           order by etapa = 'matricula_comercial' desc, atualizado_em desc limit 200) o
    join public.cursos c on c.id = o.curso_id
   where privado.tem_acesso(o.ies_id, o.curso_id, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro']);
  return r;
end $$;

-- ---------------------------------------------------------------- permissões
revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.rpc_alterar_status_ies(bigint, text), public.rpc_configurar(bigint, int, int, int, int),
  public.rpc_definir_meta(bigint, bigint, text, int), public.rpc_aceitar_proposta(bigint), public.rpc_anonimizar(bigint),
  public.rpc_fila(bigint), public.rpc_ciclo_maim(bigint), public.rpc_concluir_tarefa(bigint, text),
  public.rpc_disparar_tarefa(bigint), public.rpc_pendencias(bigint)
to authenticated;
revoke execute on all functions in schema privado from public, anon, authenticated;
grant execute on function privado.usuario_ativo(), privado.eh_master(), privado.tem_acesso(bigint, bigint, text[]),
  privado.tem_acesso_ies(bigint, text[]), privado.ve_ies(bigint), privado.ve_oportunidade(bigint, text[]) to authenticated;
