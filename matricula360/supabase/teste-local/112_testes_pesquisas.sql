-- Testes de pesquisas (migração 28).
\set ON_ERROR_STOP on
reset role;
create temp table psq (chave text primary key, v text);
create temp table psq_tok (op bigint primary key, tok text);
grant all on psq, psq_tok to anon, authenticated;
-- seis oportunidades perdidas na Alfa (público "perdido")
with alvo as (select id from (select distinct on (o.pessoa_id) o.id from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id
  where o.ies_id = 1 and o.etapa in ('novo','contato') and p.anonimizada_em is null and (select count(*) from public.oportunidades x where x.pessoa_id = o.pessoa_id) = 1 order by o.pessoa_id, o.id) z order by id desc limit 6)
update public.oportunidades set etapa = 'perdido', motivo_perda = 'Escolheu outra instituição' where id in (select id from alvo);
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false);
select teste.erro($q$select public.rpc_salvar_pesquisa(1, '{"nome":"X","publico":"perdido","perguntas":[{"id":"p1","tipo":"nps","texto":"Recomendaria?"}]}')$q$, '42501', 'coordenação não cria pesquisa');
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.erro($q$select public.rpc_salvar_pesquisa(1, '{"nome":"Ruim","publico":"perdido","perguntas":[{"id":"p1","tipo":"nps","texto":"A?"},{"id":"p1","tipo":"texto","texto":"Repetida"}]}')$q$, '22023', 'pergunta com id repetido recusada');
select teste.erro($q$select public.rpc_salvar_pesquisa(1, '{"nome":"Ruim","publico":"perdido","perguntas":[{"id":"p1","tipo":"opcao","texto":"Escolha uma","opcoes":["só uma"]}]}')$q$, '22023', 'opção com menos de 2 alternativas recusada');
insert into psq select 'q', public.rpc_salvar_pesquisa(1, '{"nome":"Por que não nos escolheu","publico":"perdido","min_respostas":5,"perguntas":[
  {"id":"motivo","tipo":"opcao","texto":"Principal motivo","opcoes":["Preço","Horário","Distância","Outra instituição","Desisti de estudar agora"]},
  {"id":"nps","tipo":"nps","texto":"De 0 a 10, quanto recomendaria nosso atendimento?"},
  {"id":"atend","tipo":"escala5","texto":"Como avalia o atendimento?"},
  {"id":"coment","tipo":"texto","texto":"O que poderíamos ter feito diferente?"}]}')->>'id';
-- tokens do portal para as perdidas
insert into psq_tok select o.id, public.rpc_gerar_acesso_portal(o.id)->>'token' from public.oportunidades o where o.ies_id = 1 and o.etapa = 'perdido' and o.motivo_perda = 'Escolheu outra instituição';
reset role; set role anon;
select teste.ok((select count(*) = 0 from psq_tok t, jsonb_array_elements(public.rpc_publico_portal_pesquisas(t.tok)) x), 'pesquisa em rascunho não aparece no portal');
reset role; set role authenticated;
select teste.ok((public.rpc_salvar_pesquisa(1, '{"status":"ativa"}', (select v::bigint from psq where chave = 'q'))->>'id') is not null, 'pesquisa ativada');
select teste.erro($q$select public.rpc_salvar_pesquisa(1, '{"nome":"Novo nome"}', (select v::bigint from psq where chave = 'q'))$q$, '22023', 'pesquisa ativa não muda perguntas');
reset role; set role anon;
select teste.ok((select count(*) = 1 from jsonb_array_elements(public.rpc_publico_portal_pesquisas((select tok from psq_tok order by op limit 1)))), 'perdido vê a pesquisa no portal');
select teste.erro($q$select public.rpc_publico_responder_pesquisa((select tok from psq_tok order by op limit 1), (select v::bigint from psq where chave = 'q'), (select op from psq_tok order by op limit 1), '{"nps":"11"}')$q$, '22023', 'NPS acima de 10 recusado');
select teste.erro($q$select public.rpc_publico_responder_pesquisa((select tok from psq_tok order by op limit 1), (select v::bigint from psq where chave = 'q'), (select op from psq_tok order by op limit 1), '{"motivo":"Inventado"}')$q$, '22023', 'opção inexistente recusada');
select teste.erro($q$select public.rpc_publico_responder_pesquisa((select tok from psq_tok order by op limit 1), (select v::bigint from psq where chave = 'q'), (select op from psq_tok order by op limit 1), '{}')$q$, '22023', 'resposta vazia recusada');
select teste.erro($q$select public.rpc_publico_responder_pesquisa((select tok from psq_tok order by op limit 1), (select v::bigint from psq where chave = 'q'), (select v from teste.var where k = 'ing1'), '{"nps":"9"}')$q$, 'P0002', 'não responde por oportunidade de outra pessoa');
-- quatro respostas: ainda abaixo do mínimo
select public.rpc_publico_responder_pesquisa(t.tok, (select v::bigint from psq where chave = 'q'), t.op,
  jsonb_build_object('motivo', (array['Preço','Preço','Horário','Outra instituição'])[n], 'nps', (array['10','9','3','6'])[n], 'atend', '4', 'coment', 'Comentário sintético ' || n))
  from (select op, tok, row_number() over (order by op) n from psq_tok) t where n <= 4;
select teste.erro($q$select public.rpc_publico_responder_pesquisa((select tok from psq_tok order by op limit 1), (select v::bigint from psq where chave = 'q'), (select op from psq_tok order by op limit 1), '{"nps":"9"}')$q$, '22023', 'resposta repetida recusada');
reset role; set role authenticated;
select teste.ok((select r->>'motivo' like 'N/D%' and not (r->>'suficiente')::boolean and r->'por_pergunta' is null and (r->>'respostas')::int = 4
                 from (select q->'resultado' r from jsonb_array_elements(public.rpc_pesquisas(1)->'pesquisas') q where (q->>'id')::bigint = (select v::bigint from psq where chave = 'q')) x),
  'abaixo do mínimo: resultados N/D (protege quem respondeu)');
reset role; set role anon;
select public.rpc_publico_responder_pesquisa(t.tok, (select v::bigint from psq where chave = 'q'), t.op, '{"motivo":"Distância","nps":"8","coment":"Muito longe de casa"}')
  from (select op, tok, row_number() over (order by op) n from psq_tok) t where n = 5;
reset role; set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('reitoria_a')::text, false);
select teste.ok((select (r->>'suficiente')::boolean and (r->>'nps')::int = 0 and (r->'por_pergunta'->'motivo'->>'Preço')::int = 2
                   and jsonb_array_length(r->'por_pergunta'->'coment') = 5 and (r->>'elegiveis')::int >= 6 and r::text not like '%@%'
                 from (select q->'resultado' r from jsonb_array_elements(public.rpc_pesquisas(1)->'pesquisas') q where (q->>'id')::bigint = (select v::bigint from psq where chave = 'q')) x),
  'com o mínimo: NPS (2 promotores, 2 detratores em 5 = 0), distribuição e comentários sem identificação');
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro($q$select public.rpc_pesquisas(1)$q$, '42501', 'comercial não vê resultados de pesquisa');
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.ok((public.rpc_salvar_pesquisa(1, '{"status":"encerrada"}', (select v::bigint from psq where chave = 'q'))->>'id') is not null, 'pesquisa encerrada');
reset role; set role anon;
select teste.ok((select count(*) = 0 from psq_tok t, jsonb_array_elements(public.rpc_publico_portal_pesquisas(t.tok)) x), 'encerrada some do portal');
reset role;
