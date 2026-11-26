-- Matrícula 360° — migração 6 (códigos HTTP 404/409) para colar no SQL Editor do projeto jbimijcvvekomovodfze.
-- Pode ser executada mais de uma vez. Transação única.
begin;
-- Matrícula 360° — migração 6: códigos HTTP corretos para "não encontrado" (404) e conflito de versão (409).
-- Gerada por scripts/gerar-migracao-6.mjs. Achado da homologação no Supabase real (25/11/2026):
--   P0002 chegava como HTTP 500; 40001 fazia o PostgREST repetir a transação até "upstream request timeout".
-- Usa SQLSTATE 'PGRST' (recurso do PostgREST) para fixar o status HTTP. Comportamento e regras inalterados.

create or replace function privado.erro_http(p_status int, p_codigo text, p_mensagem text, p_detalhe text default null)
returns void language plpgsql set search_path = '' as $$
begin
  raise sqlstate 'PGRST' using
    message = json_build_object('code', p_codigo, 'message', p_mensagem, 'details', p_detalhe, 'hint', null)::text,
    detail = json_build_object('status', p_status, 'headers', json_build_object())::text;
end $$;
revoke execute on function privado.erro_http(int, text, text, text) from public, anon, authenticated;

create or replace function privado.exigir_versao(p_op bigint, p_esperada int) returns int
language plpgsql security definer set search_path = '' as $$
declare v int;
begin
  update public.oportunidades set versao = versao + 1, atualizado_em = now()
   where id = p_op and versao = p_esperada returning versao into v;
  if v is null then
    perform privado.erro_http(409, '40001',
      'Conflito de versão: o registro foi alterado por outra operação. Recarregue e tente novamente.',
      (select versao::text from public.oportunidades where id = p_op));
  end if;
  return v;
end $$;

-- privado.carregar_op
create or replace function privado.carregar_op(p_op bigint, p_papeis text[]) returns public.oportunidades
language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades;
begin
  perform privado.exigir_usuario();
  select * into o from public.oportunidades where id = p_op for update;
  if not found or not privado.tem_acesso(o.ies_id, o.curso_id, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro']) then
    perform privado.erro_http(404, 'P0002', 'Não encontrado');
  end if;
  if not privado.tem_acesso(o.ies_id, o.curso_id, p_papeis) then
    raise exception 'Seu perfil não tem permissão para esta operação' using errcode = '42501';
  end if;
  return o;
end $$;

-- public.rpc_revogar_escopo
create or replace function public.rpc_revogar_escopo(p_escopo bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare e public.escopos;
begin
  perform privado.exigir_usuario();
  if not privado.eh_master() then raise exception 'Operação restrita ao Master' using errcode = '42501'; end if;
  update public.escopos set revogado_em = coalesce(revogado_em, now()) where id = p_escopo returning * into e;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.auditar(e.ies_id, 'escopo.revogar', 'escopo', p_escopo::text, jsonb_build_object('usuario_id', e.usuario_id));
  return jsonb_build_object('id', p_escopo);
end $$;

-- public.rpc_revogar_usuario
create or replace function public.rpc_revogar_usuario(p_usuario uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform privado.exigir_usuario();
  if not privado.eh_master() then raise exception 'Operação restrita ao Master' using errcode = '42501'; end if;
  if p_usuario = (select auth.uid()) then raise exception 'Master não pode revogar a si mesmo' using errcode = '22023'; end if;
  update public.usuarios set revogado_em = coalesce(revogado_em, now()) where id = p_usuario;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  update public.tarefas set responsavel_id = null where responsavel_id = p_usuario and status = 'aberta';
  perform privado.auditar(null, 'usuario.revogar', 'usuario', p_usuario::text);
  return jsonb_build_object('id', p_usuario);
end $$;

-- public.rpc_criar_oportunidade
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
    perform privado.erro_http(404, 'P0002', 'Não encontrado');
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

-- public.rpc_decidir_proposta
create or replace function public.rpc_decidir_proposta(p_proposta bigint, p_decisao text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.propostas; o public.oportunidades; v_status text;
begin
  perform privado.exigir_usuario();
  if p_decisao not in ('aprovar','rejeitar') then raise exception 'Decisão inválida' using errcode = '22023'; end if;
  select * into p from public.propostas where id = p_proposta for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
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

-- public.rpc_listar_oportunidades
create or replace function public.rpc_listar_oportunidades(p_ies bigint, p_etapa text default null, p_coorte text default null,
  p_pagina int default 1, p_por_pagina int default 25, p_curso bigint default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare total bigint; itens jsonb;
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if p_por_pagina not between 1 and 100 or p_pagina < 1 then raise exception 'Paginação inválida' using errcode = '22023'; end if;
  with base as (
    select o.*, c.nome as curso, c.turno, p.nome, p.email, p.telefone, r.nome as responsavel,
           privado.tem_acesso(o.ies_id, o.curso_id, array['gestor','comercial','secretaria','financeiro']) as pleno
      from public.oportunidades o join public.cursos c on c.id = o.curso_id join public.pessoas p on p.id = o.pessoa_id
      left join public.usuarios r on r.id = o.responsavel_id
     where o.ies_id = p_ies
       and privado.tem_acesso(o.ies_id, o.curso_id, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro'])
       and (p_etapa is null or o.etapa = p_etapa) and (p_coorte is null or o.coorte = p_coorte) and (p_curso is null or o.curso_id = p_curso)
  )
  select (select count(*) from base),
         coalesce(jsonb_agg(jsonb_build_object(
           'id', b.id, 'etapa', b.etapa, 'versao', b.versao, 'coorte', b.coorte, 'curso_id', b.curso_id, 'curso', b.curso, 'turno', b.turno,
           'forma_ingresso', b.forma_ingresso, 'responsavel', b.responsavel, 'nome', b.nome,
           'val_documental', b.val_documental, 'val_financeira', b.val_financeira, 'val_academica', b.val_academica,
           'email', case when b.pleno then b.email else privado.mascarar_email(b.email) end,
           'telefone', case when b.pleno then b.telefone else privado.mascarar_tel(b.telefone) end,
           'dados_mascarados', not b.pleno) order by b.atualizado_em desc, b.id desc), '[]'::jsonb)
    into total, itens
    from (select * from base order by atualizado_em desc, id desc limit p_por_pagina offset (p_pagina - 1) * p_por_pagina) b;
  return jsonb_build_object('itens', itens, 'total', total, 'pagina', p_pagina, 'por_pagina', p_por_pagina);
end $$;

-- public.rpc_bi
create or replace function public.rpc_bi(p_ies bigint, p_coorte text, p_agrupar text default 'curso')
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare t record; v_meta bigint; v_metas int; linhas jsonb; v_total boolean;
  todos text[] := array['gestor','reitoria','coordenador','comercial','secretaria','financeiro'];
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if p_coorte !~ '^\d{4}\.[12]$' then raise exception 'Coorte deve ter formato AAAA.1 ou AAAA.2' using errcode = '22023'; end if;
  if p_agrupar not in ('curso','turno','modalidade','forma_ingresso','atendente') then raise exception 'Agrupamento inválido' using errcode = '22023'; end if;
  v_total := privado.tem_acesso_ies(p_ies, todos);
  select count(*) as oportunidades,
         count(*) filter (where o.matricula_comercial_em is not null) as matriculas_comerciais,
         count(distinct o.pessoa_id) filter (where o.etapa = 'confirmado') as ingressantes,
         count(*) filter (where o.etapa = 'cancelado') as cancelamentos,
         count(*) filter (where o.etapa = 'perdido') as perdidos
    into t
    from public.oportunidades o
   where o.ies_id = p_ies and o.coorte = p_coorte and privado.tem_acesso(o.ies_id, o.curso_id, todos);
  select count(*), sum(m.meta) into v_metas, v_meta from public.metas m
   where m.ies_id = p_ies and m.coorte = p_coorte and privado.tem_acesso(m.ies_id, m.curso_id, todos);
  if v_metas = 0 then v_meta := null; end if;
  select coalesce(jsonb_agg(jsonb_build_object('chave', x.chave, 'curso_id', x.curso_id, 'oportunidades', x.n,
           'matriculas_comerciais', x.mc, 'ingressantes', x.ing, 'cancelamentos', x.canc, 'perdidos', x.perd,
           'conversao', case when x.n = 0 then null else round(x.ing::numeric / x.n, 4) end,
           'meta', m.meta,
           'atingimento', case when m.meta is null or m.meta = 0 then null else round(x.ing::numeric / m.meta, 4) end) order by x.chave), '[]'::jsonb)
    into linhas
    from (select case p_agrupar when 'curso' then c.nome || ' · ' || c.turno when 'turno' then c.turno when 'modalidade' then c.modalidade
                   when 'forma_ingresso' then o.forma_ingresso else coalesce(r.nome, 'Sem responsável') end as chave,
                 case when p_agrupar = 'curso' then c.id end as curso_id,
                 count(*) as n,
                 count(*) filter (where o.matricula_comercial_em is not null) as mc,
                 count(distinct o.pessoa_id) filter (where o.etapa = 'confirmado') as ing,
                 count(*) filter (where o.etapa = 'cancelado') as canc,
                 count(*) filter (where o.etapa = 'perdido') as perd
            from public.oportunidades o join public.cursos c on c.id = o.curso_id left join public.usuarios r on r.id = o.responsavel_id
           where o.ies_id = p_ies and o.coorte = p_coorte and privado.tem_acesso(o.ies_id, o.curso_id, todos)
           group by 1, 2) x
    left join public.metas m on x.curso_id is not null and m.ies_id = p_ies and m.curso_id = x.curso_id and m.coorte = p_coorte;
  return jsonb_build_object(
    'coorte', p_coorte, 'agrupar', p_agrupar, 'cobertura', case when v_total then 'ies' else 'cursos_autorizados' end,
    'totais', jsonb_build_object(
      'oportunidades', t.oportunidades, 'matriculas_comerciais', t.matriculas_comerciais, 'ingressantes', t.ingressantes,
      'cancelamentos', t.cancelamentos, 'perdidos', t.perdidos,
      'conversao', case when t.oportunidades = 0 then null else round(t.ingressantes::numeric / t.oportunidades, 4) end,
      'meta', v_meta,
      'atingimento', case when v_meta is null or v_meta = 0 then null else round(t.ingressantes::numeric / v_meta, 4) end,
      'projecao_oportunidades_necessarias', case when v_meta is null or t.oportunidades = 0 or t.ingressantes = 0 then null
        else ceil(greatest(v_meta - t.ingressantes, 0) / (t.ingressantes::numeric / t.oportunidades)) end),
    'linhas', linhas);
end $$;

-- public.rpc_alterar_status_ies
create or replace function public.rpc_alterar_status_ies(p_ies bigint, p_status text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform privado.exigir_usuario();
  if not privado.eh_master() then raise exception 'Operação restrita ao Master' using errcode = '42501'; end if;
  if p_status not in ('ativa','suspensa') then raise exception 'Status inválido' using errcode = '22023'; end if;
  update public.ies set status = p_status where id = p_ies;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.auditar(p_ies, 'ies.status', 'ies', p_ies::text, jsonb_build_object('status', p_status));
  return jsonb_build_object('id', p_ies, 'status', p_status);
end $$;

-- public.rpc_configurar
create or replace function public.rpc_configurar(p_ies bigint, p_sla_horas int default null, p_max_followups int default null,
  p_dias_sem_contato int default null, p_capacidade_atendente int default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.ies;
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
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

-- public.rpc_definir_meta
create or replace function public.rpc_definir_meta(p_ies bigint, p_curso bigint, p_coorte text, p_meta int)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform privado.exigir_usuario();
  if not exists (select 1 from public.cursos where id = p_curso and ies_id = p_ies)
     or not privado.tem_acesso(p_ies, p_curso, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro']) then
    perform privado.erro_http(404, 'P0002', 'Não encontrado');
  end if;
  if not privado.tem_acesso(p_ies, p_curso, array['gestor']) then raise exception 'Seu perfil não tem permissão para esta operação' using errcode = '42501'; end if;
  if p_coorte !~ '^\d{4}\.[12]$' then raise exception 'Coorte deve ter formato AAAA.1 ou AAAA.2' using errcode = '22023'; end if;
  if p_meta is null or p_meta not between 0 and 100000 then raise exception 'Meta inválida' using errcode = '22023'; end if;
  insert into public.metas(ies_id, curso_id, coorte, meta) values (p_ies, p_curso, p_coorte, p_meta)
  on conflict (ies_id, curso_id, coorte) do update set meta = excluded.meta;
  perform privado.auditar(p_ies, 'meta.definir', 'curso', p_curso::text, jsonb_build_object('coorte', p_coorte, 'meta', p_meta));
  return jsonb_build_object('curso_id', p_curso, 'coorte', p_coorte, 'meta', p_meta);
end $$;

-- public.rpc_aceitar_proposta
create or replace function public.rpc_aceitar_proposta(p_proposta bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.propostas; o public.oportunidades;
begin
  perform privado.exigir_usuario();
  select * into p from public.propostas where id = p_proposta for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
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

-- public.rpc_fila
create or replace function public.rpc_fila(p_ies bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare so_minhas boolean; r jsonb;
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if not exists (select 1 from public.escopos e where e.usuario_id = (select auth.uid()) and e.ies_id = p_ies and e.revogado_em is null
                 and e.papel in ('gestor','comercial','secretaria','financeiro')) then
    raise exception 'Seu perfil não tem permissão para esta operação' using errcode = '42501';
  end if;
  so_minhas := not exists (select 1 from public.escopos e where e.usuario_id = (select auth.uid()) and e.ies_id = p_ies
                           and e.revogado_em is null and e.papel in ('gestor','secretaria','financeiro'));
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'tipo', t.tipo, 'canal', t.canal, 'vence_em', t.vence_em,
           'oportunidade_id', t.oportunidade_id, 'responsavel_id', t.responsavel_id, 'responsavel', privado.nome_usuario(t.responsavel_id),
           'etapa', o.etapa, 'curso', c.nome, 'nome', p.nome, 'atrasada', t.vence_em < now()) order by t.vence_em), '[]'::jsonb)
    into r
    from (select * from public.tarefas where ies_id = p_ies and status = 'aberta' order by vence_em limit 200) t
    join public.oportunidades o on o.id = t.oportunidade_id
    join public.cursos c on c.id = o.curso_id
    join public.pessoas p on p.id = o.pessoa_id
   where privado.tem_acesso(o.ies_id, o.curso_id, array['gestor','comercial','secretaria','financeiro'])
     and (not so_minhas or t.responsavel_id = (select auth.uid()));
  return jsonb_build_object('tarefas', r, 'envio_externo', 'desativado');
end $$;

-- public.rpc_ciclo_maim
create or replace function public.rpc_ciclo_maim(p_ies bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare cfg public.ies; o record; v_canal text; n_follow int; rel jsonb;
  c_follow int := 0; c_supr int := 0; c_lim int := 0; c_pend int := 0; c_redis int := 0; c_atras int;
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
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

-- privado.carregar_tarefa
create or replace function privado.carregar_tarefa(p_tarefa bigint) returns public.tarefas
language plpgsql security definer set search_path = '' as $$
declare t public.tarefas; o public.oportunidades;
begin
  select * into t from public.tarefas where id = p_tarefa for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  o := privado.carregar_op(t.oportunidade_id, case when t.tipo = 'pendencia_validacao'
         then array['gestor','secretaria','financeiro'] else array['gestor','comercial'] end);
  if t.tipo <> 'pendencia_validacao' and not privado.tem_acesso(o.ies_id, o.curso_id, array['gestor'])
     and t.responsavel_id is distinct from (select auth.uid()) then
    raise exception 'Tarefa atribuída a outro atendente' using errcode = '42501';
  end if;
  return t;
end $$;

-- public.rpc_pendencias
create or replace function public.rpc_pendencias(p_ies bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare r jsonb;
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'versao', o.versao, 'etapa', o.etapa, 'coorte', o.coorte, 'curso', c.nome, 'nome', p.nome,
           'val_documental', o.val_documental, 'val_financeira', o.val_financeira, 'val_academica', o.val_academica,
           'confirmada_em', o.confirmada_em, 'cancelada_em', o.cancelada_em)
           order by o.etapa = 'matricula_comercial' desc, o.atualizado_em desc), '[]'::jsonb)
    into r
    from (select * from public.oportunidades where ies_id = p_ies and etapa in ('matricula_comercial','confirmado','cancelado')
           order by etapa = 'matricula_comercial' desc, atualizado_em desc limit 200) o
    join public.cursos c on c.id = o.curso_id
    join public.pessoas p on p.id = o.pessoa_id
   where privado.tem_acesso(o.ies_id, o.curso_id, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro']);
  return r;
end $$;

-- public.rpc_estrutura
create or replace function public.rpc_estrutura(p_ies bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare i public.ies;
  todos text[] := array['gestor','reitoria','coordenador','comercial','secretaria','financeiro'];
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  select * into i from public.ies where id = p_ies;
  return jsonb_build_object(
    'ies', jsonb_build_object('id', i.id, 'nome', i.nome, 'plano', i.plano, 'sla_horas', i.sla_horas, 'max_followups', i.max_followups,
                              'dias_sem_contato', i.dias_sem_contato, 'capacidade_atendente', i.capacidade_atendente),
    'papeis', (select coalesce(jsonb_agg(distinct e.papel), '[]'::jsonb) from public.escopos e
               where e.usuario_id = (select auth.uid()) and e.ies_id = p_ies and e.revogado_em is null),
    'acesso_total', privado.tem_acesso_ies(p_ies, todos),
    'cursos', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.nome, 'turno', c.turno, 'modalidade', c.modalidade,
                 'mensalidade_centavos', c.mensalidade_centavos, 'desconto_max_pct', c.desconto_max_pct, 'campus', cp.nome) order by c.nome), '[]'::jsonb)
               from public.cursos c join public.campus cp on cp.id = c.campus_id
               where c.ies_id = p_ies and privado.tem_acesso(p_ies, c.id, todos)),
    'coortes', (select coalesce(jsonb_agg(x.coorte order by x.coorte desc), '[]'::jsonb) from (
                 select distinct o.coorte from public.oportunidades o where o.ies_id = p_ies and privado.tem_acesso(o.ies_id, o.curso_id, todos)
                 union select distinct m.coorte from public.metas m where m.ies_id = p_ies and privado.tem_acesso(m.ies_id, m.curso_id, todos)) x),
    'etapas', '["novo","contato","inscrito","pre_matricula","matricula_comercial","confirmado","perdido","cancelado"]'::jsonb,
    'formas_ingresso', '["vestibular","enem","transferencia","segunda_graduacao","reingresso","indicacao","convenio","visita_escolar","evento","pos_graduacao"]'::jsonb,
    'bases_legais', '["consentimento","procedimentos_preliminares_contrato","legitimo_interesse"]'::jsonb,
    'canais', '["email","whatsapp","telefone"]'::jsonb);
end $$;

-- public.rpc_detalhe
create or replace function public.rpc_detalhe(p_op bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare o public.oportunidades; p public.pessoas; c public.cursos; pleno boolean;
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
    'validacoes', (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'dimensao', v.dimensao, 'resultado', v.resultado,
                     'evidencia', v.evidencia, 'em', v.em, 'por', privado.nome_usuario(v.usuario_id)) order by v.id), '[]'::jsonb)
                   from public.validacoes v where v.oportunidade_id = o.id),
    'propostas', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'desconto_pct', x.desconto_pct, 'mensalidade_centavos', x.mensalidade_centavos,
                     'valor_final_centavos', x.valor_final_centavos, 'validade', x.validade, 'status', x.status) order by x.id desc), '[]'::jsonb)
                  from public.propostas x where x.oportunidade_id = o.id
                    and privado.tem_acesso(o.ies_id, o.curso_id, array['gestor','comercial'])),
    'tarefas', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'tipo', x.tipo, 'canal', x.canal, 'status', x.status,
                     'vence_em', x.vence_em, 'resultado', x.resultado) order by x.id desc), '[]'::jsonb)
                from public.tarefas x where x.oportunidade_id = o.id),
    'historico', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'acao', a.acao, 'dados', a.dados, 'em', a.em,
                     'por', privado.nome_usuario(a.usuario_id)) order by a.id), '[]'::jsonb)
                  from public.auditoria a where a.entidade = 'oportunidade' and a.entidade_id = o.id::text));
end $$;

-- public.rpc_listar_propostas
create or replace function public.rpc_listar_propostas(p_ies bigint, p_status text default 'pendente_aprovacao')
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if not exists (select 1 from public.escopos e where e.usuario_id = (select auth.uid()) and e.ies_id = p_ies
                 and e.revogado_em is null and e.papel in ('gestor','comercial')) then
    raise exception 'Seu perfil não tem permissão para esta operação' using errcode = '42501';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'oportunidade_id', x.oportunidade_id, 'desconto_pct', x.desconto_pct,
            'valor_final_centavos', x.valor_final_centavos, 'mensalidade_centavos', x.mensalidade_centavos, 'validade', x.validade,
            'status', x.status, 'criado_por', x.criado_por, 'criado_por_nome', privado.nome_usuario(x.criado_por),
            'curso', c.nome, 'desconto_max_pct', c.desconto_max_pct, 'nome', p.nome) order by x.id desc), '[]'::jsonb)
    from (select * from public.propostas where ies_id = p_ies and status = p_status order by id desc limit 200) x
    join public.oportunidades o on o.id = x.oportunidade_id join public.cursos c on c.id = o.curso_id join public.pessoas p on p.id = o.pessoa_id
   where privado.tem_acesso(o.ies_id, o.curso_id, array['gestor','comercial']));
end $$;

-- public.rpc_auditoria
create or replace function public.rpc_auditoria(p_ies bigint, p_pagina int default 1)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if not privado.tem_acesso_ies(p_ies, array['gestor']) then raise exception 'Seu perfil não tem permissão para esta operação' using errcode = '42501'; end if;
  if p_pagina < 1 then raise exception 'Paginação inválida' using errcode = '22023'; end if;
  return jsonb_build_object(
    'total', (select count(*) from public.auditoria where ies_id = p_ies), 'pagina', p_pagina, 'por_pagina', 50,
    'itens', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'acao', a.acao, 'entidade', a.entidade, 'entidade_id', a.entidade_id,
                'dados', a.dados, 'em', a.em, 'por', privado.nome_usuario(a.usuario_id)) order by a.id desc), '[]'::jsonb)
              from (select * from public.auditoria where ies_id = p_ies order by id desc limit 50 offset (p_pagina - 1) * 50) a));
end $$;

-- public.rpc_master_acessos
create or replace function public.rpc_master_acessos(p_ies bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.exigir_usuario();
  if not privado.eh_master() then raise exception 'Operação restrita ao Master' using errcode = '42501'; end if;
  if not exists (select 1 from public.ies where id = p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  return jsonb_build_object(
    'cursos', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.nome, 'turno', c.turno, 'modalidade', c.modalidade, 'campus', cp.nome) order by c.nome), '[]'::jsonb)
               from public.cursos c join public.campus cp on cp.id = c.campus_id where c.ies_id = p_ies),
    'escopos', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'papel', e.papel, 'curso_id', e.curso_id, 'curso_nome', c.nome,
                  'concedido_em', e.concedido_em, 'revogado_em', e.revogado_em, 'usuario_id', u.id, 'nome', u.nome,
                  'email', (select au.email from auth.users au where au.id = u.id), 'usuario_revogado_em', u.revogado_em)
                  order by e.revogado_em is not null, u.nome), '[]'::jsonb)
                from public.escopos e join public.usuarios u on u.id = e.usuario_id left join public.cursos c on c.id = e.curso_id
               where e.ies_id = p_ies));
end $$;
commit;
