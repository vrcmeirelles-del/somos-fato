-- Testes da Onda C interna (migração 30): conversas, pendências financeiras, polos e egressos.
\set ON_ERROR_STOP on
reset role;
create temp table oc (chave text primary key, v text);
grant all on oc to anon, authenticated;
insert into oc select 'op_com', o.id::text from public.oportunidades o where o.ies_id = 1 and o.responsavel_id = teste.id('comercial_a') and o.etapa in ('novo','contato','inscrito') order by o.id limit 1;
set role authenticated;

-- ---------------------------------------------------------------- L21 conversas
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro($q$select public.rpc_registrar_recebida((select v::bigint from oc where chave = 'op_com'), 'visita', 'Oi, quero saber o valor')$q$, '22023', 'canal inválido recusado');
select teste.erro($q$select public.rpc_registrar_recebida((select v::bigint from oc where chave = 'op_com'), 'whatsapp_manual', 'Futuro', now() + interval '1 day')$q$, '22023', 'data futura recusada');
select public.rpc_registrar_recebida((select v::bigint from oc where chave = 'op_com'), 'whatsapp_manual', 'Oi, qual o valor da mensalidade de Direito?', now() - interval '3 hours');
select teste.ok((select (f->>'horas')::numeric between 2.9 and 3.1 and f->>'texto' like 'Oi, qual o valor%' from jsonb_array_elements(public.rpc_conversas(1)->'fila') f
                 where (f->>'oportunidade_id')::bigint = (select v::bigint from oc where chave = 'op_com')), 'mensagem recebida entra na fila com o tempo de espera');
select public.rpc_registrar_interacao((select v::bigint from oc where chave = 'op_com'), 'whatsapp_manual', 'Respondi com valores e bolsas vigentes');
select teste.ok((select count(*) = 0 from jsonb_array_elements(public.rpc_conversas(1)->'fila') f where (f->>'oportunidade_id')::bigint = (select v::bigint from oc where chave = 'op_com')),
  'resposta registrada tira da fila');
select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false);
select teste.erro($q$select public.rpc_conversas(1)$q$, '42501', 'secretaria não vê a fila comercial');

-- ---------------------------------------------------------------- L13 pendências financeiras
select set_config('request.jwt.claim.sub', teste.id('financeiro_a')::text, false);
select teste.ok((select (r->>'importadas')::int = 3 and jsonb_array_length(r->'rejeitadas') = 2 from (select public.rpc_importar_pendencias(1, jsonb_build_array(
  jsonb_build_object('email','ingressante.um@exemplo.invalid','competencia','2026-09','valor','1.290,00','vencimento',(current_date - 70)::text,'situacao','aberta'),
  jsonb_build_object('email','ingressante.um@exemplo.invalid','competencia','2026-10','valor','1290','vencimento',(current_date - 40)::text),
  jsonb_build_object('oportunidade_id',(select v from teste.var where k = 'ing2'),'competencia','2026-11','valor','1290','vencimento',(current_date - 5)::text),
  jsonb_build_object('email','nao.existe@exemplo.invalid','competencia','2026-11','valor','10','vencimento','2026-11-10'),
  jsonb_build_object('email','ingressante.um@exemplo.invalid','competencia','2026-13','valor','10','vencimento','2026-11-10'))) r) x),
  'importação: 3 pendências, 2 rejeitadas (aluno inexistente, competência inválida)');
select teste.ok((public.rpc_importar_pendencias(1, jsonb_build_array(jsonb_build_object('email','ingressante.um@exemplo.invalid','competencia','2026-09','valor','1.290,00','vencimento',(current_date - 70)::text)))->>'importadas')::int = 1,
  'reimportar a mesma competência atualiza (idempotente)');
reset role;
select teste.ok((select count(*) = 3 and sum(valor_centavos) = 387000 from public.pendencias_financeiras), 'valores convertidos para centavos sem duplicar');
set role authenticated;
select teste.ok((select (i->>'inadimplentes')::int = 1 and (i->>'em_aberto_centavos')::int = 387000 from (select public.rpc_financeiro(1, 30)->'indicadores' i) x), 'inadimplência: 1 aluno com atraso acima de 30 dias');
-- bloqueio da rematrícula sob comando: nova campanha com ing1 e ing2 pendentes
reset role;
insert into public.campanhas_rematricula(ies_id, periodo, abre_em, fecha_em, termo, status) values (1, '2028.2', current_date - 1, current_date + 10, repeat('Termo de rematrícula do período 2028.2. ', 4), 'aberta');
insert into public.rematriculas(ies_id, campanha_id, oportunidade_id) select 1, c.id, x from public.campanhas_rematricula c, unnest(array[(select v from teste.var where k = 'ing1'), (select v from teste.var where k = 'ing2')]) x where c.periodo = '2028.2' and c.ies_id = 1;
insert into oc select 'camp', id::text from public.campanhas_rematricula where periodo = '2028.2' and ies_id = 1;
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false);
select teste.erro($q$select public.rpc_bloquear_inadimplentes((select v::bigint from oc where chave = 'camp'), 30)$q$, '42501', 'secretaria não bloqueia em lote');
select set_config('request.jwt.claim.sub', teste.id('financeiro_a')::text, false);
select teste.ok((public.rpc_bloquear_inadimplentes((select v::bigint from oc where chave = 'camp'), 30)->>'bloqueadas')::int = 1, 'bloqueio em lote só de quem tem atraso acima de 30 dias');
select teste.ok((select (p->>'rematricula_pendente')::boolean is false from jsonb_array_elements(public.rpc_financeiro(1)->'pendencias') p where p->>'competencia' = '2026-09'), 'pendência mostra que a rematrícula não está mais pendente');
reset role;
insert into oc select 'pend', id::text from public.pendencias_financeiras where competencia = '2026-09';
set role authenticated;
select teste.erro($q$select public.rpc_negociar_pendencia((select v::bigint from oc where chave = 'pend'), 'negociada', 'ok')$q$, '22023', 'negociação sem descrição recusada');
select teste.ok((public.rpc_negociar_pendencia((select v::bigint from oc where chave = 'pend'), 'negociada', 'Acordo em 3 parcelas a partir de dezembro')->>'situacao') = 'negociada', 'negociação registrada');

-- ---------------------------------------------------------------- L18 polos
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro($q$select public.rpc_salvar_polo(1, (select min(id) from public.campus where ies_id = 1), '{"tipo":"polo_parceiro","parceiro":"Parceiro X"}')$q$, '42501', 'comercial não cadastra polo');
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.erro($q$select public.rpc_salvar_polo(1, (select min(id) from public.campus where ies_id = 1), '{"tipo":"polo_parceiro"}')$q$, '22023', 'polo parceiro exige o parceiro');
select public.rpc_salvar_polo(1, (select min(id) from public.campus where ies_id = 1), '{"tipo":"polo_parceiro","parceiro":"Educa Parceiro Sintético Ltda.","regra_repasse":"Conforme contrato de parceria, cláusula 5","meta_ingressos":40}');
select teste.ok((select u->>'tipo' = 'polo_parceiro' and (u->>'leads')::int > 0 and (u->>'ingressos')::int >= 2 and (u->>'meta_ingressos')::int = 40 and u ? 'receita_mensal_centavos'
                 from jsonb_array_elements(public.rpc_polos(1)->'unidades') u where (u->>'id')::bigint = (select min(id) from public.campus where ies_id = 1)), 'painel por unidade com parceiro, meta e funil');
select teste.ok((public.rpc_polos(1)->>'aviso') like '%não calcula pagamento%', 'sem cálculo de repasse');

-- ---------------------------------------------------------------- L20 egressos
select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false);
select teste.erro($q$select public.rpc_registrar_egresso((select v::bigint from oc where chave = 'op_com'), current_date, true)$q$, '22023', 'egresso só de quem foi aluno');
select teste.erro($q$select public.rpc_registrar_egresso((select v from teste.var where k = 'ing1'), current_date + 1, true)$q$, '22023', 'conclusão no futuro recusada');
insert into oc select 'eg1', public.rpc_registrar_egresso((select v from teste.var where k = 'ing1'), current_date, true, array['pos_graduacao'], 'Interesse em direito digital')->>'id';
insert into oc select 'eg2', public.rpc_registrar_egresso((select v from teste.var where k = 'ing2'), current_date, false)->>'id';
select teste.erro($q$select public.rpc_ofertar_egresso((select v::bigint from oc where chave = 'eg1'), 1, '2028.1', 'pos_graduacao')$q$, '42501', 'secretaria não oferta');
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro($q$select public.rpc_ofertar_egresso((select v::bigint from oc where chave = 'eg2'), 1, '2028.1', 'pos_graduacao')$q$, '22023', 'sem consentimento: oferta recusada');
select teste.ok(not (public.rpc_ofertar_egresso((select v::bigint from oc where chave = 'eg1'), 1, '2028.1', 'pos_graduacao')->>'duplicada')::boolean, 'oferta cria nova oportunidade');
select public.rpc_ofertar_egresso((select v::bigint from oc where chave = 'eg1'), 1, '2028.1', 'pos_graduacao');
select teste.ok((select (e->>'ofertas')::int = 1 from jsonb_array_elements(public.rpc_egressos(1)->'egressos') e where (e->>'id')::bigint = (select v::bigint from oc where chave = 'eg1')), 'oferta repetida não duplica: painel conta 1 oferta');
reset role;
select teste.ok((select o.forma_ingresso = 'pos_graduacao' and o.coorte = '2028.1' and o.egresso_origem_id = (select v::bigint from oc where chave = 'eg1')
                 from public.oportunidades o where o.egresso_origem_id is not null), 'oportunidade de pós ligada ao egresso');
select teste.ok((select count(*) >= 8 from public.auditoria where acao in ('conversa.recebida','financeiro.importar','financeiro.bloquear_lote','financeiro.negociar','polo.salvar','egresso.registrar','egresso.ofertar')), 'Onda C auditada');
