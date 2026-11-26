-- Matrícula 360° — migração 11: governança (Bíblia v0.2 §9 e E10).
--   (1) Abrangência EXPLÍCITA do escopo: 'ies', 'campus' ou 'curso'. Campo nulo deixa de significar "tudo":
--       o banco exige a abrangência declarada e coerente com campus/curso.
--   (2) Escopo por campus: cobre os cursos daquele campus, e só eles.
--   (3) Matriz de permissões por operação e módulo, legível pela interface e conferida por teste contra as RPCs.
--   (4) Exportação de oportunidades com autorização no servidor, minimização de dados pessoais e auditoria sem PII.
--   (5) Visibilidade por atribuição: atendente comercial vê só as próprias oportunidades; o gestor vê as da equipe.
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

-- ---------------------------------------------------------------- (5) visibilidade por atribuição
-- Decisão do responsável do produto (26/11/2026): o atendente comercial vê apenas as oportunidades atribuídas a ele;
-- o chefe do setor (gestor) vê todas as do seu escopo. Secretaria, financeiro, reitoria e coordenação mantêm a visão
-- do escopo (com a minimização já existente). Regra única, usada por RLS, leituras e escritas.
create or replace function privado.ve_op(p_ies bigint, p_curso bigint, p_responsavel uuid, p_papeis text[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select privado.tem_acesso(p_ies, p_curso, array_remove(p_papeis, 'comercial'))
      or ('comercial' = any (p_papeis) and p_responsavel = (select auth.uid()) and privado.tem_acesso(p_ies, p_curso, array['comercial']));
$$;
revoke execute on function privado.ve_op(bigint, bigint, uuid, text[]) from public, anon;
grant execute on function privado.ve_op(bigint, bigint, uuid, text[]) to authenticated;

create or replace function privado.ve_oportunidade(p_op bigint, p_papeis text[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.oportunidades o where o.id = p_op and privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, p_papeis));
$$;

create or replace function privado.carregar_op(p_op bigint, p_papeis text[]) returns public.oportunidades
language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades;
begin
  perform privado.exigir_usuario();
  select * into o from public.oportunidades where id = p_op for update;
  if not found or not privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro']) then
    perform privado.erro_http(404, 'P0002', 'Não encontrado');
  end if;
  if not privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, p_papeis) then
    raise exception 'Seu perfil não tem permissão para esta operação' using errcode = '42501';
  end if;
  return o;
end $$;

drop policy if exists oportunidades_leitura on public.oportunidades;
create policy oportunidades_leitura on public.oportunidades for select to authenticated
  using (privado.ve_op(ies_id, curso_id, responsavel_id, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro']));
drop policy if exists pessoas_leitura on public.pessoas;
create policy pessoas_leitura on public.pessoas for select to authenticated
  using (exists (select 1 from public.oportunidades o where o.pessoa_id = pessoas.id
                 and privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, array['gestor','comercial','secretaria','financeiro'])));

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
       and privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro'])
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

create or replace function public.rpc_detalhe(p_op bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare o public.oportunidades; p public.pessoas; c public.cursos; pleno boolean; comercial boolean;
  t constant jsonb := '{"novo":["contato","perdido"],"contato":["inscrito","perdido"],"inscrito":["pre_matricula","perdido"],"pre_matricula":["matricula_comercial","perdido"],"perdido":["contato"]}';
begin
  perform privado.exigir_usuario();
  select * into o from public.oportunidades where id = p_op;
  if not found or not privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro']) then
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
   where privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, array['gestor','comercial']));
end $$;

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
   where privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro']);
  return r;
end $$;

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
  -- Quem cadastra como atendente comercial assume o lead; cadastro pelo gestor segue a distribuição automática.
  v_resp := case when privado.tem_acesso(p_ies, v_curso, array['comercial']) then (select auth.uid()) else privado.distribuir(p_ies, v_curso) end;
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

update public.matriz_permissoes set descricao = 'Ver oportunidades do escopo (comercial: só as atribuídas a si; reitoria e coordenação: dados mascarados)'
 where operacao = 'crm.ver';
insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('crm.ver_equipe', 'CRM Educacional', 'Ver oportunidades atribuídas a outros atendentes (chefe do setor)', array['gestor','reitoria','coordenador','secretaria','financeiro'], 'curso', 'rpc_listar_oportunidades')
on conflict (operacao) do update set descricao = excluded.descricao, papeis = excluded.papeis;

revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.rpc_listar_oportunidades(bigint, text, text, int, int, bigint, text, text, boolean, boolean), public.rpc_detalhe(bigint),
  public.rpc_listar_propostas(bigint, text), public.rpc_pendencias(bigint), public.rpc_criar_oportunidade(bigint, jsonb, text)
to authenticated;
