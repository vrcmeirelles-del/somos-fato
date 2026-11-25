-- Matrícula 360° — migração 2: RPCs (única via de escrita do cliente).
-- Toda função: SECURITY DEFINER, search_path vazio, identidade de auth.uid(),
-- verificação de escopo no servidor e auditoria na MESMA transação.
-- Códigos de erro (SQLSTATE):
--   P0002 = não encontrado / fora do escopo (não revela existência)
--   42501 = perfil sem permissão
--   40001 = conflito de versão (outra operação alterou o registro)
--   22023 = regra de negócio violada / parâmetro inválido
-- [Pendente de verificação na homologação remota] mapeamento HTTP desses códigos pelo PostgREST.

-- ---------------------------------------------------------------- auxiliares
create or replace function privado.exigir_usuario() returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare v uuid := (select auth.uid());
begin
  if v is null or not privado.usuario_ativo() then
    raise exception 'Sessão ausente, expirada ou usuário revogado' using errcode = '42501';
  end if;
  return v;
end $$;

create or replace function privado.auditar(p_ies bigint, p_acao text, p_entidade text, p_entidade_id text, p_dados jsonb default '{}')
returns void language sql security definer set search_path = '' as $$
  insert into public.auditoria(ies_id, usuario_id, acao, entidade, entidade_id, dados)
  values (p_ies, (select auth.uid()), p_acao, p_entidade, p_entidade_id, coalesce(p_dados, '{}'::jsonb));
$$;

-- Carrega a oportunidade com bloqueio de linha. Sem leitura no curso => P0002; sem papel => 42501.
create or replace function privado.carregar_op(p_op bigint, p_papeis text[]) returns public.oportunidades
language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades;
begin
  perform privado.exigir_usuario();
  select * into o from public.oportunidades where id = p_op for update;
  if not found or not privado.tem_acesso(o.ies_id, o.curso_id, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro']) then
    raise exception 'Não encontrado' using errcode = 'P0002';
  end if;
  if not privado.tem_acesso(o.ies_id, o.curso_id, p_papeis) then
    raise exception 'Seu perfil não tem permissão para esta operação' using errcode = '42501';
  end if;
  return o;
end $$;

create or replace function privado.exigir_versao(p_op bigint, p_esperada int) returns int
language plpgsql security definer set search_path = '' as $$
declare v int;
begin
  update public.oportunidades set versao = versao + 1, atualizado_em = now()
   where id = p_op and versao = p_esperada returning versao into v;
  if v is null then
    raise exception 'Conflito de versão: o registro foi alterado por outra operação. Recarregue e tente novamente.'
      using errcode = '40001', detail = (select versao::text from public.oportunidades where id = p_op);
  end if;
  return v;
end $$;

-- Idempotência: mesma chave + mesmo usuário => mesma resposta, sem reexecutar.
create or replace function privado.idem_obter(p_chave text, p_rota text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r privado.idempotencia;
begin
  if p_chave is null then return null; end if;
  if length(p_chave) not between 8 and 100 then raise exception 'Chave de idempotência inválida' using errcode = '22023'; end if;
  select * into r from privado.idempotencia where usuario_id = (select auth.uid()) and chave = p_chave;
  if not found then return null; end if;
  if r.rota <> p_rota then raise exception 'Chave de idempotência reutilizada em outra operação' using errcode = '22023'; end if;
  return r.resposta || jsonb_build_object('repeticao', true);
end $$;

create or replace function privado.idem_gravar(p_chave text, p_rota text, p_resposta jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if p_chave is not null then
    insert into privado.idempotencia(usuario_id, chave, rota, resposta) values ((select auth.uid()), p_chave, p_rota, p_resposta);
  end if;
  return p_resposta;
end $$;

create or replace function privado.distribuir(p_ies bigint, p_curso bigint) returns uuid
language sql stable security definer set search_path = '' as $$
  select u.id from public.usuarios u
    join public.escopos e on e.usuario_id = u.id
   where e.ies_id = p_ies and e.papel = 'comercial' and e.revogado_em is null and u.revogado_em is null
     and (e.curso_id is null or e.curso_id = p_curso)
     and (select count(*) from public.tarefas t where t.responsavel_id = u.id and t.status = 'aberta')
         < (select capacidade_atendente from public.ies where id = p_ies)
   group by u.id
   order by (select count(*) from public.tarefas t where t.responsavel_id = u.id and t.status = 'aberta'), u.id
   limit 1;
$$;

-- ---------------------------------------------------------------- Master
create or replace function public.rpc_provisionar_ies(p_nome text, p_plano text, p_campus text, p_cursos jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_ies bigint; v_campus bigint; c jsonb;
begin
  perform privado.exigir_usuario();
  if not privado.eh_master() then raise exception 'Operação restrita ao Master' using errcode = '42501'; end if;
  if jsonb_typeof(p_cursos) <> 'array' or jsonb_array_length(p_cursos) not between 1 and 100 then
    raise exception 'Informe de 1 a 100 cursos' using errcode = '22023';
  end if;
  insert into public.ies(nome, plano) values (p_nome, coalesce(p_plano, 'piloto')) returning id into v_ies;
  insert into public.campus(ies_id, nome) values (v_ies, p_campus) returning id into v_campus;
  for c in select * from jsonb_array_elements(p_cursos) loop
    insert into public.cursos(ies_id, campus_id, nome, turno, modalidade, mensalidade_centavos, desconto_max_pct)
    values (v_ies, v_campus, c->>'nome', c->>'turno', c->>'modalidade', (c->>'mensalidade_centavos')::int, coalesce((c->>'desconto_max_pct')::numeric, 30));
  end loop;
  perform privado.auditar(v_ies, 'ies.provisionar', 'ies', v_ies::text, jsonb_build_object('plano', coalesce(p_plano, 'piloto')));
  return jsonb_build_object('id', v_ies);
end $$;

create or replace function public.rpc_conceder_escopo(p_usuario uuid, p_ies bigint, p_curso bigint, p_papel text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  perform privado.exigir_usuario();
  if not privado.eh_master() then raise exception 'Operação restrita ao Master' using errcode = '42501'; end if;
  if p_curso is not null and not exists (select 1 from public.cursos where id = p_curso and ies_id = p_ies) then
    raise exception 'Curso não pertence à IES' using errcode = '22023';
  end if;
  if exists (select 1 from public.usuarios where id = p_usuario and revogado_em is not null) then
    raise exception 'Usuário revogado' using errcode = '22023';
  end if;
  insert into public.escopos(usuario_id, ies_id, curso_id, papel, concedido_por)
  values (p_usuario, p_ies, p_curso, p_papel, (select auth.uid())) returning id into v_id;
  perform privado.auditar(p_ies, 'escopo.conceder', 'escopo', v_id::text, jsonb_build_object('usuario_id', p_usuario, 'papel', p_papel, 'curso_id', p_curso));
  return jsonb_build_object('escopo_id', v_id);
end $$;

create or replace function public.rpc_revogar_escopo(p_escopo bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare e public.escopos;
begin
  perform privado.exigir_usuario();
  if not privado.eh_master() then raise exception 'Operação restrita ao Master' using errcode = '42501'; end if;
  update public.escopos set revogado_em = coalesce(revogado_em, now()) where id = p_escopo returning * into e;
  if not found then raise exception 'Não encontrado' using errcode = 'P0002'; end if;
  perform privado.auditar(e.ies_id, 'escopo.revogar', 'escopo', p_escopo::text, jsonb_build_object('usuario_id', e.usuario_id));
  return jsonb_build_object('id', p_escopo);
end $$;

create or replace function public.rpc_revogar_usuario(p_usuario uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform privado.exigir_usuario();
  if not privado.eh_master() then raise exception 'Operação restrita ao Master' using errcode = '42501'; end if;
  if p_usuario = (select auth.uid()) then raise exception 'Master não pode revogar a si mesmo' using errcode = '22023'; end if;
  update public.usuarios set revogado_em = coalesce(revogado_em, now()) where id = p_usuario;
  if not found then raise exception 'Não encontrado' using errcode = 'P0002'; end if;
  update public.tarefas set responsavel_id = null where responsavel_id = p_usuario and status = 'aberta';
  perform privado.auditar(null, 'usuario.revogar', 'usuario', p_usuario::text);
  return jsonb_build_object('id', p_usuario);
end $$;

-- ---------------------------------------------------------------- CRM
create or replace function public.rpc_criar_oportunidade(p_ies bigint, p_dados jsonb, p_chave text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_curso bigint := (p_dados->>'curso_id')::bigint;
  v_email text := nullif(lower(trim(p_dados->>'email')), '');
  v_tel text := nullif(regexp_replace(coalesce(p_dados->>'telefone', ''), '\D', '', 'g'), '');
  v_pessoa public.pessoas; v_op public.oportunidades; v_resp uuid; v_canal text; v_sla int; r jsonb;
begin
  perform privado.exigir_usuario();
  r := privado.idem_obter(p_chave, 'criar_oportunidade'); if r is not null then return r; end if;
  if not privado.ve_ies(p_ies) or not exists (select 1 from public.cursos where id = v_curso and ies_id = p_ies) then
    raise exception 'Não encontrado' using errcode = 'P0002';
  end if;
  if not privado.tem_acesso(p_ies, v_curso, array['comercial','gestor']) then
    raise exception 'Seu perfil não tem permissão para esta operação' using errcode = '42501';
  end if;
  if coalesce(p_dados->>'base_legal', '') = '' then raise exception 'Base legal obrigatória (LGPD)' using errcode = '22023'; end if;
  if length(coalesce(trim(p_dados->>'origem'), '')) < 2 then raise exception 'Origem do contato obrigatória' using errcode = '22023'; end if;
  if v_email is null and v_tel is null then raise exception 'Informe e-mail ou telefone' using errcode = '22023'; end if;
  if v_email is not null and v_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' then raise exception 'E-mail inválido' using errcode = '22023'; end if;
  if v_tel is not null and length(v_tel) not between 10 and 13 then raise exception 'Telefone inválido' using errcode = '22023'; end if;

  select * into v_pessoa from public.pessoas
   where ies_id = p_ies and ((email is not null and email = v_email) or (telefone is not null and telefone = v_tel))
   limit 1 for update;
  if not found then
    insert into public.pessoas(ies_id, nome, email, telefone, base_legal, origem)
    values (p_ies, trim(p_dados->>'nome'), v_email, v_tel, p_dados->>'base_legal', trim(p_dados->>'origem')) returning * into v_pessoa;
  end if;
  select * into v_op from public.oportunidades where pessoa_id = v_pessoa.id and curso_id = v_curso and coorte = p_dados->>'coorte';
  if found then
    return privado.idem_gravar(p_chave, 'criar_oportunidade', jsonb_build_object('id', v_op.id, 'duplicada', true, 'versao', v_op.versao, 'etapa', v_op.etapa));
  end if;
  v_resp := privado.distribuir(p_ies, v_curso);
  insert into public.oportunidades(ies_id, curso_id, pessoa_id, forma_ingresso, coorte, responsavel_id)
  values (p_ies, v_curso, v_pessoa.id, p_dados->>'forma_ingresso', p_dados->>'coorte', v_resp) returning * into v_op;
  v_canal := case when not v_pessoa.optout_whatsapp and v_pessoa.telefone is not null then 'whatsapp'
                  when not v_pessoa.optout_email and v_pessoa.email is not null then 'email'
                  when not v_pessoa.optout_telefone and v_pessoa.telefone is not null then 'telefone' end;
  if v_canal is not null then
    select sla_horas into v_sla from public.ies where id = p_ies;
    insert into public.tarefas(ies_id, oportunidade_id, tipo, canal, responsavel_id, vence_em)
    values (p_ies, v_op.id, 'primeiro_contato', v_canal, v_resp, now() + make_interval(hours => v_sla));
  end if;
  perform privado.auditar(p_ies, 'oportunidade.criar', 'oportunidade', v_op.id::text,
    jsonb_build_object('curso_id', v_curso, 'forma_ingresso', v_op.forma_ingresso, 'coorte', v_op.coorte, 'origem', v_pessoa.origem, 'responsavel_id', v_resp));
  return privado.idem_gravar(p_chave, 'criar_oportunidade', jsonb_build_object('id', v_op.id, 'duplicada', false, 'versao', 1, 'etapa', 'novo'));
end $$;

create or replace function public.rpc_mover_etapa(p_op bigint, p_para text, p_versao int, p_motivo text default null, p_chave text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; v int; r jsonb;
  t constant jsonb := '{"novo":["contato","perdido"],"contato":["inscrito","perdido"],"inscrito":["pre_matricula","perdido"],"pre_matricula":["matricula_comercial","perdido"],"perdido":["contato"]}';
begin
  perform privado.exigir_usuario();
  r := privado.idem_obter(p_chave, 'mover_etapa:' || p_op); if r is not null then return r; end if;
  o := privado.carregar_op(p_op, array['comercial','gestor']);
  if p_para in ('confirmado','cancelado') then
    raise exception 'Ingresso e cancelamento só pelas operações próprias' using errcode = '22023';
  end if;
  if not coalesce(t->o.etapa ? p_para, false) then
    raise exception 'Transição inválida: % → %', o.etapa, p_para using errcode = '22023';
  end if;
  if p_para = 'perdido' and length(coalesce(trim(p_motivo), '')) < 3 then
    raise exception 'Motivo da perda obrigatório' using errcode = '22023';
  end if;
  v := privado.exigir_versao(p_op, p_versao);
  update public.oportunidades set etapa = p_para,
    motivo_perda = case when p_para = 'perdido' then trim(p_motivo) end,
    matricula_comercial_em = case when p_para = 'matricula_comercial' then now() else matricula_comercial_em end
   where id = p_op;
  if p_para = 'perdido' then
    update public.tarefas set status = 'cancelada', encerrada_em = now(), resultado = 'oportunidade perdida'
     where oportunidade_id = p_op and status = 'aberta';
  end if;
  if o.etapa = 'perdido' and p_para = 'contato' then
    insert into public.tarefas(ies_id, oportunidade_id, tipo, canal, responsavel_id, vence_em)
    select o.ies_id, o.id, 'recuperacao',
           case when not p.optout_whatsapp and p.telefone is not null then 'whatsapp' when not p.optout_email and p.email is not null then 'email' end,
           coalesce(o.responsavel_id, privado.distribuir(o.ies_id, o.curso_id)), now() + interval '24 hours'
      from public.pessoas p where p.id = o.pessoa_id
       and ((not p.optout_whatsapp and p.telefone is not null) or (not p.optout_email and p.email is not null));
  end if;
  perform privado.auditar(o.ies_id, 'oportunidade.etapa', 'oportunidade', p_op::text,
    jsonb_build_object('de', o.etapa, 'para', p_para, 'motivo', p_motivo, 'versao', v));
  return privado.idem_gravar(p_chave, 'mover_etapa:' || p_op, jsonb_build_object('id', p_op, 'etapa', p_para, 'versao', v));
end $$;

create or replace function public.rpc_validar(p_op bigint, p_dimensao text, p_resultado text, p_evidencia text, p_versao int)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; v int; v_papel text;
begin
  perform privado.exigir_usuario();
  if p_dimensao not in ('documental','financeira','academica') then raise exception 'Dimensão inválida' using errcode = '22023'; end if;
  if p_resultado not in ('valida','invalida','isencao_formal') then raise exception 'Resultado inválido' using errcode = '22023'; end if;
  if p_resultado = 'isencao_formal' and p_dimensao <> 'financeira' then
    raise exception 'Isenção formal só se aplica à dimensão financeira' using errcode = '22023';
  end if;
  if length(coalesce(trim(p_evidencia), '')) not between 5 and 500 then raise exception 'Evidência obrigatória' using errcode = '22023'; end if;
  -- Segregação: secretaria valida documental/acadêmica; financeiro valida financeira; comercial não valida.
  v_papel := case when p_dimensao = 'financeira' then 'financeiro' else 'secretaria' end;
  o := privado.carregar_op(p_op, array[v_papel]);
  if o.etapa <> 'matricula_comercial' then
    raise exception 'Validações só após a matrícula comercial e antes da confirmação' using errcode = '22023';
  end if;
  insert into public.validacoes(oportunidade_id, dimensao, resultado, evidencia, usuario_id)
  values (p_op, p_dimensao, p_resultado, trim(p_evidencia), (select auth.uid()));
  v := privado.exigir_versao(p_op, p_versao);
  update public.oportunidades set
    val_documental = case when p_dimensao = 'documental' then p_resultado <> 'invalida' else val_documental end,
    val_financeira = case when p_dimensao = 'financeira' then p_resultado <> 'invalida' else val_financeira end,
    val_academica  = case when p_dimensao = 'academica'  then p_resultado <> 'invalida' else val_academica end
   where id = p_op;
  perform privado.auditar(o.ies_id, 'oportunidade.validar', 'oportunidade', p_op::text,
    jsonb_build_object('dimensao', p_dimensao, 'resultado', p_resultado, 'versao', v));
  return jsonb_build_object('id', p_op, 'dimensao', p_dimensao, 'resultado', p_resultado, 'versao', v);
end $$;

create or replace function public.rpc_confirmar(p_op bigint, p_versao int)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; v int; faltam text[];
begin
  o := privado.carregar_op(p_op, array['secretaria','gestor']);
  if o.etapa <> 'matricula_comercial' then raise exception 'Confirmação exige matrícula comercial registrada' using errcode = '22023'; end if;
  faltam := array_remove(array[
    case when not o.val_documental then 'documental' end,
    case when not o.val_financeira then 'financeira' end,
    case when not o.val_academica then 'academica' end], null);
  if cardinality(faltam) > 0 then
    raise exception 'Confirmação incompleta: falta validação %', array_to_string(faltam, ', ') using errcode = '22023';
  end if;
  v := privado.exigir_versao(p_op, p_versao);
  update public.oportunidades set etapa = 'confirmado', confirmada_em = now() where id = p_op;
  update public.tarefas set status = 'cancelada', encerrada_em = now(), resultado = 'ingresso confirmado'
   where oportunidade_id = p_op and status = 'aberta';
  perform privado.auditar(o.ies_id, 'oportunidade.confirmar', 'oportunidade', p_op::text, jsonb_build_object('versao', v));
  return jsonb_build_object('id', p_op, 'etapa', 'confirmado', 'versao', v);
end $$;

create or replace function public.rpc_cancelar(p_op bigint, p_versao int, p_motivo text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; v int;
begin
  o := privado.carregar_op(p_op, array['secretaria','gestor']);
  if length(coalesce(trim(p_motivo), '')) < 3 then raise exception 'Motivo do cancelamento obrigatório' using errcode = '22023'; end if;
  if o.etapa not in ('matricula_comercial','confirmado') then
    raise exception 'Só é possível cancelar matrícula comercial ou ingresso confirmado' using errcode = '22023';
  end if;
  v := privado.exigir_versao(p_op, p_versao);
  update public.oportunidades set etapa = 'cancelado', cancelada_em = now(), motivo_cancelamento = trim(p_motivo) where id = p_op;
  update public.tarefas set status = 'cancelada', encerrada_em = now(), resultado = 'matrícula cancelada'
   where oportunidade_id = p_op and status = 'aberta';
  perform privado.auditar(o.ies_id, 'oportunidade.cancelar', 'oportunidade', p_op::text,
    jsonb_build_object('de', o.etapa, 'motivo', p_motivo, 'versao', v));
  return jsonb_build_object('id', p_op, 'etapa', 'cancelado', 'versao', v);
end $$;

-- ---------------------------------------------------------------- propostas
create or replace function public.rpc_criar_proposta(p_op bigint, p_desconto numeric, p_validade_dias int default 7)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; c public.cursos; v_final int; v_status text; v_id bigint;
begin
  o := privado.carregar_op(p_op, array['comercial','gestor']);
  if o.etapa not in ('inscrito','pre_matricula','matricula_comercial') then
    raise exception 'Proposta só para inscrito, pré-matrícula ou matrícula comercial' using errcode = '22023';
  end if;
  if p_desconto is null or p_desconto < 0 or p_desconto > 100 or p_desconto <> round(p_desconto, 2) then
    raise exception 'Desconto deve estar entre 0 e 100, com até duas casas decimais' using errcode = '22023';
  end if;
  if p_validade_dias not between 1 and 30 then raise exception 'Validade deve ser de 1 a 30 dias' using errcode = '22023'; end if;
  select * into c from public.cursos where id = o.curso_id;
  v_final := round(c.mensalidade_centavos * (1 - p_desconto / 100));
  v_status := case when p_desconto > c.desconto_max_pct then 'pendente_aprovacao' else 'aprovada' end;
  insert into public.propostas(ies_id, oportunidade_id, mensalidade_centavos, desconto_pct, valor_final_centavos, validade, status, criado_por)
  values (o.ies_id, p_op, c.mensalidade_centavos, p_desconto, v_final, now() + make_interval(days => p_validade_dias), v_status, (select auth.uid()))
  returning id into v_id;
  perform privado.auditar(o.ies_id, 'proposta.criar', 'oportunidade', p_op::text,
    jsonb_build_object('proposta_id', v_id, 'desconto_pct', p_desconto, 'limite_pct', c.desconto_max_pct, 'status', v_status));
  return jsonb_build_object('id', v_id, 'status', v_status, 'valor_final_centavos', v_final, 'limite_pct', c.desconto_max_pct);
end $$;

create or replace function public.rpc_decidir_proposta(p_proposta bigint, p_decisao text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.propostas; o public.oportunidades; v_status text;
begin
  perform privado.exigir_usuario();
  if p_decisao not in ('aprovar','rejeitar') then raise exception 'Decisão inválida' using errcode = '22023'; end if;
  select * into p from public.propostas where id = p_proposta for update;
  if not found then raise exception 'Não encontrado' using errcode = 'P0002'; end if;
  o := privado.carregar_op(p.oportunidade_id, array['gestor']);
  if p.criado_por = (select auth.uid()) then
    raise exception 'Segregação de funções: quem criou a proposta não pode decidi-la' using errcode = '42501';
  end if;
  if p.status <> 'pendente_aprovacao' then raise exception 'Proposta não está pendente de aprovação' using errcode = '22023'; end if;
  if p.validade < now() then
    update public.propostas set status = 'expirada' where id = p_proposta;
    perform privado.auditar(o.ies_id, 'proposta.expirar', 'oportunidade', o.id::text, jsonb_build_object('proposta_id', p_proposta));
    return jsonb_build_object('id', p_proposta, 'status', 'expirada');
  end if;
  v_status := case when p_decisao = 'aprovar' then 'aprovada' else 'rejeitada' end;
  update public.propostas set status = v_status, decidido_por = (select auth.uid()), decidido_em = now() where id = p_proposta;
  perform privado.auditar(o.ies_id, 'proposta.decidir', 'oportunidade', o.id::text, jsonb_build_object('proposta_id', p_proposta, 'status', v_status));
  return jsonb_build_object('id', p_proposta, 'status', v_status);
end $$;

-- ---------------------------------------------------------------- LGPD
create or replace function public.rpc_optout(p_op bigint, p_canal text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; n int;
begin
  if p_canal not in ('email','whatsapp','telefone') then raise exception 'Canal inválido' using errcode = '22023'; end if;
  o := privado.carregar_op(p_op, array['comercial','gestor','secretaria']);
  update public.pessoas set
    optout_email = optout_email or p_canal = 'email',
    optout_whatsapp = optout_whatsapp or p_canal = 'whatsapp',
    optout_telefone = optout_telefone or p_canal = 'telefone'
   where id = o.pessoa_id;
  update public.tarefas set status = 'suprimida', encerrada_em = now(), resultado = 'opt-out ' || p_canal
   where status = 'aberta' and canal = p_canal
     and oportunidade_id in (select id from public.oportunidades where pessoa_id = o.pessoa_id);
  get diagnostics n = row_count;
  perform privado.auditar(o.ies_id, 'pessoa.optout', 'oportunidade', p_op::text, jsonb_build_object('canal', p_canal, 'tarefas_suprimidas', n));
  return jsonb_build_object('canal', p_canal, 'tarefas_suprimidas', n);
end $$;

-- ---------------------------------------------------------------- leitura com minimização
-- Lista paginada; contatos mascarados para quem não tem papel operacional no curso.
create or replace function public.rpc_listar_oportunidades(p_ies bigint, p_etapa text default null, p_coorte text default null,
  p_pagina int default 1, p_por_pagina int default 25)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare total bigint; itens jsonb;
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then raise exception 'Não encontrado' using errcode = 'P0002'; end if;
  if p_por_pagina not between 1 and 100 or p_pagina < 1 then raise exception 'Paginação inválida' using errcode = '22023'; end if;
  with base as (
    select o.*, c.nome as curso, p.nome, p.email, p.telefone,
           privado.tem_acesso(o.ies_id, o.curso_id, array['gestor','comercial','secretaria','financeiro']) as pleno
      from public.oportunidades o join public.cursos c on c.id = o.curso_id join public.pessoas p on p.id = o.pessoa_id
     where o.ies_id = p_ies
       and privado.tem_acesso(o.ies_id, o.curso_id, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro'])
       and (p_etapa is null or o.etapa = p_etapa) and (p_coorte is null or o.coorte = p_coorte)
  )
  select (select count(*) from base),
         coalesce(jsonb_agg(jsonb_build_object(
           'id', b.id, 'etapa', b.etapa, 'versao', b.versao, 'coorte', b.coorte, 'curso_id', b.curso_id, 'curso', b.curso,
           'nome', b.nome,
           'email', case when b.pleno then b.email when b.email is null then null else left(b.email, 1) || '***@' || split_part(b.email, '@', 2) end,
           'telefone', case when b.pleno then b.telefone when b.telefone is null then null else '***' || right(b.telefone, 4) end,
           'dados_mascarados', not b.pleno) order by b.atualizado_em desc, b.id desc), '[]'::jsonb)
    into total, itens
    from (select * from base order by atualizado_em desc, id desc limit p_por_pagina offset (p_pagina - 1) * p_por_pagina) b;
  return jsonb_build_object('itens', itens, 'total', total, 'pagina', p_pagina, 'por_pagina', p_por_pagina);
end $$;

-- BI por coorte: null = indisponível (≠ 0); ingressantes = pessoas distintas no consolidado.
create or replace function public.rpc_bi(p_ies bigint, p_coorte text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare t record; v_meta bigint; v_metas int; linhas jsonb; v_total boolean;
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then raise exception 'Não encontrado' using errcode = 'P0002'; end if;
  if p_coorte !~ '^\d{4}\.[12]$' then raise exception 'Coorte deve ter formato AAAA.1 ou AAAA.2' using errcode = '22023'; end if;
  v_total := privado.tem_acesso_ies(p_ies, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro']);
  select count(*) as oportunidades,
         count(*) filter (where o.matricula_comercial_em is not null) as matriculas_comerciais,
         count(distinct o.pessoa_id) filter (where o.etapa = 'confirmado') as ingressantes,
         count(*) filter (where o.etapa = 'cancelado') as cancelamentos,
         count(*) filter (where o.etapa = 'perdido') as perdidos
    into t
    from public.oportunidades o
   where o.ies_id = p_ies and o.coorte = p_coorte
     and privado.tem_acesso(o.ies_id, o.curso_id, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro']);
  select count(*), sum(m.meta) into v_metas, v_meta from public.metas m
   where m.ies_id = p_ies and m.coorte = p_coorte
     and privado.tem_acesso(m.ies_id, m.curso_id, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro']);
  if v_metas = 0 then v_meta := null; end if;
  select coalesce(jsonb_agg(jsonb_build_object('curso_id', x.curso_id, 'curso', x.curso, 'oportunidades', x.n, 'ingressantes', x.ing,
           'conversao', case when x.n = 0 then null else round(x.ing::numeric / x.n, 4) end,
           'meta', x.meta,
           'atingimento', case when x.meta is null or x.meta = 0 then null else round(x.ing::numeric / x.meta, 4) end) order by x.curso), '[]'::jsonb)
    into linhas
    from (select c.id as curso_id, c.nome || ' · ' || c.turno as curso, count(o.id) as n,
                 count(distinct o.pessoa_id) filter (where o.etapa = 'confirmado') as ing,
                 (select m.meta from public.metas m where m.ies_id = p_ies and m.curso_id = c.id and m.coorte = p_coorte) as meta
            from public.cursos c join public.oportunidades o on o.curso_id = c.id and o.coorte = p_coorte
           where c.ies_id = p_ies and privado.tem_acesso(c.ies_id, c.id, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro'])
           group by c.id, c.nome, c.turno) x;
  return jsonb_build_object(
    'coorte', p_coorte, 'cobertura', case when v_total then 'ies' else 'cursos_autorizados' end,
    'totais', jsonb_build_object(
      'oportunidades', t.oportunidades, 'matriculas_comerciais', t.matriculas_comerciais, 'ingressantes', t.ingressantes,
      'cancelamentos', t.cancelamentos, 'perdidos', t.perdidos,
      'conversao', case when t.oportunidades = 0 then null else round(t.ingressantes::numeric / t.oportunidades, 4) end,
      'meta', v_meta,
      'atingimento', case when v_meta is null or v_meta = 0 then null else round(t.ingressantes::numeric / v_meta, 4) end),
    'linhas', linhas);
end $$;

-- ---------------------------------------------------------------- permissões de execução
-- Supabase concede EXECUTE em funções novas a anon/authenticated por padrão: restringe explicitamente.
revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.rpc_provisionar_ies(text, text, text, jsonb), public.rpc_conceder_escopo(uuid, bigint, bigint, text),
  public.rpc_revogar_escopo(bigint), public.rpc_revogar_usuario(uuid),
  public.rpc_criar_oportunidade(bigint, jsonb, text), public.rpc_mover_etapa(bigint, text, int, text, text),
  public.rpc_validar(bigint, text, text, text, int), public.rpc_confirmar(bigint, int), public.rpc_cancelar(bigint, int, text),
  public.rpc_criar_proposta(bigint, numeric, int), public.rpc_decidir_proposta(bigint, text),
  public.rpc_optout(bigint, text), public.rpc_listar_oportunidades(bigint, text, text, int, int), public.rpc_bi(bigint, text)
to authenticated;
-- Auxiliares de escrita (auditar, versão, idempotência...) NÃO são executáveis pelo cliente.
revoke execute on all functions in schema privado from public, anon, authenticated;
grant execute on function privado.usuario_ativo(), privado.eh_master(), privado.tem_acesso(bigint, bigint, text[]),
  privado.tem_acesso_ies(bigint, text[]), privado.ve_ies(bigint), privado.ve_oportunidade(bigint, text[]) to authenticated;
