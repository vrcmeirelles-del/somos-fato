-- Testes de banca e aproveitamento de estudos (migração 29).
\set ON_ERROR_STOP on
reset role;
create temp table bca (chave text primary key, v text);
grant all on bca to anon, authenticated;
insert into public.processos_seletivos(ies_id, coorte, nome, tipo, inscricoes_ate, criado_por) values (1, '2027.1', 'Análise curricular com banca', 'analise_curricular', current_date + 10, teste.id('gestor_a'));
insert into bca select 'proc', id::text from public.processos_seletivos where nome = 'Análise curricular com banca';
insert into bca select 'op', o.id::text from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id where o.ies_id = 1 and o.curso_id = 1 and o.etapa in ('novo','contato','inscrito') and p.anonimizada_em is null order by o.id limit 1;
insert into public.candidaturas(ies_id, processo_id, oportunidade_id) values (1, (select v::bigint from bca where chave = 'proc'), (select v::bigint from bca where chave = 'op'));
insert into bca select 'cand', id::text from public.candidaturas where processo_id = (select v::bigint from bca where chave = 'proc');
set role authenticated;

select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.erro($q$select public.rpc_avaliar_banca((select v::bigint from bca where chave = 'cand'), '{"a":5}', 'Parecer sem banca configurada')$q$, '22023', 'sem banca configurada: recusado');
select teste.erro($q$select public.rpc_configurar_banca((select v::bigint from bca where chave = 'proc'), '[{"id":"hist","texto":"Histórico","peso":0}]', 2)$q$, '22023', 'peso zero recusado');
select teste.ok((public.rpc_configurar_banca((select v::bigint from bca where chave = 'proc'),
  '[{"id":"hist","texto":"Histórico escolar","peso":2},{"id":"carta","texto":"Carta de intenção","peso":1}]', 2, 150)->>'soma_pesos')::numeric = 3, 'banca: 2 critérios, 2 avaliadores, divergência máxima 150');
select teste.erro($q$select public.rpc_avaliar_candidatura((select v::bigint from bca where chave = 'cand'), '{"resultado":"aprovado","justificativa":"Aprovado sem banca"}')$q$, '22023', 'decidir antes da banca: recusado');
select teste.erro($q$select public.rpc_avaliar_banca((select v::bigint from bca where chave = 'cand'), '{"hist":11,"carta":5}', 'Nota fora da escala de zero a dez')$q$, '22023', 'nota acima de 10 recusada');
select teste.ok((public.rpc_avaliar_banca((select v::bigint from bca where chave = 'cand'), '{"hist":9,"carta":9}', 'Histórico consistente e carta clara')->>'nota_final')::numeric = 900, 'avaliador 1: nota ponderada 900');
select teste.erro($q$select public.rpc_avaliar_banca((select v::bigint from bca where chave = 'cand'), '{"hist":1,"carta":1}', 'Tentando avaliar duas vezes')$q$, '22023', 'mesmo avaliador não avalia duas vezes');
select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false);
select teste.ok((select r->'avaliacoes' = 'null'::jsonb and (r->'situacao'->>'avaliacoes')::int = 1 and not (r->>'ja_avaliei')::boolean from (select public.rpc_banca((select v::bigint from bca where chave = 'cand')) r) x),
  'avaliação às cegas: antes da própria nota, não vê as dos outros');
select teste.ok((select (r->'banca'->>'exige_mais_um')::boolean and not (r->'banca'->>'completa')::boolean
                 from (select public.rpc_avaliar_banca((select v::bigint from bca where chave = 'cand'), '{"hist":5,"carta":6}', 'Histórico mediano, carta genérica') r) x),
  'avaliador 2 diverge 333 pontos (> 150): exige terceiro avaliador');
select teste.ok((select jsonb_array_length(r->'avaliacoes') = 2 from (select public.rpc_banca((select v::bigint from bca where chave = 'cand')) r) x), 'depois de avaliar, vê as notas da banca');
select teste.erro($q$select public.rpc_avaliar_candidatura((select v::bigint from bca where chave = 'cand'), '{"resultado":"aprovado","justificativa":"Média suficiente"}')$q$, '22023', 'divergência sem terceiro avaliador: decisão recusada');
select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false);
select public.rpc_avaliar_banca((select v::bigint from bca where chave = 'cand'), '{"hist":8,"carta":7}', 'Terceira leitura: bom histórico');
select teste.ok(((public.rpc_avaliar_candidatura((select v::bigint from bca where chave = 'cand'), '{"resultado":"aprovado","justificativa":"Média da banca 711 com terceira leitura"}'))->>'id') is not null,
  'banca completa: decisão humana registrada');
select teste.erro($q$select public.rpc_configurar_banca((select v::bigint from bca where chave = 'proc'), '[{"id":"x","texto":"Outro","peso":1}]', 1)$q$, '42501', 'coordenação não muda a rubrica');
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.erro($q$select public.rpc_configurar_banca((select v::bigint from bca where chave = 'proc'), '[{"id":"x","texto":"Outro","peso":1}]', 1)$q$, '22023', 'rubrica não muda depois de a banca avaliar');

-- ---------------------------------------------------------------- aproveitamento de estudos
reset role;
update public.oportunidades set forma_ingresso = 'transferencia' where id = (select v::bigint from bca where chave = 'op');
insert into bca select 'op_vest', o.id::text from public.oportunidades o where o.ies_id = 1 and o.curso_id = 1 and o.forma_ingresso = 'vestibular' and o.etapa in ('novo','contato','inscrito') order by o.id limit 1;
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false);
select teste.erro($q$select public.rpc_salvar_aproveitamento((select v::bigint from bca where chave = 'op_vest'), '{"instituicao_origem":"Universidade X","curso_origem":"Direito"}')$q$, '22023', 'aproveitamento só para transferência e afins');
select teste.erro($q$select public.rpc_salvar_aproveitamento((select v::bigint from bca where chave = 'op'), '{"instituicao_origem":"Universidade Sintética","curso_origem":"Direito",
  "disciplinas":[{"nome":"Teoria Geral do Estado","carga":60,"situacao":"aproveitada"}]}')$q$, '22023', 'aproveitada sem disciplina equivalente: recusado');
select teste.ok((public.rpc_salvar_aproveitamento((select v::bigint from bca where chave = 'op'), '{"instituicao_origem":"Universidade Sintética","curso_origem":"Direito",
  "disciplinas":[{"nome":"Teoria Geral do Estado","carga":60,"nota":"8,5","situacao":"aproveitada","equivalente":"Ciência Política"},
                 {"nome":"Introdução ao Direito","carga":80,"situacao":"parcial","equivalente":"Introdução ao Estudo do Direito","carga_aproveitada":40},
                 {"nome":"Economia","carga":60,"situacao":"pendente"}]}')->>'carga_aproveitada')::int = 100, 'rascunho da análise: 100 h aproveitadas');
select teste.erro($q$select public.rpc_salvar_aproveitamento((select v::bigint from bca where chave = 'op'), '{"parecer":"Parecer completo da coordenação","semestre_sugerido":2}', true)$q$, '22023', 'não conclui com disciplina pendente');
reset role; set role anon;
insert into bca select 'tok', null;
reset role; set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
update bca set v = public.rpc_gerar_acesso_portal((select v::bigint from bca where chave = 'op'))->>'token' where chave = 'tok';
reset role; set role anon;
select teste.ok((select x->>'status' = 'em_analise' and x->'disciplinas' = 'null'::jsonb from jsonb_array_elements(public.rpc_publico_portal_aproveitamento((select v from bca where chave = 'tok'))) x),
  'portal: em análise, sem detalhes');
reset role; set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false);
select teste.ok((public.rpc_salvar_aproveitamento((select v::bigint from bca where chave = 'op'), '{"disciplinas":[{"nome":"Teoria Geral do Estado","carga":60,"situacao":"aproveitada","equivalente":"Ciência Política"},
                 {"nome":"Introdução ao Direito","carga":80,"situacao":"parcial","equivalente":"Introdução ao Estudo do Direito","carga_aproveitada":40},
                 {"nome":"Economia","carga":60,"situacao":"nao_aproveitada"}],"parecer":"Aproveitamento parcial conforme ementas comparadas","semestre_sugerido":2}', true)->>'status') = 'concluida',
  'análise concluída com parecer e semestre sugerido');
select teste.erro($q$select public.rpc_salvar_aproveitamento((select v::bigint from bca where chave = 'op'), '{"parecer":"Mudança depois de concluir"}')$q$, '22023', 'análise concluída não muda');
reset role; set role anon;
select teste.ok((select (x->>'carga_aproveitada')::int = 100 and (x->>'semestre_sugerido')::int = 2 and jsonb_array_length(x->'disciplinas') = 3
                 from jsonb_array_elements(public.rpc_publico_portal_aproveitamento((select v from bca where chave = 'tok'))) x), 'portal mostra o resultado concluído');
reset role;
select teste.ok((select count(*) >= 6 from public.auditoria where acao in ('seletivo.banca','seletivo.banca_avaliar','aproveitamento.salvar')), 'banca e aproveitamento auditados');
