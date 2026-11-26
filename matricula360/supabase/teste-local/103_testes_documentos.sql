-- Testes de documentos protegidos (migração 19).
\set ON_ERROR_STOP on
reset role;
grant select on teste.var to anon;
create temp table doc_tok (t text);
grant all on doc_tok to anon, authenticated;
create temp table doc_b64 (k text primary key, b text);
grant all on doc_b64 to anon, authenticated;
insert into doc_b64 values ('pdf', encode(convert_to('%PDF-1.4 documento sintético de teste', 'UTF8'), 'base64')),
  ('png', encode('\x89504e470d0a1a0a0000000d49484452'::bytea, 'base64')),
  ('exe', encode(convert_to('MZ executável disfarçado', 'UTF8'), 'base64'));
select teste.ok((select count(*) >= 7 from public.documentos_exigidos where ies_id = 1), 'checklist inicial próprio criado');

set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
insert into teste.var values ('doc_op', (select min(id) from public.oportunidades where ies_id = 1 and etapa = 'novo' and forma_ingresso = 'vestibular'));
insert into doc_tok select public.rpc_gerar_acesso_portal((select v from teste.var where k = 'doc_op'))->>'token';
reset role; set role anon;
select teste.ok((select jsonb_array_length(x->'checklist') >= 3 from jsonb_array_elements(public.rpc_publico_portal_documentos((select t from doc_tok))) x
                 where (x->>'oportunidade_id')::bigint = (select v from teste.var where k = 'doc_op')), 'candidato vê o checklist da inscrição no portal');
select teste.erro($q$select public.rpc_publico_enviar_documento((select t from doc_tok), (select v from teste.var where k = 'doc_op'), 'identidade', 'rg.exe', (select b from doc_b64 where k = 'exe'))$q$,
  '22023', 'arquivo que não é PDF/JPG/PNG recusado pelo conteúdo');
select teste.erro($q$select public.rpc_publico_enviar_documento((select t from doc_tok), (select v from teste.var where k = 'doc_op'), 'diploma', 'diploma.pdf', (select b from doc_b64 where k = 'pdf'))$q$,
  '22023', 'documento fora do checklist recusado');
select teste.erro($q$select public.rpc_publico_enviar_documento((select t from doc_tok), 1, 'identidade', 'rg.pdf', (select b from doc_b64 where k = 'pdf'))$q$,
  'P0002', 'candidato não envia para inscrição de outra pessoa');
select teste.ok((public.rpc_publico_enviar_documento((select t from doc_tok), (select v from teste.var where k = 'doc_op'), 'identidade', 'rg.pdf', (select b from doc_b64 where k = 'pdf'))->>'mime') = 'application/pdf',
  'candidato envia PDF pelo portal');
select teste.ok((public.rpc_publico_enviar_documento((select t from doc_tok), (select v from teste.var where k = 'doc_op'), 'ensino_medio', 'historico.png', (select b from doc_b64 where k = 'png'))->>'mime') = 'image/png',
  'candidato envia PNG pelo portal');
select teste.erro('select count(*) from public.documentos_conteudo', '42501', 'conteúdo sem leitura direta (anon)');

reset role; set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.ok((select (r->>'pode_revisar')::boolean = false and jsonb_array_length(r->'historico') = 2 from (select public.rpc_documentos((select v from teste.var where k = 'doc_op')) r) x)
  or not exists (select 1 from public.oportunidades where id = (select v from teste.var where k = 'doc_op') and responsavel_id = teste.id('comercial_a')), 'comercial responsável vê a situação, sem revisar');
select teste.erro('select public.rpc_baixar_documento((select (h->>''id'')::bigint from jsonb_array_elements(public.rpc_documentos((select v from teste.var where k = ''doc_op''))->''historico'') h limit 1))', 'P0002',
  'comercial não baixa documento') ;
select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false);
insert into teste.var values ('doc_id', (select (h->>'id')::bigint from jsonb_array_elements(public.rpc_documentos((select v from teste.var where k = 'doc_op'))->'historico') h where h->>'tipo' = 'identidade'));
select teste.ok((select convert_from(decode(r->>'base64', 'base64'), 'UTF8') like '%PDF-1.4%' from (select public.rpc_baixar_documento((select v from teste.var where k = 'doc_id')) r) x), 'secretaria baixa o documento');
select teste.ok((public.rpc_detalhe((select v from teste.var where k = 'doc_op'))->'historico') @? '$[*] ? (@.acao == "documento.baixar")', 'download auditado');
select teste.erro('select public.rpc_revisar_documento((select v from teste.var where k = ''doc_id''), ''recusado'', ''x'')', '22023', 'recusa exige motivo');
select teste.ok((public.rpc_revisar_documento((select v from teste.var where k = 'doc_id'), 'recusado', 'Imagem ilegível, envie novamente')->>'status') = 'recusado', 'secretaria recusa com motivo');
reset role; set role anon;
select teste.ok((select (i->'documento'->>'motivo_recusa') = 'Imagem ilegível, envie novamente' from jsonb_array_elements(public.rpc_publico_portal_documentos((select t from doc_tok))) x, jsonb_array_elements(x->'checklist') i
                 where (x->>'oportunidade_id')::bigint = (select v from teste.var where k = 'doc_op') and i->>'tipo' = 'identidade'), 'candidato vê o motivo da recusa');
select public.rpc_publico_enviar_documento((select t from doc_tok), (select v from teste.var where k = 'doc_op'), 'identidade', 'rg-novo.pdf', (select b from doc_b64 where k = 'pdf'));
reset role;
select teste.ok((select count(*) = 1 from public.documentos where oportunidade_id = (select v from teste.var where k = 'doc_op') and tipo = 'identidade' and status = 'substituido'), 'versão anterior preservada como substituída');

-- exigência ligável antes da validação documental
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select public.rpc_configurar_documentos(1, true);
reset role;
insert into teste.var values ('doc_mc', (select o.id from public.oportunidades o where o.ies_id = 1 and o.etapa = 'matricula_comercial' and not o.val_documental limit 1));
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false);
select teste.erro($q$select public.rpc_validar((select v from teste.var where k = 'doc_mc'), 'documental', 'valida', 'conferido', (select versao from public.oportunidades where id = (select v from teste.var where k = 'doc_mc')))$q$,
  '22023', 'com exigência ligada, validação documental sem checklist aprovado é recusada')
  where (select v from teste.var where k = 'doc_mc') is not null;
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select public.rpc_configurar_documentos(1, false);
select teste.ok((select (r->>'exigir_documentos')::boolean = false and jsonb_array_length(r->'itens') >= 7 from (select public.rpc_configurar_documentos(1, null, '{"tipo":"foto","descricao":"Foto 3x4 recente","obrigatorio":false}'::jsonb) r) x),
  'gestor configura a exigência e o checklist');
select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false);
select teste.erro('select public.rpc_baixar_documento((select v from teste.var where k = ''doc_id''))', 'P0002', 'gestor de outra IES não baixa o documento');
select teste.erro('select count(*) from public.documentos', '42501', 'documentos sem leitura direta');
reset role;
select teste.ok(true, 'fim da bateria de documentos');
