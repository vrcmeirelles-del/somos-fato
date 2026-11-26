-- Matrícula 360° — migração 32 (BI da alta gestão) para o SQL Editor do projeto jbimijcvvekomovodfze.
-- Requer as migrações 1 a 31. CONFIRA o projeto na URL antes de executar. Idempotente. Transação única. A última linha deve ser commit;
begin;
-- Matrícula 360° — migração 32: BI da alta gestão (reitoria e mantenedora).
--   * Visão consolidada de todas as IES em que a pessoa tem papel de gestor ou reitoria com abrangência da instituição, e por IES.
--   * Ciclo completo por coorte, comparado à coorte anterior: captação (reaproveita os cálculos da Central: conversão, projeção,
--     custo por lead e por ingressante, receita), receita e descontos, bolsas (renúncia estimada), eficiência (payback do custo de
--     aquisição), retenção (permanência e rematrícula), inadimplência, casos do aluno e NPS.
--   * Alertas executivos por regra fixa (sem IA), com limites documentados. Só números agregados: nenhum dado pessoal.
--   * Correção: o histórico das automações passa a registrar início e fim reais (clock_timestamp).
-- Idempotente.

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('bi.executivo', 'Central de Inteligência', 'BI da alta gestão: consolidado das instituições e ciclo completo', array['gestor','reitoria'], 'ies', 'rpc_bi_executivo')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

create or replace function privado.coorte_anterior(p text) returns text
language sql immutable set search_path = '' as $$
  select case when right(p, 1) = '2' then left(p, 4) || '.1' else (left(p, 4)::int - 1)::text || '.2' end
$$;
revoke execute on function privado.coorte_anterior(text) from public, anon, authenticated;

-- Indicadores de uma IES numa coorte (além dos da Central).
create or replace function privado.bi_ies(p_ies bigint, p_coorte text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r jsonb; cheia bigint; final bigint; n_prop int; ingr int; benef int; renuncia bigint; aprov int;
  alunos int; inad int; camp public.campanhas_rematricula; remat jsonb; casos jsonb; nps jsonb; q public.pesquisas; res jsonb;
begin
  select coalesce(sum(pr.mensalidade_centavos), 0), coalesce(sum(pr.valor_final_centavos), 0), count(*) into cheia, final, n_prop
    from public.propostas pr join public.oportunidades o on o.id = pr.oportunidade_id
   where o.ies_id = p_ies and o.coorte = p_coorte and o.etapa = 'confirmado' and pr.status = 'aceita';
  select count(*) into ingr from public.oportunidades where ies_id = p_ies and coorte = p_coorte and etapa = 'confirmado';
  select count(distinct s.oportunidade_id), coalesce(sum(round(c.mensalidade_centavos * s.percentual / 100)), 0), count(*)
    into benef, renuncia, aprov
    from public.solicitacoes_bolsa s join public.oportunidades o on o.id = s.oportunidade_id join public.cursos c on c.id = o.curso_id
   where o.ies_id = p_ies and o.coorte = p_coorte and s.status = 'aprovada' and o.etapa = 'confirmado';
  select count(*) into alunos from public.oportunidades where ies_id = p_ies and etapa = 'confirmado';
  select count(distinct f.oportunidade_id) into inad from public.pendencias_financeiras f join public.oportunidades o on o.id = f.oportunidade_id
   where o.ies_id = p_ies and o.etapa = 'confirmado' and f.situacao = 'aberta' and f.vencimento < current_date - 30;
  select * into camp from public.campanhas_rematricula where ies_id = p_ies and status in ('aberta','encerrada') order by periodo desc limit 1;
  if found then
    select jsonb_build_object('periodo', camp.periodo, 'status', camp.status, 'meta_pct', camp.meta_pct, 'elegiveis', count(*),
      'aceitas', count(*) filter (where r.status = 'aceita'), 'recusadas', count(*) filter (where r.status = 'recusada'),
      'taxa_pct', case when count(*) = 0 then null else round(100.0 * count(*) filter (where r.status = 'aceita') / count(*), 1) end)
      into remat from public.rematriculas r where r.campanha_id = camp.id;
  end if;
  select jsonb_build_object('abertos', count(*) filter (where status in ('aberto','em_atendimento')),
      'vencidos', count(*) filter (where status in ('aberto','em_atendimento') and prazo < now()),
      'resolvidos', count(*) filter (where status = 'resolvido'),
      'horas_medias_resolucao', round(avg(extract(epoch from encerrado_em - aberto_em) / 3600) filter (where status = 'resolvido'), 1))
    into casos from public.casos where ies_id = p_ies;
  for q in select * from public.pesquisas where ies_id = p_ies and status in ('ativa','encerrada') order by criado_em desc loop
    res := privado.resultado_pesquisa(q);
    if (res->>'suficiente')::boolean and res->'nps' <> 'null'::jsonb then
      nps := jsonb_build_object('pesquisa', q.nome, 'publico', q.publico, 'nps', res->'nps', 'respostas', res->'respostas'); exit;
    end if;
  end loop;
  return jsonb_build_object(
    'receita', jsonb_build_object('propostas_aceitas', n_prop,
      'ticket_medio_centavos', case when n_prop = 0 then null else round(final::numeric / n_prop) end,
      'desconto_medio_pct', case when cheia = 0 then null else round(100.0 * (cheia - final) / cheia, 1) end),
    'bolsas', jsonb_build_object('beneficios_aprovados', aprov, 'ingressos_com_beneficio', benef,
      'ingressos_com_beneficio_pct', case when ingr = 0 then null else round(100.0 * benef / ingr, 1) end, 'renuncia_mensal_estimada_centavos', renuncia),
    'inadimplencia', jsonb_build_object('alunos', alunos, 'inadimplentes', inad, 'pct', case when alunos = 0 then null else round(100.0 * inad / alunos, 1) end),
    'rematricula', remat, 'casos', casos, 'nps', nps);
end $$;
revoke execute on function privado.bi_ies(bigint, text) from public, anon, authenticated;

create or replace function public.rpc_bi_executivo(p_coorte text, p_ies bigint[] default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_ies bigint[]; i bigint; ant text := privado.coorte_anterior(p_coorte); c jsonb; cp jsonb; extra jsonb; perm jsonb; item jsonb; lista jsonb := '[]'::jsonb;
  alertas jsonb; tot jsonb; n_meta int; payback numeric;
begin
  perform privado.exigir_usuario();
  if p_coorte !~ '^\d{4}\.[12]$' then raise exception 'Coorte deve ter formato AAAA.1 ou AAAA.2' using errcode = '22023'; end if;
  select array_agg(x.id order by x.nome) into v_ies from public.ies x
   where x.status = 'ativa' and privado.tem_acesso_ies(x.id, array['gestor','reitoria']) and (p_ies is null or x.id = any (p_ies));
  if v_ies is null then raise exception 'O BI da alta gestão exige papel de gestor ou reitoria com abrangência da instituição' using errcode = '42501'; end if;
  foreach i in array v_ies loop
    c := public.rpc_central(i, p_coorte)->'totais';
    cp := public.rpc_central(i, ant)->'totais';
    extra := privado.bi_ies(i, p_coorte);
    begin perm := public.rpc_relacionamento(i, p_coorte)->'permanencia'; exception when others then perm := null; end;
    payback := case when (c->>'custo_por_matricula_centavos') is null or (extra->'receita'->>'ticket_medio_centavos') is null
                      or (extra->'receita'->>'ticket_medio_centavos')::numeric = 0 then null
                    else round((c->>'custo_por_matricula_centavos')::numeric / (extra->'receita'->>'ticket_medio_centavos')::numeric, 1) end;
    alertas := '[]'::jsonb;
    if (c->>'atingimento') is not null and (c->>'atingimento')::numeric < 0.6 then
      alertas := alertas || jsonb_build_object('nivel', 'critico', 'texto', format('Atingimento da meta em %s%%: abaixo de 60%%', round((c->>'atingimento')::numeric * 100)));
    elsif (c->>'atingimento') is not null and (c->>'atingimento')::numeric < 0.8 then
      alertas := alertas || jsonb_build_object('nivel', 'atencao', 'texto', format('Atingimento da meta em %s%%: abaixo de 80%%', round((c->>'atingimento')::numeric * 100)));
    end if;
    if (c->>'meta') is null then alertas := alertas || jsonb_build_object('nivel', 'atencao', 'texto', 'Coorte sem meta cadastrada: atingimento N/D'); end if;
    if (extra->'inadimplencia'->>'pct') is not null and (extra->'inadimplencia'->>'pct')::numeric > 10 then
      alertas := alertas || jsonb_build_object('nivel', 'atencao', 'texto', format('Inadimplência de %s%% (acima de 10%%)', extra->'inadimplencia'->>'pct')); end if;
    if coalesce((extra->'casos'->>'vencidos')::int, 0) > 0 then
      alertas := alertas || jsonb_build_object('nivel', 'atencao', 'texto', format('%s caso(s) do aluno com prazo vencido', extra->'casos'->>'vencidos')); end if;
    if extra->'rematricula' is not null and (extra->'rematricula'->>'meta_pct') is not null and (extra->'rematricula'->>'taxa_pct') is not null
       and (extra->'rematricula'->>'taxa_pct')::numeric < (extra->'rematricula'->>'meta_pct')::numeric then
      alertas := alertas || jsonb_build_object('nivel', 'atencao', 'texto', format('Rematrícula %s em %s%%, abaixo da meta de %s%%', extra->'rematricula'->>'periodo',
        extra->'rematricula'->>'taxa_pct', extra->'rematricula'->>'meta_pct')); end if;
    if (extra->'receita'->>'desconto_medio_pct') is not null and (extra->'receita'->>'desconto_medio_pct')::numeric > 25 then
      alertas := alertas || jsonb_build_object('nivel', 'atencao', 'texto', format('Desconto médio de %s%% sobre a mensalidade (acima de 25%%)', extra->'receita'->>'desconto_medio_pct')); end if;
    if payback is not null and payback > 6 then
      alertas := alertas || jsonb_build_object('nivel', 'atencao', 'texto', format('Custo de aquisição equivale a %s mensalidades (acima de 6)', payback)); end if;
    if extra->'nps' is not null and (extra->'nps'->>'nps')::numeric < 0 then
      alertas := alertas || jsonb_build_object('nivel', 'atencao', 'texto', format('NPS negativo (%s) na pesquisa "%s"', extra->'nps'->>'nps', extra->'nps'->>'pesquisa')); end if;
    item := jsonb_build_object('ies_id', i, 'nome', (select nome from public.ies where id = i), 'atual', c, 'anterior', cp,
      'payback_mensalidades', payback, 'permanencia', perm, 'alertas', alertas) || extra;
    lista := lista || jsonb_build_array(item);
  end loop;
  select count(*) filter (where x->'atual'->>'meta' is not null) into n_meta from jsonb_array_elements(lista) x;
  select jsonb_build_object(
      'oportunidades', sum((x->'atual'->>'oportunidades')::int), 'matriculas_comerciais', sum((x->'atual'->>'matriculas_comerciais')::int),
      'ingressantes', sum((x->'atual'->>'ingressantes')::int), 'cancelamentos', sum((x->'atual'->>'cancelamentos')::int),
      'meta', case when n_meta = jsonb_array_length(lista) then sum((x->'atual'->>'meta')::int) end,
      'receita_mensal_ingressantes_centavos', sum((x->'atual'->>'receita_mensal_ingressantes_centavos')::bigint),
      'renuncia_mensal_estimada_centavos', sum((x->'bolsas'->>'renuncia_mensal_estimada_centavos')::bigint),
      'anterior_oportunidades', sum((x->'anterior'->>'oportunidades')::int), 'anterior_ingressantes', sum((x->'anterior'->>'ingressantes')::int),
      'anterior_receita_mensal_ingressantes_centavos', sum((x->'anterior'->>'receita_mensal_ingressantes_centavos')::bigint),
      'alunos', sum((x->'inadimplencia'->>'alunos')::int), 'inadimplentes', sum((x->'inadimplencia'->>'inadimplentes')::int),
      'casos_abertos', sum(coalesce((x->'casos'->>'abertos')::int, 0)), 'casos_vencidos', sum(coalesce((x->'casos'->>'vencidos')::int, 0)),
      'alertas', sum(jsonb_array_length(x->'alertas')))
    into tot from jsonb_array_elements(lista) x;
  tot := tot || jsonb_build_object(
    'atingimento', case when (tot->>'meta') is null or (tot->>'meta')::int = 0 then null else round((tot->>'ingressantes')::numeric / (tot->>'meta')::int, 4) end,
    'inadimplencia_pct', case when (tot->>'alunos')::int = 0 then null else round(100.0 * (tot->>'inadimplentes')::int / (tot->>'alunos')::int, 1) end);
  return jsonb_build_object('coorte', p_coorte, 'coorte_anterior', ant, 'consolidado', tot, 'ies', lista,
    'metodos', jsonb_build_object(
      'captacao', 'Oportunidades, matrículas, ingressos, conversão, projeção, custo por lead e por ingressante e receita: mesmos cálculos da Central de Inteligência, por IES.',
      'consolidado', 'Contagens e valores somados entre as IES. Meta e atingimento consolidados só quando todas as IES têm meta; taxas recalculadas sobre as somas, nunca média de percentuais.',
      'desconto', 'Desconto médio = 1 − (soma dos valores finais ÷ soma das mensalidades) das propostas aceitas dos ingressos da coorte.',
      'renuncia', 'Renúncia estimada = soma de (mensalidade de tabela do curso × percentual da bolsa aprovada) dos ingressos da coorte. Estimativa mensal; não considera a interação com o desconto da proposta.',
      'payback', 'Payback = custo por ingressante ÷ ticket médio mensal (quantas mensalidades pagam a aquisição).',
      'inadimplencia', 'Inadimplência = alunos com pendência aberta vencida há mais de 30 dias ÷ alunos com ingresso efetivo (todas as coortes).',
      'alertas', 'Regras fixas: atingimento < 60% (crítico) ou < 80%; sem meta; inadimplência > 10%; casos vencidos; rematrícula abaixo da meta; desconto médio > 25%; payback > 6 mensalidades; NPS negativo.'));
end $$;

-- Executa as regras ativas de uma IES (ou de todas). Cada regra isolada: erro em uma não impede as outras.
create or replace function privado.executar_automacoes(p_ies bigint default null, p_origem text default 'agendador') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare i record; a public.automacoes; r jsonb; tudo jsonb := '{}'::jsonb; por_ies jsonb; ex bigint; mudou boolean;
begin
  for i in select id from public.ies where status = 'ativa' and (p_ies is null or id = p_ies) loop
    perform privado.automacoes_padrao(i.id);
    insert into public.automacoes_execucoes(ies_id, origem, inicio) values (i.id, p_origem, clock_timestamp()) returning id into ex;
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
    update public.automacoes_execucoes set fim = clock_timestamp(), resultado = por_ies where id = ex;
    if mudou or p_origem = 'manual' then perform privado.auditar(i.id, 'automacao.executar', 'ies', i.id::text, jsonb_build_object('origem', p_origem, 'resultado', por_ies)); end if;
    tudo := tudo || jsonb_build_object(i.id::text, por_ies);
  end loop;
  delete from public.automacoes_execucoes where inicio < now() - interval '90 days';
  return tudo;
end $$;
revoke execute on function privado.executar_automacoes(bigint, text) from public, anon, authenticated;
alter table public.automacoes_execucoes alter column inicio set default clock_timestamp();

revoke execute on all functions in schema public from public, anon;
grant execute on function public.rpc_bi_executivo(text, bigint[]) to authenticated;
select privado.conceder_publico();

commit;
