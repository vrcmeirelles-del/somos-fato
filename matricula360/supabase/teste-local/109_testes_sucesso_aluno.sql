-- Testes de sucesso do aluno: casos e trilhas (migração 25). Usa ing1 (101) e a recusa de rematrícula do ing2 (108, presencial).
\set ON_ERROR_STOP on
reset role;
create temp table cas (chave text primary key, v text);
grant all on cas to anon, authenticated;
select teste.ok((select count(*) = 7 from public.trilhas_intervencao where ies_id = 1), 'trilhas padrão criadas para a IES');

set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro($q$select public.rpc_casos(1)$q$, '42501', 'comercial não vê casos de alunos');
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.erro($q$select public.rpc_abrir_caso((select v from teste.var where k = 'mat_op'), 'frequencia', 'Faltou três semanas')$q$, '22023', 'caso só para aluno com ingresso efetivo');
select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false);
select teste.erro($q$select public.rpc_abrir_caso((select v from teste.var where k = 'ing1'), 'saude', 'Motivo sensível')$q$, '22023', 'motivo fora da lista (ex.: saúde) recusado');
insert into cas select 'c1', public.rpc_abrir_caso((select v from teste.var where k = 'ing1'), 'adaptacao', 'Relatou dificuldade de se adaptar ao turno', 'alta')->>'id';
select teste.erro($q$select public.rpc_abrir_caso((select v from teste.var where k = 'ing1'), 'adaptacao', 'Outro caso igual')$q$, '22023', 'um caso aberto por motivo e aluno');
reset role;
select teste.ok((select c.responsavel_id is not null and c.prazo <= now() + interval '61 hours' and c.prazo > now() + interval '59 hours'
                   and exists (select 1 from public.escopos e where e.usuario_id = c.responsavel_id and e.papel = 'secretaria')
                 from public.casos c where c.id = (select v::bigint from cas where chave = 'c1')), 'roteado para a secretaria; prioridade alta reduz o prazo à metade');
insert into cas select 'resp', responsavel_id::text from public.casos where id = (select v::bigint from cas where chave = 'c1');
set role authenticated;

-- ---------------------------------------------------------------- atendimento
select set_config('request.jwt.claim.sub', teste.id('financeiro_a')::text, false);
select teste.erro($q$select public.rpc_atender_caso((select v::bigint from cas where chave = 'c1'), 'nota', 'Tentando atender caso de outro')$q$, '42501', 'quem não é responsável não atende');
select teste.erro($q$select public.rpc_atender_caso((select v::bigint from cas where chave = 'c1'), 'assumir')$q$, '42501', 'não assume caso que já tem dono');
select set_config('request.jwt.claim.sub', (select v from cas where chave = 'resp'), false);
select teste.ok((public.rpc_atender_caso((select v::bigint from cas where chave = 'c1'), 'passo', 'Conversa de acolhimento feita na secretaria')->>'status') = 'em_atendimento', 'passo concluído põe o caso em atendimento');
select teste.erro($q$select public.rpc_atender_caso((select v::bigint from cas where chave = 'c1'), 'agendar', 'Retorno', now() - interval '1 hour')$q$, '22023', 'agendamento no passado recusado');
select public.rpc_atender_caso((select v::bigint from cas where chave = 'c1'), 'agendar', 'Retorno com a coordenação', now() + interval '3 days');
select teste.erro($q$select public.rpc_atender_caso((select v::bigint from cas where chave = 'c1'), 'encaminhar', 'Para o comercial', null, teste.id('comercial_a'))$q$, '22023', 'encaminhar para quem não atende casos: recusado');
select teste.ok((public.rpc_atender_caso((select v::bigint from cas where chave = 'c1'), 'encaminhar', 'Questão de mensalidade surgiu no atendimento', null, teste.id('financeiro_a'))->>'status') = 'em_atendimento',
  'encaminhado ao financeiro');
select teste.erro($q$select public.rpc_atender_caso((select v::bigint from cas where chave = 'c1'), 'nota', 'Depois de encaminhar')$q$, '42501', 'quem encaminhou deixa de ser responsável');
select set_config('request.jwt.claim.sub', teste.id('financeiro_a')::text, false);
select teste.erro($q$select public.rpc_atender_caso((select v::bigint from cas where chave = 'c1'), 'resolver', 'ok')$q$, '22023', 'resolução exige desfecho descrito');
select teste.erro($q$select public.rpc_atender_caso((select v::bigint from cas where chave = 'c1'), 'cancelar', 'Cancelado pelo financeiro')$q$, '42501', 'só a gestão cancela');
select teste.ok((select (c->'indicadores'->>'meus')::int = 1 and (select count(*) = 1 from jsonb_array_elements(c->'agenda')) from (select public.rpc_casos(1) c) x),
  'indicadores mostram o caso do usuário e a agenda');
select teste.ok((public.rpc_atender_caso((select v::bigint from cas where chave = 'c1'), 'resolver', 'Aluno mudou para o turno da manhã e negociou o boleto de dezembro')->>'status') = 'resolvido', 'caso resolvido com desfecho');
select teste.erro($q$select public.rpc_atender_caso((select v::bigint from cas where chave = 'c1'), 'nota', 'Depois de resolvido')$q$, '22023', 'caso encerrado não recebe atendimento');
select teste.ok((select (c->'indicadores'->>'resolvidos')::int = 1 and (c->'indicadores'->>'horas_medias_resolucao') is not null
                   and jsonb_array_length(c->'casos'->-1->'eventos') >= 1
                 from (select public.rpc_casos(1, (select v from teste.var where k = 'ing1')) c) x), 'histórico do caso e tempo médio de resolução');

-- ---------------------------------------------------------------- trilha automática a partir da recusa de rematrícula no portal
reset role;
-- nova campanha aberta com o ing1 pendente
insert into public.campanhas_rematricula(ies_id, periodo, abre_em, fecha_em, termo, status)
  values (1, '2028.1', current_date - 1, current_date + 10, repeat('Termo de rematrícula do período 2028.1 conforme contrato. ', 3), 'aberta');
insert into public.rematriculas(ies_id, campanha_id, oportunidade_id)
  select 1, c.id, (select v from teste.var where k = 'ing1') from public.campanhas_rematricula c where c.periodo = '2028.1' and c.ies_id = 1;
reset role;
-- (anon não lê rematriculas: busca o id antes)
insert into cas select 'r2028', r.id::text from public.rematriculas r join public.campanhas_rematricula c on c.id = r.campanha_id where c.periodo = '2028.1' and r.oportunidade_id = (select v from teste.var where k = 'ing1');
set role anon;
select teste.ok((public.rpc_publico_responder_rematricula((select v from rem where chave = 'tok_ing1'), (select v::bigint from cas where chave = 'r2028'),
  '{"resposta":"recusada","nome":"Ingressante Um","cpf":"529.982.247-25","motivo":"Não consigo pagar a mensalidade"}')->>'status') = 'recusada', 'aluno recusa a rematrícula pelo portal');
reset role;
select teste.ok((select c.origem = 'rematricula' and c.prioridade = 'alta' and c.motivo = 'rematricula_recusada' and c.descricao like '%Não consigo pagar%' and c.aberto_por is null
                 from public.casos c where c.oportunidade_id = (select v from teste.var where k = 'ing1') and c.motivo = 'rematricula_recusada'),
  'recusa no portal abre caso automaticamente, prioridade alta, com o motivo');
select teste.ok((select count(*) = 0 from public.casos where oportunidade_id = (select v from teste.var where k = 'ing2') and motivo = 'rematricula_recusada'),
  'recusa registrada pela secretaria não abre caso automático');

-- ---------------------------------------------------------------- trilhas e escopo
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false);
select teste.erro($q$select public.rpc_salvar_trilha(1, 'frequencia', '{"prazo_horas":24}')$q$, '42501', 'secretaria não edita trilha');
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.erro($q$select public.rpc_salvar_trilha(1, 'frequencia', '{"prazo_horas":1}')$q$, '23514', 'prazo fora do limite recusado');
select teste.ok((public.rpc_salvar_trilha(1, 'frequencia', '{"prazo_horas":48,"passos":["Ligar para o aluno","Reunião com a coordenação"]}')->>'id') is not null, 'gestor edita a trilha');
select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false);
select teste.erro($q$select public.rpc_casos(1)$q$, 'P0002', 'outra IES não vê os casos');
reset role;
select teste.ok((select cardinality(passos) = 2 and prazo_horas = 48 from public.trilhas_intervencao where ies_id = 1 and motivo = 'frequencia'), 'trilha atualizada');
select teste.ok((select count(*) >= 6 from public.auditoria where acao like 'caso.%'), 'casos auditados');
