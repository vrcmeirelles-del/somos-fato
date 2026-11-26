-- Testes do aceite eletrônico reforçado (migração 22). Usa o cenário de 105 (mat_op em pré-matrícula, proposta aprovada, mat_tok).
\set ON_ERROR_STOP on
reset role;
create temp table ac (chave text primary key, txt text);
grant all on ac to anon, authenticated;
insert into ac values ('prop', (select id::text from public.propostas where oportunidade_id = (select v from teste.var where k = 'mat_op') and status = 'aprovada' order by id desc limit 1));
insert into ac values ('tok', (select t from mat_tok));
-- monta o pedido de aceite do candidato maior de idade; "extra" sobrescreve campos
create function pg_temp.dados(extra jsonb default '{}'::jsonb) returns jsonb language sql as $$
  select jsonb_build_object('contrato_versao', 2, 'proposta_id', (select txt::bigint from ac where chave = 'prop'),
    'li_contrato', true, 'concordo_condicoes', true, 'ciente_arrependimento', true,
    'nome', 'Visitante do Open House', 'cpf', '529.982.247-25', 'nascimento', '2000-05-10',
    'codigo', (select txt from ac where chave = 'cod')) || extra $$;
create function pg_temp.aceitar(d jsonb) returns jsonb language sql as $$
  select public.rpc_publico_aceitar_matricula((select txt from ac where chave = 'tok'), (select v from teste.var where k = 'mat_op'), d) $$;
grant execute on function pg_temp.dados(jsonb), pg_temp.aceitar(jsonb) to anon, authenticated;

-- ---------------------------------------------------------------- contrato com destaque de cláusulas
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.erro($q$select public.rpc_salvar_contrato(1, repeat('Cláusula de prestação de serviços educacionais conforme regimento. ', 3) || '**cláusula sem fechamento')$q$,
  '22023', 'destaque aberto (** sem fechamento) recusado');
select teste.ok((public.rpc_salvar_contrato(1, repeat('Cláusula de prestação de serviços educacionais conforme regimento. ', 3)
  || E'\n**Cláusula limitativa: multa de 10% na desistência após o início das aulas.**')->>'versao')::int = 2, 'contrato v2 com cláusula em destaque publicado');
reset role;
select teste.ok((select (dados->>'destaques')::int = 1 from public.auditoria where acao = 'contrato.publicar' order by id desc limit 1), 'auditoria registra quantas cláusulas estão em destaque');

-- ---------------------------------------------------------------- portal e código de confirmação
set role anon;
select teste.ok((select m->>'procedimento' = 'aceite-v2' and m->'confirmacao'->>'destino' = 'v***@exemplo.invalid' and (m->'contrato'->>'versao')::int = 2
                   and (m->>'prazo_arrependimento_dias')::int = 7
                 from jsonb_array_elements(public.rpc_publico_portal_matricula((select txt from ac where chave = 'tok'))) m),
  'portal informa procedimento reforçado, contato mascarado, contrato v2 e prazo de arrependimento');
select teste.erro('select pg_temp.aceitar(pg_temp.dados())', '22023', 'aceite sem código solicitado recusado');
insert into ac select 'cod', r->>'codigo_simulacao' from (select public.rpc_publico_codigo_aceite((select txt from ac where chave = 'tok'), (select v from teste.var where k = 'mat_op')) r) x;
select teste.ok((select txt ~ '^\d{6}$' from ac where chave = 'cod'), 'código de 6 dígitos emitido (simulação: exibido no portal)');
select teste.erro($q$select public.rpc_publico_codigo_aceite((select txt from ac where chave = 'tok'), (select v from teste.var where k = 'mat_op'))$q$, '54000', 'novo código antes de 1 minuto: 429');
select teste.erro($q$select public.rpc_publico_codigo_aceite(repeat('a', 64), (select v from teste.var where k = 'mat_op'))$q$, 'P0002', 'código com link inválido: 404');

-- ---------------------------------------------------------------- validações do aceite
select teste.erro($q$select pg_temp.aceitar(pg_temp.dados('{"ciente_arrependimento":false}'))$q$, '22023', 'sem as três declarações: recusado');
select teste.erro($q$select pg_temp.aceitar(pg_temp.dados('{"cpf":"111.111.111-11"}'))$q$, '22023', 'CPF inválido recusado');
select teste.erro($q$select pg_temp.aceitar(pg_temp.dados('{"cpf":"529.982.247-24"}'))$q$, '22023', 'CPF com dígito verificador errado recusado');
select teste.erro($q$select pg_temp.aceitar(pg_temp.dados('{"proposta_id":0}'))$q$, '22023', 'condições da proposta divergentes recusadas');
select teste.erro($q$select pg_temp.aceitar(pg_temp.dados('{"contrato_versao":1}'))$q$, '22023', 'versão antiga do contrato recusada');
select teste.erro($q$select pg_temp.aceitar(pg_temp.dados('{"nome":"Outro Nome Qualquer"}'))$q$, '22023', 'nome divergente do cadastro recusado');
select teste.erro($q$select pg_temp.aceitar(pg_temp.dados('{"nascimento":"2015-01-01"}'))$q$, '22023', 'idade abaixo de 14 anos recusada');
select teste.ok((select (r->>'aceito')::boolean = false and (r->>'tentativas_restantes')::int = 4 from (select pg_temp.aceitar(pg_temp.dados('{"codigo":"x"}')) r) x),
  'código incorreto: recusado sem lançar erro, com tentativas restantes');
reset role;
select teste.ok((select tentativas = 1 from public.codigos_aceite where oportunidade_id = (select v from teste.var where k = 'mat_op')), 'tentativa errada fica registrada');
set role anon;

-- ---------------------------------------------------------------- aceite válido (maior de idade)
select teste.ok((select (r->>'aceito')::boolean and r->>'evidencia_hash' ~ '^[0-9a-f]{64}$' from (select pg_temp.aceitar(pg_temp.dados('{"nome":"  visitante  do open house "}')) r) x),
  'aceite reforçado concluído com hash da evidência');
reset role;
select teste.ok((select a.menor = false and a.cpf_candidato = '52998224725' and a.responsavel_nome is null and a.confirmacao_modo = 'simulacao'
                   and a.evidencia_hash = encode(sha256(convert_to(a.evidencia::text, 'UTF8')), 'hex')
                   and a.evidencia->'condicoes'->>'valor_final_centavos' = '116100' and a.evidencia->'contrato'->>'sha256' = a.contrato_hash
                   and a.evidencia->'declaracoes'->>'ciente_do_prazo_de_arrependimento' = 'true'
                   and a.arrependimento_ate = a.aceito_em + interval '7 days'
                 from public.aceites_matricula a where a.oportunidade_id = (select v from teste.var where k = 'mat_op')),
  'evidência única: contrato, condições, identificação, declarações; SHA-256 confere');
select teste.ok((select o.etapa = 'matricula_comercial' from public.oportunidades o where o.id = (select v from teste.var where k = 'mat_op')), 'aceite leva à matrícula comercial');
select teste.ok((select count(*) = 0 from public.codigos_aceite where oportunidade_id = (select v from teste.var where k = 'mat_op')), 'código usado é descartado');
select teste.ok((select count(*) = 1 and bool_and(corpo like '%******%' and corpo not like '%' || (select txt from ac where chave = 'cod') || '%' and status = 'simulada')
                 from public.mensagens where oportunidade_id = (select v from teste.var where k = 'mat_op') and modelo_id is null and corpo like '%código de confirmação%'),
  'mensagem do código registrada em simulação, sem o código em claro');
select teste.ok((select dados->>'evidencia_sha256' ~ '^[0-9a-f]{64}$' from public.auditoria where acao = 'matricula.aceite' order by id desc limit 1), 'auditoria do aceite guarda o hash da evidência');
set role anon;
select teste.erro($q$select public.rpc_publico_codigo_aceite((select txt from ac where chave = 'tok'), (select v from teste.var where k = 'mat_op'))$q$, '22023', 'após o aceite não há novo código');

-- ---------------------------------------------------------------- comprovante
select teste.ok((select (r->>'evidencia_integra')::boolean and (r->>'contrato_integro')::boolean and r->>'contrato_texto' like '%**Cláusula limitativa%'
                   and encode(sha256(convert_to(r->>'evidencia_texto', 'UTF8')), 'hex') = r->>'evidencia_hash'
                 from (select public.rpc_publico_comprovante_aceite((select txt from ac where chave = 'tok'), (select v from teste.var where k = 'mat_op')) r) x),
  'comprovante do portal: texto integral do contrato e evidência íntegra (hash recalculável)');
reset role; set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
select teste.ok((public.rpc_comprovante_aceite((select v from teste.var where k = 'mat_op'))->>'evidencia_integra')::boolean, 'equipe da IES vê o comprovante');
select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false);
select teste.erro($q$select public.rpc_comprovante_aceite((select v from teste.var where k = 'mat_op'))$q$, 'P0002', 'outra IES não vê o comprovante');
reset role;
select teste.ok((select count(*) = 1 from public.auditoria where acao = 'matricula.comprovante_ver'), 'consulta da equipe ao comprovante é auditada');
-- adulteração detectada
update public.aceites_matricula set evidencia = jsonb_set(evidencia, '{condicoes,valor_final_centavos}', '99') where oportunidade_id = (select v from teste.var where k = 'mat_op');
set role anon;
select teste.ok((public.rpc_publico_comprovante_aceite((select txt from ac where chave = 'tok'), (select v from teste.var where k = 'mat_op'))->>'evidencia_integra')::boolean = false,
  'evidência adulterada é denunciada no comprovante');
reset role;
update public.aceites_matricula set evidencia = jsonb_set(evidencia, '{condicoes,valor_final_centavos}', '116100') where oportunidade_id = (select v from teste.var where k = 'mat_op');

-- ---------------------------------------------------------------- arrependimento
set role anon;
select teste.ok((select (m->'aceite'->>'pode_desistir')::boolean from jsonb_array_elements(public.rpc_publico_portal_matricula((select txt from ac where chave = 'tok'))) m), 'portal oferece desistência no prazo');
select teste.ok((public.rpc_publico_desistir_matricula((select txt from ac where chave = 'tok'), (select v from teste.var where k = 'mat_op'), 'Mudei de cidade')->>'cancelado')::boolean,
  'desistência no prazo de 7 dias pelo portal');
select teste.erro($q$select public.rpc_publico_desistir_matricula((select txt from ac where chave = 'tok'), (select v from teste.var where k = 'mat_op'))$q$, '22023', 'desistência repetida recusada');
select teste.ok((select m->'aceite'->>'desistencia_em' is not null and not (m->'aceite'->>'pode_desistir')::boolean and m->>'etapa' = 'cancelado'
                 from jsonb_array_elements(public.rpc_publico_portal_matricula((select txt from ac where chave = 'tok'))) m), 'portal mostra a desistência registrada');
reset role;
select teste.ok((select o.etapa = 'cancelado' and o.motivo_cancelamento like 'Arrependimento%Mudei de cidade' and a.desistencia_motivo = 'Mudei de cidade'
                 from public.oportunidades o join public.aceites_matricula a on a.oportunidade_id = o.id where o.id = (select v from teste.var where k = 'mat_op')),
  'matrícula cancelada com motivo e desistência no aceite');
select teste.ok((select count(*) = 1 from public.auditoria where acao = 'matricula.arrependimento'), 'arrependimento auditado');

-- ---------------------------------------------------------------- candidato menor de idade: representante legal
insert into teste.var values ('men_op', (select o.id from public.oportunidades o where o.ies_id = 1 and o.etapa in ('novo','contato','inscrito')
  and o.id <> (select v from teste.var where k = 'mat_op') order by o.id limit 1));
update public.oportunidades set etapa = 'pre_matricula' where id = (select v from teste.var where k = 'men_op');
insert into public.propostas(ies_id, oportunidade_id, desconto_pct, mensalidade_centavos, valor_final_centavos, validade, status, criado_por)
  select o.ies_id, o.id, 0, 99000, 99000, now() + interval '5 days', 'aprovada', teste.id('comercial_a') from public.oportunidades o where o.id = (select v from teste.var where k = 'men_op');
insert into ac select 'men_nome', p.nome from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id where o.id = (select v from teste.var where k = 'men_op');
insert into ac select 'men_prop', id::text from public.propostas where oportunidade_id = (select v from teste.var where k = 'men_op') and status = 'aprovada';
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false);
insert into ac select 'men_tok', public.rpc_gerar_acesso_portal((select v from teste.var where k = 'men_op'))->>'token';
reset role;
create function pg_temp.dmen(extra jsonb default '{}'::jsonb) returns jsonb language sql as $$
  select jsonb_build_object('contrato_versao', 2, 'proposta_id', (select txt::bigint from ac where chave = 'men_prop'),
    'li_contrato', true, 'concordo_condicoes', true, 'ciente_arrependimento', true,
    'nome', (select txt from ac where chave = 'men_nome'), 'cpf', '529.982.247-25', 'nascimento', (current_date - interval '16 years')::date::text,
    'codigo', (select txt from ac where chave = 'men_cod'),
    'responsavel', jsonb_build_object('nome', 'Maria Responsável Sintética', 'cpf', '111.444.777-35', 'nascimento', '1975-03-02', 'vinculo', 'mae', 'declaro', true)) || extra $$;
create function pg_temp.aceitar_men(d jsonb) returns jsonb language sql as $$
  select public.rpc_publico_aceitar_matricula((select txt from ac where chave = 'men_tok'), (select v from teste.var where k = 'men_op'), d) $$;
grant execute on function pg_temp.dmen(jsonb), pg_temp.aceitar_men(jsonb) to anon;
set role anon;
insert into ac select 'men_cod', public.rpc_publico_codigo_aceite((select txt from ac where chave = 'men_tok'), (select v from teste.var where k = 'men_op'))->>'codigo_simulacao';
select teste.erro($q$select pg_temp.aceitar_men(pg_temp.dmen() - 'responsavel')$q$, '22023', 'menor de 18 sem representante legal: recusado');
select teste.erro($q$select pg_temp.aceitar_men(pg_temp.dmen('{"responsavel":{"nome":"Maria Responsável Sintética","cpf":"529.982.247-25","nascimento":"1975-03-02","vinculo":"mae","declaro":true}}'))$q$,
  '22023', 'representante com o mesmo CPF do candidato: recusado');
select teste.erro($q$select pg_temp.aceitar_men(jsonb_set(pg_temp.dmen(), '{responsavel,nascimento}', to_jsonb((current_date - interval '17 years')::date::text)))$q$,
  '22023', 'representante menor de idade: recusado');
select teste.erro($q$select pg_temp.aceitar_men(jsonb_set(pg_temp.dmen(), '{responsavel,declaro}', 'false'))$q$, '22023', 'representante sem a declaração: recusado');
select teste.erro($q$select pg_temp.aceitar_men(jsonb_set(pg_temp.dmen(), '{responsavel,vinculo}', '"vizinho"'))$q$, '22023', 'vínculo fora da lista: recusado');
select teste.ok((pg_temp.aceitar_men(pg_temp.dmen())->>'aceito')::boolean, 'menor aceita com o representante legal');
reset role;
select teste.ok((select a.menor and a.responsavel_cpf = '11144477735' and a.responsavel_vinculo = 'mae'
                   and a.evidencia->'representante_legal'->>'declarou_representar_ou_assistir' = 'true' and (a.evidencia->'candidato'->>'menor_de_18')::boolean
                 from public.aceites_matricula a where a.oportunidade_id = (select v from teste.var where k = 'men_op')), 'evidência registra o representante legal');
update public.aceites_matricula set arrependimento_ate = now() - interval '1 day' where oportunidade_id = (select v from teste.var where k = 'men_op');
set role anon;
select teste.erro($q$select public.rpc_publico_desistir_matricula((select txt from ac where chave = 'men_tok'), (select v from teste.var where k = 'men_op'))$q$, '22023', 'desistência fora do prazo: recusada (vai à secretaria)');
reset role;
