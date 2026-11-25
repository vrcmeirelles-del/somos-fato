-- Testes das RPCs complementares (migração 3). Roda depois de 20_testes_rls.sql, na IES 1 (Alfa).
\set ON_ERROR_STOP on

-- ============ configuração e metas
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro('select public.rpc_configurar(1, 4)', '42501', 'comercial não altera configuração');
select teste.erro('select public.rpc_definir_meta(1, 1, ''2027.1'', 99)', '42501', 'comercial não define meta');
select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false);
select teste.erro('select public.rpc_definir_meta(1, 2, ''2027.1'', 99)', 'P0002', 'coordenador não alcança curso alheio');
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.erro('select public.rpc_configurar(1)', '22023', 'configuração vazia recusada');
select teste.erro('select public.rpc_configurar(1, 500)', '23514', 'SLA fora da faixa recusado pelo banco');
select teste.ok((public.rpc_configurar(1, 4, 2)->>'sla_horas')::int = 4, 'gestor altera SLA');
select teste.ok((public.rpc_definir_meta(1, 1, '2028.1', 0)->>'meta')::int = 0, 'gestor define meta zero');
select teste.ok((public.rpc_bi(1, '2028.1')->'totais'->>'atingimento') is null, 'meta zero => atingimento N/D, não infinito');
select teste.erro('select public.rpc_definir_meta(2, 3, ''2027.1'', 5)', 'P0002', 'gestor Alfa não define meta na Beta');

-- ============ Master: status da IES
select teste.erro('select public.rpc_alterar_status_ies(1, ''suspensa'')', '42501', 'gestor não suspende IES');
select set_config('request.jwt.claim.sub', teste.id('master')::text, false);
select teste.ok(public.rpc_alterar_status_ies(2, 'ativa')->>'status' = 'ativa', 'Master reativa IES');
select teste.erro('select public.rpc_alterar_status_ies(1, ''apagada'')', '22023', 'status inválido recusado');

-- ============ aceite de proposta
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
insert into teste.var values ('op3', (select id from public.oportunidades where ies_id = 1 and etapa = 'novo' and curso_id = 1 order by id limit 1));
select public.rpc_mover_etapa((select v from teste.var where k='op3'), 'contato', (select versao from public.oportunidades where id = (select v from teste.var where k='op3')));
select public.rpc_mover_etapa((select v from teste.var where k='op3'), 'inscrito', (select versao from public.oportunidades where id = (select v from teste.var where k='op3')));
insert into teste.var values ('p_ok', (public.rpc_criar_proposta((select v from teste.var where k='op3'), 10)->>'id')::bigint);
insert into teste.var values ('p_pend', (public.rpc_criar_proposta((select v from teste.var where k='op3'), 60)->>'id')::bigint);
select teste.erro('select public.rpc_aceitar_proposta((select v from teste.var where k=''p_pend''))', '22023', 'proposta pendente não pode ser aceita');
select teste.ok(public.rpc_aceitar_proposta((select v from teste.var where k='p_ok'))->>'status' = 'aceita', 'proposta aprovada é aceita');
reset role;
update public.propostas set status = 'aprovada', validade = now() - interval '1 day' where id = (select v from teste.var where k='p_pend');
set role authenticated;
select teste.ok(public.rpc_aceitar_proposta((select v from teste.var where k='p_pend'))->>'status' = 'expirada', 'proposta vencida expira no aceite');
select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false);
select teste.erro('select public.rpc_aceitar_proposta((select v from teste.var where k=''p_ok''))', '42501', 'coordenador não registra aceite');

-- ============ MAIM: fila, ciclo, limite, supressão, revalidação, disparo bloqueado
select set_config('request.jwt.claim.sub', teste.id('reitoria_a')::text, false);
select teste.erro('select public.rpc_fila(1)', '42501', 'reitoria não acessa fila operacional');
select set_config('request.jwt.claim.sub', teste.id('com_dir_a')::text, false);
select teste.ok((select bool_and((x->>'responsavel_id')::uuid = teste.id('com_dir_a')) from jsonb_array_elements(public.rpc_fila(1)->'tarefas') x) is not false,
  'comercial vê só as próprias tarefas');
select teste.ok(public.rpc_fila(1)->>'envio_externo' = 'desativado', 'fila declara envio externo desativado');
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro('select public.rpc_ciclo_maim(1)', '42501', 'comercial não executa ciclo MAIM');

reset role;
update public.tarefas set status = 'concluida' where ies_id = 1 and status = 'aberta';
update public.oportunidades set atualizado_em = now() - interval '10 days' where ies_id = 1;
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
insert into teste.var values ('c1', (public.rpc_ciclo_maim(1)->>'follow_ups')::int);
select teste.ok((select v from teste.var where k='c1') >= 1, 'ciclo gera follow-up para oportunidade parada');
select teste.ok((public.rpc_ciclo_maim(1)->>'follow_ups')::int = 0, 'segundo ciclo não duplica tarefas');
reset role;
update public.tarefas set status = 'concluida' where ies_id = 1 and status = 'aberta';
set role authenticated;
select teste.ok((public.rpc_ciclo_maim(1)->>'limite_atingido')::int = 0, 'com limite 2, o segundo follow-up ainda é permitido');
reset role;
update public.tarefas set status = 'concluida' where ies_id = 1 and status = 'aberta';
set role authenticated;
select teste.ok((public.rpc_ciclo_maim(1)->>'limite_atingido')::int >= 1, 'com 2 follow-ups feitos, o limite bloqueia o terceiro');
select teste.ok((public.rpc_ciclo_maim(1)->>'follow_ups')::int = 0, 'nenhum follow-up além do limite');

-- recompõe cenário com tarefas abertas para os testes de execução
select public.rpc_configurar(1, null, 5);
select teste.ok((public.rpc_ciclo_maim(1)->>'follow_ups')::int >= 1, 'ao ampliar o limite, o ciclo volta a gerar follow-ups');
-- revalidação: tarefa aberta de pessoa que pediu opt-out é suprimida na execução
insert into teste.var values ('t1', (select t.id from public.tarefas t where t.ies_id = 1 and t.status = 'aberta' and t.canal = 'email' order by t.id limit 1));
reset role;
-- opt-out registrado por fora da tarefa (ex.: outra oportunidade da mesma pessoa), sem suprimir esta tarefa
update public.pessoas set optout_email = true where id = (select o.pessoa_id from public.tarefas t join public.oportunidades o on o.id = t.oportunidade_id where t.id = (select v from teste.var where k='t1'));
set role authenticated;
select teste.ok((public.rpc_disparar_tarefa((select v from teste.var where k='t1'))->>'enviado')::boolean = false, 'disparo nunca envia');
select teste.ok((public.rpc_disparar_tarefa((select v from teste.var where k='t1'))->>'elegivel')::boolean = false, 'disparo revalida opt-out');
select teste.ok(public.rpc_concluir_tarefa((select v from teste.var where k='t1'), 'liguei e falei')->>'status' = 'suprimida', 'conclusão revalida e suprime por opt-out');
select teste.erro('select public.rpc_concluir_tarefa((select v from teste.var where k=''t1''), ''de novo'')', '22023', 'tarefa encerrada não reabre');
reset role;
select teste.ok((select count(*) from public.auditoria where acao = 'envio_externo.bloqueado') >= 2, 'tentativas de disparo auditadas');
set role authenticated;

-- tarefa de outro atendente
-- tarefa de Direito (curso visível ao atendente restrito) atribuída a outro atendente
reset role;
with nova as (
  insert into public.tarefas(ies_id, oportunidade_id, tipo, canal, responsavel_id, vence_em)
  select 1, o.id, 'follow_up', 'telefone', teste.id('comercial_a'), now() + interval '1 day'
    from public.oportunidades o where o.ies_id = 1 and o.curso_id = 1 and o.etapa = 'novo' order by o.id limit 1
  returning id)
insert into teste.var select 't2', id from nova;
set role authenticated;
select teste.ok((select v from teste.var where k='t2') is not null, 'cenário: existe tarefa aberta de Direito');
select set_config('request.jwt.claim.sub', teste.id('com_dir_a')::text, false);
select teste.erro('select public.rpc_concluir_tarefa((select v from teste.var where k=''t2''), ''tentativa'')', '42501', 'atendente não conclui tarefa de outro no mesmo curso');
reset role;
insert into teste.var values ('t3', (select t.id from public.tarefas t join public.oportunidades o on o.id = t.oportunidade_id
  where t.ies_id = 1 and t.status = 'aberta' and o.curso_id = 2 and t.tipo <> 'pendencia_validacao' order by t.id limit 1));
set role authenticated;
select teste.erro('select public.rpc_concluir_tarefa((select v from teste.var where k=''t3''), ''tentativa'')', 'P0002', 'tarefa de curso não autorizado: não encontrado (sem revelar existência)');

-- ============ pendências
select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false);
select teste.ok((select bool_and(x->>'curso' = 'Direito') from jsonb_array_elements(public.rpc_pendencias(1)) x) is not false, 'pendências respeitam curso autorizado');

-- ============ anonimização
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro('select public.rpc_anonimizar((select v from teste.var where k=''op3''))', '42501', 'comercial não anonimiza');
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
insert into teste.var values ('bi_antes', (public.rpc_bi(1, '2027.1')->'totais'->>'oportunidades')::int);
select public.rpc_anonimizar((select v from teste.var where k='op3'));
select teste.ok((select email is null and telefone is null and nome = 'Titular anonimizado' from public.pessoas
                 where id = (select pessoa_id from public.oportunidades where id = (select v from teste.var where k='op3'))), 'dados pessoais removidos');
select teste.ok((public.rpc_bi(1, '2027.1')->'totais'->>'oportunidades')::int = (select v from teste.var where k='bi_antes'), 'estatística preservada após anonimização');
reset role;
select teste.ok(not exists (select 1 from public.auditoria where dados::text ~ '@exemplo\.invalid'), 'auditoria segue sem dados pessoais');
do $$ begin raise notice 'OK  fim da bateria complementar'; end $$;
