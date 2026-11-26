-- Testes da central de automações (migração 31). Execução direta da função do agendador (como o pg_cron faria).
\set ON_ERROR_STOP on
reset role;
create temp table au (chave text primary key, v text);
grant all on au to anon, authenticated;
select teste.ok((select count(*) = 8 and count(*) filter (where not ativa) = 1 and bool_and(ativa or codigo = 'bloqueio_inadimplentes')
                 from public.automacoes where ies_id = 1), 'IES com 8 regras; só o bloqueio de inadimplentes nasce desligado');
-- cenário: proposta vencida, caso sem responsável e vencido, pendência antiga (ing1 já tem de 70 dias, migração 30)
insert into public.propostas(ies_id, oportunidade_id, desconto_pct, mensalidade_centavos, valor_final_centavos, validade, status, criado_por)
  select o.ies_id, o.id, 5, 100000, 95000, now() - interval '1 day', 'aprovada', teste.id('comercial_a')
    from public.oportunidades o where o.ies_id = 1 and o.etapa in ('contato','inscrito') and not exists (select 1 from public.propostas p where p.oportunidade_id = o.id and p.status in ('aprovada','pendente_aprovacao')) order by o.id limit 1;
insert into au select 'prop', max(id)::text from public.propostas where status = 'aprovada' and validade < now();
insert into public.casos(ies_id, oportunidade_id, motivo, origem, prioridade, descricao, trilha_id, prazo)
  select 1, (select v from teste.var where k = 'ing2'), 'desempenho', 'equipe', 'baixa', 'Caso sem responsável e vencido', t.id, now() - interval '30 hours'
    from public.trilhas_intervencao t where t.ies_id = 1 and t.motivo = 'desempenho';
insert into au select 'caso', max(id)::text from public.casos where descricao = 'Caso sem responsável e vencido';
update public.casos set status = 'resolvido', encerrado_em = now() where oportunidade_id = (select v from teste.var where k = 'ing1') and motivo = 'financeiro' and status in ('aberto','em_atendimento');

-- execução pelo agendador
insert into au select 'r', privado.executar_automacoes(1, 'agendador')::text;
select teste.ok((select status = 'expirada' from public.propostas where id = (select v::bigint from au where chave = 'prop')), 'proposta vencida expirada pela automação');
select teste.ok((select responsavel_id is not null and prioridade = 'alta' from public.casos where id = (select v::bigint from au where chave = 'caso')), 'caso sem dono roteado e vencido escalonado para alta');
select teste.ok((select count(*) = 1 and bool_and(origem = 'automacao') from public.casos where oportunidade_id = (select v from teste.var where k = 'ing1') and motivo = 'financeiro' and status = 'aberto'),
  'pendência vencida há mais de 30 dias abre caso financeiro identificado como automação');
select teste.ok((select (v::jsonb->'1'->'ciclo_maim') ? 'follow_ups' and (v::jsonb->'1'->'regua') ? 'simuladas' and not (v::jsonb->'1') ? 'bloqueio_inadimplentes' from au where chave = 'r'),
  'regras ativas executadas; a desligada não roda');
select teste.ok((select count(*) = 0 from public.mensagens where status = 'enviada'), 'automação não envia nada (só simulação)');
-- idempotência: segunda execução não duplica
insert into au select 'r2', privado.executar_automacoes(1, 'agendador')::text;
select teste.ok((select count(*) = 1 from public.casos where oportunidade_id = (select v from teste.var where k = 'ing1') and motivo = 'financeiro' and status = 'aberto'), 'segunda execução não duplica caso');
select teste.ok((select (v::jsonb->'1'->'expirar_propostas'->>'expiradas')::int = 0 from au where chave = 'r2'), 'segunda execução não reexpira');
select teste.ok((select count(*) >= 2 and bool_and(fim is not null) from public.automacoes_execucoes where ies_id = 1), 'execuções registradas com início e fim');
select teste.ok((select count(*) >= 1 from public.auditoria where acao = 'automacao.executar'), 'execução com efeito é auditada');

-- gestão das regras
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro($q$select public.rpc_automacoes(1)$q$, '42501', 'comercial não vê automações');
select set_config('request.jwt.claim.sub', teste.id('reitoria_a')::text, false);
select teste.ok((select jsonb_array_length(r->'regras') = 8 and not (r->>'pode_gerir')::boolean from (select public.rpc_automacoes(1) r) x), 'reitoria vê as regras sem poder mudar');
select teste.erro($q$select public.rpc_configurar_automacao(1, 'bloqueio_inadimplentes', true)$q$, '42501', 'reitoria não liga automação');
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.erro($q$select public.rpc_configurar_automacao(1, 'bloqueio_inadimplentes', true, '{"dias_atraso": 0}')$q$, '22023', 'parâmetro fora do intervalo recusado');
select teste.erro($q$select public.rpc_configurar_automacao(1, 'nao_existe', true)$q$, 'P0002', 'automação inexistente: 404');
select teste.ok((public.rpc_configurar_automacao(1, 'bloqueio_inadimplentes', true, '{"dias_atraso": 30}')->>'ativa')::boolean, 'gestor liga o bloqueio automático com 30 dias');
reset role;
-- campanha aberta com ing1 pendente para o bloqueio automático agir
insert into public.campanhas_rematricula(ies_id, periodo, abre_em, fecha_em, termo, status) values (1, '2029.1', current_date - 1, current_date + 10, repeat('Termo de rematrícula do período 2029.1. ', 4), 'aberta');
insert into public.rematriculas(ies_id, campanha_id, oportunidade_id) select 1, c.id, (select v from teste.var where k = 'ing1') from public.campanhas_rematricula c where c.periodo = '2029.1' and c.ies_id = 1;
set role authenticated;
select teste.ok((select (r->'bloqueio_inadimplentes'->>'bloqueadas')::int >= 1 from (select public.rpc_executar_automacoes(1) r) x), 'execução manual pelo gestor aplica o bloqueio ligado');
reset role;
select teste.ok((select r.status = 'bloqueada' and r.motivo like 'Bloqueio automático%' from public.rematriculas r join public.campanhas_rematricula c on c.id = r.campanha_id
                 where c.periodo = '2029.1' and r.oportunidade_id = (select v from teste.var where k = 'ing1')), 'rematrícula bloqueada com motivo automático');
-- campanha vencida é encerrada
update public.campanhas_rematricula set fecha_em = current_date - 1, abre_em = current_date - 5 where periodo = '2029.1' and ies_id = 1;
select privado.executar_automacoes(1);
select teste.ok((select status = 'encerrada' from public.campanhas_rematricula where periodo = '2029.1' and ies_id = 1), 'campanha vencida encerrada pela automação');
select teste.ok((select count(*) = 1 from public.auditoria where acao = 'automacao.configurar'), 'mudança de regra auditada');
update public.automacoes set ativa = false where codigo = 'bloqueio_inadimplentes';
