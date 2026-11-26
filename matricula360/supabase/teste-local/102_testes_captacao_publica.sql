-- Testes da captação pública, portal do candidato e direitos do titular (migração 18).
\set ON_ERROR_STOP on
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro($q$select public.rpc_salvar_formulario(1, '{"slug":"x"}'::jsonb)$q$, '42501', 'comercial não cria formulário público');
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.erro($q$select public.rpc_salvar_formulario(1, '{"slug":"vestibular-2027","titulo":"Vestibular 2027","cursos":[1,3],"coorte":"2027.1","texto_consentimento":"Autorizo a Faculdade Alfa a usar meus dados para contato sobre o processo seletivo, conforme a LGPD."}'::jsonb)$q$,
  '22023', 'formulário com curso de outra IES recusado');
select teste.erro($q$select public.rpc_salvar_formulario(1, '{"slug":"vestibular-2027","titulo":"Vestibular 2027","cursos":[1,2],"coorte":"2027.1","texto_consentimento":"curto"}'::jsonb)$q$,
  '22023', 'termo de consentimento curto recusado');
insert into teste.var values ('form', (public.rpc_salvar_formulario(1, '{"slug":"vestibular-2027","titulo":"Vestibular 2027","cursos":[1,2],"coorte":"2027.1","texto_consentimento":"Autorizo a Faculdade Alfa a usar meus dados para contato sobre o processo seletivo, conforme a LGPD."}'::jsonb)->>'id')::bigint);
select teste.erro($q$select public.rpc_salvar_formulario(1, '{"slug":"vestibular-2027","titulo":"Outro","cursos":[1],"coorte":"2027.1","texto_consentimento":"Autorizo a Faculdade Alfa a usar meus dados para contato sobre o processo seletivo."}'::jsonb)$q$,
  '23505', 'endereço repetido: conflito');

-- público (anon)
reset role; set role anon;
select set_config('request.jwt.claim.sub', '', false);
select teste.ok((select jsonb_array_length(r->'cursos') = 2 and (r->>'versao_consentimento')::int = 1 and r->>'instituicao' like 'Faculdade Alfa%'
                 from (select public.rpc_publico_formulario('vestibular-2027') r) x), 'anônimo lê o formulário público (cursos e termo)');
select teste.erro('select public.rpc_publico_formulario(''nao-existe'')', 'P0002', 'formulário inexistente: 404');
select teste.erro('select count(*) from public.formularios', '42501', 'anônimo não lê tabelas');
select teste.erro('select public.rpc_formularios(1)', '42501', 'anônimo não executa RPC da equipe');
select teste.erro($q$select public.rpc_publico_inscrever('vestibular-2027', '{"nome":"Rápido Demais","email":"rapido@exemplo.invalid","curso_id":1,"aceite":true,"versao_consentimento":1,"tempo_ms":500}'::jsonb)$q$,
  '22023', 'envio rápido demais recusado');
select teste.ok((public.rpc_publico_inscrever('vestibular-2027', '{"nome":"Robô","email":"robo@exemplo.invalid","curso_id":1,"aceite":true,"versao_consentimento":1,"tempo_ms":9000,"site":"http://spam"}'::jsonb)->>'portal') is null,
  'campo-isca: resposta neutra, nada criado');
select teste.erro($q$select public.rpc_publico_inscrever('vestibular-2027', '{"nome":"Sem Aceite","email":"sem.aceite@exemplo.invalid","curso_id":1,"aceite":false,"versao_consentimento":1,"tempo_ms":9000}'::jsonb)$q$,
  '22023', 'sem aceite do termo vigente: recusado');
select teste.erro($q$select public.rpc_publico_inscrever('vestibular-2027', '{"nome":"Curso Errado","email":"curso.errado@exemplo.invalid","curso_id":3,"aceite":true,"versao_consentimento":1,"tempo_ms":9000}'::jsonb)$q$,
  '22023', 'curso fora do formulário recusado');
reset role;
create temp table portal_tok (t text);
grant all on portal_tok to anon;
set role anon;
insert into portal_tok select public.rpc_publico_inscrever('vestibular-2027', '{"nome":"Candidata Pública","email":"candidata.publica@exemplo.invalid","telefone":"(11) 98888-7777","curso_id":1,"aceite":true,"versao_consentimento":1,"tempo_ms":15000}'::jsonb)->>'portal';
select teste.ok((select length(t) = 64 from portal_tok), 'inscrição nova devolve link do portal (token de 64 caracteres)');
select teste.ok((public.rpc_publico_inscrever('vestibular-2027', '{"nome":"Outra Pessoa Tentando","email":"candidata.publica@exemplo.invalid","curso_id":2,"aceite":true,"versao_consentimento":1,"tempo_ms":15000}'::jsonb)->>'portal') is null,
  'e-mail já cadastrado: sem link (terceiro não acessa dados alheios), resposta neutra');
select teste.ok((select (r->>'nome') = 'Candidata Pública' and jsonb_array_length(r->'inscricoes') = 2 and r->'inscricoes'->1->>'situacao' = 'Inscrição recebida'
                 from (select public.rpc_publico_portal((select t from portal_tok)) r) x), 'portal mostra as inscrições da candidata em linguagem simples');
select teste.erro('select public.rpc_publico_portal(repeat(''a'', 64))', 'P0002', 'token inválido: 404 genérico');
select teste.ok((public.rpc_publico_portal_optout((select t from portal_tok), 'whatsapp')->>'tarefas_suprimidas')::int >= 1, 'opt-out pelo próprio titular suprime tarefas do canal');
select teste.ok((public.rpc_publico_portal_solicitar((select t from portal_tok), 'eliminacao', 'Não quero mais contato')->>'status') = 'aberta', 'titular solicita eliminação');
select teste.erro('select public.rpc_publico_portal_solicitar((select t from portal_tok), ''eliminacao'')', '22023', 'solicitação repetida em análise recusada');

reset role;
select teste.ok((select p.base_legal = 'consentimento' and p.consentimento_versao = 1 and p.consentimento_hash is not null and p.origem like 'formulário:%'
                 from public.pessoas p where p.email = 'candidata.publica@exemplo.invalid'), 'consentimento registrado com versão e hash do termo');
select teste.ok((select count(*) = 1 from public.acessos_candidato a join public.pessoas p on p.id = a.pessoa_id where p.email = 'candidata.publica@exemplo.invalid'
                 and a.token_hash <> (select t from portal_tok)), 'só o hash do token fica no banco');
select teste.ok((select bool_and(o.responsavel_id is not null and o.funil_versao_id is not null) from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id
                 where p.email = 'candidata.publica@exemplo.invalid'), 'lead público distribuído e posicionado no funil');
select teste.ok((select count(*) from public.inscricoes_publicas where resultado = 'isca') = 1, 'tentativa de robô registrada sem dados pessoais');
-- limite por origem
insert into public.inscricoes_publicas(formulario_id, ies_id, origem_hash, resultado) select (select v from teste.var where k = 'form'), 1, privado.origem_hash(), 'criada' from generate_series(1, 5);
set role anon;
select teste.erro($q$select public.rpc_publico_inscrever('vestibular-2027', '{"nome":"Muitas Tentativas","email":"muitas@exemplo.invalid","curso_id":1,"aceite":true,"versao_consentimento":1,"tempo_ms":9000}'::jsonb)$q$,
  '54000', 'limite por origem: 429');
reset role;
delete from public.inscricoes_publicas where resultado = 'criada' and oportunidade_id is null;

-- equipe: link manual, termo versionado, solicitações
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.ok((select (r->>'validade_dias')::int = 90 and length(r->>'token') = 64 from (select public.rpc_gerar_acesso_portal((select min(id) from public.oportunidades where ies_id = 1 and etapa = 'novo' and responsavel_id is not null)) r) x),
  'equipe gera link do portal para envio manual');
select public.rpc_salvar_formulario(1, '{"texto_consentimento":"Autorizo a Faculdade Alfa a usar meus dados para contato sobre o processo seletivo e eventos, conforme a LGPD."}'::jsonb, (select v from teste.var where k = 'form'));
select teste.ok((select (f->>'versao_consentimento')::int = 2 from jsonb_array_elements(public.rpc_formularios(1)) f where (f->>'id')::bigint = (select v from teste.var where k = 'form')), 'termo alterado gera nova versão');
reset role; set role anon;
select teste.erro($q$select public.rpc_publico_inscrever('vestibular-2027', '{"nome":"Versão Antiga","email":"versao.antiga@exemplo.invalid","curso_id":1,"aceite":true,"versao_consentimento":1,"tempo_ms":9000}'::jsonb)$q$,
  '22023', 'aceite de versão antiga do termo recusado');
reset role; set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.erro('select public.rpc_tratar_solicitacao((select (s->>''id'')::bigint from jsonb_array_elements(public.rpc_solicitacoes_titular(1)) s limit 1), ''atendida'', ''ok'')', '22023', 'resposta ao titular obrigatória');
select teste.ok((public.rpc_tratar_solicitacao((select (s->>'id')::bigint from jsonb_array_elements(public.rpc_solicitacoes_titular(1)) s limit 1), 'atendida', 'Dados anonimizados conforme solicitado.')->>'status') = 'atendida',
  'gestor trata a solicitação do titular');
select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false);
select teste.ok(jsonb_array_length(public.rpc_solicitacoes_titular(2)) = 0, 'solicitações isoladas por instituição');
select teste.erro('select public.rpc_salvar_formulario(1, ''{"ativo":false}''::jsonb, (select v from teste.var where k = ''form''))', 'P0002', 'gestor de outra IES não altera o formulário');
reset role;
select teste.ok(true, 'fim da bateria de captação pública');
