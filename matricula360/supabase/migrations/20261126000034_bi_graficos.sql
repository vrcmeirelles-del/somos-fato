-- Matrícula 360° — migração 34: gráficos do BI da alta gestão (inclui os ajustes da migração 33; pode ser aplicada com ou sem ela).
--   * Série das últimas 4 coortes (oportunidades, ingressos e meta), evolução semanal, funil, origem e curso (dados da Central),
--     motivos de perda da coorte, faixas de atraso da inadimplência, casos abertos por motivo e bolsas aprovadas por programa.
--   * Ticket médio na base da receita da Central e alertas com uma casa decimal (ajustes da migração 33).
-- Só números agregados. Idempotente.

create or replace function privado.bi_graficos(p_ies bigint, p_coorte text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare cs text[] := array[p_coorte]; k int; serie jsonb := '[]'::jsonb; x text;
begin
  for k in 1..3 loop cs := array_prepend(privado.coorte_anterior(cs[1]), cs); end loop;
  foreach x in array cs loop
    serie := serie || jsonb_build_array(jsonb_build_object('coorte', x,
      'oportunidades', (select count(*) from public.oportunidades where ies_id = p_ies and coorte = x),
      'ingressantes', (select count(*) from public.oportunidades where ies_id = p_ies and coorte = x and etapa = 'confirmado'),
      'meta', (select sum(meta) from public.metas where ies_id = p_ies and coorte = x)));
  end loop;
  return jsonb_build_object('serie_coortes', serie,
    'perdas', (select coalesce(jsonb_agg(jsonb_build_object('motivo', m, 'quantidade', n) order by n desc, m), '[]'::jsonb) from (
        select coalesce(nullif(trim(motivo_perda), ''), 'Não informado') m, count(*) n from public.oportunidades
         where ies_id = p_ies and coorte = p_coorte and etapa = 'perdido' group by 1 order by 2 desc limit 8) z),
    'aging', (select jsonb_agg(jsonb_build_object('faixa', f.faixa, 'quantidade', coalesce(z.n, 0), 'valor_centavos', coalesce(z.v, 0)) order by f.ordem) from
        (values (1, 'até 30 dias'), (2, '31 a 60 dias'), (3, '61 a 90 dias'), (4, 'mais de 90 dias')) f(ordem, faixa)
        left join (select case when current_date - p.vencimento <= 30 then 1 when current_date - p.vencimento <= 60 then 2 when current_date - p.vencimento <= 90 then 3 else 4 end ordem,
                          count(*) n, sum(p.valor_centavos) v
                     from public.pendencias_financeiras p join public.oportunidades o on o.id = p.oportunidade_id
                    where o.ies_id = p_ies and p.situacao = 'aberta' and p.vencimento < current_date group by 1) z on z.ordem = f.ordem),
    'casos_motivo', (select coalesce(jsonb_agg(jsonb_build_object('motivo', motivo, 'quantidade', n) order by n desc), '[]'::jsonb) from (
        select motivo, count(*) n from public.casos where ies_id = p_ies and status in ('aberto','em_atendimento') group by motivo) z),
    'bolsas_programa', (select coalesce(jsonb_agg(jsonb_build_object('programa', g.nome, 'tipo', g.tipo, 'aprovadas', z.n, 'renuncia_centavos', z.r) order by z.r desc), '[]'::jsonb) from (
        select s.programa_id, count(*) n, sum(round(c.mensalidade_centavos * s.percentual / 100)) r from public.solicitacoes_bolsa s
          join public.oportunidades o on o.id = s.oportunidade_id join public.cursos c on c.id = o.curso_id
         where o.ies_id = p_ies and o.coorte = p_coorte and s.status = 'aprovada' group by s.programa_id) z join public.programas_bolsa g on g.id = z.programa_id));
end $$;
revoke execute on function privado.bi_graficos(bigint, text) from public, anon, authenticated;

create or replace function public.rpc_bi_executivo(p_coorte text, p_ies bigint[] default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare cen jsonb; v_ies bigint[]; i bigint; ant text := privado.coorte_anterior(p_coorte); c jsonb; cp jsonb; extra jsonb; perm jsonb; item jsonb; lista jsonb := '[]'::jsonb;
  alertas jsonb; tot jsonb; n_meta int; payback numeric;
begin
  perform privado.exigir_usuario();
  if p_coorte !~ '^\d{4}\.[12]$' then raise exception 'Coorte deve ter formato AAAA.1 ou AAAA.2' using errcode = '22023'; end if;
  select array_agg(x.id order by x.nome) into v_ies from public.ies x
   where x.status = 'ativa' and privado.tem_acesso_ies(x.id, array['gestor','reitoria']) and (p_ies is null or x.id = any (p_ies));
  if v_ies is null then raise exception 'O BI da alta gestão exige papel de gestor ou reitoria com abrangência da instituição' using errcode = '42501'; end if;
  foreach i in array v_ies loop
    cen := public.rpc_central(i, p_coorte); c := cen->'totais';
    cp := public.rpc_central(i, ant)->'totais';
    extra := privado.bi_ies(i, p_coorte);
    -- ticket médio na mesma base da receita da Central (receita mensal dos ingressos ÷ ingressos)
    extra := jsonb_set(extra, '{receita,ticket_medio_centavos}', case when coalesce((c->>'ingressantes')::int, 0) = 0 then 'null'::jsonb
               else to_jsonb(round((c->>'receita_mensal_ingressantes_centavos')::numeric / (c->>'ingressantes')::int)) end);
    begin perm := public.rpc_relacionamento(i, p_coorte)->'permanencia'; exception when others then perm := null; end;
    payback := case when (c->>'custo_por_matricula_centavos') is null or (extra->'receita'->>'ticket_medio_centavos') is null
                      or (extra->'receita'->>'ticket_medio_centavos')::numeric = 0 then null
                    else round((c->>'custo_por_matricula_centavos')::numeric / (extra->'receita'->>'ticket_medio_centavos')::numeric, 1) end;
    alertas := '[]'::jsonb;
    if (c->>'atingimento') is not null and (c->>'atingimento')::numeric < 0.6 then
      alertas := alertas || jsonb_build_object('nivel', 'critico', 'texto', format('Atingimento da meta em %s%%: abaixo de 60%%', round((c->>'atingimento')::numeric * 100, 1)));
    elsif (c->>'atingimento') is not null and (c->>'atingimento')::numeric < 0.8 then
      alertas := alertas || jsonb_build_object('nivel', 'atencao', 'texto', format('Atingimento da meta em %s%%: abaixo de 80%%', round((c->>'atingimento')::numeric * 100, 1)));
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
      'payback_mensalidades', payback, 'permanencia', perm, 'alertas', alertas,
      'graficos', jsonb_build_object('evolucao', cen->'evolucao', 'funil', cen->'funil', 'por_origem', cen->'por_origem', 'por_curso', cen->'por_curso',
        'por_campanha', cen->'por_campanha') || privado.bi_graficos(i, p_coorte)) || extra;
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
      'ticket', 'Ticket médio = receita mensal dos ingressos ÷ ingressos (mesma base da Central).',
      'payback', 'Payback = custo por ingressante ÷ ticket médio mensal (quantas mensalidades pagam a aquisição).',
      'inadimplencia', 'Inadimplência = alunos com pendência aberta vencida há mais de 30 dias ÷ alunos com ingresso efetivo (todas as coortes).',
      'alertas', 'Regras fixas: atingimento < 60% (crítico) ou < 80%; sem meta; inadimplência > 10%; casos vencidos; rematrícula abaixo da meta; desconto médio > 25%; payback > 6 mensalidades; NPS negativo.'));
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.rpc_bi_executivo(text, bigint[]) to authenticated;
select privado.conceder_publico();
