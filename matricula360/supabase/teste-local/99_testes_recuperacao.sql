-- Testes de Recuperação e Aceleração (migração 15).
\set ON_ERROR_STOP on
set role authenticated;
-- Base sintética: três leads perdidos com situações diferentes de LGPD.
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
insert into teste.var values ('rec_ok', (public.rpc_criar_oportunidade(1, jsonb_build_object('nome', 'Perdido Elegível', 'email', 'perdido.ok@exemplo.invalid', 'curso_id', 1,
  'forma_ingresso', 'vestibular', 'coorte', '2027.1', 'base_legal', 'consentimento', 'origem', 'site'), 'rec-ok-000001')->>'id')::bigint);
insert into teste.var values ('rec_base', (public.rpc_criar_oportunidade(1, jsonb_build_object('nome', 'Perdido Contratual', 'email', 'perdido.base@exemplo.invalid', 'curso_id', 1,
  'forma_ingresso', 'vestibular', 'coorte', '2027.1', 'base_legal', 'procedimentos_preliminares_contrato', 'origem', 'site'), 'rec-base-00001')->>'id')::bigint);
insert into teste.var values ('rec_opt', (public.rpc_criar_oportunidade(1, jsonb_build_object('nome', 'Perdido Optout', 'email', 'perdido.opt@exemplo.invalid', 'curso_id', 1,
  'forma_ingresso', 'vestibular', 'coorte', '2027.1', 'base_legal', 'consentimento', 'origem', 'site'), 'rec-opt-000001')->>'id')::bigint);
select public.rpc_mover_etapa((select v from teste.var where k = 'rec_ok'), 'perdido', 1, 'Mensalidade acima do orçamento', 'rec-mov-ok-01');
select public.rpc_mover_etapa((select v from teste.var where k = 'rec_base'), 'perdido', 1, 'Sem retorno', 'rec-mov-base-1');
select public.rpc_mover_etapa((select v from teste.var where k = 'rec_opt'), 'perdido', 1, 'Desistiu', 'rec-mov-opt-01');
select public.rpc_optout((select v from teste.var where k = 'rec_opt'), 'email');

select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.ok((select (x->>'elegivel')::boolean = false and x->>'motivo_inelegivel' like 'Em carência%' from jsonb_array_elements(public.rpc_recuperaveis(1, 30)) x
                 where (x->>'id')::bigint = (select v from teste.var where k = 'rec_ok')), 'perda recente respeita a carência');
select teste.ok((select (x->>'elegivel')::boolean from jsonb_array_elements(public.rpc_recuperaveis(1, 0)) x where (x->>'id')::bigint = (select v from teste.var where k = 'rec_ok')),
  'sem carência, perdido com consentimento e canal disponível é elegível');
select teste.ok((select x->>'motivo_inelegivel' like 'Base legal%' from jsonb_array_elements(public.rpc_recuperaveis(1, 0)) x where (x->>'id')::bigint = (select v from teste.var where k = 'rec_base')),
  'base legal contratual não permite novo contato após a perda');
select teste.ok((select x->>'motivo_inelegivel' like 'Sem canal%' from jsonb_array_elements(public.rpc_recuperaveis(1, 0)) x where (x->>'id')::bigint = (select v from teste.var where k = 'rec_opt')),
  'opt-out no único canal torna inelegível');
select teste.ok((select bool_and(x->>'motivo_perda' ilike '%orçamento%') from jsonb_array_elements(public.rpc_recuperaveis(1, 0, 'orçamento')) x), 'filtro por motivo de perda');

-- protocolo
select teste.erro('select public.rpc_salvar_protocolo(1, ''{"nome":"Sem meta","tipo":"recuperacao_base","responsavel":"Equipe","prazo":"2027-01-31","coorte_destino":"2027.1"}''::jsonb)', '22023', 'protocolo sem meta recusado');
insert into teste.var values ('prot', (public.rpc_salvar_protocolo(1, '{"nome":"Recuperação de base 2027.1","tipo":"recuperacao_base","responsavel":"Coordenação comercial",
  "prazo":"2027-02-15","checklist":["Revisar motivo de perda","Oferecer condição vigente","Registrar contato"],"meta":2,"custo_centavos":50000,"coorte_destino":"2027.1","carencia_dias":0}'::jsonb)->>'id')::bigint);
insert into teste.var values ('prot_prox', (public.rpc_salvar_protocolo(1, '{"nome":"Reingresso 2027.2","tipo":"reingresso","responsavel":"Coordenação comercial",
  "prazo":"2027-06-30","meta":1,"coorte_destino":"2027.2","carencia_dias":0}'::jsonb)->>'id')::bigint);
select teste.ok((select (r->>'selecionadas')::int = 1 and jsonb_array_length(r->'recusadas') = 2
                 from (select public.rpc_selecionar_recuperacao((select v from teste.var where k = 'prot'),
                         array[(select v from teste.var where k = 'rec_ok'), (select v from teste.var where k = 'rec_base'), (select v from teste.var where k = 'rec_opt')]) r) x),
  'seleção aceita só elegíveis e devolve o motivo das recusadas');
select teste.ok((select jsonb_array_length((public.rpc_selecionar_recuperacao((select v from teste.var where k = 'prot'), array[(select v from teste.var where k = 'rec_ok')]))->'recusadas') = 1),
  'mesma oportunidade não entra duas vezes no protocolo');
insert into teste.var values ('item', (select (i->>'id')::bigint from jsonb_array_elements(public.rpc_recuperacao(1)->'protocolos') p, jsonb_array_elements(p->'itens') i
                                        where (p->>'id')::bigint = (select v from teste.var where k = 'prot')));
select teste.ok((select p->>'status' = 'em_execucao' from jsonb_array_elements(public.rpc_recuperacao(1)->'protocolos') p where (p->>'id')::bigint = (select v from teste.var where k = 'prot')),
  'protocolo passa a em execução ao receber a base');

-- execução pelo atendente
select set_config('request.jwt.claim.sub', teste.id('com_dir_a')::text, false);
select teste.erro('select public.rpc_tratar_recuperacao((select v from teste.var where k = ''item''), ''contatada'', ''tentativa'')', 'P0002', 'atendente não trata item atribuído a outro');
select teste.ok((select coalesce(sum(jsonb_array_length(p->'itens')), 0) = 0 from jsonb_array_elements(public.rpc_recuperacao(1)->'protocolos') p), 'atendente não vê itens de outros');
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro('select public.rpc_selecionar_recuperacao((select v from teste.var where k = ''prot''), array[1])', '42501', 'atendente não seleciona base');
select teste.erro('select public.rpc_tratar_recuperacao((select v from teste.var where k = ''item''), ''contatada'', '''')', '22023', 'contato sem resumo recusado');
select teste.ok((public.rpc_tratar_recuperacao((select v from teste.var where k = 'item'), 'contatada', 'Conversou sobre bolsa vigente')->>'acao') = 'contatada', 'atendente registra contato');
select teste.ok((public.rpc_tratar_recuperacao((select v from teste.var where k = 'item'), 'reativar', 'Aceitou nova conversa')->>'oportunidade')::bigint = (select v from teste.var where k = 'rec_ok'),
  'reativação na mesma coorte reabre a própria oportunidade');
select teste.ok((select etapa = 'contato' from public.oportunidades where id = (select v from teste.var where k = 'rec_ok')), 'perdido → contato pela transição oficial');
select teste.ok((public.rpc_detalhe((select v from teste.var where k = 'rec_ok'))->'historico') @? '$[*] ? (@.acao == "oportunidade.etapa" && @.dados.para == "contato" && @.dados.de == "perdido")',
  'histórico preserva a perda e registra a reativação');
select teste.ok((select count(*) = 1 from public.tarefas where oportunidade_id = (select v from teste.var where k = 'rec_ok') and tipo = 'recuperacao' and status = 'aberta'), 'tarefa de recuperação criada');
select teste.erro('select public.rpc_tratar_recuperacao((select v from teste.var where k = ''item''), ''descartada'', ''x x x'')', '22023', 'item reativado não muda mais');

-- reativação em outra coorte cria nova oportunidade vinculada
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select public.rpc_mover_etapa((select v from teste.var where k = 'rec_ok'), 'perdido', (select versao from public.oportunidades where id = (select v from teste.var where k = 'rec_ok')), 'Adiou para o próximo semestre', 'rec-mov-ok-02');
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select public.rpc_selecionar_recuperacao((select v from teste.var where k = 'prot_prox'), array[(select v from teste.var where k = 'rec_ok')]);
insert into teste.var values ('item2', (select (i->>'id')::bigint from jsonb_array_elements(public.rpc_recuperacao(1)->'protocolos') p, jsonb_array_elements(p->'itens') i
                                         where (p->>'id')::bigint = (select v from teste.var where k = 'prot_prox')));
insert into teste.var values ('op_nova', (public.rpc_tratar_recuperacao((select v from teste.var where k = 'item2'), 'reativar')->>'oportunidade')::bigint);
select teste.ok((select coorte = '2027.2' and recuperada_de = (select v from teste.var where k = 'rec_ok') and etapa = 'contato' and funil_versao_id is not null
                 from public.oportunidades where id = (select v from teste.var where k = 'op_nova')), 'outra coorte: nova oportunidade vinculada à de origem, já no funil');
select teste.ok((select etapa = 'perdido' from public.oportunidades where id = (select v from teste.var where k = 'rec_ok')), 'oportunidade de origem permanece perdida (histórico intacto)');
select teste.ok((select (p->>'reativadas')::int = 1 and (p->>'atingimento_meta')::numeric = 0.5 and (p->>'custo_por_reativacao_centavos')::bigint = 50000
                 from jsonb_array_elements(public.rpc_recuperacao(1)->'protocolos') p where (p->>'id')::bigint = (select v from teste.var where k = 'prot')),
  'resultado do protocolo: reativadas, atingimento da meta e custo por reativação');
select teste.erro('select public.rpc_salvar_protocolo(1, ''{"status":"concluido"}''::jsonb, (select v from teste.var where k = ''prot''))', '22023', 'protocolo só conclui com resultado registrado');

-- sprints
insert into teste.var values ('sprint', (public.rpc_salvar_sprint(1, '{"nome":"Sprint de janeiro","objetivo":"Reativar a base perdida de 2026","inicio":"2027-01-04","fim":"2027-01-18"}'::jsonb)->>'id')::bigint);
insert into teste.var values ('sitem', (public.rpc_salvar_item_sprint((select v from teste.var where k = 'sprint'), '{"entrega":"Lista revisada da base","responsavel":"Equipe comercial"}'::jsonb)->>'id')::bigint);
select teste.erro('select public.rpc_salvar_item_sprint((select v from teste.var where k = ''sprint''), ''{"status":"impedido"}''::jsonb, (select v from teste.var where k = ''sitem''))', '22023', 'impedimento exige descrição');
select public.rpc_salvar_item_sprint((select v from teste.var where k = 'sprint'), '{"status":"impedido","impedimento":"Aguardando condição comercial aprovada"}'::jsonb, (select v from teste.var where k = 'sitem'));
select teste.erro('select public.rpc_salvar_sprint(1, ''{"status":"encerrada"}''::jsonb, (select v from teste.var where k = ''sprint''))', '22023', 'sprint não encerra sem reavaliação');
select teste.ok((select (s->>'impedimentos')::int = 1 from jsonb_array_elements(public.rpc_recuperacao(1)->'sprints') s), 'impedimentos contados na sprint');
select public.rpc_salvar_sprint(1, '{"status":"encerrada","reavaliacao":"Base revisada; condição comercial atrasou duas semanas; repetir com aprovação prévia."}'::jsonb, (select v from teste.var where k = 'sprint'));
select teste.erro('select public.rpc_salvar_item_sprint((select v from teste.var where k = ''sprint''), ''{"entrega":"Nova","responsavel":"X"}''::jsonb)', '22023', 'sprint encerrada não recebe itens');

-- isolamento
select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false);
select teste.ok(jsonb_array_length(public.rpc_recuperacao(2)->'protocolos') = 0, 'recuperação isolada por instituição');
select teste.erro('select public.rpc_tratar_recuperacao((select v from teste.var where k = ''item2''), ''descartada'', ''cruzado'')', 'P0002', 'gestor de outra IES não alcança item');
select teste.erro('select public.rpc_recuperaveis(1)', 'P0002', 'gestor de outra IES não lista a base perdida da Alfa');
select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false);
select teste.erro('select public.rpc_recuperacao(1)', '42501', 'secretaria sem acesso à recuperação comercial');
select teste.erro('select count(*) from public.recuperacoes', '42501', 'recuperações sem leitura direta');
reset role;
select teste.ok(true, 'fim da bateria de recuperação');
