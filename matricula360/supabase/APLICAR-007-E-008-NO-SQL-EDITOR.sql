-- Matrícula 360° — migrações 7 (correções da Fase 2, com saneamento auditado) e 8 (Central de Inteligência).
-- Para o SQL Editor do projeto jbimijcvvekomovodfze. Idempotente. Transação única: se algo falhar, nada fica gravado.
begin;
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
commit;
