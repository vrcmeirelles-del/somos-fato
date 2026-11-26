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
