-- Matrícula 360° — migração 17 (Relacionamento Estudantil) para o SQL Editor do projeto jbimijcvvekomovodfze.
-- Requer as migrações anteriores. CONFIRA o projeto na URL antes de executar. Idempotente. Transação única. A última linha deve ser commit;
begin;
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
