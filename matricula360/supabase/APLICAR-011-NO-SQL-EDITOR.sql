-- Matrícula 360° — migração 11 (governança) para o SQL Editor do projeto jbimijcvvekomovodfze.
-- CONFIRA o projeto na URL antes de executar. Idempotente. Transação única. A última linha deve ser commit;
begin;
-- Matrícula 360° — migração 11: governança (Bíblia v0.2 §9 e E10).
--   (1) Abrangência EXPLÍCITA do escopo: 'ies', 'campus' ou 'curso'. Campo nulo deixa de significar "tudo":
--       o banco exige a abrangência declarada e coerente com campus/curso.
--   (2) Escopo por campus: cobre os cursos daquele campus, e só eles.
--   (3) Matriz de permissões por operação e módulo, legível pela interface e conferida por teste contra as RPCs.
--   (4) Exportação de oportunidades com autorização no servidor, minimização de dados pessoais e auditoria sem PII.
-- Idempotente.

-- ---------------------------------------------------------------- (1) abrangência explícita
alter table public.escopos add column if not exists campus_id bigint references public.campus(id);
alter table public.escopos add column if not exists abrangencia text;
update public.escopos set abrangencia = case when curso_id is not null then 'curso' else 'ies' end where abrangencia is null;
alter table public.escopos alter column abrangencia set not null;
create index if not exists escopos_campus on public.escopos(campus_id);

do $$
declare c text;
begin
  -- remove a regra antiga do coordenador (será refeita considerando campus)
  for c in select conname from pg_constraint where conrelid = 'public.escopos'::regclass and contype = 'c'
             and pg_get_constraintdef(oid) like '%coordenador%' and conname <> 'escopo_coordenador' loop
    execute format('alter table public.escopos drop constraint %I', c);
  end loop;
  if not exists (select 1 from pg_constraint where conname = 'escopo_abrangencia') then
    alter table public.escopos add constraint escopo_abrangencia check (
      (abrangencia = 'ies' and campus_id is null and curso_id is null) or
      (abrangencia = 'campus' and campus_id is not null and curso_id is null) or
      (abrangencia = 'curso' and curso_id is not null and campus_id is null));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'escopo_coordenador') then
    alter table public.escopos add constraint escopo_coordenador check (papel <> 'coordenador' or abrangencia in ('campus', 'curso'));
  end if;
end $$;

drop index if exists public.escopo_unico;
create unique index if not exists escopo_unico_v2 on public.escopos(usuario_id, ies_id, abrangencia, coalesce(campus_id, 0), coalesce(curso_id, 0), papel)
  where revogado_em is null;

-- Campus e curso do escopo precisam pertencer à IES do escopo.
create or replace function privado.validar_escopo() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.campus_id is not null and not exists (select 1 from public.campus where id = new.campus_id and ies_id = new.ies_id) then
    raise exception 'Campus não pertence à IES' using errcode = '22023';
  end if;
  if new.curso_id is not null and not exists (select 1 from public.cursos where id = new.curso_id and ies_id = new.ies_id) then
    raise exception 'Curso não pertence à IES' using errcode = '22023';
  end if;
  return new;
end $$;
revoke execute on function privado.validar_escopo() from public, anon, authenticated;
drop trigger if exists escopo_valida on public.escopos;
create trigger escopo_valida before insert or update of ies_id, campus_id, curso_id on public.escopos
  for each row execute function privado.validar_escopo();

-- Um escopo cobre o curso? Única regra de cobertura, usada por todas as verificações.
create or replace function privado.escopo_cobre(p_abrangencia text, p_campus bigint, p_curso_escopo bigint, p_curso bigint) returns boolean
language sql stable security definer set search_path = '' as $$
  select case p_abrangencia
    when 'ies' then true
    when 'curso' then p_curso is not null and p_curso_escopo = p_curso
    when 'campus' then p_curso is not null and exists (select 1 from public.cursos c where c.id = p_curso and c.campus_id = p_campus)
    else false end;
$$;
revoke execute on function privado.escopo_cobre(text, bigint, bigint, bigint) from public, anon, authenticated;

create or replace function privado.tem_acesso(p_ies bigint, p_curso bigint, p_papeis text[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.escopos e
      join public.usuarios u on u.id = e.usuario_id
      join public.ies i on i.id = e.ies_id
    where e.usuario_id = (select auth.uid()) and e.revogado_em is null and u.revogado_em is null
      and i.status = 'ativa' and e.ies_id = p_ies and e.papel = any (p_papeis)
      and privado.escopo_cobre(e.abrangencia, e.campus_id, e.curso_id, p_curso)
  );
$$;

-- Operações de instituição inteira exigem abrangência 'ies' declarada.
create or replace function privado.tem_acesso_ies(p_ies bigint, p_papeis text[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.escopos e
      join public.usuarios u on u.id = e.usuario_id
      join public.ies i on i.id = e.ies_id
    where e.usuario_id = (select auth.uid()) and e.revogado_em is null and u.revogado_em is null
      and i.status = 'ativa' and e.ies_id = p_ies and e.papel = any (p_papeis) and e.abrangencia = 'ies'
  );
$$;

create or replace function privado.distribuir(p_ies bigint, p_curso bigint) returns uuid
language sql stable security definer set search_path = '' as $$
  select u.id from public.usuarios u
    join public.escopos e on e.usuario_id = u.id
   where e.ies_id = p_ies and e.papel = 'comercial' and e.revogado_em is null and u.revogado_em is null
     and privado.escopo_cobre(e.abrangencia, e.campus_id, e.curso_id, p_curso)
     and (select count(*) from public.tarefas t where t.responsavel_id = u.id and t.status = 'aberta')
         < (select capacidade_atendente from public.ies where id = p_ies)
   group by u.id
   order by (select count(*) from public.tarefas t where t.responsavel_id = u.id and t.status = 'aberta'), u.id
   limit 1;
$$;

create or replace function public.rpc_reatribuir(p_op bigint, p_responsavel uuid, p_motivo text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; n int;
begin
  o := privado.carregar_op(p_op, array['gestor']);
  if length(coalesce(trim(p_motivo), '')) < 3 then raise exception 'Motivo da reatribuição obrigatório' using errcode = '22023'; end if;
  if not exists (select 1 from public.escopos e join public.usuarios u on u.id = e.usuario_id
                 where e.usuario_id = p_responsavel and e.ies_id = o.ies_id and e.papel = 'comercial' and e.revogado_em is null
                   and u.revogado_em is null and privado.escopo_cobre(e.abrangencia, e.campus_id, e.curso_id, o.curso_id)) then
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

create or replace function public.rpc_atendentes(p_ies bigint, p_curso bigint default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  -- Sem curso: exige gestor da instituição. Com curso: basta gestor cujo escopo cubra o curso (inclui gestor de campus).
  if (p_curso is null and not privado.tem_acesso_ies(p_ies, array['gestor']))
     or (p_curso is not null and not privado.tem_acesso(p_ies, p_curso, array['gestor'])) then
    raise exception 'Seu perfil não tem permissão para esta operação' using errcode = '42501';
  end if;
  return (select coalesce(jsonb_agg(distinct jsonb_build_object('id', u.id, 'nome', u.nome)), '[]'::jsonb)
            from public.escopos e join public.usuarios u on u.id = e.usuario_id
           where e.ies_id = p_ies and e.papel = 'comercial' and e.revogado_em is null and u.revogado_em is null
             and (p_curso is null or privado.escopo_cobre(e.abrangencia, e.campus_id, e.curso_id, p_curso)));
end $$;

-- ---------------------------------------------------------------- concessão com abrangência declarada
drop function if exists public.rpc_conceder_escopo_email(text, text, bigint, bigint, text);
drop function if exists public.rpc_conceder_escopo(uuid, bigint, bigint, text);

create or replace function public.rpc_conceder_escopo(p_usuario uuid, p_ies bigint, p_curso bigint, p_papel text, p_campus bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id bigint; v_abr text;
begin
  perform privado.exigir_usuario();
  if not privado.eh_master() then raise exception 'Operação restrita ao Master' using errcode = '42501'; end if;
  if p_curso is not null and p_campus is not null then
    raise exception 'Escolha uma abrangência: instituição, campus OU curso' using errcode = '22023';
  end if;
  v_abr := case when p_curso is not null then 'curso' when p_campus is not null then 'campus' else 'ies' end;
  if p_papel = 'coordenador' and v_abr = 'ies' then
    raise exception 'Coordenação exige abrangência de campus ou curso' using errcode = '22023';
  end if;
  if exists (select 1 from public.usuarios where id = p_usuario and revogado_em is not null) then
    raise exception 'Usuário revogado' using errcode = '22023';
  end if;
  insert into public.escopos(usuario_id, ies_id, abrangencia, campus_id, curso_id, papel, concedido_por)
  values (p_usuario, p_ies, v_abr, p_campus, p_curso, p_papel, (select auth.uid())) returning id into v_id;
  perform privado.auditar(p_ies, 'escopo.conceder', 'escopo', v_id::text,
    jsonb_build_object('usuario_id', p_usuario, 'papel', p_papel, 'abrangencia', v_abr, 'campus_id', p_campus, 'curso_id', p_curso));
  return jsonb_build_object('escopo_id', v_id, 'abrangencia', v_abr);
exception when unique_violation then
  perform privado.erro_http(409, '23505', 'Este escopo já está concedido a este usuário');
end $$;

create or replace function public.rpc_conceder_escopo_email(p_email text, p_nome text, p_ies bigint, p_curso bigint, p_papel text, p_campus bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_novo boolean := false;
begin
  perform privado.exigir_usuario();
  if not privado.eh_master() then raise exception 'Operação restrita ao Master' using errcode = '42501'; end if;
  select id into v_id from auth.users where lower(email) = lower(trim(p_email));
  if v_id is null then
    raise exception 'Conta não encontrada no Supabase Auth. Convide o usuário pelo painel (Authentication → Users) e tente de novo.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.usuarios where id = v_id) then
    insert into public.usuarios(id, nome) values (v_id, coalesce(nullif(trim(p_nome), ''), split_part(p_email, '@', 1)));
    v_novo := true;
    perform privado.auditar(p_ies, 'usuario.convidar', 'usuario', v_id::text);
  end if;
  return public.rpc_conceder_escopo(v_id, p_ies, p_curso, p_papel, p_campus) || jsonb_build_object('usuario_id', v_id, 'perfil_novo', v_novo);
end $$;

-- ---------------------------------------------------------------- leitura de escopos com abrangência
create or replace function public.rpc_me()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare u public.usuarios;
begin
  perform privado.exigir_usuario();
  select * into u from public.usuarios where id = (select auth.uid());
  return jsonb_build_object(
    'usuario', jsonb_build_object('id', u.id, 'nome', u.nome, 'master', u.master),
    'escopos', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'ies_id', e.ies_id, 'ies_nome', i.nome, 'abrangencia', e.abrangencia,
        'campus_id', e.campus_id, 'campus_nome', cp.nome, 'curso_id', e.curso_id, 'curso_nome', c.nome, 'papel', e.papel) order by i.nome, e.papel)
      from public.escopos e join public.ies i on i.id = e.ies_id left join public.cursos c on c.id = e.curso_id left join public.campus cp on cp.id = e.campus_id
      where e.usuario_id = u.id and e.revogado_em is null and i.status = 'ativa'), '[]'::jsonb));
end $$;

create or replace function public.rpc_master_acessos(p_ies bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.exigir_usuario();
  if not privado.eh_master() then raise exception 'Operação restrita ao Master' using errcode = '42501'; end if;
  if not exists (select 1 from public.ies where id = p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  return jsonb_build_object(
    'campi', (select coalesce(jsonb_agg(jsonb_build_object('id', cp.id, 'nome', cp.nome) order by cp.nome), '[]'::jsonb)
              from public.campus cp where cp.ies_id = p_ies),
    'cursos', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.nome, 'turno', c.turno, 'modalidade', c.modalidade, 'campus', cp.nome) order by c.nome), '[]'::jsonb)
               from public.cursos c join public.campus cp on cp.id = c.campus_id where c.ies_id = p_ies),
    'escopos', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'papel', e.papel, 'abrangencia', e.abrangencia,
                  'campus_id', e.campus_id, 'campus_nome', cp.nome, 'curso_id', e.curso_id, 'curso_nome', c.nome,
                  'concedido_em', e.concedido_em, 'revogado_em', e.revogado_em, 'usuario_id', u.id, 'nome', u.nome,
                  'email', (select au.email from auth.users au where au.id = u.id), 'usuario_revogado_em', u.revogado_em)
                  order by e.revogado_em is not null, u.nome), '[]'::jsonb)
                from public.escopos e join public.usuarios u on u.id = e.usuario_id
                left join public.cursos c on c.id = e.curso_id left join public.campus cp on cp.id = e.campus_id
               where e.ies_id = p_ies));
end $$;

-- ---------------------------------------------------------------- (3) matriz de permissões por operação
-- Contrato declarado: quais papéis executam cada operação e com que abrangência mínima.
-- A conformidade das RPCs com esta matriz é verificada pela bateria de testes (teste-local/90).
create table if not exists public.matriz_permissoes (
  operacao text primary key,
  modulo text not null,
  descricao text not null,
  papeis text[] not null,
  abrangencia_minima text not null check (abrangencia_minima in ('curso', 'ies')),
  rpc text not null
);
alter table public.matriz_permissoes enable row level security;
revoke all on public.matriz_permissoes from anon, authenticated;
drop policy if exists matriz_leitura on public.matriz_permissoes;
create policy matriz_leitura on public.matriz_permissoes for select to authenticated using (true);
grant select on public.matriz_permissoes to authenticated;

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('painel.ver',            'Central de Inteligência', 'Ver painel executivo e BI do recorte autorizado', array['gestor','reitoria','coordenador','comercial','secretaria','financeiro'], 'curso', 'rpc_central'),
  ('maim.executar',         'Central de Inteligência', 'Executar o ciclo do MAIM',                         array['gestor'], 'ies', 'rpc_ciclo_maim'),
  ('fila.ver',              'Central de Inteligência', 'Ver fila de intervenções',                         array['gestor','comercial','secretaria','financeiro'], 'curso', 'rpc_fila'),
  ('crm.ver',               'CRM Educacional',         'Ver oportunidades (dados pessoais mascarados para reitoria e coordenação)', array['gestor','reitoria','coordenador','comercial','secretaria','financeiro'], 'curso', 'rpc_listar_oportunidades'),
  ('crm.criar',             'CRM Educacional',         'Cadastrar e importar oportunidades',               array['gestor','comercial'], 'curso', 'rpc_criar_oportunidade'),
  ('crm.mover',             'CRM Educacional',         'Mover oportunidade no funil',                      array['gestor','comercial'], 'curso', 'rpc_mover_etapa'),
  ('crm.registrar',         'CRM Educacional',         'Registrar interação, objeção e agendamento',       array['gestor','comercial'], 'curso', 'rpc_registrar_interacao'),
  ('crm.reatribuir',        'CRM Educacional',         'Reatribuir responsável',                           array['gestor'], 'curso', 'rpc_reatribuir'),
  ('crm.exportar',          'CRM Educacional',         'Exportar oportunidades (contato só para gestor)',  array['gestor','reitoria','coordenador'], 'curso', 'rpc_exportar_oportunidades'),
  ('lgpd.optout',           'CRM Educacional',         'Registrar opt-out de canal',                       array['gestor','comercial','secretaria'], 'curso', 'rpc_optout'),
  ('lgpd.anonimizar',       'CRM Educacional',         'Anonimizar titular',                               array['gestor'], 'curso', 'rpc_anonimizar'),
  ('proposta.criar',        'Conversão e Matrículas',  'Emitir proposta',                                  array['gestor','comercial'], 'curso', 'rpc_criar_proposta'),
  ('proposta.decidir',      'Conversão e Matrículas',  'Aprovar ou rejeitar proposta acima do limite (nunca a própria)', array['gestor'], 'curso', 'rpc_decidir_proposta'),
  ('validacao.documental',  'Conversão e Matrículas',  'Validar documentação e requisito acadêmico',       array['secretaria'], 'curso', 'rpc_validar'),
  ('validacao.financeira',  'Conversão e Matrículas',  'Validar situação financeira',                      array['financeiro'], 'curso', 'rpc_validar'),
  ('matricula.confirmar',   'Conversão e Matrículas',  'Confirmar ingresso efetivo',                       array['gestor','secretaria'], 'curso', 'rpc_confirmar'),
  ('matricula.cancelar',    'Conversão e Matrículas',  'Cancelar matrícula',                               array['gestor','secretaria'], 'curso', 'rpc_cancelar'),
  ('config.alterar',        'Governança Institucional','Alterar parâmetros do MAIM, SLA e amostra mínima', array['gestor'], 'ies', 'rpc_configurar'),
  ('meta.definir',          'Governança Institucional','Definir metas por curso e coorte',                 array['gestor'], 'ies', 'rpc_definir_meta'),
  ('auditoria.ver',         'Governança Institucional','Ver auditoria da instituição',                     array['gestor'], 'ies', 'rpc_auditoria')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

-- Permissões efetivas do usuário na IES: matriz × escopos ativos.
create or replace function public.rpc_permissoes(p_ies bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  return jsonb_build_object(
    'escopos', (select coalesce(jsonb_agg(jsonb_build_object('papel', e.papel, 'abrangencia', e.abrangencia,
                  'alvo', coalesce(c.nome || ' · ' || c.turno, cp.nome, i.nome)) order by e.papel), '[]'::jsonb)
                from public.escopos e join public.ies i on i.id = e.ies_id
                left join public.cursos c on c.id = e.curso_id left join public.campus cp on cp.id = e.campus_id
               where e.usuario_id = (select auth.uid()) and e.ies_id = p_ies and e.revogado_em is null),
    'matriz', (select coalesce(jsonb_agg(jsonb_build_object('operacao', m.operacao, 'modulo', m.modulo, 'descricao', m.descricao,
                  'papeis', m.papeis, 'abrangencia_minima', m.abrangencia_minima,
                  'permitida', case when m.abrangencia_minima = 'ies' then privado.tem_acesso_ies(p_ies, m.papeis)
                                    else exists (select 1 from public.cursos c where c.ies_id = p_ies and privado.tem_acesso(p_ies, c.id, m.papeis)) end)
                  order by m.modulo, m.operacao), '[]'::jsonb)
               from public.matriz_permissoes m));
end $$;

-- ---------------------------------------------------------------- (4) exportação
-- Só papéis da matriz (crm.exportar), só cursos cobertos pelo escopo, contato apenas para gestor do curso.
-- Auditoria registra filtros e volume, nunca os dados exportados.
create or replace function public.rpc_exportar_oportunidades(p_ies bigint, p_coorte text default null, p_curso bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare papeis text[]; n int; linhas jsonb; com_contato boolean;
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  select m.papeis into papeis from public.matriz_permissoes m where m.operacao = 'crm.exportar';
  if not exists (select 1 from public.cursos c where c.ies_id = p_ies and privado.tem_acesso(p_ies, c.id, papeis)) then
    raise exception 'Seu perfil não tem permissão para esta operação' using errcode = '42501';
  end if;
  if p_coorte is not null and p_coorte !~ '^\d{4}\.[12]$' then raise exception 'Coorte deve ter formato AAAA.1 ou AAAA.2' using errcode = '22023'; end if;
  if p_curso is not null and not privado.tem_acesso(p_ies, p_curso, papeis) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  select count(*) into n from public.oportunidades o
   where o.ies_id = p_ies and (p_coorte is null or o.coorte = p_coorte) and (p_curso is null or o.curso_id = p_curso)
     and privado.tem_acesso(o.ies_id, o.curso_id, papeis);
  if n > 5000 then raise exception 'Exportação limitada a 5.000 linhas (% encontradas). Filtre por coorte ou curso.', n using errcode = '22023'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', o.id, 'nome', case when p.anonimizada_em is not null then 'Titular anonimizado' else p.nome end,
           'email', case when privado.tem_acesso(o.ies_id, o.curso_id, array['gestor']) then p.email else privado.mascarar_email(p.email) end,
           'telefone', case when privado.tem_acesso(o.ies_id, o.curso_id, array['gestor']) then p.telefone else privado.mascarar_tel(p.telefone) end,
           'campus', cp.nome, 'curso', c.nome, 'turno', c.turno, 'modalidade', c.modalidade, 'coorte', o.coorte, 'etapa', o.etapa,
           'forma_ingresso', o.forma_ingresso, 'origem', p.origem, 'base_legal', p.base_legal,
           'responsavel', privado.nome_usuario(o.responsavel_id), 'criado_em', o.criado_em) order by o.id), '[]'::jsonb),
         bool_or(privado.tem_acesso(o.ies_id, o.curso_id, array['gestor']))
    into linhas, com_contato
    from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id
    join public.cursos c on c.id = o.curso_id join public.campus cp on cp.id = c.campus_id
   where o.ies_id = p_ies and (p_coorte is null or o.coorte = p_coorte) and (p_curso is null or o.curso_id = p_curso)
     and privado.tem_acesso(o.ies_id, o.curso_id, papeis);
  perform privado.auditar(p_ies, 'exportacao.gerar', 'ies', p_ies::text,
    jsonb_build_object('linhas', n, 'coorte', p_coorte, 'curso_id', p_curso, 'contato_completo', coalesce(com_contato, false)));
  return jsonb_build_object('linhas', linhas, 'total', n, 'contato_completo', coalesce(com_contato, false), 'gerado_em', now());
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.rpc_conceder_escopo(uuid, bigint, bigint, text, bigint), public.rpc_conceder_escopo_email(text, text, bigint, bigint, text, bigint),
  public.rpc_me(), public.rpc_master_acessos(bigint), public.rpc_reatribuir(bigint, uuid, text), public.rpc_atendentes(bigint, bigint),
  public.rpc_permissoes(bigint), public.rpc_exportar_oportunidades(bigint, text, bigint)
to authenticated;

commit;
