-- Testes de eventos e processo seletivo online (migração 20).
\set ON_ERROR_STOP on
reset role;
create temp table sel_tok (t text);
grant all on sel_tok to anon, authenticated;
set role authenticated;

-- ---------------------------------------------------------------- eventos
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro($q$select public.rpc_salvar_evento(1, '{"titulo":"Open house","tipo":"open_house","inicio":"2027-01-10T10:00:00Z","fim":"2027-01-10T12:00:00Z"}'::jsonb)$q$, '42501', 'comercial não cria evento');
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.erro($q$select public.rpc_salvar_evento(1, '{"titulo":"Datas invertidas","tipo":"tour","inicio":"2027-01-10T12:00:00Z","fim":"2027-01-10T10:00:00Z"}'::jsonb)$q$, '22023', 'evento com fim antes do início recusado');
insert into teste.var values ('evento', (public.rpc_salvar_evento(1, jsonb_build_object('titulo', 'Open house de Direito', 'tipo', 'open_house', 'inicio', now() + interval '1 hour',
  'fim', now() + interval '3 hours', 'local', 'Campus Centro', 'vagas', 2))->>'id')::bigint);
select public.rpc_vincular_evento_formulario((select v from teste.var where k = 'form'), (select v from teste.var where k = 'evento'));
reset role; set role anon;
select public.rpc_publico_inscrever('vestibular-2027', '{"nome":"Visitante do Open House","email":"visitante.oh@exemplo.invalid","curso_id":1,"aceite":true,"versao_consentimento":2,"tempo_ms":12000}'::jsonb);
reset role;
select teste.ok((select count(*) = 1 from public.inscricoes_evento i join public.pessoas p on p.id = i.pessoa_id where p.email = 'visitante.oh@exemplo.invalid'
                 and i.evento_id = (select v from teste.var where k = 'evento')), 'formulário público vinculado inscreve no evento');
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select public.rpc_inscrever_evento((select v from teste.var where k = 'evento'), (select min(id) from public.oportunidades where ies_id = 1 and etapa = 'contato'));
select teste.erro($q$select public.rpc_inscrever_evento((select v from teste.var where k = 'evento'), (select max(id) from public.oportunidades where ies_id = 1 and etapa = 'novo'))$q$, '22023', 'evento sem vagas recusa nova inscrição');
insert into teste.var values ('insc_ev', (select (i->>'id')::bigint from jsonb_array_elements(public.rpc_eventos(1)) e, jsonb_array_elements(e->'inscricoes') i
                                           where (e->>'id')::bigint = (select v from teste.var where k = 'evento') limit 1));
select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false);
select teste.ok((public.rpc_checkin((select v from teste.var where k = 'insc_ev'), 'presente')->>'status') = 'presente', 'check-in de presença registrado');
select teste.ok((select (e->>'presentes')::int = 1 and (e->>'inscritos')::int = 2 from jsonb_array_elements(public.rpc_eventos(1)) e where (e->>'id')::bigint = (select v from teste.var where k = 'evento')),
  'evento mostra inscritos e presentes');
select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false);
select teste.erro('select public.rpc_checkin((select v from teste.var where k = ''insc_ev''), ''ausente'')', 'P0002', 'gestor de outra IES não registra presença');

-- ---------------------------------------------------------------- processo seletivo
select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false);
insert into teste.var values ('proc', (public.rpc_salvar_processo(1, jsonb_build_object('coorte', '2027.1', 'nome', 'Vestibular agendado 2027.1', 'tipo', 'prova_agendada',
  'inscricoes_ate', current_date + 30, 'nota_minima', 500, 'tema_redacao', 'O papel da educação superior no desenvolvimento regional',
  'agenda', jsonb_build_object('inicio', now() + interval '1 day', 'local', 'Campus Centro, sala 12', 'vagas', 50)))->>'id')::bigint);
insert into teste.var values ('proc_enem', (public.rpc_salvar_processo(1, jsonb_build_object('coorte', '2027.1', 'nome', 'Seleção ENEM 2027.1', 'tipo', 'enem',
  'inscricoes_ate', current_date + 30, 'nota_minima', 550))->>'id')::bigint);
insert into teste.var values ('agenda', (select (a->>'id')::bigint from jsonb_array_elements(public.rpc_seletivo(1)->'processos') p, jsonb_array_elements(p->'agendas') a
                                          where (p->>'id')::bigint = (select v from teste.var where k = 'proc')));
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
reset role;
insert into teste.var values ('sel_op', (select o.id from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id where p.email = 'visitante.oh@exemplo.invalid'));
update public.oportunidades set etapa = 'contato' where id = (select v from teste.var where k = 'sel_op');
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
insert into sel_tok select public.rpc_gerar_acesso_portal((select v from teste.var where k = 'sel_op'))->>'token';
reset role; set role anon;
select teste.ok((select jsonb_array_length(r->'processos_abertos') = 2 and jsonb_array_length(r->'eventos') = 1 from (select public.rpc_publico_portal_seletivo((select t from sel_tok)) r) x),
  'candidato vê processos abertos e o evento em que se inscreveu');
select teste.erro($q$select public.rpc_publico_candidatar((select t from sel_tok), (select v from teste.var where k = 'proc'), (select v from teste.var where k = 'sel_op'))$q$, '22023', 'prova agendada exige escolher data');
select teste.ok((public.rpc_publico_candidatar((select t from sel_tok), (select v from teste.var where k = 'proc'), (select v from teste.var where k = 'sel_op'), (select v from teste.var where k = 'agenda'))->>'id') is not null,
  'candidato se inscreve no vestibular agendado pelo portal');
select teste.erro($q$select public.rpc_publico_candidatar((select t from sel_tok), (select v from teste.var where k = 'proc'), (select v from teste.var where k = 'sel_op'), (select v from teste.var where k = 'agenda'))$q$, '22023', 'inscrição repetida recusada');
select teste.ok((select (r->'candidaturas'->0->'tema_redacao') = 'null'::jsonb from (select public.rpc_publico_portal_seletivo((select t from sel_tok)) r) x), 'tema da redação só aparece no horário da prova');
select teste.erro($q$select public.rpc_publico_enviar_redacao((select t from sel_tok), (select (c->>'id')::bigint from jsonb_array_elements(public.rpc_publico_portal_seletivo((select t from sel_tok))->'candidaturas') c limit 1), repeat('texto ', 60))$q$,
  '22023', 'redação fora do horário recusada');
reset role;
select teste.ok((select etapa = 'inscrito' from public.oportunidades where id = (select v from teste.var where k = 'sel_op')), 'inscrição no processo move contato → inscrito (auditado)');
update public.agendas_prova set inicio = now() - interval '10 minutes' where id = (select v from teste.var where k = 'agenda');
insert into teste.var values ('cand', (select id from public.candidaturas where oportunidade_id = (select v from teste.var where k = 'sel_op')));
set role anon;
select teste.ok(length((public.rpc_publico_portal_seletivo((select t from sel_tok))->'candidaturas'->0->>'tema_redacao')) > 10, 'no horário da prova o tema aparece');
select teste.erro($q$select public.rpc_publico_enviar_redacao((select t from sel_tok), (select v from teste.var where k = 'cand'), 'curta')$q$, '22023', 'redação curta recusada');
select teste.ok((public.rpc_publico_enviar_redacao((select t from sel_tok), (select v from teste.var where k = 'cand'), repeat('A educação superior amplia oportunidades. ', 10))->>'enviada')::boolean, 'redação enviada no horário');
select teste.erro($q$select public.rpc_publico_enviar_redacao((select t from sel_tok), (select v from teste.var where k = 'cand'), repeat('Outra versão do texto. ', 20))$q$, '22023', 'envio único da redação');
reset role; set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false);
select teste.erro($q$select public.rpc_avaliar_candidatura((select v from teste.var where k = 'cand'), '{"redacao_nota":720}'::jsonb)$q$, '22023', 'correção exige parecer');
select public.rpc_avaliar_candidatura((select v from teste.var where k = 'cand'), '{"redacao_nota":720,"redacao_parecer":"Texto coeso, tese clara, repertório adequado."}'::jsonb);
select teste.ok((select c->>'sugestao' = 'aprovado' and c->>'resultado' = 'pendente' from jsonb_array_elements(public.rpc_seletivo(1)->'processos') p, jsonb_array_elements(p->'candidaturas') c
                 where (c->>'id')::bigint = (select v from teste.var where k = 'cand')), 'sistema só sugere; resultado continua pendente até decisão humana');
select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false);
select teste.erro('select public.rpc_divulgar_resultado((select v from teste.var where k = ''proc''))', '22023', 'divulgação bloqueada com candidatura pendente');
select teste.erro($q$select public.rpc_avaliar_candidatura((select v from teste.var where k = 'cand'), '{"resultado":"aprovado"}'::jsonb)$q$, '22023', 'resultado exige justificativa');
select public.rpc_avaliar_candidatura((select v from teste.var where k = 'cand'), '{"resultado":"aprovado","justificativa":"Redação 720, acima da nota mínima 500."}'::jsonb);
reset role; set role anon;
select teste.ok((public.rpc_publico_portal_seletivo((select t from sel_tok))->'candidaturas'->0->'resultado') = 'null'::jsonb, 'candidato não vê o resultado antes da divulgação');
reset role; set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false);
select teste.ok((public.rpc_divulgar_resultado((select v from teste.var where k = 'proc'))->>'divulgado')::boolean, 'secretaria divulga o resultado');
select teste.erro($q$select public.rpc_avaliar_candidatura((select v from teste.var where k = 'cand'), '{"resultado":"reprovado","justificativa":"tentativa de mudar após divulgar"}'::jsonb)$q$, '22023', 'resultado divulgado não muda');
reset role; set role anon;
select teste.ok((public.rpc_publico_portal_seletivo((select t from sel_tok))->'candidaturas'->0->>'resultado') = 'aprovado', 'candidato vê o resultado após a divulgação');
-- ENEM: aprovar exige conferência humana da nota
select public.rpc_publico_candidatar((select t from sel_tok), (select v from teste.var where k = 'proc_enem'), (select v from teste.var where k = 'sel_op'), null, 610);
reset role; set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false);
insert into teste.var values ('cand_enem', (select (c->>'id')::bigint from jsonb_array_elements(public.rpc_seletivo(1)->'processos') p, jsonb_array_elements(p->'candidaturas') c
                                             where (p->>'id')::bigint = (select v from teste.var where k = 'proc_enem')));
select teste.erro($q$select public.rpc_avaliar_candidatura((select v from teste.var where k = 'cand_enem'), '{"resultado":"aprovado","justificativa":"Nota declarada 610"}'::jsonb)$q$, '22023', 'ENEM: aprovar exige nota conferida');
select public.rpc_avaliar_candidatura((select v from teste.var where k = 'cand_enem'), '{"conferir_enem":true,"resultado":"aprovado","justificativa":"Nota 610 conferida no boletim oficial."}'::jsonb);
select teste.ok((select (c->>'enem_conferido')::boolean and c->>'resultado' = 'aprovado' from jsonb_array_elements(public.rpc_seletivo(1)->'processos') p, jsonb_array_elements(p->'candidaturas') c
                 where (c->>'id')::bigint = (select v from teste.var where k = 'cand_enem')), 'ENEM conferido por pessoa e aprovado com justificativa');
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro('select public.rpc_divulgar_resultado((select v from teste.var where k = ''proc_enem''))', '42501', 'comercial não divulga resultado');
select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false);
select teste.erro('select public.rpc_avaliar_candidatura((select v from teste.var where k = ''cand_enem''), ''{"nota_objetiva":1}''::jsonb)', 'P0002', 'gestor de outra IES não avalia');
select teste.erro('select count(*) from public.candidaturas', '42501', 'candidaturas sem leitura direta');
reset role;
select teste.ok(true, 'fim da bateria de eventos e processo seletivo');
