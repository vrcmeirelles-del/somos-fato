-- Matrícula 360° — migrações 1 a 17 consolidadas (instalação NOVA, banco vazio). Transação única.
begin;

-- ===================== supabase/migrations/20261125000001_esquema_rls.sql
-- Matrícula 360° — migração 1: esquema, RLS e defesas no banco.
-- Destino: projeto Supabase independente de homologação. NÃO aplicar em banco de outros produtos.
-- Princípios:
--   * Leitura pelo cliente somente via RLS (perfil autenticado, escopo por IES/curso).
--   * Nenhum INSERT/UPDATE/DELETE direto do cliente: escritas só por RPC (migração 2).
--   * Funções auxiliares ficam no schema "privado" (não exposto pela API).

create schema if not exists privado;
revoke all on schema privado from public;

-- ---------------------------------------------------------------- tabelas
create table public.ies (
  id bigint generated always as identity primary key,
  nome text not null unique check (length(nome) between 2 and 120),
  plano text not null default 'piloto' check (plano in ('piloto','essencial','completo')),
  status text not null default 'ativa' check (status in ('ativa','suspensa')),
  sla_horas int not null default 2 check (sla_horas between 1 and 168),
  max_followups int not null default 3 check (max_followups between 0 and 10),
  dias_sem_contato int not null default 3 check (dias_sem_contato between 1 and 60),
  capacidade_atendente int not null default 50 check (capacidade_atendente between 1 and 1000),
  criado_em timestamptz not null default now()
);

create table public.campus (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  nome text not null,
  unique (ies_id, nome)
);

create table public.cursos (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  campus_id bigint not null references public.campus(id),
  nome text not null,
  turno text not null check (turno in ('matutino','vespertino','noturno','integral','ead')),
  modalidade text not null check (modalidade in ('presencial','ead','semipresencial')),
  mensalidade_centavos int not null check (mensalidade_centavos > 0),
  desconto_max_pct numeric(5,2) not null default 30 check (desconto_max_pct between 0 and 100),
  unique (ies_id, campus_id, nome, turno)
);
create index cursos_ies on public.cursos(ies_id);

-- Perfil de aplicação ligado ao Supabase Auth. Revogação vale mesmo com JWT ainda válido.
create table public.usuarios (
  id uuid primary key references auth.users(id) on delete restrict,
  nome text not null,
  master boolean not null default false,
  revogado_em timestamptz,
  criado_em timestamptz not null default now()
);

create table public.escopos (
  id bigint generated always as identity primary key,
  usuario_id uuid not null references public.usuarios(id),
  ies_id bigint not null references public.ies(id),
  curso_id bigint references public.cursos(id),
  papel text not null check (papel in ('gestor','reitoria','coordenador','comercial','secretaria','financeiro')),
  concedido_por uuid references public.usuarios(id),
  concedido_em timestamptz not null default now(),
  revogado_em timestamptz,
  check (papel <> 'coordenador' or curso_id is not null)
);
create unique index escopo_unico on public.escopos(usuario_id, ies_id, coalesce(curso_id, 0), papel) where revogado_em is null;
create index escopos_usuario on public.escopos(usuario_id) where revogado_em is null;

create table public.pessoas (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  nome text not null,
  email text,
  telefone text,
  base_legal text not null check (base_legal in ('consentimento','procedimentos_preliminares_contrato','legitimo_interesse')),
  origem text not null check (length(origem) between 2 and 80),
  optout_email boolean not null default false,
  optout_whatsapp boolean not null default false,
  optout_telefone boolean not null default false,
  anonimizada_em timestamptz,
  criado_em timestamptz not null default now(),
  check (anonimizada_em is not null or email is not null or telefone is not null)
);
create unique index pessoa_email on public.pessoas(ies_id, email) where email is not null;
create unique index pessoa_tel on public.pessoas(ies_id, telefone) where telefone is not null;

create table public.oportunidades (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  curso_id bigint not null references public.cursos(id),
  pessoa_id bigint not null references public.pessoas(id),
  forma_ingresso text not null check (forma_ingresso in ('vestibular','enem','transferencia','segunda_graduacao','reingresso','indicacao','convenio','visita_escolar','evento','pos_graduacao')),
  coorte text not null check (coorte ~ '^\d{4}\.[12]$'),
  etapa text not null default 'novo' check (etapa in ('novo','contato','inscrito','pre_matricula','matricula_comercial','confirmado','perdido','cancelado')),
  versao int not null default 1,
  responsavel_id uuid references public.usuarios(id),
  motivo_perda text,
  val_documental boolean not null default false,
  val_financeira boolean not null default false,
  val_academica boolean not null default false,
  matricula_comercial_em timestamptz,
  confirmada_em timestamptz,
  cancelada_em timestamptz,
  motivo_cancelamento text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (pessoa_id, curso_id, coorte)
);
create index op_ies_coorte on public.oportunidades(ies_id, coorte, etapa);
create index op_curso on public.oportunidades(curso_id);
create index op_pessoa on public.oportunidades(pessoa_id);
create index op_responsavel on public.oportunidades(responsavel_id);

create table public.validacoes (
  id bigint generated always as identity primary key,
  oportunidade_id bigint not null references public.oportunidades(id),
  dimensao text not null check (dimensao in ('documental','financeira','academica')),
  resultado text not null check (resultado in ('valida','invalida','isencao_formal')),
  evidencia text not null check (length(evidencia) between 5 and 500),
  usuario_id uuid not null references public.usuarios(id),
  em timestamptz not null default now(),
  check (resultado <> 'isencao_formal' or dimensao = 'financeira')
);
create index validacoes_op on public.validacoes(oportunidade_id);

create table public.propostas (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  oportunidade_id bigint not null references public.oportunidades(id),
  mensalidade_centavos int not null,
  desconto_pct numeric(5,2) not null check (desconto_pct between 0 and 100),
  valor_final_centavos int not null,
  validade timestamptz not null,
  status text not null check (status in ('pendente_aprovacao','aprovada','rejeitada','aceita','expirada')),
  criado_por uuid not null references public.usuarios(id),
  decidido_por uuid references public.usuarios(id),
  criado_em timestamptz not null default now(),
  decidido_em timestamptz,
  check (decidido_por is null or decidido_por <> criado_por)
);
create index propostas_op on public.propostas(oportunidade_id);
create index propostas_ies on public.propostas(ies_id, status);

create table public.tarefas (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  oportunidade_id bigint not null references public.oportunidades(id),
  tipo text not null check (tipo in ('primeiro_contato','follow_up','pendencia_validacao','recuperacao')),
  canal text check (canal in ('email','whatsapp','telefone')),
  responsavel_id uuid references public.usuarios(id),
  vence_em timestamptz not null,
  status text not null default 'aberta' check (status in ('aberta','concluida','suprimida','cancelada')),
  resultado text,
  criado_em timestamptz not null default now(),
  encerrada_em timestamptz
);
create index tarefa_fila on public.tarefas(ies_id, status, vence_em);
create index tarefa_op on public.tarefas(oportunidade_id);
create index tarefa_resp on public.tarefas(responsavel_id) where status = 'aberta';

create table public.metas (
  ies_id bigint not null references public.ies(id),
  curso_id bigint not null references public.cursos(id),
  coorte text not null check (coorte ~ '^\d{4}\.[12]$'),
  meta int not null check (meta >= 0),
  primary key (ies_id, curso_id, coorte)
);

create table public.auditoria (
  id bigint generated always as identity primary key,
  ies_id bigint references public.ies(id),
  usuario_id uuid references public.usuarios(id),
  acao text not null,
  entidade text not null,
  entidade_id text,
  dados jsonb not null default '{}'::jsonb,
  em timestamptz not null default now()
);
create index auditoria_ent on public.auditoria(entidade, entidade_id);
create index auditoria_ies on public.auditoria(ies_id, id desc);

create table privado.idempotencia (
  usuario_id uuid not null,
  chave text not null check (length(chave) between 8 and 100),
  rota text not null,
  resposta jsonb not null,
  em timestamptz not null default now(),
  primary key (usuario_id, chave)
);

-- ---------------------------------------------------------------- defesas no banco
create or replace function privado.bloquear_alteracao_auditoria() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'auditoria imutavel' using errcode = '42501';
end $$;
create trigger auditoria_sem_update before update or delete on public.auditoria
  for each row execute function privado.bloquear_alteracao_auditoria();
create trigger auditoria_sem_truncate before truncate on public.auditoria
  for each statement execute function privado.bloquear_alteracao_auditoria();

create or replace function privado.confirmacao_integra() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.etapa = 'confirmado' and old.etapa is distinct from 'confirmado' and
     (old.etapa <> 'matricula_comercial' or not (new.val_documental and new.val_financeira and new.val_academica)) then
    raise exception 'confirmacao incompleta' using errcode = '22023';
  end if;
  return new;
end $$;
create trigger confirmacao_integra before update of etapa on public.oportunidades
  for each row execute function privado.confirmacao_integra();

-- ---------------------------------------------------------------- funções de escopo
-- SECURITY DEFINER para não depender de RLS recursiva; search_path vazio contra sequestro.
create or replace function privado.usuario_ativo() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.usuarios u where u.id = (select auth.uid()) and u.revogado_em is null);
$$;

create or replace function privado.eh_master() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.usuarios u where u.id = (select auth.uid()) and u.master and u.revogado_em is null);
$$;

-- Acesso a um curso de uma IES com um dos papéis informados (escopo de IES inteira ou do curso).
create or replace function privado.tem_acesso(p_ies bigint, p_curso bigint, p_papeis text[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.escopos e
      join public.usuarios u on u.id = e.usuario_id
      join public.ies i on i.id = e.ies_id
    where e.usuario_id = (select auth.uid()) and e.revogado_em is null and u.revogado_em is null
      and i.status = 'ativa' and e.ies_id = p_ies and e.papel = any (p_papeis)
      and (e.curso_id is null or e.curso_id = p_curso)
  );
$$;

-- Acesso com escopo de IES inteira (sem restrição de curso).
create or replace function privado.tem_acesso_ies(p_ies bigint, p_papeis text[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.escopos e
      join public.usuarios u on u.id = e.usuario_id
      join public.ies i on i.id = e.ies_id
    where e.usuario_id = (select auth.uid()) and e.revogado_em is null and u.revogado_em is null
      and i.status = 'ativa' and e.ies_id = p_ies and e.papel = any (p_papeis) and e.curso_id is null
  );
$$;

create or replace function privado.ve_ies(p_ies bigint) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.escopos e
      join public.usuarios u on u.id = e.usuario_id
      join public.ies i on i.id = e.ies_id
    where e.usuario_id = (select auth.uid()) and e.revogado_em is null and u.revogado_em is null
      and i.status = 'ativa' and e.ies_id = p_ies
  );
$$;

create or replace function privado.ve_oportunidade(p_op bigint, p_papeis text[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.oportunidades o where o.id = p_op and privado.tem_acesso(o.ies_id, o.curso_id, p_papeis));
$$;

-- ---------------------------------------------------------------- RLS
alter table public.ies enable row level security;
alter table public.campus enable row level security;
alter table public.cursos enable row level security;
alter table public.usuarios enable row level security;
alter table public.escopos enable row level security;
alter table public.pessoas enable row level security;
alter table public.oportunidades enable row level security;
alter table public.validacoes enable row level security;
alter table public.propostas enable row level security;
alter table public.tarefas enable row level security;
alter table public.metas enable row level security;
alter table public.auditoria enable row level security;
alter table privado.idempotencia enable row level security;

-- Cliente: nenhuma escrita direta; leitura filtrada por RLS. anon não lê nada.
revoke all on all tables in schema public from anon, authenticated;
grant select on all tables in schema public to authenticated;
revoke all on all tables in schema privado from anon, authenticated;
revoke all on all functions in schema privado from public, anon, authenticated;
grant usage on schema privado to authenticated;
-- Somente as funções usadas nas políticas de RLS (avaliadas com o papel do cliente).
grant execute on function privado.usuario_ativo(), privado.eh_master(), privado.tem_acesso(bigint, bigint, text[]),
  privado.tem_acesso_ies(bigint, text[]), privado.ve_ies(bigint), privado.ve_oportunidade(bigint, text[]) to authenticated;
alter default privileges in schema public revoke all on tables from anon, authenticated;

create policy ies_leitura on public.ies for select to authenticated
  using (privado.ve_ies(id) or privado.eh_master());
create policy campus_leitura on public.campus for select to authenticated
  using (privado.ve_ies(ies_id) or privado.eh_master());
create policy cursos_leitura on public.cursos for select to authenticated
  using (privado.tem_acesso(ies_id, id, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro']) or privado.eh_master());
create policy usuarios_leitura on public.usuarios for select to authenticated
  using (id = (select auth.uid()) or privado.eh_master());
create policy escopos_leitura on public.escopos for select to authenticated
  using (usuario_id = (select auth.uid()) or privado.eh_master());
-- Dados pessoais: só perfis operacionais no curso. Reitoria e coordenação usam a RPC mascarada.
-- Master NÃO lê candidatos.
create policy pessoas_leitura on public.pessoas for select to authenticated
  using (exists (select 1 from public.oportunidades o where o.pessoa_id = pessoas.id
                 and privado.tem_acesso(o.ies_id, o.curso_id, array['gestor','comercial','secretaria','financeiro'])));
create policy oportunidades_leitura on public.oportunidades for select to authenticated
  using (privado.tem_acesso(ies_id, curso_id, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro']));
create policy validacoes_leitura on public.validacoes for select to authenticated
  using (privado.ve_oportunidade(oportunidade_id, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro']));
create policy propostas_leitura on public.propostas for select to authenticated
  using (privado.ve_oportunidade(oportunidade_id, array['gestor','comercial']));
create policy tarefas_leitura on public.tarefas for select to authenticated
  using (privado.ve_oportunidade(oportunidade_id, array['gestor','comercial','secretaria','financeiro']));
create policy metas_leitura on public.metas for select to authenticated
  using (privado.tem_acesso(ies_id, curso_id, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro']));
create policy auditoria_leitura on public.auditoria for select to authenticated
  using (ies_id is not null and privado.tem_acesso_ies(ies_id, array['gestor']));
-- privado.idempotencia: RLS ligada e nenhuma política => invisível ao cliente.

-- ===================== supabase/migrations/20261125000002_rpcs.sql
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

-- ===================== supabase/migrations/20261125000003_rpcs_complementares.sql
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

-- ===================== supabase/migrations/20261125000004_indices_fk.sql
-- Matrícula 360° — migração 4: índices para chaves estrangeiras sem cobertura.
-- Origem: Performance Advisor do Supabase (lint "unindexed_foreign_keys"), 25/11/2026.
-- Evita varreduras completas em junções, nas checagens de FK e em exclusões.
create index if not exists auditoria_usuario on public.auditoria(usuario_id);
create index if not exists cursos_campus on public.cursos(campus_id);
create index if not exists escopos_ies on public.escopos(ies_id);
create index if not exists escopos_curso on public.escopos(curso_id);
create index if not exists escopos_concedido_por on public.escopos(concedido_por);
create index if not exists metas_curso on public.metas(curso_id);
create index if not exists propostas_criado_por on public.propostas(criado_por);
create index if not exists propostas_decidido_por on public.propostas(decidido_por);
create index if not exists validacoes_usuario on public.validacoes(usuario_id);
-- Cobertos apenas por índices parciais (não servem à checagem de FK em exclusões).
-- O advisor não os aponta; incluídos por robustez.
create index if not exists escopos_usuario_todos on public.escopos(usuario_id);
create index if not exists pessoas_ies on public.pessoas(ies_id);
create index if not exists tarefas_responsavel_todos on public.tarefas(responsavel_id);

-- ===================== supabase/migrations/20261125000005_rpcs_leitura.sql
-- Matrícula 360° — migração 5: RPCs de leitura para a interface ligada ao Supabase.
-- Mantêm as regras do piloto: minimização (contatos mascarados para quem não opera o curso),
-- Master sem acesso a candidatos, paginação e N/D distinto de zero. Somente leitura.

-- ---------------------------------------------------------------- utilitários
create or replace function privado.mascarar_email(e text) returns text
language sql immutable set search_path = '' as $$
  select case when e is null then null else left(e, 1) || '***@' || split_part(e, '@', 2) end;
$$;
create or replace function privado.mascarar_tel(t text) returns text
language sql immutable set search_path = '' as $$
  select case when t is null then null else '***' || right(t, 4) end;
$$;
create or replace function privado.nome_usuario(p uuid) returns text
language sql stable security definer set search_path = '' as $$
  select nome from public.usuarios where id = p;
$$;
revoke execute on function privado.mascarar_email(text), privado.mascarar_tel(text), privado.nome_usuario(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- identidade e estrutura
create or replace function public.rpc_me()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare u public.usuarios;
begin
  perform privado.exigir_usuario();
  select * into u from public.usuarios where id = (select auth.uid());
  return jsonb_build_object(
    'usuario', jsonb_build_object('id', u.id, 'nome', u.nome, 'master', u.master),
    'escopos', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'ies_id', e.ies_id, 'ies_nome', i.nome,
        'curso_id', e.curso_id, 'curso_nome', c.nome, 'papel', e.papel) order by i.nome, e.papel)
      from public.escopos e join public.ies i on i.id = e.ies_id left join public.cursos c on c.id = e.curso_id
      where e.usuario_id = u.id and e.revogado_em is null and i.status = 'ativa'), '[]'::jsonb));
end $$;

create or replace function public.rpc_estrutura(p_ies bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare i public.ies;
  todos text[] := array['gestor','reitoria','coordenador','comercial','secretaria','financeiro'];
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then raise exception 'Não encontrado' using errcode = 'P0002'; end if;
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

-- ---------------------------------------------------------------- listas (substitui a versão da migração 2)
drop function if exists public.rpc_listar_oportunidades(bigint, text, text, int, int);
create or replace function public.rpc_listar_oportunidades(p_ies bigint, p_etapa text default null, p_coorte text default null,
  p_pagina int default 1, p_por_pagina int default 25, p_curso bigint default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare total bigint; itens jsonb;
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then raise exception 'Não encontrado' using errcode = 'P0002'; end if;
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

create or replace function public.rpc_detalhe(p_op bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare o public.oportunidades; p public.pessoas; c public.cursos; pleno boolean;
  t constant jsonb := '{"novo":["contato","perdido"],"contato":["inscrito","perdido"],"inscrito":["pre_matricula","perdido"],"pre_matricula":["matricula_comercial","perdido"],"perdido":["contato"]}';
begin
  perform privado.exigir_usuario();
  select * into o from public.oportunidades where id = p_op;
  if not found or not privado.tem_acesso(o.ies_id, o.curso_id, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro']) then
    raise exception 'Não encontrado' using errcode = 'P0002';
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

create or replace function public.rpc_listar_propostas(p_ies bigint, p_status text default 'pendente_aprovacao')
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then raise exception 'Não encontrado' using errcode = 'P0002'; end if;
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

-- Fila e pendências: acrescenta nome do candidato e do responsável (mesmas regras de acesso da migração 3).
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

create or replace function public.rpc_pendencias(p_ies bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare r jsonb;
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then raise exception 'Não encontrado' using errcode = 'P0002'; end if;
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

-- BI com agrupamento (substitui a versão da migração 2; mesmo cálculo e mesma semântica de N/D).
drop function if exists public.rpc_bi(bigint, text);
create or replace function public.rpc_bi(p_ies bigint, p_coorte text, p_agrupar text default 'curso')
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare t record; v_meta bigint; v_metas int; linhas jsonb; v_total boolean;
  todos text[] := array['gestor','reitoria','coordenador','comercial','secretaria','financeiro'];
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then raise exception 'Não encontrado' using errcode = 'P0002'; end if;
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

create or replace function public.rpc_auditoria(p_ies bigint, p_pagina int default 1)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then raise exception 'Não encontrado' using errcode = 'P0002'; end if;
  if not privado.tem_acesso_ies(p_ies, array['gestor']) then raise exception 'Seu perfil não tem permissão para esta operação' using errcode = '42501'; end if;
  if p_pagina < 1 then raise exception 'Paginação inválida' using errcode = '22023'; end if;
  return jsonb_build_object(
    'total', (select count(*) from public.auditoria where ies_id = p_ies), 'pagina', p_pagina, 'por_pagina', 50,
    'itens', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'acao', a.acao, 'entidade', a.entidade, 'entidade_id', a.entidade_id,
                'dados', a.dados, 'em', a.em, 'por', privado.nome_usuario(a.usuario_id)) order by a.id desc), '[]'::jsonb)
              from (select * from public.auditoria where ies_id = p_ies order by id desc limit 50 offset (p_pagina - 1) * 50) a));
end $$;

-- ---------------------------------------------------------------- Master
create or replace function public.rpc_master_listar_ies()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.exigir_usuario();
  if not privado.eh_master() then raise exception 'Operação restrita ao Master' using errcode = '42501'; end if;
  -- Configuração e acessos; nenhum dado de candidato.
  return (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'nome', i.nome, 'plano', i.plano, 'status', i.status, 'criado_em', i.criado_em,
            'cursos', (select count(*) from public.cursos c where c.ies_id = i.id),
            'usuarios', (select count(distinct e.usuario_id) from public.escopos e where e.ies_id = i.id and e.revogado_em is null)) order by i.nome), '[]'::jsonb)
          from public.ies i);
end $$;

create or replace function public.rpc_master_acessos(p_ies bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.exigir_usuario();
  if not privado.eh_master() then raise exception 'Operação restrita ao Master' using errcode = '42501'; end if;
  if not exists (select 1 from public.ies where id = p_ies) then raise exception 'Não encontrado' using errcode = 'P0002'; end if;
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

-- Concede escopo a uma conta já existente no Supabase Auth, localizada pelo e-mail.
-- Cria o perfil de aplicação se ainda não existir. A criação da conta (convite) é feita no Supabase Auth.
create or replace function public.rpc_conceder_escopo_email(p_email text, p_nome text, p_ies bigint, p_curso bigint, p_papel text)
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
  return public.rpc_conceder_escopo(v_id, p_ies, p_curso, p_papel) || jsonb_build_object('usuario_id', v_id, 'perfil_novo', v_novo);
end $$;

-- ---------------------------------------------------------------- permissões
revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.rpc_me(), public.rpc_estrutura(bigint), public.rpc_listar_oportunidades(bigint, text, text, int, int, bigint),
  public.rpc_detalhe(bigint), public.rpc_listar_propostas(bigint, text), public.rpc_fila(bigint), public.rpc_pendencias(bigint),
  public.rpc_bi(bigint, text, text), public.rpc_auditoria(bigint, int),
  public.rpc_master_listar_ies(), public.rpc_master_acessos(bigint), public.rpc_conceder_escopo_email(text, text, bigint, bigint, text)
to authenticated;
revoke execute on all functions in schema privado from public, anon, authenticated;
grant execute on function privado.usuario_ativo(), privado.eh_master(), privado.tem_acesso(bigint, bigint, text[]),
  privado.tem_acesso_ies(bigint, text[]), privado.ve_ies(bigint), privado.ve_oportunidade(bigint, text[]) to authenticated;

-- ===================== supabase/migrations/20261125000006_codigos_http.sql
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

-- ===================== supabase/migrations/20261125000007_correcoes_fase2.sql
-- Matrícula 360° — migração 7: correções da Fase 2 (P0), reproduzidas em docs/DIAGNOSTICO-FASE2.md.
--   (2) proposta ativa única por oportunidade: nova proposta substitui a anterior (auditado)
--   (3) projeção com taxa sobre oportunidades decididas
--   (4) mudança de etapa encerra tarefas incompatíveis (auditado)
--   (5) RPC para leitura das metas cadastradas
-- Inclui saneamento auditado dos dados existentes. Regras aplicadas por gatilho: valem para qualquer caminho.

-- ---------------------------------------------------------------- (2) propostas
alter table public.propostas drop constraint if exists propostas_status_check;
alter table public.propostas add constraint propostas_status_check
  check (status in ('pendente_aprovacao','aprovada','rejeitada','aceita','expirada','substituida'));

-- Saneamento: mantém a proposta ativa mais recente de cada oportunidade; as anteriores viram "substituida".
with ativas as (
  select id, oportunidade_id, ies_id, row_number() over (partition by oportunidade_id order by id desc) as n
    from public.propostas where status in ('pendente_aprovacao','aprovada')
), alvo as (
  update public.propostas p set status = 'substituida', decidido_em = now()
    from ativas a where a.id = p.id and a.n > 1
  returning p.id, p.ies_id, p.oportunidade_id
)
insert into public.auditoria(ies_id, usuario_id, acao, entidade, entidade_id, dados)
select ies_id, null, 'proposta.substituir', 'oportunidade', oportunidade_id::text,
       jsonb_build_object('proposta_id', id, 'motivo', 'saneamento migração 7: mais de uma proposta ativa')
  from alvo;

create unique index if not exists proposta_ativa_unica on public.propostas(oportunidade_id)
  where status in ('pendente_aprovacao','aprovada');

create or replace function privado.substituir_proposta_ativa() returns trigger
language plpgsql security definer set search_path = '' as $$
declare r record;
begin
  for r in update public.propostas set status = 'substituida', decidido_em = now()
            where oportunidade_id = new.oportunidade_id and status in ('pendente_aprovacao','aprovada')
            returning id loop
    perform privado.auditar(new.ies_id, 'proposta.substituir', 'oportunidade', new.oportunidade_id::text,
      jsonb_build_object('proposta_id', r.id, 'motivo', 'nova proposta emitida'));
  end loop;
  return new;
end $$;
drop trigger if exists proposta_substitui_anterior on public.propostas;
create trigger proposta_substitui_anterior before insert on public.propostas
  for each row execute function privado.substituir_proposta_ativa();

-- ---------------------------------------------------------------- (4) tarefas incompatíveis com a etapa
-- primeiro_contato só faz sentido em "novo"; tarefas comerciais (contato, follow-up, recuperação) não cabem
-- após a matrícula comercial ou em etapa encerrada. Pendência de validação só existe em matrícula comercial.
create or replace function privado.tarefa_compativel(p_tipo text, p_etapa text) returns boolean
language sql immutable set search_path = '' as $$
  select case p_tipo
    when 'primeiro_contato' then p_etapa = 'novo'
    when 'follow_up' then p_etapa in ('contato','inscrito','pre_matricula')
    when 'recuperacao' then p_etapa in ('contato','inscrito','pre_matricula')
    when 'pendencia_validacao' then p_etapa = 'matricula_comercial'
    else true end;
$$;

create or replace function privado.encerrar_tarefas_incompativeis() returns trigger
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  update public.tarefas
     set status = 'cancelada', encerrada_em = now(),
         resultado = 'encerrada automaticamente: incompatível com a etapa ' || new.etapa
   where oportunidade_id = new.id and status = 'aberta' and not privado.tarefa_compativel(tipo, new.etapa);
  get diagnostics n = row_count;
  if n > 0 then
    perform privado.auditar(new.ies_id, 'tarefa.encerrar_incompativel', 'oportunidade', new.id::text,
      jsonb_build_object('etapa', new.etapa, 'tarefas', n));
  end if;
  return new;
end $$;
drop trigger if exists etapa_encerra_tarefas on public.oportunidades;
create trigger etapa_encerra_tarefas after update of etapa on public.oportunidades
  for each row when (old.etapa is distinct from new.etapa) execute function privado.encerrar_tarefas_incompativeis();

-- Saneamento auditado das tarefas já abertas e incompatíveis.
with alvo as (
  update public.tarefas t set status = 'cancelada', encerrada_em = now(),
         resultado = 'encerrada no saneamento da migração 7: incompatível com a etapa ' || o.etapa
    from public.oportunidades o
   where o.id = t.oportunidade_id and t.status = 'aberta' and not privado.tarefa_compativel(t.tipo, o.etapa)
  returning t.ies_id, t.oportunidade_id, o.etapa
)
insert into public.auditoria(ies_id, usuario_id, acao, entidade, entidade_id, dados)
select ies_id, null, 'tarefa.encerrar_incompativel', 'oportunidade', oportunidade_id::text,
       jsonb_build_object('etapa', etapa, 'tarefas', count(*), 'motivo', 'saneamento migração 7')
  from alvo group by ies_id, oportunidade_id, etapa;

-- Primeiro contato só é criado para oportunidade em "novo" (defesa contra chamadas futuras).
create or replace function privado.bloquear_tarefa_incompativel() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_etapa text;
begin
  select etapa into v_etapa from public.oportunidades where id = new.oportunidade_id;
  if new.status = 'aberta' and not privado.tarefa_compativel(new.tipo, v_etapa) then
    raise exception 'Tarefa % incompatível com a etapa %', new.tipo, v_etapa using errcode = '22023';
  end if;
  return new;
end $$;
drop trigger if exists tarefa_compativel_etapa on public.tarefas;
create trigger tarefa_compativel_etapa before insert on public.tarefas
  for each row execute function privado.bloquear_tarefa_incompativel();

-- ---------------------------------------------------------------- (3) projeção no BI
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
      -- Projeção (migração 7): taxa sobre oportunidades DECIDIDAS (ingresso, perda ou cancelamento).
      -- A coorte em andamento não entra no denominador. Sem base decidida => N/D.
      'oportunidades_abertas', t.oportunidades - t.ingressantes - t.perdidos - t.cancelamentos,
      'taxa_conversao_decididas', case when (t.ingressantes + t.perdidos + t.cancelamentos) = 0 then null
        else round(t.ingressantes::numeric / (t.ingressantes + t.perdidos + t.cancelamentos), 4) end,
      'ingressos_esperados_pipeline', case when (t.ingressantes + t.perdidos + t.cancelamentos) = 0 then null
        else round((t.oportunidades - t.ingressantes - t.perdidos - t.cancelamentos)
                   * t.ingressantes::numeric / (t.ingressantes + t.perdidos + t.cancelamentos), 1) end,
      'lacuna_meta', case when v_meta is null then null else greatest(v_meta - t.ingressantes, 0) end,
      'projecao_oportunidades_necessarias', case
        when v_meta is null or (t.ingressantes + t.perdidos + t.cancelamentos) = 0 or t.ingressantes = 0 then null
        else greatest(ceil(
          (v_meta - t.ingressantes
           - (t.oportunidades - t.ingressantes - t.perdidos - t.cancelamentos)
             * t.ingressantes::numeric / (t.ingressantes + t.perdidos + t.cancelamentos))
          / (t.ingressantes::numeric / (t.ingressantes + t.perdidos + t.cancelamentos))), 0) end,
      'projecao_metodo', 'Novas oportunidades necessárias = (meta − ingressantes − ingressos esperados do pipeline aberto) ÷ taxa de conversão das oportunidades decididas'),
    'linhas', linhas);
end $$;

-- ---------------------------------------------------------------- (5) metas cadastradas
create or replace function public.rpc_metas(p_ies bigint, p_coorte text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if p_coorte !~ '^\d{4}\.[12]$' then raise exception 'Coorte deve ter formato AAAA.1 ou AAAA.2' using errcode = '22023'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('curso_id', m.curso_id, 'meta', m.meta) order by m.curso_id), '[]'::jsonb)
            from public.metas m
           where m.ies_id = p_ies and m.coorte = p_coorte
             and privado.tem_acesso(m.ies_id, m.curso_id, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro']));
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.rpc_metas(bigint, text), public.rpc_bi(bigint, text, text) to authenticated;
revoke execute on function privado.substituir_proposta_ativa(), privado.encerrar_tarefas_incompativeis(),
  privado.bloquear_tarefa_incompativel(), privado.tarefa_compativel(text, text) from public, anon, authenticated;

-- ===================== supabase/migrations/20261125000008_central_inteligencia.sql
-- Matrícula 360° — migração 8: Central de Inteligência (BI executivo) com filtros globais.
-- Uma RPC somente leitura devolve todos os blocos do painel, sob as mesmas regras de escopo.
-- Regras: indisponível (null) ≠ zero; estimativas sempre identificadas e com método; nada é inventado.
-- Custo por lead/matrícula exige investimento cadastrado (módulo Campanhas, P1): até lá, N/D com motivo.

create or replace function privado.ordem_etapa(p text) returns int
language sql immutable set search_path = '' as $$
  select case p when 'novo' then 1 when 'contato' then 2 when 'inscrito' then 3 when 'pre_matricula' then 4
                when 'matricula_comercial' then 5 when 'confirmado' then 6 else 0 end;
$$;
revoke execute on function privado.ordem_etapa(text) from public, anon, authenticated;

create or replace function public.rpc_central(p_ies bigint, p_coorte text, p_filtros jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  todos constant text[] := array['gestor','reitoria','coordenador','comercial','secretaria','financeiro'];
  f_campus bigint := nullif(p_filtros->>'campus_id', '')::bigint;
  f_curso bigint := nullif(p_filtros->>'curso_id', '')::bigint;
  f_turno text := nullif(p_filtros->>'turno', '');
  f_modal text := nullif(p_filtros->>'modalidade', '');
  cfg public.ies; r jsonb;
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if p_coorte !~ '^\d{4}\.[12]$' then raise exception 'Coorte deve ter formato AAAA.1 ou AAAA.2' using errcode = '22023'; end if;
  select * into cfg from public.ies where id = p_ies;

  with cursos_ok as (
    select c.*, cp.nome as campus_nome from public.cursos c join public.campus cp on cp.id = c.campus_id
     where c.ies_id = p_ies and privado.tem_acesso(p_ies, c.id, todos)
       and (f_campus is null or c.campus_id = f_campus) and (f_curso is null or c.id = f_curso)
       and (f_turno is null or c.turno = f_turno) and (f_modal is null or c.modalidade = f_modal)
  ), ops as (
    select o.*, c.nome as curso, c.turno, c.modalidade, c.mensalidade_centavos, c.campus_nome, p.origem,
           coalesce(u.nome, 'Sem responsável') as atendente,
           greatest(
             case when o.etapa in ('perdido','cancelado') then 0 else privado.ordem_etapa(o.etapa) end,
             case when o.confirmada_em is not null then 6 when o.matricula_comercial_em is not null then 5 else 0 end,
             coalesce((select max(greatest(privado.ordem_etapa(a.dados->>'de'), privado.ordem_etapa(a.dados->>'para')))
                         from public.auditoria a where a.entidade = 'oportunidade' and a.entidade_id = o.id::text
                          and a.acao = 'oportunidade.etapa'), 1)) as alcance,
           (select x.valor_final_centavos from public.propostas x where x.oportunidade_id = o.id and x.status = 'aceita' order by x.id desc limit 1) as valor_aceito
      from public.oportunidades o join cursos_ok c on c.id = o.curso_id join public.pessoas p on p.id = o.pessoa_id
      left join public.usuarios u on u.id = o.responsavel_id
     where o.ies_id = p_ies and o.coorte = p_coorte
  ), tot as (
    select count(*) as oportunidades,
           count(*) filter (where matricula_comercial_em is not null) as matriculas_comerciais,
           count(distinct pessoa_id) filter (where etapa = 'confirmado') as ingressantes,
           count(*) filter (where etapa = 'perdido') as perdidos,
           count(*) filter (where etapa = 'cancelado') as cancelamentos,
           count(*) filter (where etapa not in ('confirmado','perdido','cancelado')) as abertas,
           coalesce(sum(coalesce(valor_aceito, mensalidade_centavos)) filter (where etapa = 'confirmado'), 0) as receita_ingressos,
           coalesce(sum(coalesce(valor_aceito, mensalidade_centavos)) filter (where etapa not in ('confirmado','perdido','cancelado')), 0) as receita_pipeline_bruta
      from ops
  ), metas_f as (
    select sum(m.meta) as meta, count(*) as n from public.metas m join cursos_ok c on c.id = m.curso_id
     where m.ies_id = p_ies and m.coorte = p_coorte
  ), base as (
    select t.*, mf.meta, mf.n as n_metas,
           (t.ingressantes + t.perdidos + t.cancelamentos) as decididas,
           case when (t.ingressantes + t.perdidos + t.cancelamentos) = 0 then null
                else t.ingressantes::numeric / (t.ingressantes + t.perdidos + t.cancelamentos) end as taxa
      from tot t, metas_f mf
  )
  select jsonb_build_object(
    'coorte', p_coorte, 'filtros', p_filtros,
    'cobertura', case when privado.tem_acesso_ies(p_ies, todos) and f_campus is null and f_curso is null and f_turno is null and f_modal is null then 'ies' else 'recorte' end,
    'totais', (select jsonb_build_object(
        'oportunidades', b.oportunidades, 'matriculas_comerciais', b.matriculas_comerciais, 'ingressantes', b.ingressantes,
        'perdidos', b.perdidos, 'cancelamentos', b.cancelamentos, 'oportunidades_abertas', b.abertas,
        'conversao_geral', case when b.oportunidades = 0 then null else round(b.ingressantes::numeric / b.oportunidades, 4) end,
        'taxa_conversao_decididas', round(b.taxa, 4),
        'meta', case when b.n_metas = 0 then null else b.meta end,
        'atingimento', case when b.n_metas = 0 or b.meta = 0 then null else round(b.ingressantes::numeric / b.meta, 4) end,
        'ingressos_esperados_pipeline', case when b.taxa is null then null else round(b.abertas * b.taxa, 1) end,
        'projecao_ingressos', case when b.taxa is null then null else round(b.ingressantes + b.abertas * b.taxa, 1) end,
        'lacuna_meta', case when b.n_metas = 0 then null else greatest(b.meta - b.ingressantes, 0) end,
        'novas_oportunidades_necessarias', case when b.n_metas = 0 or b.taxa is null or b.taxa = 0 then null
          else greatest(ceil((b.meta - b.ingressantes - b.abertas * b.taxa) / b.taxa), 0) end,
        'receita_mensal_ingressantes_centavos', b.receita_ingressos,
        'receita_mensal_potencial_pipeline_centavos', case when b.taxa is null then null else round(b.receita_pipeline_bruta * b.taxa) end,
        'custo_por_lead_centavos', null, 'custo_por_matricula_centavos', null,
        'custo_motivo', 'Sem investimento cadastrado: disponível com o módulo de Campanhas (P1).',
        'metodos', jsonb_build_object(
          'taxa', 'Ingressantes ÷ oportunidades decididas (ingresso, perda ou cancelamento) da coorte.',
          'projecao', 'Ingressantes + oportunidades abertas × taxa das decididas.',
          'novas', '(Meta − ingressantes − ingressos esperados do pipeline) ÷ taxa das decididas.',
          'funil', 'Oportunidades que ALCANÇARAM cada etapa, reconstruído pelo histórico auditado. Quem confirmou e depois cancelou conta no alcance do ingresso, mas não entre os ingressantes efetivos.',
          'receita', 'Mensalidade do valor final da proposta aceita; sem proposta aceita, mensalidade cheia do curso. Pipeline ponderado pela taxa das decididas (estimativa).'))
      from base b),
    'funil', (select coalesce(jsonb_agg(jsonb_build_object('etapa', e.etapa, 'quantidade', e.q,
                'conversao_da_anterior', case when e.ant is null or e.ant = 0 then null else round(e.q::numeric / e.ant, 4) end) order by e.k), '[]'::jsonb)
              from (select k, etapa, q, lag(q) over (order by k) as ant from (
                      select s.k, s.etapa, (select count(*) from ops where alcance >= s.k) as q
                        from (values (1,'novo'),(2,'contato'),(3,'inscrito'),(4,'pre_matricula'),(5,'matricula_comercial'),(6,'confirmado')) s(k, etapa)) z) e),
    'evolucao', (select coalesce(jsonb_agg(jsonb_build_object('semana', w.semana, 'oportunidades', w.ops, 'matriculas_comerciais', w.mc, 'ingressantes', w.ing) order by w.semana), '[]'::jsonb)
                 from (select to_char(sem, 'YYYY-MM-DD') as semana,
                              (select count(*) from ops where date_trunc('week', criado_em) = sem) as ops,
                              (select count(*) from ops where date_trunc('week', matricula_comercial_em) = sem) as mc,
                              (select count(*) from ops where date_trunc('week', confirmada_em) = sem) as ing
                         from generate_series(date_trunc('week', now()) - interval '11 weeks', date_trunc('week', now()), interval '1 week') sem) w),
    'por_origem', (select coalesce(jsonb_agg(jsonb_build_object('chave', x.chave, 'oportunidades', x.n, 'ingressantes', x.ing,
                     'conversao', case when x.n = 0 then null else round(x.ing::numeric / x.n, 4) end) order by x.n desc), '[]'::jsonb)
                   from (select origem as chave, count(*) as n, count(distinct pessoa_id) filter (where etapa = 'confirmado') as ing from ops group by 1) x),
    'por_curso', (select coalesce(jsonb_agg(jsonb_build_object('chave', x.chave, 'curso_id', x.curso_id, 'oportunidades', x.n, 'ingressantes', x.ing,
                    'matriculas_comerciais', x.mc, 'meta', x.meta,
                    'atingimento', case when x.meta is null or x.meta = 0 then null else round(x.ing::numeric / x.meta, 4) end,
                    'conversao', case when x.n = 0 then null else round(x.ing::numeric / x.n, 4) end) order by x.chave), '[]'::jsonb)
                  from (select c.nome || ' · ' || c.turno as chave, c.id as curso_id, count(o.id) as n,
                               count(distinct o.pessoa_id) filter (where o.etapa = 'confirmado') as ing,
                               count(o.id) filter (where o.matricula_comercial_em is not null) as mc,
                               (select m.meta from public.metas m where m.ies_id = p_ies and m.curso_id = c.id and m.coorte = p_coorte) as meta
                          from cursos_ok c left join ops o on o.curso_id = c.id group by c.id, c.nome, c.turno) x),
    'por_turno', (select coalesce(jsonb_agg(jsonb_build_object('chave', turno, 'oportunidades', n, 'ingressantes', ing) order by turno), '[]'::jsonb)
                  from (select turno, count(*) n, count(distinct pessoa_id) filter (where etapa = 'confirmado') ing from ops group by 1) x),
    'por_modalidade', (select coalesce(jsonb_agg(jsonb_build_object('chave', modalidade, 'oportunidades', n, 'ingressantes', ing) order by modalidade), '[]'::jsonb)
                       from (select modalidade, count(*) n, count(distinct pessoa_id) filter (where etapa = 'confirmado') ing from ops group by 1) x),
    'por_atendente', (select coalesce(jsonb_agg(jsonb_build_object('chave', atendente, 'oportunidades', n, 'matriculas_comerciais', mc, 'ingressantes', ing,
                        'conversao', case when n = 0 then null else round(ing::numeric / n, 4) end) order by n desc), '[]'::jsonb)
                      from (select atendente, count(*) n, count(*) filter (where matricula_comercial_em is not null) mc,
                                   count(distinct pessoa_id) filter (where etapa = 'confirmado') ing from ops group by 1) x),
    'alertas', (select jsonb_agg(a order by (a->>'prioridade')::int, a->>'tipo') from (
        select jsonb_build_object('tipo', 'sla_vencido', 'prioridade', 1, 'titulo', 'Tarefas com SLA vencido',
               'quantidade', count(*), 'acao', 'Priorizar contato na fila do MAIM') as a
          from public.tarefas t join ops o on o.id = t.oportunidade_id where t.status = 'aberta' and t.vence_em < now()
        union all
        select jsonb_build_object('tipo', 'pendencia_validacao', 'prioridade', 1, 'titulo', 'Matrículas comerciais aguardando validação há mais de 48h',
               'quantidade', count(*), 'acao', 'Secretaria e financeiro: concluir validações em Conversão e Matrículas')
          from ops where etapa = 'matricula_comercial' and matricula_comercial_em < now() - interval '48 hours'
        union all
        select jsonb_build_object('tipo', 'proposta_aprovacao', 'prioridade', 2, 'titulo', 'Propostas aguardando aprovação do gestor',
               'quantidade', count(*), 'acao', 'Decidir em Conversão e Matrículas → Propostas')
          from public.propostas x join ops o on o.id = x.oportunidade_id where x.status = 'pendente_aprovacao'
        union all
        select jsonb_build_object('tipo', 'proposta_vencendo', 'prioridade', 2, 'titulo', 'Propostas aprovadas que vencem em até 48h',
               'quantidade', count(*), 'acao', 'Contatar o candidato para registrar o aceite')
          from public.propostas x join ops o on o.id = x.oportunidade_id
         where x.status = 'aprovada' and x.validade between now() and now() + interval '48 hours'
        union all
        select jsonb_build_object('tipo', 'parada', 'prioridade', 2, 'titulo', 'Oportunidades paradas sem tarefa aberta',
               'quantidade', count(*), 'acao', 'Executar o ciclo MAIM ou registrar contato')
          from ops o where o.etapa in ('contato','inscrito','pre_matricula')
           and o.atualizado_em < now() - make_interval(days => cfg.dias_sem_contato)
           and not exists (select 1 from public.tarefas t where t.oportunidade_id = o.id and t.status = 'aberta')
        union all
        select jsonb_build_object('tipo', 'sem_responsavel', 'prioridade', 3, 'titulo', 'Oportunidades abertas sem responsável',
               'quantidade', count(*), 'acao', 'Rever capacidade dos atendentes e redistribuir')
          from ops where etapa not in ('confirmado','perdido','cancelado') and responsavel_id is null
      ) z where (a->>'quantidade')::int > 0),
    'filtros_disponiveis', (select jsonb_build_object(
        'campi', (select coalesce(jsonb_agg(distinct jsonb_build_object('id', cp.id, 'nome', cp.nome)), '[]'::jsonb)
                    from public.cursos c join public.campus cp on cp.id = c.campus_id where c.ies_id = p_ies and privado.tem_acesso(p_ies, c.id, todos)),
        'turnos', (select coalesce(jsonb_agg(distinct c.turno), '[]'::jsonb) from public.cursos c where c.ies_id = p_ies and privado.tem_acesso(p_ies, c.id, todos)),
        'modalidades', (select coalesce(jsonb_agg(distinct c.modalidade), '[]'::jsonb) from public.cursos c where c.ies_id = p_ies and privado.tem_acesso(p_ies, c.id, todos))))
  ) into r;
  return r;
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.rpc_central(bigint, text, jsonb) to authenticated;

-- ===================== supabase/migrations/20261125000009_conformidade_biblia_v02.sql
-- Matrícula 360° — migração 9: conformidade com a Bíblia-Mestra v0.2, §6 (divergências D1, D2 e D3).
-- Decisão do responsável (25/11/2026):
--   (D1) indicador oficial = ⌈meta restante ÷ conversão observada⌉, em aritmética exata (corrige o artefato
--        R03: 169 → 168); o método por pipeline fica como "cenário complementar" identificado;
--   amostra mínima configurável por IES, padrão 30 (abaixo dela: N/D com motivo);
--   (D2) receita potencial = soma das mensalidades ofertadas válidas;
--   (D3) conversão de destaque = ingressantes ÷ oportunidades da coorte.

alter table public.ies add column if not exists amostra_minima_forecast int not null default 30
  check (amostra_minima_forecast between 1 and 10000);

create or replace function public.rpc_central(p_ies bigint, p_coorte text, p_filtros jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  todos constant text[] := array['gestor','reitoria','coordenador','comercial','secretaria','financeiro'];
  f_campus bigint := nullif(p_filtros->>'campus_id', '')::bigint;
  f_curso bigint := nullif(p_filtros->>'curso_id', '')::bigint;
  f_turno text := nullif(p_filtros->>'turno', '');
  f_modal text := nullif(p_filtros->>'modalidade', '');
  cfg public.ies; r jsonb;
  v_min int;
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if p_coorte !~ '^\d{4}\.[12]$' then raise exception 'Coorte deve ter formato AAAA.1 ou AAAA.2' using errcode = '22023'; end if;
  select * into cfg from public.ies where id = p_ies;
  v_min := cfg.amostra_minima_forecast;

  with cursos_ok as (
    select c.*, cp.nome as campus_nome from public.cursos c join public.campus cp on cp.id = c.campus_id
     where c.ies_id = p_ies and privado.tem_acesso(p_ies, c.id, todos)
       and (f_campus is null or c.campus_id = f_campus) and (f_curso is null or c.id = f_curso)
       and (f_turno is null or c.turno = f_turno) and (f_modal is null or c.modalidade = f_modal)
  ), ops as (
    select o.*, c.nome as curso, c.turno, c.modalidade, c.mensalidade_centavos, c.campus_nome, p.origem,
           coalesce(u.nome, 'Sem responsável') as atendente,
           greatest(
             case when o.etapa in ('perdido','cancelado') then 0 else privado.ordem_etapa(o.etapa) end,
             case when o.confirmada_em is not null then 6 when o.matricula_comercial_em is not null then 5 else 0 end,
             coalesce((select max(greatest(privado.ordem_etapa(a.dados->>'de'), privado.ordem_etapa(a.dados->>'para')))
                         from public.auditoria a where a.entidade = 'oportunidade' and a.entidade_id = o.id::text
                          and a.acao = 'oportunidade.etapa'), 1)) as alcance,
           (select x.valor_final_centavos from public.propostas x where x.oportunidade_id = o.id and x.status = 'aceita' order by x.id desc limit 1) as valor_aceito
      from public.oportunidades o join cursos_ok c on c.id = o.curso_id join public.pessoas p on p.id = o.pessoa_id
      left join public.usuarios u on u.id = o.responsavel_id
     where o.ies_id = p_ies and o.coorte = p_coorte
  ), tot as (
    select count(*) as oportunidades,
           count(*) filter (where matricula_comercial_em is not null) as matriculas_comerciais,
           count(distinct pessoa_id) filter (where etapa = 'confirmado') as ingressantes,
           count(*) filter (where etapa = 'perdido') as perdidos,
           count(*) filter (where etapa = 'cancelado') as cancelamentos,
           count(*) filter (where etapa not in ('confirmado','perdido','cancelado')) as abertas,
           coalesce(sum(coalesce(valor_aceito, mensalidade_centavos)) filter (where etapa = 'confirmado'), 0) as receita_ingressos,
           coalesce(sum(coalesce(valor_aceito, mensalidade_centavos)) filter (where etapa not in ('confirmado','perdido','cancelado')), 0) as receita_pipeline_bruta,
           -- Bíblia §6 (D2): receita potencial = soma das mensalidades ofertadas válidas (proposta ativa ou aceita, dentro da validade)
           (select coalesce(sum(x.valor_final_centavos), 0) from public.propostas x join ops o2 on o2.id = x.oportunidade_id
             where o2.etapa not in ('perdido','cancelado')
               and (x.status = 'aceita' or (x.status in ('aprovada','pendente_aprovacao') and x.validade >= now()))) as receita_ofertada,
           (select count(*) from public.propostas x join ops o2 on o2.id = x.oportunidade_id
             where o2.etapa not in ('perdido','cancelado')
               and (x.status = 'aceita' or (x.status in ('aprovada','pendente_aprovacao') and x.validade >= now()))) as n_ofertas
      from ops
  ), metas_f as (
    select sum(m.meta) as meta, count(*) as n from public.metas m join cursos_ok c on c.id = m.curso_id
     where m.ies_id = p_ies and m.coorte = p_coorte
  ), base as (
    select t.*, mf.meta, mf.n as n_metas,
           (t.ingressantes + t.perdidos + t.cancelamentos) as decididas,
           case when (t.ingressantes + t.perdidos + t.cancelamentos) = 0 then null
                else t.ingressantes::numeric / (t.ingressantes + t.perdidos + t.cancelamentos) end as taxa
      from tot t, metas_f mf
  )
  select jsonb_build_object(
    'coorte', p_coorte, 'filtros', p_filtros,
    'cobertura', case when privado.tem_acesso_ies(p_ies, todos) and f_campus is null and f_curso is null and f_turno is null and f_modal is null then 'ies' else 'recorte' end,
    'totais', (select jsonb_build_object(
        'oportunidades', b.oportunidades, 'matriculas_comerciais', b.matriculas_comerciais, 'ingressantes', b.ingressantes,
        'perdidos', b.perdidos, 'cancelamentos', b.cancelamentos, 'oportunidades_abertas', b.abertas,
        -- Bíblia §6 (D3): conversão = ingressantes efetivos ÷ oportunidades da mesma coorte
        'conversao', case when b.oportunidades = 0 then null else round(b.ingressantes::numeric / b.oportunidades, 4) end,
        'meta', case when b.n_metas = 0 then null else b.meta end,
        'atingimento', case when b.n_metas = 0 or b.meta = 0 then null else round(b.ingressantes::numeric / b.meta, 4) end,
        'meta_restante', case when b.n_metas = 0 then null else greatest(b.meta - b.ingressantes, 0) end,
        'amostra', b.oportunidades, 'amostra_minima', v_min,
        -- Bíblia §6 (D1): ceil(meta restante ÷ conversão observada NÃO arredondada), em aritmética inteira exata:
        -- meta_restante ÷ (ingressantes ÷ oportunidades) = meta_restante × oportunidades ÷ ingressantes
        'oportunidades_adicionais_projetadas', case
          when b.n_metas = 0 then null
          when greatest(b.meta - b.ingressantes, 0) = 0 then 0
          when b.ingressantes = 0 or b.oportunidades < v_min then null
          else (greatest(b.meta - b.ingressantes, 0)::bigint * b.oportunidades + b.ingressantes - 1) / b.ingressantes end,
        'forecast_motivo', case
          when b.n_metas = 0 then 'Sem meta cadastrada no recorte.'
          when greatest(b.meta - b.ingressantes, 0) = 0 then 'Meta cumprida: necessidade adicional zero.'
          when b.ingressantes = 0 then 'Conversão observada zero: projeção indisponível.'
          when b.oportunidades < v_min then format('Amostra insuficiente: %s oportunidades (mínimo configurado: %s).', b.oportunidades, v_min)
          else null end,
        'cenario_pipeline', jsonb_build_object(
          'rotulo', 'Cenário complementar (não é o indicador oficial)',
          'taxa_conversao_decididas', round(b.taxa, 4),
          'ingressos_esperados_pipeline', case when b.taxa is null then null else round(b.abertas * b.taxa, 1) end,
          'projecao_ingressos', case when b.taxa is null then null else round(b.ingressantes + b.abertas * b.taxa, 1) end,
          'novas_oportunidades_necessarias', case when b.n_metas = 0 or b.taxa is null or b.taxa = 0 then null
            else greatest(ceil((b.meta - b.ingressantes - b.abertas * b.taxa) / b.taxa), 0) end),
        'receita_mensal_ingressantes_centavos', b.receita_ingressos,
        'receita_mensal_potencial_ofertada_centavos', b.receita_ofertada,
        'propostas_validas', b.n_ofertas,
        'custo_por_lead_centavos', null, 'custo_por_matricula_centavos', null,
        'custo_motivo', 'Sem investimento cadastrado: disponível com o módulo de Campanhas (P1).',
        'metodos', jsonb_build_object(
          'conversao', 'Ingressantes efetivos (pessoas distintas) ÷ oportunidades da mesma coorte (Bíblia §6).',
          'projecao', 'Oportunidades adicionais = ⌈meta restante ÷ conversão observada⌉, com a conversão não arredondada (Bíblia §6). N/D com conversão zero ou amostra abaixo do mínimo configurado; zero com a meta cumprida.',
          'cenario', 'Cenário complementar: taxa sobre oportunidades decididas (ingresso, perda ou cancelamento) aplicada ao pipeline aberto. Não substitui o indicador oficial.',
          'receita', 'Receita potencial = soma das mensalidades ofertadas válidas (propostas ativas dentro da validade ou aceitas), valor mensal, natureza de projeção (Bíblia §6). Ingressantes: mensalidade da proposta aceita ou mensalidade cheia do curso.',
          'funil', 'Oportunidades que ALCANÇARAM cada etapa, reconstruído pelo histórico auditado. Quem confirmou e depois cancelou conta no alcance do ingresso, mas não entre os ingressantes efetivos.'))
      from base b),
    'funil', (select coalesce(jsonb_agg(jsonb_build_object('etapa', e.etapa, 'quantidade', e.q,
                'conversao_da_anterior', case when e.ant is null or e.ant = 0 then null else round(e.q::numeric / e.ant, 4) end) order by e.k), '[]'::jsonb)
              from (select k, etapa, q, lag(q) over (order by k) as ant from (
                      select s.k, s.etapa, (select count(*) from ops where alcance >= s.k) as q
                        from (values (1,'novo'),(2,'contato'),(3,'inscrito'),(4,'pre_matricula'),(5,'matricula_comercial'),(6,'confirmado')) s(k, etapa)) z) e),
    'evolucao', (select coalesce(jsonb_agg(jsonb_build_object('semana', w.semana, 'oportunidades', w.ops, 'matriculas_comerciais', w.mc, 'ingressantes', w.ing) order by w.semana), '[]'::jsonb)
                 from (select to_char(sem, 'YYYY-MM-DD') as semana,
                              (select count(*) from ops where date_trunc('week', criado_em) = sem) as ops,
                              (select count(*) from ops where date_trunc('week', matricula_comercial_em) = sem) as mc,
                              (select count(*) from ops where date_trunc('week', confirmada_em) = sem) as ing
                         from generate_series(date_trunc('week', now()) - interval '11 weeks', date_trunc('week', now()), interval '1 week') sem) w),
    'por_origem', (select coalesce(jsonb_agg(jsonb_build_object('chave', x.chave, 'oportunidades', x.n, 'ingressantes', x.ing,
                     'conversao', case when x.n = 0 then null else round(x.ing::numeric / x.n, 4) end) order by x.n desc), '[]'::jsonb)
                   from (select origem as chave, count(*) as n, count(distinct pessoa_id) filter (where etapa = 'confirmado') as ing from ops group by 1) x),
    'por_curso', (select coalesce(jsonb_agg(jsonb_build_object('chave', x.chave, 'curso_id', x.curso_id, 'oportunidades', x.n, 'ingressantes', x.ing,
                    'matriculas_comerciais', x.mc, 'meta', x.meta,
                    'atingimento', case when x.meta is null or x.meta = 0 then null else round(x.ing::numeric / x.meta, 4) end,
                    'conversao', case when x.n = 0 then null else round(x.ing::numeric / x.n, 4) end) order by x.chave), '[]'::jsonb)
                  from (select c.nome || ' · ' || c.turno as chave, c.id as curso_id, count(o.id) as n,
                               count(distinct o.pessoa_id) filter (where o.etapa = 'confirmado') as ing,
                               count(o.id) filter (where o.matricula_comercial_em is not null) as mc,
                               (select m.meta from public.metas m where m.ies_id = p_ies and m.curso_id = c.id and m.coorte = p_coorte) as meta
                          from cursos_ok c left join ops o on o.curso_id = c.id group by c.id, c.nome, c.turno) x),
    'por_turno', (select coalesce(jsonb_agg(jsonb_build_object('chave', turno, 'oportunidades', n, 'ingressantes', ing) order by turno), '[]'::jsonb)
                  from (select turno, count(*) n, count(distinct pessoa_id) filter (where etapa = 'confirmado') ing from ops group by 1) x),
    'por_modalidade', (select coalesce(jsonb_agg(jsonb_build_object('chave', modalidade, 'oportunidades', n, 'ingressantes', ing) order by modalidade), '[]'::jsonb)
                       from (select modalidade, count(*) n, count(distinct pessoa_id) filter (where etapa = 'confirmado') ing from ops group by 1) x),
    'por_atendente', (select coalesce(jsonb_agg(jsonb_build_object('chave', atendente, 'oportunidades', n, 'matriculas_comerciais', mc, 'ingressantes', ing,
                        'conversao', case when n = 0 then null else round(ing::numeric / n, 4) end) order by n desc), '[]'::jsonb)
                      from (select atendente, count(*) n, count(*) filter (where matricula_comercial_em is not null) mc,
                                   count(distinct pessoa_id) filter (where etapa = 'confirmado') ing from ops group by 1) x),
    'alertas', (select jsonb_agg(a order by (a->>'prioridade')::int, a->>'tipo') from (
        select jsonb_build_object('tipo', 'sla_vencido', 'prioridade', 1, 'titulo', 'Tarefas com SLA vencido',
               'quantidade', count(*), 'acao', 'Priorizar contato na fila do MAIM') as a
          from public.tarefas t join ops o on o.id = t.oportunidade_id where t.status = 'aberta' and t.vence_em < now()
        union all
        select jsonb_build_object('tipo', 'pendencia_validacao', 'prioridade', 1, 'titulo', 'Matrículas comerciais aguardando validação há mais de 48h',
               'quantidade', count(*), 'acao', 'Secretaria e financeiro: concluir validações em Conversão e Matrículas')
          from ops where etapa = 'matricula_comercial' and matricula_comercial_em < now() - interval '48 hours'
        union all
        select jsonb_build_object('tipo', 'proposta_aprovacao', 'prioridade', 2, 'titulo', 'Propostas aguardando aprovação do gestor',
               'quantidade', count(*), 'acao', 'Decidir em Conversão e Matrículas → Propostas')
          from public.propostas x join ops o on o.id = x.oportunidade_id where x.status = 'pendente_aprovacao'
        union all
        select jsonb_build_object('tipo', 'proposta_vencendo', 'prioridade', 2, 'titulo', 'Propostas aprovadas que vencem em até 48h',
               'quantidade', count(*), 'acao', 'Contatar o candidato para registrar o aceite')
          from public.propostas x join ops o on o.id = x.oportunidade_id
         where x.status = 'aprovada' and x.validade between now() and now() + interval '48 hours'
        union all
        select jsonb_build_object('tipo', 'parada', 'prioridade', 2, 'titulo', 'Oportunidades paradas sem tarefa aberta',
               'quantidade', count(*), 'acao', 'Executar o ciclo MAIM ou registrar contato')
          from ops o where o.etapa in ('contato','inscrito','pre_matricula')
           and o.atualizado_em < now() - make_interval(days => cfg.dias_sem_contato)
           and not exists (select 1 from public.tarefas t where t.oportunidade_id = o.id and t.status = 'aberta')
        union all
        select jsonb_build_object('tipo', 'sem_responsavel', 'prioridade', 3, 'titulo', 'Oportunidades abertas sem responsável',
               'quantidade', count(*), 'acao', 'Rever capacidade dos atendentes e redistribuir')
          from ops where etapa not in ('confirmado','perdido','cancelado') and responsavel_id is null
      ) z where (a->>'quantidade')::int > 0),
    'filtros_disponiveis', (select jsonb_build_object(
        'campi', (select coalesce(jsonb_agg(distinct jsonb_build_object('id', cp.id, 'nome', cp.nome)), '[]'::jsonb)
                    from public.cursos c join public.campus cp on cp.id = c.campus_id where c.ies_id = p_ies and privado.tem_acesso(p_ies, c.id, todos)),
        'turnos', (select coalesce(jsonb_agg(distinct c.turno), '[]'::jsonb) from public.cursos c where c.ies_id = p_ies and privado.tem_acesso(p_ies, c.id, todos)),
        'modalidades', (select coalesce(jsonb_agg(distinct c.modalidade), '[]'::jsonb) from public.cursos c where c.ies_id = p_ies and privado.tem_acesso(p_ies, c.id, todos))))
  ) into r;
  return r;
end $$;

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
      -- Projeção (migração 7): taxa sobre oportunidades DECIDIDAS (ingresso, perda ou cancelamento).
      -- A coorte em andamento não entra no denominador. Sem base decidida => N/D.
      'oportunidades_abertas', t.oportunidades - t.ingressantes - t.perdidos - t.cancelamentos,
      'taxa_conversao_decididas', case when (t.ingressantes + t.perdidos + t.cancelamentos) = 0 then null
        else round(t.ingressantes::numeric / (t.ingressantes + t.perdidos + t.cancelamentos), 4) end,
      'ingressos_esperados_pipeline', case when (t.ingressantes + t.perdidos + t.cancelamentos) = 0 then null
        else round((t.oportunidades - t.ingressantes - t.perdidos - t.cancelamentos)
                   * t.ingressantes::numeric / (t.ingressantes + t.perdidos + t.cancelamentos), 1) end,
      'lacuna_meta', case when v_meta is null then null else greatest(v_meta - t.ingressantes, 0) end,
      'projecao_oportunidades_necessarias', case
        when v_meta is null then null
        when greatest(v_meta - t.ingressantes, 0) = 0 then 0
        when t.ingressantes = 0 or t.oportunidades < (select amostra_minima_forecast from public.ies where id = p_ies) then null
        else (greatest(v_meta - t.ingressantes, 0)::bigint * t.oportunidades + t.ingressantes - 1) / t.ingressantes end,
      'projecao_metodo', 'Oportunidades adicionais = ⌈meta restante ÷ conversão observada⌉ em aritmética exata (Bíblia §6); N/D com conversão zero ou amostra abaixo do mínimo.'),
    'linhas', linhas);
end $$;

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
                              'dias_sem_contato', i.dias_sem_contato, 'capacidade_atendente', i.capacidade_atendente, 'amostra_minima_forecast', i.amostra_minima_forecast),
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

drop function if exists public.rpc_configurar(bigint, int, int, int, int);
create or replace function public.rpc_configurar(p_ies bigint, p_sla_horas int default null, p_max_followups int default null,
  p_dias_sem_contato int default null, p_capacidade_atendente int default null,
  p_amostra_minima_forecast int default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.ies;
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if not privado.tem_acesso_ies(p_ies, array['gestor']) then raise exception 'Seu perfil não tem permissão para esta operação' using errcode = '42501'; end if;
  if coalesce(p_sla_horas, p_max_followups, p_dias_sem_contato, p_capacidade_atendente, p_amostra_minima_forecast) is null then
    raise exception 'Nada a alterar' using errcode = '22023';
  end if;
  update public.ies set
    sla_horas = coalesce(p_sla_horas, sla_horas),
    max_followups = coalesce(p_max_followups, max_followups),
    dias_sem_contato = coalesce(p_dias_sem_contato, dias_sem_contato),
    capacidade_atendente = coalesce(p_capacidade_atendente, capacidade_atendente),
    amostra_minima_forecast = coalesce(p_amostra_minima_forecast, amostra_minima_forecast)
   where id = p_ies returning * into r;
  perform privado.auditar(p_ies, 'ies.configurar', 'ies', p_ies::text, jsonb_build_object(
    'sla_horas', r.sla_horas, 'max_followups', r.max_followups, 'dias_sem_contato', r.dias_sem_contato, 'capacidade_atendente', r.capacidade_atendente, 'amostra_minima_forecast', r.amostra_minima_forecast));
  return jsonb_build_object('sla_horas', r.sla_horas, 'max_followups', r.max_followups,
    'dias_sem_contato', r.dias_sem_contato, 'capacidade_atendente', r.capacidade_atendente, 'amostra_minima_forecast', r.amostra_minima_forecast);
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.rpc_central(bigint, text, jsonb), public.rpc_bi(bigint, text, text),
  public.rpc_estrutura(bigint), public.rpc_configurar(bigint, int, int, int, int, int) to authenticated;

-- ===================== supabase/migrations/20261125000010_crm_avancado.sql
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

-- ===================== supabase/migrations/20261125000011_governanca.sql
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

-- ===================== supabase/migrations/20261125000012_planejamento_campanhas.sql
-- Matrícula 360° — migração 12: Planejamento Estratégico (E02) e Marketing e Captação (E03). Bíblia v0.2 §2, §6 e §7.
--   * Plano por coorte com diagnóstico, orçamento, revisão periódica e aprovação por pessoa diferente de quem criou.
--   * Objetivos com indicador e meta, e o realizado calculado a partir dos dados (nunca digitado).
--   * Ações 5W2H vinculadas a objetivos, com acompanhamento de execução.
--   * Campanhas com canal, coorte, vigência, orçamento e código de atribuição; custos lançados com estorno auditado.
--   * Atribuição de origem na oportunidade; sem campanha = "atribuição desconhecida" (Bíblia §7).
--   * CPL e custo por ingressante na Central, com método e N/D quando faltar base (Bíblia §6).
--   * Concorrência apenas com fonte verificável e data de coleta, e revisão humana por outra pessoa.
--   * Integrações (Meta, Google, TikTok, WhatsApp) continuam DESLIGADAS: canais são apenas classificação.
-- Autorização destas RPCs vem da matriz de permissões (privado.autorizar). Tabelas sem política de leitura:
-- todo acesso passa por RPC. Idempotente.

-- ---------------------------------------------------------------- autorização pela matriz
create or replace function privado.autorizar(p_ies bigint, p_operacao text) returns void
language plpgsql stable security definer set search_path = '' as $$
declare m public.matriz_permissoes;
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  select * into m from public.matriz_permissoes where operacao = p_operacao;
  if not found then raise exception 'Operação não cadastrada na matriz: %', p_operacao using errcode = '42501'; end if;
  if (m.abrangencia_minima = 'ies' and not privado.tem_acesso_ies(p_ies, m.papeis))
     or (m.abrangencia_minima = 'curso' and not exists (select 1 from public.cursos c where c.ies_id = p_ies and privado.tem_acesso(p_ies, c.id, m.papeis))) then
    raise exception 'Seu perfil não tem permissão para esta operação' using errcode = '42501';
  end if;
end $$;
revoke execute on function privado.autorizar(bigint, text) from public, anon, authenticated;

create or replace function privado.pode(p_ies bigint, p_operacao text) returns boolean
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.autorizar(p_ies, p_operacao);
  return true;
exception when others then return false;
end $$;
revoke execute on function privado.pode(bigint, text) from public, anon, authenticated;

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('planejamento.ver',      'Planejamento Estratégico', 'Ver plano, objetivos, orçamento e ações 5W2H', array['gestor','reitoria','coordenador'], 'curso', 'rpc_planejamento'),
  ('planejamento.editar',   'Planejamento Estratégico', 'Criar e editar plano, objetivos e ações',       array['gestor'], 'ies', 'rpc_salvar_plano'),
  ('planejamento.aprovar',  'Planejamento Estratégico', 'Aprovar ou devolver plano (nunca o próprio)',   array['gestor','reitoria'], 'ies', 'rpc_plano_status'),
  ('concorrencia.registrar','Planejamento Estratégico', 'Registrar oferta concorrente com fonte e data',  array['gestor','coordenador'], 'curso', 'rpc_registrar_concorrencia'),
  ('concorrencia.revisar',  'Planejamento Estratégico', 'Revisar registro de concorrência (nunca o próprio)', array['gestor'], 'ies', 'rpc_revisar_concorrencia'),
  ('campanha.ver',          'Marketing e Captação',     'Ver campanhas e códigos de atribuição',         array['gestor','reitoria','coordenador','comercial','financeiro'], 'curso', 'rpc_campanhas'),
  ('campanha.editar',       'Marketing e Captação',     'Criar e editar campanhas',                      array['gestor'], 'ies', 'rpc_salvar_campanha'),
  ('campanha.custos_ver',   'Marketing e Captação',     'Ver custos, CPL e custo por ingressante',       array['gestor','reitoria','financeiro'], 'ies', 'rpc_campanhas'),
  ('custo.lancar',          'Marketing e Captação',     'Lançar e estornar custo de campanha',           array['gestor','financeiro'], 'ies', 'rpc_lancar_custo')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

-- ---------------------------------------------------------------- tabelas
create table if not exists public.planos (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  coorte text not null check (coorte ~ '^\d{4}\.[12]$'),
  titulo text not null check (length(titulo) between 3 and 120),
  diagnostico text check (length(diagnostico) <= 4000),
  orcamento_centavos bigint not null default 0 check (orcamento_centavos >= 0),
  status text not null default 'rascunho' check (status in ('rascunho','em_aprovacao','aprovado','em_revisao','encerrado')),
  revisar_em date,
  versao int not null default 1,
  criado_por uuid not null references public.usuarios(id),
  criado_em timestamptz not null default now(),
  aprovado_por uuid references public.usuarios(id),
  aprovado_em timestamptz,
  atualizado_em timestamptz not null default now(),
  unique (ies_id, coorte, titulo)
);
create table if not exists public.objetivos (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  plano_id bigint not null references public.planos(id),
  descricao text not null check (length(descricao) between 3 and 300),
  indicador text not null check (indicador in ('ingressantes','oportunidades','matriculas_comerciais','conversao','cpl_centavos','custo_ingressante_centavos')),
  curso_id bigint references public.cursos(id),
  meta numeric(14,4) not null check (meta >= 0),
  prazo date,
  criado_em timestamptz not null default now()
);
create table if not exists public.acoes (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  plano_id bigint not null references public.planos(id),
  objetivo_id bigint references public.objetivos(id),
  o_que text not null check (length(o_que) between 3 and 200),
  por_que text not null check (length(por_que) between 3 and 400),
  onde text,
  quando date not null,
  quem text not null check (length(quem) between 2 and 120),
  como text,
  quanto_centavos bigint not null default 0 check (quanto_centavos >= 0),
  status text not null default 'pendente' check (status in ('pendente','em_andamento','concluida','cancelada')),
  atualizado_em timestamptz not null default now()
);
create table if not exists public.campanhas (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  plano_id bigint references public.planos(id),
  coorte text not null check (coorte ~ '^\d{4}\.[12]$'),
  nome text not null check (length(nome) between 3 and 120),
  codigo text not null check (codigo ~ '^[a-z0-9][a-z0-9-]{2,40}$'),
  canal text not null check (canal in ('meta_ads','google_ads','tiktok_ads','whatsapp','email','site','evento','visita_escolar','indicacao','convenio','radio_tv','impresso','outro')),
  inicio date not null,
  fim date not null,
  orcamento_centavos bigint not null default 0 check (orcamento_centavos >= 0),
  status text not null default 'planejada' check (status in ('planejada','ativa','encerrada','cancelada')),
  objetivo text,
  versao int not null default 1,
  criado_por uuid not null references public.usuarios(id),
  criado_em timestamptz not null default now(),
  check (fim >= inicio),
  unique (ies_id, codigo)
);
create table if not exists public.custos_campanha (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  campanha_id bigint not null references public.campanhas(id),
  data date not null,
  valor_centavos bigint not null check (valor_centavos > 0),
  descricao text not null check (length(descricao) between 3 and 200),
  lancado_por uuid not null references public.usuarios(id),
  lancado_em timestamptz not null default now(),
  chave text,
  estornado_em timestamptz,
  estornado_por uuid references public.usuarios(id),
  motivo_estorno text,
  unique (lancado_por, chave)
);
create table if not exists public.concorrencia (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  instituicao text not null check (length(instituicao) between 2 and 120),
  curso text not null check (length(curso) between 2 and 120),
  modalidade text check (modalidade in ('presencial','ead','semipresencial')),
  mensalidade_centavos bigint check (mensalidade_centavos > 0),
  fonte_url text not null check (fonte_url ~ '^https?://[^\s]+\.[^\s]+$'),
  coletado_em date not null,
  observacao text check (length(observacao) <= 500),
  registrado_por uuid not null references public.usuarios(id),
  registrado_em timestamptz not null default now(),
  revisado_por uuid references public.usuarios(id),
  revisado_em timestamptz
);
alter table public.oportunidades add column if not exists campanha_id bigint references public.campanhas(id);

create index if not exists planos_ies on public.planos(ies_id, coorte);
create index if not exists objetivos_plano on public.objetivos(plano_id);
create index if not exists objetivos_curso on public.objetivos(curso_id);
create index if not exists objetivos_ies on public.objetivos(ies_id);
create index if not exists acoes_plano on public.acoes(plano_id);
create index if not exists acoes_objetivo on public.acoes(objetivo_id);
create index if not exists acoes_ies on public.acoes(ies_id);
create index if not exists campanhas_ies on public.campanhas(ies_id, coorte);
create index if not exists campanhas_plano on public.campanhas(plano_id);
create index if not exists custos_campanha_c on public.custos_campanha(campanha_id);
create index if not exists custos_campanha_ies on public.custos_campanha(ies_id);
create index if not exists concorrencia_ies on public.concorrencia(ies_id);
create index if not exists oportunidades_campanha on public.oportunidades(campanha_id);
create index if not exists fk_planos_criado on public.planos(criado_por);
create index if not exists fk_planos_aprovado on public.planos(aprovado_por);
create index if not exists fk_campanhas_criado on public.campanhas(criado_por);
create index if not exists fk_custos_lancado on public.custos_campanha(lancado_por);
create index if not exists fk_custos_estornado on public.custos_campanha(estornado_por);
create index if not exists fk_conc_registrado on public.concorrencia(registrado_por);
create index if not exists fk_conc_revisado on public.concorrencia(revisado_por);

alter table public.planos enable row level security;
alter table public.objetivos enable row level security;
alter table public.acoes enable row level security;
alter table public.campanhas enable row level security;
alter table public.custos_campanha enable row level security;
alter table public.concorrencia enable row level security;
revoke all on public.planos, public.objetivos, public.acoes, public.campanhas, public.custos_campanha, public.concorrencia from anon, authenticated;

-- ---------------------------------------------------------------- Planejamento
create or replace function public.rpc_salvar_plano(p_ies bigint, p_dados jsonb, p_id bigint default null, p_versao int default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare pl public.planos; v_id bigint;
begin
  perform privado.autorizar(p_ies, 'planejamento.editar');
  if p_id is null then
    insert into public.planos(ies_id, coorte, titulo, diagnostico, orcamento_centavos, revisar_em, criado_por)
    values (p_ies, p_dados->>'coorte', trim(p_dados->>'titulo'), nullif(trim(p_dados->>'diagnostico'), ''),
            coalesce((p_dados->>'orcamento_centavos')::bigint, 0), nullif(p_dados->>'revisar_em', '')::date, (select auth.uid()))
    returning id into v_id;
    perform privado.auditar(p_ies, 'plano.criar', 'plano', v_id::text, jsonb_build_object('coorte', p_dados->>'coorte'));
    return jsonb_build_object('id', v_id, 'versao', 1);
  end if;
  select * into pl from public.planos where id = p_id and ies_id = p_ies for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if pl.versao <> coalesce(p_versao, -1) then perform privado.erro_http(409, '40001', 'Conflito de versão: o plano foi alterado por outra pessoa. Recarregue.'); end if;
  if pl.status not in ('rascunho','em_revisao') then raise exception 'Plano % não pode ser editado; devolva para revisão antes', pl.status using errcode = '22023'; end if;
  update public.planos set titulo = coalesce(trim(p_dados->>'titulo'), titulo), diagnostico = coalesce(nullif(trim(p_dados->>'diagnostico'), ''), diagnostico),
         orcamento_centavos = coalesce((p_dados->>'orcamento_centavos')::bigint, orcamento_centavos),
         revisar_em = coalesce(nullif(p_dados->>'revisar_em', '')::date, revisar_em), versao = versao + 1, atualizado_em = now()
   where id = p_id;
  perform privado.auditar(p_ies, 'plano.editar', 'plano', p_id::text, jsonb_build_object('versao', pl.versao + 1));
  return jsonb_build_object('id', p_id, 'versao', pl.versao + 1);
exception when unique_violation then
  perform privado.erro_http(409, '23505', 'Já existe plano com este título na coorte');
end $$;

-- Fluxo: rascunho → em_aprovacao → aprovado → (em_revisao → em_aprovacao) → encerrado. Quem cria não aprova.
create or replace function public.rpc_plano_status(p_plano bigint, p_acao text, p_justificativa text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare pl public.planos; novo text;
begin
  perform privado.exigir_usuario();
  select * into pl from public.planos where id = p_plano for update;
  if not found or not privado.ve_ies(pl.ies_id) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if p_acao in ('submeter','revisar','encerrar') then perform privado.autorizar(pl.ies_id, 'planejamento.editar');
  elsif p_acao in ('aprovar','devolver') then perform privado.autorizar(pl.ies_id, 'planejamento.aprovar');
  else raise exception 'Ação inválida' using errcode = '22023'; end if;
  novo := case
    when p_acao = 'submeter' and pl.status in ('rascunho','em_revisao') then 'em_aprovacao'
    when p_acao = 'aprovar'  and pl.status = 'em_aprovacao' then 'aprovado'
    when p_acao = 'devolver' and pl.status = 'em_aprovacao' then 'em_revisao'
    when p_acao = 'revisar'  and pl.status = 'aprovado' then 'em_revisao'
    when p_acao = 'encerrar' and pl.status = 'aprovado' then 'encerrado' end;
  if novo is null then raise exception 'Transição inválida: % → %', pl.status, p_acao using errcode = '22023'; end if;
  if p_acao = 'aprovar' and pl.criado_por = (select auth.uid()) then
    raise exception 'Segregação de funções: quem criou o plano não o aprova' using errcode = '42501';
  end if;
  if p_acao = 'submeter' and not exists (select 1 from public.objetivos where plano_id = p_plano) then
    raise exception 'Cadastre ao menos um objetivo antes de submeter' using errcode = '22023';
  end if;
  if p_acao in ('devolver','revisar','encerrar') and length(coalesce(trim(p_justificativa), '')) < 3 then
    raise exception 'Justificativa obrigatória' using errcode = '22023';
  end if;
  update public.planos set status = novo, versao = versao + 1, atualizado_em = now(),
         aprovado_por = case when novo = 'aprovado' then (select auth.uid()) else aprovado_por end,
         aprovado_em = case when novo = 'aprovado' then now() else aprovado_em end
   where id = p_plano;
  perform privado.auditar(pl.ies_id, 'plano.' || p_acao, 'plano', p_plano::text,
    jsonb_build_object('de', pl.status, 'para', novo, 'justificativa', nullif(trim(coalesce(p_justificativa, '')), '')));
  return jsonb_build_object('id', p_plano, 'status', novo);
end $$;

create or replace function privado.plano_editavel(p_plano bigint) returns public.planos
language plpgsql security definer set search_path = '' as $$
declare pl public.planos;
begin
  select * into pl from public.planos where id = p_plano for update;
  if not found or not privado.ve_ies(pl.ies_id) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(pl.ies_id, 'planejamento.editar');
  return pl;
end $$;
revoke execute on function privado.plano_editavel(bigint) from public, anon, authenticated;

create or replace function public.rpc_salvar_objetivo(p_plano bigint, p_dados jsonb, p_id bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare pl public.planos; v_id bigint; v_curso bigint := nullif(p_dados->>'curso_id', '')::bigint;
begin
  pl := privado.plano_editavel(p_plano);
  if pl.status not in ('rascunho','em_revisao') then raise exception 'Objetivos só mudam com o plano em rascunho ou revisão' using errcode = '22023'; end if;
  if v_curso is not null and not exists (select 1 from public.cursos where id = v_curso and ies_id = pl.ies_id) then
    raise exception 'Curso não pertence à IES' using errcode = '22023';
  end if;
  if p_dados->>'indicador' = 'conversao' and (p_dados->>'meta')::numeric > 1 then raise exception 'Meta de conversão é uma fração entre 0 e 1' using errcode = '22023'; end if;
  if p_id is null then
    insert into public.objetivos(ies_id, plano_id, descricao, indicador, curso_id, meta, prazo)
    values (pl.ies_id, p_plano, trim(p_dados->>'descricao'), p_dados->>'indicador', v_curso, (p_dados->>'meta')::numeric, nullif(p_dados->>'prazo', '')::date)
    returning id into v_id;
  else
    update public.objetivos set descricao = trim(p_dados->>'descricao'), indicador = p_dados->>'indicador', curso_id = v_curso,
           meta = (p_dados->>'meta')::numeric, prazo = nullif(p_dados->>'prazo', '')::date
     where id = p_id and plano_id = p_plano returning id into v_id;
    if v_id is null then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  end if;
  perform privado.auditar(pl.ies_id, 'objetivo.salvar', 'plano', p_plano::text, jsonb_build_object('objetivo_id', v_id, 'indicador', p_dados->>'indicador'));
  return jsonb_build_object('id', v_id);
end $$;

create or replace function public.rpc_salvar_acao(p_plano bigint, p_dados jsonb, p_id bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare pl public.planos; v_id bigint; a public.acoes; v_obj bigint := nullif(p_dados->>'objetivo_id', '')::bigint;
begin
  pl := privado.plano_editavel(p_plano);
  if v_obj is not null and not exists (select 1 from public.objetivos where id = v_obj and plano_id = p_plano) then
    raise exception 'Objetivo não pertence ao plano' using errcode = '22023';
  end if;
  if p_id is null then
    if pl.status not in ('rascunho','em_revisao') then raise exception 'Novas ações só com o plano em rascunho ou revisão' using errcode = '22023'; end if;
    insert into public.acoes(ies_id, plano_id, objetivo_id, o_que, por_que, onde, quando, quem, como, quanto_centavos)
    values (pl.ies_id, p_plano, v_obj, trim(p_dados->>'o_que'), trim(p_dados->>'por_que'), nullif(trim(p_dados->>'onde'), ''),
            (p_dados->>'quando')::date, trim(p_dados->>'quem'), nullif(trim(p_dados->>'como'), ''), coalesce((p_dados->>'quanto_centavos')::bigint, 0))
    returning id into v_id;
  else
    select * into a from public.acoes where id = p_id and plano_id = p_plano for update;
    if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
    if pl.status in ('aprovado') then
      -- Plano aprovado: só o andamento da execução muda; o conteúdo aprovado fica preservado.
      if p_dados ?| array['o_que','por_que','onde','quando','quem','como','quanto_centavos','objetivo_id'] then
        raise exception 'Plano aprovado: só o status da ação pode mudar' using errcode = '22023';
      end if;
    elsif pl.status not in ('rascunho','em_revisao') then raise exception 'Plano % não aceita alterações', pl.status using errcode = '22023'; end if;
    update public.acoes set
      o_que = coalesce(trim(p_dados->>'o_que'), o_que), por_que = coalesce(trim(p_dados->>'por_que'), por_que),
      onde = coalesce(nullif(trim(p_dados->>'onde'), ''), onde), quando = coalesce((p_dados->>'quando')::date, quando),
      quem = coalesce(trim(p_dados->>'quem'), quem), como = coalesce(nullif(trim(p_dados->>'como'), ''), como),
      quanto_centavos = coalesce((p_dados->>'quanto_centavos')::bigint, quanto_centavos),
      objetivo_id = case when p_dados ? 'objetivo_id' then v_obj else objetivo_id end,
      status = coalesce(p_dados->>'status', status), atualizado_em = now()
     where id = p_id returning id into v_id;
  end if;
  perform privado.auditar(pl.ies_id, 'acao.salvar', 'plano', p_plano::text, jsonb_build_object('acao_id', v_id, 'status', p_dados->>'status'));
  return jsonb_build_object('id', v_id);
end $$;

-- Realizado de cada indicador, calculado dos dados (Bíblia §6). N/D quando faltar base.
create or replace function privado.realizado(p_ies bigint, p_coorte text, p_indicador text, p_curso bigint) returns numeric
language plpgsql stable security definer set search_path = '' as $$
declare n bigint; ing bigint; mc bigint; custo bigint; leads bigint; ing_atr bigint;
begin
  select count(*), count(distinct pessoa_id) filter (where etapa = 'confirmado'), count(*) filter (where matricula_comercial_em is not null),
         count(*) filter (where campanha_id is not null), count(distinct pessoa_id) filter (where etapa = 'confirmado' and campanha_id is not null)
    into n, ing, mc, leads, ing_atr
    from public.oportunidades where ies_id = p_ies and coorte = p_coorte and (p_curso is null or curso_id = p_curso);
  if p_indicador = 'oportunidades' then return n; end if;
  if p_indicador = 'ingressantes' then return ing; end if;
  if p_indicador = 'matriculas_comerciais' then return mc; end if;
  if p_indicador = 'conversao' then return case when n = 0 then null else round(ing::numeric / n, 4) end; end if;
  if p_curso is not null then return null; end if; -- custo não é rateado por curso
  select coalesce(sum(cc.valor_centavos), 0) into custo from public.custos_campanha cc join public.campanhas k on k.id = cc.campanha_id
   where k.ies_id = p_ies and k.coorte = p_coorte and cc.estornado_em is null;
  if custo = 0 then return null; end if;
  if p_indicador = 'cpl_centavos' then return case when leads = 0 then null else round(custo::numeric / leads) end; end if;
  if p_indicador = 'custo_ingressante_centavos' then return case when ing_atr = 0 then null else round(custo::numeric / ing_atr) end; end if;
  return null;
end $$;
revoke execute on function privado.realizado(bigint, text, text, bigint) from public, anon, authenticated;

create or replace function public.rpc_planejamento(p_ies bigint, p_coorte text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare ve_custo boolean;
begin
  perform privado.autorizar(p_ies, 'planejamento.ver');
  if p_coorte !~ '^\d{4}\.[12]$' then raise exception 'Coorte deve ter formato AAAA.1 ou AAAA.2' using errcode = '22023'; end if;
  ve_custo := privado.pode(p_ies, 'campanha.custos_ver');
  return jsonb_build_object('coorte', p_coorte,
    'pode_editar', privado.pode(p_ies, 'planejamento.editar'), 'pode_aprovar', privado.pode(p_ies, 'planejamento.aprovar'),
    'planos', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', pl.id, 'titulo', pl.titulo, 'diagnostico', pl.diagnostico, 'status', pl.status, 'versao', pl.versao,
        'orcamento_centavos', case when ve_custo then pl.orcamento_centavos end,
        'orcamento_alocado_centavos', case when ve_custo then (select coalesce(sum(k.orcamento_centavos), 0) from public.campanhas k where k.plano_id = pl.id and k.status <> 'cancelada') end,
        'gasto_centavos', case when ve_custo then (select coalesce(sum(cc.valor_centavos), 0) from public.custos_campanha cc join public.campanhas k on k.id = cc.campanha_id
                                                   where k.plano_id = pl.id and cc.estornado_em is null) end,
        'revisar_em', pl.revisar_em, 'revisao_vencida', pl.revisar_em is not null and pl.revisar_em < current_date and pl.status = 'aprovado',
        'criado_por', privado.nome_usuario(pl.criado_por), 'criado_por_mim', pl.criado_por = (select auth.uid()),
        'aprovado_por', privado.nome_usuario(pl.aprovado_por), 'aprovado_em', pl.aprovado_em,
        'objetivos', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'descricao', o.descricao, 'indicador', o.indicador,
                        'curso_id', o.curso_id, 'curso', (select c.nome || ' · ' || c.turno from public.cursos c where c.id = o.curso_id),
                        'meta', o.meta, 'prazo', o.prazo,
                        'realizado', case when o.indicador like '%centavos' and not ve_custo then null else privado.realizado(p_ies, p_coorte, o.indicador, o.curso_id) end)
                        order by o.id), '[]'::jsonb) from public.objetivos o where o.plano_id = pl.id),
        'acoes', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'objetivo_id', a.objetivo_id, 'o_que', a.o_que, 'por_que', a.por_que,
                     'onde', a.onde, 'quando', a.quando, 'quem', a.quem, 'como', a.como,
                     'quanto_centavos', case when ve_custo then a.quanto_centavos end, 'status', a.status,
                     'atrasada', a.status in ('pendente','em_andamento') and a.quando < current_date) order by a.quando, a.id), '[]'::jsonb)
                  from public.acoes a where a.plano_id = pl.id)) order by pl.id), '[]'::jsonb)
      from public.planos pl where pl.ies_id = p_ies and pl.coorte = p_coorte),
    'metodos', jsonb_build_object('realizado', 'Calculado dos registros da coorte (Bíblia §6); nunca digitado. CPL e custo por ingressante: institucionais (sem rateio por curso); N/D sem custo lançado ou sem base.'));
end $$;

-- ---------------------------------------------------------------- Concorrência (fonte verificável + revisão humana)
create or replace function public.rpc_registrar_concorrencia(p_ies bigint, p_dados jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id bigint; v_data date := (p_dados->>'coletado_em')::date;
begin
  perform privado.autorizar(p_ies, 'concorrencia.registrar');
  if v_data is null or v_data > current_date or v_data < current_date - 365 then
    raise exception 'Data de coleta obrigatória, não futura e de até 12 meses' using errcode = '22023';
  end if;
  insert into public.concorrencia(ies_id, instituicao, curso, modalidade, mensalidade_centavos, fonte_url, coletado_em, observacao, registrado_por)
  values (p_ies, trim(p_dados->>'instituicao'), trim(p_dados->>'curso'), nullif(p_dados->>'modalidade', ''), nullif(p_dados->>'mensalidade_centavos', '')::bigint,
          trim(p_dados->>'fonte_url'), v_data, nullif(trim(p_dados->>'observacao'), ''), (select auth.uid()))
  returning id into v_id;
  perform privado.auditar(p_ies, 'concorrencia.registrar', 'ies', p_ies::text, jsonb_build_object('registro_id', v_id));
  return jsonb_build_object('id', v_id);
exception when check_violation then
  raise exception 'Registro inválido: informe instituição, curso e fonte (endereço http/https verificável)' using errcode = '22023';
end $$;

create or replace function public.rpc_revisar_concorrencia(p_id bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.concorrencia;
begin
  perform privado.exigir_usuario();
  select * into r from public.concorrencia where id = p_id for update;
  if not found or not privado.ve_ies(r.ies_id) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(r.ies_id, 'concorrencia.revisar');
  if r.registrado_por = (select auth.uid()) then raise exception 'Revisão por pessoa diferente de quem registrou' using errcode = '42501'; end if;
  if r.revisado_em is not null then raise exception 'Registro já revisado' using errcode = '22023'; end if;
  update public.concorrencia set revisado_por = (select auth.uid()), revisado_em = now() where id = p_id;
  perform privado.auditar(r.ies_id, 'concorrencia.revisar', 'ies', r.ies_id::text, jsonb_build_object('registro_id', p_id));
  return jsonb_build_object('id', p_id, 'revisado', true);
end $$;

create or replace function public.rpc_concorrencia(p_ies bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.autorizar(p_ies, 'planejamento.ver');
  return (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'instituicao', r.instituicao, 'curso', r.curso, 'modalidade', r.modalidade,
            'mensalidade_centavos', r.mensalidade_centavos, 'fonte_url', r.fonte_url, 'coletado_em', r.coletado_em, 'observacao', r.observacao,
            'registrado_por', privado.nome_usuario(r.registrado_por), 'registrado_por_mim', r.registrado_por = (select auth.uid()),
            'revisado_por', privado.nome_usuario(r.revisado_por), 'revisado_em', r.revisado_em,
            'desatualizado', r.coletado_em < current_date - 180) order by r.coletado_em desc, r.id desc), '[]'::jsonb)
    from public.concorrencia r where r.ies_id = p_ies);
end $$;

-- ---------------------------------------------------------------- Campanhas e custos
create or replace function public.rpc_salvar_campanha(p_ies bigint, p_dados jsonb, p_id bigint default null, p_versao int default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare k public.campanhas; v_id bigint; v_plano bigint := nullif(p_dados->>'plano_id', '')::bigint;
begin
  perform privado.autorizar(p_ies, 'campanha.editar');
  if v_plano is not null and not exists (select 1 from public.planos where id = v_plano and ies_id = p_ies) then
    raise exception 'Plano não pertence à IES' using errcode = '22023';
  end if;
  if p_id is null then
    insert into public.campanhas(ies_id, plano_id, coorte, nome, codigo, canal, inicio, fim, orcamento_centavos, status, objetivo, criado_por)
    values (p_ies, v_plano, p_dados->>'coorte', trim(p_dados->>'nome'), lower(trim(p_dados->>'codigo')), p_dados->>'canal',
            (p_dados->>'inicio')::date, (p_dados->>'fim')::date, coalesce((p_dados->>'orcamento_centavos')::bigint, 0),
            coalesce(p_dados->>'status', 'planejada'), nullif(trim(p_dados->>'objetivo'), ''), (select auth.uid()))
    returning id into v_id;
    perform privado.auditar(p_ies, 'campanha.criar', 'campanha', v_id::text, jsonb_build_object('codigo', lower(trim(p_dados->>'codigo')), 'canal', p_dados->>'canal'));
    return jsonb_build_object('id', v_id, 'versao', 1);
  end if;
  select * into k from public.campanhas where id = p_id and ies_id = p_ies for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if k.versao <> coalesce(p_versao, -1) then perform privado.erro_http(409, '40001', 'Conflito de versão: a campanha foi alterada por outra pessoa. Recarregue.'); end if;
  if p_dados ? 'codigo' and lower(trim(p_dados->>'codigo')) <> k.codigo and exists (select 1 from public.oportunidades where campanha_id = p_id) then
    raise exception 'O código não muda depois de haver oportunidades atribuídas (preserva a atribuição)' using errcode = '22023';
  end if;
  update public.campanhas set plano_id = case when p_dados ? 'plano_id' then v_plano else plano_id end,
         nome = coalesce(trim(p_dados->>'nome'), nome), codigo = coalesce(lower(trim(p_dados->>'codigo')), codigo),
         canal = coalesce(p_dados->>'canal', canal), inicio = coalesce((p_dados->>'inicio')::date, inicio), fim = coalesce((p_dados->>'fim')::date, fim),
         orcamento_centavos = coalesce((p_dados->>'orcamento_centavos')::bigint, orcamento_centavos), status = coalesce(p_dados->>'status', status),
         objetivo = coalesce(nullif(trim(p_dados->>'objetivo'), ''), objetivo), versao = versao + 1
   where id = p_id;
  perform privado.auditar(p_ies, 'campanha.editar', 'campanha', p_id::text, jsonb_build_object('versao', k.versao + 1, 'status', p_dados->>'status'));
  return jsonb_build_object('id', p_id, 'versao', k.versao + 1);
exception
  when unique_violation then perform privado.erro_http(409, '23505', 'Código de campanha já usado nesta instituição');
  when check_violation then raise exception 'Dados da campanha inválidos (código: letras minúsculas, números e hífen; fim não anterior ao início)' using errcode = '22023';
end $$;

create or replace function public.rpc_lancar_custo(p_campanha bigint, p_data date, p_valor_centavos bigint, p_descricao text, p_chave text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare k public.campanhas; v_id bigint;
begin
  perform privado.exigir_usuario();
  select * into k from public.campanhas where id = p_campanha;
  if not found or not privado.ve_ies(k.ies_id) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(k.ies_id, 'custo.lancar');
  if p_chave is null or length(p_chave) < 8 then raise exception 'Chave de idempotência obrigatória' using errcode = '22023'; end if;
  select id into v_id from public.custos_campanha where lancado_por = (select auth.uid()) and chave = p_chave;
  if found then return jsonb_build_object('id', v_id, 'repeticao', true); end if;
  if p_valor_centavos is null or p_valor_centavos <= 0 then raise exception 'Valor deve ser positivo' using errcode = '22023'; end if;
  if p_data is null or p_data > current_date then raise exception 'Data do custo não pode ser futura' using errcode = '22023'; end if;
  insert into public.custos_campanha(ies_id, campanha_id, data, valor_centavos, descricao, lancado_por, chave)
  values (k.ies_id, p_campanha, p_data, p_valor_centavos, trim(p_descricao), (select auth.uid()), p_chave) returning id into v_id;
  perform privado.auditar(k.ies_id, 'custo.lancar', 'campanha', p_campanha::text, jsonb_build_object('custo_id', v_id, 'valor_centavos', p_valor_centavos));
  return jsonb_build_object('id', v_id, 'repeticao', false);
exception when check_violation then raise exception 'Descrição do custo obrigatória' using errcode = '22023';
end $$;

create or replace function public.rpc_estornar_custo(p_custo bigint, p_motivo text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare cc public.custos_campanha;
begin
  perform privado.exigir_usuario();
  select * into cc from public.custos_campanha where id = p_custo for update;
  if not found or not privado.ve_ies(cc.ies_id) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(cc.ies_id, 'custo.lancar');
  if cc.estornado_em is not null then raise exception 'Custo já estornado' using errcode = '22023'; end if;
  if length(coalesce(trim(p_motivo), '')) < 3 then raise exception 'Motivo do estorno obrigatório' using errcode = '22023'; end if;
  update public.custos_campanha set estornado_em = now(), estornado_por = (select auth.uid()), motivo_estorno = trim(p_motivo) where id = p_custo;
  perform privado.auditar(cc.ies_id, 'custo.estornar', 'campanha', cc.campanha_id::text, jsonb_build_object('custo_id', p_custo, 'valor_centavos', cc.valor_centavos, 'motivo', trim(p_motivo)));
  return jsonb_build_object('id', p_custo, 'estornado', true);
end $$;

-- Campanhas da coorte com resultados atribuídos. Custos só para quem tem campanha.custos_ver.
create or replace function public.rpc_campanhas(p_ies bigint, p_coorte text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare ve_custo boolean; todos constant text[] := array['gestor','reitoria','coordenador','comercial','secretaria','financeiro'];
begin
  perform privado.autorizar(p_ies, 'campanha.ver');
  if p_coorte !~ '^\d{4}\.[12]$' then raise exception 'Coorte deve ter formato AAAA.1 ou AAAA.2' using errcode = '22023'; end if;
  ve_custo := privado.pode(p_ies, 'campanha.custos_ver');
  return jsonb_build_object('coorte', p_coorte, 've_custos', ve_custo,
    'pode_editar', privado.pode(p_ies, 'campanha.editar'), 'pode_lancar_custo', privado.pode(p_ies, 'custo.lancar'),
    'integracoes', jsonb_build_object('meta_ads', 'desligada', 'google_ads', 'desligada', 'tiktok_ads', 'desligada', 'whatsapp', 'desligada'),
    'campanhas', (select coalesce(jsonb_agg(x.j order by x.inicio desc, x.id), '[]'::jsonb) from (
      select k.id, k.inicio, jsonb_build_object('id', k.id, 'nome', k.nome, 'codigo', k.codigo, 'canal', k.canal, 'inicio', k.inicio, 'fim', k.fim,
        'status', k.status, 'objetivo', k.objetivo, 'versao', k.versao, 'plano_id', k.plano_id,
        'vigente', current_date between k.inicio and k.fim,
        'leads', r.leads, 'matriculas_comerciais', r.mc, 'ingressantes', r.ing,
        'conversao', case when r.leads = 0 then null else round(r.ing::numeric / r.leads, 4) end,
        'orcamento_centavos', case when ve_custo then k.orcamento_centavos end,
        'custo_centavos', case when ve_custo then g.custo end,
        'cpl_centavos', case when ve_custo and g.custo > 0 and r.leads > 0 then round(g.custo::numeric / r.leads) end,
        'custo_ingressante_centavos', case when ve_custo and g.custo > 0 and r.ing > 0 then round(g.custo::numeric / r.ing) end,
        'custos', case when ve_custo then (select coalesce(jsonb_agg(jsonb_build_object('id', cc.id, 'data', cc.data, 'valor_centavos', cc.valor_centavos,
                    'descricao', cc.descricao, 'lancado_por', privado.nome_usuario(cc.lancado_por), 'estornado_em', cc.estornado_em,
                    'motivo_estorno', cc.motivo_estorno) order by cc.data desc, cc.id desc), '[]'::jsonb)
                  from public.custos_campanha cc where cc.campanha_id = k.id) end) as j
        from public.campanhas k
        cross join lateral (select count(*) as leads, count(*) filter (where o.matricula_comercial_em is not null) as mc,
                                   count(distinct o.pessoa_id) filter (where o.etapa = 'confirmado') as ing
                              from public.oportunidades o where o.campanha_id = k.id and privado.tem_acesso(o.ies_id, o.curso_id, todos)) r
        cross join lateral (select coalesce(sum(cc.valor_centavos), 0) as custo from public.custos_campanha cc where cc.campanha_id = k.id and cc.estornado_em is null) g
       where k.ies_id = p_ies and k.coorte = p_coorte) x),
    'atribuicao_desconhecida', (select jsonb_build_object('leads', count(*), 'ingressantes', count(distinct o.pessoa_id) filter (where o.etapa = 'confirmado'))
       from public.oportunidades o where o.ies_id = p_ies and o.coorte = p_coorte and o.campanha_id is null and privado.tem_acesso(o.ies_id, o.curso_id, todos)),
    'metodos', jsonb_build_object(
      'atribuicao', 'Origem registrada no cadastro pelo código da campanha. Sem código: atribuição desconhecida (não é distribuída entre campanhas).',
      'cpl', 'CPL = custo lançado (sem estornos) ÷ oportunidades atribuídas à campanha. N/D sem custo ou sem leads.',
      'custo_ingressante', 'Custo por ingressante = custo lançado ÷ ingressantes efetivos atribuídos. N/D sem custo ou sem ingressante.'));
end $$;

-- ---------------------------------------------------------------- Central: filtro de campanha, CPL e custo por ingressante
create or replace function public.rpc_central(p_ies bigint, p_coorte text, p_filtros jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  todos constant text[] := array['gestor','reitoria','coordenador','comercial','secretaria','financeiro'];
  f_campus bigint := nullif(p_filtros->>'campus_id', '')::bigint;
  f_curso bigint := nullif(p_filtros->>'curso_id', '')::bigint;
  f_turno text := nullif(p_filtros->>'turno', '');
  f_modal text := nullif(p_filtros->>'modalidade', '');
  f_campanha bigint := nullif(p_filtros->>'campanha_id', '')::bigint;
  v_custo bigint;
  cfg public.ies; r jsonb;
  v_min int;
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if p_coorte !~ '^\d{4}\.[12]$' then raise exception 'Coorte deve ter formato AAAA.1 ou AAAA.2' using errcode = '22023'; end if;
  select * into cfg from public.ies where id = p_ies;
  v_min := cfg.amostra_minima_forecast;
  -- Custo atribuído (institucional; sem rateio por curso): só para quem tem campanha.custos_ver e sem recorte por curso/campus/turno/modalidade.
  if privado.pode(p_ies, 'campanha.custos_ver') and f_campus is null and f_curso is null and f_turno is null and f_modal is null then
    select coalesce(sum(cc.valor_centavos), 0) into v_custo from public.custos_campanha cc join public.campanhas k on k.id = cc.campanha_id
     where k.ies_id = p_ies and k.coorte = p_coorte and cc.estornado_em is null and (f_campanha is null or k.id = f_campanha);
  end if;

  with cursos_ok as (
    select c.*, cp.nome as campus_nome from public.cursos c join public.campus cp on cp.id = c.campus_id
     where c.ies_id = p_ies and privado.tem_acesso(p_ies, c.id, todos)
       and (f_campus is null or c.campus_id = f_campus) and (f_curso is null or c.id = f_curso)
       and (f_turno is null or c.turno = f_turno) and (f_modal is null or c.modalidade = f_modal)
  ), ops as (
    select o.*, c.nome as curso, c.turno, c.modalidade, c.mensalidade_centavos, c.campus_nome, p.origem,
           coalesce(u.nome, 'Sem responsável') as atendente,
           greatest(
             case when o.etapa in ('perdido','cancelado') then 0 else privado.ordem_etapa(o.etapa) end,
             case when o.confirmada_em is not null then 6 when o.matricula_comercial_em is not null then 5 else 0 end,
             coalesce((select max(greatest(privado.ordem_etapa(a.dados->>'de'), privado.ordem_etapa(a.dados->>'para')))
                         from public.auditoria a where a.entidade = 'oportunidade' and a.entidade_id = o.id::text
                          and a.acao = 'oportunidade.etapa'), 1)) as alcance,
           (select x.valor_final_centavos from public.propostas x where x.oportunidade_id = o.id and x.status = 'aceita' order by x.id desc limit 1) as valor_aceito
      from public.oportunidades o join cursos_ok c on c.id = o.curso_id join public.pessoas p on p.id = o.pessoa_id
      left join public.usuarios u on u.id = o.responsavel_id
     where o.ies_id = p_ies and o.coorte = p_coorte and (f_campanha is null or o.campanha_id = f_campanha)
  ), tot as (
    select count(*) as oportunidades,
           count(*) filter (where matricula_comercial_em is not null) as matriculas_comerciais,
           count(distinct pessoa_id) filter (where etapa = 'confirmado') as ingressantes,
           count(*) filter (where etapa = 'perdido') as perdidos,
           count(*) filter (where etapa = 'cancelado') as cancelamentos,
           count(*) filter (where etapa not in ('confirmado','perdido','cancelado')) as abertas,
           coalesce(sum(coalesce(valor_aceito, mensalidade_centavos)) filter (where etapa = 'confirmado'), 0) as receita_ingressos,
           coalesce(sum(coalesce(valor_aceito, mensalidade_centavos)) filter (where etapa not in ('confirmado','perdido','cancelado')), 0) as receita_pipeline_bruta,
           -- Bíblia §6 (D2): receita potencial = soma das mensalidades ofertadas válidas (proposta ativa ou aceita, dentro da validade)
           (select coalesce(sum(x.valor_final_centavos), 0) from public.propostas x join ops o2 on o2.id = x.oportunidade_id
             where o2.etapa not in ('perdido','cancelado')
               and (x.status = 'aceita' or (x.status in ('aprovada','pendente_aprovacao') and x.validade >= now()))) as receita_ofertada,
           (select count(*) from public.propostas x join ops o2 on o2.id = x.oportunidade_id
             where o2.etapa not in ('perdido','cancelado')
               and (x.status = 'aceita' or (x.status in ('aprovada','pendente_aprovacao') and x.validade >= now()))) as n_ofertas
      from ops
  ), metas_f as (
    select sum(m.meta) as meta, count(*) as n from public.metas m join cursos_ok c on c.id = m.curso_id
     where m.ies_id = p_ies and m.coorte = p_coorte
  ), base as (
    select t.*, mf.meta, mf.n as n_metas,
           (t.ingressantes + t.perdidos + t.cancelamentos) as decididas,
           case when (t.ingressantes + t.perdidos + t.cancelamentos) = 0 then null
                else t.ingressantes::numeric / (t.ingressantes + t.perdidos + t.cancelamentos) end as taxa
      from tot t, metas_f mf
  )
  select jsonb_build_object(
    'coorte', p_coorte, 'filtros', p_filtros,
    'cobertura', case when privado.tem_acesso_ies(p_ies, todos) and f_campus is null and f_curso is null and f_turno is null and f_modal is null and f_campanha is null then 'ies' else 'recorte' end,
    'totais', (select jsonb_build_object(
        'oportunidades', b.oportunidades, 'matriculas_comerciais', b.matriculas_comerciais, 'ingressantes', b.ingressantes,
        'perdidos', b.perdidos, 'cancelamentos', b.cancelamentos, 'oportunidades_abertas', b.abertas,
        -- Bíblia §6 (D3): conversão = ingressantes efetivos ÷ oportunidades da mesma coorte
        'conversao', case when b.oportunidades = 0 then null else round(b.ingressantes::numeric / b.oportunidades, 4) end,
        'meta', case when b.n_metas = 0 then null else b.meta end,
        'atingimento', case when b.n_metas = 0 or b.meta = 0 then null else round(b.ingressantes::numeric / b.meta, 4) end,
        'meta_restante', case when b.n_metas = 0 then null else greatest(b.meta - b.ingressantes, 0) end,
        'amostra', b.oportunidades, 'amostra_minima', v_min,
        -- Bíblia §6 (D1): ceil(meta restante ÷ conversão observada NÃO arredondada), em aritmética inteira exata:
        -- meta_restante ÷ (ingressantes ÷ oportunidades) = meta_restante × oportunidades ÷ ingressantes
        'oportunidades_adicionais_projetadas', case
          when b.n_metas = 0 then null
          when greatest(b.meta - b.ingressantes, 0) = 0 then 0
          when b.ingressantes = 0 or b.oportunidades < v_min then null
          else (greatest(b.meta - b.ingressantes, 0)::bigint * b.oportunidades + b.ingressantes - 1) / b.ingressantes end,
        'forecast_motivo', case
          when b.n_metas = 0 then 'Sem meta cadastrada no recorte.'
          when greatest(b.meta - b.ingressantes, 0) = 0 then 'Meta cumprida: necessidade adicional zero.'
          when b.ingressantes = 0 then 'Conversão observada zero: projeção indisponível.'
          when b.oportunidades < v_min then format('Amostra insuficiente: %s oportunidades (mínimo configurado: %s).', b.oportunidades, v_min)
          else null end,
        'cenario_pipeline', jsonb_build_object(
          'rotulo', 'Cenário complementar (não é o indicador oficial)',
          'taxa_conversao_decididas', round(b.taxa, 4),
          'ingressos_esperados_pipeline', case when b.taxa is null then null else round(b.abertas * b.taxa, 1) end,
          'projecao_ingressos', case when b.taxa is null then null else round(b.ingressantes + b.abertas * b.taxa, 1) end,
          'novas_oportunidades_necessarias', case when b.n_metas = 0 or b.taxa is null or b.taxa = 0 then null
            else greatest(ceil((b.meta - b.ingressantes - b.abertas * b.taxa) / b.taxa), 0) end),
        'receita_mensal_ingressantes_centavos', b.receita_ingressos,
        'receita_mensal_potencial_ofertada_centavos', b.receita_ofertada,
        'propostas_validas', b.n_ofertas,
        'custo_atribuido_centavos', case when v_custo > 0 then v_custo end,
        'custo_por_lead_centavos', case when v_custo > 0 and (select count(*) from ops where campanha_id is not null) > 0
          then round(v_custo::numeric / (select count(*) from ops where campanha_id is not null)) end,
        'custo_por_matricula_centavos', case when v_custo > 0 and (select count(distinct pessoa_id) from ops where campanha_id is not null and etapa = 'confirmado') > 0
          then round(v_custo::numeric / (select count(distinct pessoa_id) from ops where campanha_id is not null and etapa = 'confirmado')) end,
        'custo_motivo', case
          when v_custo is null and not privado.pode(p_ies, 'campanha.custos_ver') then 'Custos visíveis apenas para gestão institucional e financeiro.'
          when v_custo is null then 'Custo é institucional e não é rateado por curso, campus, turno ou modalidade: remova esses filtros.'
          when v_custo = 0 then 'Sem custo lançado nas campanhas da coorte.'
          when (select count(*) from ops where campanha_id is not null) = 0 then 'Nenhuma oportunidade atribuída a campanha.'
          when (select count(distinct pessoa_id) from ops where campanha_id is not null and etapa = 'confirmado') = 0 then 'Sem ingressante atribuído a campanha: custo por ingressante indisponível.'
          else null end,
        'leads_atribuidos', (select count(*) from ops where campanha_id is not null),
        'leads_atribuicao_desconhecida', (select count(*) from ops where campanha_id is null),
        'metodos', jsonb_build_object(
          'conversao', 'Ingressantes efetivos (pessoas distintas) ÷ oportunidades da mesma coorte (Bíblia §6).',
          'projecao', 'Oportunidades adicionais = ⌈meta restante ÷ conversão observada⌉, com a conversão não arredondada (Bíblia §6). N/D com conversão zero ou amostra abaixo do mínimo configurado; zero com a meta cumprida.',
          'cenario', 'Cenário complementar: taxa sobre oportunidades decididas (ingresso, perda ou cancelamento) aplicada ao pipeline aberto. Não substitui o indicador oficial.',
          'custo', 'CPL = custo lançado (sem estornos) nas campanhas da coorte ÷ oportunidades atribuídas a campanhas. Custo por matrícula = mesmo custo ÷ ingressantes efetivos atribuídos (conceito: ingresso efetivo). Leads sem código de campanha ficam como atribuição desconhecida.',
          'receita', 'Receita potencial = soma das mensalidades ofertadas válidas (propostas ativas dentro da validade ou aceitas), valor mensal, natureza de projeção (Bíblia §6). Ingressantes: mensalidade da proposta aceita ou mensalidade cheia do curso.',
          'funil', 'Oportunidades que ALCANÇARAM cada etapa, reconstruído pelo histórico auditado. Quem confirmou e depois cancelou conta no alcance do ingresso, mas não entre os ingressantes efetivos.'))
      from base b),
    'funil', (select coalesce(jsonb_agg(jsonb_build_object('etapa', e.etapa, 'quantidade', e.q,
                'conversao_da_anterior', case when e.ant is null or e.ant = 0 then null else round(e.q::numeric / e.ant, 4) end) order by e.k), '[]'::jsonb)
              from (select k, etapa, q, lag(q) over (order by k) as ant from (
                      select s.k, s.etapa, (select count(*) from ops where alcance >= s.k) as q
                        from (values (1,'novo'),(2,'contato'),(3,'inscrito'),(4,'pre_matricula'),(5,'matricula_comercial'),(6,'confirmado')) s(k, etapa)) z) e),
    'evolucao', (select coalesce(jsonb_agg(jsonb_build_object('semana', w.semana, 'oportunidades', w.ops, 'matriculas_comerciais', w.mc, 'ingressantes', w.ing) order by w.semana), '[]'::jsonb)
                 from (select to_char(sem, 'YYYY-MM-DD') as semana,
                              (select count(*) from ops where date_trunc('week', criado_em) = sem) as ops,
                              (select count(*) from ops where date_trunc('week', matricula_comercial_em) = sem) as mc,
                              (select count(*) from ops where date_trunc('week', confirmada_em) = sem) as ing
                         from generate_series(date_trunc('week', now()) - interval '11 weeks', date_trunc('week', now()), interval '1 week') sem) w),
    'por_origem', (select coalesce(jsonb_agg(jsonb_build_object('chave', x.chave, 'oportunidades', x.n, 'ingressantes', x.ing,
                     'conversao', case when x.n = 0 then null else round(x.ing::numeric / x.n, 4) end) order by x.n desc), '[]'::jsonb)
                   from (select origem as chave, count(*) as n, count(distinct pessoa_id) filter (where etapa = 'confirmado') as ing from ops group by 1) x),
    'por_campanha', (select coalesce(jsonb_agg(jsonb_build_object('chave', x.chave, 'oportunidades', x.n, 'ingressantes', x.ing,
                     'conversao', case when x.n = 0 then null else round(x.ing::numeric / x.n, 4) end) order by x.n desc), '[]'::jsonb)
                   from (select coalesce(k.nome, 'Atribuição desconhecida') as chave, count(*) as n, count(distinct o.pessoa_id) filter (where o.etapa = 'confirmado') as ing
                           from ops o left join public.campanhas k on k.id = o.campanha_id group by 1) x),
    'por_curso', (select coalesce(jsonb_agg(jsonb_build_object('chave', x.chave, 'curso_id', x.curso_id, 'oportunidades', x.n, 'ingressantes', x.ing,
                    'matriculas_comerciais', x.mc, 'meta', x.meta,
                    'atingimento', case when x.meta is null or x.meta = 0 then null else round(x.ing::numeric / x.meta, 4) end,
                    'conversao', case when x.n = 0 then null else round(x.ing::numeric / x.n, 4) end) order by x.chave), '[]'::jsonb)
                  from (select c.nome || ' · ' || c.turno as chave, c.id as curso_id, count(o.id) as n,
                               count(distinct o.pessoa_id) filter (where o.etapa = 'confirmado') as ing,
                               count(o.id) filter (where o.matricula_comercial_em is not null) as mc,
                               (select m.meta from public.metas m where m.ies_id = p_ies and m.curso_id = c.id and m.coorte = p_coorte) as meta
                          from cursos_ok c left join ops o on o.curso_id = c.id group by c.id, c.nome, c.turno) x),
    'por_turno', (select coalesce(jsonb_agg(jsonb_build_object('chave', turno, 'oportunidades', n, 'ingressantes', ing) order by turno), '[]'::jsonb)
                  from (select turno, count(*) n, count(distinct pessoa_id) filter (where etapa = 'confirmado') ing from ops group by 1) x),
    'por_modalidade', (select coalesce(jsonb_agg(jsonb_build_object('chave', modalidade, 'oportunidades', n, 'ingressantes', ing) order by modalidade), '[]'::jsonb)
                       from (select modalidade, count(*) n, count(distinct pessoa_id) filter (where etapa = 'confirmado') ing from ops group by 1) x),
    'por_atendente', (select coalesce(jsonb_agg(jsonb_build_object('chave', atendente, 'oportunidades', n, 'matriculas_comerciais', mc, 'ingressantes', ing,
                        'conversao', case when n = 0 then null else round(ing::numeric / n, 4) end) order by n desc), '[]'::jsonb)
                      from (select atendente, count(*) n, count(*) filter (where matricula_comercial_em is not null) mc,
                                   count(distinct pessoa_id) filter (where etapa = 'confirmado') ing from ops group by 1) x),
    'alertas', (select jsonb_agg(a order by (a->>'prioridade')::int, a->>'tipo') from (
        select jsonb_build_object('tipo', 'sla_vencido', 'prioridade', 1, 'titulo', 'Tarefas com SLA vencido',
               'quantidade', count(*), 'acao', 'Priorizar contato na fila do MAIM') as a
          from public.tarefas t join ops o on o.id = t.oportunidade_id where t.status = 'aberta' and t.vence_em < now()
        union all
        select jsonb_build_object('tipo', 'pendencia_validacao', 'prioridade', 1, 'titulo', 'Matrículas comerciais aguardando validação há mais de 48h',
               'quantidade', count(*), 'acao', 'Secretaria e financeiro: concluir validações em Conversão e Matrículas')
          from ops where etapa = 'matricula_comercial' and matricula_comercial_em < now() - interval '48 hours'
        union all
        select jsonb_build_object('tipo', 'proposta_aprovacao', 'prioridade', 2, 'titulo', 'Propostas aguardando aprovação do gestor',
               'quantidade', count(*), 'acao', 'Decidir em Conversão e Matrículas → Propostas')
          from public.propostas x join ops o on o.id = x.oportunidade_id where x.status = 'pendente_aprovacao'
        union all
        select jsonb_build_object('tipo', 'proposta_vencendo', 'prioridade', 2, 'titulo', 'Propostas aprovadas que vencem em até 48h',
               'quantidade', count(*), 'acao', 'Contatar o candidato para registrar o aceite')
          from public.propostas x join ops o on o.id = x.oportunidade_id
         where x.status = 'aprovada' and x.validade between now() and now() + interval '48 hours'
        union all
        select jsonb_build_object('tipo', 'parada', 'prioridade', 2, 'titulo', 'Oportunidades paradas sem tarefa aberta',
               'quantidade', count(*), 'acao', 'Executar o ciclo MAIM ou registrar contato')
          from ops o where o.etapa in ('contato','inscrito','pre_matricula')
           and o.atualizado_em < now() - make_interval(days => cfg.dias_sem_contato)
           and not exists (select 1 from public.tarefas t where t.oportunidade_id = o.id and t.status = 'aberta')
        union all
        select jsonb_build_object('tipo', 'sem_responsavel', 'prioridade', 3, 'titulo', 'Oportunidades abertas sem responsável',
               'quantidade', count(*), 'acao', 'Rever capacidade dos atendentes e redistribuir')
          from ops where etapa not in ('confirmado','perdido','cancelado') and responsavel_id is null
      ) z where (a->>'quantidade')::int > 0),
    'filtros_disponiveis', (select jsonb_build_object(
        'campi', (select coalesce(jsonb_agg(distinct jsonb_build_object('id', cp.id, 'nome', cp.nome)), '[]'::jsonb)
                    from public.cursos c join public.campus cp on cp.id = c.campus_id where c.ies_id = p_ies and privado.tem_acesso(p_ies, c.id, todos)),
        'turnos', (select coalesce(jsonb_agg(distinct c.turno), '[]'::jsonb) from public.cursos c where c.ies_id = p_ies and privado.tem_acesso(p_ies, c.id, todos)),
        'modalidades', (select coalesce(jsonb_agg(distinct c.modalidade), '[]'::jsonb) from public.cursos c where c.ies_id = p_ies and privado.tem_acesso(p_ies, c.id, todos)),
        'campanhas', (select coalesce(jsonb_agg(jsonb_build_object('id', k.id, 'nome', k.nome) order by k.nome), '[]'::jsonb) from public.campanhas k where k.ies_id = p_ies and k.coorte = p_coorte)))
  ) into r;
  return r;
end $$;

-- ---------------------------------------------------------------- cadastro com atribuição de campanha
create or replace function public.rpc_criar_oportunidade(p_ies bigint, p_dados jsonb, p_chave text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_curso bigint := (p_dados->>'curso_id')::bigint;
  v_email text := nullif(lower(trim(p_dados->>'email')), '');
  v_tel text := nullif(regexp_replace(coalesce(p_dados->>'telefone', ''), '\D', '', 'g'), '');
  v_pessoa public.pessoas; v_op public.oportunidades; v_resp uuid; v_canal text; v_sla int; r jsonb; v_camp bigint;
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
  -- Atribuição de origem pelo código da campanha (Bíblia §7). Código informado e inexistente é recusado: não se perde atribuição em silêncio.
  if nullif(trim(coalesce(p_dados->>'campanha', '')), '') is not null then
    select id into v_camp from public.campanhas where ies_id = p_ies and codigo = lower(trim(p_dados->>'campanha')) and status <> 'cancelada';
    if v_camp is null then raise exception 'Campanha não encontrada: %', p_dados->>'campanha' using errcode = '22023'; end if;
  end if;

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
  insert into public.oportunidades(ies_id, curso_id, pessoa_id, forma_ingresso, coorte, responsavel_id, campanha_id)
  values (p_ies, v_curso, v_pessoa.id, p_dados->>'forma_ingresso', p_dados->>'coorte', v_resp, v_camp) returning * into v_op;
  v_canal := case when not v_pessoa.optout_whatsapp and v_pessoa.telefone is not null then 'whatsapp'
                  when not v_pessoa.optout_email and v_pessoa.email is not null then 'email'
                  when not v_pessoa.optout_telefone and v_pessoa.telefone is not null then 'telefone' end;
  if v_canal is not null then
    select sla_horas into v_sla from public.ies where id = p_ies;
    insert into public.tarefas(ies_id, oportunidade_id, tipo, canal, responsavel_id, vence_em)
    values (p_ies, v_op.id, 'primeiro_contato', v_canal, v_resp, now() + make_interval(hours => v_sla));
  end if;
  perform privado.auditar(p_ies, 'oportunidade.criar', 'oportunidade', v_op.id::text,
    jsonb_build_object('curso_id', v_curso, 'forma_ingresso', v_op.forma_ingresso, 'coorte', v_op.coorte, 'origem', v_pessoa.origem, 'responsavel_id', v_resp, 'campanha_id', v_camp));
  return privado.idem_gravar(p_chave, 'criar_oportunidade', jsonb_build_object('id', v_op.id, 'duplicada', false, 'versao', 1, 'etapa', 'novo'));
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.rpc_salvar_plano(bigint, jsonb, bigint, int), public.rpc_plano_status(bigint, text, text), public.rpc_salvar_objetivo(bigint, jsonb, bigint),
  public.rpc_salvar_acao(bigint, jsonb, bigint), public.rpc_planejamento(bigint, text), public.rpc_registrar_concorrencia(bigint, jsonb),
  public.rpc_revisar_concorrencia(bigint), public.rpc_concorrencia(bigint), public.rpc_salvar_campanha(bigint, jsonb, bigint, int),
  public.rpc_lancar_custo(bigint, date, bigint, text, text), public.rpc_estornar_custo(bigint, text), public.rpc_campanhas(bigint, text),
  public.rpc_central(bigint, text, jsonb), public.rpc_criar_oportunidade(bigint, jsonb, text)
to authenticated;

-- ===================== supabase/migrations/20261125000013_funis.sql
-- Matrícula 360° — migração 13: Funis Comerciais configuráveis (E05). Bíblia v0.2 §2 e §4.
--   * Funil por modalidade e/ou forma de ingresso; funil padrão por IES replica o funil atual (mapeamento explícito).
--   * Versões: rascunho → publicada → arquivada. Versão publicada é imutável; a oportunidade fica presa à versão
--     em que nasceu (histórico não é sobrescrito).
--   * Etapas configuráveis detalham as etapas oficiais (etapa_base). Transições entre etapas oficiais continuam
--     validadas por rpc_mover_etapa; a subetapa só avança dentro da mesma etapa oficial.
--   * Roteiro (script) e SLA por etapa; cadência de contatos como guia (nenhum envio); metas de conversão por forma.
-- Idempotente.

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('funil.ver',     'Funis Comerciais', 'Ver funis, roteiros, cadências e metas por forma de ingresso', array['gestor','reitoria','coordenador','comercial'], 'curso', 'rpc_funis'),
  ('funil.editar',  'Funis Comerciais', 'Criar funil e editar versão em rascunho',                      array['gestor'], 'ies', 'rpc_salvar_versao'),
  ('funil.publicar','Funis Comerciais', 'Publicar versão (a anterior é arquivada)',                    array['gestor'], 'ies', 'rpc_publicar_versao'),
  ('crm.subetapa',  'CRM Educacional',  'Avançar subetapa dentro da etapa oficial',                    array['gestor','comercial'], 'curso', 'rpc_mover_subetapa')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

create table if not exists public.funis (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  nome text not null check (length(nome) between 3 and 80),
  modalidade text check (modalidade in ('presencial','ead','semipresencial')),
  formas text[] check (formas is null or (cardinality(formas) > 0 and formas <@ array['vestibular','enem','transferencia','segunda_graduacao','reingresso','indicacao','convenio','visita_escolar','evento','pos_graduacao'])),
  padrao boolean not null default false,
  ativo boolean not null default true,
  criado_por uuid references public.usuarios(id),
  criado_em timestamptz not null default now(),
  unique (ies_id, nome),
  check (not padrao or (modalidade is null and formas is null))
);
create unique index if not exists funil_padrao_unico on public.funis(ies_id) where padrao;

create table if not exists public.funil_versoes (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  funil_id bigint not null references public.funis(id),
  versao int not null,
  status text not null default 'rascunho' check (status in ('rascunho','publicada','arquivada')),
  notas text check (length(notas) <= 500),
  criado_por uuid references public.usuarios(id),
  criado_em timestamptz not null default now(),
  publicada_por uuid references public.usuarios(id),
  publicada_em timestamptz,
  unique (funil_id, versao)
);
create unique index if not exists funil_uma_publicada on public.funil_versoes(funil_id) where status = 'publicada';
create unique index if not exists funil_um_rascunho on public.funil_versoes(funil_id) where status = 'rascunho';

create table if not exists public.funil_etapas (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  versao_id bigint not null references public.funil_versoes(id),
  ordem int not null check (ordem between 1 and 40),
  nome text not null check (length(nome) between 2 and 60),
  etapa_base text not null check (etapa_base in ('novo','contato','inscrito','pre_matricula','matricula_comercial')),
  sla_horas int check (sla_horas between 1 and 720),
  roteiro text check (length(roteiro) <= 3000),
  unique (versao_id, ordem),
  unique (versao_id, nome)
);
create table if not exists public.funil_cadencias (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  versao_id bigint not null references public.funil_versoes(id),
  etapa_ordem int not null,
  passo int not null check (passo between 1 and 20),
  dia int not null check (dia between 0 and 90),
  canal text not null check (canal in ('telefone','whatsapp','email','presencial')),
  descricao text not null check (length(descricao) between 3 and 300),
  unique (versao_id, etapa_ordem, passo)
);
create table if not exists public.funil_metas (
  ies_id bigint not null references public.ies(id),
  versao_id bigint not null references public.funil_versoes(id),
  forma_ingresso text not null check (forma_ingresso in ('vestibular','enem','transferencia','segunda_graduacao','reingresso','indicacao','convenio','visita_escolar','evento','pos_graduacao')),
  conversao_meta numeric(5,4) not null check (conversao_meta > 0 and conversao_meta <= 1),
  primary key (versao_id, forma_ingresso)
);
alter table public.oportunidades add column if not exists funil_versao_id bigint references public.funil_versoes(id);
alter table public.oportunidades add column if not exists funil_etapa_ordem int;

create index if not exists funis_ies on public.funis(ies_id);
create index if not exists funis_criado on public.funis(criado_por);
create index if not exists funil_versoes_funil on public.funil_versoes(funil_id);
create index if not exists funil_versoes_ies on public.funil_versoes(ies_id);
create index if not exists funil_versoes_criado on public.funil_versoes(criado_por);
create index if not exists funil_versoes_publicada on public.funil_versoes(publicada_por);
create index if not exists funil_etapas_ies on public.funil_etapas(ies_id);
create index if not exists funil_cadencias_versao on public.funil_cadencias(versao_id);
create index if not exists funil_cadencias_ies on public.funil_cadencias(ies_id);
create index if not exists funil_metas_ies on public.funil_metas(ies_id);
create index if not exists oportunidades_funil on public.oportunidades(funil_versao_id);

alter table public.funis enable row level security;
alter table public.funil_versoes enable row level security;
alter table public.funil_etapas enable row level security;
alter table public.funil_cadencias enable row level security;
alter table public.funil_metas enable row level security;
revoke all on public.funis, public.funil_versoes, public.funil_etapas, public.funil_cadencias, public.funil_metas from anon, authenticated;

-- ---------------------------------------------------------------- funil padrão (replica o funil atual)
create or replace function privado.criar_funil_padrao(p_ies bigint) returns bigint
language plpgsql security definer set search_path = '' as $$
declare f bigint; v bigint; sla int;
begin
  select id into f from public.funis where ies_id = p_ies and padrao;
  if found then return (select id from public.funil_versoes where funil_id = f and status = 'publicada'); end if;
  select sla_horas into sla from public.ies where id = p_ies;
  insert into public.funis(ies_id, nome, padrao) values (p_ies, 'Funil padrão institucional', true) returning id into f;
  insert into public.funil_versoes(ies_id, funil_id, versao, status, notas, publicada_em)
  values (p_ies, f, 1, 'publicada', 'Mapeamento 1:1 das etapas oficiais existentes (migração 13).', now()) returning id into v;
  insert into public.funil_etapas(ies_id, versao_id, ordem, nome, etapa_base, sla_horas) values
    (p_ies, v, 1, 'Novo lead', 'novo', sla), (p_ies, v, 2, 'Contato', 'contato', null), (p_ies, v, 3, 'Inscrito', 'inscrito', null),
    (p_ies, v, 4, 'Pré-matrícula', 'pre_matricula', null), (p_ies, v, 5, 'Matrícula comercial', 'matricula_comercial', null);
  return v;
end $$;
revoke execute on function privado.criar_funil_padrao(bigint) from public, anon, authenticated;

create or replace function privado.ies_funil_padrao() returns trigger
language plpgsql security definer set search_path = '' as $$
begin perform privado.criar_funil_padrao(new.id); return new; end $$;
revoke execute on function privado.ies_funil_padrao() from public, anon, authenticated;
drop trigger if exists ies_cria_funil on public.ies;
create trigger ies_cria_funil after insert on public.ies for each row execute function privado.ies_funil_padrao();

-- Versão aplicável a uma nova oportunidade: mais específica primeiro (modalidade+forma > forma > modalidade > padrão);
-- empate decidido pelo menor id do funil (estável e documentado).
create or replace function privado.versao_aplicavel(p_ies bigint, p_curso bigint, p_forma text) returns bigint
language sql stable security definer set search_path = '' as $$
  select v.id from public.funis f
    join public.funil_versoes v on v.funil_id = f.id and v.status = 'publicada'
    join public.cursos c on c.id = p_curso
   where f.ies_id = p_ies and f.ativo
     and (f.modalidade is null or f.modalidade = c.modalidade)
     and (f.formas is null or p_forma = any (f.formas))
   order by (f.modalidade is not null)::int + 2 * (f.formas is not null)::int desc, f.padrao, f.id
   limit 1;
$$;
revoke execute on function privado.versao_aplicavel(bigint, bigint, text) from public, anon, authenticated;

-- Fixa a versão no nascimento e posiciona a subetapa na primeira etapa configurada da etapa oficial.
create or replace function privado.oportunidade_funil() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' and new.funil_versao_id is null then
    new.funil_versao_id := privado.versao_aplicavel(new.ies_id, new.curso_id, new.forma_ingresso);
  end if;
  if tg_op = 'INSERT' or new.etapa is distinct from old.etapa then
    new.funil_etapa_ordem := (select min(e.ordem) from public.funil_etapas e where e.versao_id = new.funil_versao_id and e.etapa_base = new.etapa);
  end if;
  return new;
end $$;
revoke execute on function privado.oportunidade_funil() from public, anon, authenticated;
drop trigger if exists oportunidade_funil on public.oportunidades;
create trigger oportunidade_funil before insert or update of etapa on public.oportunidades
  for each row execute function privado.oportunidade_funil();

-- Mapeamento explícito do legado: cada IES ganha o funil padrão; cada oportunidade existente fica na versão 1,
-- na subetapa equivalente à sua etapa oficial (etapas encerradas ficam sem subetapa).
select privado.criar_funil_padrao(id) from public.ies;
update public.oportunidades o set funil_versao_id = v.id,
       funil_etapa_ordem = (select min(e.ordem) from public.funil_etapas e where e.versao_id = v.id and e.etapa_base = o.etapa)
  from public.funis f join public.funil_versoes v on v.funil_id = f.id and v.versao = 1
 where f.ies_id = o.ies_id and f.padrao and o.funil_versao_id is null;

-- ---------------------------------------------------------------- leitura
create or replace function privado.versao_json(p_versao bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', v.id, 'versao', v.versao, 'status', v.status, 'notas', v.notas,
    'criado_por', privado.nome_usuario(v.criado_por), 'criado_em', v.criado_em,
    'publicada_por', privado.nome_usuario(v.publicada_por), 'publicada_em', v.publicada_em,
    'oportunidades', (select count(*) from public.oportunidades o where o.funil_versao_id = v.id),
    'etapas', (select coalesce(jsonb_agg(jsonb_build_object('ordem', e.ordem, 'nome', e.nome, 'etapa_base', e.etapa_base,
                 'sla_horas', e.sla_horas, 'roteiro', e.roteiro) order by e.ordem), '[]'::jsonb) from public.funil_etapas e where e.versao_id = v.id),
    'cadencias', (select coalesce(jsonb_agg(jsonb_build_object('etapa_ordem', c.etapa_ordem, 'passo', c.passo, 'dia', c.dia, 'canal', c.canal,
                 'descricao', c.descricao) order by c.etapa_ordem, c.passo), '[]'::jsonb) from public.funil_cadencias c where c.versao_id = v.id),
    'metas', (select coalesce(jsonb_agg(jsonb_build_object('forma_ingresso', m.forma_ingresso, 'conversao_meta', m.conversao_meta) order by m.forma_ingresso), '[]'::jsonb)
              from public.funil_metas m where m.versao_id = v.id))
    from public.funil_versoes v where v.id = p_versao;
$$;
revoke execute on function privado.versao_json(bigint) from public, anon, authenticated;

create or replace function public.rpc_funis(p_ies bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare todos constant text[] := array['gestor','reitoria','coordenador','comercial','secretaria','financeiro'];
begin
  perform privado.autorizar(p_ies, 'funil.ver');
  return jsonb_build_object(
    'pode_editar', privado.pode(p_ies, 'funil.editar'), 'pode_publicar', privado.pode(p_ies, 'funil.publicar'),
    'regra_selecao', 'Nova oportunidade recebe a versão publicada do funil mais específico: modalidade e forma > forma > modalidade > funil padrão; empate pelo funil mais antigo. A versão fica fixa na oportunidade.',
    'funis', (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'nome', f.nome, 'modalidade', f.modalidade, 'formas', f.formas,
        'padrao', f.padrao, 'ativo', f.ativo,
        'versoes', (select coalesce(jsonb_agg(privado.versao_json(v.id) order by v.versao desc), '[]'::jsonb) from public.funil_versoes v where v.funil_id = f.id),
        -- Desempenho por forma de ingresso nas oportunidades do funil (todas as versões), contra a meta da versão publicada.
        'desempenho', (select coalesce(jsonb_agg(jsonb_build_object('forma_ingresso', x.forma, 'oportunidades', x.n, 'ingressantes', x.ing,
                         'conversao', case when x.n = 0 then null else round(x.ing::numeric / x.n, 4) end,
                         'meta', (select m.conversao_meta from public.funil_metas m join public.funil_versoes pv on pv.id = m.versao_id
                                   where pv.funil_id = f.id and pv.status = 'publicada' and m.forma_ingresso = x.forma)) order by x.n desc), '[]'::jsonb)
                       from (select o.forma_ingresso as forma, count(*) as n, count(distinct o.pessoa_id) filter (where o.etapa = 'confirmado') as ing
                               from public.oportunidades o join public.funil_versoes v on v.id = o.funil_versao_id
                              where v.funil_id = f.id and privado.tem_acesso(o.ies_id, o.curso_id, todos) group by 1) x))
        order by f.padrao desc, f.nome), '[]'::jsonb)
      from public.funis f where f.ies_id = p_ies));
end $$;

-- Funil da oportunidade: etapa atual, roteiro e cadência, e as subetapas disponíveis dentro da etapa oficial.
create or replace function public.rpc_funil_oportunidade(p_op bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare o public.oportunidades; f public.funis; v public.funil_versoes;
begin
  perform privado.exigir_usuario();
  select * into o from public.oportunidades where id = p_op;
  if not found or not privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro']) then
    perform privado.erro_http(404, 'P0002', 'Não encontrado');
  end if;
  select * into v from public.funil_versoes where id = o.funil_versao_id;
  if not found then return jsonb_build_object('funil', null); end if;
  select * into f from public.funis where id = v.funil_id;
  return jsonb_build_object('funil', f.nome, 'versao', v.versao, 'versao_status', v.status, 'etapa_ordem', o.funil_etapa_ordem, 'versao_op', o.versao,
    'atual', (select jsonb_build_object('ordem', e.ordem, 'nome', e.nome, 'sla_horas', e.sla_horas, 'roteiro', e.roteiro)
                from public.funil_etapas e where e.versao_id = v.id and e.ordem = o.funil_etapa_ordem),
    'subetapas', (select coalesce(jsonb_agg(jsonb_build_object('ordem', e.ordem, 'nome', e.nome) order by e.ordem), '[]'::jsonb)
                    from public.funil_etapas e where e.versao_id = v.id and e.etapa_base = o.etapa),
    'cadencia', (select coalesce(jsonb_agg(jsonb_build_object('passo', c.passo, 'dia', c.dia, 'canal', c.canal, 'descricao', c.descricao) order by c.passo), '[]'::jsonb)
                   from public.funil_cadencias c where c.versao_id = v.id and c.etapa_ordem = o.funil_etapa_ordem),
    'meta_conversao_forma', (select m.conversao_meta from public.funil_metas m where m.versao_id = v.id and m.forma_ingresso = o.forma_ingresso));
end $$;

-- ---------------------------------------------------------------- escrita
create or replace function public.rpc_salvar_funil(p_ies bigint, p_dados jsonb, p_id bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare f bigint; v bigint; base bigint; formas text[];
begin
  perform privado.autorizar(p_ies, 'funil.editar');
  formas := case when jsonb_typeof(p_dados->'formas') = 'array' and jsonb_array_length(p_dados->'formas') > 0
                 then array(select jsonb_array_elements_text(p_dados->'formas')) end;
  if p_id is null then
    if nullif(p_dados->>'modalidade', '') is null and formas is null then
      raise exception 'Funil específico exige modalidade ou forma de ingresso (o funil padrão já cobre o restante)' using errcode = '22023';
    end if;
    insert into public.funis(ies_id, nome, modalidade, formas, criado_por)
    values (p_ies, trim(p_dados->>'nome'), nullif(p_dados->>'modalidade', ''), formas, (select auth.uid())) returning id into f;
    -- Versão 1 em rascunho, copiada do funil padrão publicado (ponto de partida editável).
    insert into public.funil_versoes(ies_id, funil_id, versao, criado_por) values (p_ies, f, 1, (select auth.uid())) returning id into v;
    select pv.id into base from public.funis pf join public.funil_versoes pv on pv.funil_id = pf.id and pv.status = 'publicada' where pf.ies_id = p_ies and pf.padrao;
    insert into public.funil_etapas(ies_id, versao_id, ordem, nome, etapa_base, sla_horas, roteiro)
      select p_ies, v, ordem, nome, etapa_base, sla_horas, roteiro from public.funil_etapas where versao_id = base;
    perform privado.auditar(p_ies, 'funil.criar', 'funil', f::text, jsonb_build_object('modalidade', p_dados->>'modalidade', 'formas', formas));
    return jsonb_build_object('id', f, 'versao_id', v);
  end if;
  update public.funis set nome = coalesce(trim(p_dados->>'nome'), nome),
         ativo = coalesce((p_dados->>'ativo')::boolean, ativo)
   where id = p_id and ies_id = p_ies and (not padrao or coalesce((p_dados->>'ativo')::boolean, true))
  returning id into f;
  if f is null then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.auditar(p_ies, 'funil.editar', 'funil', f::text, jsonb_build_object('ativo', p_dados->>'ativo'));
  return jsonb_build_object('id', f);
exception
  when unique_violation then perform privado.erro_http(409, '23505', 'Já existe funil com este nome');
  when check_violation then raise exception 'Dados do funil inválidos (nome de 3 a 80 caracteres; formas de ingresso válidas)' using errcode = '22023';
end $$;

-- Nova versão em rascunho, clonada da versão publicada (ou da mais recente).
create or replace function public.rpc_nova_versao(p_funil bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare f public.funis; origem bigint; v bigint; n int;
begin
  perform privado.exigir_usuario();
  select * into f from public.funis where id = p_funil;
  if not found or not privado.ve_ies(f.ies_id) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(f.ies_id, 'funil.editar');
  if exists (select 1 from public.funil_versoes where funil_id = p_funil and status = 'rascunho') then
    raise exception 'Já existe uma versão em rascunho deste funil' using errcode = '22023';
  end if;
  select id into origem from public.funil_versoes where funil_id = p_funil order by (status = 'publicada') desc, versao desc limit 1;
  select coalesce(max(versao), 0) + 1 into n from public.funil_versoes where funil_id = p_funil;
  insert into public.funil_versoes(ies_id, funil_id, versao, criado_por) values (f.ies_id, p_funil, n, (select auth.uid())) returning id into v;
  insert into public.funil_etapas(ies_id, versao_id, ordem, nome, etapa_base, sla_horas, roteiro)
    select f.ies_id, v, ordem, nome, etapa_base, sla_horas, roteiro from public.funil_etapas where versao_id = origem;
  insert into public.funil_cadencias(ies_id, versao_id, etapa_ordem, passo, dia, canal, descricao)
    select f.ies_id, v, etapa_ordem, passo, dia, canal, descricao from public.funil_cadencias where versao_id = origem;
  insert into public.funil_metas(ies_id, versao_id, forma_ingresso, conversao_meta)
    select f.ies_id, v, forma_ingresso, conversao_meta from public.funil_metas where versao_id = origem;
  perform privado.auditar(f.ies_id, 'funil.nova_versao', 'funil', p_funil::text, jsonb_build_object('versao', n));
  return jsonb_build_object('versao_id', v, 'versao', n);
end $$;

-- Regras estruturais de uma versão: etapas 1..N contíguas, ordem coerente com as etapas oficiais,
-- toda etapa oficial aberta coberta, cadências apontando para etapas existentes.
create or replace function privado.validar_versao(p_versao bigint) returns void
language plpgsql stable security definer set search_path = '' as $$
declare faltando text; n int;
begin
  select count(*) into n from public.funil_etapas where versao_id = p_versao;
  if n = 0 or n <> (select max(ordem) from public.funil_etapas where versao_id = p_versao) then
    raise exception 'As etapas devem ser numeradas de 1 a N, sem lacunas' using errcode = '22023';
  end if;
  select string_agg(b, ', ') into faltando from unnest(array['novo','contato','inscrito','pre_matricula','matricula_comercial']) b
   where not exists (select 1 from public.funil_etapas e where e.versao_id = p_versao and e.etapa_base = b);
  if faltando is not null then raise exception 'Toda etapa oficial precisa de ao menos uma etapa no funil. Faltando: %', faltando using errcode = '22023'; end if;
  if exists (select 1 from (select privado.ordem_etapa(etapa_base) - lag(privado.ordem_etapa(etapa_base)) over (order by ordem) as d
                              from public.funil_etapas where versao_id = p_versao) x where d < 0) then
    raise exception 'A ordem das etapas deve seguir a ordem das etapas oficiais (novo → matrícula comercial)' using errcode = '22023';
  end if;
  if exists (select 1 from public.funil_cadencias c where c.versao_id = p_versao
             and not exists (select 1 from public.funil_etapas e where e.versao_id = p_versao and e.ordem = c.etapa_ordem)) then
    raise exception 'Cadência aponta para etapa inexistente' using errcode = '22023';
  end if;
end $$;
revoke execute on function privado.validar_versao(bigint) from public, anon, authenticated;

-- Substitui o conteúdo de um rascunho de forma atômica (etapas, cadências, metas, notas).
create or replace function public.rpc_salvar_versao(p_versao bigint, p_dados jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v public.funil_versoes;
begin
  perform privado.exigir_usuario();
  select * into v from public.funil_versoes where id = p_versao for update;
  if not found or not privado.ve_ies(v.ies_id) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(v.ies_id, 'funil.editar');
  if v.status <> 'rascunho' then raise exception 'Versão % é imutável; crie uma nova versão', v.status using errcode = '22023'; end if;
  if jsonb_typeof(p_dados->'etapas') <> 'array' or jsonb_array_length(p_dados->'etapas') not between 5 and 40 then
    raise exception 'Informe de 5 a 40 etapas' using errcode = '22023';
  end if;
  delete from public.funil_cadencias where versao_id = p_versao;
  delete from public.funil_metas where versao_id = p_versao;
  delete from public.funil_etapas where versao_id = p_versao;
  insert into public.funil_etapas(ies_id, versao_id, ordem, nome, etapa_base, sla_horas, roteiro)
    select v.ies_id, p_versao, (e->>'ordem')::int, trim(e->>'nome'), e->>'etapa_base', nullif(e->>'sla_horas', '')::int, nullif(trim(e->>'roteiro'), '')
      from jsonb_array_elements(p_dados->'etapas') e;
  insert into public.funil_cadencias(ies_id, versao_id, etapa_ordem, passo, dia, canal, descricao)
    select v.ies_id, p_versao, (c->>'etapa_ordem')::int, (c->>'passo')::int, (c->>'dia')::int, c->>'canal', trim(c->>'descricao')
      from jsonb_array_elements(coalesce(p_dados->'cadencias', '[]'::jsonb)) c;
  insert into public.funil_metas(ies_id, versao_id, forma_ingresso, conversao_meta)
    select v.ies_id, p_versao, m->>'forma_ingresso', (m->>'conversao_meta')::numeric
      from jsonb_array_elements(coalesce(p_dados->'metas', '[]'::jsonb)) m;
  update public.funil_versoes set notas = nullif(trim(coalesce(p_dados->>'notas', '')), '') where id = p_versao;
  perform privado.validar_versao(p_versao);
  perform privado.auditar(v.ies_id, 'funil.salvar_versao', 'funil', v.funil_id::text,
    jsonb_build_object('versao', v.versao, 'etapas', jsonb_array_length(p_dados->'etapas')));
  return privado.versao_json(p_versao);
exception
  when unique_violation then raise exception 'Etapas com ordem ou nome repetidos, ou cadência repetida' using errcode = '22023';
  when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'Dados da versão inválidos: confira nomes (2 a 60), etapa oficial, SLA (1 a 720 h), canais e metas (0 a 100%%)' using errcode = '22023';
end $$;

create or replace function public.rpc_publicar_versao(p_versao bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v public.funil_versoes; anterior int;
begin
  perform privado.exigir_usuario();
  select * into v from public.funil_versoes where id = p_versao for update;
  if not found or not privado.ve_ies(v.ies_id) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(v.ies_id, 'funil.publicar');
  if v.status <> 'rascunho' then raise exception 'Só um rascunho pode ser publicado' using errcode = '22023'; end if;
  perform privado.validar_versao(p_versao);
  update public.funil_versoes set status = 'arquivada' where funil_id = v.funil_id and status = 'publicada' returning versao into anterior;
  update public.funil_versoes set status = 'publicada', publicada_por = (select auth.uid()), publicada_em = now() where id = p_versao;
  perform privado.auditar(v.ies_id, 'funil.publicar', 'funil', v.funil_id::text, jsonb_build_object('versao', v.versao, 'arquivada', anterior));
  return jsonb_build_object('versao_id', p_versao, 'versao', v.versao, 'arquivada', anterior);
end $$;

-- Avança a subetapa dentro da mesma etapa oficial (sem mudar a etapa oficial nem as validações).
create or replace function public.rpc_mover_subetapa(p_op bigint, p_ordem int, p_versao int)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; e public.funil_etapas; de text;
begin
  o := privado.carregar_op(p_op, array['comercial','gestor']);
  if o.versao <> p_versao then perform privado.erro_http(409, '40001', 'Conflito de versão: a oportunidade foi alterada por outra pessoa. Recarregue.'); end if;
  select * into e from public.funil_etapas where versao_id = o.funil_versao_id and ordem = p_ordem;
  if not found or e.etapa_base <> o.etapa then
    raise exception 'Subetapa inválida: só é possível mover dentro da etapa oficial atual (%). Para mudar de etapa, use o funil oficial.', o.etapa using errcode = '22023';
  end if;
  if o.funil_etapa_ordem = p_ordem then raise exception 'A oportunidade já está nesta subetapa' using errcode = '22023'; end if;
  select nome into de from public.funil_etapas where versao_id = o.funil_versao_id and ordem = o.funil_etapa_ordem;
  update public.oportunidades set funil_etapa_ordem = p_ordem, versao = versao + 1, atualizado_em = now() where id = p_op;
  perform privado.auditar(o.ies_id, 'oportunidade.subetapa', 'oportunidade', p_op::text, jsonb_build_object('de', de, 'para', e.nome));
  return jsonb_build_object('id', p_op, 'etapa_ordem', p_ordem, 'versao', o.versao + 1);
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.rpc_funis(bigint), public.rpc_funil_oportunidade(bigint), public.rpc_salvar_funil(bigint, jsonb, bigint),
  public.rpc_nova_versao(bigint), public.rpc_salvar_versao(bigint, jsonb), public.rpc_publicar_versao(bigint),
  public.rpc_mover_subetapa(bigint, int, int)
to authenticated;

-- ===================== supabase/migrations/20261125000014_maim_performance.sql
-- Matrícula 360° — migração 14: MAIM Performance (Bíblia v0.2 §5, P1).
--   * Por etapa oficial: alcance, avanço, conversão da etapa, perdas, tempo mediano de permanência e parados,
--     sempre com o denominador explícito. Gargalo = menor conversão entre etapas com amostra suficiente.
--   * Por atendente: SLA do primeiro contato, horas até o primeiro contato, interações, matrículas, ingressos.
--     Gestão e reitoria veem a equipe; o atendente vê apenas a própria linha.
--   * Recomendações: regras puras versionadas (performance-v1), com justificativa numérica. Não executam nada.
--   * Aviso obrigatório: apoio à gestão; não usar isoladamente para decisões laborais (Bíblia §5).
-- Idempotente.

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('performance.ver',    'Central de Inteligência', 'Ver gargalos e indicadores por etapa do recorte autorizado', array['gestor','reitoria','coordenador','comercial'], 'curso', 'rpc_performance'),
  ('performance.equipe', 'Central de Inteligência', 'Ver indicadores individuais da equipe comercial',          array['gestor','reitoria'], 'curso', 'rpc_performance')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

create or replace function public.rpc_performance(p_ies bigint, p_coorte text, p_filtros jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  todos constant text[] := array['gestor','reitoria','coordenador','comercial','secretaria','financeiro'];
  amostra_min constant int := 10;  -- regra performance-v1: abaixo disso a conversão da etapa não aponta gargalo
  f_campus bigint := nullif(p_filtros->>'campus_id', '')::bigint;
  f_curso bigint := nullif(p_filtros->>'curso_id', '')::bigint;
  f_turno text := nullif(p_filtros->>'turno', '');
  f_modal text := nullif(p_filtros->>'modalidade', '');
  equipe boolean; cfg public.ies; etapas jsonb; atendentes jsonb; gargalo jsonb; recs jsonb := '[]'::jsonb; sla_eq numeric; v_parados int;
begin
  perform privado.autorizar(p_ies, 'performance.ver');
  if p_coorte !~ '^\d{4}\.[12]$' then raise exception 'Coorte deve ter formato AAAA.1 ou AAAA.2' using errcode = '22023'; end if;
  equipe := privado.pode(p_ies, 'performance.equipe');
  select * into cfg from public.ies where id = p_ies;

  create temp table if not exists pg_temp.perf_ops (id bigint primary key, etapa text, responsavel_id uuid, pessoa_id bigint, criado_em timestamptz,
    matricula_comercial_em timestamptz, confirmada_em timestamptz, atualizado_em timestamptz, alcance int) on commit drop;
  truncate pg_temp.perf_ops;
  insert into pg_temp.perf_ops
  select o.id, o.etapa, o.responsavel_id, o.pessoa_id, o.criado_em, o.matricula_comercial_em, o.confirmada_em, o.atualizado_em,
         greatest(case when o.etapa in ('perdido','cancelado') then 0 else privado.ordem_etapa(o.etapa) end,
                  case when o.confirmada_em is not null then 6 when o.matricula_comercial_em is not null then 5 else 0 end,
                  coalesce((select max(greatest(privado.ordem_etapa(a.dados->>'de'), privado.ordem_etapa(a.dados->>'para')))
                              from public.auditoria a where a.entidade = 'oportunidade' and a.entidade_id = o.id::text and a.acao = 'oportunidade.etapa'), 1))
    from public.oportunidades o join public.cursos c on c.id = o.curso_id
   where o.ies_id = p_ies and o.coorte = p_coorte and privado.tem_acesso(o.ies_id, o.curso_id, todos)
     and (f_campus is null or c.campus_id = f_campus) and (f_curso is null or c.id = f_curso)
     and (f_turno is null or c.turno = f_turno) and (f_modal is null or c.modalidade = f_modal);

  -- Movimentos auditados (entradas e saídas de cada etapa) para medir permanência e perdas por etapa.
  with mov as (
    select a.entidade_id::bigint as op, a.dados->>'de' as de, a.dados->>'para' as para, a.em
      from public.auditoria a join pg_temp.perf_ops p on p.id::text = a.entidade_id
     where a.entidade = 'oportunidade' and a.acao = 'oportunidade.etapa'
  ), entradas as (
    select id as op, 'novo' as etapa, criado_em as em from pg_temp.perf_ops
    union all select op, para, em from mov
  ), permanencia as (
    select e.etapa, extract(epoch from (select min(m.em) from mov m where m.op = e.op and m.de = e.etapa and m.em >= e.em) - e.em) / 3600 as horas
      from entradas e
  ), base as (
    select s.k, s.etapa,
           (select count(*) from pg_temp.perf_ops where alcance >= s.k) as alcancaram,
           (select count(*) from pg_temp.perf_ops where alcance >= s.k + 1) as avancaram,
           (select count(*) from mov where de = s.etapa and para = 'perdido') as perdidos,
           (select percentile_cont(0.5) within group (order by horas) from permanencia where etapa = s.etapa and horas is not null) as horas_mediana,
           (select count(*) from permanencia where etapa = s.etapa and horas is not null) as n_tempo,
           (select count(*) from pg_temp.perf_ops where etapa = s.etapa and atualizado_em < now() - make_interval(days => cfg.dias_sem_contato)) as parados
      from (values (1,'novo'),(2,'contato'),(3,'inscrito'),(4,'pre_matricula'),(5,'matricula_comercial')) s(k, etapa)
  )
  select jsonb_agg(jsonb_build_object('etapa', etapa, 'alcancaram', alcancaram, 'avancaram', avancaram,
           'conversao_etapa', case when alcancaram = 0 then null else round(avancaram::numeric / alcancaram, 4) end,
           'denominador', alcancaram, 'amostra_suficiente', alcancaram >= amostra_min,
           'perdidos_na_etapa', perdidos, 'horas_mediana_na_etapa', round(horas_mediana::numeric, 1), 'medicoes_tempo', n_tempo,
           'parados', parados) order by k)
    into etapas from base;

  select e into gargalo from jsonb_array_elements(etapas) e
   where (e->>'amostra_suficiente')::boolean and e->>'conversao_etapa' is not null
   order by (e->>'conversao_etapa')::numeric, e->>'etapa' limit 1;

  -- Indicadores por atendente (responsável atual). Denominadores explícitos; N/D quando não há base.
  with t as (
    select p.responsavel_id, x.status, x.vence_em, x.encerrada_em, p.criado_em as op_criada
      from pg_temp.perf_ops p join public.tarefas x on x.oportunidade_id = p.id and x.tipo = 'primeiro_contato'
  ), por as (
    select p.responsavel_id, count(*) as oportunidades,
           count(*) filter (where p.matricula_comercial_em is not null) as matriculas_comerciais,
           count(distinct p.pessoa_id) filter (where p.etapa = 'confirmado') as ingressantes,
           (select count(*) from t where t.responsavel_id is not distinct from p.responsavel_id and t.status = 'concluida' and t.encerrada_em <= t.vence_em) as sla_no_prazo,
           (select count(*) from t where t.responsavel_id is not distinct from p.responsavel_id and (t.status = 'concluida' or (t.status = 'aberta' and t.vence_em < now()))) as sla_base,
           (select percentile_cont(0.5) within group (order by extract(epoch from t.encerrada_em - t.op_criada) / 3600) from t
             where t.responsavel_id is not distinct from p.responsavel_id and t.status = 'concluida') as horas_primeiro_contato,
           (select count(*) from public.interacoes i join pg_temp.perf_ops q on q.id = i.oportunidade_id where i.usuario_id = p.responsavel_id) as interacoes,
           (select count(*) from public.tarefas x join pg_temp.perf_ops q on q.id = x.oportunidade_id where x.responsavel_id = p.responsavel_id and x.status = 'aberta' and x.vence_em < now()) as tarefas_atrasadas
      from pg_temp.perf_ops p group by p.responsavel_id
  )
  select jsonb_agg(jsonb_build_object('atendente', coalesce(privado.nome_usuario(responsavel_id), 'Sem responsável'), 'eu', responsavel_id = (select auth.uid()),
           'oportunidades', oportunidades, 'matriculas_comerciais', matriculas_comerciais, 'ingressantes', ingressantes,
           'conversao', case when oportunidades = 0 then null else round(ingressantes::numeric / oportunidades, 4) end,
           'sla_primeiro_contato', case when sla_base = 0 then null else round(sla_no_prazo::numeric / sla_base, 4) end, 'sla_denominador', sla_base,
           'horas_ate_primeiro_contato', round(horas_primeiro_contato::numeric, 1), 'interacoes', interacoes, 'tarefas_atrasadas', tarefas_atrasadas)
           order by oportunidades desc)
    into atendentes from por
   where equipe or responsavel_id = (select auth.uid());

  -- Recomendações (performance-v1): propostas com justificativa; nada é executado.
  if gargalo is not null then
    recs := recs || jsonb_build_object('regra', 'performance-v1/gargalo', 'prioridade', 1,
      'titulo', format('Gargalo na etapa %s', gargalo->>'etapa'),
      'justificativa', format('%s de %s oportunidades avançaram (%s%%), a menor conversão entre as etapas com amostra mínima de %s.',
                              gargalo->>'avancaram', gargalo->>'alcancaram', round((gargalo->>'conversao_etapa')::numeric * 100, 1), amostra_min),
      'proposta', case gargalo->>'etapa'
        when 'novo' then 'Reforçar o primeiro contato: cumprir o SLA e revisar a qualidade dos leads por origem.'
        when 'contato' then 'Revisar roteiro e cadência da etapa de contato no funil e tratar as objeções mais frequentes.'
        when 'inscrito' then 'Acompanhar inscritos até a prova/análise e antecipar a apresentação das condições.'
        when 'pre_matricula' then 'Revisar propostas e bolsas pendentes e o prazo de validade das ofertas.'
        else 'Concluir as validações documental, financeira e acadêmica das matrículas comerciais.' end);
  end if;
  select round(sum((a->>'sla_primeiro_contato')::numeric * (a->>'sla_denominador')::int) / nullif(sum((a->>'sla_denominador')::int), 0), 4)
    into sla_eq from jsonb_array_elements(coalesce(atendentes, '[]'::jsonb)) a where a->>'sla_primeiro_contato' is not null;
  if equipe and sla_eq is not null and sla_eq < 0.8 then
    recs := recs || jsonb_build_object('regra', 'performance-v1/sla', 'prioridade', 1, 'titulo', 'SLA do primeiro contato abaixo de 80%',
      'justificativa', format('Cumprimento da equipe: %s%%.', round(sla_eq * 100, 1)),
      'proposta', 'Rever capacidade por atendente e distribuição nas Configurações; priorizar a fila do MAIM.');
  end if;
  select sum((e->>'parados')::int) into v_parados from jsonb_array_elements(etapas) e;
  if v_parados > 0 then
    recs := recs || jsonb_build_object('regra', 'performance-v1/parados', 'prioridade', 2, 'titulo', 'Oportunidades paradas',
      'justificativa', format('%s oportunidade(s) abertas sem atualização há mais de %s dias.', v_parados, cfg.dias_sem_contato),
      'proposta', 'Executar o ciclo do MAIM para gerar follow-ups ou registrar o contato realizado.');
  end if;

  return jsonb_build_object('coorte', p_coorte, 'regra', 'performance-v1', 'amostra_minima_etapa', amostra_min, 've_equipe', equipe,
    'etapas', coalesce(etapas, '[]'::jsonb), 'gargalo', gargalo, 'atendentes', coalesce(atendentes, '[]'::jsonb),
    'sla_primeiro_contato_equipe', case when equipe then sla_eq end, 'recomendacoes', recs,
    'aviso', 'Indicadores de apoio à gestão comercial. Não devem ser usados isoladamente para decisões laborais nem para decidir ingresso.',
    'metodos', jsonb_build_object(
      'conversao_etapa', 'Oportunidades que alcançaram a etapa seguinte ÷ oportunidades que alcançaram a etapa (alcance reconstruído pelo histórico auditado). Gargalo só com denominador ≥ amostra mínima.',
      'permanencia', 'Mediana das horas entre a entrada e a saída da etapa, a partir dos movimentos auditados; oportunidades ainda na etapa não entram na medição.',
      'sla', 'Tarefas de primeiro contato concluídas no prazo ÷ (concluídas + abertas vencidas).',
      'parados', format('Abertas na etapa sem atualização há mais de %s dias (parâmetro da instituição).', cfg.dias_sem_contato)));
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.rpc_performance(bigint, text, jsonb) to authenticated;

-- ===================== supabase/migrations/20261125000015_recuperacao.sql
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

-- ===================== supabase/migrations/20261125000016_academia.sql
-- Matrícula 360° — migração 16: Academia de Captação (E08) e MAIM Learning. Bíblia v0.2 §2, §5 e §8.
--   * Trilhas por papel (SDR, Closer, Farmer, liderança, produtos, ética e LGPD) com módulos e competência; progresso.
--   * Rubricas versionadas (rascunho → publicada imutável → arquivada) sobre 7 competências, 4 níveis descritos.
--   * Roleplay apenas com cenários SINTÉTICOS.
--   * Avaliação HUMANA: avaliador ≠ avaliado; evidência obrigatória; finalizada é imutável; o avaliado vê tudo.
--     Nenhuma nota automática por texto ou IA: a consolidação é só a média ponderada dos níveis dados pela pessoa.
--   * PDI com objetivo, ações, prazo e reavaliação; histórico longitudinal por competência.
--   * MAIM Learning (learning-v1): lacuna = nível ≤ 2 na avaliação finalizada mais recente; recomenda módulos.
-- Conteúdo inicial é próprio da plataforma e editável. Idempotente.

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('academia.ver',     'Academia de Captação', 'Ver trilhas, cenários, próprias avaliações, PDI e recomendações', array['gestor','reitoria','comercial'], 'curso', 'rpc_academia'),
  ('academia.equipe',  'Academia de Captação', 'Ver avaliações, PDIs e lacunas da equipe',                        array['gestor','reitoria'], 'curso', 'rpc_academia'),
  ('academia.avaliar', 'Academia de Captação', 'Avaliar atendente por rubrica publicada (nunca a si mesmo)',      array['gestor'], 'curso', 'rpc_salvar_avaliacao'),
  ('academia.gerir',   'Academia de Captação', 'Editar trilhas, rubricas e cenários; abrir PDI',                  array['gestor'], 'ies', 'rpc_salvar_rubrica')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

create table if not exists public.trilhas (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  nome text not null check (length(nome) between 3 and 100),
  papel_alvo text not null check (papel_alvo in ('sdr','closer','farmer','lideranca','todos')),
  descricao text check (length(descricao) <= 1000),
  ativa boolean not null default true,
  unique (ies_id, nome)
);
create table if not exists public.modulos (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  trilha_id bigint not null references public.trilhas(id),
  ordem int not null check (ordem between 1 and 50),
  titulo text not null check (length(titulo) between 3 and 120),
  conteudo text not null check (length(conteudo) between 10 and 8000),
  competencia text not null check (competencia in ('comunicacao','escuta','dominio_tecnico','negociacao_etica','objecoes','registro','disciplina_operacional')),
  carga_minutos int not null default 30 check (carga_minutos between 5 and 600),
  unique (trilha_id, ordem)
);
create table if not exists public.progresso_modulos (
  usuario_id uuid not null references public.usuarios(id),
  modulo_id bigint not null references public.modulos(id),
  ies_id bigint not null references public.ies(id),
  concluido_em timestamptz not null default now(),
  primary key (usuario_id, modulo_id)
);
create table if not exists public.rubricas (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  nome text not null check (length(nome) between 3 and 100),
  versao int not null,
  status text not null default 'rascunho' check (status in ('rascunho','publicada','arquivada')),
  publicada_em timestamptz,
  unique (ies_id, nome, versao)
);
create unique index if not exists rubrica_uma_publicada on public.rubricas(ies_id, nome) where status = 'publicada';
create table if not exists public.rubrica_criterios (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  rubrica_id bigint not null references public.rubricas(id),
  competencia text not null check (competencia in ('comunicacao','escuta','dominio_tecnico','negociacao_etica','objecoes','registro','disciplina_operacional')),
  descricao text not null check (length(descricao) between 3 and 400),
  niveis jsonb not null check (jsonb_typeof(niveis) = 'array' and jsonb_array_length(niveis) = 4),
  peso int not null default 1 check (peso between 1 and 5),
  unique (rubrica_id, competencia)
);
create table if not exists public.cenarios (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  titulo text not null check (length(titulo) between 3 and 120),
  perfil_sintetico text not null check (length(perfil_sintetico) between 10 and 2000),
  objetivo text not null check (length(objetivo) between 3 and 400),
  objecoes text check (length(objecoes) <= 1000),
  etapa_base text check (etapa_base in ('novo','contato','inscrito','pre_matricula','matricula_comercial')),
  ativo boolean not null default true,
  unique (ies_id, titulo)
);
create table if not exists public.avaliacoes (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  avaliado_id uuid not null references public.usuarios(id),
  avaliador_id uuid not null references public.usuarios(id),
  rubrica_id bigint not null references public.rubricas(id),
  cenario_id bigint references public.cenarios(id),
  tipo text not null check (tipo in ('roleplay','observacao_atendimento')),
  niveis jsonb not null default '{}'::jsonb,
  evidencias text not null check (length(evidencias) between 10 and 4000),
  comentario text check (length(comentario) <= 2000),
  status text not null default 'rascunho' check (status in ('rascunho','finalizada')),
  criado_em timestamptz not null default now(),
  finalizada_em timestamptz,
  check (avaliado_id <> avaliador_id)
);
create table if not exists public.pdis (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  usuario_id uuid not null references public.usuarios(id),
  competencia text not null check (competencia in ('comunicacao','escuta','dominio_tecnico','negociacao_etica','objecoes','registro','disciplina_operacional')),
  objetivo text not null check (length(objetivo) between 3 and 400),
  acoes text not null check (length(acoes) between 3 and 2000),
  prazo date not null,
  reavaliar_em date,
  status text not null default 'aberto' check (status in ('aberto','em_andamento','concluido','cancelado')),
  avaliacao_origem bigint references public.avaliacoes(id),
  criado_por uuid references public.usuarios(id),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create index if not exists trilhas_ies on public.trilhas(ies_id);
create index if not exists modulos_trilha on public.modulos(trilha_id);
create index if not exists modulos_ies on public.modulos(ies_id);
create index if not exists progresso_modulo on public.progresso_modulos(modulo_id);
create index if not exists progresso_ies on public.progresso_modulos(ies_id);
create index if not exists rubricas_ies on public.rubricas(ies_id);
create index if not exists criterios_ies on public.rubrica_criterios(ies_id);
create index if not exists cenarios_ies on public.cenarios(ies_id);
create index if not exists avaliacoes_ies on public.avaliacoes(ies_id);
create index if not exists avaliacoes_avaliado on public.avaliacoes(avaliado_id);
create index if not exists avaliacoes_avaliador on public.avaliacoes(avaliador_id);
create index if not exists avaliacoes_rubrica on public.avaliacoes(rubrica_id);
create index if not exists avaliacoes_cenario on public.avaliacoes(cenario_id);
create index if not exists pdis_ies on public.pdis(ies_id);
create index if not exists pdis_usuario on public.pdis(usuario_id);
create index if not exists pdis_avaliacao on public.pdis(avaliacao_origem);
create index if not exists pdis_criado on public.pdis(criado_por);

alter table public.trilhas enable row level security;
alter table public.modulos enable row level security;
alter table public.progresso_modulos enable row level security;
alter table public.rubricas enable row level security;
alter table public.rubrica_criterios enable row level security;
alter table public.cenarios enable row level security;
alter table public.avaliacoes enable row level security;
alter table public.pdis enable row level security;
revoke all on public.trilhas, public.modulos, public.progresso_modulos, public.rubricas, public.rubrica_criterios,
  public.cenarios, public.avaliacoes, public.pdis from anon, authenticated;

-- ---------------------------------------------------------------- conteúdo inicial próprio (editável)
create or replace function privado.criar_academia_padrao(p_ies bigint) returns void
language plpgsql security definer set search_path = '' as $$
declare t bigint; r bigint;
begin
  if exists (select 1 from public.trilhas where ies_id = p_ies) then return; end if;
  insert into public.trilhas(ies_id, nome, papel_alvo, descricao) values (p_ies, 'Atendimento inicial (SDR)', 'sdr', 'Primeiro contato, qualificação e registro.') returning id into t;
  insert into public.modulos(ies_id, trilha_id, ordem, titulo, conteudo, competencia, carga_minutos) values
    (p_ies, t, 1, 'Preparação e acolhimento', 'Antes do contato, leia a ficha e a origem do lead. Apresente-se, diga por que está ligando e confirme se é um bom momento. O objetivo do primeiro contato é entender, não vender.', 'comunicacao', 30),
    (p_ies, t, 2, 'Diagnóstico com perguntas abertas', 'Pergunte sobre objetivo profissional, rotina, horários e experiências anteriores. Escute até o fim, resuma o que ouviu e confirme. Anote o que for relevante para a próxima conversa.', 'escuta', 40),
    (p_ies, t, 3, 'Registro que serve à equipe', 'Todo contato vira registro: o que foi conversado, objeções e próximo passo com data. Registro incompleto faz o colega recomeçar do zero e expõe o candidato a repetições.', 'registro', 20);
  insert into public.trilhas(ies_id, nome, papel_alvo, descricao) values (p_ies, 'Condução e fechamento ético (Closer)', 'closer', 'Apresentação, condições e tratamento de objeções sem pressão indevida.') returning id into t;
  insert into public.modulos(ies_id, trilha_id, ordem, titulo, conteudo, competencia, carga_minutos) values
    (p_ies, t, 1, 'Apresentação do curso pelo que importa ao candidato', 'Conecte o curso ao objetivo que o candidato contou no diagnóstico. Use informações oficiais do curso; não prometa resultado profissional nem condições que não estejam aprovadas.', 'dominio_tecnico', 40),
    (p_ies, t, 2, 'Objeções: entender antes de responder', 'Trate a objeção como informação. Pergunte o que está por trás (preço, horário, distância, família), registre a categoria e responda com fatos. Objeção não superada também é registro válido.', 'objecoes', 40),
    (p_ies, t, 3, 'Condições e próximos passos', 'Apresente valores e bolsas dentro do limite aprovado, com validade clara. Combine o próximo passo com data. Descontos acima do limite exigem aprovação de outra pessoa.', 'negociacao_etica', 30);
  insert into public.trilhas(ies_id, nome, papel_alvo, descricao) values (p_ies, 'Relacionamento e reativação (Farmer)', 'farmer', 'Base perdida, reingresso e indicações com respeito às escolhas do titular.') returning id into t;
  insert into public.modulos(ies_id, trilha_id, ordem, titulo, conteudo, competencia, carga_minutos) values
    (p_ies, t, 1, 'Retomar contato com quem disse não', 'Leia o motivo da perda antes de ligar. Reconheça a decisão anterior, informe o que mudou (nova turma, condição, modalidade) e aceite um novo não. Respeite opt-out e carência.', 'comunicacao', 30),
    (p_ies, t, 2, 'Disciplina de cadência', 'Siga a cadência do funil e registre cada tentativa. Cadência não é insistência: depois do último passo, encerre ou devolva ao gestor.', 'disciplina_operacional', 20);
  insert into public.trilhas(ies_id, nome, papel_alvo, descricao) values (p_ies, 'Liderança comercial', 'lideranca', 'Acompanhamento da equipe por indicadores com denominador e por avaliação humana.') returning id into t;
  insert into public.modulos(ies_id, trilha_id, ordem, titulo, conteudo, competencia, carga_minutos) values
    (p_ies, t, 1, 'Ler indicadores sem tirar conclusões apressadas', 'Olhe sempre o denominador e o tamanho da amostra. Indicador é ponto de partida para conversa e treinamento, não sentença. Combine dados com observação do atendimento.', 'dominio_tecnico', 40),
    (p_ies, t, 2, 'Feedback e PDI', 'Feedback descreve comportamento observado com evidência, não a pessoa. Todo PDI tem objetivo, ações, prazo e data de reavaliação combinados com o atendente.', 'comunicacao', 40);
  insert into public.trilhas(ies_id, nome, papel_alvo, descricao) values (p_ies, 'Ética e LGPD na captação', 'todos', 'Base legal, minimização, opt-out e direitos do titular.') returning id into t;
  insert into public.modulos(ies_id, trilha_id, ordem, titulo, conteudo, competencia, carga_minutos) values
    (p_ies, t, 1, 'Base legal e origem do contato', 'Todo lead precisa de base legal e origem registradas. Sem isso, o cadastro é recusado. Não use listas de origem desconhecida.', 'negociacao_etica', 25),
    (p_ies, t, 2, 'Opt-out e minimização', 'Quando o titular pede para não ser contatado por um canal, o sistema suprime as tarefas daquele canal. Registre apenas o necessário e nunca compartilhe dados fora da plataforma.', 'registro', 25);
  insert into public.rubricas(ies_id, nome, versao, status, publicada_em) values (p_ies, 'Atendimento comercial', 1, 'publicada', now()) returning id into r;
  insert into public.rubrica_criterios(ies_id, rubrica_id, competencia, descricao, niveis, peso) values
    (p_ies, r, 'comunicacao', 'Clareza, cordialidade e adequação da linguagem', '["Confuso ou inadequado","Claro em parte","Claro e cordial","Claro, cordial e adaptado ao candidato"]', 1),
    (p_ies, r, 'escuta', 'Diagnóstico por perguntas abertas e confirmação do entendimento', '["Não investiga","Investiga pouco","Investiga e resume","Investiga, resume e usa o que ouviu"]', 2),
    (p_ies, r, 'dominio_tecnico', 'Informações corretas sobre curso, ingresso e condições', '["Informações incorretas","Informações incompletas","Informações corretas","Corretas e conectadas ao objetivo do candidato"]', 1),
    (p_ies, r, 'negociacao_etica', 'Condições dentro do aprovado, sem pressão ou promessa indevida', '["Pressão ou promessa indevida","Condição pouco clara","Condição clara e aprovada","Clara, aprovada e com prazo explicado"]', 2),
    (p_ies, r, 'objecoes', 'Entendimento e tratamento das objeções', '["Ignora a objeção","Responde sem entender","Entende e responde com fatos","Entende, responde e registra"]', 1),
    (p_ies, r, 'registro', 'Registro completo do contato e do próximo passo', '["Sem registro","Registro incompleto","Registro completo","Completo e útil para a equipe"]', 1),
    (p_ies, r, 'disciplina_operacional', 'Cumprimento de SLA, cadência e agenda', '["Descumpre","Cumpre parcialmente","Cumpre","Cumpre e antecipa"]', 1);
  insert into public.cenarios(ies_id, titulo, perfil_sintetico, objetivo, objecoes, etapa_base) values
    (p_ies, 'Trabalhador do turno da noite interessado em EAD', 'Pessoa fictícia de 32 anos, trabalha em turnos, concluiu o ensino médio há 12 anos e quer uma graduação para promoção interna.', 'Fazer o diagnóstico e apresentar a rotina do EAD.', 'Tempo disponível; receio de não acompanhar.', 'contato'),
    (p_ies, 'Candidato comparando mensalidades', 'Pessoa fictícia de 19 anos, recém-aprovada no ENEM, pesquisando três instituições.', 'Tratar a objeção de preço com fatos e condições aprovadas.', 'Concorrente mais barato; família decide.', 'pre_matricula');
end $$;
revoke execute on function privado.criar_academia_padrao(bigint) from public, anon, authenticated;
select privado.criar_academia_padrao(id) from public.ies;
create or replace function privado.ies_academia_padrao() returns trigger
language plpgsql security definer set search_path = '' as $$ begin perform privado.criar_academia_padrao(new.id); return new; end $$;
revoke execute on function privado.ies_academia_padrao() from public, anon, authenticated;
drop trigger if exists ies_cria_academia on public.ies;
create trigger ies_cria_academia after insert on public.ies for each row execute function privado.ies_academia_padrao();

-- Usuário é da equipe comercial desta IES (alvo de avaliação/PDI)?
create or replace function privado.eh_comercial(p_ies bigint, p_usuario uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.escopos e join public.usuarios u on u.id = e.usuario_id
                  where e.usuario_id = p_usuario and e.ies_id = p_ies and e.papel = 'comercial' and e.revogado_em is null and u.revogado_em is null);
$$;
revoke execute on function privado.eh_comercial(bigint, uuid) from public, anon, authenticated;

-- Consolidação determinística da avaliação humana (média ponderada dos níveis 1–4 atribuídos pelo avaliador).
create or replace function privado.consolidado(p_avaliacao bigint) returns numeric
language sql stable security definer set search_path = '' as $$
  select round(sum((a.niveis->>c.id::text)::int * c.peso)::numeric / nullif(sum(c.peso), 0), 2)
    from public.avaliacoes a join public.rubrica_criterios c on c.rubrica_id = a.rubrica_id
   where a.id = p_avaliacao and a.niveis ? c.id::text;
$$;
revoke execute on function privado.consolidado(bigint) from public, anon, authenticated;

-- ---------------------------------------------------------------- leitura
create or replace function public.rpc_academia(p_ies bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare equipe boolean; eu uuid := (select auth.uid());
begin
  perform privado.autorizar(p_ies, 'academia.ver');
  equipe := privado.pode(p_ies, 'academia.equipe');
  return jsonb_build_object('regra', 'learning-v1', 've_equipe', equipe,
    'pode_avaliar', privado.pode(p_ies, 'academia.avaliar'), 'pode_gerir', privado.pode(p_ies, 'academia.gerir'),
    'aviso', 'Avaliação formativa e humana, com evidência. Nenhuma nota automática por texto ou IA. Não use isoladamente para decisões laborais. O avaliado acessa integralmente as próprias avaliações e o PDI.',
    'trilhas', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'nome', t.nome, 'papel_alvo', t.papel_alvo, 'descricao', t.descricao,
        'modulos', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'ordem', m.ordem, 'titulo', m.titulo, 'conteudo', m.conteudo, 'competencia', m.competencia,
                      'carga_minutos', m.carga_minutos, 'concluido', exists (select 1 from public.progresso_modulos g where g.modulo_id = m.id and g.usuario_id = eu)) order by m.ordem), '[]'::jsonb)
                    from public.modulos m where m.trilha_id = t.id)) order by t.id), '[]'::jsonb)
      from public.trilhas t where t.ies_id = p_ies and t.ativa),
    'rubricas', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'nome', r.nome, 'versao', r.versao, 'status', r.status,
        'criterios', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'competencia', c.competencia, 'descricao', c.descricao, 'niveis', c.niveis, 'peso', c.peso) order by c.id), '[]'::jsonb)
                      from public.rubrica_criterios c where c.rubrica_id = r.id)) order by r.nome, r.versao desc), '[]'::jsonb)
      from public.rubricas r where r.ies_id = p_ies and r.status <> 'arquivada'),
    'cenarios', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'titulo', c.titulo, 'perfil_sintetico', c.perfil_sintetico, 'objetivo', c.objetivo,
        'objecoes', c.objecoes, 'etapa_base', c.etapa_base) order by c.id), '[]'::jsonb) from public.cenarios c where c.ies_id = p_ies and c.ativo),
    'equipe', case when equipe then (select coalesce(jsonb_agg(distinct jsonb_build_object('id', u.id, 'nome', u.nome)), '[]'::jsonb)
        from public.escopos e join public.usuarios u on u.id = e.usuario_id where e.ies_id = p_ies and e.papel = 'comercial' and e.revogado_em is null and u.revogado_em is null) end,
    'avaliacoes', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'avaliado', privado.nome_usuario(a.avaliado_id), 'avaliado_id', a.avaliado_id,
        'avaliador', privado.nome_usuario(a.avaliador_id), 'meu_rascunho', a.avaliador_id = eu and a.status = 'rascunho',
        'rubrica', r.nome || ' v' || r.versao, 'rubrica_id', a.rubrica_id, 'cenario', (select c.titulo from public.cenarios c where c.id = a.cenario_id), 'tipo', a.tipo,
        'niveis', a.niveis, 'evidencias', a.evidencias, 'comentario', a.comentario, 'status', a.status, 'criado_em', a.criado_em, 'finalizada_em', a.finalizada_em,
        'consolidado', privado.consolidado(a.id)) order by a.criado_em desc), '[]'::jsonb)
      from public.avaliacoes a join public.rubricas r on r.id = a.rubrica_id
     where a.ies_id = p_ies and (a.avaliado_id = eu or (equipe and (a.status = 'finalizada' or a.avaliador_id = eu)))),
    'pdis', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'usuario', privado.nome_usuario(p.usuario_id), 'meu', p.usuario_id = eu, 'competencia', p.competencia,
        'objetivo', p.objetivo, 'acoes', p.acoes, 'prazo', p.prazo, 'reavaliar_em', p.reavaliar_em, 'status', p.status,
        'reavaliacao_vencida', p.reavaliar_em < current_date and p.status in ('aberto','em_andamento')) order by p.prazo), '[]'::jsonb)
      from public.pdis p where p.ies_id = p_ies and (p.usuario_id = eu or equipe)),
    -- MAIM Learning: lacunas por pessoa e competência na avaliação finalizada mais recente, com módulos recomendados.
    'lacunas', (select coalesce(jsonb_agg(jsonb_build_object('usuario', privado.nome_usuario(x.avaliado_id), 'meu', x.avaliado_id = eu, 'competencia', x.competencia,
        'nivel', x.nivel, 'avaliada_em', x.finalizada_em,
        'historico', (select jsonb_agg(jsonb_build_object('em', a2.finalizada_em, 'nivel', (a2.niveis->>c2.id::text)::int) order by a2.finalizada_em)
                        from public.avaliacoes a2 join public.rubrica_criterios c2 on c2.rubrica_id = a2.rubrica_id
                       where a2.avaliado_id = x.avaliado_id and a2.ies_id = p_ies and a2.status = 'finalizada' and c2.competencia = x.competencia and a2.niveis ? c2.id::text),
        'recomendados', (select coalesce(jsonb_agg(jsonb_build_object('modulo_id', m.id, 'titulo', m.titulo, 'trilha', t.nome,
                            'concluido', exists (select 1 from public.progresso_modulos g where g.modulo_id = m.id and g.usuario_id = x.avaliado_id))), '[]'::jsonb)
                         from public.modulos m join public.trilhas t on t.id = m.trilha_id where t.ies_id = p_ies and t.ativa and m.competencia = x.competencia),
        'pdi_aberto', exists (select 1 from public.pdis p where p.usuario_id = x.avaliado_id and p.competencia = x.competencia and p.status in ('aberto','em_andamento')))
        order by x.nivel, x.competencia), '[]'::jsonb)
      from (select distinct on (a.avaliado_id, c.competencia) a.avaliado_id, c.competencia, (a.niveis->>c.id::text)::int as nivel, a.finalizada_em
              from public.avaliacoes a join public.rubrica_criterios c on c.rubrica_id = a.rubrica_id
             where a.ies_id = p_ies and a.status = 'finalizada' and a.niveis ? c.id::text and (a.avaliado_id = eu or equipe)
             order by a.avaliado_id, c.competencia, a.finalizada_em desc) x where x.nivel <= 2));
end $$;

-- ---------------------------------------------------------------- escrita
create or replace function public.rpc_concluir_modulo(p_modulo bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare m public.modulos;
begin
  perform privado.exigir_usuario();
  select * into m from public.modulos where id = p_modulo;
  if not found or not privado.ve_ies(m.ies_id) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(m.ies_id, 'academia.ver');
  insert into public.progresso_modulos(usuario_id, modulo_id, ies_id) values ((select auth.uid()), p_modulo, m.ies_id) on conflict do nothing;
  perform privado.auditar(m.ies_id, 'academia.modulo', 'modulo', p_modulo::text);
  return jsonb_build_object('modulo', p_modulo, 'concluido', true);
end $$;

create or replace function public.rpc_salvar_modulo(p_ies bigint, p_dados jsonb, p_id bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id bigint; t bigint := (p_dados->>'trilha_id')::bigint;
begin
  perform privado.autorizar(p_ies, 'academia.gerir');
  if p_id is null then
    if not exists (select 1 from public.trilhas where id = t and ies_id = p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
    insert into public.modulos(ies_id, trilha_id, ordem, titulo, conteudo, competencia, carga_minutos)
    values (p_ies, t, coalesce((select max(ordem) from public.modulos where trilha_id = t), 0) + 1, trim(p_dados->>'titulo'), trim(p_dados->>'conteudo'),
            p_dados->>'competencia', coalesce((p_dados->>'carga_minutos')::int, 30)) returning id into v_id;
  else
    update public.modulos set titulo = coalesce(trim(p_dados->>'titulo'), titulo), conteudo = coalesce(trim(p_dados->>'conteudo'), conteudo),
           competencia = coalesce(p_dados->>'competencia', competencia), carga_minutos = coalesce((p_dados->>'carga_minutos')::int, carga_minutos)
     where id = p_id and ies_id = p_ies returning id into v_id;
    if v_id is null then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  end if;
  perform privado.auditar(p_ies, 'academia.conteudo', 'modulo', v_id::text);
  return jsonb_build_object('id', v_id);
exception when check_violation or not_null_violation then
  raise exception 'Módulo inválido: título (3 a 120), conteúdo (10 a 8000), competência válida' using errcode = '22023';
end $$;

-- Nova versão de rubrica (rascunho) clonada da publicada; publicar arquiva a anterior. Avaliações já feitas mantêm a versão usada.
create or replace function public.rpc_salvar_rubrica(p_ies bigint, p_acao text, p_rubrica bigint, p_criterios jsonb default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.rubricas; v_id bigint;
begin
  perform privado.autorizar(p_ies, 'academia.gerir');
  select * into r from public.rubricas where id = p_rubrica and ies_id = p_ies for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if p_acao = 'nova_versao' then
    if exists (select 1 from public.rubricas where ies_id = p_ies and nome = r.nome and status = 'rascunho') then raise exception 'Já existe rascunho desta rubrica' using errcode = '22023'; end if;
    insert into public.rubricas(ies_id, nome, versao) values (p_ies, r.nome, (select max(versao) + 1 from public.rubricas where ies_id = p_ies and nome = r.nome)) returning id into v_id;
    insert into public.rubrica_criterios(ies_id, rubrica_id, competencia, descricao, niveis, peso)
      select p_ies, v_id, competencia, descricao, niveis, peso from public.rubrica_criterios where rubrica_id = p_rubrica;
  elsif p_acao = 'salvar' then
    if r.status <> 'rascunho' then raise exception 'Rubrica publicada é imutável; crie nova versão' using errcode = '22023'; end if;
    delete from public.rubrica_criterios where rubrica_id = p_rubrica;
    insert into public.rubrica_criterios(ies_id, rubrica_id, competencia, descricao, niveis, peso)
      select p_ies, p_rubrica, c->>'competencia', trim(c->>'descricao'), c->'niveis', coalesce((c->>'peso')::int, 1) from jsonb_array_elements(p_criterios) c;
    if (select count(*) from public.rubrica_criterios where rubrica_id = p_rubrica) < 3 then raise exception 'Rubrica precisa de ao menos 3 critérios' using errcode = '22023'; end if;
    v_id := p_rubrica;
  elsif p_acao = 'publicar' then
    if r.status <> 'rascunho' then raise exception 'Só rascunho pode ser publicado' using errcode = '22023'; end if;
    update public.rubricas set status = 'arquivada' where ies_id = p_ies and nome = r.nome and status = 'publicada';
    update public.rubricas set status = 'publicada', publicada_em = now() where id = p_rubrica;
    v_id := p_rubrica;
  else raise exception 'Ação inválida' using errcode = '22023'; end if;
  perform privado.auditar(p_ies, 'rubrica.' || p_acao, 'rubrica', v_id::text, jsonb_build_object('nome', r.nome));
  return jsonb_build_object('id', v_id);
exception when unique_violation or check_violation or not_null_violation then
  raise exception 'Critérios inválidos: competência válida e única, descrição e exatamente 4 níveis' using errcode = '22023';
end $$;

create or replace function public.rpc_salvar_cenario(p_ies bigint, p_dados jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  perform privado.autorizar(p_ies, 'academia.gerir');
  -- Cenário é sintético: recusa texto com padrão de e-mail ou telefone (evita dado pessoal real no roleplay).
  if concat_ws(' ', p_dados->>'perfil_sintetico', p_dados->>'objecoes', p_dados->>'titulo') ~ '[^\s@]+@[^\s@]+\.[a-z]{2,}|\d{8,}|\(\d{2}\)\s?\d{4,5}-?\d{4}' then
    raise exception 'Cenário deve ser sintético: não inclua e-mail ou telefone' using errcode = '22023';
  end if;
  insert into public.cenarios(ies_id, titulo, perfil_sintetico, objetivo, objecoes, etapa_base)
  values (p_ies, trim(p_dados->>'titulo'), trim(p_dados->>'perfil_sintetico'), trim(p_dados->>'objetivo'), nullif(trim(p_dados->>'objecoes'), ''), nullif(p_dados->>'etapa_base', ''))
  returning id into v_id;
  perform privado.auditar(p_ies, 'academia.cenario', 'cenario', v_id::text);
  return jsonb_build_object('id', v_id);
exception
  when unique_violation then perform privado.erro_http(409, '23505', 'Já existe cenário com este título');
  when check_violation or not_null_violation then raise exception 'Cenário inválido: título, perfil sintético (10+ caracteres) e objetivo obrigatórios' using errcode = '22023';
end $$;

-- Avaliação humana: rascunho editável pelo avaliador; finalizar exige todos os critérios e torna imutável.
create or replace function public.rpc_salvar_avaliacao(p_ies bigint, p_dados jsonb, p_id bigint default null, p_finalizar boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a public.avaliacoes; v_id bigint; v_avaliado uuid := (p_dados->>'avaliado_id')::uuid; v_rub bigint := (p_dados->>'rubrica_id')::bigint; k text; n int;
begin
  perform privado.autorizar(p_ies, 'academia.avaliar');
  if p_id is null then
    if v_avaliado = (select auth.uid()) then raise exception 'Ninguém avalia a si mesmo' using errcode = '42501'; end if;
    if not privado.eh_comercial(p_ies, v_avaliado) then raise exception 'Avaliado precisa ser atendente comercial ativo desta instituição' using errcode = '22023'; end if;
    if not exists (select 1 from public.rubricas where id = v_rub and ies_id = p_ies and status = 'publicada') then
      raise exception 'Use uma rubrica publicada' using errcode = '22023';
    end if;
    if nullif(p_dados->>'cenario_id', '') is not null and not exists (select 1 from public.cenarios where id = (p_dados->>'cenario_id')::bigint and ies_id = p_ies) then
      raise exception 'Cenário não pertence à IES' using errcode = '22023';
    end if;
    insert into public.avaliacoes(ies_id, avaliado_id, avaliador_id, rubrica_id, cenario_id, tipo, niveis, evidencias, comentario)
    values (p_ies, v_avaliado, (select auth.uid()), v_rub, nullif(p_dados->>'cenario_id', '')::bigint, p_dados->>'tipo', coalesce(p_dados->'niveis', '{}'::jsonb),
            trim(p_dados->>'evidencias'), nullif(trim(p_dados->>'comentario'), '')) returning * into a;
  else
    select * into a from public.avaliacoes where id = p_id and ies_id = p_ies for update;
    if not found or a.avaliador_id <> (select auth.uid()) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
    if a.status = 'finalizada' then raise exception 'Avaliação finalizada é imutável' using errcode = '22023'; end if;
    update public.avaliacoes set niveis = coalesce(p_dados->'niveis', niveis), evidencias = coalesce(trim(p_dados->>'evidencias'), evidencias),
           comentario = coalesce(nullif(trim(p_dados->>'comentario'), ''), comentario) where id = p_id returning * into a;
  end if;
  -- níveis só para critérios da rubrica e entre 1 e 4
  for k in select jsonb_object_keys(a.niveis) loop
    if not exists (select 1 from public.rubrica_criterios c where c.rubrica_id = a.rubrica_id and c.id::text = k) then raise exception 'Critério % não pertence à rubrica', k using errcode = '22023'; end if;
    n := (a.niveis->>k)::int;
    if n not between 1 and 4 then raise exception 'Nível deve ser de 1 a 4' using errcode = '22023'; end if;
  end loop;
  if p_finalizar then
    if exists (select 1 from public.rubrica_criterios c where c.rubrica_id = a.rubrica_id and not a.niveis ? c.id::text) then
      raise exception 'Para finalizar, avalie todos os critérios da rubrica' using errcode = '22023';
    end if;
    update public.avaliacoes set status = 'finalizada', finalizada_em = now() where id = a.id;
  end if;
  perform privado.auditar(p_ies, case when p_finalizar then 'avaliacao.finalizar' else 'avaliacao.salvar' end, 'avaliacao', a.id::text,
    jsonb_build_object('avaliado_id', a.avaliado_id, 'tipo', a.tipo));
  return jsonb_build_object('id', a.id, 'status', case when p_finalizar then 'finalizada' else 'rascunho' end, 'consolidado', privado.consolidado(a.id));
exception
  when check_violation or not_null_violation then raise exception 'Avaliação inválida: tipo, evidências (10+ caracteres) e avaliador diferente do avaliado' using errcode = '22023';
  when invalid_text_representation then raise exception 'Nível deve ser número de 1 a 4' using errcode = '22023';
end $$;

create or replace function public.rpc_salvar_pdi(p_ies bigint, p_dados jsonb, p_id bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id bigint; pd public.pdis; v_usuario uuid := (p_dados->>'usuario_id')::uuid;
begin
  perform privado.exigir_usuario();
  if p_id is null then
    perform privado.autorizar(p_ies, 'academia.gerir');
    if not privado.eh_comercial(p_ies, v_usuario) then raise exception 'PDI é para atendente comercial ativo desta instituição' using errcode = '22023'; end if;
    if nullif(p_dados->>'avaliacao_origem', '') is not null and not exists (select 1 from public.avaliacoes where id = (p_dados->>'avaliacao_origem')::bigint and avaliado_id = v_usuario and status = 'finalizada') then
      raise exception 'Avaliação de origem precisa ser finalizada e da mesma pessoa' using errcode = '22023';
    end if;
    insert into public.pdis(ies_id, usuario_id, competencia, objetivo, acoes, prazo, reavaliar_em, avaliacao_origem, criado_por)
    values (p_ies, v_usuario, p_dados->>'competencia', trim(p_dados->>'objetivo'), trim(p_dados->>'acoes'), (p_dados->>'prazo')::date,
            nullif(p_dados->>'reavaliar_em', '')::date, nullif(p_dados->>'avaliacao_origem', '')::bigint, (select auth.uid())) returning id into v_id;
  else
    -- O próprio atendente atualiza o andamento; o gestor também.
    select * into pd from public.pdis where id = p_id and ies_id = p_ies for update;
    if not found or not (pd.usuario_id = (select auth.uid()) or privado.pode(p_ies, 'academia.gerir')) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
    if p_dados ?| array['objetivo','acoes','prazo','competencia','usuario_id'] and not privado.pode(p_ies, 'academia.gerir') then
      raise exception 'O atendente atualiza apenas o andamento do PDI' using errcode = '42501';
    end if;
    update public.pdis set status = coalesce(p_dados->>'status', status), objetivo = coalesce(trim(p_dados->>'objetivo'), objetivo),
           acoes = coalesce(trim(p_dados->>'acoes'), acoes), prazo = coalesce((p_dados->>'prazo')::date, prazo),
           reavaliar_em = coalesce(nullif(p_dados->>'reavaliar_em', '')::date, reavaliar_em), atualizado_em = now() where id = p_id returning id into v_id;
  end if;
  perform privado.auditar(p_ies, 'pdi.salvar', 'pdi', v_id::text, jsonb_build_object('status', p_dados->>'status'));
  return jsonb_build_object('id', v_id);
exception when check_violation or not_null_violation then
  raise exception 'PDI inválido: competência, objetivo, ações e prazo obrigatórios' using errcode = '22023';
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.rpc_academia(bigint), public.rpc_concluir_modulo(bigint), public.rpc_salvar_modulo(bigint, jsonb, bigint),
  public.rpc_salvar_rubrica(bigint, text, bigint, jsonb), public.rpc_salvar_cenario(bigint, jsonb),
  public.rpc_salvar_avaliacao(bigint, jsonb, bigint, boolean), public.rpc_salvar_pdi(bigint, jsonb, bigint)
to authenticated;

-- ===================== supabase/migrations/20261125000017_relacionamento.sql
-- Matrícula 360° — migração 17: Relacionamento Estudantil (E09) e MAIM Retention. Bíblia v0.2 §2, §5, §6 e §8.
--   * Vínculo do ingressante nos marcos 30 dias, 90 dias e rematrícula, registrado por pessoa autorizada
--     (sem integração acadêmica). SEM registro = "desconhecido": nunca se presume evasão.
--   * Permanência 30/90 (Bíblia §6) = ingressantes elegíveis com vínculo ativo ÷ coorte elegível. Com cobertura
--     incompleta, o indicador oficial é N/D com a cobertura exibida; o "mínimo observado" é rotulado como tal.
--   * Onboarding com modelo editável por IES.
--   * Indicações rastreáveis por código no cadastro do lead; embaixadores com regras publicadas e aceite registrado.
--   * MAIM Retention (retention-v1): alertas de registro pendente, risco declarado e rematrícula, sem envio.
-- Idempotente.

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('relacionamento.ver',       'Relacionamento Estudantil', 'Ver ingressantes, permanência, onboarding, indicações e embaixadores', array['gestor','reitoria','coordenador','secretaria'], 'curso', 'rpc_relacionamento'),
  ('relacionamento.registrar', 'Relacionamento Estudantil', 'Registrar vínculo nos marcos e concluir itens de onboarding',      array['gestor','secretaria'], 'curso', 'rpc_registrar_vinculo'),
  ('indicacao.gerir',          'Relacionamento Estudantil', 'Criar códigos de indicação',                                        array['gestor','comercial'], 'curso', 'rpc_criar_indicacao'),
  ('embaixador.gerir',         'Relacionamento Estudantil', 'Publicar regras do programa e cadastrar embaixadores',             array['gestor'], 'ies', 'rpc_salvar_embaixador')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

alter table public.ies add column if not exists onboarding_modelo text[] not null
  default array['Boas-vindas e apresentação da coordenação','Acesso ao ambiente virtual e e-mail institucional','Calendário acadêmico e horários','Canais de atendimento ao estudante'];
alter table public.ies add column if not exists programa_embaixadores text check (length(programa_embaixadores) <= 3000);

create table if not exists public.vinculos (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  oportunidade_id bigint not null references public.oportunidades(id),
  marco text not null check (marco in ('d30','d90','rematricula')),
  situacao text not null check (situacao in ('ativo','trancado','evadido','transferido')),
  data_referencia date not null,
  fonte text not null default 'registro_manual' check (fonte in ('registro_manual','sistema_academico')),
  observacao text check (length(observacao) <= 500),
  registrado_por uuid not null references public.usuarios(id),
  registrado_em timestamptz not null default now(),
  unique (oportunidade_id, marco)
);
create table if not exists public.onboarding (
  ies_id bigint not null references public.ies(id),
  oportunidade_id bigint not null references public.oportunidades(id),
  item text not null check (length(item) between 3 and 200),
  concluido_por uuid not null references public.usuarios(id),
  concluido_em timestamptz not null default now(),
  primary key (oportunidade_id, item)
);
create table if not exists public.embaixadores (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  oportunidade_id bigint not null references public.oportunidades(id),
  status text not null default 'ativo' check (status in ('ativo','inativo')),
  aceite_regras_em timestamptz not null,
  versao_regras text not null,
  criado_por uuid references public.usuarios(id),
  criado_em timestamptz not null default now(),
  unique (oportunidade_id)
);
create table if not exists public.indicacoes (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  codigo text not null check (codigo ~ '^[a-z0-9][a-z0-9-]{3,40}$'),
  indicador_tipo text not null check (indicador_tipo in ('aluno','embaixador','colaborador','parceiro')),
  indicador_nome text not null check (length(indicador_nome) between 2 and 120),
  embaixador_id bigint references public.embaixadores(id),
  ativa boolean not null default true,
  criado_por uuid references public.usuarios(id),
  criado_em timestamptz not null default now(),
  unique (ies_id, codigo)
);
alter table public.oportunidades add column if not exists indicacao_id bigint references public.indicacoes(id);

create index if not exists vinculos_ies on public.vinculos(ies_id);
create index if not exists vinculos_registrado on public.vinculos(registrado_por);
create index if not exists onboarding_ies on public.onboarding(ies_id);
create index if not exists onboarding_por on public.onboarding(concluido_por);
create index if not exists embaixadores_ies on public.embaixadores(ies_id);
create index if not exists embaixadores_criado on public.embaixadores(criado_por);
create index if not exists indicacoes_embaixador on public.indicacoes(embaixador_id);
create index if not exists indicacoes_criado on public.indicacoes(criado_por);
create index if not exists oportunidades_indicacao on public.oportunidades(indicacao_id);

alter table public.vinculos enable row level security;
alter table public.onboarding enable row level security;
alter table public.embaixadores enable row level security;
alter table public.indicacoes enable row level security;
revoke all on public.vinculos, public.onboarding, public.embaixadores, public.indicacoes from anon, authenticated;

-- Dias do marco a partir da confirmação do ingresso (regra retention-v1).
create or replace function privado.dias_marco(p_marco text) returns int
language sql immutable set search_path = '' as $$
  select case p_marco when 'd30' then 30 when 'd90' then 90 when 'rematricula' then 150 end;
$$;
revoke execute on function privado.dias_marco(text) from public, anon, authenticated;

-- ---------------------------------------------------------------- escrita
create or replace function public.rpc_registrar_vinculo(p_op bigint, p_marco text, p_situacao text, p_data date, p_observacao text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; v_id bigint; anterior text;
begin
  perform privado.exigir_usuario();
  select * into o from public.oportunidades where id = p_op;
  if not found or not privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, array['gestor','reitoria','coordenador','secretaria']) then
    perform privado.erro_http(404, 'P0002', 'Não encontrado');
  end if;
  if not privado.tem_acesso(o.ies_id, o.curso_id, (select papeis from public.matriz_permissoes where operacao = 'relacionamento.registrar')) then
    raise exception 'Seu perfil não tem permissão para esta operação' using errcode = '42501';
  end if;
  if o.etapa <> 'confirmado' then raise exception 'Vínculo só para ingressante efetivo' using errcode = '22023'; end if;
  if p_marco not in ('d30','d90','rematricula') or p_situacao not in ('ativo','trancado','evadido','transferido') then
    raise exception 'Marco ou situação inválidos' using errcode = '22023';
  end if;
  if p_data is null or p_data > current_date or p_data < o.confirmada_em::date then
    raise exception 'Data de referência entre a confirmação do ingresso e hoje' using errcode = '22023';
  end if;
  if current_date < o.confirmada_em::date + privado.dias_marco(p_marco) then
    raise exception 'Marco ainda não alcançado: disponível a partir de %', o.confirmada_em::date + privado.dias_marco(p_marco) using errcode = '22023';
  end if;
  if p_situacao <> 'ativo' and length(coalesce(trim(p_observacao), '')) < 3 then
    raise exception 'Descreva a fonte da informação para situação diferente de ativo' using errcode = '22023';
  end if;
  select situacao into anterior from public.vinculos where oportunidade_id = p_op and marco = p_marco;
  insert into public.vinculos(ies_id, oportunidade_id, marco, situacao, data_referencia, observacao, registrado_por)
  values (o.ies_id, p_op, p_marco, p_situacao, p_data, nullif(trim(p_observacao), ''), (select auth.uid()))
  on conflict (oportunidade_id, marco) do update set situacao = excluded.situacao, data_referencia = excluded.data_referencia,
     observacao = excluded.observacao, registrado_por = excluded.registrado_por, registrado_em = now()
  returning id into v_id;
  perform privado.auditar(o.ies_id, 'vinculo.registrar', 'oportunidade', p_op::text,
    jsonb_build_object('marco', p_marco, 'situacao', p_situacao, 'anterior', anterior, 'data_referencia', p_data));
  return jsonb_build_object('id', v_id, 'marco', p_marco, 'situacao', p_situacao, 'correcao', anterior is not null);
end $$;

create or replace function public.rpc_onboarding_item(p_op bigint, p_item text, p_concluido boolean default true)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades;
begin
  perform privado.exigir_usuario();
  select * into o from public.oportunidades where id = p_op;
  if not found or not privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, array['gestor','reitoria','coordenador','secretaria']) then
    perform privado.erro_http(404, 'P0002', 'Não encontrado');
  end if;
  if not privado.tem_acesso(o.ies_id, o.curso_id, array['gestor','secretaria']) then raise exception 'Seu perfil não tem permissão para esta operação' using errcode = '42501'; end if;
  if o.etapa <> 'confirmado' then raise exception 'Onboarding só para ingressante efetivo' using errcode = '22023'; end if;
  if not exists (select 1 from public.ies i where i.id = o.ies_id and p_item = any (i.onboarding_modelo)) then raise exception 'Item fora do modelo de onboarding' using errcode = '22023'; end if;
  if p_concluido then
    insert into public.onboarding(ies_id, oportunidade_id, item, concluido_por) values (o.ies_id, p_op, p_item, (select auth.uid())) on conflict do nothing;
  else
    delete from public.onboarding where oportunidade_id = p_op and item = p_item;
  end if;
  perform privado.auditar(o.ies_id, 'onboarding.item', 'oportunidade', p_op::text, jsonb_build_object('item', p_item, 'concluido', p_concluido));
  return jsonb_build_object('item', p_item, 'concluido', p_concluido);
end $$;

create or replace function public.rpc_configurar_relacionamento(p_ies bigint, p_onboarding text[] default null, p_programa text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform privado.autorizar(p_ies, 'embaixador.gerir');
  if p_onboarding is not null and (cardinality(p_onboarding) not between 1 and 20 or exists (select 1 from unnest(p_onboarding) x where length(trim(x)) not between 3 and 200)) then
    raise exception 'Modelo de onboarding: de 1 a 20 itens, cada um com 3 a 200 caracteres' using errcode = '22023';
  end if;
  update public.ies set onboarding_modelo = coalesce(array(select trim(x) from unnest(p_onboarding) x), onboarding_modelo),
         programa_embaixadores = coalesce(nullif(trim(p_programa), ''), programa_embaixadores) where id = p_ies;
  perform privado.auditar(p_ies, 'relacionamento.configurar', 'ies', p_ies::text,
    jsonb_build_object('onboarding_itens', cardinality(p_onboarding), 'programa_atualizado', p_programa is not null));
  return jsonb_build_object('ok', true);
end $$;

-- Embaixador: ingressante efetivo, com regras publicadas e aceite registrado (data e versão das regras).
create or replace function public.rpc_salvar_embaixador(p_op bigint, p_aceite_em timestamptz, p_status text default 'ativo')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; regras text; v_id bigint;
begin
  perform privado.exigir_usuario();
  select * into o from public.oportunidades where id = p_op;
  if not found or not privado.ve_ies(o.ies_id) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(o.ies_id, 'embaixador.gerir');
  select programa_embaixadores into regras from public.ies where id = o.ies_id;
  if regras is null then raise exception 'Publique as regras do programa de embaixadores antes de cadastrar' using errcode = '22023'; end if;
  if o.etapa <> 'confirmado' then raise exception 'Embaixador precisa ser ingressante efetivo' using errcode = '22023'; end if;
  if p_aceite_em is null or p_aceite_em > now() then raise exception 'Registre a data do aceite das regras (não futura)' using errcode = '22023'; end if;
  insert into public.embaixadores(ies_id, oportunidade_id, status, aceite_regras_em, versao_regras, criado_por)
  values (o.ies_id, p_op, p_status, p_aceite_em, md5(regras), (select auth.uid()))
  on conflict (oportunidade_id) do update set status = excluded.status returning id into v_id;
  perform privado.auditar(o.ies_id, 'embaixador.salvar', 'oportunidade', p_op::text, jsonb_build_object('status', p_status));
  return jsonb_build_object('id', v_id);
end $$;

create or replace function public.rpc_criar_indicacao(p_ies bigint, p_dados jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id bigint; v_emb bigint := nullif(p_dados->>'embaixador_id', '')::bigint; v_nome text := trim(p_dados->>'indicador_nome');
begin
  perform privado.autorizar(p_ies, 'indicacao.gerir');
  if v_emb is not null then
    select p.nome into v_nome from public.embaixadores e join public.oportunidades o on o.id = e.oportunidade_id join public.pessoas p on p.id = o.pessoa_id
     where e.id = v_emb and e.ies_id = p_ies and e.status = 'ativo';
    if v_nome is null then raise exception 'Embaixador não encontrado ou inativo' using errcode = '22023'; end if;
  end if;
  insert into public.indicacoes(ies_id, codigo, indicador_tipo, indicador_nome, embaixador_id, criado_por)
  values (p_ies, lower(trim(p_dados->>'codigo')), case when v_emb is not null then 'embaixador' else p_dados->>'indicador_tipo' end, v_nome, v_emb, (select auth.uid()))
  returning id into v_id;
  perform privado.auditar(p_ies, 'indicacao.criar', 'ies', p_ies::text, jsonb_build_object('indicacao_id', v_id, 'tipo', coalesce(p_dados->>'indicador_tipo', 'embaixador')));
  return jsonb_build_object('id', v_id, 'codigo', lower(trim(p_dados->>'codigo')));
exception
  when unique_violation then perform privado.erro_http(409, '23505', 'Código de indicação já usado');
  when check_violation or not_null_violation then raise exception 'Indicação inválida: código (letras minúsculas, números e hífen, 4 a 41), tipo e nome do indicador' using errcode = '22023';
end $$;

-- ---------------------------------------------------------------- leitura e MAIM Retention
create or replace function public.rpc_relacionamento(p_ies bigint, p_coorte text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare papeis_ver text[]; modelo text[]; ind jsonb; alertas jsonb;
begin
  perform privado.autorizar(p_ies, 'relacionamento.ver');
  if p_coorte !~ '^\d{4}\.[12]$' then raise exception 'Coorte deve ter formato AAAA.1 ou AAAA.2' using errcode = '22023'; end if;
  papeis_ver := array['gestor','reitoria','coordenador','secretaria'];
  select onboarding_modelo into modelo from public.ies where id = p_ies;

  -- Permanência por marco (Bíblia §6): sem cobertura completa, oficial = N/D com motivo.
  select jsonb_agg(jsonb_build_object('marco', m.marco, 'elegiveis', m.eleg, 'registrados', m.reg, 'ativos', m.atv,
           'desconhecidos', m.eleg - m.reg, 'cobertura', case when m.eleg = 0 then null else round(m.reg::numeric / m.eleg, 4) end,
           'permanencia', case when m.eleg = 0 or m.reg < m.eleg then null else round(m.atv::numeric / m.eleg, 4) end,
           'minimo_observado', case when m.eleg = 0 then null else round(m.atv::numeric / m.eleg, 4) end,
           'motivo', case when m.eleg = 0 then 'Nenhum ingressante alcançou o marco.'
                          when m.reg < m.eleg then format('Cobertura incompleta: %s de %s elegíveis com vínculo registrado. Sem registro não se presume evasão.', m.reg, m.eleg) end)
           order by privado.dias_marco(m.marco))
    into ind
    from (select x.marco,
                 count(*) filter (where current_date >= o.confirmada_em::date + privado.dias_marco(x.marco)) as eleg,
                 count(v.id) filter (where current_date >= o.confirmada_em::date + privado.dias_marco(x.marco)) as reg,
                 count(v.id) filter (where v.situacao = 'ativo' and current_date >= o.confirmada_em::date + privado.dias_marco(x.marco)) as atv
            from (values ('d30'), ('d90'), ('rematricula')) x(marco)
            cross join public.oportunidades o
            left join public.vinculos v on v.oportunidade_id = o.id and v.marco = x.marco
           where o.ies_id = p_ies and o.coorte = p_coorte and o.etapa = 'confirmado' and privado.tem_acesso(o.ies_id, o.curso_id, papeis_ver)
           group by x.marco) m;

  -- retention-v1: registrar pendências, contato de permanência quando há risco declarado e base legal permite.
  select coalesce(jsonb_agg(a order by (a->>'prioridade')::int), '[]'::jsonb) into alertas from (
    select jsonb_build_object('regra', 'retention-v1/registro_pendente', 'prioridade', 1, 'titulo', 'Vínculos sem registro em marco alcançado',
             'quantidade', count(*), 'proposta', 'Secretaria: registrar a situação do vínculo (a ausência de registro não indica evasão).') as a
      from public.oportunidades o cross join (values ('d30'), ('d90'), ('rematricula')) x(marco)
     where o.ies_id = p_ies and o.coorte = p_coorte and o.etapa = 'confirmado' and privado.tem_acesso(o.ies_id, o.curso_id, papeis_ver)
       and current_date >= o.confirmada_em::date + privado.dias_marco(x.marco)
       and not exists (select 1 from public.vinculos v where v.oportunidade_id = o.id and v.marco = x.marco)
    union all
    select jsonb_build_object('regra', 'retention-v1/risco_declarado', 'prioridade', 1, 'titulo', 'Trancamento ou evasão registrados',
             'quantidade', count(*), 'proposta', 'Coordenação: contato de permanência quando a base legal permitir; registrar o resultado.')
      from public.vinculos v join public.oportunidades o on o.id = v.oportunidade_id
     where o.ies_id = p_ies and o.coorte = p_coorte and v.situacao in ('trancado','evadido') and privado.tem_acesso(o.ies_id, o.curso_id, papeis_ver)
    union all
    select jsonb_build_object('regra', 'retention-v1/rematricula', 'prioridade', 2, 'titulo', 'Rematrícula nos próximos 30 dias',
             'quantidade', count(*), 'proposta', 'Preparar a comunicação de rematrícula com a secretaria.')
      from public.oportunidades o
     where o.ies_id = p_ies and o.coorte = p_coorte and o.etapa = 'confirmado' and privado.tem_acesso(o.ies_id, o.curso_id, papeis_ver)
       and o.confirmada_em::date + 150 between current_date and current_date + 30
       and not exists (select 1 from public.vinculos v where v.oportunidade_id = o.id and v.marco = 'rematricula')
  ) z where (a->>'quantidade')::int > 0;

  return jsonb_build_object('coorte', p_coorte, 'regra', 'retention-v1',
    'pode_registrar', privado.pode(p_ies, 'relacionamento.registrar'), 'pode_gerir', privado.pode(p_ies, 'embaixador.gerir'),
    'pode_indicar', privado.pode(p_ies, 'indicacao.gerir'),
    'marcos', jsonb_build_object('d30', 30, 'd90', 90, 'rematricula', 150), 'onboarding_modelo', to_jsonb(modelo),
    'programa_embaixadores', (select programa_embaixadores from public.ies where id = p_ies),
    'permanencia', coalesce(ind, '[]'::jsonb), 'alertas', alertas,
    'ingressantes', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'nome', p.nome, 'curso', c.nome || ' · ' || c.turno, 'confirmada_em', o.confirmada_em,
        'dias_desde_ingresso', current_date - o.confirmada_em::date,
        'vinculos', (select coalesce(jsonb_object_agg(v.marco, jsonb_build_object('situacao', v.situacao, 'data', v.data_referencia, 'observacao', v.observacao,
                       'por', privado.nome_usuario(v.registrado_por))), '{}'::jsonb) from public.vinculos v where v.oportunidade_id = o.id),
        'onboarding', (select coalesce(jsonb_agg(b.item), '[]'::jsonb) from public.onboarding b where b.oportunidade_id = o.id),
        'embaixador', exists (select 1 from public.embaixadores e where e.oportunidade_id = o.id and e.status = 'ativo')) order by o.confirmada_em desc), '[]'::jsonb)
      from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id join public.cursos c on c.id = o.curso_id
     where o.ies_id = p_ies and o.coorte = p_coorte and o.etapa = 'confirmado' and privado.tem_acesso(o.ies_id, o.curso_id, papeis_ver)),
    'embaixadores', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'nome', p.nome, 'curso', c.nome, 'status', e.status, 'aceite_regras_em', e.aceite_regras_em,
        'regras_atuais', e.versao_regras = md5(coalesce((select programa_embaixadores from public.ies where id = p_ies), '')),
        'indicacoes', (select count(*) from public.oportunidades x join public.indicacoes i on i.id = x.indicacao_id where i.embaixador_id = e.id),
        'ingressantes_indicados', (select count(distinct x.pessoa_id) from public.oportunidades x join public.indicacoes i on i.id = x.indicacao_id where i.embaixador_id = e.id and x.etapa = 'confirmado'))
        order by p.nome), '[]'::jsonb)
      from public.embaixadores e join public.oportunidades o on o.id = e.oportunidade_id join public.pessoas p on p.id = o.pessoa_id join public.cursos c on c.id = o.curso_id
     where e.ies_id = p_ies and privado.tem_acesso(o.ies_id, o.curso_id, papeis_ver)),
    'indicacoes', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'codigo', i.codigo, 'indicador_tipo', i.indicador_tipo, 'indicador_nome', i.indicador_nome,
        'leads', (select count(*) from public.oportunidades x where x.indicacao_id = i.id),
        'ingressantes', (select count(distinct x.pessoa_id) from public.oportunidades x where x.indicacao_id = i.id and x.etapa = 'confirmado')) order by i.criado_em desc), '[]'::jsonb)
      from public.indicacoes i where i.ies_id = p_ies),
    'metodos', jsonb_build_object(
      'permanencia', 'Permanência = ingressantes elegíveis com vínculo ativo ÷ ingressantes elegíveis no marco (30, 90 ou 150 dias após a confirmação). Com qualquer elegível sem registro, o indicador oficial é N/D; o mínimo observado considera só os ativos registrados.',
      'indicacao', 'Indicação atribuída pelo código informado no cadastro do lead.'));
end $$;

-- Códigos de indicação para quem cadastra leads (comercial e gestor).
create or replace function public.rpc_indicacoes(p_ies bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.autorizar(p_ies, 'indicacao.gerir');
  return (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'codigo', i.codigo, 'indicador_tipo', i.indicador_tipo, 'indicador_nome', i.indicador_nome,
            'leads', (select count(*) from public.oportunidades x where x.indicacao_id = i.id)) order by i.criado_em desc), '[]'::jsonb)
    from public.indicacoes i where i.ies_id = p_ies and i.ativa);
end $$;

-- ---------------------------------------------------------------- cadastro com indicação rastreável
create or replace function public.rpc_criar_oportunidade(p_ies bigint, p_dados jsonb, p_chave text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_curso bigint := (p_dados->>'curso_id')::bigint;
  v_email text := nullif(lower(trim(p_dados->>'email')), '');
  v_tel text := nullif(regexp_replace(coalesce(p_dados->>'telefone', ''), '\D', '', 'g'), '');
  v_pessoa public.pessoas; v_op public.oportunidades; v_resp uuid; v_canal text; v_sla int; r jsonb; v_camp bigint; v_ind bigint;
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
  -- Atribuição de origem pelo código da campanha (Bíblia §7). Código informado e inexistente é recusado: não se perde atribuição em silêncio.
  if nullif(trim(coalesce(p_dados->>'campanha', '')), '') is not null then
    select id into v_camp from public.campanhas where ies_id = p_ies and codigo = lower(trim(p_dados->>'campanha')) and status <> 'cancelada';
    if v_camp is null then raise exception 'Campanha não encontrada: %', p_dados->>'campanha' using errcode = '22023'; end if;
  end if;
  -- Indicação rastreável pelo código (Bíblia §8). Código informado e inexistente é recusado.
  if nullif(trim(coalesce(p_dados->>'indicacao', '')), '') is not null then
    select id into v_ind from public.indicacoes where ies_id = p_ies and codigo = lower(trim(p_dados->>'indicacao')) and ativa;
    if v_ind is null then raise exception 'Indicação não encontrada: %', p_dados->>'indicacao' using errcode = '22023'; end if;
  end if;

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
  insert into public.oportunidades(ies_id, curso_id, pessoa_id, forma_ingresso, coorte, responsavel_id, campanha_id, indicacao_id)
  values (p_ies, v_curso, v_pessoa.id, p_dados->>'forma_ingresso', p_dados->>'coorte', v_resp, v_camp, v_ind) returning * into v_op;
  v_canal := case when not v_pessoa.optout_whatsapp and v_pessoa.telefone is not null then 'whatsapp'
                  when not v_pessoa.optout_email and v_pessoa.email is not null then 'email'
                  when not v_pessoa.optout_telefone and v_pessoa.telefone is not null then 'telefone' end;
  if v_canal is not null then
    select sla_horas into v_sla from public.ies where id = p_ies;
    insert into public.tarefas(ies_id, oportunidade_id, tipo, canal, responsavel_id, vence_em)
    values (p_ies, v_op.id, 'primeiro_contato', v_canal, v_resp, now() + make_interval(hours => v_sla));
  end if;
  perform privado.auditar(p_ies, 'oportunidade.criar', 'oportunidade', v_op.id::text,
    jsonb_build_object('curso_id', v_curso, 'forma_ingresso', v_op.forma_ingresso, 'coorte', v_op.coorte, 'origem', v_pessoa.origem, 'responsavel_id', v_resp, 'campanha_id', v_camp, 'indicacao_id', v_ind));
  return privado.idem_gravar(p_chave, 'criar_oportunidade', jsonb_build_object('id', v_op.id, 'duplicada', false, 'versao', 1, 'etapa', 'novo'));
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.rpc_registrar_vinculo(bigint, text, text, date, text), public.rpc_onboarding_item(bigint, text, boolean),
  public.rpc_configurar_relacionamento(bigint, text[], text), public.rpc_salvar_embaixador(bigint, timestamptz, text),
  public.rpc_criar_indicacao(bigint, jsonb), public.rpc_relacionamento(bigint, text), public.rpc_indicacoes(bigint),
  public.rpc_criar_oportunidade(bigint, jsonb, text)
to authenticated;

commit;
