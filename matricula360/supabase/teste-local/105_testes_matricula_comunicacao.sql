-- Testes de matrícula online, comunicação (simulação) e integrações/importações (migração 21).
\set ON_ERROR_STOP on
reset role;
create temp table mat_tok (t text);
grant all on mat_tok to anon, authenticated;
set role authenticated;

-- ---------------------------------------------------------------- matrícula online
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.erro('select public.rpc_salvar_contrato(1, ''curto demais'')', '22023', 'contrato curto recusado');
select teste.ok((public.rpc_salvar_contrato(1, repeat('Cláusula de prestação de serviços educacionais conforme regimento da instituição. ', 3))->>'versao')::int = 1, 'contrato v1 publicado');
select teste.ok((select (r->'versoes'->0->>'ativo')::boolean and r->>'aviso' like '[Não verificado]%' from (select public.rpc_contratos(1) r) x), 'contratos com aviso de validação jurídica');
reset role;
-- oportunidade em pré-matrícula com proposta aprovada e vigente (cenário sintético do candidato)
insert into teste.var values ('mat_op', (select o.id from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id where p.email = 'visitante.oh@exemplo.invalid'));
update public.oportunidades set etapa = 'pre_matricula' where id = (select v from teste.var where k = 'mat_op');
insert into public.propostas(ies_id, oportunidade_id, desconto_pct, mensalidade_centavos, valor_final_centavos, validade, status, criado_por)
  select o.ies_id, o.id, 10, 129000, 116100, now() + interval '5 days', 'aprovada', teste.id('comercial_a') from public.oportunidades o where o.id = (select v from teste.var where k = 'mat_op');
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
insert into mat_tok select public.rpc_gerar_acesso_portal((select v from teste.var where k = 'mat_op'))->>'token';
reset role; set role anon;
select teste.ok((select (m->'proposta'->>'valor_final_centavos')::int = 116100 and (m->'contrato'->>'versao')::int = 1 from jsonb_array_elements(public.rpc_publico_portal_matricula((select t from mat_tok))) m),
  'portal mostra proposta aprovada e contrato vigente');
select teste.erro($q$select public.rpc_publico_aceitar_matricula((select t from mat_tok), (select v from teste.var where k = 'mat_op'), 1, 'Outro Nome Qualquer')$q$, '22023', 'nome divergente do cadastro recusado');
select teste.erro($q$select public.rpc_publico_aceitar_matricula((select t from mat_tok), (select v from teste.var where k = 'mat_op'), 99, 'Visitante do Open House')$q$, '22023', 'versão de contrato desatualizada recusada');
select teste.ok((public.rpc_publico_aceitar_matricula((select t from mat_tok), (select v from teste.var where k = 'mat_op'), 1, '  visitante  do open house ')->>'aceito')::boolean, 'aceite eletrônico com nome confirmado');
select teste.erro($q$select public.rpc_publico_aceitar_matricula((select t from mat_tok), (select v from teste.var where k = 'mat_op'), 1, 'Visitante do Open House')$q$, '22023', 'segundo aceite recusado');
reset role;
select teste.ok((select o.etapa = 'matricula_comercial' and o.matricula_comercial_em is not null from public.oportunidades o where o.id = (select v from teste.var where k = 'mat_op')), 'aceite leva à matrícula comercial (transição oficial)');
select teste.ok((select a.contrato_hash = encode(sha256(convert_to(k.texto, 'UTF8')), 'hex') from public.aceites_matricula a join public.contratos_modelo k on k.id = a.contrato_id
                 where a.oportunidade_id = (select v from teste.var where k = 'mat_op')), 'evidência guarda o hash do contrato aceito');
select teste.ok((select status = 'aceita' from public.propostas where oportunidade_id = (select v from teste.var where k = 'mat_op') order by id desc limit 1), 'proposta marcada como aceita');

-- ---------------------------------------------------------------- comunicação (simulação)
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
insert into teste.var values ('modelo', (public.rpc_salvar_modelo_mensagem(1, '{"nome":"Boas-vindas","canal":"email","gatilho":"etapa_novo","assunto":"Recebemos seu interesse","corpo":"Olá, {{nome}}! Recebemos seu interesse em {{curso}} na {{instituicao}}."}'::jsonb)->>'id')::bigint);
select public.rpc_salvar_modelo_mensagem(1, '{"nome":"Contato manual","canal":"whatsapp","gatilho":"manual","corpo":"Oi, {{nome}}, aqui é da equipe de {{curso}}."}'::jsonb);
select teste.ok((select (r->>'simuladas')::int > 0 and (r->>'enviadas')::int = 0 and r->>'modo' = 'simulação' from (select public.rpc_executar_regua(1) r) x), 'régua gera mensagens só em simulação (nada enviado)');
select teste.ok((select (r->>'simuladas')::int = 0 from (select public.rpc_executar_regua(1) r) x), 'régua não duplica mensagens');
reset role;
select teste.ok((select count(*) = 0 from public.mensagens where status = 'enviada'), 'nenhuma mensagem enviada');
select teste.ok((select bool_and(corpo not like '%{{%') from public.mensagens), 'variáveis substituídas no texto');
select teste.ok((select count(*) >= 1 from public.mensagens g join public.oportunidades o on o.id = g.oportunidade_id join public.pessoas p on p.id = o.pessoa_id
                 where g.status = 'bloqueada' and (p.optout_email or p.email is null)) or not exists (select 1 from public.pessoas p join public.oportunidades o on o.pessoa_id = p.id
                 where o.etapa = 'novo' and o.ies_id = 1 and (p.optout_email or p.email is null)), 'opt-out bloqueia a mensagem na régua');
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro('select public.rpc_executar_regua(1)', '42501', 'comercial não executa a régua');
reset role;
insert into teste.var values ('msg_op', (select min(o.id) from public.oportunidades o where o.responsavel_id = teste.id('comercial_a') and o.etapa in ('novo','contato')));
update public.pessoas set telefone = coalesce(telefone, '11977776666'), optout_whatsapp = false
 where id = (select pessoa_id from public.oportunidades where id = (select v from teste.var where k = 'msg_op'));
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.ok((public.rpc_mensagem_manual((select v from teste.var where k = 'msg_op'),
                 (select (m->>'id')::bigint from jsonb_array_elements(public.rpc_comunicacao(1)->'modelos') m where m->>'nome' = 'Contato manual'))->>'texto') like 'Oi, %',
  'atendente gera texto para envio manual');
select teste.ok((select (m->'abertura') = 'null'::jsonb from jsonb_array_elements(public.rpc_comunicacao(1)->'modelos') m limit 1), 'abertura e clique N/D sem provedor');

-- ---------------------------------------------------------------- integrações e importações
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.ok((select jsonb_array_length(r->'itens') = 10 and bool_and(i->>'status' = 'desligada') from (select public.rpc_integracoes(1) r) x, jsonb_array_elements(r->'itens') i group by r),
  'dez integrações registradas, todas desligadas');
select teste.erro('select public.rpc_integracoes(1, ''whatsapp'', ''x'')', '22023', 'pedido de ativação exige descrição');
select teste.ok((select i->>'status' = 'pedido_registrado' from jsonb_array_elements(public.rpc_integracoes(1, 'whatsapp', 'WhatsApp Business oficial para confirmações de inscrição')->'itens') i where i->>'tipo' = 'whatsapp'),
  'pedido registrado não ativa nada');
select teste.ok((select (r->>'importadas')::int = 1 and jsonb_array_length(r->'rejeitadas') = 1 from (select public.rpc_importar_custos(1,
  '[{"campanha":"verao-2027","data":"2026-11-20","valor_centavos":45000,"descricao":"Meta Ads semana 47"},{"campanha":"nao-existe","data":"2026-11-20","valor_centavos":1}]'::jsonb) r) x),
  'importação de custos com relatório por linha');
select teste.ok((select (r->>'repetidas')::int = 1 and (r->>'importadas')::int = 0 from (select public.rpc_importar_custos(1, '[{"campanha":"verao-2027","data":"2026-11-20","valor_centavos":45000,"descricao":"Meta Ads semana 47"}]'::jsonb) r) x),
  'reimportar a mesma linha não duplica custo');
select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false);
select teste.ok((select (r->>'importadas')::int = 1 and jsonb_array_length(r->'rejeitadas') = 1 from (select public.rpc_importar_vinculos(1, jsonb_build_array(
    jsonb_build_object('oportunidade_id', (select v from teste.var where k = 'ing2'), 'marco', 'd90', 'situacao', 'ativo', 'data', current_date),
    jsonb_build_object('email', 'ninguem@exemplo.invalid', 'marco', 'd30', 'situacao', 'ativo', 'data', current_date))) r) x),
  'importação de vínculos acadêmicos com relatório');
reset role;
select teste.ok((select fonte = 'sistema_academico' from public.vinculos where oportunidade_id = (select v from teste.var where k = 'ing2') and marco = 'd90'), 'vínculo importado marcado com a fonte');
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false);
select teste.erro('select public.rpc_importar_custos(1, ''[{"campanha":"verao-2027","data":"2026-11-20","valor_centavos":1}]''::jsonb)', 'P0002', 'gestor de outra IES não importa custos na Alfa');
select teste.erro('select count(*) from public.mensagens', '42501', 'mensagens sem leitura direta');
reset role;
select teste.ok(true, 'fim da bateria de matrícula online, comunicação e integrações');
