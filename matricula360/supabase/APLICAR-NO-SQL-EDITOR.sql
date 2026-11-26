-- Matrícula 360° — migrações 1 a 12 consolidadas (instalação NOVA, banco vazio). Transação única.
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

commit;
