-- Matrícula 360° — migrações 1 a 6 consolidadas para colar no SQL Editor do Supabase (instalação NOVA, banco vazio).
-- Executar UMA vez, inteiro. Tudo roda numa única transação.
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

commit;
