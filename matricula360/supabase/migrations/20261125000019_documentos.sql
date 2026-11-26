-- Matrícula 360° — migração 19 (P4): documentos protegidos com checklist (L3; Bíblia §4 "documentos protegidos").
--   * Checklist por forma de ingresso (modelo inicial próprio, editável).
--   * Envio pelo candidato (portal, por token) ou pela equipe; tipo conferido pelo conteúdo (PDF, JPEG, PNG); até 3 MB;
--     SHA-256 registrado; nova versão substitui a anterior sem apagá-la.
--   * Conteúdo em tabela separada, sem leitura direta; download só por RPC, para secretaria/gestão, sempre auditado.
--   * Revisão (aprovar/recusar com motivo) por secretaria/gestão. Exigência de checklist aprovado antes da validação
--     documental é LIGÁVEL por instituição (ies.exigir_documentos), para não alterar o fluxo atual sem decisão.
--   * Trade-off registrado: arquivos no banco (plano Free: 500 MB). Migração futura para o Storage quando houver
--     autorização para função de servidor.
-- Idempotente.

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('documento.ver',     'Conversão e Matrículas', 'Ver checklist e situação dos documentos',            array['gestor','secretaria','comercial','financeiro'], 'curso', 'rpc_documentos'),
  ('documento.enviar',  'Conversão e Matrículas', 'Enviar documento em nome do candidato',             array['gestor','secretaria','comercial'], 'curso', 'rpc_enviar_documento'),
  ('documento.revisar', 'Conversão e Matrículas', 'Baixar, aprovar ou recusar documento (auditado)',   array['gestor','secretaria'], 'curso', 'rpc_revisar_documento'),
  ('documento.config',  'Governança Institucional', 'Configurar checklist e a exigência de documentos', array['gestor'], 'ies', 'rpc_configurar_documentos')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

alter table public.ies add column if not exists exigir_documentos boolean not null default false;

create table if not exists public.documentos_exigidos (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  forma_ingresso text check (forma_ingresso in ('vestibular','enem','transferencia','segunda_graduacao','reingresso','indicacao','convenio','visita_escolar','evento','pos_graduacao')),
  tipo text not null check (tipo ~ '^[a-z0-9_]{3,40}$'),
  descricao text not null check (length(descricao) between 3 and 200),
  obrigatorio boolean not null default true,
  ativo boolean not null default true,
  unique nulls not distinct (ies_id, forma_ingresso, tipo)
);
create table if not exists public.documentos (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  oportunidade_id bigint not null references public.oportunidades(id),
  tipo text not null,
  nome_arquivo text not null check (length(nome_arquivo) between 1 and 200),
  mime text not null check (mime in ('application/pdf','image/jpeg','image/png')),
  tamanho int not null check (tamanho between 1 and 3145728),
  sha256 text not null,
  enviado_por_tipo text not null check (enviado_por_tipo in ('candidato','equipe')),
  enviado_por uuid references public.usuarios(id),
  enviado_em timestamptz not null default now(),
  status text not null default 'enviado' check (status in ('enviado','aprovado','recusado','substituido')),
  motivo_recusa text check (length(motivo_recusa) <= 300),
  revisado_por uuid references public.usuarios(id),
  revisado_em timestamptz
);
create table if not exists public.documentos_conteudo (
  documento_id bigint primary key references public.documentos(id),
  conteudo bytea not null
);
create index if not exists doc_exig_ies on public.documentos_exigidos(ies_id);
create index if not exists documentos_op on public.documentos(oportunidade_id, tipo);
create index if not exists documentos_ies on public.documentos(ies_id);
create index if not exists documentos_enviado on public.documentos(enviado_por);
create index if not exists documentos_revisado on public.documentos(revisado_por);
alter table public.documentos_exigidos enable row level security;
alter table public.documentos enable row level security;
alter table public.documentos_conteudo enable row level security;
revoke all on public.documentos_exigidos, public.documentos, public.documentos_conteudo from anon, authenticated;

create or replace function privado.criar_documentos_padrao(p_ies bigint) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.documentos_exigidos where ies_id = p_ies) then return; end if;
  insert into public.documentos_exigidos(ies_id, forma_ingresso, tipo, descricao, obrigatorio) values
    (p_ies, null, 'identidade', 'Documento de identidade com foto e CPF', true),
    (p_ies, null, 'ensino_medio', 'Certificado de conclusão e histórico do ensino médio', true),
    (p_ies, null, 'residencia', 'Comprovante de residência recente', false),
    (p_ies, 'enem', 'boletim_enem', 'Boletim de desempenho do ENEM', true),
    (p_ies, 'transferencia', 'historico_origem', 'Histórico da instituição de origem', true),
    (p_ies, 'transferencia', 'planos_ensino', 'Planos de ensino das disciplinas cursadas', false),
    (p_ies, 'segunda_graduacao', 'diploma', 'Diploma de graduação registrado', true);
end $$;
revoke execute on function privado.criar_documentos_padrao(bigint) from public, anon, authenticated;
select privado.criar_documentos_padrao(id) from public.ies;
create or replace function privado.ies_documentos_padrao() returns trigger
language plpgsql security definer set search_path = '' as $$ begin perform privado.criar_documentos_padrao(new.id); return new; end $$;
revoke execute on function privado.ies_documentos_padrao() from public, anon, authenticated;
drop trigger if exists ies_cria_documentos on public.ies;
create trigger ies_cria_documentos after insert on public.ies for each row execute function privado.ies_documentos_padrao();

-- Checklist da oportunidade: itens gerais + itens da forma de ingresso, com o documento vigente de cada tipo.
create or replace function privado.checklist(p_op bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('tipo', e.tipo, 'descricao', e.descricao, 'obrigatorio', e.obrigatorio,
           'documento', (select jsonb_build_object('id', d.id, 'nome_arquivo', d.nome_arquivo, 'mime', d.mime, 'tamanho', d.tamanho, 'status', d.status,
                            'motivo_recusa', d.motivo_recusa, 'enviado_em', d.enviado_em, 'enviado_por_tipo', d.enviado_por_tipo)
                          from public.documentos d where d.oportunidade_id = o.id and d.tipo = e.tipo and d.status <> 'substituido' order by d.id desc limit 1))
           order by e.obrigatorio desc, e.id), '[]'::jsonb)
    from public.oportunidades o join public.documentos_exigidos e on e.ies_id = o.ies_id and e.ativo and (e.forma_ingresso is null or e.forma_ingresso = o.forma_ingresso)
   where o.id = p_op;
$$;
revoke execute on function privado.checklist(bigint) from public, anon, authenticated;

create or replace function privado.checklist_completo(p_op bigint) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(bool_and((i->'documento'->>'status') = 'aprovado'), true)
    from jsonb_array_elements(privado.checklist(p_op)) i where (i->>'obrigatorio')::boolean;
$$;
revoke execute on function privado.checklist_completo(bigint) from public, anon, authenticated;

-- Grava o arquivo (comum a candidato e equipe). Valida tipo pelo conteúdo, tamanho e o item do checklist.
create or replace function privado.gravar_documento(p_op bigint, p_tipo text, p_nome text, p_base64 text, p_origem text, p_por uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; b bytea; v_mime text; v_id bigint;
begin
  select * into o from public.oportunidades where id = p_op;
  if o.etapa in ('perdido','cancelado') then raise exception 'Inscrição encerrada: não recebe documentos' using errcode = '22023'; end if;
  if not exists (select 1 from jsonb_array_elements(privado.checklist(p_op)) i where i->>'tipo' = p_tipo) then
    raise exception 'Documento fora do checklist desta inscrição' using errcode = '22023';
  end if;
  begin b := decode(p_base64, 'base64'); exception when others then raise exception 'Arquivo inválido' using errcode = '22023'; end;
  if length(b) = 0 or length(b) > 3145728 then raise exception 'Arquivo vazio ou acima de 3 MB' using errcode = '22023'; end if;
  v_mime := case when substring(b from 1 for 4) = '\x25504446'::bytea then 'application/pdf'
                 when substring(b from 1 for 3) = '\xffd8ff'::bytea then 'image/jpeg'
                 when substring(b from 1 for 8) = '\x89504e470d0a1a0a'::bytea then 'image/png' end;
  if v_mime is null then raise exception 'Formato não aceito: envie PDF, JPG ou PNG' using errcode = '22023'; end if;
  update public.documentos set status = 'substituido' where oportunidade_id = p_op and tipo = p_tipo and status in ('enviado','recusado','aprovado');
  insert into public.documentos(ies_id, oportunidade_id, tipo, nome_arquivo, mime, tamanho, sha256, enviado_por_tipo, enviado_por)
  values (o.ies_id, p_op, p_tipo, left(regexp_replace(coalesce(p_nome, 'documento'), '[^\w.\- ]', '_', 'g'), 200), v_mime, length(b), encode(sha256(b), 'hex'), p_origem, p_por)
  returning id into v_id;
  insert into public.documentos_conteudo(documento_id, conteudo) values (v_id, b);
  perform privado.auditar(o.ies_id, 'documento.enviar', 'oportunidade', p_op::text, jsonb_build_object('documento_id', v_id, 'tipo', p_tipo, 'origem', p_origem, 'tamanho', length(b)));
  return jsonb_build_object('id', v_id, 'status', 'enviado', 'mime', v_mime);
end $$;
revoke execute on function privado.gravar_documento(bigint, text, text, text, text, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- portal (anon, por token)
create or replace function public.rpc_publico_portal_documentos(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.pessoas;
begin
  p := privado.portal_pessoa(p_token);
  return (select coalesce(jsonb_agg(jsonb_build_object('oportunidade_id', o.id, 'curso', c.nome || ' · ' || c.turno, 'coorte', o.coorte, 'checklist', privado.checklist(o.id)) order by o.id), '[]'::jsonb)
    from public.oportunidades o join public.cursos c on c.id = o.curso_id where o.pessoa_id = p.id and o.etapa not in ('perdido','cancelado'));
end $$;

create or replace function public.rpc_publico_enviar_documento(p_token text, p_op bigint, p_tipo text, p_nome text, p_base64 text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.pessoas;
begin
  p := privado.portal_pessoa(p_token);
  if not exists (select 1 from public.oportunidades where id = p_op and pessoa_id = p.id) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if (select count(*) from public.documentos where oportunidade_id = p_op and enviado_em > now() - interval '1 hour') >= 20 then
    perform privado.erro_http(429, '54000', 'Muitos envios em pouco tempo. Tente mais tarde.');
  end if;
  return privado.gravar_documento(p_op, p_tipo, p_nome, p_base64, 'candidato', null);
end $$;

-- ---------------------------------------------------------------- equipe
create or replace function public.rpc_documentos(p_op bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare o public.oportunidades;
begin
  perform privado.exigir_usuario();
  select * into o from public.oportunidades where id = p_op;
  if not found or not privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, (select papeis from public.matriz_permissoes where operacao = 'documento.ver')) then
    perform privado.erro_http(404, 'P0002', 'Não encontrado');
  end if;
  return jsonb_build_object('checklist', privado.checklist(p_op), 'completo', privado.checklist_completo(p_op),
    'exigido_para_validar', (select exigir_documentos from public.ies where id = o.ies_id),
    'pode_revisar', privado.tem_acesso(o.ies_id, o.curso_id, (select papeis from public.matriz_permissoes where operacao = 'documento.revisar')),
    'historico', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'tipo', d.tipo, 'nome_arquivo', d.nome_arquivo, 'status', d.status, 'enviado_em', d.enviado_em,
                    'enviado_por', coalesce(privado.nome_usuario(d.enviado_por), d.enviado_por_tipo), 'revisado_por', privado.nome_usuario(d.revisado_por),
                    'motivo_recusa', d.motivo_recusa, 'sha256', d.sha256) order by d.id desc), '[]'::jsonb) from public.documentos d where d.oportunidade_id = p_op));
end $$;

create or replace function public.rpc_enviar_documento(p_op bigint, p_tipo text, p_nome text, p_base64 text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades;
begin
  o := privado.carregar_op(p_op, (select papeis from public.matriz_permissoes where operacao = 'documento.enviar'));
  return privado.gravar_documento(p_op, p_tipo, p_nome, p_base64, 'equipe', (select auth.uid()));
end $$;

create or replace function public.rpc_baixar_documento(p_documento bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare d public.documentos; o public.oportunidades;
begin
  perform privado.exigir_usuario();
  select * into d from public.documentos where id = p_documento;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  select * into o from public.oportunidades where id = d.oportunidade_id;
  if not privado.tem_acesso(o.ies_id, o.curso_id, (select papeis from public.matriz_permissoes where operacao = 'documento.revisar')) then
    perform privado.erro_http(404, 'P0002', 'Não encontrado');
  end if;
  perform privado.auditar(o.ies_id, 'documento.baixar', 'oportunidade', o.id::text, jsonb_build_object('documento_id', d.id, 'tipo', d.tipo));
  return jsonb_build_object('nome_arquivo', d.nome_arquivo, 'mime', d.mime, 'base64', (select encode(conteudo, 'base64') from public.documentos_conteudo where documento_id = d.id));
end $$;

create or replace function public.rpc_revisar_documento(p_documento bigint, p_status text, p_motivo text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare d public.documentos; o public.oportunidades;
begin
  perform privado.exigir_usuario();
  select * into d from public.documentos where id = p_documento for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  select * into o from public.oportunidades where id = d.oportunidade_id;
  if not privado.tem_acesso(o.ies_id, o.curso_id, (select papeis from public.matriz_permissoes where operacao = 'documento.revisar')) then
    perform privado.erro_http(404, 'P0002', 'Não encontrado');
  end if;
  if d.status <> 'enviado' then raise exception 'Só documento aguardando revisão pode ser revisado' using errcode = '22023'; end if;
  if p_status not in ('aprovado','recusado') then raise exception 'Decisão inválida' using errcode = '22023'; end if;
  if p_status = 'recusado' and length(coalesce(trim(p_motivo), '')) < 5 then raise exception 'Informe ao candidato o motivo da recusa' using errcode = '22023'; end if;
  update public.documentos set status = p_status, motivo_recusa = case when p_status = 'recusado' then trim(p_motivo) end,
         revisado_por = (select auth.uid()), revisado_em = now() where id = p_documento;
  perform privado.auditar(o.ies_id, 'documento.revisar', 'oportunidade', o.id::text, jsonb_build_object('documento_id', d.id, 'tipo', d.tipo, 'status', p_status));
  return jsonb_build_object('id', p_documento, 'status', p_status, 'checklist_completo', privado.checklist_completo(o.id));
end $$;

create or replace function public.rpc_configurar_documentos(p_ies bigint, p_exigir boolean default null, p_item jsonb default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform privado.autorizar(p_ies, 'documento.config');
  if p_exigir is not null then update public.ies set exigir_documentos = p_exigir where id = p_ies; end if;
  if p_item is not null then
    insert into public.documentos_exigidos(ies_id, forma_ingresso, tipo, descricao, obrigatorio, ativo)
    values (p_ies, nullif(p_item->>'forma_ingresso', ''), lower(trim(p_item->>'tipo')), trim(p_item->>'descricao'),
            coalesce((p_item->>'obrigatorio')::boolean, true), coalesce((p_item->>'ativo')::boolean, true))
    on conflict (ies_id, forma_ingresso, tipo) do update set descricao = excluded.descricao, obrigatorio = excluded.obrigatorio, ativo = excluded.ativo;
  end if;
  perform privado.auditar(p_ies, 'documentos.configurar', 'ies', p_ies::text, jsonb_build_object('exigir', p_exigir, 'item', p_item->>'tipo'));
  return jsonb_build_object('exigir_documentos', (select exigir_documentos from public.ies where id = p_ies),
    'itens', (select coalesce(jsonb_agg(jsonb_build_object('tipo', e.tipo, 'forma_ingresso', e.forma_ingresso, 'descricao', e.descricao, 'obrigatorio', e.obrigatorio, 'ativo', e.ativo) order by e.forma_ingresso nulls first, e.id), '[]'::jsonb)
              from public.documentos_exigidos e where e.ies_id = p_ies));
exception when check_violation or not_null_violation then
  raise exception 'Item inválido: tipo (letras minúsculas, números e _), descrição e forma de ingresso válida' using errcode = '22023';
end $$;

-- Validação documental "válida" exige checklist obrigatório aprovado, quando a instituição liga a exigência.
create or replace function privado.validacao_exige_documentos() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.dimensao = 'documental' and new.resultado = 'valida'
     and (select i.exigir_documentos from public.oportunidades o join public.ies i on i.id = o.ies_id where o.id = new.oportunidade_id)
     and not privado.checklist_completo(new.oportunidade_id) then
    raise exception 'Validação documental exige todos os documentos obrigatórios aprovados' using errcode = '22023';
  end if;
  return new;
end $$;
revoke execute on function privado.validacao_exige_documentos() from public, anon, authenticated;
drop trigger if exists validacao_documentos on public.validacoes;
create trigger validacao_documentos before insert on public.validacoes for each row execute function privado.validacao_exige_documentos();

revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.rpc_documentos(bigint), public.rpc_enviar_documento(bigint, text, text, text), public.rpc_baixar_documento(bigint),
  public.rpc_revisar_documento(bigint, text, text), public.rpc_configurar_documentos(bigint, boolean, jsonb)
to authenticated;
select privado.conceder_publico();
