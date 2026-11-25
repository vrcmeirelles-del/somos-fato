-- Matrícula 360° — migração 7 (correções da Fase 2) para colar no SQL Editor do projeto jbimijcvvekomovodfze.
-- Inclui saneamento auditado dos dados existentes. Idempotente. Transação única.
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
commit;
