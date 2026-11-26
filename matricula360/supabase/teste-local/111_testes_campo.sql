-- Testes de captação em campo (migração 27).
\set ON_ERROR_STOP on
reset role;
create temp table cmp (chave text primary key, v text);
grant all on cmp to anon, authenticated;
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false);
select teste.erro($q$select public.rpc_salvar_escola(1, '{"nome":"Escola X","rede":"publica","cidade":"Campo Grande","uf":"MS"}')$q$, '42501', 'secretaria não cadastra escola');
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select teste.erro($q$select public.rpc_salvar_escola(1, '{"nome":"Escola X","rede":"publica","cidade":"Campo Grande","uf":"ms1"}')$q$, '23514', 'UF inválida recusada');
insert into cmp select 'esc', public.rpc_salvar_escola(1, '{"nome":"Escola Estadual Sintética","rede":"publica","cidade":"Campo Grande","uf":"ms","inep":"50000001"}')->>'id';
select teste.erro($q$select public.rpc_salvar_escola(1, '{"nome":"Escola Estadual Sintética","rede":"publica","cidade":"Campo Grande","uf":"MS"}')$q$, '22023', 'escola repetida na mesma cidade recusada');
select teste.erro($q$select public.rpc_salvar_visita(1, '{"titulo":"Feira","tipo":"feira","data":"2026-12-01","campanha":"nao-existe"}')$q$, '22023', 'campanha inexistente recusada');
insert into cmp select 'vis', public.rpc_salvar_visita(1, jsonb_build_object('escola_id', (select v from cmp where chave = 'esc'), 'titulo', 'Palestra 3º ano', 'tipo', 'palestra',
  'data', current_date, 'publico_estimado', 120, 'codigo', 'eesint-2026'))->>'id';
select teste.erro($q$select public.rpc_salvar_visita(1, '{"titulo":"Outra","tipo":"visita","data":"2026-12-01","codigo":"eesint-2026"}')$q$, '22023', 'código de visita repetido recusado');

-- ---------------------------------------------------------------- modo feira: lote com repetição, contato existente e rejeição
select teste.ok((select (r->>'recebidos')::int = 2 and (r->>'contatos_existentes')::int = 1 and jsonb_array_length(r->'rejeitados') = 2
                 from (select public.rpc_captar_campo((select v::bigint from cmp where chave = 'vis'), jsonb_build_array(
    jsonb_build_object('id_local','11111111-1111-4111-8111-111111111111','nome','Aluna Feira Um','telefone','67999990001','curso_id',1,'coorte','2027.1',
      'consentimento',true,'consentimento_hash',repeat('a',64),'capturado_em', now() - interval '2 hours'),
    jsonb_build_object('id_local','22222222-2222-4222-8222-222222222222','nome','Ingressante Um','email','ingressante.um@exemplo.invalid','curso_id',1,'coorte','2027.1',
      'consentimento',true,'consentimento_hash',repeat('a',64)),
    jsonb_build_object('id_local','33333333-3333-4333-8333-333333333333','nome','Sem Consentimento','telefone','67999990003','curso_id',1,'coorte','2027.1','consentimento',false),
    jsonb_build_object('id_local','44444444-4444-4444-8444-444444444444','nome','Sem Contato','curso_id',1,'coorte','2027.1','consentimento',true,'consentimento_hash',repeat('a',64))
  )) r) x), 'lote: 2 recebidos (1 contato já existente), 2 rejeitados com motivo');
select teste.ok((select (r->>'recebidos')::int = 0 and (r->>'ja_sincronizados')::int = 1
                 from (select public.rpc_captar_campo((select v::bigint from cmp where chave = 'vis'), jsonb_build_array(
    jsonb_build_object('id_local','11111111-1111-4111-8111-111111111111','nome','Aluna Feira Um','telefone','67999990001','curso_id',1,'coorte','2027.1','consentimento',true,'consentimento_hash',repeat('a',64))
  )) r) x), 'reenvio do mesmo cadastro (sincronização repetida) é ignorado');
reset role;
select teste.ok((select o.visita_id = (select v::bigint from cmp where chave = 'vis') and o.forma_ingresso = 'visita_escolar' and o.responsavel_id = teste.id('comercial_a') and p.base_legal = 'consentimento'
                 from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id where p.telefone = '67999990001'), 'lead criado com a visita, forma de ingresso e responsável');
select teste.ok((select visita_id is null from public.oportunidades where id = (select v from teste.var where k = 'ing1')), 'contato existente não muda de origem');
select teste.ok((select status = 'realizada' from public.visitas_escola where id = (select v::bigint from cmp where chave = 'vis')), 'visita com captação passa a realizada');
select teste.ok((select capturado_em < sincronizado_em - interval '1 hour' from public.captacoes_campo where id_local = '11111111-1111-4111-8111-111111111111'), 'guarda a hora da captura e a da sincronização');
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.ok((select (v->>'leads')::int >= 1 and (v->>'capturados')::int = 2 and v->>'escola' like 'Escola Estadual Sintética%'
                 from jsonb_array_elements(public.rpc_campo(1)->'visitas') v where (v->>'id')::bigint = (select v::bigint from cmp where chave = 'vis')), 'painel por visita');
select teste.ok((select (e->>'visitas')::int = 1 and (e->>'leads')::int >= 1 from jsonb_array_elements(public.rpc_campo(1)->'escolas') e where (e->>'id')::bigint = (select v::bigint from cmp where chave = 'esc')),
  'painel por escola');
select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false);
select teste.erro($q$select public.rpc_captar_campo((select v::bigint from cmp where chave = 'vis'), '[]')$q$, 'P0002', 'outra IES não sincroniza na visita');
reset role;
-- QR code: inscrição no formulário público e vínculo com a visita pelo link pessoal
set role anon;
insert into cmp select 'qr_tok', public.rpc_publico_inscrever('vestibular-2027', '{"nome":"Aluna do QR","email":"aluna.qr@exemplo.invalid","curso_id":1,"aceite":true,"versao_consentimento":2,"tempo_ms":12000}'::jsonb)->>'portal';
select teste.ok((public.rpc_publico_vincular_visita((select v from cmp where chave = 'qr_tok'), 'EESINT-2026')->>'vinculadas')::int = 1, 'QR: inscrição vinculada à visita');
select teste.ok((public.rpc_publico_vincular_visita((select v from cmp where chave = 'qr_tok'), 'eesint-2026')->>'vinculadas')::int = 0, 'QR: vínculo não se repete');
select teste.ok((public.rpc_publico_vincular_visita((select v from cmp where chave = 'qr_tok'), 'nao-existe')->>'vinculadas')::int = 0, 'QR: código inexistente não vincula');
reset role;
select teste.ok((select o.visita_id = (select v::bigint from cmp where chave = 'vis') from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id where p.email = 'aluna.qr@exemplo.invalid'),
  'oportunidade do QR atribuída à visita');
select teste.ok((select count(*) >= 5 from public.auditoria where acao like 'campo.%'), 'captação em campo auditada');
