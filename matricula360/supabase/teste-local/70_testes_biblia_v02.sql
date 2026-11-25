-- Conformidade com a Bíblia-Mestra v0.2, §6 (migração 9).
\set ON_ERROR_STOP on
-- Cenário idêntico ao da captura R03, numa coorte isolada (2030.1): meta 16, 24 oportunidades, 2 ingressantes.
insert into public.pessoas(ies_id, nome, email, base_legal, origem)
  select 1, 'R03 ' || g, 'r03-' || g || '@exemplo.invalid', 'consentimento', 'teste R03' from generate_series(1, 24) g;
insert into public.oportunidades(ies_id, curso_id, pessoa_id, forma_ingresso, coorte, etapa, matricula_comercial_em, confirmada_em, val_documental, val_financeira, val_academica)
  select 1, 1, p.id, 'enem', '2030.1', case when n <= 2 then 'confirmado' else 'contato' end,
         case when n <= 2 then now() end, case when n <= 2 then now() end, n <= 2, n <= 2, n <= 2
    from (select id, row_number() over (order by id) n from public.pessoas where origem = 'teste R03') p;
insert into public.metas values (1, 1, '2030.1', 16);
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.ok((public.rpc_central(1, '2030.1')->'totais'->>'oportunidades_adicionais_projetadas') is null
                and (public.rpc_central(1, '2030.1')->'totais'->>'forecast_motivo') like 'Amostra insuficiente: 24 oportunidades (mínimo configurado: 30)%', 'amostra abaixo do mínimo padrão (30): N/D com motivo');
select public.rpc_configurar(1, null, null, null, null, 20);
select teste.ok((public.rpc_estrutura(1)->'ies'->>'amostra_minima_forecast')::int = 20, 'gestor configura a amostra mínima');
select teste.ok((public.rpc_central(1, '2030.1')->'totais'->>'oportunidades_adicionais_projetadas')::int = 168, 'R03: cenário da captura dá 168 (aritmética exata), não 169');
select teste.ok((public.rpc_bi(1, '2030.1')->'totais'->>'projecao_oportunidades_necessarias')::int = 168, 'R03: BI legado usa a mesma fórmula (168)');
select teste.ok((public.rpc_central(1, '2030.1')->'totais'->>'conversao')::numeric = round(2::numeric / 24, 4), 'D3: conversão = ingressantes ÷ oportunidades da coorte');
select teste.ok((public.rpc_central(1, '2030.1')->'totais'->>'meta_restante')::int = 14, 'meta restante = max(meta − ingressantes, 0)');
select teste.ok((public.rpc_central(1, '2030.1')->'totais'->'cenario_pipeline'->>'rotulo') like 'Cenário complementar%', 'D1: método por pipeline apenas como cenário identificado');
select teste.erro('select public.rpc_configurar(1, null, null, null, null, 0)', '23514', 'amostra mínima fora da faixa recusada');
reset role;
update public.metas set meta = 2 where ies_id = 1 and curso_id = 1 and coorte = '2030.1';
set role authenticated;
select teste.ok((public.rpc_central(1, '2030.1')->'totais'->>'oportunidades_adicionais_projetadas')::int = 0
                and (public.rpc_central(1, '2030.1')->'totais'->>'forecast_motivo') like 'Meta cumprida%', 'meta cumprida: necessidade adicional zero');
reset role;
update public.metas set meta = 16 where ies_id = 1 and curso_id = 1 and coorte = '2030.1';
update public.oportunidades set etapa = 'cancelado', cancelada_em = now() where coorte = '2030.1' and etapa = 'confirmado';
set role authenticated;
select teste.ok((public.rpc_central(1, '2030.1')->'totais'->>'oportunidades_adicionais_projetadas') is null
                and (public.rpc_central(1, '2030.1')->'totais'->>'forecast_motivo') like 'Conversão observada zero%', 'conversão zero: projeção indisponível (N/D), nunca zero');
-- D2: receita potencial = mensalidades ofertadas válidas
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.ok((public.rpc_central(1, '2027.1')->'totais'->>'receita_mensal_potencial_ofertada_centavos')::bigint
  = (select coalesce(sum(x.valor_final_centavos), 0) from public.propostas x join public.oportunidades o on o.id = x.oportunidade_id
      where o.ies_id = 1 and o.coorte = '2027.1' and o.etapa not in ('perdido','cancelado')
        and (x.status = 'aceita' or (x.status in ('aprovada','pendente_aprovacao') and x.validade >= now()))), 'D2: receita potencial = soma das mensalidades ofertadas válidas');
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro('select public.rpc_configurar(1, null, null, null, null, 25)', '42501', 'comercial não altera a amostra mínima');
reset role;
do $$ begin raise notice 'OK  fim da bateria de conformidade v0.2'; end $$;
