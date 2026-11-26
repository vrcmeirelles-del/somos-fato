-- Matrícula 360° — migração 31 (central de automações) para o SQL Editor do projeto jbimijcvvekomovodfze.
-- Requer as migrações 1 a 30. CONFIRA o projeto na URL antes de executar. Idempotente. Transação única. A última linha deve ser commit;
begin;
-- Matrícula 360° — migração 31: Central de automações (algoritmo determinístico, sem IA e sem custo).
--   Diretriz do responsável (26/11/2026): tudo o que pode ser feito por algoritmo e automação sem custo fica ativo; a IA entra
--   depois, só para ajuste fino. Nenhuma automação envia mensagem externa (integrações seguem desligadas) nem toma decisão
--   reservada a pessoas (admissão, bolsa, resultado). Cada regra é ligável por IES, com parâmetros, histórico e auditoria.
--   * Agendador: pg_cron (módulo do próprio banco Supabase) roda privado.executar_automacoes() de hora em hora.
--     Em banco sem pg_cron (teste local) a migração apenas não agenda; a execução manual continua disponível.
--   Regras (padrão entre parênteses):
--     ciclo_maim (ligada)            follow-ups por cadência, pendências de validação e redistribuição de tarefas sem dono
--     regua (ligada)                 régua de comunicação em modo simulação (gera a fila de mensagens; nada é enviado)
--     expirar_propostas (ligada)     marca como expiradas propostas aprovadas ou pendentes vencidas
--     rematricula (ligada)           inclui novos elegíveis nas campanhas abertas e encerra as que passaram do prazo
--     escalonar_casos (ligada)       caso sem responsável é roteado de novo; caso vencido há 24 h sobe para prioridade alta
--     casos_financeiros (ligada)     abre caso "financeiro" para aluno com pendência aberta vencida há N dias (padrão 30)
--     bloqueio_inadimplentes (DESLIGADA) bloqueia rematrícula pendente de inadimplente há N dias (afeta direito do aluno:
--                                    a gestão liga se quiser)
--     limpeza_tecnica (ligada)       apaga códigos de confirmação expirados
-- Idempotente.

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('automacao.ver',   'Governança Institucional', 'Ver a central de automações e o histórico de execuções', array['gestor','reitoria'], 'ies', 'rpc_automacoes'),
  ('automacao.gerir', 'Governança Institucional', 'Ligar, desligar, parametrizar e executar automações', array['gestor'], 'ies', 'rpc_configurar_automacao')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

create table if not exists public.automacoes (
  ies_id bigint not null references public.ies(id),
  codigo text not null check (codigo in ('ciclo_maim','regua','expirar_propostas','rematricula','escalonar_casos','casos_financeiros','bloqueio_inadimplentes','limpeza_tecnica')),
  ativa boolean not null,
  parametros jsonb not null default '{}'::jsonb,
  ultima_execucao timestamptz,
  ultimo_resultado jsonb,
  alterada_por uuid references public.usuarios(id),
  alterada_em timestamptz,
  primary key (ies_id, codigo)
);
create table if not exists public.automacoes_execucoes (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  origem text not null check (origem in ('agendador','manual')),
  inicio timestamptz not null default now(),
  fim timestamptz,
  resultado jsonb,
  erro text
);
create index if not exists automacoes_alterada on public.automacoes(alterada_por);
create index if not exists autom_exec_ies on public.automacoes_execucoes(ies_id, inicio desc);
alter table public.automacoes enable row level security;
alter table public.automacoes_execucoes enable row level security;
revoke all on public.automacoes, public.automacoes_execucoes from anon, authenticated;
do $$ begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'privado' and p.proname = 'mfa_ok') then
    execute 'drop policy if exists mfa_obrigatorio on public.automacoes; create policy mfa_obrigatorio on public.automacoes as restrictive for all to authenticated using ((select privado.mfa_ok()))';
    execute 'drop policy if exists mfa_obrigatorio on public.automacoes_execucoes; create policy mfa_obrigatorio on public.automacoes_execucoes as restrictive for all to authenticated using ((select privado.mfa_ok()))';
  end if;
end $$;

-- casos abertos pela automação ficam identificados
alter table public.casos drop constraint if exists casos_origem_check;
alter table public.casos add constraint casos_origem_check check (origem in ('equipe','rematricula','automacao'));

create or replace function privado.automacoes_padrao(p_ies bigint) returns void
language sql security definer set search_path = '' as $$
  insert into public.automacoes(ies_id, codigo, ativa, parametros) values
    (p_ies, 'ciclo_maim', true, '{}'), (p_ies, 'regua', true, '{}'), (p_ies, 'expirar_propostas', true, '{}'),
    (p_ies, 'rematricula', true, '{}'), (p_ies, 'escalonar_casos', true, '{"horas_vencido": 24}'),
    (p_ies, 'casos_financeiros', true, '{"dias_atraso": 30}'), (p_ies, 'bloqueio_inadimplentes', false, '{"dias_atraso": 60}'),
    (p_ies, 'limpeza_tecnica', true, '{}')
  on conflict (ies_id, codigo) do nothing;
$$;
select privado.automacoes_padrao(id) from public.ies;
create or replace function privado.ies_automacoes() returns trigger language plpgsql security definer set search_path = '' as $$
begin perform privado.automacoes_padrao(new.id); return new; end $$;
drop trigger if exists ies_automacoes on public.ies;
create trigger ies_automacoes after insert on public.ies for each row execute function privado.ies_automacoes();

-- ---------------------------------------------------------------- regras (sem usuário: o agendador roda como sistema)
create or replace function privado.auto_ciclo_maim(p_ies bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare cfg public.ies; o record; v_canal text; n_follow int; c_follow int := 0; c_supr int := 0; c_lim int := 0; c_pend int := 0; c_redis int := 0;
begin
  select * into cfg from public.ies where id = p_ies for update;
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
   where op.ies_id = p_ies and op.etapa = 'matricula_comercial' and not (op.val_documental and op.val_financeira and op.val_academica)
     and not exists (select 1 from public.tarefas t where t.oportunidade_id = op.id and t.status = 'aberta' and t.tipo = 'pendencia_validacao');
  get diagnostics c_pend = row_count;
  with orfas as (
    select t.id, privado.distribuir(p_ies, op.curso_id) as resp from public.tarefas t join public.oportunidades op on op.id = t.oportunidade_id
     where t.ies_id = p_ies and t.status = 'aberta' and t.responsavel_id is null and t.tipo <> 'pendencia_validacao')
  update public.tarefas t set responsavel_id = orfas.resp from orfas where t.id = orfas.id and orfas.resp is not null;
  get diagnostics c_redis = row_count;
  return jsonb_build_object('follow_ups', c_follow, 'suprimidos_optout', c_supr, 'limite_atingido', c_lim, 'pendencias_validacao', c_pend, 'redistribuidas', c_redis);
end $$;

create or replace function privado.auto_regua(p_ies bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare m public.modelos_mensagem; o record; bloq text; n_sim int := 0; n_bloq int := 0;
begin
  for m in select * from public.modelos_mensagem where ies_id = p_ies and ativo and gatilho <> 'manual' loop
    for o in select x.id from public.oportunidades x where x.ies_id = p_ies
               and ((m.gatilho like 'etapa_%' and x.etapa = substr(m.gatilho, 7))
                 or (m.gatilho = 'documento_pendente' and x.etapa in ('pre_matricula','matricula_comercial') and not privado.checklist_completo(x.id))
                 or (m.gatilho = 'evento_inscrito' and exists (select 1 from public.inscricoes_evento i join public.eventos e on e.id = i.evento_id
                                                                where i.oportunidade_id = x.id and i.status = 'inscrito' and e.inicio > now())))
               and not exists (select 1 from public.mensagens g where g.oportunidade_id = x.id and g.modelo_id = m.id) limit 500 loop
      bloq := privado.bloqueio_canal(o.id, m.canal);
      insert into public.mensagens(ies_id, oportunidade_id, modelo_id, canal, destino_mascarado, corpo, status, motivo)
      select p_ies, o.id, m.id, m.canal, case when m.canal = 'email' then privado.mascarar_email(p.email) else privado.mascarar_tel(p.telefone) end,
             privado.render(m.corpo, o.id), case when bloq is null then 'simulada' else 'bloqueada' end,
             coalesce(bloq, 'Modo simulação (automação): integração de ' || m.canal || ' desligada')
        from public.oportunidades x join public.pessoas p on p.id = x.pessoa_id where x.id = o.id;
      if bloq is null then n_sim := n_sim + 1; else n_bloq := n_bloq + 1; end if;
    end loop;
  end loop;
  return jsonb_build_object('simuladas', n_sim, 'bloqueadas', n_bloq);
end $$;

create or replace function privado.auto_expirar_propostas(p_ies bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  update public.propostas set status = 'expirada' where ies_id = p_ies and status in ('aprovada','pendente_aprovacao') and validade < now();
  get diagnostics n = row_count;
  return jsonb_build_object('expiradas', n);
end $$;

create or replace function privado.auto_rematricula(p_ies bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c public.campanhas_rematricula; novos int := 0; n int; enc int := 0;
begin
  for c in select * from public.campanhas_rematricula where ies_id = p_ies and status = 'aberta' loop
    if c.fecha_em < current_date then
      update public.campanhas_rematricula set status = 'encerrada' where id = c.id; enc := enc + 1;
    else
      insert into public.rematriculas(ies_id, campanha_id, oportunidade_id) select c.ies_id, c.id, e from privado.elegiveis_rematricula(c) e
      on conflict (campanha_id, oportunidade_id) do nothing;
      get diagnostics n = row_count; novos := novos + n;
    end if;
  end loop;
  return jsonb_build_object('novos_elegiveis', novos, 'campanhas_encerradas', enc);
end $$;

create or replace function privado.auto_escalonar_casos(p_ies bigint, p_horas int) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c record; rot int := 0; esc int := 0; resp uuid;
begin
  for c in select x.*, o.curso_id, t.papel_responsavel from public.casos x join public.oportunidades o on o.id = x.oportunidade_id
            left join public.trilhas_intervencao t on t.id = x.trilha_id
            where x.ies_id = p_ies and x.status in ('aberto','em_atendimento') loop
    if c.responsavel_id is null and c.papel_responsavel is not null then
      resp := privado.rotear_caso(p_ies, c.curso_id, c.papel_responsavel);
      if resp is not null then
        update public.casos set responsavel_id = resp where id = c.id;
        insert into public.casos_eventos(caso_id, tipo, texto) values (c.id, 'encaminhamento', 'Roteado automaticamente para ' || privado.nome_usuario(resp));
        rot := rot + 1;
      end if;
    end if;
    if c.prazo < now() - make_interval(hours => p_horas) and c.prioridade <> 'alta' then
      update public.casos set prioridade = 'alta' where id = c.id;
      insert into public.casos_eventos(caso_id, tipo, texto) values (c.id, 'nota', 'Prioridade elevada automaticamente: prazo vencido há mais de ' || p_horas || ' h');
      esc := esc + 1;
    end if;
  end loop;
  return jsonb_build_object('roteados', rot, 'escalonados', esc);
end $$;

create or replace function privado.auto_casos_financeiros(p_ies bigint, p_dias int) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; n int := 0;
begin
  for o in select x.* from public.oportunidades x where x.ies_id = p_ies and x.etapa = 'confirmado'
            and exists (select 1 from public.pendencias_financeiras f where f.oportunidade_id = x.id and f.situacao = 'aberta' and f.vencimento < current_date - p_dias)
            and not exists (select 1 from public.casos k where k.oportunidade_id = x.id and k.motivo = 'financeiro' and k.status in ('aberto','em_atendimento')) loop
    perform privado.abrir_caso(o, 'financeiro', 'automacao', 'media',
      'Aberto pela automação: pendência financeira aberta vencida há mais de ' || p_dias || ' dias. Oferecer negociação, bolsas e financiamento vigentes.', null);
    n := n + 1;
  end loop;
  return jsonb_build_object('casos_abertos', n);
end $$;

create or replace function privado.auto_bloqueio_inadimplentes(p_ies bigint, p_dias int) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  update public.rematriculas r set status = 'bloqueada', bloqueio_categoria = 'financeiro', atualizado_em = now(),
    motivo = 'Bloqueio automático: pendência financeira vencida há mais de ' || p_dias || ' dias'
   from public.campanhas_rematricula c
   where c.id = r.campanha_id and c.ies_id = p_ies and c.status = 'aberta' and r.status = 'pendente'
     and exists (select 1 from public.pendencias_financeiras f where f.oportunidade_id = r.oportunidade_id and f.situacao = 'aberta' and f.vencimento < current_date - p_dias);
  get diagnostics n = row_count;
  return jsonb_build_object('bloqueadas', n);
end $$;

create or replace function privado.auto_limpeza(p_ies bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  delete from public.codigos_aceite where ies_id = p_ies and expira_em < now() - interval '1 day';
  get diagnostics n = row_count;
  return jsonb_build_object('codigos_expirados_apagados', n);
end $$;

-- Executa as regras ativas de uma IES (ou de todas). Cada regra isolada: erro em uma não impede as outras.
create or replace function privado.executar_automacoes(p_ies bigint default null, p_origem text default 'agendador') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare i record; a public.automacoes; r jsonb; tudo jsonb := '{}'::jsonb; por_ies jsonb; ex bigint; mudou boolean;
begin
  for i in select id from public.ies where status = 'ativa' and (p_ies is null or id = p_ies) loop
    perform privado.automacoes_padrao(i.id);
    insert into public.automacoes_execucoes(ies_id, origem) values (i.id, p_origem) returning id into ex;
    por_ies := '{}'::jsonb; mudou := false;
    for a in select * from public.automacoes where ies_id = i.id and ativa order by codigo loop
      begin
        r := case a.codigo
          when 'ciclo_maim' then privado.auto_ciclo_maim(i.id)
          when 'regua' then privado.auto_regua(i.id)
          when 'expirar_propostas' then privado.auto_expirar_propostas(i.id)
          when 'rematricula' then privado.auto_rematricula(i.id)
          when 'escalonar_casos' then privado.auto_escalonar_casos(i.id, coalesce((a.parametros->>'horas_vencido')::int, 24))
          when 'casos_financeiros' then privado.auto_casos_financeiros(i.id, coalesce((a.parametros->>'dias_atraso')::int, 30))
          when 'bloqueio_inadimplentes' then privado.auto_bloqueio_inadimplentes(i.id, coalesce((a.parametros->>'dias_atraso')::int, 60))
          when 'limpeza_tecnica' then privado.auto_limpeza(i.id) end;
      exception when others then r := jsonb_build_object('erro', sqlerrm);
      end;
      update public.automacoes set ultima_execucao = now(), ultimo_resultado = r where ies_id = i.id and codigo = a.codigo;
      por_ies := por_ies || jsonb_build_object(a.codigo, r);
      if exists (select 1 from jsonb_each(r) e where e.key = 'erro' or (jsonb_typeof(e.value) = 'number' and (e.value)::text <> '0')) then mudou := true; end if;
    end loop;
    update public.automacoes_execucoes set fim = now(), resultado = por_ies where id = ex;
    if mudou or p_origem = 'manual' then perform privado.auditar(i.id, 'automacao.executar', 'ies', i.id::text, jsonb_build_object('origem', p_origem, 'resultado', por_ies)); end if;
    tudo := tudo || jsonb_build_object(i.id::text, por_ies);
  end loop;
  delete from public.automacoes_execucoes where inicio < now() - interval '90 days';
  return tudo;
end $$;
revoke execute on function privado.automacoes_padrao(bigint), privado.ies_automacoes(), privado.auto_ciclo_maim(bigint), privado.auto_regua(bigint),
  privado.auto_expirar_propostas(bigint), privado.auto_rematricula(bigint), privado.auto_escalonar_casos(bigint, int), privado.auto_casos_financeiros(bigint, int),
  privado.auto_bloqueio_inadimplentes(bigint, int), privado.auto_limpeza(bigint), privado.executar_automacoes(bigint, text) from public, anon, authenticated;

-- ---------------------------------------------------------------- RPCs da gestão
create or replace function public.rpc_automacoes(p_ies bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform privado.autorizar(p_ies, 'automacao.ver');
  perform privado.automacoes_padrao(p_ies);
  return jsonb_build_object('pode_gerir', privado.pode(p_ies, 'automacao.gerir'),
    'agendador', exists (select 1 from pg_extension where extname = 'pg_cron'),
    'aviso', 'Automações determinísticas, sem IA e sem envio externo. Decisões reservadas a pessoas (admissão, bolsa, resultado) não são automatizadas.',
    'regras', (select coalesce(jsonb_agg(jsonb_build_object('codigo', a.codigo, 'ativa', a.ativa, 'parametros', a.parametros, 'ultima_execucao', a.ultima_execucao,
        'ultimo_resultado', a.ultimo_resultado, 'alterada_por', privado.nome_usuario(a.alterada_por), 'alterada_em', a.alterada_em) order by a.codigo), '[]'::jsonb)
      from public.automacoes a where a.ies_id = p_ies),
    'execucoes', (select coalesce(jsonb_agg(jsonb_build_object('origem', e.origem, 'inicio', e.inicio, 'fim', e.fim, 'resultado', e.resultado) order by e.inicio desc), '[]'::jsonb)
      from (select * from public.automacoes_execucoes where ies_id = p_ies order by inicio desc limit 20) e));
end $$;

create or replace function public.rpc_configurar_automacao(p_ies bigint, p_codigo text, p_ativa boolean, p_parametros jsonb default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v text;
begin
  perform privado.autorizar(p_ies, 'automacao.gerir');
  perform privado.automacoes_padrao(p_ies);
  if p_parametros is not null then
    for v in select jsonb_object_keys(p_parametros) loop
      if v not in ('dias_atraso','horas_vencido') or jsonb_typeof(p_parametros->v) <> 'number' or (p_parametros->>v)::int not between 1 and 365 then
        raise exception 'Parâmetro inválido: %', v using errcode = '22023'; end if;
    end loop;
  end if;
  update public.automacoes set ativa = p_ativa, parametros = coalesce(p_parametros, parametros), alterada_por = (select auth.uid()), alterada_em = now()
   where ies_id = p_ies and codigo = p_codigo;
  if not found then perform privado.erro_http(404, 'P0002', 'Automação não encontrada'); end if;
  perform privado.auditar(p_ies, 'automacao.configurar', 'ies', p_ies::text, jsonb_build_object('codigo', p_codigo, 'ativa', p_ativa, 'parametros', p_parametros));
  return jsonb_build_object('codigo', p_codigo, 'ativa', p_ativa);
end $$;

create or replace function public.rpc_executar_automacoes(p_ies bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform privado.autorizar(p_ies, 'automacao.gerir');
  return privado.executar_automacoes(p_ies, 'manual')->(p_ies::text);
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.rpc_automacoes(bigint), public.rpc_configurar_automacao(bigint, text, boolean, jsonb), public.rpc_executar_automacoes(bigint) to authenticated;
select privado.conceder_publico();

-- ---------------------------------------------------------------- agendamento (pg_cron, de hora em hora no minuto 17)
do $$ begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron with schema pg_catalog;
    perform cron.schedule('m360-automacoes', '17 * * * *', 'select privado.executar_automacoes()');
  else
    raise notice 'pg_cron indisponível neste banco: automações só por execução manual.';
  end if;
end $$;

commit;
