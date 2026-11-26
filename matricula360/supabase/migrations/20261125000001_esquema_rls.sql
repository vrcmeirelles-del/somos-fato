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
