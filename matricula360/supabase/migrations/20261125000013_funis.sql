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
