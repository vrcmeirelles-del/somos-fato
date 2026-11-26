-- Testes de rematrícula ativa (migração 24). Usa ing1/ing2 (101) e a matrícula do menor com aceite reforçado (106: men_op, ac.men_tok).
\set ON_ERROR_STOP on
reset role;
create temp table rem (chave text primary key, v text);
grant all on rem to anon, authenticated;
-- o menor com aceite (CPF 52998224725, representante 11144477735) passa a ingressante efetivo
update public.oportunidades set etapa = 'confirmado', confirmada_em = now() - interval '150 days', val_documental = true, val_financeira = true, val_academica = true
 where id = (select v from teste.var where k = 'men_op');
-- um ingressante evadido (não elegível)
insert into public.pessoas(ies_id, nome, email, base_legal, origem) values (1, 'Ingressante Evadido', 'ingressante.evadido@exemplo.invalid', 'consentimento', 'site');
insert into public.oportunidades(ies_id, curso_id, pessoa_id, forma_ingresso, coorte, etapa, val_documental, val_financeira, val_academica, matricula_comercial_em, confirmada_em)
  select 1, 1, p.id, 'vestibular', '2027.1', 'confirmado', true, true, true, now() - interval '200 days', now() - interval '190 days' from public.pessoas p where p.email = 'ingressante.evadido@exemplo.invalid';
insert into rem select 'evadido', o.id::text from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id where p.email = 'ingressante.evadido@exemplo.invalid';
insert into public.vinculos(ies_id, oportunidade_id, marco, situacao, data_referencia, observacao, registrado_por)
  values (1, (select v::bigint from rem where chave = 'evadido'), 'd90', 'evadido', current_date - 10, 'Informado pela coordenação', teste.id('secretaria_a'));

set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro($q$select public.rpc_rematricula(1)$q$, '42501', 'comercial não vê rematrícula');
select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false);
select teste.erro($q$select public.rpc_salvar_campanha_rematricula(1, jsonb_build_object('periodo','2027.2','abre_em',current_date,'fecha_em',current_date + 20,
  'termo', repeat('Termo de rematrícula do período. ', 4) || '**sem fechar'))$q$, '22023', 'termo com destaque aberto recusado');
select teste.erro($q$select public.rpc_salvar_campanha_rematricula(1, jsonb_build_object('periodo','2027-2','abre_em',current_date,'fecha_em',current_date + 20,
  'termo', repeat('Termo de rematrícula do período. ', 4)))$q$, '23514', 'período fora do padrão recusado');
insert into rem select 'camp', public.rpc_salvar_campanha_rematricula(1, jsonb_build_object('periodo','2027.2','abre_em',current_date - 1,'fecha_em',current_date + 20,'meta_pct',85,
  'termo', repeat('Termo de rematrícula do período, conforme contrato vigente. ', 3) || E'\n**Reajuste anual conforme Lei 9.870/1999.**'))->>'id';
select teste.ok((select r->'campanhas'->0->>'status' = 'rascunho' and (r->'campanhas'->0->'totais'->>'elegiveis')::int = 0 and r->'campanhas'->0->'totais'->'taxa_pct' = 'null'::jsonb
                 from (select public.rpc_rematricula(1) r) x), 'campanha em rascunho sem elegíveis: taxa N/D');
select teste.ok((public.rpc_status_campanha_rematricula((select v::bigint from rem where chave = 'camp'), 'aberta')->>'novos_elegiveis')::int >= 3, 'abrir fotografa os elegíveis');
select teste.ok((public.rpc_status_campanha_rematricula((select v::bigint from rem where chave = 'camp'), 'aberta')->>'novos_elegiveis')::int = 0, 'reabrir não duplica elegíveis');
select teste.erro($q$select public.rpc_salvar_campanha_rematricula(1, jsonb_build_object('termo', repeat('Outro termo depois de aberto. ', 5)), (select v::bigint from rem where chave = 'camp'))$q$,
  '22023', 'termo não muda com a campanha aberta');
select teste.ok((select not (a @? ('$[*] ? (@.oportunidade_id == ' || (select v from rem where chave = 'evadido') || ')')::jsonpath)
                   and a @? ('$[*] ? (@.oportunidade_id == ' || (select v from teste.var where k = 'ing1') || ')')::jsonpath
                 from (select public.rpc_rematricula(1)->'campanhas'->0->'alunos' a) x), 'evadido fora, ingressante ativo dentro');
reset role;
insert into rem select 'r_men', id::text from public.rematriculas where oportunidade_id = (select v from teste.var where k = 'men_op');
insert into rem select 'r_ing1', id::text from public.rematriculas where oportunidade_id = (select v from teste.var where k = 'ing1');
insert into rem select 'r_ing2', id::text from public.rematriculas where oportunidade_id = (select v from teste.var where k = 'ing2');
set role authenticated;

-- ---------------------------------------------------------------- tratamento pela equipe
select set_config('request.jwt.claim.sub', teste.id('financeiro_a')::text, false);
select teste.erro($q$select public.rpc_tratar_rematricula((select v::bigint from rem where chave = 'r_ing1'), 'bloquear', 'x', 'financeiro')$q$, '22023', 'bloqueio sem motivo recusado');
select teste.ok((public.rpc_tratar_rematricula((select v::bigint from rem where chave = 'r_ing1'), 'bloquear', 'Mensalidades de outubro e novembro em aberto', 'financeiro')->>'status') = 'bloqueada',
  'financeiro bloqueia com categoria e motivo');
select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false);
select teste.ok((public.rpc_tratar_rematricula((select v::bigint from rem where chave = 'r_ing2'), 'recusada', 'Aluno informou no balcão que vai transferir')->>'status') = 'recusada',
  'secretaria registra recusa presencial');
select teste.erro($q$select public.rpc_tratar_rematricula((select v::bigint from rem where chave = 'r_ing2'), 'aceita', 'Mudou de ideia no mesmo dia')$q$, '22023', 'resposta registrada não muda');

-- ---------------------------------------------------------------- portal
reset role;
insert into rem select 'tok_ing1', null;
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
update rem set v = public.rpc_gerar_acesso_portal((select v from teste.var where k = 'ing1'))->>'token' where chave = 'tok_ing1';
reset role; set role anon;
select teste.ok((select r->>'status' = 'bloqueada' and r->>'bloqueio' = 'financeiro' and (r->>'aberta_agora')::boolean
                 from jsonb_array_elements(public.rpc_publico_portal_rematricula((select v from rem where chave = 'tok_ing1'))) r), 'aluno bloqueado vê só a categoria da pendência');
select teste.erro($q$select public.rpc_publico_responder_rematricula((select v from rem where chave = 'tok_ing1'), (select v::bigint from rem where chave = 'r_ing1'),
  '{"resposta":"aceita","nome":"Ingressante Um","cpf":"52998224725","li_termo":true,"concordo":true}')$q$, '22023', 'bloqueado não rematricula pelo portal');
select teste.erro($q$select public.rpc_publico_responder_rematricula((select v from rem where chave = 'tok_ing1'), (select v::bigint from rem where chave = 'r_men'),
  '{"resposta":"aceita","nome":"Ingressante Um","cpf":"52998224725","li_termo":true,"concordo":true}')$q$, 'P0002', 'não responde a rematrícula de outra pessoa');
-- menor: CPF tem de ser o do aceite e o representante confirma
select teste.erro($q$select public.rpc_publico_responder_rematricula((select txt from ac where chave = 'men_tok'), (select v::bigint from rem where chave = 'r_men'),
  jsonb_build_object('resposta','aceita','nome',(select txt from ac where chave = 'men_nome'),'cpf','111.444.777-35','li_termo',true,'concordo',true))$q$, '22023', 'CPF diferente do da matrícula recusado');
select teste.erro($q$select public.rpc_publico_responder_rematricula((select txt from ac where chave = 'men_tok'), (select v::bigint from rem where chave = 'r_men'),
  jsonb_build_object('resposta','aceita','nome',(select txt from ac where chave = 'men_nome'),'cpf','529.982.247-25','li_termo',true,'concordo',true))$q$, '22023', 'menor sem o representante: recusado');
select teste.ok((select r->>'status' = 'aceita' and r->>'evidencia_hash' ~ '^[0-9a-f]{64}$' from (select public.rpc_publico_responder_rematricula((select txt from ac where chave = 'men_tok'), (select v::bigint from rem where chave = 'r_men'),
  jsonb_build_object('resposta','aceita','nome',(select txt from ac where chave = 'men_nome'),'cpf','529.982.247-25','li_termo',true,'concordo',true,
    'responsavel', jsonb_build_object('cpf','111.444.777-35','declaro',true))) r) x), 'menor rematricula com o representante da matrícula');
select teste.erro($q$select public.rpc_publico_responder_rematricula((select txt from ac where chave = 'men_tok'), (select v::bigint from rem where chave = 'r_men'),
  jsonb_build_object('resposta','recusada','nome',(select txt from ac where chave = 'men_nome'),'cpf','529.982.247-25','motivo','mudei'))$q$, '22023', 'resposta do portal não muda');
reset role;
select teste.ok((select r.evidencia_hash = encode(sha256(convert_to(r.evidencia::text, 'UTF8')), 'hex') and (r.evidencia->'aluno'->>'cpf_conferido_com_matricula')::boolean
                   and r.evidencia->'representante_legal'->>'cpf' = '11144477735' and r.evidencia->>'termo_sha256' = encode(sha256(convert_to(c.termo, 'UTF8')), 'hex')
                 from public.rematriculas r join public.campanhas_rematricula c on c.id = r.campanha_id where r.id = (select v::bigint from rem where chave = 'r_men')),
  'evidência da rematrícula: CPF conferido, representante e hash do termo');
select teste.ok((select count(*) = 0 from public.vinculos where oportunidade_id = (select v from teste.var where k = 'men_op') and marco = 'rematricula'), 'rematrícula aceita não grava vínculo acadêmico');

-- ---------------------------------------------------------------- indicadores e encerramento
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false);
select teste.ok((select (t->>'aceitas')::int = 1 and (t->>'recusadas')::int = 1 and (t->>'bloqueadas')::int = 1
                   and (t->>'taxa_pct')::numeric = round(100.0 / (t->>'elegiveis')::int, 1)
                 from (select public.rpc_rematricula(1)->'campanhas'->0->'totais' t) x), 'indicadores: aceitas, recusadas, bloqueadas e taxa sobre elegíveis');
select teste.ok((public.rpc_status_campanha_rematricula((select v::bigint from rem where chave = 'camp'), 'encerrada')->>'status') = 'encerrada', 'campanha encerrada');
select teste.erro($q$select public.rpc_status_campanha_rematricula((select v::bigint from rem where chave = 'camp'), 'aberta')$q$, '22023', 'campanha encerrada não reabre');
select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false);
select teste.erro($q$select public.rpc_rematricula(1)$q$, 'P0002', 'outra IES não vê a rematrícula');
reset role;
select teste.ok((select count(*) >= 5 from public.auditoria where acao like 'rematricula.%'), 'rematrícula auditada');
