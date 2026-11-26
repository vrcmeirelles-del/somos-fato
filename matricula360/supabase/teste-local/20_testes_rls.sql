-- Testes de isolamento e regras no banco (Postgres real). Cada bloco assume uma identidade
-- via JWT simulado e o papel "authenticated", exatamente como um cliente Supabase.
\set ON_ERROR_STOP on
\set QUIET on

-- ============ anon não lê nada
set role anon;
select teste.erro('select count(*) from public.oportunidades', '42501', 'anon: sem permissão de leitura');
select teste.erro('select public.rpc_bi(1, ''2027.1'')', '42501', 'anon: não executa RPC');
reset role;

-- ============ isolamento entre IES
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.ok((select count(*) from public.oportunidades) = 8, 'gestor Alfa vê só as 8 oportunidades da Alfa');
select teste.ok((select count(*) from public.oportunidades where ies_id = 2) = 0, 'gestor Alfa não vê nada da Beta');
select teste.ok((select count(*) from public.pessoas where ies_id = 2) = 0, 'gestor Alfa não vê pessoas da Beta');
select teste.ok((select count(*) from public.ies) = 1, 'gestor Alfa vê só a própria IES');
select teste.erro('select public.rpc_mover_etapa(9, ''contato'', 1)', 'P0002', 'IDOR: mover oportunidade da Beta => não encontrado');
select teste.erro('select public.rpc_listar_oportunidades(2)', 'P0002', 'IDOR: listar IES alheia => não encontrado');
select teste.erro('select public.rpc_bi(2, ''2027.1'')', 'P0002', 'IDOR: BI de IES alheia => não encontrado');
select teste.erro('select public.rpc_mover_etapa(999999, ''contato'', 1)', 'P0002', 'ID inexistente => não encontrado');

select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false);
select teste.ok((select count(*) from public.oportunidades) = 4, 'gestor Beta vê só as 4 da Beta');

-- ============ escrita direta bloqueada (só RPC)
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.erro('update public.oportunidades set etapa = ''confirmado'' where id = 1', '42501', 'UPDATE direto bloqueado');
select teste.erro('update public.oportunidades set val_documental = true where id = 1', '42501', 'alteração direta de validação bloqueada');
select teste.erro('insert into public.escopos(usuario_id, ies_id, papel) values (auth.uid(), 2, ''gestor'')', '42501', 'autoconceder escopo bloqueado');
select teste.erro('update public.usuarios set master = true where id = auth.uid()', '42501', 'autopromoção a Master bloqueada');
select teste.erro('delete from public.auditoria', '42501', 'DELETE na auditoria bloqueado');
select teste.erro('select privado.auditar(1, ''x'', ''y'', ''1'')', '42501', 'auxiliar interno de auditoria não executável');
select teste.erro('select * from privado.idempotencia', '42501', 'tabela de idempotência inacessível');
select teste.erro('select public.rpc_conceder_escopo(auth.uid(), 2, null, ''gestor'')', '42501', 'gestor não usa RPC de Master');

-- ============ coordenador: só curso autorizado; sem dados pessoais diretos
select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false);
select teste.ok((select count(*) from public.oportunidades) = 4 and (select bool_and(curso_id = 1) from public.oportunidades), 'coordenador vê só Direito');
select teste.ok((select count(*) from public.pessoas) = 0, 'coordenador não lê tabela de pessoas (minimização)');
select teste.ok((select bool_and((x->>'dados_mascarados')::boolean and x->>'email' like '%***@%')
                 from jsonb_array_elements(public.rpc_listar_oportunidades(1)->'itens') x), 'coordenador recebe contatos mascarados');
select teste.ok(public.rpc_bi(1, '2027.1')->>'cobertura' = 'cursos_autorizados', 'BI do coordenador limitado aos cursos');
select teste.erro('select public.rpc_mover_etapa(2, ''contato'', 1)', '42501', 'coordenador não opera funil');

-- reitoria: IES inteira, mas sem dados pessoais
select set_config('request.jwt.claim.sub', teste.id('reitoria_a')::text, false);
select teste.ok((select count(*) from public.oportunidades) = 8, 'reitoria vê a IES inteira');
select teste.ok((select count(*) from public.pessoas) = 0, 'reitoria não lê dados pessoais');

-- comercial restrito a Direito
select set_config('request.jwt.claim.sub', teste.id('com_dir_a')::text, false);
select teste.erro($q$select public.rpc_criar_oportunidade(1, '{"nome":"X Y","email":"xy@exemplo.invalid","curso_id":2,"forma_ingresso":"enem","coorte":"2027.1","base_legal":"consentimento","origem":"site"}')$q$,
  '42501', 'comercial de Direito não cria em Administração');

-- ============ Master não lê candidatos
select set_config('request.jwt.claim.sub', teste.id('master')::text, false);
select teste.ok((select count(*) from public.oportunidades) = 0 and (select count(*) from public.pessoas) = 0, 'Master sem escopo não vê candidatos');
select teste.ok((select count(*) from public.ies) = 2, 'Master vê cadastro das IES');

-- ============ revogação vale mesmo com JWT ainda válido
select set_config('request.jwt.claim.sub', teste.id('revogado_a')::text, false);
select teste.ok((select count(*) from public.oportunidades) = 0, 'usuário revogado não lê nada');
select teste.erro($q$select public.rpc_criar_oportunidade(1, '{"nome":"X Y","email":"rv@exemplo.invalid","curso_id":1,"forma_ingresso":"enem","coorte":"2027.1","base_legal":"consentimento","origem":"site"}')$q$,
  '42501', 'usuário revogado não escreve');

-- ============ LGPD
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro($q$select public.rpc_criar_oportunidade(1, '{"nome":"Sem Base","email":"sb@exemplo.invalid","curso_id":1,"forma_ingresso":"enem","coorte":"2027.1","origem":"site"}')$q$,
  '22023', 'sem base legal não entra');
select teste.ok((public.rpc_criar_oportunidade(1, '{"nome":"Dup","email":"A2@EXEMPLO.INVALID","curso_id":1,"forma_ingresso":"enem","coorte":"2027.1","base_legal":"consentimento","origem":"site"}')->>'duplicada')::boolean,
  'deduplicação por e-mail normalizado');

-- ============ idempotência
select teste.ok((select (public.rpc_criar_oportunidade(1, '{"nome":"Idem","email":"idem@exemplo.invalid","curso_id":2,"forma_ingresso":"evento","coorte":"2027.2","base_legal":"consentimento","origem":"feira"}', 'chave-idem-0001')->>'duplicada')::boolean = false), 'primeira chamada cria');
select teste.ok((public.rpc_criar_oportunidade(1, '{"nome":"Idem","email":"idem@exemplo.invalid","curso_id":2,"forma_ingresso":"evento","coorte":"2027.2","base_legal":"consentimento","origem":"feira"}', 'chave-idem-0001')->>'repeticao')::boolean,
  'repetição com a mesma chave devolve a resposta gravada');
reset role;
select teste.ok((select count(*) from public.auditoria where acao = 'oportunidade.criar' and dados->>'coorte' = '2027.2') = 1, 'repetição não gerou segunda auditoria');
set role authenticated;

-- ============ funil, versão, segregação, confirmação e cancelamento
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
insert into teste.var values ('op', (select id from public.oportunidades where ies_id = 1 and curso_id = 1 and coorte = '2027.1' order by id limit 1));
select teste.erro('select public.rpc_mover_etapa((select v from teste.var where k=''op''), ''matricula_comercial'', 1)', '22023', 'pular etapas é recusado');
select public.rpc_mover_etapa((select v from teste.var where k='op'), 'contato', 1);
select teste.erro('select public.rpc_mover_etapa((select v from teste.var where k=''op''), ''inscrito'', 1)', '40001', 'versão antiga => conflito');
select public.rpc_mover_etapa((select v from teste.var where k='op'), 'inscrito', 2);
select teste.erro('select public.rpc_mover_etapa((select v from teste.var where k=''op''), ''confirmado'', 3)', '22023', 'confirmar por transição comum é recusado');
-- proposta acima do limite (30%) vai para aprovação; criador não decide
insert into teste.var values ('prop', (public.rpc_criar_proposta((select v from teste.var where k='op'), 45)->>'id')::bigint);
select teste.ok((select status from public.propostas where id = (select v from teste.var where k='prop')) = 'pendente_aprovacao', 'desconto acima do limite fica pendente');
select teste.erro('select public.rpc_criar_proposta((select v from teste.var where k=''op''), 120)', '22023', 'desconto acima de 100% recusado');
select teste.erro('select public.rpc_decidir_proposta((select v from teste.var where k=''prop''), ''aprovar'')', '42501', 'comercial não aprova proposta');
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.ok(public.rpc_decidir_proposta((select v from teste.var where k='prop'), 'aprovar')->>'status' = 'aprovada', 'gestor aprova proposta de outro usuário');
insert into teste.var values ('prop2', (public.rpc_criar_proposta((select v from teste.var where k='op'), 50)->>'id')::bigint);
select teste.erro('select public.rpc_decidir_proposta((select v from teste.var where k=''prop2''), ''aprovar'')', '42501', 'gestor não aprova a própria proposta (segregação)');

select public.rpc_mover_etapa((select v from teste.var where k='op'), 'pre_matricula', 3);
select public.rpc_mover_etapa((select v from teste.var where k='op'), 'matricula_comercial', 4);
-- validações por papel
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro('select public.rpc_validar((select v from teste.var where k=''op''), ''documental'', ''valida'', ''RG conferido'', 5)', '42501', 'comercial não valida');
select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false);
select teste.erro('select public.rpc_validar((select v from teste.var where k=''op''), ''financeira'', ''valida'', ''boleto pago'', 5)', '42501', 'secretaria não valida financeira');
select teste.erro('select public.rpc_validar((select v from teste.var where k=''op''), ''documental'', ''valida'', '''', 5)', '22023', 'validação sem evidência recusada');
select public.rpc_validar((select v from teste.var where k='op'), 'documental', 'valida', 'RG e histórico conferidos', 5);
select teste.erro('select public.rpc_confirmar((select v from teste.var where k=''op''), 6)', '22023', 'confirmação incompleta recusada');
select set_config('request.jwt.claim.sub', teste.id('financeiro_a')::text, false);
select teste.erro('select public.rpc_validar((select v from teste.var where k=''op''), ''documental'', ''valida'', ''RG conferido'', 6)', '42501', 'financeiro não valida documental');
select public.rpc_validar((select v from teste.var where k='op'), 'financeira', 'isencao_formal', 'Portaria de isenção 1 (sintética)', 6);
select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false);
select public.rpc_validar((select v from teste.var where k='op'), 'academica', 'valida', 'Requisitos de ingresso atendidos', 7);
select teste.ok(public.rpc_confirmar((select v from teste.var where k='op'), 8)->>'etapa' = 'confirmado', 'confirmação com as três validações');
select teste.erro('select public.rpc_cancelar((select v from teste.var where k=''op''), 9, '''')', '22023', 'cancelamento sem motivo recusado');
select public.rpc_cancelar((select v from teste.var where k='op'), 9, 'Desistência formal (sintética)');
select teste.ok((select etapa = 'cancelado' and confirmada_em is not null from public.oportunidades where id = (select v from teste.var where k='op')), 'cancelamento preserva data de confirmação');
select teste.ok((select count(*) from public.validacoes where oportunidade_id = (select v from teste.var where k='op')) = 3, 'cancelamento preserva validações');
reset role;
select teste.ok((select count(*) from public.auditoria where entidade_id = (select v::text from teste.var where k='op')) >= 10, 'histórico completo auditado');
select teste.ok(not exists (select 1 from public.auditoria where dados::text ~ '@exemplo\.invalid'), 'auditoria sem e-mails de candidatos');
-- defesa no banco mesmo para o dono do esquema
select teste.erro('update public.oportunidades set etapa = ''confirmado'' where id = (select id from public.oportunidades where etapa = ''novo'' limit 1)', '22023', 'banco recusa ingresso sem validações (gatilho)');
select teste.erro('update public.auditoria set acao = ''x''', '42501', 'auditoria imutável mesmo para o dono');
select teste.erro('truncate public.auditoria', '42501', 'TRUNCATE da auditoria bloqueado');
set role authenticated;

-- ============ opt-out
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
insert into teste.var values ('op2', (select id from public.oportunidades where ies_id = 1 and etapa = 'novo' and coorte = '2027.1' order by id limit 1));
select teste.ok((public.rpc_optout((select v from teste.var where k='op2'), 'email')->>'tarefas_suprimidas')::int >= 1, 'opt-out suprime tarefas do canal');
select teste.ok((select bool_and(status = 'suprimida') from public.tarefas where oportunidade_id = (select v from teste.var where k='op2') and canal = 'email'), 'tarefas do canal ficaram suprimidas');

-- ============ BI: zero vs indisponível e pessoas distintas
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.ok((public.rpc_bi(1, '2031.1')->'totais'->>'conversao') is null and (public.rpc_bi(1, '2031.1')->'totais'->>'oportunidades')::int = 0, 'coorte vazia: conversão N/D, não zero');
select teste.ok((public.rpc_bi(1, '2027.2')->'totais'->>'meta') is null, 'coorte sem meta: meta N/D');
select teste.ok((public.rpc_bi(1, '2027.1')->'totais'->>'meta')::int = 16, 'meta somada dos cursos');
select teste.ok((public.rpc_bi(1, '2027.1')->'totais'->>'oportunidades')::int = (select count(*) from public.oportunidades where ies_id = 1 and coorte = '2027.1'), 'denominador = oportunidades da coorte');
select teste.erro('select public.rpc_bi(1, ''2027'')', '22023', 'coorte malformada recusada');
select teste.erro('select public.rpc_listar_oportunidades(1, null, null, 1, 1000)', '22023', 'página gigante recusada');

-- ============ revogação de escopo e suspensão de IES
reset role;
update public.escopos set revogado_em = now() where usuario_id = teste.id('comercial_b');
update public.ies set status = 'suspensa' where id = 2;
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('comercial_b')::text, false);
select teste.ok((select count(*) from public.oportunidades) = 0, 'escopo revogado perde leitura imediatamente');
select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false);
select teste.ok((select count(*) from public.oportunidades) = 0, 'IES suspensa bloqueia acesso');
reset role;
do $$ begin raise notice 'OK  fim da bateria (todos os blocos executados)'; end $$;
