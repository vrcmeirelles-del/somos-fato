-- Matrícula 360° — testes de isolamento (RLS) no banco REAL, para colar no SQL Editor do Supabase.
-- Projeto: jbimijcvvekomovodfze. Gerado por scripts/gerar-teste-remoto.mjs a partir de supabase/teste-local/.
-- COMO LER O RESULTADO: o editor vai mostrar um "erro" de propósito, porque é assim que tudo é desfeito.
--   * "RESULTADO: N verificações aprovadas, 0 falhas"  => tudo certo; nada ficou gravado.
--   * "FALHOU: ..."                                     => uma verificação falhou; nada ficou gravado.
--   * "ABORTADO: ..."                                   => o banco já tinha dados; nada foi executado.
do $bloco$
declare n int;
begin
  if exists (select 1 from public.ies) or exists (select 1 from public.usuarios) then
    raise exception 'ABORTADO: o banco já tem dados; este teste só roda em banco vazio.';
  end if;
  execute $x$ alter table public.usuarios drop constraint if exists usuarios_id_fkey $x$;
  execute $x$ alter table public.ies alter column id restart with 1 $x$;
  execute $x$ alter table public.campus alter column id restart with 1 $x$;
  execute $x$ alter table public.cursos alter column id restart with 1 $x$;
  execute $x$ alter table public.pessoas alter column id restart with 1 $x$;
  execute $x$ alter table public.oportunidades alter column id restart with 1 $x$;
  execute $x$ create schema teste $x$;
  execute $x$ create table teste.usuario (apelido text primary key, id uuid not null) $x$;
  execute $x$ insert into teste.usuario values
  ('master',      '00000000-0000-0000-0000-000000000001'),
  ('gestor_a',    '00000000-0000-0000-0000-0000000000a1'),
  ('reitoria_a',  '00000000-0000-0000-0000-0000000000a2'),
  ('coord_dir_a', '00000000-0000-0000-0000-0000000000a3'),
  ('comercial_a', '00000000-0000-0000-0000-0000000000a4'),
  ('com_dir_a',   '00000000-0000-0000-0000-0000000000a5'),
  ('secretaria_a','00000000-0000-0000-0000-0000000000a6'),
  ('financeiro_a','00000000-0000-0000-0000-0000000000a7'),
  ('gestor_b',    '00000000-0000-0000-0000-0000000000b1'),
  ('comercial_b', '00000000-0000-0000-0000-0000000000b4'),
  ('revogado_a',  '00000000-0000-0000-0000-0000000000a9') $x$;
  execute $x$ insert into public.usuarios(id, nome, master) select id, apelido, apelido = 'master' from teste.usuario $x$;
  execute $x$ insert into public.ies(nome) values ('Faculdade Alfa (fictícia)'), ('Centro Universitário Beta (fictício)') $x$;
  execute $x$ insert into public.campus(ies_id, nome) values (1, 'Centro'), (2, 'Norte') $x$;
  execute $x$ insert into public.cursos(ies_id, campus_id, nome, turno, modalidade, mensalidade_centavos, desconto_max_pct) values
  (1, 1, 'Direito', 'noturno', 'presencial', 129000, 30),
  (1, 1, 'Administração', 'ead', 'ead', 39900, 40),
  (2, 2, 'Psicologia', 'matutino', 'presencial', 115000, 25),
  (2, 2, 'Enfermagem', 'noturno', 'presencial', 98000, 25) $x$;
  execute $x$ insert into public.escopos(usuario_id, ies_id, abrangencia, curso_id, papel)
select u.id, x.ies, case when x.curso is null then 'ies' else 'curso' end, x.curso, x.papel from (values
  ('gestor_a', 1, null::bigint, 'gestor'), ('reitoria_a', 1, null, 'reitoria'), ('coord_dir_a', 1, 1, 'coordenador'),
  ('comercial_a', 1, null, 'comercial'), ('com_dir_a', 1, 1, 'comercial'), ('secretaria_a', 1, null, 'secretaria'),
  ('financeiro_a', 1, null, 'financeiro'), ('gestor_b', 2, null, 'gestor'), ('comercial_b', 2, null, 'comercial'),
  ('revogado_a', 1, null, 'comercial')) as x(apelido, ies, curso, papel)
join teste.usuario u on u.apelido = x.apelido $x$;
  execute $x$ update public.usuarios set revogado_em = now() where id = (select id from teste.usuario where apelido = 'revogado_a') $x$;
  execute $x$ insert into public.metas values (1, 1, '2027.1', 10), (1, 2, '2027.1', 6) $x$;
  execute $x$ create function teste.id(p text) returns uuid language sql stable as $$ select id from teste.usuario where apelido = p $$ $x$;
  execute $x$ create function teste.ok(p boolean, p_nome text) returns void language plpgsql as $$
begin
  if p is distinct from true then raise exception 'FALHOU: %', p_nome; end if;
  raise notice 'OK  %', p_nome;
end $$ $x$;
  execute $x$ create function teste.erro(p_sql text, p_codigo text, p_nome text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlstate = p_codigo or (sqlstate = 'PGRST' and sqlerrm::jsonb->>'code' = p_codigo) then
      raise notice 'OK  % (SQLSTATE %)', p_nome, p_codigo; return;
    end if;
    raise exception 'FALHOU: % — esperado %, obtido % (%)', p_nome, p_codigo, sqlstate, sqlerrm;
  end;
  raise exception 'FALHOU: % — deveria ter falhado com %', p_nome, p_codigo;
end $$ $x$;
  execute $x$ grant usage on schema teste to anon, authenticated $x$;
  execute $x$ grant select on teste.usuario to anon, authenticated $x$;
  execute $x$ grant execute on all functions in schema teste to anon, authenticated $x$;
  execute $x$ create table teste.var (k text primary key, v bigint) $x$;
  execute $x$ grant all on teste.var to authenticated $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select public.rpc_criar_oportunidade(1, jsonb_build_object('nome', 'Cand ' || g, 'email', 'a' || g || '@exemplo.invalid',
  'curso_id', 1 + (g % 2), 'forma_ingresso', 'enem', 'coorte', '2027.1', 'base_legal', 'consentimento', 'origem', 'site'))
from generate_series(1, 8) g $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_b')::text, false) $x$;
  execute $x$ select public.rpc_criar_oportunidade(2, jsonb_build_object('nome', 'Cand B' || g, 'email', 'b' || g || '@exemplo.invalid',
  'curso_id', 3 + (g % 2), 'forma_ingresso', 'vestibular', 'coorte', '2027.1', 'base_legal', 'consentimento', 'origem', 'evento'))
from generate_series(1, 4) g $x$;
  execute $x$ reset role $x$;
  execute $x$ create table teste.resultado (n serial, nome text) $x$;
  execute $x$ grant insert on teste.resultado to anon, authenticated $x$;
  execute $x$ grant usage on sequence teste.resultado_n_seq to anon, authenticated $x$;
  execute $x$ create or replace function teste.ok(p boolean, p_nome text) returns void language plpgsql as $f$
   begin if p is distinct from true then raise exception 'FALHOU: %', p_nome; end if; insert into teste.resultado(nome) values (p_nome); end $f$ $x$;
  execute $x$ create or replace function teste.erro(p_sql text, p_codigo text, p_nome text) returns void language plpgsql as $f$
   begin
     begin execute p_sql;
     exception when others then
       if sqlstate = p_codigo or (sqlstate = 'PGRST' and sqlerrm::jsonb->>'code' = p_codigo) then insert into teste.resultado(nome) values (p_nome); return; end if;
       raise exception 'FALHOU: % — esperado %, obtido % (%)', p_nome, p_codigo, sqlstate, sqlerrm;
     end;
     raise exception 'FALHOU: % — deveria ter falhado com %', p_nome, p_codigo;
   end $f$ $x$;
  execute $x$ set role anon $x$;
  execute $x$ select teste.erro('select count(*) from public.oportunidades', '42501', 'anon: sem permissão de leitura') $x$;
  execute $x$ select teste.erro('select public.rpc_bi(1, ''2027.1'')', '42501', 'anon: não executa RPC') $x$;
  execute $x$ reset role $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.ok((select count(*) from public.oportunidades) = 8, 'gestor Alfa vê só as 8 oportunidades da Alfa') $x$;
  execute $x$ select teste.ok((select count(*) from public.oportunidades where ies_id = 2) = 0, 'gestor Alfa não vê nada da Beta') $x$;
  execute $x$ select teste.ok((select count(*) from public.pessoas where ies_id = 2) = 0, 'gestor Alfa não vê pessoas da Beta') $x$;
  execute $x$ select teste.ok((select count(*) from public.ies) = 1, 'gestor Alfa vê só a própria IES') $x$;
  execute $x$ select teste.erro('select public.rpc_mover_etapa(9, ''contato'', 1)', 'P0002', 'IDOR: mover oportunidade da Beta => não encontrado') $x$;
  execute $x$ select teste.erro('select public.rpc_listar_oportunidades(2)', 'P0002', 'IDOR: listar IES alheia => não encontrado') $x$;
  execute $x$ select teste.erro('select public.rpc_bi(2, ''2027.1'')', 'P0002', 'IDOR: BI de IES alheia => não encontrado') $x$;
  execute $x$ select teste.erro('select public.rpc_mover_etapa(999999, ''contato'', 1)', 'P0002', 'ID inexistente => não encontrado') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false) $x$;
  execute $x$ select teste.ok((select count(*) from public.oportunidades) = 4, 'gestor Beta vê só as 4 da Beta') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.erro('update public.oportunidades set etapa = ''confirmado'' where id = 1', '42501', 'UPDATE direto bloqueado') $x$;
  execute $x$ select teste.erro('update public.oportunidades set val_documental = true where id = 1', '42501', 'alteração direta de validação bloqueada') $x$;
  execute $x$ select teste.erro('insert into public.escopos(usuario_id, ies_id, papel) values (auth.uid(), 2, ''gestor'')', '42501', 'autoconceder escopo bloqueado') $x$;
  execute $x$ select teste.erro('update public.usuarios set master = true where id = auth.uid()', '42501', 'autopromoção a Master bloqueada') $x$;
  execute $x$ select teste.erro('delete from public.auditoria', '42501', 'DELETE na auditoria bloqueado') $x$;
  execute $x$ select teste.erro('select privado.auditar(1, ''x'', ''y'', ''1'')', '42501', 'auxiliar interno de auditoria não executável') $x$;
  execute $x$ select teste.erro('select * from privado.idempotencia', '42501', 'tabela de idempotência inacessível') $x$;
  execute $x$ select teste.erro('select public.rpc_conceder_escopo(auth.uid(), 2, null, ''gestor'')', '42501', 'gestor não usa RPC de Master') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false) $x$;
  execute $x$ select teste.ok((select count(*) from public.oportunidades) = 4 and (select bool_and(curso_id = 1) from public.oportunidades), 'coordenador vê só Direito') $x$;
  execute $x$ select teste.ok((select count(*) from public.pessoas) = 0, 'coordenador não lê tabela de pessoas (minimização)') $x$;
  execute $x$ select teste.ok((select bool_and((x->>'dados_mascarados')::boolean and x->>'email' like '%***@%')
                 from jsonb_array_elements(public.rpc_listar_oportunidades(1)->'itens') x), 'coordenador recebe contatos mascarados') $x$;
  execute $x$ select teste.ok(public.rpc_bi(1, '2027.1')->>'cobertura' = 'cursos_autorizados', 'BI do coordenador limitado aos cursos') $x$;
  execute $x$ select teste.erro('select public.rpc_mover_etapa(2, ''contato'', 1)', '42501', 'coordenador não opera funil') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('reitoria_a')::text, false) $x$;
  execute $x$ select teste.ok((select count(*) from public.oportunidades) = 8, 'reitoria vê a IES inteira') $x$;
  execute $x$ select teste.ok((select count(*) from public.pessoas) = 0, 'reitoria não lê dados pessoais') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('com_dir_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_criar_oportunidade(1, '{"nome":"X Y","email":"xy@exemplo.invalid","curso_id":2,"forma_ingresso":"enem","coorte":"2027.1","base_legal":"consentimento","origem":"site"}')$q$,
  '42501', 'comercial de Direito não cria em Administração') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('master')::text, false) $x$;
  execute $x$ select teste.ok((select count(*) from public.oportunidades) = 0 and (select count(*) from public.pessoas) = 0, 'Master sem escopo não vê candidatos') $x$;
  execute $x$ select teste.ok((select count(*) from public.ies) = 2, 'Master vê cadastro das IES') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('revogado_a')::text, false) $x$;
  execute $x$ select teste.ok((select count(*) from public.oportunidades) = 0, 'usuário revogado não lê nada') $x$;
  execute $x$ select teste.erro($q$select public.rpc_criar_oportunidade(1, '{"nome":"X Y","email":"rv@exemplo.invalid","curso_id":1,"forma_ingresso":"enem","coorte":"2027.1","base_legal":"consentimento","origem":"site"}')$q$,
  '42501', 'usuário revogado não escreve') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_criar_oportunidade(1, '{"nome":"Sem Base","email":"sb@exemplo.invalid","curso_id":1,"forma_ingresso":"enem","coorte":"2027.1","origem":"site"}')$q$,
  '22023', 'sem base legal não entra') $x$;
  execute $x$ select teste.ok((public.rpc_criar_oportunidade(1, '{"nome":"Dup","email":"A2@EXEMPLO.INVALID","curso_id":1,"forma_ingresso":"enem","coorte":"2027.1","base_legal":"consentimento","origem":"site"}')->>'duplicada')::boolean,
  'deduplicação por e-mail normalizado') $x$;
  execute $x$ select teste.ok((select (public.rpc_criar_oportunidade(1, '{"nome":"Idem","email":"idem@exemplo.invalid","curso_id":2,"forma_ingresso":"evento","coorte":"2027.2","base_legal":"consentimento","origem":"feira"}', 'chave-idem-0001')->>'duplicada')::boolean = false), 'primeira chamada cria') $x$;
  execute $x$ select teste.ok((public.rpc_criar_oportunidade(1, '{"nome":"Idem","email":"idem@exemplo.invalid","curso_id":2,"forma_ingresso":"evento","coorte":"2027.2","base_legal":"consentimento","origem":"feira"}', 'chave-idem-0001')->>'repeticao')::boolean,
  'repetição com a mesma chave devolve a resposta gravada') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select count(*) from public.auditoria where acao = 'oportunidade.criar' and dados->>'coorte' = '2027.2') = 1, 'repetição não gerou segunda auditoria') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ insert into teste.var values ('op', (select id from public.oportunidades where ies_id = 1 and curso_id = 1 and coorte = '2027.1' order by id limit 1)) $x$;
  execute $x$ select teste.erro('select public.rpc_mover_etapa((select v from teste.var where k=''op''), ''matricula_comercial'', 1)', '22023', 'pular etapas é recusado') $x$;
  execute $x$ select public.rpc_mover_etapa((select v from teste.var where k='op'), 'contato', 1) $x$;
  execute $x$ select teste.erro('select public.rpc_mover_etapa((select v from teste.var where k=''op''), ''inscrito'', 1)', '40001', 'versão antiga => conflito') $x$;
  execute $x$ select public.rpc_mover_etapa((select v from teste.var where k='op'), 'inscrito', 2) $x$;
  execute $x$ select teste.erro('select public.rpc_mover_etapa((select v from teste.var where k=''op''), ''confirmado'', 3)', '22023', 'confirmar por transição comum é recusado') $x$;
  execute $x$ insert into teste.var values ('prop', (public.rpc_criar_proposta((select v from teste.var where k='op'), 45)->>'id')::bigint) $x$;
  execute $x$ select teste.ok((select status from public.propostas where id = (select v from teste.var where k='prop')) = 'pendente_aprovacao', 'desconto acima do limite fica pendente') $x$;
  execute $x$ select teste.erro('select public.rpc_criar_proposta((select v from teste.var where k=''op''), 120)', '22023', 'desconto acima de 100% recusado') $x$;
  execute $x$ select teste.erro('select public.rpc_decidir_proposta((select v from teste.var where k=''prop''), ''aprovar'')', '42501', 'comercial não aprova proposta') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.ok(public.rpc_decidir_proposta((select v from teste.var where k='prop'), 'aprovar')->>'status' = 'aprovada', 'gestor aprova proposta de outro usuário') $x$;
  execute $x$ insert into teste.var values ('prop2', (public.rpc_criar_proposta((select v from teste.var where k='op'), 50)->>'id')::bigint) $x$;
  execute $x$ select teste.erro('select public.rpc_decidir_proposta((select v from teste.var where k=''prop2''), ''aprovar'')', '42501', 'gestor não aprova a própria proposta (segregação)') $x$;
  execute $x$ select public.rpc_mover_etapa((select v from teste.var where k='op'), 'pre_matricula', 3) $x$;
  execute $x$ select public.rpc_mover_etapa((select v from teste.var where k='op'), 'matricula_comercial', 4) $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_validar((select v from teste.var where k=''op''), ''documental'', ''valida'', ''RG conferido'', 5)', '42501', 'comercial não valida') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_validar((select v from teste.var where k=''op''), ''financeira'', ''valida'', ''boleto pago'', 5)', '42501', 'secretaria não valida financeira') $x$;
  execute $x$ select teste.erro('select public.rpc_validar((select v from teste.var where k=''op''), ''documental'', ''valida'', '''', 5)', '22023', 'validação sem evidência recusada') $x$;
  execute $x$ select public.rpc_validar((select v from teste.var where k='op'), 'documental', 'valida', 'RG e histórico conferidos', 5) $x$;
  execute $x$ select teste.erro('select public.rpc_confirmar((select v from teste.var where k=''op''), 6)', '22023', 'confirmação incompleta recusada') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('financeiro_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_validar((select v from teste.var where k=''op''), ''documental'', ''valida'', ''RG conferido'', 6)', '42501', 'financeiro não valida documental') $x$;
  execute $x$ select public.rpc_validar((select v from teste.var where k='op'), 'financeira', 'isencao_formal', 'Portaria de isenção 1 (sintética)', 6) $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false) $x$;
  execute $x$ select public.rpc_validar((select v from teste.var where k='op'), 'academica', 'valida', 'Requisitos de ingresso atendidos', 7) $x$;
  execute $x$ select teste.ok(public.rpc_confirmar((select v from teste.var where k='op'), 8)->>'etapa' = 'confirmado', 'confirmação com as três validações') $x$;
  execute $x$ select teste.erro('select public.rpc_cancelar((select v from teste.var where k=''op''), 9, '''')', '22023', 'cancelamento sem motivo recusado') $x$;
  execute $x$ select public.rpc_cancelar((select v from teste.var where k='op'), 9, 'Desistência formal (sintética)') $x$;
  execute $x$ select teste.ok((select etapa = 'cancelado' and confirmada_em is not null from public.oportunidades where id = (select v from teste.var where k='op')), 'cancelamento preserva data de confirmação') $x$;
  execute $x$ select teste.ok((select count(*) from public.validacoes where oportunidade_id = (select v from teste.var where k='op')) = 3, 'cancelamento preserva validações') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select count(*) from public.auditoria where entidade_id = (select v::text from teste.var where k='op')) >= 10, 'histórico completo auditado') $x$;
  execute $x$ select teste.ok(not exists (select 1 from public.auditoria where dados::text ~ '@exemplo\.invalid'), 'auditoria sem e-mails de candidatos') $x$;
  execute $x$ select teste.erro('update public.oportunidades set etapa = ''confirmado'' where id = (select id from public.oportunidades where etapa = ''novo'' limit 1)', '22023', 'banco recusa ingresso sem validações (gatilho)') $x$;
  execute $x$ select teste.erro('update public.auditoria set acao = ''x''', '42501', 'auditoria imutável mesmo para o dono') $x$;
  execute $x$ select teste.erro('truncate public.auditoria', '42501', 'TRUNCATE da auditoria bloqueado') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ insert into teste.var values ('op2', (select id from public.oportunidades where ies_id = 1 and etapa = 'novo' and coorte = '2027.1' order by id limit 1)) $x$;
  execute $x$ select teste.ok((public.rpc_optout((select v from teste.var where k='op2'), 'email')->>'tarefas_suprimidas')::int >= 1, 'opt-out suprime tarefas do canal') $x$;
  execute $x$ select teste.ok((select bool_and(status = 'suprimida') from public.tarefas where oportunidade_id = (select v from teste.var where k='op2') and canal = 'email'), 'tarefas do canal ficaram suprimidas') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.ok((public.rpc_bi(1, '2031.1')->'totais'->>'conversao') is null and (public.rpc_bi(1, '2031.1')->'totais'->>'oportunidades')::int = 0, 'coorte vazia: conversão N/D, não zero') $x$;
  execute $x$ select teste.ok((public.rpc_bi(1, '2027.2')->'totais'->>'meta') is null, 'coorte sem meta: meta N/D') $x$;
  execute $x$ select teste.ok((public.rpc_bi(1, '2027.1')->'totais'->>'meta')::int = 16, 'meta somada dos cursos') $x$;
  execute $x$ select teste.ok((public.rpc_bi(1, '2027.1')->'totais'->>'oportunidades')::int = (select count(*) from public.oportunidades where ies_id = 1 and coorte = '2027.1'), 'denominador = oportunidades da coorte') $x$;
  execute $x$ select teste.erro('select public.rpc_bi(1, ''2027'')', '22023', 'coorte malformada recusada') $x$;
  execute $x$ select teste.erro('select public.rpc_listar_oportunidades(1, null, null, 1, 1000)', '22023', 'página gigante recusada') $x$;
  execute $x$ reset role $x$;
  execute $x$ update public.escopos set revogado_em = now() where usuario_id = teste.id('comercial_b') $x$;
  execute $x$ update public.ies set status = 'suspensa' where id = 2 $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_b')::text, false) $x$;
  execute $x$ select teste.ok((select count(*) from public.oportunidades) = 0, 'escopo revogado perde leitura imediatamente') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false) $x$;
  execute $x$ select teste.ok((select count(*) from public.oportunidades) = 0, 'IES suspensa bloqueia acesso') $x$;
  execute $x$ reset role $x$;
  execute $x$ do $$ begin raise notice 'OK  fim da bateria (todos os blocos executados)'; end $$ $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_configurar(1, 4)', '42501', 'comercial não altera configuração') $x$;
  execute $x$ select teste.erro('select public.rpc_definir_meta(1, 1, ''2027.1'', 99)', '42501', 'comercial não define meta') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_definir_meta(1, 2, ''2027.1'', 99)', 'P0002', 'coordenador não alcança curso alheio') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_configurar(1)', '22023', 'configuração vazia recusada') $x$;
  execute $x$ select teste.erro('select public.rpc_configurar(1, 500)', '23514', 'SLA fora da faixa recusado pelo banco') $x$;
  execute $x$ select teste.ok((public.rpc_configurar(1, 4, 2)->>'sla_horas')::int = 4, 'gestor altera SLA') $x$;
  execute $x$ select teste.ok((public.rpc_definir_meta(1, 1, '2028.1', 0)->>'meta')::int = 0, 'gestor define meta zero') $x$;
  execute $x$ select teste.ok((public.rpc_bi(1, '2028.1')->'totais'->>'atingimento') is null, 'meta zero => atingimento N/D, não infinito') $x$;
  execute $x$ select teste.erro('select public.rpc_definir_meta(2, 3, ''2027.1'', 5)', 'P0002', 'gestor Alfa não define meta na Beta') $x$;
  execute $x$ select teste.erro('select public.rpc_alterar_status_ies(1, ''suspensa'')', '42501', 'gestor não suspende IES') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('master')::text, false) $x$;
  execute $x$ select teste.ok(public.rpc_alterar_status_ies(2, 'ativa')->>'status' = 'ativa', 'Master reativa IES') $x$;
  execute $x$ select teste.erro('select public.rpc_alterar_status_ies(1, ''apagada'')', '22023', 'status inválido recusado') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ insert into teste.var values ('op3', (select id from public.oportunidades where ies_id = 1 and etapa = 'novo' and curso_id = 1 order by id limit 1)) $x$;
  execute $x$ select public.rpc_mover_etapa((select v from teste.var where k='op3'), 'contato', (select versao from public.oportunidades where id = (select v from teste.var where k='op3'))) $x$;
  execute $x$ select public.rpc_mover_etapa((select v from teste.var where k='op3'), 'inscrito', (select versao from public.oportunidades where id = (select v from teste.var where k='op3'))) $x$;
  execute $x$ insert into teste.var values ('p_pend', (public.rpc_criar_proposta((select v from teste.var where k='op3'), 60)->>'id')::bigint) $x$;
  execute $x$ select teste.erro('select public.rpc_aceitar_proposta((select v from teste.var where k=''p_pend''))', '22023', 'proposta pendente não pode ser aceita') $x$;
  execute $x$ insert into teste.var values ('p_ok', (public.rpc_criar_proposta((select v from teste.var where k='op3'), 10)->>'id')::bigint) $x$;
  execute $x$ select teste.ok(public.rpc_aceitar_proposta((select v from teste.var where k='p_ok'))->>'status' = 'aceita', 'proposta aprovada é aceita') $x$;
  execute $x$ reset role $x$;
  execute $x$ update public.propostas set status = 'aprovada', validade = now() - interval '1 day' where id = (select v from teste.var where k='p_pend') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select teste.ok(public.rpc_aceitar_proposta((select v from teste.var where k='p_pend'))->>'status' = 'expirada', 'proposta vencida expira no aceite') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_aceitar_proposta((select v from teste.var where k=''p_ok''))', '42501', 'coordenador não registra aceite') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('reitoria_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_fila(1)', '42501', 'reitoria não acessa fila operacional') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('com_dir_a')::text, false) $x$;
  execute $x$ select teste.ok((select bool_and((x->>'responsavel_id')::uuid = teste.id('com_dir_a')) from jsonb_array_elements(public.rpc_fila(1)->'tarefas') x) is not false,
  'comercial vê só as próprias tarefas') $x$;
  execute $x$ select teste.ok(public.rpc_fila(1)->>'envio_externo' = 'desativado', 'fila declara envio externo desativado') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_ciclo_maim(1)', '42501', 'comercial não executa ciclo MAIM') $x$;
  execute $x$ reset role $x$;
  execute $x$ update public.tarefas set status = 'concluida' where ies_id = 1 and status = 'aberta' $x$;
  execute $x$ update public.oportunidades set atualizado_em = now() - interval '10 days' where ies_id = 1 $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ insert into teste.var values ('c1', (public.rpc_ciclo_maim(1)->>'follow_ups')::int) $x$;
  execute $x$ select teste.ok((select v from teste.var where k='c1') >= 1, 'ciclo gera follow-up para oportunidade parada') $x$;
  execute $x$ select teste.ok((public.rpc_ciclo_maim(1)->>'follow_ups')::int = 0, 'segundo ciclo não duplica tarefas') $x$;
  execute $x$ reset role $x$;
  execute $x$ update public.tarefas set status = 'concluida' where ies_id = 1 and status = 'aberta' $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select teste.ok((public.rpc_ciclo_maim(1)->>'limite_atingido')::int = 0, 'com limite 2, o segundo follow-up ainda é permitido') $x$;
  execute $x$ reset role $x$;
  execute $x$ update public.tarefas set status = 'concluida' where ies_id = 1 and status = 'aberta' $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select teste.ok((public.rpc_ciclo_maim(1)->>'limite_atingido')::int >= 1, 'com 2 follow-ups feitos, o limite bloqueia o terceiro') $x$;
  execute $x$ select teste.ok((public.rpc_ciclo_maim(1)->>'follow_ups')::int = 0, 'nenhum follow-up além do limite') $x$;
  execute $x$ select public.rpc_configurar(1, null, 5) $x$;
  execute $x$ select teste.ok((public.rpc_ciclo_maim(1)->>'follow_ups')::int >= 1, 'ao ampliar o limite, o ciclo volta a gerar follow-ups') $x$;
  execute $x$ insert into teste.var values ('t1', (select t.id from public.tarefas t where t.ies_id = 1 and t.status = 'aberta' and t.canal = 'email' order by t.id limit 1)) $x$;
  execute $x$ reset role $x$;
  execute $x$ update public.pessoas set optout_email = true where id = (select o.pessoa_id from public.tarefas t join public.oportunidades o on o.id = t.oportunidade_id where t.id = (select v from teste.var where k='t1')) $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select teste.ok((public.rpc_disparar_tarefa((select v from teste.var where k='t1'))->>'enviado')::boolean = false, 'disparo nunca envia') $x$;
  execute $x$ select teste.ok((public.rpc_disparar_tarefa((select v from teste.var where k='t1'))->>'elegivel')::boolean = false, 'disparo revalida opt-out') $x$;
  execute $x$ select teste.ok(public.rpc_concluir_tarefa((select v from teste.var where k='t1'), 'liguei e falei')->>'status' = 'suprimida', 'conclusão revalida e suprime por opt-out') $x$;
  execute $x$ select teste.erro('select public.rpc_concluir_tarefa((select v from teste.var where k=''t1''), ''de novo'')', '22023', 'tarefa encerrada não reabre') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select count(*) from public.auditoria where acao = 'envio_externo.bloqueado') >= 2, 'tentativas de disparo auditadas') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ reset role $x$;
  execute $x$ with nova as (
  insert into public.tarefas(ies_id, oportunidade_id, tipo, canal, responsavel_id, vence_em)
  select 1, o.id, 'primeiro_contato', 'telefone', teste.id('comercial_a'), now() + interval '1 day'
    from public.oportunidades o where o.ies_id = 1 and o.curso_id = 1 and o.etapa = 'novo' order by o.id limit 1
  returning id)
insert into teste.var select 't2', id from nova $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select teste.ok((select v from teste.var where k='t2') is not null, 'cenário: existe tarefa aberta de Direito') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('com_dir_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_concluir_tarefa((select v from teste.var where k=''t2''), ''tentativa'')', 'P0002', 'atendente não vê nem conclui tarefa de oportunidade atribuída a outro') $x$;
  execute $x$ reset role $x$;
  execute $x$ insert into teste.var values ('t3', (select t.id from public.tarefas t join public.oportunidades o on o.id = t.oportunidade_id
  where t.ies_id = 1 and t.status = 'aberta' and o.curso_id = 2 and t.tipo <> 'pendencia_validacao' order by t.id limit 1)) $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select teste.erro('select public.rpc_concluir_tarefa((select v from teste.var where k=''t3''), ''tentativa'')', 'P0002', 'tarefa de curso não autorizado: não encontrado (sem revelar existência)') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false) $x$;
  execute $x$ select teste.ok((select bool_and(x->>'curso' = 'Direito') from jsonb_array_elements(public.rpc_pendencias(1)) x) is not false, 'pendências respeitam curso autorizado') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_anonimizar((select v from teste.var where k=''op3''))', '42501', 'comercial não anonimiza') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ insert into teste.var values ('bi_antes', (public.rpc_bi(1, '2027.1')->'totais'->>'oportunidades')::int) $x$;
  execute $x$ select public.rpc_anonimizar((select v from teste.var where k='op3')) $x$;
  execute $x$ select teste.ok((select email is null and telefone is null and nome = 'Titular anonimizado' from public.pessoas
                 where id = (select pessoa_id from public.oportunidades where id = (select v from teste.var where k='op3'))), 'dados pessoais removidos') $x$;
  execute $x$ select teste.ok((public.rpc_bi(1, '2027.1')->'totais'->>'oportunidades')::int = (select v from teste.var where k='bi_antes'), 'estatística preservada após anonimização') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok(not exists (select 1 from public.auditoria where dados::text ~ '@exemplo\.invalid'), 'auditoria segue sem dados pessoais') $x$;
  execute $x$ do $$ begin raise notice 'OK  fim da bateria complementar'; end $$ $x$;
  execute $x$ set role anon $x$;
  execute $x$ select teste.erro('select public.rpc_me()', '42501', 'anon não chama rpc_me') $x$;
  execute $x$ select teste.erro('select public.rpc_detalhe(1)', '42501', 'anon não chama rpc_detalhe') $x$;
  execute $x$ reset role $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.ok(jsonb_array_length(public.rpc_me()->'escopos') = 1 and public.rpc_me()->'escopos'->0->>'papel' = 'gestor', 'rpc_me devolve só os próprios escopos') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('revogado_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_me()', '42501', 'usuário revogado não obtém identidade') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false) $x$;
  execute $x$ select teste.ok(jsonb_array_length(public.rpc_estrutura(1)->'cursos') = 1 and public.rpc_estrutura(1)->'cursos'->0->>'nome' = 'Direito', 'estrutura do coordenador lista só Direito') $x$;
  execute $x$ select teste.ok((public.rpc_estrutura(1)->>'acesso_total')::boolean = false, 'coordenador sem acesso total') $x$;
  execute $x$ select teste.erro('select public.rpc_estrutura(2)', 'P0002', 'estrutura de IES alheia => não encontrado') $x$;
  execute $x$ select teste.ok((select (d->'pessoa'->>'dados_mascarados')::boolean and d->'pessoa'->>'email' like '%***@%'
                        and d->'pessoa'->>'email' <> (select p.email from public.pessoas p where p.id = (d->'pessoa'->>'id')::bigint union all select '' limit 1)
                 from (select public.rpc_detalhe((select min(id) from public.oportunidades where curso_id = 1 and etapa = 'novo')) d) x),
  'detalhe para coordenador vem com contato mascarado') $x$;
  execute $x$ select teste.ok(jsonb_array_length(public.rpc_detalhe((select min(id) from public.oportunidades where curso_id = 1))->'propostas') = 0,
  'coordenador não vê propostas no detalhe') $x$;
  execute $x$ reset role $x$;
  execute $x$ insert into teste.var values ('adm', (select min(id) from public.oportunidades where ies_id = 1 and curso_id = 2)) $x$;
  execute $x$ insert into teste.var values ('beta', (select min(id) from public.oportunidades where ies_id = 2)) $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select teste.erro('select public.rpc_detalhe((select v from teste.var where k=''adm''))', 'P0002', 'detalhe de curso não autorizado => não encontrado') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.ok((select (d->'pessoa'->>'dados_mascarados')::boolean = false and jsonb_array_length(d->'historico') >= 1
                 from (select public.rpc_detalhe((select v from teste.var where k='adm')) d) x), 'gestor vê contato pleno e histórico') $x$;
  execute $x$ select teste.erro('select public.rpc_detalhe((select v from teste.var where k=''beta''))', 'P0002', 'detalhe de outra IES => não encontrado') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('master')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_detalhe((select v from teste.var where k=''adm''))', 'P0002', 'Master não lê detalhe de candidato') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.ok((select bool_and((x->>'curso_id')::int = 2) from jsonb_array_elements(public.rpc_listar_oportunidades(1, null, null, 1, 100, 2)->'itens') x), 'filtro por curso') $x$;
  execute $x$ select teste.ok((public.rpc_listar_oportunidades(1, null, null, 1, 100, 2)->>'total')::int = (select count(*) from public.oportunidades where ies_id = 1 and curso_id = 2), 'total do filtro por curso correto') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false) $x$;
  execute $x$ select teste.ok((public.rpc_listar_oportunidades(1, null, null, 1, 100, 2)->>'total')::int = 0, 'coordenador filtrando curso alheio recebe zero itens') $x$;
  execute $x$ select teste.erro('select public.rpc_listar_propostas(1)', '42501', 'coordenador não lista propostas') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.ok(jsonb_typeof(public.rpc_listar_propostas(1, 'aceita')) = 'array', 'comercial lista propostas') $x$;
  execute $x$ select teste.ok((select bool_and(x ? 'nome' and x ? 'responsavel') from jsonb_array_elements(public.rpc_fila(1)->'tarefas') x) is not false, 'fila traz nome e responsável') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.ok((select sum((x->>'oportunidades')::int) from jsonb_array_elements(public.rpc_bi(1, '2027.1', 'turno')->'linhas') x)
                = (public.rpc_bi(1, '2027.1', 'turno')->'totais'->>'oportunidades')::int, 'BI por turno soma o total') $x$;
  execute $x$ select teste.ok((public.rpc_bi(1, '2035.2', 'atendente')->'totais'->>'conversao') is null, 'BI agrupado mantém N/D em coorte vazia') $x$;
  execute $x$ select teste.erro('select public.rpc_bi(1, ''2027.1'', ''pessoa'')', '22023', 'agrupamento inválido recusado') $x$;
  execute $x$ select teste.ok((public.rpc_auditoria(1)->>'total')::int > 0, 'gestor lê auditoria') $x$;
  execute $x$ select teste.ok(not (public.rpc_auditoria(1)::text ~ '@exemplo\.invalid'), 'auditoria exibida sem e-mails') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_auditoria(1)', '42501', 'comercial não lê auditoria') $x$;
  execute $x$ select teste.erro('select public.rpc_master_listar_ies()', '42501', 'não Master não lista IES') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('master')::text, false) $x$;
  execute $x$ select teste.ok(jsonb_array_length(public.rpc_master_listar_ies()) = 2, 'Master lista as IES') $x$;
  execute $x$ select teste.ok(jsonb_array_length(public.rpc_master_acessos(1)->'escopos') >= 7, 'Master vê acessos da IES') $x$;
  execute $x$ select teste.erro('select public.rpc_conceder_escopo_email(''ninguem@exemplo.invalid'', ''X'', 1, null, ''comercial'')', '22023', 'e-mail sem conta no Auth recusado') $x$;
  execute $x$ reset role $x$;
  execute $x$ insert into auth.users(id, email) values ('00000000-0000-0000-0000-0000000000c1', 'novo.atendente@exemplo.invalid') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select teste.ok((public.rpc_conceder_escopo_email('NOVO.Atendente@exemplo.invalid', 'Novo Atendente', 1, 1, 'comercial')->>'perfil_novo')::boolean, 'Master concede escopo por e-mail e cria perfil') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false) $x$;
  execute $x$ select teste.ok((select array_agg(x->>'id') = array['1'] from jsonb_array_elements(public.rpc_estrutura(1)->'cursos') x) and (select count(*) from public.oportunidades) = 0,
  'novo atendente enxerga só o curso concedido e nenhuma oportunidade de colegas') $x$;
  execute $x$ reset role $x$;
  execute $x$ do $$ begin raise notice 'OK  fim da bateria de leitura'; end $$ $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ insert into teste.var values ('f2op', (select min(id) from public.oportunidades where ies_id = 1 and curso_id = 1 and etapa = 'novo')) $x$;
  execute $x$ select public.rpc_mover_etapa((select v from teste.var where k='f2op'), 'contato', (select versao from public.oportunidades where id = (select v from teste.var where k='f2op'))) $x$;
  execute $x$ select public.rpc_mover_etapa((select v from teste.var where k='f2op'), 'inscrito', (select versao from public.oportunidades where id = (select v from teste.var where k='f2op'))) $x$;
  execute $x$ insert into teste.var values ('f2p1', (public.rpc_criar_proposta((select v from teste.var where k='f2op'), 10)->>'id')::bigint) $x$;
  execute $x$ insert into teste.var values ('f2p2', (public.rpc_criar_proposta((select v from teste.var where k='f2op'), 20)->>'id')::bigint) $x$;
  execute $x$ select teste.ok((select status from public.propostas where id = (select v from teste.var where k='f2p1')) = 'substituida', 'nova proposta substitui a anterior ativa') $x$;
  execute $x$ select teste.ok((select count(*) from public.propostas where oportunidade_id = (select v from teste.var where k='f2op') and status in ('pendente_aprovacao','aprovada')) = 1, 'uma única proposta ativa por oportunidade') $x$;
  execute $x$ select teste.erro('select public.rpc_aceitar_proposta((select v from teste.var where k=''f2p1''))', '22023', 'proposta substituída não pode ser aceita') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select count(*) from public.auditoria where acao = 'proposta.substituir' and entidade_id = (select v::text from teste.var where k='f2op')) = 1, 'substituição auditada') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select teste.ok((select count(*) from public.tarefas where oportunidade_id = (select v from teste.var where k='f2op') and tipo = 'primeiro_contato' and status = 'aberta') = 0,
  'ao sair de "novo", a tarefa de primeiro contato é encerrada') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok(not exists (select 1 from public.tarefas t join public.oportunidades o on o.id = t.oportunidade_id
                            where t.status = 'aberta' and not privado.tarefa_compativel(t.tipo, o.etapa)), 'nenhuma tarefa aberta incompatível com a etapa') $x$;
  execute $x$ select teste.ok((select count(*) from public.auditoria where acao = 'tarefa.encerrar_incompativel' and entidade_id = (select v::text from teste.var where k='f2op')) >= 1, 'encerramento automático auditado') $x$;
  execute $x$ select teste.erro('insert into public.tarefas(ies_id, oportunidade_id, tipo, canal, vence_em) values (1, (select v from teste.var where k=''f2op''), ''primeiro_contato'', ''email'', now())',
  '22023', 'banco recusa criar primeiro contato fora de "novo"') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.ok((select (b->'totais'->>'taxa_conversao_decididas')::numeric
                   = round((b->'totais'->>'ingressantes')::numeric / nullif((b->'totais'->>'ingressantes')::int + (b->'totais'->>'perdidos')::int + (b->'totais'->>'cancelamentos')::int, 0), 4)
                   or (b->'totais'->>'taxa_conversao_decididas') is null
                 from (select public.rpc_bi(1, '2027.1') b) x), 'taxa usa apenas oportunidades decididas') $x$;
  execute $x$ select teste.ok((public.rpc_bi(1, '2031.1')->'totais'->>'projecao_oportunidades_necessarias') is null, 'sem base decidida a projeção é N/D') $x$;
  execute $x$ select teste.ok((public.rpc_bi(1, '2027.1')->'totais'->>'projecao_metodo') like 'Oportunidades adicionais%', 'método da projeção explicitado (Bíblia §6)') $x$;
  execute $x$ select teste.ok((select sum((x->>'meta')::int) from jsonb_array_elements(public.rpc_metas(1, '2027.1')) x) = 16, 'metas cadastradas são lidas (10 + 6)') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false) $x$;
  execute $x$ select teste.ok(jsonb_array_length(public.rpc_metas(1, '2027.1')) = 1, 'coordenador lê só a meta do curso autorizado') $x$;
  execute $x$ select teste.erro('select public.rpc_metas(2, ''2027.1'')', 'P0002', 'metas de IES alheia: não encontrado') $x$;
  execute $x$ reset role $x$;
  execute $x$ do $$ begin raise notice 'OK  fim da bateria da Fase 2'; end $$ $x$;
  execute $x$ set role anon $x$;
  execute $x$ select teste.erro('select public.rpc_central(1, ''2027.1'')', '42501', 'anon não acessa a Central') $x$;
  execute $x$ reset role $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ insert into teste.var values ('c_ops', (public.rpc_central(1, '2027.1')->'totais'->>'oportunidades')::bigint) $x$;
  execute $x$ select teste.ok((select v from teste.var where k='c_ops') = (public.rpc_bi(1, '2027.1')->'totais'->>'oportunidades')::bigint, 'Central e BI concordam no total de oportunidades') $x$;
  execute $x$ select teste.ok((public.rpc_central(1, '2027.1')->'totais'->>'ingressantes') = (public.rpc_bi(1, '2027.1')->'totais'->>'ingressantes'), 'Central e BI concordam nos ingressantes') $x$;
  execute $x$ select teste.ok((public.rpc_central(1, '2027.1')->'funil'->0->>'quantidade')::bigint = (select v from teste.var where k='c_ops'), 'funil começa no total de oportunidades') $x$;
  execute $x$ select teste.ok((select bool_and(coalesce((x->>'conversao_da_anterior')::numeric, 0) <= 1) from jsonb_array_elements(public.rpc_central(1, '2027.1')->'funil') x), 'funil nunca aumenta entre etapas') $x$;
  execute $x$ select teste.ok((public.rpc_central(1, '2027.1')->'funil'->5->>'quantidade')::bigint
                 = (select count(*) from public.oportunidades where ies_id = 1 and coorte = '2027.1' and confirmada_em is not null), 'última etapa do funil = oportunidades que alcançaram o ingresso') $x$;
  execute $x$ select teste.ok((public.rpc_central(1, '2027.1')->'funil'->5->>'quantidade')::int >= (public.rpc_central(1, '2027.1')->'totais'->>'ingressantes')::int, 'alcance do ingresso ≥ ingressantes efetivos (diferença = cancelamentos após confirmar)') $x$;
  execute $x$ select teste.ok((public.rpc_central(1, '2027.1')->'totais'->>'custo_por_lead_centavos') is null and (public.rpc_central(1, '2027.1')->'totais'->>'custo_motivo') similar to '(Sem investimento cadastrado|Sem custo lançado)%', 'custo por lead N/D com motivo (sem custo lançado)') $x$;
  execute $x$ select teste.ok((public.rpc_central(1, '2031.1')->'totais'->>'taxa_conversao_decididas') is null and (public.rpc_central(1, '2031.1')->'totais'->>'oportunidades')::int = 0, 'coorte vazia: zero oportunidades e taxa N/D') $x$;
  execute $x$ select teste.ok(jsonb_array_length(public.rpc_central(1, '2027.1')->'evolucao') = 12, 'evolução cobre 12 semanas') $x$;
  execute $x$ select teste.ok((select sum((x->>'oportunidades')::int) from jsonb_array_elements(public.rpc_central(1, '2027.1')->'por_origem') x) = (select v from teste.var where k='c_ops'), 'origem soma o total') $x$;
  execute $x$ select teste.ok((select sum((x->>'oportunidades')::int) from jsonb_array_elements(public.rpc_central(1, '2027.1')->'por_atendente') x) = (select v from teste.var where k='c_ops'), 'atendente soma o total') $x$;
  execute $x$ select teste.ok((public.rpc_central(1, '2027.1', '{"curso_id": 1}')->'totais'->>'oportunidades')::bigint
                 = (select count(*) from public.oportunidades where ies_id = 1 and curso_id = 1 and coorte = '2027.1'), 'filtro de curso restringe o recorte') $x$;
  execute $x$ select teste.ok(public.rpc_central(1, '2027.1', '{"curso_id": 1}')->>'cobertura' = 'recorte', 'filtro marca cobertura como recorte') $x$;
  execute $x$ select teste.ok((public.rpc_central(1, '2027.1', '{"modalidade": "ead"}')->'totais'->>'oportunidades')::bigint
                 = (select count(*) from public.oportunidades o join public.cursos c on c.id = o.curso_id where o.ies_id = 1 and c.modalidade = 'ead' and o.coorte = '2027.1'), 'filtro de modalidade') $x$;
  execute $x$ select teste.ok((public.rpc_central(1, '2027.1', '{"curso_id": 3}')->'totais'->>'oportunidades')::int = 0, 'filtro com curso de outra IES não vaza dados') $x$;
  execute $x$ select teste.erro('select public.rpc_central(2, ''2027.1'')', 'P0002', 'Central de IES alheia: não encontrado') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false) $x$;
  execute $x$ select teste.ok(public.rpc_central(1, '2027.1')->>'cobertura' = 'recorte'
                and (select bool_and(x->>'chave' like 'Direito%') from jsonb_array_elements(public.rpc_central(1, '2027.1')->'por_curso') x), 'coordenador vê só Direito na Central') $x$;
  execute $x$ select teste.ok(jsonb_array_length(public.rpc_central(1, '2027.1')->'filtros_disponiveis'->'turnos') = 1, 'filtros disponíveis respeitam o escopo') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('master')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_central(1, ''2027.1'')', 'P0002', 'Master sem escopo não acessa a Central') $x$;
  execute $x$ reset role $x$;
  execute $x$ do $$ begin raise notice 'OK  fim da bateria da Central'; end $$ $x$;
  execute $x$ insert into public.pessoas(ies_id, nome, email, base_legal, origem)
  select 1, 'R03 ' || g, 'r03-' || g || '@exemplo.invalid', 'consentimento', 'teste R03' from generate_series(1, 24) g $x$;
  execute $x$ insert into public.oportunidades(ies_id, curso_id, pessoa_id, forma_ingresso, coorte, etapa, matricula_comercial_em, confirmada_em, val_documental, val_financeira, val_academica)
  select 1, 1, p.id, 'enem', '2030.1', case when n <= 2 then 'confirmado' else 'contato' end,
         case when n <= 2 then now() end, case when n <= 2 then now() end, n <= 2, n <= 2, n <= 2
    from (select id, row_number() over (order by id) n from public.pessoas where origem = 'teste R03') p $x$;
  execute $x$ insert into public.metas values (1, 1, '2030.1', 16) $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.ok((public.rpc_central(1, '2030.1')->'totais'->>'oportunidades_adicionais_projetadas') is null
                and (public.rpc_central(1, '2030.1')->'totais'->>'forecast_motivo') like 'Amostra insuficiente: 24 oportunidades (mínimo configurado: 30)%', 'amostra abaixo do mínimo padrão (30): N/D com motivo') $x$;
  execute $x$ select public.rpc_configurar(1, null, null, null, null, 20) $x$;
  execute $x$ select teste.ok((public.rpc_estrutura(1)->'ies'->>'amostra_minima_forecast')::int = 20, 'gestor configura a amostra mínima') $x$;
  execute $x$ select teste.ok((public.rpc_central(1, '2030.1')->'totais'->>'oportunidades_adicionais_projetadas')::int = 168, 'R03: cenário da captura dá 168 (aritmética exata), não 169') $x$;
  execute $x$ select teste.ok((public.rpc_bi(1, '2030.1')->'totais'->>'projecao_oportunidades_necessarias')::int = 168, 'R03: BI legado usa a mesma fórmula (168)') $x$;
  execute $x$ select teste.ok((public.rpc_central(1, '2030.1')->'totais'->>'conversao')::numeric = round(2::numeric / 24, 4), 'D3: conversão = ingressantes ÷ oportunidades da coorte') $x$;
  execute $x$ select teste.ok((public.rpc_central(1, '2030.1')->'totais'->>'meta_restante')::int = 14, 'meta restante = max(meta − ingressantes, 0)') $x$;
  execute $x$ select teste.ok((public.rpc_central(1, '2030.1')->'totais'->'cenario_pipeline'->>'rotulo') like 'Cenário complementar%', 'D1: método por pipeline apenas como cenário identificado') $x$;
  execute $x$ select teste.erro('select public.rpc_configurar(1, null, null, null, null, 0)', '23514', 'amostra mínima fora da faixa recusada') $x$;
  execute $x$ reset role $x$;
  execute $x$ update public.metas set meta = 2 where ies_id = 1 and curso_id = 1 and coorte = '2030.1' $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select teste.ok((public.rpc_central(1, '2030.1')->'totais'->>'oportunidades_adicionais_projetadas')::int = 0
                and (public.rpc_central(1, '2030.1')->'totais'->>'forecast_motivo') like 'Meta cumprida%', 'meta cumprida: necessidade adicional zero') $x$;
  execute $x$ reset role $x$;
  execute $x$ update public.metas set meta = 16 where ies_id = 1 and curso_id = 1 and coorte = '2030.1' $x$;
  execute $x$ update public.oportunidades set etapa = 'cancelado', cancelada_em = now() where coorte = '2030.1' and etapa = 'confirmado' $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select teste.ok((public.rpc_central(1, '2030.1')->'totais'->>'oportunidades_adicionais_projetadas') is null
                and (public.rpc_central(1, '2030.1')->'totais'->>'forecast_motivo') like 'Conversão observada zero%', 'conversão zero: projeção indisponível (N/D), nunca zero') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.ok((public.rpc_central(1, '2027.1')->'totais'->>'receita_mensal_potencial_ofertada_centavos')::bigint
  = (select coalesce(sum(x.valor_final_centavos), 0) from public.propostas x join public.oportunidades o on o.id = x.oportunidade_id
      where o.ies_id = 1 and o.coorte = '2027.1' and o.etapa not in ('perdido','cancelado')
        and (x.status = 'aceita' or (x.status in ('aprovada','pendente_aprovacao') and x.validade >= now()))), 'D2: receita potencial = soma das mensalidades ofertadas válidas') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_configurar(1, null, null, null, null, 25)', '42501', 'comercial não altera a amostra mínima') $x$;
  execute $x$ reset role $x$;
  execute $x$ do $$ begin raise notice 'OK  fim da bateria de conformidade v0.2'; end $$ $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ insert into teste.var values ('crm', (select min(id) from public.oportunidades where ies_id = 1 and curso_id = 1 and etapa = 'novo')) $x$;
  execute $x$ select teste.ok((public.rpc_registrar_interacao((select v from teste.var where k='crm'), 'ligacao', 'Conversa sobre horários do curso')->>'id') is not null, 'interação registrada') $x$;
  execute $x$ select teste.ok((select ultima_interacao_em is not null from public.oportunidades where id = (select v from teste.var where k='crm')), 'última interação atualizada') $x$;
  execute $x$ select teste.erro('select public.rpc_registrar_interacao((select v from teste.var where k=''crm''), ''telepatia'', ''x x x'')', '22023', 'tipo de interação inválido recusado') $x$;
  execute $x$ select teste.erro('select public.rpc_registrar_interacao(9, ''ligacao'', ''tentativa cruzada'')', 'P0002', 'interação em oportunidade de outra IES: não encontrado') $x$;
  execute $x$ insert into teste.var values ('obj', (public.rpc_registrar_objecao((select v from teste.var where k='crm'), 'preco', 'Mensalidade acima do orçamento da família')->>'id')::bigint) $x$;
  execute $x$ select teste.ok((public.rpc_detalhe((select v from teste.var where k='crm'))->'objecoes'->0->>'status') = 'aberta', 'objeção registrada em aberto') $x$;
  execute $x$ select teste.erro('select public.rpc_tratar_objecao((select v from teste.var where k=''obj''), ''superada'', '''')', '22023', 'tratamento sem descrição recusado') $x$;
  execute $x$ select teste.ok(public.rpc_tratar_objecao((select v from teste.var where k='obj'), 'superada', 'Apresentada bolsa dentro do limite do curso')->>'status' = 'superada', 'objeção tratada') $x$;
  execute $x$ select teste.ok((public.rpc_agendar((select v from teste.var where k='crm'), now() + interval '2 days', 'Retorno com a família', 'telefone')->>'id') is not null, 'agendamento criado') $x$;
  execute $x$ select teste.ok(jsonb_array_length(public.rpc_agenda(1, now(), now() + interval '7 days')) >= 1, 'agenda lista o compromisso') $x$;
  execute $x$ select teste.erro('select public.rpc_agendar((select v from teste.var where k=''crm''), now() - interval ''2 days'', ''no passado'')', '22023', 'agendamento no passado recusado') $x$;
  execute $x$ select teste.erro('select public.rpc_agenda(1, now(), now() + interval ''200 days'')', '22023', 'intervalo de agenda excessivo recusado') $x$;
  execute $x$ select teste.ok((select (s->>'score')::int between 0 and 100 and s->>'versao' = 'score-v1' and jsonb_array_length(s->'razoes') > 0
                        and s->>'aviso' like '%não é usado para decidir ingresso%'
                 from (select public.rpc_detalhe((select v from teste.var where k='crm'))->'score' s) x), 'score versionado, explicado e com a trava de não decidir ingresso') $x$;
  execute $x$ select teste.ok((public.rpc_listar_oportunidades(1, null, null, 1, 100)->'itens'->0) ? 'score', 'score presente no cartão') $x$;
  execute $x$ select teste.ok((public.rpc_listar_oportunidades(1, null, null, 1, 100, null, 'cand 2')->>'total')::int >= 1, 'busca por nome, sem acento e sem caixa') $x$;
  execute $x$ select teste.ok((public.rpc_listar_oportunidades(1, null, null, 1, 100, null, 'a2@exemplo')->>'total')::int = 1, 'comercial busca por e-mail') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false) $x$;
  execute $x$ select teste.ok((public.rpc_listar_oportunidades(1, null, null, 1, 100, null, 'a2@exemplo')->>'total')::int = 0, 'coordenação NÃO consegue buscar por e-mail (minimização)') $x$;
  execute $x$ select teste.ok(jsonb_array_length(public.rpc_detalhe((select v from teste.var where k='crm'))->'interacoes') = 0, 'coordenação não lê o conteúdo das interações') $x$;
  execute $x$ select teste.ok((public.rpc_detalhe((select v from teste.var where k='crm'))->'score') = 'null'::jsonb, 'coordenação não vê score comercial') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.ok((select bool_and((x->>'forma_ingresso') = 'enem') from jsonb_array_elements(public.rpc_listar_oportunidades(1, null, null, 1, 100, null, null, 'enem')->'itens') x), 'filtro por forma de ingresso') $x$;
  execute $x$ select teste.ok((select bool_and((x->>'sla_atrasado')::boolean) from jsonb_array_elements(public.rpc_listar_oportunidades(1, null, null, 1, 100, null, null, null, false, true)->'itens') x) is not false, 'filtro de SLA atrasado') $x$;
  execute $x$ select teste.erro('select public.rpc_reatribuir((select v from teste.var where k=''crm''), teste.id(''com_dir_a''), ''troca'')', '42501', 'comercial não reatribui') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_reatribuir((select v from teste.var where k=''crm''), teste.id(''secretaria_a''), ''troca'')', '22023', 'não reatribui para quem não é comercial') $x$;
  execute $x$ select teste.erro('select public.rpc_reatribuir((select v from teste.var where k=''crm''), teste.id(''comercial_b''), ''troca'')', '22023', 'não reatribui para atendente de outra IES') $x$;
  execute $x$ select teste.ok((public.rpc_reatribuir((select v from teste.var where k='crm'),
  (select case when responsavel_id = teste.id('com_dir_a') then teste.id('comercial_a') else teste.id('com_dir_a') end from public.oportunidades where id = (select v from teste.var where k='crm')),
  'Rebalanceamento de carteira')->>'tarefas_transferidas')::int >= 1, 'gestor reatribui e as tarefas acompanham') $x$;
  execute $x$ select teste.erro('select public.rpc_reatribuir((select v from teste.var where k=''crm''), (select responsavel_id from public.oportunidades where id = (select v from teste.var where k=''crm'')), ''de novo'')', '22023', 'reatribuir ao responsável atual é recusado') $x$;
  execute $x$ select teste.ok((select count(*) from public.auditoria where acao = 'oportunidade.reatribuir' and entidade_id = (select v::text from teste.var where k='crm')) = 1, 'histórico de responsáveis auditado') $x$;
  execute $x$ select teste.ok(jsonb_array_length(public.rpc_atendentes(1, 1)) >= 2, 'lista de atendentes elegíveis do curso') $x$;
  execute $x$ reset role $x$;
  execute $x$ insert into public.pessoas(ies_id, nome, email, base_legal, origem)
  select 1, upper((select nome from public.pessoas where id = (select pessoa_id from public.oportunidades where id = (select v from teste.var where k='crm')))), 'homonimo@exemplo.invalid', 'consentimento', 'teste' $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select teste.ok(jsonb_array_length(public.rpc_detalhe((select v from teste.var where k='crm'))->'possiveis_duplicidades') = 1, 'homônimo sinalizado como possível duplicidade (sem fusão)') $x$;
  execute $x$ select teste.ok((public.rpc_detalhe((select v from teste.var where k='crm'))->'possiveis_duplicidades'->0->>'email') like '%***@%', 'possível duplicidade exibida com contato mascarado') $x$;
  execute $x$ reset role $x$;
  execute $x$ do $$ begin raise notice 'OK  fim da bateria do CRM'; end $$ $x$;
  execute $x$ reset role $x$;
  execute $x$ insert into public.campus(ies_id, nome) values (1, 'Sul') $x$;
  execute $x$ insert into public.cursos(ies_id, campus_id, nome, turno, modalidade, mensalidade_centavos, desconto_max_pct)
  values (1, (select id from public.campus where ies_id = 1 and nome = 'Sul'), 'Pedagogia', 'noturno', 'presencial', 89000, 30) $x$;
  execute $x$ insert into teste.usuario values ('gestor_sul', '00000000-0000-0000-0000-0000000000d1'), ('com_sul', '00000000-0000-0000-0000-0000000000d2') $x$;
  execute $x$ insert into auth.users(id, email) values ('00000000-0000-0000-0000-0000000000d1', 'gestor.sul@exemplo.invalid'), ('00000000-0000-0000-0000-0000000000d2', 'com.sul@exemplo.invalid') $x$;
  execute $x$ insert into public.usuarios(id, nome) values ('00000000-0000-0000-0000-0000000000d1', 'gestor_sul'), ('00000000-0000-0000-0000-0000000000d2', 'com_sul') $x$;
  execute $x$ insert into teste.var values ('sul', (select id from public.campus where ies_id = 1 and nome = 'Sul')) $x$;
  execute $x$ insert into teste.var values ('ped', (select id from public.cursos where ies_id = 1 and nome = 'Pedagogia')) $x$;
  execute $x$ create or replace function teste.tenta(p_sql text) returns text language plpgsql as $f$
begin
  begin
    execute p_sql;
    raise exception using errcode = 'T0001';
  exception when others then
    if sqlstate = 'T0001' then return 'ok'; end if;
    if sqlstate = 'PGRST' then return sqlerrm::jsonb->>'code'; end if;
    return sqlstate;
  end;
end $f$ $x$;
  execute $x$ grant execute on function teste.tenta(text) to authenticated $x$;
  execute $x$ select teste.erro('insert into public.escopos(usuario_id, ies_id, curso_id, papel) values (teste.id(''com_sul''), 1, null, ''comercial'')', '23502', 'escopo sem abrangência declarada é recusado (nulo não é curinga)') $x$;
  execute $x$ select teste.erro('insert into public.escopos(usuario_id, ies_id, abrangencia, curso_id, papel) values (teste.id(''com_sul''), 1, ''ies'', 1, ''comercial'')', '23514', 'abrangência incoerente com o curso é recusada') $x$;
  execute $x$ select teste.erro('insert into public.escopos(usuario_id, ies_id, abrangencia, campus_id, papel) values (teste.id(''com_sul''), 1, ''campus'', 2, ''comercial'')', '22023', 'campus de outra IES é recusado') $x$;
  execute $x$ select teste.ok((select bool_and(abrangencia in ('ies','campus','curso')) from public.escopos), 'todos os escopos existentes têm abrangência explícita') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('master')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_conceder_escopo(teste.id(''com_sul''), 1, 1, ''comercial'', 1)', '22023', 'curso e campus ao mesmo tempo: recusado') $x$;
  execute $x$ select teste.erro('select public.rpc_conceder_escopo(teste.id(''com_sul''), 1, null, ''coordenador'')', '22023', 'coordenação com abrangência de instituição: recusada') $x$;
  execute $x$ select teste.ok(public.rpc_conceder_escopo(teste.id('com_sul'), 1, null, 'comercial', (select v from teste.var where k = 'sul'))->>'abrangencia' = 'campus', 'Master concede comercial com abrangência de campus') $x$;
  execute $x$ select teste.ok(public.rpc_conceder_escopo(teste.id('gestor_sul'), 1, null, 'gestor', (select v from teste.var where k = 'sul'))->>'abrangencia' = 'campus', 'Master concede gestor com abrangência de campus') $x$;
  execute $x$ select teste.erro('select public.rpc_conceder_escopo(teste.id(''com_sul''), 1, null, ''comercial'', (select v from teste.var where k = ''sul''))', '23505', 'escopo repetido: conflito (409)') $x$;
  execute $x$ select teste.ok((select count(*) = 1 from jsonb_array_elements(public.rpc_master_acessos(1)->'escopos') e where e->>'abrangencia' = 'campus' and e->>'nome' = 'com_sul'), 'painel do Master mostra a abrangência') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('com_sul')::text, false) $x$;
  execute $x$ select teste.ok((select array_agg(x->>'nome') = array['Pedagogia'] from jsonb_array_elements(public.rpc_estrutura(1)->'cursos') x), 'comercial do campus Sul vê apenas o curso do campus') $x$;
  execute $x$ select teste.ok((public.rpc_estrutura(1)->>'acesso_total')::boolean = false, 'escopo de campus não é acesso total') $x$;
  execute $x$ insert into teste.var values ('op_ped', (public.rpc_criar_oportunidade(1, jsonb_build_object('nome', 'Cand Pedagogia', 'email', 'ped@exemplo.invalid', 'curso_id', (select v from teste.var where k = 'ped'),
  'forma_ingresso', 'enem', 'coorte', '2027.1', 'base_legal', 'consentimento', 'origem', 'teste governança'), 'gov-ped-1')->>'id')::bigint) $x$;
  execute $x$ select teste.ok((public.rpc_listar_oportunidades(1, null, null, 1, 100)->>'total')::int = 1, 'lista do campus contém só a oportunidade do campus') $x$;
  execute $x$ select teste.erro('select public.rpc_detalhe((select min(id) from public.oportunidades where ies_id = 1 and curso_id = 1))', 'P0002', 'oportunidade de outro campus: não encontrada') $x$;
  execute $x$ select teste.erro('select public.rpc_criar_oportunidade(1, jsonb_build_object(''nome'', ''X'', ''curso_id'', 1, ''forma_ingresso'', ''enem'', ''coorte'', ''2027.1'', ''base_legal'', ''consentimento'', ''origem'', ''t''), ''gov-fora-campus-1'')', '42501', 'não cadastra em curso fora do campus') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_sul')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_configurar(1, 24)', '42501', 'gestor de campus não altera parâmetros da instituição') $x$;
  execute $x$ select teste.erro('select public.rpc_auditoria(1, 1)', '42501', 'gestor de campus não lê a auditoria da instituição') $x$;
  execute $x$ select teste.ok((public.rpc_detalhe((select v from teste.var where k = 'op_ped'))->'pessoa'->>'email') = 'ped@exemplo.invalid', 'gestor de campus vê o contato no seu campus') $x$;
  execute $x$ select teste.erro('select public.rpc_atendentes(1)', '42501', 'gestor de campus não lista atendentes da instituição inteira') $x$;
  execute $x$ select teste.ok((select bool_or(x->>'nome' = 'com_sul') from jsonb_array_elements(public.rpc_atendentes(1, (select v from teste.var where k = 'ped'))) x), 'gestor de campus lista os atendentes do curso do seu campus') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.ok((select o.responsavel_id in (teste.id('com_sul'), teste.id('comercial_a')) from public.oportunidades o where o.id = (select v from teste.var where k = 'op_ped')), 'distribuição só escolhe atendente que cobre o curso') $x$;
  execute $x$ select teste.ok((select bool_and(x->>'nome' <> 'com_sul') from jsonb_array_elements(public.rpc_atendentes(1, 1)) x), 'atendente do campus Sul não é elegível para curso de outro campus') $x$;
  execute $x$ select teste.ok((select bool_or(x->>'nome' = 'com_sul') from jsonb_array_elements(public.rpc_atendentes(1, (select v from teste.var where k = 'ped'))) x), 'atendente do campus Sul é elegível no curso do campus') $x$;
  execute $x$ reset role $x$;
  execute $x$ create temp table conformidade as
select m.operacao, u.apelido, (e.papel = any (m.papeis)) as esperado, s.sql_teste
  from public.matriz_permissoes m
  join (values
    ('config.alterar',  'select public.rpc_configurar(1, 24)'),
    ('auditoria.ver',   'select public.rpc_auditoria(1, 1)'),
    ('meta.definir',    'select public.rpc_definir_meta(1, 1, ''2027.1'', 10)'),
    ('maim.executar',   'select public.rpc_ciclo_maim(1)'),
    ('fila.ver',        'select public.rpc_fila(1)'),
    ('crm.exportar',    'select public.rpc_exportar_oportunidades(1)'),
    ('painel.ver',      'select public.rpc_central(1, ''2027.1'')')) as s(operacao, sql_teste) on s.operacao = m.operacao
  cross join (values ('gestor_a'), ('reitoria_a'), ('comercial_a'), ('secretaria_a'), ('financeiro_a')) as u(apelido)
  join public.escopos e on e.usuario_id = teste.id(u.apelido) and e.revogado_em is null $x$;
  execute $x$ grant select on conformidade to authenticated $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ do $$
declare r record; got text; n int := 0;
begin
  for r in select * from conformidade loop
    perform set_config('request.jwt.claim.sub', teste.id(r.apelido)::text, false);
    got := teste.tenta(r.sql_teste);
    if r.esperado and got = '42501' then raise exception 'FALHOU: matriz permite % para %, mas a RPC recusou', r.operacao, r.apelido; end if;
    if not r.esperado and got <> '42501' then raise exception 'FALHOU: matriz nega % para %, mas a RPC devolveu %', r.operacao, r.apelido, got; end if;
    n := n + 1;
  end loop;
  if n < 30 then raise exception 'FALHOU: poucas combinações verificadas (%)', n; end if;
end $$ $x$;
  execute $x$ select teste.ok(true, 'matriz de permissões confere com as RPCs (7 operações × 5 papéis)') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.ok((select bool_and(((x->>'permitida')::boolean) = (x->'papeis' ? 'comercial')) from jsonb_array_elements(public.rpc_permissoes(1)->'matriz') x
                 where x->>'abrangencia_minima' = 'curso'), 'permissões efetivas do comercial batem com a matriz') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_sul')::text, false) $x$;
  execute $x$ select teste.ok((select bool_and(not (x->>'permitida')::boolean) from jsonb_array_elements(public.rpc_permissoes(1)->'matriz') x where x->>'abrangencia_minima' = 'ies'),
  'gestor de campus não recebe operações de instituição') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.ok((select (r->>'contato_completo')::boolean and (r->>'total')::int = jsonb_array_length(r->'linhas') and (r->>'total')::int > 0
                 from (select public.rpc_exportar_oportunidades(1, '2027.1') r) x), 'gestor exporta a coorte com contato') $x$;
  execute $x$ select teste.ok((select count(*) from public.auditoria where acao = 'exportacao.gerar' and not (dados ? 'linhas_exportadas') and dados ? 'linhas') >= 1, 'exportação auditada com volume e sem os dados') $x$;
  execute $x$ select teste.erro('select public.rpc_exportar_oportunidades(1, ''2027'')', '22023', 'coorte inválida na exportação recusada') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false) $x$;
  execute $x$ select teste.ok((select not (r->>'contato_completo')::boolean and bool_and(l->>'email' is null or l->>'email' like '%*%') and bool_and((l->>'curso') = 'Direito')
                 from (select public.rpc_exportar_oportunidades(1) r) x, jsonb_array_elements(r->'linhas') l group by r), 'coordenação exporta só o seu curso e com contato mascarado') $x$;
  execute $x$ select teste.erro('select public.rpc_exportar_oportunidades(1, null, 2)', 'P0002', 'coordenação não exporta curso fora do escopo') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_exportar_oportunidades(1)', '42501', 'comercial não exporta') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_exportar_oportunidades(1)', 'P0002', 'gestor de outra IES: exportação não encontrada') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_estrutura(2)', 'P0002', 'R09: estrutura da IES 2 recusada ao gestor da IES 1') $x$;
  execute $x$ select teste.erro('select public.rpc_central(2, ''2027.1'')', 'P0002', 'R09: painel da IES 2 recusado') $x$;
  execute $x$ select teste.erro('select public.rpc_permissoes(2)', 'P0002', 'R09: permissões da IES 2 recusadas') $x$;
  execute $x$ select teste.erro('select public.rpc_agenda(2, now(), now() + interval ''1 day'')', 'P0002', 'R09: agenda da IES 2 recusada') $x$;
  execute $x$ select teste.ok((public.rpc_listar_oportunidades(1, null, null, 1, 100)->'itens') @? '$[*] ? (@.curso == "Psicologia")' = false, 'R09: lista da IES 1 não contém curso da IES 2') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false) $x$;
  execute $x$ select teste.ok((select count(*) from public.oportunidades where curso_id <> 1) = 0, 'R09: coordenação de curso não lê outros cursos nem por tabela direta') $x$;
  execute $x$ reset role $x$;
  execute $x$ insert into teste.var values ('total_a', (select count(*) from public.oportunidades where ies_id = 1)) $x$;
  execute $x$ insert into teste.var values ('op_mov', (select min(id) from public.oportunidades where ies_id = 1 and curso_id = 1
                                          and responsavel_id = teste.id('comercial_a'))) $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select public.rpc_reatribuir((select v from teste.var where k = 'op_mov'), teste.id('com_dir_a'), 'teste de visibilidade por atribuição') $x$;
  execute $x$ select teste.ok((public.rpc_listar_oportunidades(1, null, null, 1, 100)->>'total')::int = (select v from teste.var where k = 'total_a'), 'chefe do setor (gestor) vê todas as oportunidades da equipe') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.ok((select bool_and(x->>'responsavel' = 'comercial_a') from jsonb_array_elements(public.rpc_listar_oportunidades(1, null, null, 1, 100)->'itens') x), 'atendente lista só as oportunidades atribuídas a si') $x$;
  execute $x$ select teste.ok((select count(*) from public.oportunidades where responsavel_id is distinct from teste.id('comercial_a')) = 0, 'atendente não lê oportunidades de colegas nem por tabela direta') $x$;
  execute $x$ select teste.ok((select count(*) from public.pessoas p where not exists (select 1 from public.oportunidades o where o.pessoa_id = p.id)) = 0, 'atendente não lê dados pessoais de candidatos de colegas') $x$;
  execute $x$ select teste.erro('select public.rpc_detalhe((select v from teste.var where k = ''op_mov''))', 'P0002', 'após reatribuição, o atendente anterior perde o acesso (404)') $x$;
  execute $x$ select teste.erro('select public.rpc_mover_etapa((select v from teste.var where k = ''op_mov''), ''perdido'', 99, ''x'')', 'P0002', 'atendente não move oportunidade de colega') $x$;
  execute $x$ select teste.erro('select public.rpc_registrar_interacao((select v from teste.var where k = ''op_mov''), ''ligacao'', ''tentativa'')', 'P0002', 'atendente não registra contato em oportunidade de colega') $x$;
  execute $x$ select teste.ok((select count(*) from jsonb_array_elements(public.rpc_listar_propostas(1, 'pendente_aprovacao')) x
                 where not exists (select 1 from public.oportunidades o where o.id = (x->>'oportunidade_id')::bigint)) = 0, 'atendente não vê propostas de oportunidades de colegas') $x$;
  execute $x$ insert into teste.var values ('op_propria', (public.rpc_criar_oportunidade(1, jsonb_build_object('nome', 'Lead do Atendente', 'email', 'lead.atendente@exemplo.invalid', 'curso_id', 1,
  'forma_ingresso', 'vestibular', 'coorte', '2027.1', 'base_legal', 'consentimento', 'origem', 'indicação'), 'gov-lead-atendente-1')->>'id')::bigint) $x$;
  execute $x$ select teste.ok((select responsavel_id = teste.id('comercial_a') from public.oportunidades where id = (select v from teste.var where k = 'op_propria')), 'quem cadastra como atendente assume o lead') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('com_dir_a')::text, false) $x$;
  execute $x$ select teste.ok((public.rpc_detalhe((select v from teste.var where k = 'op_mov'))->'oportunidade'->>'id')::bigint = (select v from teste.var where k = 'op_mov'), 'novo responsável passa a ver a oportunidade') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false) $x$;
  execute $x$ select teste.ok((public.rpc_listar_oportunidades(1, null, null, 1, 100)->>'total')::int > 1, 'secretaria mantém a visão do escopo (validações)') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.ok((select (x->>'permitida')::boolean from jsonb_array_elements(public.rpc_permissoes(1)->'matriz') x where x->>'operacao' = 'crm.ver_equipe'), 'matriz: gestor tem crm.ver_equipe') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.ok((select not (x->>'permitida')::boolean from jsonb_array_elements(public.rpc_permissoes(1)->'matriz') x where x->>'operacao' = 'crm.ver_equipe'), 'matriz: atendente não tem crm.ver_equipe') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('master')::text, false) $x$;
  execute $x$ select public.rpc_revogar_escopo((select id from public.escopos where usuario_id = teste.id('com_sul') and revogado_em is null)) $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('com_sul')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_estrutura(1)', 'P0002', 'escopo de campus revogado: instituição deixa de ser visível') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok(true, 'fim da bateria de governança') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ insert into teste.var values ('plano', (public.rpc_salvar_plano(1, '{"coorte":"2027.1","titulo":"Plano de captação 2027.1","diagnostico":"Base sintética","orcamento_centavos":5000000,"revisar_em":"2027-03-01"}'::jsonb)->>'id')::bigint) $x$;
  execute $x$ select teste.erro('select public.rpc_salvar_plano(1, ''{"coorte":"2027.1","titulo":"Plano de captação 2027.1"}''::jsonb)', '23505', 'título repetido na coorte: conflito') $x$;
  execute $x$ select teste.erro('select public.rpc_plano_status((select v from teste.var where k = ''plano''), ''submeter'')', '22023', 'plano sem objetivo não é submetido') $x$;
  execute $x$ insert into teste.var values ('obj_ing', (public.rpc_salvar_objetivo((select v from teste.var where k = 'plano'), '{"descricao":"Ingressantes no Direito","indicador":"ingressantes","curso_id":1,"meta":10}'::jsonb)->>'id')::bigint) $x$;
  execute $x$ select public.rpc_salvar_objetivo((select v from teste.var where k = 'plano'), '{"descricao":"CPL institucional","indicador":"cpl_centavos","meta":5000}'::jsonb) $x$;
  execute $x$ select teste.erro('select public.rpc_salvar_objetivo((select v from teste.var where k = ''plano''), ''{"descricao":"Conversão","indicador":"conversao","meta":30}''::jsonb)', '22023', 'meta de conversão acima de 1 recusada') $x$;
  execute $x$ select teste.erro('select public.rpc_salvar_objetivo((select v from teste.var where k = ''plano''), ''{"descricao":"Curso de outra IES","indicador":"ingressantes","curso_id":3,"meta":5}''::jsonb)', '22023', 'objetivo com curso de outra IES recusado') $x$;
  execute $x$ insert into teste.var values ('acao', (public.rpc_salvar_acao((select v from teste.var where k = 'plano'), jsonb_build_object('objetivo_id', (select v from teste.var where k = 'obj_ing'),
  'o_que', 'Visitas a escolas de ensino médio', 'por_que', 'Ampliar leads de vestibular', 'onde', 'Região central', 'quando', '2027-01-20',
  'quem', 'Equipe comercial', 'como', 'Agenda com coordenação pedagógica', 'quanto_centavos', 150000))->>'id')::bigint) $x$;
  execute $x$ select teste.erro('select public.rpc_salvar_plano(1, ''{"titulo":"x"}''::jsonb, (select v from teste.var where k = ''plano''), 99)', '40001', 'edição com versão antiga: conflito') $x$;
  execute $x$ select teste.ok((public.rpc_plano_status((select v from teste.var where k = 'plano'), 'submeter')->>'status') = 'em_aprovacao', 'plano submetido para aprovação') $x$;
  execute $x$ select teste.erro('select public.rpc_plano_status((select v from teste.var where k = ''plano''), ''aprovar'')', '42501', 'quem criou o plano não o aprova (segregação)') $x$;
  execute $x$ select teste.erro('select public.rpc_salvar_objetivo((select v from teste.var where k = ''plano''), ''{"descricao":"Novo","indicador":"oportunidades","meta":100}''::jsonb)', '22023', 'plano em aprovação não aceita novos objetivos') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_planejamento(1, ''2027.1'')', '42501', 'comercial não vê o planejamento') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false) $x$;
  execute $x$ select teste.ok((select (p->>'orcamento_centavos') is null and jsonb_array_length(p->'objetivos') = 2 from jsonb_array_elements(public.rpc_planejamento(1, '2027.1')->'planos') p),
  'coordenação vê o plano sem valores financeiros') $x$;
  execute $x$ select teste.erro('select public.rpc_plano_status((select v from teste.var where k = ''plano''), ''aprovar'')', '42501', 'coordenação não aprova plano') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('reitoria_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_plano_status((select v from teste.var where k = ''plano''), ''devolver'')', '22023', 'devolução sem justificativa recusada') $x$;
  execute $x$ select teste.ok((public.rpc_plano_status((select v from teste.var where k = 'plano'), 'aprovar')->>'status') = 'aprovado', 'reitoria aprova o plano criado pelo gestor') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_salvar_acao((select v from teste.var where k = ''plano''), ''{"o_que":"Mudança após aprovação"}''::jsonb, (select v from teste.var where k = ''acao''))', '22023', 'plano aprovado preserva o conteúdo das ações') $x$;
  execute $x$ select teste.ok((public.rpc_salvar_acao((select v from teste.var where k = 'plano'), '{"status":"em_andamento"}'::jsonb, (select v from teste.var where k = 'acao'))->>'id') is not null, 'plano aprovado aceita acompanhamento do status da ação') $x$;
  execute $x$ select teste.ok((select (o->>'realizado')::numeric = (select count(distinct pessoa_id) from public.oportunidades where ies_id = 1 and coorte = '2027.1' and curso_id = 1 and etapa = 'confirmado')
                 from jsonb_array_elements(public.rpc_planejamento(1, '2027.1')->'planos'->0->'objetivos') o where o->>'indicador' = 'ingressantes'), 'realizado calculado dos dados, não digitado') $x$;
  execute $x$ select teste.ok((select o->'realizado' = 'null'::jsonb from jsonb_array_elements(public.rpc_planejamento(1, '2027.1')->'planos'->0->'objetivos') o where o->>'indicador' = 'cpl_centavos'), 'CPL sem custo lançado é N/D, não zero') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_plano_status((select v from teste.var where k = ''plano''), ''revisar'', ''tentativa cruzada'')', 'P0002', 'gestor de outra IES não alcança o plano') $x$;
  execute $x$ select teste.ok(jsonb_array_length(public.rpc_planejamento(2, '2027.1')->'planos') = 0, 'planejamento isolado por instituição') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_registrar_concorrencia(1, ''{"instituicao":"Faculdade X","curso":"Direito","fonte_url":"sem fonte","coletado_em":"2026-11-01"}''::jsonb)', '22023', 'concorrência sem fonte verificável recusada') $x$;
  execute $x$ select teste.erro('select public.rpc_registrar_concorrencia(1, ''{"instituicao":"Faculdade X","curso":"Direito","fonte_url":"https://exemplo.invalid/direito","coletado_em":"2099-01-01"}''::jsonb)', '22023', 'data de coleta futura recusada') $x$;
  execute $x$ insert into teste.var values ('conc', (public.rpc_registrar_concorrencia(1, jsonb_build_object('instituicao', 'Faculdade X (fictícia)', 'curso', 'Direito', 'modalidade', 'presencial',
  'mensalidade_centavos', 119000, 'fonte_url', 'https://exemplo.invalid/direito', 'coletado_em', current_date - 3))->>'id')::bigint) $x$;
  execute $x$ select teste.erro('select public.rpc_revisar_concorrencia((select v from teste.var where k = ''conc''))', '42501', 'coordenação não revisa registro de concorrência') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.ok((public.rpc_revisar_concorrencia((select v from teste.var where k = 'conc'))->>'revisado')::boolean, 'gestor revisa registro feito por outra pessoa') $x$;
  execute $x$ select teste.ok((public.rpc_concorrencia(1)->0->>'revisado_por') is not null, 'registro mostra quem revisou') $x$;
  execute $x$ insert into teste.var values ('camp', (public.rpc_salvar_campanha(1, jsonb_build_object('coorte', '2027.1', 'nome', 'Vestibular de verão', 'codigo', 'verao-2027',
  'canal', 'meta_ads', 'inicio', '2026-11-01', 'fim', '2027-02-28', 'orcamento_centavos', 1200000, 'status', 'ativa', 'plano_id', (select v from teste.var where k = 'plano')))->>'id')::bigint) $x$;
  execute $x$ select teste.erro('select public.rpc_salvar_campanha(1, ''{"coorte":"2027.1","nome":"Outra","codigo":"verao-2027","canal":"site","inicio":"2026-11-01","fim":"2027-01-01"}''::jsonb)', '23505', 'código de campanha repetido: conflito') $x$;
  execute $x$ select teste.erro('select public.rpc_salvar_campanha(1, ''{"coorte":"2027.1","nome":"Inválida","codigo":"Código Ruim","canal":"site","inicio":"2026-11-01","fim":"2027-01-01"}''::jsonb)', '22023', 'código de campanha fora do padrão recusado') $x$;
  execute $x$ select teste.erro('select public.rpc_salvar_campanha(1, ''{"coorte":"2027.1","nome":"Datas","codigo":"datas-ruins","canal":"site","inicio":"2027-02-01","fim":"2027-01-01"}''::jsonb)', '22023', 'fim antes do início recusado') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_salvar_campanha(1, ''{"coorte":"2027.1","nome":"Do atendente","codigo":"do-atendente","canal":"site","inicio":"2026-11-01","fim":"2027-01-01"}''::jsonb)', '42501', 'comercial não cria campanha') $x$;
  execute $x$ select teste.ok((select c->>'codigo' = 'verao-2027' and c->'custo_centavos' = 'null'::jsonb from jsonb_array_elements(public.rpc_campanhas(1, '2027.1')->'campanhas') c),
  'comercial vê a campanha e o código, sem custos') $x$;
  execute $x$ insert into teste.var values ('op_camp', (public.rpc_criar_oportunidade(1, jsonb_build_object('nome', 'Lead da Campanha', 'email', 'lead.campanha@exemplo.invalid', 'curso_id', 1,
  'forma_ingresso', 'vestibular', 'coorte', '2027.1', 'base_legal', 'consentimento', 'origem', 'anúncio', 'campanha', 'VERAO-2027'), 'camp-lead-0001')->>'id')::bigint) $x$;
  execute $x$ select teste.erro('select public.rpc_criar_oportunidade(1, jsonb_build_object(''nome'', ''Lead perdido'', ''email'', ''perdido@exemplo.invalid'', ''curso_id'', 1, ''forma_ingresso'', ''enem'', ''coorte'', ''2027.1'', ''base_legal'', ''consentimento'', ''origem'', ''x'', ''campanha'', ''nao-existe''), ''camp-lead-0002'')',
  '22023', 'código de campanha inexistente é recusado (atribuição não se perde em silêncio)') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('financeiro_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_lancar_custo((select v from teste.var where k = ''camp''), current_date + 1, 1000, ''futuro'', ''custo-futuro-1'')', '22023', 'custo com data futura recusado') $x$;
  execute $x$ insert into teste.var values ('custo', (public.rpc_lancar_custo((select v from teste.var where k = 'camp'), current_date, 300000, 'Impulsionamento novembro', 'custo-nov-0001')->>'id')::bigint) $x$;
  execute $x$ select teste.ok((public.rpc_lancar_custo((select v from teste.var where k = 'camp'), current_date, 300000, 'Impulsionamento novembro', 'custo-nov-0001')->>'repeticao')::boolean, 'lançamento repetido com a mesma chave não duplica') $x$;
  execute $x$ insert into teste.var values ('custo_erro', (public.rpc_lancar_custo((select v from teste.var where k = 'camp'), current_date, 99999, 'Lançado por engano', 'custo-erro-0001')->>'id')::bigint) $x$;
  execute $x$ select teste.erro('select public.rpc_estornar_custo((select v from teste.var where k = ''custo_erro''), '''')', '22023', 'estorno sem motivo recusado') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.ok((public.rpc_estornar_custo((select v from teste.var where k = 'custo_erro'), 'valor lançado em duplicidade')->>'estornado')::boolean, 'estorno auditado') $x$;
  execute $x$ select teste.ok((select (c->>'custo_centavos')::bigint = 300000 and (c->>'leads')::int = 1 and (c->>'cpl_centavos')::bigint = 300000
                 from jsonb_array_elements(public.rpc_campanhas(1, '2027.1')->'campanhas') c where c->>'codigo' = 'verao-2027'), 'CPL da campanha = custo sem estornos ÷ leads atribuídos') $x$;
  execute $x$ select teste.ok((select (c->>'custo_ingressante_centavos') is null from jsonb_array_elements(public.rpc_campanhas(1, '2027.1')->'campanhas') c where c->>'codigo' = 'verao-2027'),
  'custo por ingressante N/D sem ingressante atribuído') $x$;
  execute $x$ select teste.ok((public.rpc_campanhas(1, '2027.1')->'atribuicao_desconhecida'->>'leads')::int > 0, 'leads sem campanha aparecem como atribuição desconhecida') $x$;
  execute $x$ select teste.ok((select (t->>'custo_por_lead_centavos')::bigint = 300000 and (t->>'leads_atribuidos')::int = 1 from (select public.rpc_central(1, '2027.1')->'totais' t) x), 'Central mostra CPL com custo lançado') $x$;
  execute $x$ select teste.ok((public.rpc_central(1, '2027.1', '{"curso_id":"1"}')->'totais'->>'custo_motivo') like '%não é rateado%', 'Central: custo N/D com recorte por curso, com motivo') $x$;
  execute $x$ select teste.ok((select (t->>'oportunidades')::int = 1 from (select public.rpc_central(1, '2027.1', jsonb_build_object('campanha_id', (select v from teste.var where k = 'camp')::text))->'totais' t) x), 'filtro global de campanha na Central') $x$;
  execute $x$ select teste.ok((public.rpc_central(1, '2027.1')->'por_campanha') @? '$[*] ? (@.chave == "Atribuição desconhecida")', 'Central separa atribuição desconhecida') $x$;
  execute $x$ select teste.ok((select (o->>'realizado')::numeric = 300000 from jsonb_array_elements(public.rpc_planejamento(1, '2027.1')->'planos'->0->'objetivos') o where o->>'indicador' = 'cpl_centavos'), 'objetivo de CPL acompanha o custo lançado') $x$;
  execute $x$ select teste.ok((public.rpc_planejamento(1, '2027.1')->'planos'->0->>'gasto_centavos')::bigint = 300000, 'gasto do plano soma custos das campanhas vinculadas, sem estornos') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('reitoria_a')::text, false) $x$;
  execute $x$ select teste.ok((select (t->>'custo_por_lead_centavos') is not null from (select public.rpc_central(1, '2027.1')->'totais' t) x), 'reitoria vê custos') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false) $x$;
  execute $x$ select teste.ok((select (t->>'custo_por_lead_centavos') is null and (t->>'custo_motivo') like '%apenas%' from (select public.rpc_central(1, '2027.1')->'totais' t) x), 'coordenação não vê custos, com motivo') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_lancar_custo((select v from teste.var where k = ''camp''), current_date, 100, ''cruzado'', ''custo-cruzado-1'')', 'P0002', 'gestor de outra IES não lança custo na campanha da Alfa') $x$;
  execute $x$ select teste.ok(jsonb_array_length(public.rpc_campanhas(2, '2027.1')->'campanhas') = 0, 'campanhas isoladas por instituição') $x$;
  execute $x$ select teste.erro('select public.rpc_criar_oportunidade(2, jsonb_build_object(''nome'', ''Cruzado'', ''email'', ''cruzado@exemplo.invalid'', ''curso_id'', 3, ''forma_ingresso'', ''enem'', ''coorte'', ''2027.1'', ''base_legal'', ''consentimento'', ''origem'', ''x'', ''campanha'', ''verao-2027''), ''camp-cruzada-001'')',
  '22023', 'código de campanha de outra IES não é aceito') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_salvar_campanha(1, ''{"codigo":"novo-codigo"}''::jsonb, (select v from teste.var where k = ''camp''), 1)', '22023', 'código não muda com oportunidades atribuídas') $x$;
  execute $x$ select teste.erro('select count(*) from public.campanhas', '42501', 'campanhas sem leitura direta (só por RPC)') $x$;
  execute $x$ select teste.erro('select count(*) from public.planos', '42501', 'planos sem leitura direta (só por RPC)') $x$;
  execute $x$ select teste.erro('insert into public.custos_campanha(ies_id, campanha_id, data, valor_centavos, descricao, lancado_por) values (1, 1, current_date, 1, ''x'', auth.uid())', '42501', 'escrita direta em custos bloqueada') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok(true, 'fim da bateria de planejamento e campanhas') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select count(*) from public.funis where padrao) = (select count(*) from public.ies), 'toda IES tem funil padrão (inclusive as criadas depois da migração)') $x$;
  execute $x$ select teste.ok((select count(*) from public.oportunidades where funil_versao_id is null) = 0, 'toda oportunidade tem versão de funil fixada') $x$;
  execute $x$ select teste.ok((select bool_and(o.funil_etapa_ordem is not null) from public.oportunidades o where o.etapa in ('novo','contato','inscrito','pre_matricula','matricula_comercial')),
  'oportunidades abertas posicionadas na subetapa equivalente à etapa oficial') $x$;
  execute $x$ select teste.ok((select bool_and(o.funil_etapa_ordem is null) from public.oportunidades o where o.etapa in ('confirmado','perdido','cancelado')), 'etapas encerradas ficam sem subetapa') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.ok((select jsonb_array_length(f->'versoes'->0->'etapas') = 5 and (f->>'padrao')::boolean from jsonb_array_elements(public.rpc_funis(1)->'funis') f where (f->>'padrao')::boolean),
  'funil padrão replica as 5 etapas oficiais abertas') $x$;
  execute $x$ select teste.erro('select public.rpc_salvar_funil(1, ''{"nome":"Sem critério"}''::jsonb)', '22023', 'funil específico sem modalidade nem forma recusado') $x$;
  execute $x$ insert into teste.var values ('funil_ead', (public.rpc_salvar_funil(1, '{"nome":"Funil EAD","modalidade":"ead"}'::jsonb)->>'id')::bigint) $x$;
  execute $x$ insert into teste.var values ('v_ead', (select (v->>'id')::bigint from jsonb_array_elements(public.rpc_funis(1)->'funis') f, jsonb_array_elements(f->'versoes') v
                                         where (f->>'id')::bigint = (select v from teste.var where k = 'funil_ead'))) $x$;
  execute $x$ select teste.erro('select public.rpc_nova_versao((select v from teste.var where k = ''funil_ead''))', '22023', 'segundo rascunho do mesmo funil recusado') $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_versao((select v from teste.var where k = 'v_ead'), '{"etapas":[
  {"ordem":1,"nome":"Novo","etapa_base":"novo"},{"ordem":2,"nome":"Contato","etapa_base":"contato"},{"ordem":3,"nome":"Inscrito","etapa_base":"inscrito"},
  {"ordem":4,"nome":"Pré","etapa_base":"pre_matricula"},{"ordem":5,"nome":"Mais um","etapa_base":"pre_matricula"}]}'::jsonb)$q$, '22023', 'versão sem etapa oficial coberta (matrícula comercial) recusada') $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_versao((select v from teste.var where k = 'v_ead'), '{"etapas":[
  {"ordem":1,"nome":"Novo","etapa_base":"novo"},{"ordem":2,"nome":"Inscrito","etapa_base":"inscrito"},{"ordem":3,"nome":"Contato","etapa_base":"contato"},
  {"ordem":4,"nome":"Pré","etapa_base":"pre_matricula"},{"ordem":5,"nome":"MC","etapa_base":"matricula_comercial"}]}'::jsonb)$q$, '22023', 'ordem incoerente com as etapas oficiais recusada') $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_versao((select v from teste.var where k = 'v_ead'), '{"etapas":[
  {"ordem":1,"nome":"Novo","etapa_base":"novo"},{"ordem":2,"nome":"Contato","etapa_base":"contato"},{"ordem":4,"nome":"Inscrito","etapa_base":"inscrito"},
  {"ordem":5,"nome":"Pré","etapa_base":"pre_matricula"},{"ordem":6,"nome":"MC","etapa_base":"matricula_comercial"}]}'::jsonb)$q$, '22023', 'numeração com lacuna recusada') $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_versao((select v from teste.var where k = 'v_ead'), '{"etapas":[
  {"ordem":1,"nome":"Novo","etapa_base":"novo"},{"ordem":2,"nome":"Contato","etapa_base":"contato"},{"ordem":3,"nome":"Inscrito","etapa_base":"confirmado"},
  {"ordem":4,"nome":"Pré","etapa_base":"pre_matricula"},{"ordem":5,"nome":"MC","etapa_base":"matricula_comercial"}]}'::jsonb)$q$, '22023', 'etapa encerrada (ingresso) não é configurável') $x$;
  execute $x$ select teste.ok((public.rpc_salvar_versao((select v from teste.var where k = 'v_ead'), '{"notas":"Contato desdobrado para EAD","etapas":[
  {"ordem":1,"nome":"Novo lead EAD","etapa_base":"novo","sla_horas":4,"roteiro":"Apresente-se e confirme o interesse no curso."},
  {"ordem":2,"nome":"1ª tentativa","etapa_base":"contato","sla_horas":24},
  {"ordem":3,"nome":"Demonstração da plataforma","etapa_base":"contato","roteiro":"Mostre o ambiente virtual e a rotina de estudos."},
  {"ordem":4,"nome":"Inscrito","etapa_base":"inscrito"},{"ordem":5,"nome":"Pré-matrícula","etapa_base":"pre_matricula"},
  {"ordem":6,"nome":"Matrícula comercial","etapa_base":"matricula_comercial"}],
  "cadencias":[{"etapa_ordem":2,"passo":1,"dia":0,"canal":"whatsapp","descricao":"Mensagem de boas-vindas (registro manual)"},
               {"etapa_ordem":2,"passo":2,"dia":2,"canal":"telefone","descricao":"Ligação de acompanhamento"}],
  "metas":[{"forma_ingresso":"enem","conversao_meta":0.2},{"forma_ingresso":"vestibular","conversao_meta":0.15}]}'::jsonb)->'etapas'->2->>'nome') = 'Demonstração da plataforma',
  'rascunho salvo com subetapas, roteiro, cadência e metas por forma') $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_versao((select v from teste.var where k = 'v_ead'), '{"etapas":[
  {"ordem":1,"nome":"Novo","etapa_base":"novo"},{"ordem":2,"nome":"Contato","etapa_base":"contato"},{"ordem":3,"nome":"Inscrito","etapa_base":"inscrito"},
  {"ordem":4,"nome":"Pré","etapa_base":"pre_matricula"},{"ordem":5,"nome":"MC","etapa_base":"matricula_comercial"}],
  "metas":[{"forma_ingresso":"enem","conversao_meta":1.5}]}'::jsonb)$q$, '22023', 'meta de conversão acima de 100% recusada (rascunho anterior preservado)') $x$;
  execute $x$ select teste.ok((select jsonb_array_length(v->'etapas') = 6 from jsonb_array_elements(public.rpc_funis(1)->'funis') f, jsonb_array_elements(f->'versoes') v
                 where (v->>'id')::bigint = (select v from teste.var where k = 'v_ead')), 'falha de validação não altera o rascunho (transação atômica)') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_publicar_versao((select v from teste.var where k = ''v_ead''))', '42501', 'comercial não publica funil') $x$;
  execute $x$ select teste.ok(jsonb_array_length(public.rpc_funis(1)->'funis') = 2, 'comercial vê os funis (roteiros e cadências)') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_publicar_versao((select v from teste.var where k = ''v_ead''))', 'P0002', 'gestor de outra IES não alcança o funil') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.ok((public.rpc_publicar_versao((select v from teste.var where k = 'v_ead'))->>'versao')::int = 1, 'gestor publica o funil EAD') $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_versao((select v from teste.var where k = 'v_ead'), '{"etapas":[]}'::jsonb)$q$, '22023', 'versão publicada é imutável') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ insert into teste.var values ('op_ead', (public.rpc_criar_oportunidade(1, jsonb_build_object('nome', 'Lead EAD', 'email', 'lead.ead@exemplo.invalid', 'curso_id', 2,
  'forma_ingresso', 'enem', 'coorte', '2027.1', 'base_legal', 'consentimento', 'origem', 'site'), 'funil-ead-0001')->>'id')::bigint) $x$;
  execute $x$ select teste.ok((select r->>'funil' = 'Funil EAD' and (r->'atual'->>'nome') = 'Novo lead EAD' and (r->'meta_conversao_forma')::numeric = 0.2
                 from (select public.rpc_funil_oportunidade((select v from teste.var where k = 'op_ead')) r) x), 'curso EAD recebe o funil EAD, com roteiro e meta da forma') $x$;
  execute $x$ insert into teste.var values ('op_pres', (public.rpc_criar_oportunidade(1, jsonb_build_object('nome', 'Lead Presencial', 'email', 'lead.pres@exemplo.invalid', 'curso_id', 1,
  'forma_ingresso', 'enem', 'coorte', '2027.1', 'base_legal', 'consentimento', 'origem', 'site'), 'funil-pres-0001')->>'id')::bigint) $x$;
  execute $x$ select teste.ok((public.rpc_funil_oportunidade((select v from teste.var where k = 'op_pres'))->>'funil') = 'Funil padrão institucional', 'curso presencial fica no funil padrão') $x$;
  execute $x$ select public.rpc_mover_etapa((select v from teste.var where k = 'op_ead'), 'contato', 1, null, 'funil-ead-mover-1') $x$;
  execute $x$ select teste.ok((select (r->'atual'->>'nome') = '1ª tentativa' and jsonb_array_length(r->'subetapas') = 2 and jsonb_array_length(r->'cadencia') = 2
                 from (select public.rpc_funil_oportunidade((select v from teste.var where k = 'op_ead')) r) x), 'mudança de etapa oficial posiciona na primeira subetapa, com cadência') $x$;
  execute $x$ select teste.erro('select public.rpc_mover_subetapa((select v from teste.var where k = ''op_ead''), 4, 2)', '22023', 'subetapa de outra etapa oficial recusada') $x$;
  execute $x$ select teste.erro('select public.rpc_mover_subetapa((select v from teste.var where k = ''op_ead''), 3, 1)', '40001', 'subetapa com versão antiga: conflito') $x$;
  execute $x$ select teste.ok((public.rpc_mover_subetapa((select v from teste.var where k = 'op_ead'), 3, 2)->>'etapa_ordem')::int = 3, 'subetapa avança dentro da etapa oficial') $x$;
  execute $x$ select teste.ok((select etapa = 'contato' from public.oportunidades where id = (select v from teste.var where k = 'op_ead')), 'subetapa não altera a etapa oficial') $x$;
  execute $x$ select teste.ok((public.rpc_detalhe((select v from teste.var where k = 'op_ead'))->'historico') @? '$[*] ? (@.acao == "oportunidade.subetapa")', 'mudança de subetapa auditada') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ insert into teste.var values ('v_ead2', (public.rpc_nova_versao((select v from teste.var where k = 'funil_ead'))->>'versao_id')::bigint) $x$;
  execute $x$ select teste.ok((select jsonb_array_length(public.rpc_funis(1)->'funis') = 2), 'nova versão criada como rascunho') $x$;
  execute $x$ select public.rpc_salvar_versao((select v from teste.var where k = 'v_ead2'), '{"etapas":[
  {"ordem":1,"nome":"Novo","etapa_base":"novo"},{"ordem":2,"nome":"Contato","etapa_base":"contato"},{"ordem":3,"nome":"Inscrito","etapa_base":"inscrito"},
  {"ordem":4,"nome":"Pré","etapa_base":"pre_matricula"},{"ordem":5,"nome":"MC","etapa_base":"matricula_comercial"}]}'::jsonb) $x$;
  execute $x$ select public.rpc_publicar_versao((select v from teste.var where k = 'v_ead2')) $x$;
  execute $x$ select teste.ok((select (r->>'versao')::int = 1 and r->>'versao_status' = 'arquivada' and (r->'atual'->>'nome') = 'Demonstração da plataforma'
                 from (select public.rpc_funil_oportunidade((select v from teste.var where k = 'op_ead')) r) x), 'oportunidade antiga continua na versão em que nasceu (histórico preservado)') $x$;
  execute $x$ select teste.ok((select (v->>'status') = 'arquivada' from jsonb_array_elements(public.rpc_funis(1)->'funis') f, jsonb_array_elements(f->'versoes') v
                 where (v->>'id')::bigint = (select v from teste.var where k = 'v_ead')), 'versão anterior arquivada ao publicar a nova') $x$;
  execute $x$ select teste.ok((select (d->>'oportunidades')::int >= 1 from jsonb_array_elements(public.rpc_funis(1)->'funis') f, jsonb_array_elements(f->'desempenho') d
                 where f->>'nome' = 'Funil EAD' and d->>'forma_ingresso' = 'enem'), 'desempenho por forma de ingresso calculado') $x$;
  execute $x$ select teste.erro('select count(*) from public.funis', '42501', 'funis sem leitura direta (só por RPC)') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('master')::text, false) $x$;
  execute $x$ insert into teste.var values ('ies_nova', (public.rpc_provisionar_ies('Faculdade Gama (fictícia)', 'piloto', 'Campus Único',
  '[{"nome":"Pedagogia","turno":"noturno","modalidade":"ead","mensalidade_centavos":29900}]'::jsonb)->>'id')::bigint) $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select count(*) = 1 from public.funis where ies_id = (select v from teste.var where k = 'ies_nova') and padrao), 'instituição nova nasce com funil padrão publicado') $x$;
  execute $x$ select teste.ok(true, 'fim da bateria de funis') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ insert into teste.var values ('perf_ok', 1) $x$;
  execute $x$ select teste.ok((select jsonb_array_length(r->'etapas') = 5 and r->>'regra' = 'performance-v1' and r->>'aviso' like '%decisões laborais%'
                 from (select public.rpc_performance(1, '2027.1') r) x), 'cinco etapas oficiais, regra versionada e aviso de uso') $x$;
  execute $x$ select teste.ok((select bool_and((e->>'denominador')::int = (e->>'alcancaram')::int and ((e->>'alcancaram')::int = 0) = (e->'conversao_etapa' = 'null'::jsonb))
                 from jsonb_array_elements(public.rpc_performance(1, '2027.1')->'etapas') e), 'conversão da etapa com denominador explícito; N/D sem base') $x$;
  execute $x$ select teste.ok((select (e->>'alcancaram')::int = (select count(*) from public.oportunidades where ies_id = 1 and coorte = '2027.1')
                 from jsonb_array_elements(public.rpc_performance(1, '2027.1')->'etapas') e where e->>'etapa' = 'novo'), 'toda oportunidade da coorte alcançou a etapa novo') $x$;
  execute $x$ select teste.ok((select bool_and((e->>'avancaram')::int <= (e->>'alcancaram')::int) from jsonb_array_elements(public.rpc_performance(1, '2027.1')->'etapas') e), 'avanço nunca excede o alcance') $x$;
  execute $x$ select teste.ok((select r->'gargalo' = 'null'::jsonb or ((r->'gargalo'->>'alcancaram')::int >= 10) from (select public.rpc_performance(1, '2027.1') r) x), 'gargalo só com amostra mínima') $x$;
  execute $x$ select teste.ok((select jsonb_array_length(r->'atendentes') >= 2 and (r->>'ve_equipe')::boolean from (select public.rpc_performance(1, '2027.1') r) x), 'gestor vê a equipe') $x$;
  execute $x$ select teste.ok((select bool_and(a->'sla_primeiro_contato' = 'null'::jsonb or ((a->>'sla_primeiro_contato')::numeric between 0 and 1 and (a->>'sla_denominador')::int > 0))
                 from jsonb_array_elements(public.rpc_performance(1, '2027.1')->'atendentes') a), 'SLA do primeiro contato entre 0 e 1 com denominador') $x$;
  execute $x$ select teste.ok((select sum((a->>'oportunidades')::int) = (select count(*) from public.oportunidades where ies_id = 1 and coorte = '2027.1')
                 from jsonb_array_elements(public.rpc_performance(1, '2027.1')->'atendentes') a), 'soma por atendente fecha com o total da coorte') $x$;
  execute $x$ select teste.ok((select bool_and(x->>'regra' like 'performance-v1/%' and length(x->>'justificativa') > 10) from jsonb_array_elements(public.rpc_performance(1, '2027.1')->'recomendacoes') x) is not false,
  'recomendações com regra versionada e justificativa') $x$;
  execute $x$ select teste.ok((select (e->>'alcancaram')::int <= (select count(*) from public.oportunidades where ies_id = 1 and coorte = '2027.1' and curso_id = 1)
                 from jsonb_array_elements(public.rpc_performance(1, '2027.1', '{"curso_id":"1"}')->'etapas') e where e->>'etapa' = 'novo'), 'filtro de curso aplicado') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.ok((select (r->>'ve_equipe')::boolean = false and jsonb_array_length(r->'atendentes') <= 1 and coalesce(bool_and((a->>'eu')::boolean), true)
                 from (select public.rpc_performance(1, '2027.1') r) x left join lateral jsonb_array_elements(r->'atendentes') a on true group by r),
  'atendente vê apenas a própria linha') $x$;
  execute $x$ select teste.ok((public.rpc_performance(1, '2027.1')->'sla_primeiro_contato_equipe') = 'null'::jsonb, 'atendente não vê o SLA consolidado da equipe') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false) $x$;
  execute $x$ select teste.ok((select jsonb_array_length(r->'atendentes') = 0 and (e->>'alcancaram')::int <= (select count(*) from public.oportunidades where ies_id = 1 and coorte = '2027.1' and curso_id = 1)
                 from (select public.rpc_performance(1, '2027.1') r) x, jsonb_array_elements(r->'etapas') e where e->>'etapa' = 'novo'),
  'coordenação vê etapas só do seu curso e nenhum indicador individual') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_performance(1, ''2027.1'')', '42501', 'secretaria não acessa performance comercial') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_performance(1, ''2027.1'')', 'P0002', 'gestor de outra IES: não encontrado') $x$;
  execute $x$ select teste.erro('select public.rpc_performance(2, ''2027'')', '22023', 'coorte inválida recusada') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok(true, 'fim da bateria de performance') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ insert into teste.var values ('rec_ok', (public.rpc_criar_oportunidade(1, jsonb_build_object('nome', 'Perdido Elegível', 'email', 'perdido.ok@exemplo.invalid', 'curso_id', 1,
  'forma_ingresso', 'vestibular', 'coorte', '2027.1', 'base_legal', 'consentimento', 'origem', 'site'), 'rec-ok-000001')->>'id')::bigint) $x$;
  execute $x$ insert into teste.var values ('rec_base', (public.rpc_criar_oportunidade(1, jsonb_build_object('nome', 'Perdido Contratual', 'email', 'perdido.base@exemplo.invalid', 'curso_id', 1,
  'forma_ingresso', 'vestibular', 'coorte', '2027.1', 'base_legal', 'procedimentos_preliminares_contrato', 'origem', 'site'), 'rec-base-00001')->>'id')::bigint) $x$;
  execute $x$ insert into teste.var values ('rec_opt', (public.rpc_criar_oportunidade(1, jsonb_build_object('nome', 'Perdido Optout', 'email', 'perdido.opt@exemplo.invalid', 'curso_id', 1,
  'forma_ingresso', 'vestibular', 'coorte', '2027.1', 'base_legal', 'consentimento', 'origem', 'site'), 'rec-opt-000001')->>'id')::bigint) $x$;
  execute $x$ select public.rpc_mover_etapa((select v from teste.var where k = 'rec_ok'), 'perdido', 1, 'Mensalidade acima do orçamento', 'rec-mov-ok-01') $x$;
  execute $x$ select public.rpc_mover_etapa((select v from teste.var where k = 'rec_base'), 'perdido', 1, 'Sem retorno', 'rec-mov-base-1') $x$;
  execute $x$ select public.rpc_mover_etapa((select v from teste.var where k = 'rec_opt'), 'perdido', 1, 'Desistiu', 'rec-mov-opt-01') $x$;
  execute $x$ select public.rpc_optout((select v from teste.var where k = 'rec_opt'), 'email') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.ok((select (x->>'elegivel')::boolean = false and x->>'motivo_inelegivel' like 'Em carência%' from jsonb_array_elements(public.rpc_recuperaveis(1, 30)) x
                 where (x->>'id')::bigint = (select v from teste.var where k = 'rec_ok')), 'perda recente respeita a carência') $x$;
  execute $x$ select teste.ok((select (x->>'elegivel')::boolean from jsonb_array_elements(public.rpc_recuperaveis(1, 0)) x where (x->>'id')::bigint = (select v from teste.var where k = 'rec_ok')),
  'sem carência, perdido com consentimento e canal disponível é elegível') $x$;
  execute $x$ select teste.ok((select x->>'motivo_inelegivel' like 'Base legal%' from jsonb_array_elements(public.rpc_recuperaveis(1, 0)) x where (x->>'id')::bigint = (select v from teste.var where k = 'rec_base')),
  'base legal contratual não permite novo contato após a perda') $x$;
  execute $x$ select teste.ok((select x->>'motivo_inelegivel' like 'Sem canal%' from jsonb_array_elements(public.rpc_recuperaveis(1, 0)) x where (x->>'id')::bigint = (select v from teste.var where k = 'rec_opt')),
  'opt-out no único canal torna inelegível') $x$;
  execute $x$ select teste.ok((select bool_and(x->>'motivo_perda' ilike '%orçamento%') from jsonb_array_elements(public.rpc_recuperaveis(1, 0, 'orçamento')) x), 'filtro por motivo de perda') $x$;
  execute $x$ select teste.erro('select public.rpc_salvar_protocolo(1, ''{"nome":"Sem meta","tipo":"recuperacao_base","responsavel":"Equipe","prazo":"2027-01-31","coorte_destino":"2027.1"}''::jsonb)', '22023', 'protocolo sem meta recusado') $x$;
  execute $x$ insert into teste.var values ('prot', (public.rpc_salvar_protocolo(1, '{"nome":"Recuperação de base 2027.1","tipo":"recuperacao_base","responsavel":"Coordenação comercial",
  "prazo":"2027-02-15","checklist":["Revisar motivo de perda","Oferecer condição vigente","Registrar contato"],"meta":2,"custo_centavos":50000,"coorte_destino":"2027.1","carencia_dias":0}'::jsonb)->>'id')::bigint) $x$;
  execute $x$ insert into teste.var values ('prot_prox', (public.rpc_salvar_protocolo(1, '{"nome":"Reingresso 2027.2","tipo":"reingresso","responsavel":"Coordenação comercial",
  "prazo":"2027-06-30","meta":1,"coorte_destino":"2027.2","carencia_dias":0}'::jsonb)->>'id')::bigint) $x$;
  execute $x$ select teste.ok((select (r->>'selecionadas')::int = 1 and jsonb_array_length(r->'recusadas') = 2
                 from (select public.rpc_selecionar_recuperacao((select v from teste.var where k = 'prot'),
                         array[(select v from teste.var where k = 'rec_ok'), (select v from teste.var where k = 'rec_base'), (select v from teste.var where k = 'rec_opt')]) r) x),
  'seleção aceita só elegíveis e devolve o motivo das recusadas') $x$;
  execute $x$ select teste.ok((select jsonb_array_length((public.rpc_selecionar_recuperacao((select v from teste.var where k = 'prot'), array[(select v from teste.var where k = 'rec_ok')]))->'recusadas') = 1),
  'mesma oportunidade não entra duas vezes no protocolo') $x$;
  execute $x$ insert into teste.var values ('item', (select (i->>'id')::bigint from jsonb_array_elements(public.rpc_recuperacao(1)->'protocolos') p, jsonb_array_elements(p->'itens') i
                                        where (p->>'id')::bigint = (select v from teste.var where k = 'prot'))) $x$;
  execute $x$ select teste.ok((select p->>'status' = 'em_execucao' from jsonb_array_elements(public.rpc_recuperacao(1)->'protocolos') p where (p->>'id')::bigint = (select v from teste.var where k = 'prot')),
  'protocolo passa a em execução ao receber a base') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('com_dir_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_tratar_recuperacao((select v from teste.var where k = ''item''), ''contatada'', ''tentativa'')', 'P0002', 'atendente não trata item atribuído a outro') $x$;
  execute $x$ select teste.ok((select coalesce(sum(jsonb_array_length(p->'itens')), 0) = 0 from jsonb_array_elements(public.rpc_recuperacao(1)->'protocolos') p), 'atendente não vê itens de outros') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_selecionar_recuperacao((select v from teste.var where k = ''prot''), array[1])', '42501', 'atendente não seleciona base') $x$;
  execute $x$ select teste.erro('select public.rpc_tratar_recuperacao((select v from teste.var where k = ''item''), ''contatada'', '''')', '22023', 'contato sem resumo recusado') $x$;
  execute $x$ select teste.ok((public.rpc_tratar_recuperacao((select v from teste.var where k = 'item'), 'contatada', 'Conversou sobre bolsa vigente')->>'acao') = 'contatada', 'atendente registra contato') $x$;
  execute $x$ select teste.ok((public.rpc_tratar_recuperacao((select v from teste.var where k = 'item'), 'reativar', 'Aceitou nova conversa')->>'oportunidade')::bigint = (select v from teste.var where k = 'rec_ok'),
  'reativação na mesma coorte reabre a própria oportunidade') $x$;
  execute $x$ select teste.ok((select etapa = 'contato' from public.oportunidades where id = (select v from teste.var where k = 'rec_ok')), 'perdido → contato pela transição oficial') $x$;
  execute $x$ select teste.ok((public.rpc_detalhe((select v from teste.var where k = 'rec_ok'))->'historico') @? '$[*] ? (@.acao == "oportunidade.etapa" && @.dados.para == "contato" && @.dados.de == "perdido")',
  'histórico preserva a perda e registra a reativação') $x$;
  execute $x$ select teste.ok((select count(*) = 1 from public.tarefas where oportunidade_id = (select v from teste.var where k = 'rec_ok') and tipo = 'recuperacao' and status = 'aberta'), 'tarefa de recuperação criada') $x$;
  execute $x$ select teste.erro('select public.rpc_tratar_recuperacao((select v from teste.var where k = ''item''), ''descartada'', ''x x x'')', '22023', 'item reativado não muda mais') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select public.rpc_mover_etapa((select v from teste.var where k = 'rec_ok'), 'perdido', (select versao from public.oportunidades where id = (select v from teste.var where k = 'rec_ok')), 'Adiou para o próximo semestre', 'rec-mov-ok-02') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select public.rpc_selecionar_recuperacao((select v from teste.var where k = 'prot_prox'), array[(select v from teste.var where k = 'rec_ok')]) $x$;
  execute $x$ insert into teste.var values ('item2', (select (i->>'id')::bigint from jsonb_array_elements(public.rpc_recuperacao(1)->'protocolos') p, jsonb_array_elements(p->'itens') i
                                         where (p->>'id')::bigint = (select v from teste.var where k = 'prot_prox'))) $x$;
  execute $x$ insert into teste.var values ('op_nova', (public.rpc_tratar_recuperacao((select v from teste.var where k = 'item2'), 'reativar')->>'oportunidade')::bigint) $x$;
  execute $x$ select teste.ok((select coorte = '2027.2' and recuperada_de = (select v from teste.var where k = 'rec_ok') and etapa = 'contato' and funil_versao_id is not null
                 from public.oportunidades where id = (select v from teste.var where k = 'op_nova')), 'outra coorte: nova oportunidade vinculada à de origem, já no funil') $x$;
  execute $x$ select teste.ok((select etapa = 'perdido' from public.oportunidades where id = (select v from teste.var where k = 'rec_ok')), 'oportunidade de origem permanece perdida (histórico intacto)') $x$;
  execute $x$ select teste.ok((select (p->>'reativadas')::int = 1 and (p->>'atingimento_meta')::numeric = 0.5 and (p->>'custo_por_reativacao_centavos')::bigint = 50000
                 from jsonb_array_elements(public.rpc_recuperacao(1)->'protocolos') p where (p->>'id')::bigint = (select v from teste.var where k = 'prot')),
  'resultado do protocolo: reativadas, atingimento da meta e custo por reativação') $x$;
  execute $x$ select teste.erro('select public.rpc_salvar_protocolo(1, ''{"status":"concluido"}''::jsonb, (select v from teste.var where k = ''prot''))', '22023', 'protocolo só conclui com resultado registrado') $x$;
  execute $x$ insert into teste.var values ('sprint', (public.rpc_salvar_sprint(1, '{"nome":"Sprint de janeiro","objetivo":"Reativar a base perdida de 2026","inicio":"2027-01-04","fim":"2027-01-18"}'::jsonb)->>'id')::bigint) $x$;
  execute $x$ insert into teste.var values ('sitem', (public.rpc_salvar_item_sprint((select v from teste.var where k = 'sprint'), '{"entrega":"Lista revisada da base","responsavel":"Equipe comercial"}'::jsonb)->>'id')::bigint) $x$;
  execute $x$ select teste.erro('select public.rpc_salvar_item_sprint((select v from teste.var where k = ''sprint''), ''{"status":"impedido"}''::jsonb, (select v from teste.var where k = ''sitem''))', '22023', 'impedimento exige descrição') $x$;
  execute $x$ select public.rpc_salvar_item_sprint((select v from teste.var where k = 'sprint'), '{"status":"impedido","impedimento":"Aguardando condição comercial aprovada"}'::jsonb, (select v from teste.var where k = 'sitem')) $x$;
  execute $x$ select teste.erro('select public.rpc_salvar_sprint(1, ''{"status":"encerrada"}''::jsonb, (select v from teste.var where k = ''sprint''))', '22023', 'sprint não encerra sem reavaliação') $x$;
  execute $x$ select teste.ok((select (s->>'impedimentos')::int = 1 from jsonb_array_elements(public.rpc_recuperacao(1)->'sprints') s), 'impedimentos contados na sprint') $x$;
  execute $x$ select public.rpc_salvar_sprint(1, '{"status":"encerrada","reavaliacao":"Base revisada; condição comercial atrasou duas semanas; repetir com aprovação prévia."}'::jsonb, (select v from teste.var where k = 'sprint')) $x$;
  execute $x$ select teste.erro('select public.rpc_salvar_item_sprint((select v from teste.var where k = ''sprint''), ''{"entrega":"Nova","responsavel":"X"}''::jsonb)', '22023', 'sprint encerrada não recebe itens') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false) $x$;
  execute $x$ select teste.ok(jsonb_array_length(public.rpc_recuperacao(2)->'protocolos') = 0, 'recuperação isolada por instituição') $x$;
  execute $x$ select teste.erro('select public.rpc_tratar_recuperacao((select v from teste.var where k = ''item2''), ''descartada'', ''cruzado'')', 'P0002', 'gestor de outra IES não alcança item') $x$;
  execute $x$ select teste.erro('select public.rpc_recuperaveis(1)', 'P0002', 'gestor de outra IES não lista a base perdida da Alfa') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_recuperacao(1)', '42501', 'secretaria sem acesso à recuperação comercial') $x$;
  execute $x$ select teste.erro('select count(*) from public.recuperacoes', '42501', 'recuperações sem leitura direta') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok(true, 'fim da bateria de recuperação') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select count(*) from public.trilhas where ies_id = 1) = 5 and (select count(*) from public.rubricas where ies_id = 1 and status = 'publicada') = 1,
  'conteúdo inicial próprio: 5 trilhas e rubrica publicada') $x$;
  execute $x$ select teste.ok((select count(*) from public.rubrica_criterios c join public.rubricas r on r.id = c.rubrica_id where r.ies_id = 1) = 7, 'rubrica cobre as 7 competências da Bíblia') $x$;
  execute $x$ insert into teste.var values ('rub', (select id from public.rubricas where ies_id = 1 and status = 'publicada')) $x$;
  execute $x$ insert into teste.var values ('crit_escuta', (select c.id from public.rubrica_criterios c where c.rubrica_id = (select v from teste.var where k = 'rub') and c.competencia = 'escuta')) $x$;
  execute $x$ insert into teste.var values ('cenario', (select min(id) from public.cenarios where ies_id = 1)) $x$;
  execute $x$ insert into teste.var values ('mod_escuta', (select m.id from public.modulos m join public.trilhas t on t.id = m.trilha_id where t.ies_id = 1 and m.competencia = 'escuta' limit 1)) $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.ok((select jsonb_array_length(r->'trilhas') = 5 and (r->>'ve_equipe')::boolean = false and r->>'aviso' like '%Nenhuma nota automática%'
                 from (select public.rpc_academia(1) r) x), 'atendente vê trilhas e o aviso de avaliação humana') $x$;
  execute $x$ select teste.ok((public.rpc_concluir_modulo((select v from teste.var where k = 'mod_escuta'))->>'concluido')::boolean, 'atendente conclui módulo') $x$;
  execute $x$ select teste.ok((public.rpc_concluir_modulo((select v from teste.var where k = 'mod_escuta'))->>'concluido')::boolean, 'conclusão repetida é idempotente') $x$;
  execute $x$ select teste.erro('select public.rpc_salvar_avaliacao(1, jsonb_build_object(''avaliado_id'', teste.id(''com_dir_a''), ''rubrica_id'', 1, ''tipo'', ''roleplay'', ''evidencias'', ''tentativa de avaliar colega''))', '42501', 'atendente não avalia') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_avaliacao(1, jsonb_build_object('avaliado_id', teste.id('gestor_a'), 'rubrica_id', (select v from teste.var where k = 'rub'), 'tipo', 'roleplay', 'evidencias', 'autoavaliação indevida'))$q$, '42501', 'ninguém avalia a si mesmo') $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_avaliacao(1, jsonb_build_object('avaliado_id', teste.id('secretaria_a'), 'rubrica_id', (select v from teste.var where k = 'rub'), 'tipo', 'roleplay', 'evidencias', 'secretaria não é alvo'))$q$, '22023', 'avaliado precisa ser atendente comercial') $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_avaliacao(1, jsonb_build_object('avaliado_id', teste.id('comercial_a'), 'rubrica_id', (select v from teste.var where k = 'rub'), 'tipo', 'roleplay', 'evidencias', 'curta'))$q$, '22023', 'evidência obrigatória (10+ caracteres)') $x$;
  execute $x$ insert into teste.var values ('aval', (public.rpc_salvar_avaliacao(1, jsonb_build_object('avaliado_id', teste.id('comercial_a'), 'rubrica_id', (select v from teste.var where k = 'rub'),
  'cenario_id', (select v from teste.var where k = 'cenario'), 'tipo', 'roleplay', 'evidencias', 'Roleplay do cenário EAD: não confirmou o entendimento do objetivo do candidato.',
  'niveis', jsonb_build_object((select v from teste.var where k = 'crit_escuta')::text, 2)))->>'id')::bigint) $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_avaliacao(1, jsonb_build_object('niveis', jsonb_build_object((select v from teste.var where k = 'crit_escuta')::text, 7)), (select v from teste.var where k = 'aval'))$q$, '22023', 'nível fora de 1 a 4 recusado') $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_avaliacao(1, '{}'::jsonb, (select v from teste.var where k = 'aval'), true)$q$, '22023', 'finalizar exige todos os critérios') $x$;
  execute $x$ select teste.ok(public.rpc_salvar_avaliacao(1,
    jsonb_build_object('niveis', (select jsonb_object_agg(c->>'id', case when c->>'competencia' = 'escuta' then 2 else 3 end)
                                    from jsonb_array_elements(public.rpc_academia(1)->'rubricas') r, jsonb_array_elements(r->'criterios') c
                                   where (r->>'id')::bigint = (select v from teste.var where k = 'rub'))),
    (select v from teste.var where k = 'aval'), true)->>'status' = 'finalizada', 'gestor finaliza a avaliação com todos os critérios') $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_avaliacao(1, '{"comentario":"mudança posterior"}'::jsonb, (select v from teste.var where k = 'aval'))$q$, '22023', 'avaliação finalizada é imutável') $x$;
  execute $x$ select teste.ok((select (a->>'consolidado')::numeric between 2 and 3 from jsonb_array_elements(public.rpc_academia(1)->'avaliacoes') a where (a->>'id')::bigint = (select v from teste.var where k = 'aval')),
  'consolidação = média ponderada dos níveis humanos') $x$;
  execute $x$ select teste.ok((select l->>'competencia' = 'escuta' and (l->>'nivel')::int = 2 and jsonb_array_length(l->'recomendados') >= 1 and (l->'recomendados'->0->>'concluido')::boolean
                 from jsonb_array_elements(public.rpc_academia(1)->'lacunas') l where l->>'usuario' = 'comercial_a'), 'MAIM Learning: lacuna em escuta com módulo recomendado (já concluído pela pessoa)') $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_pdi(1, jsonb_build_object('usuario_id', teste.id('comercial_a'), 'competencia', 'escuta', 'objetivo', 'x', 'acoes', 'y', 'prazo', '2027-03-01'))$q$, '22023', 'PDI com objetivo e ações insuficientes recusado') $x$;
  execute $x$ insert into teste.var values ('pdi', (public.rpc_salvar_pdi(1, jsonb_build_object('usuario_id', teste.id('comercial_a'), 'competencia', 'escuta',
  'objetivo', 'Confirmar o entendimento do objetivo do candidato em todo diagnóstico', 'acoes', 'Refazer o módulo de diagnóstico; dois roleplays acompanhados',
  'prazo', '2027-03-01', 'reavaliar_em', '2027-03-15', 'avaliacao_origem', (select v from teste.var where k = 'aval')))->>'id')::bigint) $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.ok((select count(*) = 1 from jsonb_array_elements(public.rpc_academia(1)->'avaliacoes') a where (a->>'avaliado_id')::uuid = teste.id('comercial_a')), 'avaliado vê integralmente a própria avaliação') $x$;
  execute $x$ select teste.ok((public.rpc_salvar_pdi(1, '{"status":"em_andamento"}'::jsonb, (select v from teste.var where k = 'pdi'))->>'id')::bigint = (select v from teste.var where k = 'pdi'), 'atendente atualiza o andamento do próprio PDI') $x$;
  execute $x$ select teste.erro('select public.rpc_salvar_pdi(1, ''{"objetivo":"Outro objetivo definido pelo atendente"}''::jsonb, (select v from teste.var where k = ''pdi''))', '42501', 'atendente não reescreve objetivo do PDI') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('com_dir_a')::text, false) $x$;
  execute $x$ select teste.ok((select jsonb_array_length(r->'avaliacoes') = 0 and jsonb_array_length(r->'pdis') = 0 and jsonb_array_length(r->'lacunas') = 0 from (select public.rpc_academia(1) r) x),
  'colega não vê avaliação, PDI nem lacunas de outro atendente') $x$;
  execute $x$ select teste.erro('select public.rpc_salvar_pdi(1, ''{"status":"concluido"}''::jsonb, (select v from teste.var where k = ''pdi''))', 'P0002', 'colega não altera PDI alheio') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ insert into teste.var values ('rub2', (public.rpc_salvar_rubrica(1, 'nova_versao', (select v from teste.var where k = 'rub'))->>'id')::bigint) $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_rubrica(1, 'salvar', (select v from teste.var where k = 'rub'), '[]'::jsonb)$q$, '22023', 'rubrica publicada é imutável') $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_rubrica(1, 'salvar', (select v from teste.var where k = 'rub2'), '[{"competencia":"escuta","descricao":"Escuta","niveis":["a","b","c"]}]'::jsonb)$q$, '22023', 'critério com menos de 4 níveis recusado') $x$;
  execute $x$ select public.rpc_salvar_rubrica(1, 'publicar', (select v from teste.var where k = 'rub2')) $x$;
  execute $x$ select teste.ok((select a->>'rubrica' like '%v1' from jsonb_array_elements(public.rpc_academia(1)->'avaliacoes') a where (a->>'id')::bigint = (select v from teste.var where k = 'aval')),
  'avaliação antiga mantém a versão de rubrica usada') $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_cenario(1, '{"titulo":"Com dado real","perfil_sintetico":"Candidata com e-mail maria@empresa.com.br quer mudar de curso","objetivo":"Testar"}'::jsonb)$q$, '22023', 'cenário com e-mail recusado (sintético)') $x$;
  execute $x$ select teste.ok((public.rpc_salvar_cenario(1, '{"titulo":"Transferência de outra instituição","perfil_sintetico":"Pessoa fictícia no 3º semestre em outra instituição, insatisfeita com o horário.","objetivo":"Explicar aproveitamento de disciplinas."}'::jsonb)->>'id') is not null, 'cenário sintético criado') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false) $x$;
  execute $x$ select teste.ok((select jsonb_array_length(public.rpc_academia(2)->'avaliacoes') = 0), 'avaliações isoladas por instituição') $x$;
  execute $x$ select teste.erro('select public.rpc_concluir_modulo((select v from teste.var where k = ''mod_escuta''))', 'P0002', 'módulo de outra IES não alcançável') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_academia(1)', '42501', 'coordenação acadêmica fora da Academia comercial') $x$;
  execute $x$ select teste.erro('select count(*) from public.avaliacoes', '42501', 'avaliações sem leitura direta') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select status = 'arquivada' from public.rubricas where id = (select v from teste.var where k = 'rub')), 'versão anterior da rubrica arquivada') $x$;
  execute $x$ select teste.ok((select count(*) = 1 from public.trilhas where ies_id = (select v from teste.var where k = 'ies_nova') and nome = 'Ética e LGPD na captação') or not exists (select 1 from teste.var where k = 'ies_nova'),
  'instituição nova recebe a Academia inicial') $x$;
  execute $x$ select teste.ok(true, 'fim da bateria da academia') $x$;
  execute $x$ reset role $x$;
  execute $x$ insert into public.pessoas(ies_id, nome, email, base_legal, origem) values
  (1, 'Ingressante Um', 'ingressante.um@exemplo.invalid', 'consentimento', 'site'), (1, 'Ingressante Dois', 'ingressante.dois@exemplo.invalid', 'consentimento', 'site') $x$;
  execute $x$ insert into public.oportunidades(ies_id, curso_id, pessoa_id, forma_ingresso, coorte, etapa, val_documental, val_financeira, val_academica, matricula_comercial_em, confirmada_em)
  select 1, 1, p.id, 'vestibular', '2027.1', 'confirmado', true, true, true, now() - interval '101 days', now() - interval '100 days'
    from public.pessoas p where p.email in ('ingressante.um@exemplo.invalid', 'ingressante.dois@exemplo.invalid') $x$;
  execute $x$ insert into teste.var values ('ing1', (select o.id from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id where p.email = 'ingressante.um@exemplo.invalid')) $x$;
  execute $x$ insert into teste.var values ('ing2', (select o.id from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id where p.email = 'ingressante.dois@exemplo.invalid')) $x$;
  execute $x$ select teste.ok((select v from teste.var where k = 'ing1') is not null and (select v from teste.var where k = 'ing2') is not null, 'dois ingressantes efetivos sintéticos') $x$;
  execute $x$ update public.oportunidades set confirmada_em = now() - interval '10 days' where id = (select v from teste.var where k = 'ing2') $x$;
  execute $x$ insert into teste.var values ('nao_ing', (select min(id) from public.oportunidades where ies_id = 1 and etapa in ('novo','contato'))) $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false) $x$;
  execute $x$ select teste.ok((select (m->>'elegiveis')::int >= 1 and m->'permanencia' = 'null'::jsonb and m->>'motivo' like 'Cobertura incompleta%'
                 from jsonb_array_elements(public.rpc_relacionamento(1, '2027.1')->'permanencia') m where m->>'marco' = 'd30'),
  'sem registro de vínculo: permanência N/D com cobertura (não presume evasão)') $x$;
  execute $x$ select teste.ok((public.rpc_relacionamento(1, '2027.1')->'alertas') @? '$[*] ? (@.regra == "retention-v1/registro_pendente")', 'alerta de registro pendente, não de evasão') $x$;
  execute $x$ select teste.erro('select public.rpc_registrar_vinculo((select v from teste.var where k = ''ing2''), ''d30'', ''ativo'', current_date)', '22023', 'marco ainda não alcançado é recusado') $x$;
  execute $x$ select teste.erro('select public.rpc_registrar_vinculo((select v from teste.var where k = ''nao_ing''), ''d30'', ''ativo'', current_date)', '22023', 'vínculo só para ingressante efetivo') $x$;
  execute $x$ select teste.erro('select public.rpc_registrar_vinculo((select v from teste.var where k = ''ing1''), ''d30'', ''trancado'', current_date)', '22023', 'situação diferente de ativo exige a fonte') $x$;
  execute $x$ select teste.erro('select public.rpc_registrar_vinculo((select v from teste.var where k = ''ing1''), ''d30'', ''ativo'', current_date + 1)', '22023', 'data futura recusada') $x$;
  execute $x$ select teste.ok((public.rpc_registrar_vinculo((select v from teste.var where k = 'ing1'), 'd30', 'ativo', current_date)->>'situacao') = 'ativo', 'secretaria registra vínculo ativo no marco de 30 dias') $x$;
  execute $x$ select teste.ok((public.rpc_registrar_vinculo((select v from teste.var where k = 'ing1'), 'd90', 'trancado', current_date, 'Informado pela coordenação do curso')->>'correcao')::boolean = false,
  'trancamento registrado com a fonte') $x$;
  execute $x$ select teste.ok((public.rpc_registrar_vinculo((select v from teste.var where k = 'ing1'), 'd90', 'ativo', current_date, 'Destrancou após contato')->>'correcao')::boolean, 'correção do registro é auditada') $x$;
  execute $x$ select teste.ok((public.rpc_detalhe((select v from teste.var where k = 'ing1'))->'historico') @? '$[*] ? (@.acao == "vinculo.registrar" && @.dados.anterior == "trancado")', 'histórico guarda a situação anterior') $x$;
  execute $x$ select teste.erro('select public.rpc_onboarding_item((select v from teste.var where k = ''ing1''), ''Item inventado'')', '22023', 'item fora do modelo recusado') $x$;
  execute $x$ select teste.ok((public.rpc_onboarding_item((select v from teste.var where k = 'ing1'), 'Calendário acadêmico e horários')->>'concluido')::boolean, 'item de onboarding concluído') $x$;
  execute $x$ select teste.ok((select jsonb_array_length(i->'onboarding') = 1 from jsonb_array_elements(public.rpc_relacionamento(1, '2027.1')->'ingressantes') i
                 where (i->>'id')::bigint = (select v from teste.var where k = 'ing1')), 'progresso de onboarding visível') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_salvar_embaixador((select v from teste.var where k = ''ing1''), now())', '22023', 'embaixador exige regras do programa publicadas') $x$;
  execute $x$ select public.rpc_configurar_relacionamento(1, null, 'Embaixadores indicam conhecidos com autorização deles; não há pagamento em dinheiro; reconhecimento em evento semestral.') $x$;
  execute $x$ select teste.erro('select public.rpc_salvar_embaixador((select v from teste.var where k = ''ing1''), now() + interval ''1 day'')', '22023', 'aceite futuro recusado') $x$;
  execute $x$ insert into teste.var values ('emb', (public.rpc_salvar_embaixador((select v from teste.var where k = 'ing1'), now() - interval '1 day')->>'id')::bigint) $x$;
  execute $x$ select teste.erro('select public.rpc_salvar_embaixador((select v from teste.var where k = ''nao_ing''), now())', '22023', 'embaixador precisa ser ingressante efetivo') $x$;
  execute $x$ select teste.ok((public.rpc_criar_indicacao(1, jsonb_build_object('codigo', 'emb-ana-2027', 'embaixador_id', (select v from teste.var where k = 'emb')))->>'codigo') = 'emb-ana-2027', 'código de indicação do embaixador') $x$;
  execute $x$ select teste.erro('select public.rpc_criar_indicacao(1, ''{"codigo":"emb-ana-2027","indicador_tipo":"aluno","indicador_nome":"Outro"}''::jsonb)', '23505', 'código repetido: conflito') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.ok((select bool_or(x->>'codigo' = 'emb-ana-2027') from jsonb_array_elements(public.rpc_indicacoes(1)) x), 'comercial vê os códigos de indicação') $x$;
  execute $x$ select teste.erro('select public.rpc_relacionamento(1, ''2027.1'')', '42501', 'comercial não vê dados de permanência dos alunos') $x$;
  execute $x$ insert into teste.var values ('op_ind', (public.rpc_criar_oportunidade(1, jsonb_build_object('nome', 'Indicado pela Embaixadora', 'email', 'indicado@exemplo.invalid', 'curso_id', 1,
  'forma_ingresso', 'indicacao', 'coorte', '2027.2', 'base_legal', 'consentimento', 'origem', 'indicação', 'indicacao', 'EMB-ANA-2027'), 'ind-lead-0001')->>'id')::bigint) $x$;
  execute $x$ select teste.erro($q$select public.rpc_criar_oportunidade(1, jsonb_build_object('nome', 'X', 'email', 'x.ind@exemplo.invalid', 'curso_id', 1, 'forma_ingresso', 'indicacao', 'coorte', '2027.2', 'base_legal', 'consentimento', 'origem', 'x', 'indicacao', 'nao-existe'), 'ind-lead-0002')$q$,
  '22023', 'código de indicação inexistente recusado') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.ok((select (e->>'indicacoes')::int = 1 and (e->>'regras_atuais')::boolean from jsonb_array_elements(public.rpc_relacionamento(1, '2027.1')->'embaixadores') e),
  'indicação rastreada até a embaixadora, com aceite das regras vigentes') $x$;
  execute $x$ select public.rpc_configurar_relacionamento(1, null, 'Regras revisadas: reconhecimento anual; sem pagamento em dinheiro.') $x$;
  execute $x$ select teste.ok((select not (e->>'regras_atuais')::boolean from jsonb_array_elements(public.rpc_relacionamento(1, '2027.1')->'embaixadores') e), 'mudança de regras exige novo aceite (sinalizado)') $x$;
  execute $x$ reset role $x$;
  execute $x$ update public.oportunidades set confirmada_em = now() - interval '100 days' where id = (select v from teste.var where k = 'ing2') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false) $x$;
  execute $x$ select public.rpc_registrar_vinculo(o, 'd30', 'ativo', current_date) from unnest(array(select (i->>'id')::bigint from jsonb_array_elements(public.rpc_relacionamento(1, '2027.1')->'ingressantes') i
  where not (i->'vinculos' ? 'd30') and (i->>'dias_desde_ingresso')::int >= 30)) o $x$;
  execute $x$ select teste.ok((select (m->>'permanencia')::numeric = 1 and (m->>'cobertura')::numeric = 1 from jsonb_array_elements(public.rpc_relacionamento(1, '2027.1')->'permanencia') m where m->>'marco' = 'd30'),
  'com cobertura completa, permanência 30 dias calculada') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_registrar_vinculo((select v from teste.var where k = ''ing1''), ''d30'', ''evadido'', current_date, ''cruzado'')', 'P0002', 'gestor de outra IES não alcança o aluno') $x$;
  execute $x$ select teste.ok(jsonb_array_length(public.rpc_relacionamento(2, '2027.1')->'embaixadores') = 0, 'relacionamento isolado por instituição') $x$;
  execute $x$ select teste.erro('select count(*) from public.vinculos', '42501', 'vínculos sem leitura direta') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok(true, 'fim da bateria de relacionamento') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_formulario(1, '{"slug":"x"}'::jsonb)$q$, '42501', 'comercial não cria formulário público') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_formulario(1, '{"slug":"vestibular-2027","titulo":"Vestibular 2027","cursos":[1,3],"coorte":"2027.1","texto_consentimento":"Autorizo a Faculdade Alfa a usar meus dados para contato sobre o processo seletivo, conforme a LGPD."}'::jsonb)$q$,
  '22023', 'formulário com curso de outra IES recusado') $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_formulario(1, '{"slug":"vestibular-2027","titulo":"Vestibular 2027","cursos":[1,2],"coorte":"2027.1","texto_consentimento":"curto"}'::jsonb)$q$,
  '22023', 'termo de consentimento curto recusado') $x$;
  execute $x$ insert into teste.var values ('form', (public.rpc_salvar_formulario(1, '{"slug":"vestibular-2027","titulo":"Vestibular 2027","cursos":[1,2],"coorte":"2027.1","texto_consentimento":"Autorizo a Faculdade Alfa a usar meus dados para contato sobre o processo seletivo, conforme a LGPD."}'::jsonb)->>'id')::bigint) $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_formulario(1, '{"slug":"vestibular-2027","titulo":"Outro","cursos":[1],"coorte":"2027.1","texto_consentimento":"Autorizo a Faculdade Alfa a usar meus dados para contato sobre o processo seletivo."}'::jsonb)$q$,
  '23505', 'endereço repetido: conflito') $x$;
  execute $x$ reset role $x$;
  execute $x$ set role anon $x$;
  execute $x$ select set_config('request.jwt.claim.sub', '', false) $x$;
  execute $x$ select teste.ok((select jsonb_array_length(r->'cursos') = 2 and (r->>'versao_consentimento')::int = 1 and r->>'instituicao' like 'Faculdade Alfa%'
                 from (select public.rpc_publico_formulario('vestibular-2027') r) x), 'anônimo lê o formulário público (cursos e termo)') $x$;
  execute $x$ select teste.erro('select public.rpc_publico_formulario(''nao-existe'')', 'P0002', 'formulário inexistente: 404') $x$;
  execute $x$ select teste.erro('select count(*) from public.formularios', '42501', 'anônimo não lê tabelas') $x$;
  execute $x$ select teste.erro('select public.rpc_formularios(1)', '42501', 'anônimo não executa RPC da equipe') $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_inscrever('vestibular-2027', '{"nome":"Rápido Demais","email":"rapido@exemplo.invalid","curso_id":1,"aceite":true,"versao_consentimento":1,"tempo_ms":500}'::jsonb)$q$,
  '22023', 'envio rápido demais recusado') $x$;
  execute $x$ select teste.ok((public.rpc_publico_inscrever('vestibular-2027', '{"nome":"Robô","email":"robo@exemplo.invalid","curso_id":1,"aceite":true,"versao_consentimento":1,"tempo_ms":9000,"site":"http://spam"}'::jsonb)->>'portal') is null,
  'campo-isca: resposta neutra, nada criado') $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_inscrever('vestibular-2027', '{"nome":"Sem Aceite","email":"sem.aceite@exemplo.invalid","curso_id":1,"aceite":false,"versao_consentimento":1,"tempo_ms":9000}'::jsonb)$q$,
  '22023', 'sem aceite do termo vigente: recusado') $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_inscrever('vestibular-2027', '{"nome":"Curso Errado","email":"curso.errado@exemplo.invalid","curso_id":3,"aceite":true,"versao_consentimento":1,"tempo_ms":9000}'::jsonb)$q$,
  '22023', 'curso fora do formulário recusado') $x$;
  execute $x$ reset role $x$;
  execute $x$ create temp table portal_tok (t text) $x$;
  execute $x$ grant all on portal_tok to anon $x$;
  execute $x$ set role anon $x$;
  execute $x$ insert into portal_tok select public.rpc_publico_inscrever('vestibular-2027', '{"nome":"Candidata Pública","email":"candidata.publica@exemplo.invalid","telefone":"(11) 98888-7777","curso_id":1,"aceite":true,"versao_consentimento":1,"tempo_ms":15000}'::jsonb)->>'portal' $x$;
  execute $x$ select teste.ok((select length(t) = 64 from portal_tok), 'inscrição nova devolve link do portal (token de 64 caracteres)') $x$;
  execute $x$ select teste.ok((public.rpc_publico_inscrever('vestibular-2027', '{"nome":"Outra Pessoa Tentando","email":"candidata.publica@exemplo.invalid","curso_id":2,"aceite":true,"versao_consentimento":1,"tempo_ms":15000}'::jsonb)->>'portal') is null,
  'e-mail já cadastrado: sem link (terceiro não acessa dados alheios), resposta neutra') $x$;
  execute $x$ select teste.ok((select (r->>'nome') = 'Candidata Pública' and jsonb_array_length(r->'inscricoes') = 2 and r->'inscricoes'->1->>'situacao' = 'Inscrição recebida'
                 from (select public.rpc_publico_portal((select t from portal_tok)) r) x), 'portal mostra as inscrições da candidata em linguagem simples') $x$;
  execute $x$ select teste.erro('select public.rpc_publico_portal(repeat(''a'', 64))', 'P0002', 'token inválido: 404 genérico') $x$;
  execute $x$ select teste.ok((public.rpc_publico_portal_optout((select t from portal_tok), 'whatsapp')->>'tarefas_suprimidas')::int >= 1, 'opt-out pelo próprio titular suprime tarefas do canal') $x$;
  execute $x$ select teste.ok((public.rpc_publico_portal_solicitar((select t from portal_tok), 'eliminacao', 'Não quero mais contato')->>'status') = 'aberta', 'titular solicita eliminação') $x$;
  execute $x$ select teste.erro('select public.rpc_publico_portal_solicitar((select t from portal_tok), ''eliminacao'')', '22023', 'solicitação repetida em análise recusada') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select p.base_legal = 'consentimento' and p.consentimento_versao = 1 and p.consentimento_hash is not null and p.origem like 'formulário:%'
                 from public.pessoas p where p.email = 'candidata.publica@exemplo.invalid'), 'consentimento registrado com versão e hash do termo') $x$;
  execute $x$ select teste.ok((select count(*) = 1 from public.acessos_candidato a join public.pessoas p on p.id = a.pessoa_id where p.email = 'candidata.publica@exemplo.invalid'
                 and a.token_hash <> (select t from portal_tok)), 'só o hash do token fica no banco') $x$;
  execute $x$ select teste.ok((select bool_and(o.responsavel_id is not null and o.funil_versao_id is not null) from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id
                 where p.email = 'candidata.publica@exemplo.invalid'), 'lead público distribuído e posicionado no funil') $x$;
  execute $x$ select teste.ok((select count(*) from public.inscricoes_publicas where resultado = 'isca') = 1, 'tentativa de robô registrada sem dados pessoais') $x$;
  execute $x$ insert into public.inscricoes_publicas(formulario_id, ies_id, origem_hash, resultado) select (select v from teste.var where k = 'form'), 1, privado.origem_hash(), 'criada' from generate_series(1, 5) $x$;
  execute $x$ set role anon $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_inscrever('vestibular-2027', '{"nome":"Muitas Tentativas","email":"muitas@exemplo.invalid","curso_id":1,"aceite":true,"versao_consentimento":1,"tempo_ms":9000}'::jsonb)$q$,
  '54000', 'limite por origem: 429') $x$;
  execute $x$ reset role $x$;
  execute $x$ delete from public.inscricoes_publicas where resultado = 'criada' and oportunidade_id is null $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.ok((select (r->>'validade_dias')::int = 90 and length(r->>'token') = 64 from (select public.rpc_gerar_acesso_portal((select min(id) from public.oportunidades where ies_id = 1 and etapa = 'novo' and responsavel_id is not null)) r) x),
  'equipe gera link do portal para envio manual') $x$;
  execute $x$ select public.rpc_salvar_formulario(1, '{"texto_consentimento":"Autorizo a Faculdade Alfa a usar meus dados para contato sobre o processo seletivo e eventos, conforme a LGPD."}'::jsonb, (select v from teste.var where k = 'form')) $x$;
  execute $x$ select teste.ok((select (f->>'versao_consentimento')::int = 2 from jsonb_array_elements(public.rpc_formularios(1)) f where (f->>'id')::bigint = (select v from teste.var where k = 'form')), 'termo alterado gera nova versão') $x$;
  execute $x$ reset role $x$;
  execute $x$ set role anon $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_inscrever('vestibular-2027', '{"nome":"Versão Antiga","email":"versao.antiga@exemplo.invalid","curso_id":1,"aceite":true,"versao_consentimento":1,"tempo_ms":9000}'::jsonb)$q$,
  '22023', 'aceite de versão antiga do termo recusado') $x$;
  execute $x$ reset role $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_tratar_solicitacao((select (s->>''id'')::bigint from jsonb_array_elements(public.rpc_solicitacoes_titular(1)) s limit 1), ''atendida'', ''ok'')', '22023', 'resposta ao titular obrigatória') $x$;
  execute $x$ select teste.ok((public.rpc_tratar_solicitacao((select (s->>'id')::bigint from jsonb_array_elements(public.rpc_solicitacoes_titular(1)) s limit 1), 'atendida', 'Dados anonimizados conforme solicitado.')->>'status') = 'atendida',
  'gestor trata a solicitação do titular') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false) $x$;
  execute $x$ select teste.ok(jsonb_array_length(public.rpc_solicitacoes_titular(2)) = 0, 'solicitações isoladas por instituição') $x$;
  execute $x$ select teste.erro('select public.rpc_salvar_formulario(1, ''{"ativo":false}''::jsonb, (select v from teste.var where k = ''form''))', 'P0002', 'gestor de outra IES não altera o formulário') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok(true, 'fim da bateria de captação pública') $x$;
  execute $x$ reset role $x$;
  execute $x$ grant select on teste.var to anon $x$;
  execute $x$ create temp table doc_tok (t text) $x$;
  execute $x$ grant all on doc_tok to anon, authenticated $x$;
  execute $x$ create temp table doc_b64 (k text primary key, b text) $x$;
  execute $x$ grant all on doc_b64 to anon, authenticated $x$;
  execute $x$ insert into doc_b64 values ('pdf', encode(convert_to('%PDF-1.4 documento sintético de teste', 'UTF8'), 'base64')),
  ('png', encode('\x89504e470d0a1a0a0000000d49484452'::bytea, 'base64')),
  ('exe', encode(convert_to('MZ executável disfarçado', 'UTF8'), 'base64')) $x$;
  execute $x$ select teste.ok((select count(*) >= 7 from public.documentos_exigidos where ies_id = 1), 'checklist inicial próprio criado') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ insert into teste.var values ('doc_op', (select min(id) from public.oportunidades where ies_id = 1 and etapa = 'novo' and forma_ingresso = 'vestibular')) $x$;
  execute $x$ insert into doc_tok select public.rpc_gerar_acesso_portal((select v from teste.var where k = 'doc_op'))->>'token' $x$;
  execute $x$ reset role $x$;
  execute $x$ set role anon $x$;
  execute $x$ select teste.ok((select jsonb_array_length(x->'checklist') >= 3 from jsonb_array_elements(public.rpc_publico_portal_documentos((select t from doc_tok))) x
                 where (x->>'oportunidade_id')::bigint = (select v from teste.var where k = 'doc_op')), 'candidato vê o checklist da inscrição no portal') $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_enviar_documento((select t from doc_tok), (select v from teste.var where k = 'doc_op'), 'identidade', 'rg.exe', (select b from doc_b64 where k = 'exe'))$q$,
  '22023', 'arquivo que não é PDF/JPG/PNG recusado pelo conteúdo') $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_enviar_documento((select t from doc_tok), (select v from teste.var where k = 'doc_op'), 'diploma', 'diploma.pdf', (select b from doc_b64 where k = 'pdf'))$q$,
  '22023', 'documento fora do checklist recusado') $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_enviar_documento((select t from doc_tok), 1, 'identidade', 'rg.pdf', (select b from doc_b64 where k = 'pdf'))$q$,
  'P0002', 'candidato não envia para inscrição de outra pessoa') $x$;
  execute $x$ select teste.ok((public.rpc_publico_enviar_documento((select t from doc_tok), (select v from teste.var where k = 'doc_op'), 'identidade', 'rg.pdf', (select b from doc_b64 where k = 'pdf'))->>'mime') = 'application/pdf',
  'candidato envia PDF pelo portal') $x$;
  execute $x$ select teste.ok((public.rpc_publico_enviar_documento((select t from doc_tok), (select v from teste.var where k = 'doc_op'), 'ensino_medio', 'historico.png', (select b from doc_b64 where k = 'png'))->>'mime') = 'image/png',
  'candidato envia PNG pelo portal') $x$;
  execute $x$ select teste.erro('select count(*) from public.documentos_conteudo', '42501', 'conteúdo sem leitura direta (anon)') $x$;
  execute $x$ reset role $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.ok((select (r->>'pode_revisar')::boolean = false and jsonb_array_length(r->'historico') = 2 from (select public.rpc_documentos((select v from teste.var where k = 'doc_op')) r) x)
  or not exists (select 1 from public.oportunidades where id = (select v from teste.var where k = 'doc_op') and responsavel_id = teste.id('comercial_a')), 'comercial responsável vê a situação, sem revisar') $x$;
  execute $x$ select teste.erro('select public.rpc_baixar_documento((select (h->>''id'')::bigint from jsonb_array_elements(public.rpc_documentos((select v from teste.var where k = ''doc_op''))->''historico'') h limit 1))', 'P0002',
  'comercial não baixa documento') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false) $x$;
  execute $x$ insert into teste.var values ('doc_id', (select (h->>'id')::bigint from jsonb_array_elements(public.rpc_documentos((select v from teste.var where k = 'doc_op'))->'historico') h where h->>'tipo' = 'identidade')) $x$;
  execute $x$ select teste.ok((select convert_from(decode(r->>'base64', 'base64'), 'UTF8') like '%PDF-1.4%' from (select public.rpc_baixar_documento((select v from teste.var where k = 'doc_id')) r) x), 'secretaria baixa o documento') $x$;
  execute $x$ select teste.ok((public.rpc_detalhe((select v from teste.var where k = 'doc_op'))->'historico') @? '$[*] ? (@.acao == "documento.baixar")', 'download auditado') $x$;
  execute $x$ select teste.erro('select public.rpc_revisar_documento((select v from teste.var where k = ''doc_id''), ''recusado'', ''x'')', '22023', 'recusa exige motivo') $x$;
  execute $x$ select teste.ok((public.rpc_revisar_documento((select v from teste.var where k = 'doc_id'), 'recusado', 'Imagem ilegível, envie novamente')->>'status') = 'recusado', 'secretaria recusa com motivo') $x$;
  execute $x$ reset role $x$;
  execute $x$ set role anon $x$;
  execute $x$ select teste.ok((select (i->'documento'->>'motivo_recusa') = 'Imagem ilegível, envie novamente' from jsonb_array_elements(public.rpc_publico_portal_documentos((select t from doc_tok))) x, jsonb_array_elements(x->'checklist') i
                 where (x->>'oportunidade_id')::bigint = (select v from teste.var where k = 'doc_op') and i->>'tipo' = 'identidade'), 'candidato vê o motivo da recusa') $x$;
  execute $x$ select public.rpc_publico_enviar_documento((select t from doc_tok), (select v from teste.var where k = 'doc_op'), 'identidade', 'rg-novo.pdf', (select b from doc_b64 where k = 'pdf')) $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select count(*) = 1 from public.documentos where oportunidade_id = (select v from teste.var where k = 'doc_op') and tipo = 'identidade' and status = 'substituido'), 'versão anterior preservada como substituída') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select public.rpc_configurar_documentos(1, true) $x$;
  execute $x$ reset role $x$;
  execute $x$ insert into teste.var values ('doc_mc', (select o.id from public.oportunidades o where o.ies_id = 1 and o.etapa = 'matricula_comercial' and not o.val_documental limit 1)) $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_validar((select v from teste.var where k = 'doc_mc'), 'documental', 'valida', 'conferido', (select versao from public.oportunidades where id = (select v from teste.var where k = 'doc_mc')))$q$,
  '22023', 'com exigência ligada, validação documental sem checklist aprovado é recusada')
  where (select v from teste.var where k = 'doc_mc') is not null $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select public.rpc_configurar_documentos(1, false) $x$;
  execute $x$ select teste.ok((select (r->>'exigir_documentos')::boolean = false and jsonb_array_length(r->'itens') >= 7 from (select public.rpc_configurar_documentos(1, null, '{"tipo":"foto","descricao":"Foto 3x4 recente","obrigatorio":false}'::jsonb) r) x),
  'gestor configura a exigência e o checklist') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_baixar_documento((select v from teste.var where k = ''doc_id''))', 'P0002', 'gestor de outra IES não baixa o documento') $x$;
  execute $x$ select teste.erro('select count(*) from public.documentos', '42501', 'documentos sem leitura direta') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok(true, 'fim da bateria de documentos') $x$;
  execute $x$ reset role $x$;
  execute $x$ create temp table sel_tok (t text) $x$;
  execute $x$ grant all on sel_tok to anon, authenticated $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_evento(1, '{"titulo":"Open house","tipo":"open_house","inicio":"2027-01-10T10:00:00Z","fim":"2027-01-10T12:00:00Z"}'::jsonb)$q$, '42501', 'comercial não cria evento') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_evento(1, '{"titulo":"Datas invertidas","tipo":"tour","inicio":"2027-01-10T12:00:00Z","fim":"2027-01-10T10:00:00Z"}'::jsonb)$q$, '22023', 'evento com fim antes do início recusado') $x$;
  execute $x$ insert into teste.var values ('evento', (public.rpc_salvar_evento(1, jsonb_build_object('titulo', 'Open house de Direito', 'tipo', 'open_house', 'inicio', now() + interval '1 hour',
  'fim', now() + interval '3 hours', 'local', 'Campus Centro', 'vagas', 2))->>'id')::bigint) $x$;
  execute $x$ select public.rpc_vincular_evento_formulario((select v from teste.var where k = 'form'), (select v from teste.var where k = 'evento')) $x$;
  execute $x$ reset role $x$;
  execute $x$ set role anon $x$;
  execute $x$ select public.rpc_publico_inscrever('vestibular-2027', '{"nome":"Visitante do Open House","email":"visitante.oh@exemplo.invalid","curso_id":1,"aceite":true,"versao_consentimento":2,"tempo_ms":12000}'::jsonb) $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select count(*) = 1 from public.inscricoes_evento i join public.pessoas p on p.id = i.pessoa_id where p.email = 'visitante.oh@exemplo.invalid'
                 and i.evento_id = (select v from teste.var where k = 'evento')), 'formulário público vinculado inscreve no evento') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select public.rpc_inscrever_evento((select v from teste.var where k = 'evento'), (select min(id) from public.oportunidades where ies_id = 1 and etapa = 'contato')) $x$;
  execute $x$ select teste.erro($q$select public.rpc_inscrever_evento((select v from teste.var where k = 'evento'), (select max(id) from public.oportunidades where ies_id = 1 and etapa = 'novo'))$q$, '22023', 'evento sem vagas recusa nova inscrição') $x$;
  execute $x$ insert into teste.var values ('insc_ev', (select (i->>'id')::bigint from jsonb_array_elements(public.rpc_eventos(1)) e, jsonb_array_elements(e->'inscricoes') i
                                           where (e->>'id')::bigint = (select v from teste.var where k = 'evento') limit 1)) $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false) $x$;
  execute $x$ select teste.ok((public.rpc_checkin((select v from teste.var where k = 'insc_ev'), 'presente')->>'status') = 'presente', 'check-in de presença registrado') $x$;
  execute $x$ select teste.ok((select (e->>'presentes')::int = 1 and (e->>'inscritos')::int = 2 from jsonb_array_elements(public.rpc_eventos(1)) e where (e->>'id')::bigint = (select v from teste.var where k = 'evento')),
  'evento mostra inscritos e presentes') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_checkin((select v from teste.var where k = ''insc_ev''), ''ausente'')', 'P0002', 'gestor de outra IES não registra presença') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false) $x$;
  execute $x$ insert into teste.var values ('proc', (public.rpc_salvar_processo(1, jsonb_build_object('coorte', '2027.1', 'nome', 'Vestibular agendado 2027.1', 'tipo', 'prova_agendada',
  'inscricoes_ate', current_date + 30, 'nota_minima', 500, 'tema_redacao', 'O papel da educação superior no desenvolvimento regional',
  'agenda', jsonb_build_object('inicio', now() + interval '1 day', 'local', 'Campus Centro, sala 12', 'vagas', 50)))->>'id')::bigint) $x$;
  execute $x$ insert into teste.var values ('proc_enem', (public.rpc_salvar_processo(1, jsonb_build_object('coorte', '2027.1', 'nome', 'Seleção ENEM 2027.1', 'tipo', 'enem',
  'inscricoes_ate', current_date + 30, 'nota_minima', 550))->>'id')::bigint) $x$;
  execute $x$ insert into teste.var values ('agenda', (select (a->>'id')::bigint from jsonb_array_elements(public.rpc_seletivo(1)->'processos') p, jsonb_array_elements(p->'agendas') a
                                          where (p->>'id')::bigint = (select v from teste.var where k = 'proc'))) $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ reset role $x$;
  execute $x$ insert into teste.var values ('sel_op', (select o.id from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id where p.email = 'visitante.oh@exemplo.invalid')) $x$;
  execute $x$ update public.oportunidades set etapa = 'contato' where id = (select v from teste.var where k = 'sel_op') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ insert into sel_tok select public.rpc_gerar_acesso_portal((select v from teste.var where k = 'sel_op'))->>'token' $x$;
  execute $x$ reset role $x$;
  execute $x$ set role anon $x$;
  execute $x$ select teste.ok((select jsonb_array_length(r->'processos_abertos') = 2 and jsonb_array_length(r->'eventos') = 1 from (select public.rpc_publico_portal_seletivo((select t from sel_tok)) r) x),
  'candidato vê processos abertos e o evento em que se inscreveu') $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_candidatar((select t from sel_tok), (select v from teste.var where k = 'proc'), (select v from teste.var where k = 'sel_op'))$q$, '22023', 'prova agendada exige escolher data') $x$;
  execute $x$ select teste.ok((public.rpc_publico_candidatar((select t from sel_tok), (select v from teste.var where k = 'proc'), (select v from teste.var where k = 'sel_op'), (select v from teste.var where k = 'agenda'))->>'id') is not null,
  'candidato se inscreve no vestibular agendado pelo portal') $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_candidatar((select t from sel_tok), (select v from teste.var where k = 'proc'), (select v from teste.var where k = 'sel_op'), (select v from teste.var where k = 'agenda'))$q$, '22023', 'inscrição repetida recusada') $x$;
  execute $x$ select teste.ok((select (r->'candidaturas'->0->'tema_redacao') = 'null'::jsonb from (select public.rpc_publico_portal_seletivo((select t from sel_tok)) r) x), 'tema da redação só aparece no horário da prova') $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_enviar_redacao((select t from sel_tok), (select (c->>'id')::bigint from jsonb_array_elements(public.rpc_publico_portal_seletivo((select t from sel_tok))->'candidaturas') c limit 1), repeat('texto ', 60))$q$,
  '22023', 'redação fora do horário recusada') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select etapa = 'inscrito' from public.oportunidades where id = (select v from teste.var where k = 'sel_op')), 'inscrição no processo move contato → inscrito (auditado)') $x$;
  execute $x$ update public.agendas_prova set inicio = now() - interval '10 minutes' where id = (select v from teste.var where k = 'agenda') $x$;
  execute $x$ insert into teste.var values ('cand', (select id from public.candidaturas where oportunidade_id = (select v from teste.var where k = 'sel_op'))) $x$;
  execute $x$ set role anon $x$;
  execute $x$ select teste.ok(length((public.rpc_publico_portal_seletivo((select t from sel_tok))->'candidaturas'->0->>'tema_redacao')) > 10, 'no horário da prova o tema aparece') $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_enviar_redacao((select t from sel_tok), (select v from teste.var where k = 'cand'), 'curta')$q$, '22023', 'redação curta recusada') $x$;
  execute $x$ select teste.ok((public.rpc_publico_enviar_redacao((select t from sel_tok), (select v from teste.var where k = 'cand'), repeat('A educação superior amplia oportunidades. ', 10))->>'enviada')::boolean, 'redação enviada no horário') $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_enviar_redacao((select t from sel_tok), (select v from teste.var where k = 'cand'), repeat('Outra versão do texto. ', 20))$q$, '22023', 'envio único da redação') $x$;
  execute $x$ reset role $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_avaliar_candidatura((select v from teste.var where k = 'cand'), '{"redacao_nota":720}'::jsonb)$q$, '22023', 'correção exige parecer') $x$;
  execute $x$ select public.rpc_avaliar_candidatura((select v from teste.var where k = 'cand'), '{"redacao_nota":720,"redacao_parecer":"Texto coeso, tese clara, repertório adequado."}'::jsonb) $x$;
  execute $x$ select teste.ok((select c->>'sugestao' = 'aprovado' and c->>'resultado' = 'pendente' from jsonb_array_elements(public.rpc_seletivo(1)->'processos') p, jsonb_array_elements(p->'candidaturas') c
                 where (c->>'id')::bigint = (select v from teste.var where k = 'cand')), 'sistema só sugere; resultado continua pendente até decisão humana') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_divulgar_resultado((select v from teste.var where k = ''proc''))', '22023', 'divulgação bloqueada com candidatura pendente') $x$;
  execute $x$ select teste.erro($q$select public.rpc_avaliar_candidatura((select v from teste.var where k = 'cand'), '{"resultado":"aprovado"}'::jsonb)$q$, '22023', 'resultado exige justificativa') $x$;
  execute $x$ select public.rpc_avaliar_candidatura((select v from teste.var where k = 'cand'), '{"resultado":"aprovado","justificativa":"Redação 720, acima da nota mínima 500."}'::jsonb) $x$;
  execute $x$ reset role $x$;
  execute $x$ set role anon $x$;
  execute $x$ select teste.ok((public.rpc_publico_portal_seletivo((select t from sel_tok))->'candidaturas'->0->'resultado') = 'null'::jsonb, 'candidato não vê o resultado antes da divulgação') $x$;
  execute $x$ reset role $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false) $x$;
  execute $x$ select teste.ok((public.rpc_divulgar_resultado((select v from teste.var where k = 'proc'))->>'divulgado')::boolean, 'secretaria divulga o resultado') $x$;
  execute $x$ select teste.erro($q$select public.rpc_avaliar_candidatura((select v from teste.var where k = 'cand'), '{"resultado":"reprovado","justificativa":"tentativa de mudar após divulgar"}'::jsonb)$q$, '22023', 'resultado divulgado não muda') $x$;
  execute $x$ reset role $x$;
  execute $x$ set role anon $x$;
  execute $x$ select teste.ok((public.rpc_publico_portal_seletivo((select t from sel_tok))->'candidaturas'->0->>'resultado') = 'aprovado', 'candidato vê o resultado após a divulgação') $x$;
  execute $x$ select public.rpc_publico_candidatar((select t from sel_tok), (select v from teste.var where k = 'proc_enem'), (select v from teste.var where k = 'sel_op'), null, 610) $x$;
  execute $x$ reset role $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false) $x$;
  execute $x$ insert into teste.var values ('cand_enem', (select (c->>'id')::bigint from jsonb_array_elements(public.rpc_seletivo(1)->'processos') p, jsonb_array_elements(p->'candidaturas') c
                                             where (p->>'id')::bigint = (select v from teste.var where k = 'proc_enem'))) $x$;
  execute $x$ select teste.erro($q$select public.rpc_avaliar_candidatura((select v from teste.var where k = 'cand_enem'), '{"resultado":"aprovado","justificativa":"Nota declarada 610"}'::jsonb)$q$, '22023', 'ENEM: aprovar exige nota conferida') $x$;
  execute $x$ select public.rpc_avaliar_candidatura((select v from teste.var where k = 'cand_enem'), '{"conferir_enem":true,"resultado":"aprovado","justificativa":"Nota 610 conferida no boletim oficial."}'::jsonb) $x$;
  execute $x$ select teste.ok((select (c->>'enem_conferido')::boolean and c->>'resultado' = 'aprovado' from jsonb_array_elements(public.rpc_seletivo(1)->'processos') p, jsonb_array_elements(p->'candidaturas') c
                 where (c->>'id')::bigint = (select v from teste.var where k = 'cand_enem')), 'ENEM conferido por pessoa e aprovado com justificativa') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_divulgar_resultado((select v from teste.var where k = ''proc_enem''))', '42501', 'comercial não divulga resultado') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_avaliar_candidatura((select v from teste.var where k = ''cand_enem''), ''{"nota_objetiva":1}''::jsonb)', 'P0002', 'gestor de outra IES não avalia') $x$;
  execute $x$ select teste.erro('select count(*) from public.candidaturas', '42501', 'candidaturas sem leitura direta') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok(true, 'fim da bateria de eventos e processo seletivo') $x$;
  execute $x$ reset role $x$;
  execute $x$ create temp table mat_tok (t text) $x$;
  execute $x$ grant all on mat_tok to anon, authenticated $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_salvar_contrato(1, ''curto demais'')', '22023', 'contrato curto recusado') $x$;
  execute $x$ select teste.ok((public.rpc_salvar_contrato(1, repeat('Cláusula de prestação de serviços educacionais conforme regimento da instituição. ', 3))->>'versao')::int = 1, 'contrato v1 publicado') $x$;
  execute $x$ select teste.ok((select (r->'versoes'->0->>'ativo')::boolean and r->>'aviso' like '[Não verificado]%' from (select public.rpc_contratos(1) r) x), 'contratos com aviso de validação jurídica') $x$;
  execute $x$ reset role $x$;
  execute $x$ insert into teste.var values ('mat_op', (select o.id from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id where p.email = 'visitante.oh@exemplo.invalid')) $x$;
  execute $x$ update public.oportunidades set etapa = 'pre_matricula' where id = (select v from teste.var where k = 'mat_op') $x$;
  execute $x$ insert into public.propostas(ies_id, oportunidade_id, desconto_pct, mensalidade_centavos, valor_final_centavos, validade, status, criado_por)
  select o.ies_id, o.id, 10, 129000, 116100, now() + interval '5 days', 'aprovada', teste.id('comercial_a') from public.oportunidades o where o.id = (select v from teste.var where k = 'mat_op') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ insert into mat_tok select public.rpc_gerar_acesso_portal((select v from teste.var where k = 'mat_op'))->>'token' $x$;
  execute $x$ reset role $x$;
  execute $x$ set role anon $x$;
  execute $x$ select teste.ok((select (m->'proposta'->>'valor_final_centavos')::int = 116100 and (m->'contrato'->>'versao')::int = 1 from jsonb_array_elements(public.rpc_publico_portal_matricula((select t from mat_tok))) m),
  'portal mostra proposta aprovada e contrato vigente') $x$;
  execute $x$ reset role $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ insert into teste.var values ('modelo', (public.rpc_salvar_modelo_mensagem(1, '{"nome":"Boas-vindas","canal":"email","gatilho":"etapa_novo","assunto":"Recebemos seu interesse","corpo":"Olá, {{nome}}! Recebemos seu interesse em {{curso}} na {{instituicao}}."}'::jsonb)->>'id')::bigint) $x$;
  execute $x$ select public.rpc_salvar_modelo_mensagem(1, '{"nome":"Contato manual","canal":"whatsapp","gatilho":"manual","corpo":"Oi, {{nome}}, aqui é da equipe de {{curso}}."}'::jsonb) $x$;
  execute $x$ select teste.ok((select (r->>'simuladas')::int > 0 and (r->>'enviadas')::int = 0 and r->>'modo' = 'simulação' from (select public.rpc_executar_regua(1) r) x), 'régua gera mensagens só em simulação (nada enviado)') $x$;
  execute $x$ select teste.ok((select (r->>'simuladas')::int = 0 from (select public.rpc_executar_regua(1) r) x), 'régua não duplica mensagens') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select count(*) = 0 from public.mensagens where status = 'enviada'), 'nenhuma mensagem enviada') $x$;
  execute $x$ select teste.ok((select bool_and(corpo not like '%{{%') from public.mensagens), 'variáveis substituídas no texto') $x$;
  execute $x$ select teste.ok((select count(*) >= 1 from public.mensagens g join public.oportunidades o on o.id = g.oportunidade_id join public.pessoas p on p.id = o.pessoa_id
                 where g.status = 'bloqueada' and (p.optout_email or p.email is null)) or not exists (select 1 from public.pessoas p join public.oportunidades o on o.pessoa_id = p.id
                 where o.etapa = 'novo' and o.ies_id = 1 and (p.optout_email or p.email is null)), 'opt-out bloqueia a mensagem na régua') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_executar_regua(1)', '42501', 'comercial não executa a régua') $x$;
  execute $x$ reset role $x$;
  execute $x$ insert into teste.var values ('msg_op', (select min(o.id) from public.oportunidades o where o.responsavel_id = teste.id('comercial_a') and o.etapa in ('novo','contato'))) $x$;
  execute $x$ update public.pessoas set telefone = coalesce(telefone, '11977776666'), optout_whatsapp = false
 where id = (select pessoa_id from public.oportunidades where id = (select v from teste.var where k = 'msg_op')) $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.ok((public.rpc_mensagem_manual((select v from teste.var where k = 'msg_op'),
                 (select (m->>'id')::bigint from jsonb_array_elements(public.rpc_comunicacao(1)->'modelos') m where m->>'nome' = 'Contato manual'))->>'texto') like 'Oi, %',
  'atendente gera texto para envio manual') $x$;
  execute $x$ select teste.ok((select (m->'abertura') = 'null'::jsonb from jsonb_array_elements(public.rpc_comunicacao(1)->'modelos') m limit 1), 'abertura e clique N/D sem provedor') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.ok((select jsonb_array_length(r->'itens') = 10 and bool_and(i->>'status' = 'desligada') from (select public.rpc_integracoes(1) r) x, jsonb_array_elements(r->'itens') i group by r),
  'dez integrações registradas, todas desligadas') $x$;
  execute $x$ select teste.erro('select public.rpc_integracoes(1, ''whatsapp'', ''x'')', '22023', 'pedido de ativação exige descrição') $x$;
  execute $x$ select teste.ok((select i->>'status' = 'pedido_registrado' from jsonb_array_elements(public.rpc_integracoes(1, 'whatsapp', 'WhatsApp Business oficial para confirmações de inscrição')->'itens') i where i->>'tipo' = 'whatsapp'),
  'pedido registrado não ativa nada') $x$;
  execute $x$ select teste.ok((select (r->>'importadas')::int = 1 and jsonb_array_length(r->'rejeitadas') = 1 from (select public.rpc_importar_custos(1,
  '[{"campanha":"verao-2027","data":"2026-11-20","valor_centavos":45000,"descricao":"Meta Ads semana 47"},{"campanha":"nao-existe","data":"2026-11-20","valor_centavos":1}]'::jsonb) r) x),
  'importação de custos com relatório por linha') $x$;
  execute $x$ select teste.ok((select (r->>'repetidas')::int = 1 and (r->>'importadas')::int = 0 from (select public.rpc_importar_custos(1, '[{"campanha":"verao-2027","data":"2026-11-20","valor_centavos":45000,"descricao":"Meta Ads semana 47"}]'::jsonb) r) x),
  'reimportar a mesma linha não duplica custo') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false) $x$;
  execute $x$ select teste.ok((select (r->>'importadas')::int = 1 and jsonb_array_length(r->'rejeitadas') = 1 from (select public.rpc_importar_vinculos(1, jsonb_build_array(
    jsonb_build_object('oportunidade_id', (select v from teste.var where k = 'ing2'), 'marco', 'd90', 'situacao', 'ativo', 'data', current_date),
    jsonb_build_object('email', 'ninguem@exemplo.invalid', 'marco', 'd30', 'situacao', 'ativo', 'data', current_date))) r) x),
  'importação de vínculos acadêmicos com relatório') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select fonte = 'sistema_academico' from public.vinculos where oportunidade_id = (select v from teste.var where k = 'ing2') and marco = 'd90'), 'vínculo importado marcado com a fonte') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false) $x$;
  execute $x$ select teste.erro('select public.rpc_importar_custos(1, ''[{"campanha":"verao-2027","data":"2026-11-20","valor_centavos":1}]''::jsonb)', 'P0002', 'gestor de outra IES não importa custos na Alfa') $x$;
  execute $x$ select teste.erro('select count(*) from public.mensagens', '42501', 'mensagens sem leitura direta') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok(true, 'fim da bateria de matrícula online, comunicação e integrações') $x$;
  execute $x$ reset role $x$;
  execute $x$ create temp table ac (chave text primary key, txt text) $x$;
  execute $x$ grant all on ac to anon, authenticated $x$;
  execute $x$ insert into ac values ('prop', (select id::text from public.propostas where oportunidade_id = (select v from teste.var where k = 'mat_op') and status = 'aprovada' order by id desc limit 1)) $x$;
  execute $x$ insert into ac values ('tok', (select t from mat_tok)) $x$;
  execute $x$ create function pg_temp.dados(extra jsonb default '{}'::jsonb) returns jsonb language sql as $$
  select jsonb_build_object('contrato_versao', 2, 'proposta_id', (select txt::bigint from ac where chave = 'prop'),
    'li_contrato', true, 'concordo_condicoes', true, 'ciente_arrependimento', true,
    'nome', 'Visitante do Open House', 'cpf', '529.982.247-25', 'nascimento', '2000-05-10',
    'codigo', (select txt from ac where chave = 'cod')) || extra $$ $x$;
  execute $x$ create function pg_temp.aceitar(d jsonb) returns jsonb language sql as $$
  select public.rpc_publico_aceitar_matricula((select txt from ac where chave = 'tok'), (select v from teste.var where k = 'mat_op'), d) $$ $x$;
  execute $x$ grant execute on function pg_temp.dados(jsonb), pg_temp.aceitar(jsonb) to anon, authenticated $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_contrato(1, repeat('Cláusula de prestação de serviços educacionais conforme regimento. ', 3) || '**cláusula sem fechamento')$q$,
  '22023', 'destaque aberto (** sem fechamento) recusado') $x$;
  execute $x$ select teste.ok((public.rpc_salvar_contrato(1, repeat('Cláusula de prestação de serviços educacionais conforme regimento. ', 3)
  || E'\n**Cláusula limitativa: multa de 10% na desistência após o início das aulas.**')->>'versao')::int = 2, 'contrato v2 com cláusula em destaque publicado') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select (dados->>'destaques')::int = 1 from public.auditoria where acao = 'contrato.publicar' order by id desc limit 1), 'auditoria registra quantas cláusulas estão em destaque') $x$;
  execute $x$ set role anon $x$;
  execute $x$ select teste.ok((select m->>'procedimento' = 'aceite-v2' and m->'confirmacao'->>'destino' = 'v***@exemplo.invalid' and (m->'contrato'->>'versao')::int = 2
                   and (m->>'prazo_arrependimento_dias')::int = 7
                 from jsonb_array_elements(public.rpc_publico_portal_matricula((select txt from ac where chave = 'tok'))) m),
  'portal informa procedimento reforçado, contato mascarado, contrato v2 e prazo de arrependimento') $x$;
  execute $x$ select teste.erro('select pg_temp.aceitar(pg_temp.dados())', '22023', 'aceite sem código solicitado recusado') $x$;
  execute $x$ insert into ac select 'cod', r->>'codigo_simulacao' from (select public.rpc_publico_codigo_aceite((select txt from ac where chave = 'tok'), (select v from teste.var where k = 'mat_op')) r) x $x$;
  execute $x$ select teste.ok((select txt ~ '^\d{6}$' from ac where chave = 'cod'), 'código de 6 dígitos emitido (simulação: exibido no portal)') $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_codigo_aceite((select txt from ac where chave = 'tok'), (select v from teste.var where k = 'mat_op'))$q$, '54000', 'novo código antes de 1 minuto: 429') $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_codigo_aceite(repeat('a', 64), (select v from teste.var where k = 'mat_op'))$q$, 'P0002', 'código com link inválido: 404') $x$;
  execute $x$ select teste.erro($q$select pg_temp.aceitar(pg_temp.dados('{"ciente_arrependimento":false}'))$q$, '22023', 'sem as três declarações: recusado') $x$;
  execute $x$ select teste.erro($q$select pg_temp.aceitar(pg_temp.dados('{"cpf":"111.111.111-11"}'))$q$, '22023', 'CPF inválido recusado') $x$;
  execute $x$ select teste.erro($q$select pg_temp.aceitar(pg_temp.dados('{"cpf":"529.982.247-24"}'))$q$, '22023', 'CPF com dígito verificador errado recusado') $x$;
  execute $x$ select teste.erro($q$select pg_temp.aceitar(pg_temp.dados('{"proposta_id":0}'))$q$, '22023', 'condições da proposta divergentes recusadas') $x$;
  execute $x$ select teste.erro($q$select pg_temp.aceitar(pg_temp.dados('{"contrato_versao":1}'))$q$, '22023', 'versão antiga do contrato recusada') $x$;
  execute $x$ select teste.erro($q$select pg_temp.aceitar(pg_temp.dados('{"nome":"Outro Nome Qualquer"}'))$q$, '22023', 'nome divergente do cadastro recusado') $x$;
  execute $x$ select teste.erro($q$select pg_temp.aceitar(pg_temp.dados('{"nascimento":"2015-01-01"}'))$q$, '22023', 'idade abaixo de 14 anos recusada') $x$;
  execute $x$ select teste.ok((select (r->>'aceito')::boolean = false and (r->>'tentativas_restantes')::int = 4 from (select pg_temp.aceitar(pg_temp.dados('{"codigo":"x"}')) r) x),
  'código incorreto: recusado sem lançar erro, com tentativas restantes') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select tentativas = 1 from public.codigos_aceite where oportunidade_id = (select v from teste.var where k = 'mat_op')), 'tentativa errada fica registrada') $x$;
  execute $x$ set role anon $x$;
  execute $x$ select teste.ok((select (r->>'aceito')::boolean and r->>'evidencia_hash' ~ '^[0-9a-f]{64}$' from (select pg_temp.aceitar(pg_temp.dados('{"nome":"  visitante  do open house "}')) r) x),
  'aceite reforçado concluído com hash da evidência') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select a.menor = false and a.cpf_candidato = '52998224725' and a.responsavel_nome is null and a.confirmacao_modo = 'simulacao'
                   and a.evidencia_hash = encode(sha256(convert_to(a.evidencia::text, 'UTF8')), 'hex')
                   and a.evidencia->'condicoes'->>'valor_final_centavos' = '116100' and a.evidencia->'contrato'->>'sha256' = a.contrato_hash
                   and a.evidencia->'declaracoes'->>'ciente_do_prazo_de_arrependimento' = 'true'
                   and a.arrependimento_ate = a.aceito_em + interval '7 days'
                 from public.aceites_matricula a where a.oportunidade_id = (select v from teste.var where k = 'mat_op')),
  'evidência única: contrato, condições, identificação, declarações; SHA-256 confere') $x$;
  execute $x$ select teste.ok((select o.etapa = 'matricula_comercial' from public.oportunidades o where o.id = (select v from teste.var where k = 'mat_op')), 'aceite leva à matrícula comercial') $x$;
  execute $x$ select teste.ok((select count(*) = 0 from public.codigos_aceite where oportunidade_id = (select v from teste.var where k = 'mat_op')), 'código usado é descartado') $x$;
  execute $x$ select teste.ok((select count(*) = 1 and bool_and(corpo like '%******%' and corpo not like '%' || (select txt from ac where chave = 'cod') || '%' and status = 'simulada')
                 from public.mensagens where oportunidade_id = (select v from teste.var where k = 'mat_op') and modelo_id is null and corpo like '%código de confirmação%'),
  'mensagem do código registrada em simulação, sem o código em claro') $x$;
  execute $x$ select teste.ok((select dados->>'evidencia_sha256' ~ '^[0-9a-f]{64}$' from public.auditoria where acao = 'matricula.aceite' order by id desc limit 1), 'auditoria do aceite guarda o hash da evidência') $x$;
  execute $x$ set role anon $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_codigo_aceite((select txt from ac where chave = 'tok'), (select v from teste.var where k = 'mat_op'))$q$, '22023', 'após o aceite não há novo código') $x$;
  execute $x$ select teste.ok((select (r->>'evidencia_integra')::boolean and (r->>'contrato_integro')::boolean and r->>'contrato_texto' like '%**Cláusula limitativa%'
                   and encode(sha256(convert_to(r->>'evidencia_texto', 'UTF8')), 'hex') = r->>'evidencia_hash'
                 from (select public.rpc_publico_comprovante_aceite((select txt from ac where chave = 'tok'), (select v from teste.var where k = 'mat_op')) r) x),
  'comprovante do portal: texto integral do contrato e evidência íntegra (hash recalculável)') $x$;
  execute $x$ reset role $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.ok((public.rpc_comprovante_aceite((select v from teste.var where k = 'mat_op'))->>'evidencia_integra')::boolean, 'equipe da IES vê o comprovante') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_comprovante_aceite((select v from teste.var where k = 'mat_op'))$q$, 'P0002', 'outra IES não vê o comprovante') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select count(*) = 1 from public.auditoria where acao = 'matricula.comprovante_ver'), 'consulta da equipe ao comprovante é auditada') $x$;
  execute $x$ update public.aceites_matricula set evidencia = jsonb_set(evidencia, '{condicoes,valor_final_centavos}', '99') where oportunidade_id = (select v from teste.var where k = 'mat_op') $x$;
  execute $x$ set role anon $x$;
  execute $x$ select teste.ok((public.rpc_publico_comprovante_aceite((select txt from ac where chave = 'tok'), (select v from teste.var where k = 'mat_op'))->>'evidencia_integra')::boolean = false,
  'evidência adulterada é denunciada no comprovante') $x$;
  execute $x$ reset role $x$;
  execute $x$ update public.aceites_matricula set evidencia = jsonb_set(evidencia, '{condicoes,valor_final_centavos}', '116100') where oportunidade_id = (select v from teste.var where k = 'mat_op') $x$;
  execute $x$ set role anon $x$;
  execute $x$ select teste.ok((select (m->'aceite'->>'pode_desistir')::boolean from jsonb_array_elements(public.rpc_publico_portal_matricula((select txt from ac where chave = 'tok'))) m), 'portal oferece desistência no prazo') $x$;
  execute $x$ select teste.ok((public.rpc_publico_desistir_matricula((select txt from ac where chave = 'tok'), (select v from teste.var where k = 'mat_op'), 'Mudei de cidade')->>'cancelado')::boolean,
  'desistência no prazo de 7 dias pelo portal') $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_desistir_matricula((select txt from ac where chave = 'tok'), (select v from teste.var where k = 'mat_op'))$q$, '22023', 'desistência repetida recusada') $x$;
  execute $x$ select teste.ok((select m->'aceite'->>'desistencia_em' is not null and not (m->'aceite'->>'pode_desistir')::boolean and m->>'etapa' = 'cancelado'
                 from jsonb_array_elements(public.rpc_publico_portal_matricula((select txt from ac where chave = 'tok'))) m), 'portal mostra a desistência registrada') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select o.etapa = 'cancelado' and o.motivo_cancelamento like 'Arrependimento%Mudei de cidade' and a.desistencia_motivo = 'Mudei de cidade'
                 from public.oportunidades o join public.aceites_matricula a on a.oportunidade_id = o.id where o.id = (select v from teste.var where k = 'mat_op')),
  'matrícula cancelada com motivo e desistência no aceite') $x$;
  execute $x$ select teste.ok((select count(*) = 1 from public.auditoria where acao = 'matricula.arrependimento'), 'arrependimento auditado') $x$;
  execute $x$ insert into teste.var values ('men_op', (select o.id from public.oportunidades o where o.ies_id = 1 and o.etapa in ('novo','contato','inscrito')
  and o.id <> (select v from teste.var where k = 'mat_op') order by o.id limit 1)) $x$;
  execute $x$ update public.oportunidades set etapa = 'pre_matricula' where id = (select v from teste.var where k = 'men_op') $x$;
  execute $x$ insert into public.propostas(ies_id, oportunidade_id, desconto_pct, mensalidade_centavos, valor_final_centavos, validade, status, criado_por)
  select o.ies_id, o.id, 0, 99000, 99000, now() + interval '5 days', 'aprovada', teste.id('comercial_a') from public.oportunidades o where o.id = (select v from teste.var where k = 'men_op') $x$;
  execute $x$ insert into ac select 'men_nome', p.nome from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id where o.id = (select v from teste.var where k = 'men_op') $x$;
  execute $x$ insert into ac select 'men_prop', id::text from public.propostas where oportunidade_id = (select v from teste.var where k = 'men_op') and status = 'aprovada' $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ insert into ac select 'men_tok', public.rpc_gerar_acesso_portal((select v from teste.var where k = 'men_op'))->>'token' $x$;
  execute $x$ reset role $x$;
  execute $x$ create function pg_temp.dmen(extra jsonb default '{}'::jsonb) returns jsonb language sql as $$
  select jsonb_build_object('contrato_versao', 2, 'proposta_id', (select txt::bigint from ac where chave = 'men_prop'),
    'li_contrato', true, 'concordo_condicoes', true, 'ciente_arrependimento', true,
    'nome', (select txt from ac where chave = 'men_nome'), 'cpf', '529.982.247-25', 'nascimento', (current_date - interval '16 years')::date::text,
    'codigo', (select txt from ac where chave = 'men_cod'),
    'responsavel', jsonb_build_object('nome', 'Maria Responsável Sintética', 'cpf', '111.444.777-35', 'nascimento', '1975-03-02', 'vinculo', 'mae', 'declaro', true)) || extra $$ $x$;
  execute $x$ create function pg_temp.aceitar_men(d jsonb) returns jsonb language sql as $$
  select public.rpc_publico_aceitar_matricula((select txt from ac where chave = 'men_tok'), (select v from teste.var where k = 'men_op'), d) $$ $x$;
  execute $x$ grant execute on function pg_temp.dmen(jsonb), pg_temp.aceitar_men(jsonb) to anon $x$;
  execute $x$ set role anon $x$;
  execute $x$ insert into ac select 'men_cod', public.rpc_publico_codigo_aceite((select txt from ac where chave = 'men_tok'), (select v from teste.var where k = 'men_op'))->>'codigo_simulacao' $x$;
  execute $x$ select teste.erro($q$select pg_temp.aceitar_men(pg_temp.dmen() - 'responsavel')$q$, '22023', 'menor de 18 sem representante legal: recusado') $x$;
  execute $x$ select teste.erro($q$select pg_temp.aceitar_men(pg_temp.dmen('{"responsavel":{"nome":"Maria Responsável Sintética","cpf":"529.982.247-25","nascimento":"1975-03-02","vinculo":"mae","declaro":true}}'))$q$,
  '22023', 'representante com o mesmo CPF do candidato: recusado') $x$;
  execute $x$ select teste.erro($q$select pg_temp.aceitar_men(jsonb_set(pg_temp.dmen(), '{responsavel,nascimento}', to_jsonb((current_date - interval '17 years')::date::text)))$q$,
  '22023', 'representante menor de idade: recusado') $x$;
  execute $x$ select teste.erro($q$select pg_temp.aceitar_men(jsonb_set(pg_temp.dmen(), '{responsavel,declaro}', 'false'))$q$, '22023', 'representante sem a declaração: recusado') $x$;
  execute $x$ select teste.erro($q$select pg_temp.aceitar_men(jsonb_set(pg_temp.dmen(), '{responsavel,vinculo}', '"vizinho"'))$q$, '22023', 'vínculo fora da lista: recusado') $x$;
  execute $x$ select teste.ok((pg_temp.aceitar_men(pg_temp.dmen())->>'aceito')::boolean, 'menor aceita com o representante legal') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select a.menor and a.responsavel_cpf = '11144477735' and a.responsavel_vinculo = 'mae'
                   and a.evidencia->'representante_legal'->>'declarou_representar_ou_assistir' = 'true' and (a.evidencia->'candidato'->>'menor_de_18')::boolean
                 from public.aceites_matricula a where a.oportunidade_id = (select v from teste.var where k = 'men_op')), 'evidência registra o representante legal') $x$;
  execute $x$ update public.aceites_matricula set arrependimento_ate = now() - interval '1 day' where oportunidade_id = (select v from teste.var where k = 'men_op') $x$;
  execute $x$ set role anon $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_desistir_matricula((select txt from ac where chave = 'men_tok'), (select v from teste.var where k = 'men_op'))$q$, '22023', 'desistência fora do prazo: recusada (vai à secretaria)') $x$;
  execute $x$ reset role $x$;
  execute $x$ reset role $x$;
  execute $x$ create temp table bol (chave text primary key, v text) $x$;
  execute $x$ grant all on bol to anon, authenticated $x$;
  execute $x$ insert into bol select 'op', o.id::text from public.oportunidades o where o.ies_id = 1 and o.responsavel_id = teste.id('comercial_a') and o.etapa in ('novo','contato','inscrito') order by o.id limit 1 $x$;
  execute $x$ insert into bol select 'curso', curso_id::text from public.oportunidades where id = (select v::bigint from bol where chave = 'op') $x$;
  execute $x$ insert into bol select 'outro_curso', c.id::text from public.cursos c where c.ies_id = 1 and c.id <> (select v::bigint from bol where chave = 'curso') order by c.id limit 1 $x$;
  execute $x$ insert into bol select 'op_portal', o.id::text from public.oportunidades o where o.ies_id = 1 and o.etapa in ('novo','contato','inscrito')
  and o.id <> (select v::bigint from bol where chave = 'op') and o.curso_id = (select v::bigint from bol where chave = 'curso') order by o.id desc limit 1 $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_programa_bolsa(1, '{"nome":"Bolsa X","tipo":"bolsa_institucional","percentual_max":30}')$q$, '42501', 'comercial não cria programa') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_programa_bolsa(1, '{"nome":"ProUni errado","tipo":"prouni","percentual_max":70}')$q$, '22023', 'ProUni só com 50% ou 100%') $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_programa_bolsa(1, '{"nome":"Fora","tipo":"bolsa_institucional","percentual_max":20,"cursos":[999999]}')$q$, '22023', 'curso de outra IES recusado') $x$;
  execute $x$ insert into bol select 'prouni', public.rpc_salvar_programa_bolsa(1, '{"nome":"ProUni 2027","tipo":"prouni","percentual_max":100,"requisitos":"Renda per capita conforme edital","documentos":["comprovante_renda"]}')->>'id' $x$;
  execute $x$ insert into bol select 'merito', public.rpc_salvar_programa_bolsa(1, jsonb_build_object('nome','Bolsa Mérito ENEM','tipo','bolsa_institucional','percentual_max',30,'vagas',1,
  'cursos', jsonb_build_array((select v::bigint from bol where chave = 'curso'))))->>'id' $x$;
  execute $x$ insert into bol select 'convenio', public.rpc_salvar_programa_bolsa(1, '{"nome":"Convênio Empresa Sintética","tipo":"convenio_empresa","percentual_max":15,"cumulativo":true}')->>'id' $x$;
  execute $x$ insert into bol select 'restrito', public.rpc_salvar_programa_bolsa(1, jsonb_build_object('nome','Bolsa só outro curso','tipo','bolsa_institucional','percentual_max',10,
  'cursos', jsonb_build_array((select v::bigint from bol where chave = 'outro_curso'))))->>'id' $x$;
  execute $x$ select teste.ok((select count(*) = 4 from jsonb_array_elements(public.rpc_bolsas(1)->'programas')), 'gestor vê os quatro programas') $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_programa_bolsa(1, '{"nome":"ProUni 2027","tipo":"prouni","percentual_max":50}')$q$, '22023', 'nome repetido recusado') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_bolsas(1)$q$, 'P0002', 'outra IES não vê os programas') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_solicitar_bolsa((select v::bigint from bol where chave = 'op'), (select v::bigint from bol where chave = 'prouni'), 70)$q$, '22023', 'ProUni de 70% recusado') $x$;
  execute $x$ select teste.erro($q$select public.rpc_solicitar_bolsa((select v::bigint from bol where chave = 'op'), (select v::bigint from bol where chave = 'merito'), 40)$q$, '22023', 'acima do percentual máximo recusado') $x$;
  execute $x$ select teste.erro($q$select public.rpc_solicitar_bolsa((select v::bigint from bol where chave = 'op'), (select v::bigint from bol where chave = 'restrito'), 10)$q$, '22023', 'programa de outro curso recusado') $x$;
  execute $x$ insert into bol select 's_merito', public.rpc_solicitar_bolsa((select v::bigint from bol where chave = 'op'), (select v::bigint from bol where chave = 'merito'), 30, 'Nota ENEM alta')->>'id' $x$;
  execute $x$ insert into bol select 's_prouni', public.rpc_solicitar_bolsa((select v::bigint from bol where chave = 'op'), (select v::bigint from bol where chave = 'prouni'), 100)->>'id' $x$;
  execute $x$ select teste.erro($q$select public.rpc_solicitar_bolsa((select v::bigint from bol where chave = 'op'), (select v::bigint from bol where chave = 'merito'), 20)$q$, '22023', 'solicitação repetida do mesmo programa recusada') $x$;
  execute $x$ select teste.erro($q$select public.rpc_decidir_bolsa((select v::bigint from bol where chave = 's_merito'), 'aprovada', 'Aprovo minha própria')$q$, '42501', 'comercial não decide') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select count(*) = 2 and bool_and(etapa_externa is null or etapa_externa = 'inscricao') from public.solicitacoes_bolsa where oportunidade_id = (select v::bigint from bol where chave = 'op')),
  'solicitações registradas; ProUni começa na etapa de inscrição') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('financeiro_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_decidir_bolsa((select v::bigint from bol where chave = 's_merito'), 'aprovada', 'ok')$q$, '22023', 'justificativa curta recusada') $x$;
  execute $x$ select teste.ok((public.rpc_decidir_bolsa((select v::bigint from bol where chave = 's_merito'), 'aprovada', 'Nota acima do corte do edital interno')->>'status') = 'aprovada', 'financeiro aprova a bolsa mérito') $x$;
  execute $x$ select teste.erro($q$select public.rpc_decidir_bolsa((select v::bigint from bol where chave = 's_prouni'), 'aprovada', 'ProUni deferido no sistema do MEC')$q$, '22023',
  'ProUni não cumulativo com mérito já aprovado: recusado') $x$;
  execute $x$ select teste.ok((public.rpc_decidir_bolsa((select v::bigint from bol where chave = 's_prouni'), 'indeferida', 'Não cumulativo com a bolsa mérito')->>'status') = 'indeferida', 'indeferimento com justificativa') $x$;
  execute $x$ select teste.erro($q$select public.rpc_decidir_bolsa((select v::bigint from bol where chave = 's_prouni'), 'aprovada', 'Mudança de ideia')$q$, '22023', 'decisão não muda depois de tomada') $x$;
  execute $x$ insert into bol select 's_conv', public.rpc_solicitar_bolsa((select v::bigint from bol where chave = 'op'), (select v::bigint from bol where chave = 'convenio'), 15)->>'id'
  where false $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ insert into bol select 's_conv', public.rpc_solicitar_bolsa((select v::bigint from bol where chave = 'op'), (select v::bigint from bol where chave = 'convenio'), 15)->>'id' $x$;
  execute $x$ select teste.erro($q$select public.rpc_decidir_bolsa((select v::bigint from bol where chave = 's_conv'), 'aprovada', 'Convênio vigente com a empresa')$q$, '42501', 'quem solicitou não decide') $x$;
  execute $x$ select teste.ok((select (s->>'decide_proprio')::boolean from jsonb_array_elements(public.rpc_bolsas(1)->'solicitacoes') s where (s->>'id')::bigint = (select v::bigint from bol where chave = 's_conv')),
  'painel sinaliza a solicitação que o usuário não pode decidir') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('financeiro_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_decidir_bolsa((select v::bigint from bol where chave = 's_conv'), 'aprovada', 'Convênio vigente com a empresa')$q$, '22023',
  'convênio cumulativo, mas a bolsa mérito não é: recusado') $x$;
  execute $x$ reset role $x$;
  execute $x$ insert into bol select 'op2', o.id::text from public.oportunidades o where o.ies_id = 1 and o.curso_id = (select v::bigint from bol where chave = 'curso')
  and o.etapa in ('novo','contato','inscrito') and o.id not in ((select v::bigint from bol where chave = 'op'), (select v::bigint from bol where chave = 'op_portal')) order by o.id limit 1 $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ insert into bol select 's_merito2', public.rpc_solicitar_bolsa((select v::bigint from bol where chave = 'op2'), (select v::bigint from bol where chave = 'merito'), 20)->>'id' $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('financeiro_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_decidir_bolsa((select v::bigint from bol where chave = 's_merito2'), 'aprovada', 'Segunda bolsa mérito')$q$, '22023', 'vagas esgotadas: recusado') $x$;
  execute $x$ select teste.ok((select (g->>'aprovadas')::int = 1 and (g->>'solicitadas')::int = 1 and (g->>'percentual_medio')::numeric = 30
                 from jsonb_array_elements(public.rpc_bolsas(1)->'programas') g where (g->>'id')::bigint = (select v::bigint from bol where chave = 'merito')), 'painel conta aprovadas, pendentes e percentual médio') $x$;
  execute $x$ select teste.ok((public.rpc_cancelar_bolsa((select v::bigint from bol where chave = 's_merito'), 'Candidato desistiu da bolsa')->>'status') = 'cancelada', 'cancelamento com motivo libera a vaga') $x$;
  execute $x$ select teste.ok((public.rpc_decidir_bolsa((select v::bigint from bol where chave = 's_merito2'), 'aprovada', 'Vaga liberada')->>'status') = 'aprovada', 'vaga liberada pode ser usada') $x$;
  execute $x$ select teste.ok((public.rpc_etapa_bolsa((select v::bigint from bol where chave = 's_prouni'), 'pre_selecao')->>'etapa_externa') = 'pre_selecao', 'etapa externa do ProUni registrada') $x$;
  execute $x$ select teste.erro($q$select public.rpc_etapa_bolsa((select v::bigint from bol where chave = 's_merito2'), 'contratado')$q$, '22023', 'etapa externa só para programas externos') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select count(*) >= 6 from public.auditoria where acao like 'bolsa.%'), 'operações de bolsa auditadas') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.ok((select bool_and((s->>'oportunidade_id')::bigint in (select o.id from public.oportunidades o where o.responsavel_id = teste.id('comercial_a')))
                 from jsonb_array_elements(public.rpc_bolsas(1)->'solicitacoes') s), 'comercial só vê solicitações das suas oportunidades') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ insert into bol select 'tok', public.rpc_gerar_acesso_portal((select v::bigint from bol where chave = 'op_portal'))->>'token' $x$;
  execute $x$ reset role $x$;
  execute $x$ set role anon $x$;
  execute $x$ select teste.ok((select count(*) = 3 and bool_and(g->>'nome' <> 'Bolsa só outro curso')
                 from jsonb_array_elements(public.rpc_publico_portal_bolsas((select v from bol where chave = 'tok'))) x, jsonb_array_elements(x->'programas') g
                 where (x->>'oportunidade_id')::bigint = (select v::bigint from bol where chave = 'op_portal')), 'portal mostra só os programas do curso do candidato') $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_solicitar_bolsa((select v from bol where chave = 'tok'), (select v::bigint from bol where chave = 'op_portal'), (select v::bigint from bol where chave = 'convenio'), 10, false)$q$,
  '22023', 'portal exige declaração de veracidade') $x$;
  execute $x$ select teste.ok((public.rpc_publico_solicitar_bolsa((select v from bol where chave = 'tok'), (select v::bigint from bol where chave = 'op_portal'), (select v::bigint from bol where chave = 'convenio'), 10, true, 'Trabalho na empresa conveniada')->>'status') = 'solicitada',
  'candidato solicita bolsa pelo portal') $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_solicitar_bolsa((select v from bol where chave = 'tok'), (select v::bigint from bol where chave = 'op'), (select v::bigint from bol where chave = 'convenio'), 10, true)$q$,
  'P0002', 'portal não solicita para oportunidade de outra pessoa') $x$;
  execute $x$ select teste.ok((select count(*) = 1 from jsonb_array_elements(public.rpc_publico_portal_bolsas((select v from bol where chave = 'tok'))) x, jsonb_array_elements(x->'solicitacoes') s
                 where s->>'status' = 'solicitada'), 'candidato acompanha a solicitação no portal') $x$;
  execute $x$ reset role $x$;
  execute $x$ reset role $x$;
  execute $x$ create temp table rem (chave text primary key, v text) $x$;
  execute $x$ grant all on rem to anon, authenticated $x$;
  execute $x$ update public.oportunidades set etapa = 'confirmado', confirmada_em = now() - interval '150 days', val_documental = true, val_financeira = true, val_academica = true
 where id = (select v from teste.var where k = 'men_op') $x$;
  execute $x$ insert into public.pessoas(ies_id, nome, email, base_legal, origem) values (1, 'Ingressante Evadido', 'ingressante.evadido@exemplo.invalid', 'consentimento', 'site') $x$;
  execute $x$ insert into public.oportunidades(ies_id, curso_id, pessoa_id, forma_ingresso, coorte, etapa, val_documental, val_financeira, val_academica, matricula_comercial_em, confirmada_em)
  select 1, 1, p.id, 'vestibular', '2027.1', 'confirmado', true, true, true, now() - interval '200 days', now() - interval '190 days' from public.pessoas p where p.email = 'ingressante.evadido@exemplo.invalid' $x$;
  execute $x$ insert into rem select 'evadido', o.id::text from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id where p.email = 'ingressante.evadido@exemplo.invalid' $x$;
  execute $x$ insert into public.vinculos(ies_id, oportunidade_id, marco, situacao, data_referencia, observacao, registrado_por)
  values (1, (select v::bigint from rem where chave = 'evadido'), 'd90', 'evadido', current_date - 10, 'Informado pela coordenação', teste.id('secretaria_a')) $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_rematricula(1)$q$, '42501', 'comercial não vê rematrícula') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_campanha_rematricula(1, jsonb_build_object('periodo','2027.2','abre_em',current_date,'fecha_em',current_date + 20,
  'termo', repeat('Termo de rematrícula do período. ', 4) || '**sem fechar'))$q$, '22023', 'termo com destaque aberto recusado') $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_campanha_rematricula(1, jsonb_build_object('periodo','2027-2','abre_em',current_date,'fecha_em',current_date + 20,
  'termo', repeat('Termo de rematrícula do período. ', 4)))$q$, '23514', 'período fora do padrão recusado') $x$;
  execute $x$ insert into rem select 'camp', public.rpc_salvar_campanha_rematricula(1, jsonb_build_object('periodo','2027.2','abre_em',current_date - 1,'fecha_em',current_date + 20,'meta_pct',85,
  'termo', repeat('Termo de rematrícula do período, conforme contrato vigente. ', 3) || E'\n**Reajuste anual conforme Lei 9.870/1999.**'))->>'id' $x$;
  execute $x$ select teste.ok((select r->'campanhas'->0->>'status' = 'rascunho' and (r->'campanhas'->0->'totais'->>'elegiveis')::int = 0 and r->'campanhas'->0->'totais'->'taxa_pct' = 'null'::jsonb
                 from (select public.rpc_rematricula(1) r) x), 'campanha em rascunho sem elegíveis: taxa N/D') $x$;
  execute $x$ select teste.ok((public.rpc_status_campanha_rematricula((select v::bigint from rem where chave = 'camp'), 'aberta')->>'novos_elegiveis')::int >= 3, 'abrir fotografa os elegíveis') $x$;
  execute $x$ select teste.ok((public.rpc_status_campanha_rematricula((select v::bigint from rem where chave = 'camp'), 'aberta')->>'novos_elegiveis')::int = 0, 'reabrir não duplica elegíveis') $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_campanha_rematricula(1, jsonb_build_object('termo', repeat('Outro termo depois de aberto. ', 5)), (select v::bigint from rem where chave = 'camp'))$q$,
  '22023', 'termo não muda com a campanha aberta') $x$;
  execute $x$ select teste.ok((select not (a @? ('$[*] ? (@.oportunidade_id == ' || (select v from rem where chave = 'evadido') || ')')::jsonpath)
                   and a @? ('$[*] ? (@.oportunidade_id == ' || (select v from teste.var where k = 'ing1') || ')')::jsonpath
                 from (select public.rpc_rematricula(1)->'campanhas'->0->'alunos' a) x), 'evadido fora, ingressante ativo dentro') $x$;
  execute $x$ reset role $x$;
  execute $x$ insert into rem select 'r_men', id::text from public.rematriculas where oportunidade_id = (select v from teste.var where k = 'men_op') $x$;
  execute $x$ insert into rem select 'r_ing1', id::text from public.rematriculas where oportunidade_id = (select v from teste.var where k = 'ing1') $x$;
  execute $x$ insert into rem select 'r_ing2', id::text from public.rematriculas where oportunidade_id = (select v from teste.var where k = 'ing2') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('financeiro_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_tratar_rematricula((select v::bigint from rem where chave = 'r_ing1'), 'bloquear', 'x', 'financeiro')$q$, '22023', 'bloqueio sem motivo recusado') $x$;
  execute $x$ select teste.ok((public.rpc_tratar_rematricula((select v::bigint from rem where chave = 'r_ing1'), 'bloquear', 'Mensalidades de outubro e novembro em aberto', 'financeiro')->>'status') = 'bloqueada',
  'financeiro bloqueia com categoria e motivo') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false) $x$;
  execute $x$ select teste.ok((public.rpc_tratar_rematricula((select v::bigint from rem where chave = 'r_ing2'), 'recusada', 'Aluno informou no balcão que vai transferir')->>'status') = 'recusada',
  'secretaria registra recusa presencial') $x$;
  execute $x$ select teste.erro($q$select public.rpc_tratar_rematricula((select v::bigint from rem where chave = 'r_ing2'), 'aceita', 'Mudou de ideia no mesmo dia')$q$, '22023', 'resposta registrada não muda') $x$;
  execute $x$ reset role $x$;
  execute $x$ insert into rem select 'tok_ing1', null $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ update rem set v = public.rpc_gerar_acesso_portal((select v from teste.var where k = 'ing1'))->>'token' where chave = 'tok_ing1' $x$;
  execute $x$ reset role $x$;
  execute $x$ set role anon $x$;
  execute $x$ select teste.ok((select r->>'status' = 'bloqueada' and r->>'bloqueio' = 'financeiro' and (r->>'aberta_agora')::boolean
                 from jsonb_array_elements(public.rpc_publico_portal_rematricula((select v from rem where chave = 'tok_ing1'))) r), 'aluno bloqueado vê só a categoria da pendência') $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_responder_rematricula((select v from rem where chave = 'tok_ing1'), (select v::bigint from rem where chave = 'r_ing1'),
  '{"resposta":"aceita","nome":"Ingressante Um","cpf":"52998224725","li_termo":true,"concordo":true}')$q$, '22023', 'bloqueado não rematricula pelo portal') $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_responder_rematricula((select v from rem where chave = 'tok_ing1'), (select v::bigint from rem where chave = 'r_men'),
  '{"resposta":"aceita","nome":"Ingressante Um","cpf":"52998224725","li_termo":true,"concordo":true}')$q$, 'P0002', 'não responde a rematrícula de outra pessoa') $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_responder_rematricula((select txt from ac where chave = 'men_tok'), (select v::bigint from rem where chave = 'r_men'),
  jsonb_build_object('resposta','aceita','nome',(select txt from ac where chave = 'men_nome'),'cpf','111.444.777-35','li_termo',true,'concordo',true))$q$, '22023', 'CPF diferente do da matrícula recusado') $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_responder_rematricula((select txt from ac where chave = 'men_tok'), (select v::bigint from rem where chave = 'r_men'),
  jsonb_build_object('resposta','aceita','nome',(select txt from ac where chave = 'men_nome'),'cpf','529.982.247-25','li_termo',true,'concordo',true))$q$, '22023', 'menor sem o representante: recusado') $x$;
  execute $x$ select teste.ok((select r->>'status' = 'aceita' and r->>'evidencia_hash' ~ '^[0-9a-f]{64}$' from (select public.rpc_publico_responder_rematricula((select txt from ac where chave = 'men_tok'), (select v::bigint from rem where chave = 'r_men'),
  jsonb_build_object('resposta','aceita','nome',(select txt from ac where chave = 'men_nome'),'cpf','529.982.247-25','li_termo',true,'concordo',true,
    'responsavel', jsonb_build_object('cpf','111.444.777-35','declaro',true))) r) x), 'menor rematricula com o representante da matrícula') $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_responder_rematricula((select txt from ac where chave = 'men_tok'), (select v::bigint from rem where chave = 'r_men'),
  jsonb_build_object('resposta','recusada','nome',(select txt from ac where chave = 'men_nome'),'cpf','529.982.247-25','motivo','mudei'))$q$, '22023', 'resposta do portal não muda') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select r.evidencia_hash = encode(sha256(convert_to(r.evidencia::text, 'UTF8')), 'hex') and (r.evidencia->'aluno'->>'cpf_conferido_com_matricula')::boolean
                   and r.evidencia->'representante_legal'->>'cpf' = '11144477735' and r.evidencia->>'termo_sha256' = encode(sha256(convert_to(c.termo, 'UTF8')), 'hex')
                 from public.rematriculas r join public.campanhas_rematricula c on c.id = r.campanha_id where r.id = (select v::bigint from rem where chave = 'r_men')),
  'evidência da rematrícula: CPF conferido, representante e hash do termo') $x$;
  execute $x$ select teste.ok((select count(*) = 0 from public.vinculos where oportunidade_id = (select v from teste.var where k = 'men_op') and marco = 'rematricula'), 'rematrícula aceita não grava vínculo acadêmico') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false) $x$;
  execute $x$ select teste.ok((select (t->>'aceitas')::int = 1 and (t->>'recusadas')::int = 1 and (t->>'bloqueadas')::int = 1
                   and (t->>'taxa_pct')::numeric = round(100.0 / (t->>'elegiveis')::int, 1)
                 from (select public.rpc_rematricula(1)->'campanhas'->0->'totais' t) x), 'indicadores: aceitas, recusadas, bloqueadas e taxa sobre elegíveis') $x$;
  execute $x$ select teste.ok((public.rpc_status_campanha_rematricula((select v::bigint from rem where chave = 'camp'), 'encerrada')->>'status') = 'encerrada', 'campanha encerrada') $x$;
  execute $x$ select teste.erro($q$select public.rpc_status_campanha_rematricula((select v::bigint from rem where chave = 'camp'), 'aberta')$q$, '22023', 'campanha encerrada não reabre') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_rematricula(1)$q$, 'P0002', 'outra IES não vê a rematrícula') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select count(*) >= 5 from public.auditoria where acao like 'rematricula.%'), 'rematrícula auditada') $x$;
  execute $x$ reset role $x$;
  execute $x$ create temp table cas (chave text primary key, v text) $x$;
  execute $x$ grant all on cas to anon, authenticated $x$;
  execute $x$ select teste.ok((select count(*) = 7 from public.trilhas_intervencao where ies_id = 1), 'trilhas padrão criadas para a IES') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_casos(1)$q$, '42501', 'comercial não vê casos de alunos') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_abrir_caso((select v from teste.var where k = 'mat_op'), 'frequencia', 'Faltou três semanas')$q$, '22023', 'caso só para aluno com ingresso efetivo') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_abrir_caso((select v from teste.var where k = 'ing1'), 'saude', 'Motivo sensível')$q$, '22023', 'motivo fora da lista (ex.: saúde) recusado') $x$;
  execute $x$ insert into cas select 'c1', public.rpc_abrir_caso((select v from teste.var where k = 'ing1'), 'adaptacao', 'Relatou dificuldade de se adaptar ao turno', 'alta')->>'id' $x$;
  execute $x$ select teste.erro($q$select public.rpc_abrir_caso((select v from teste.var where k = 'ing1'), 'adaptacao', 'Outro caso igual')$q$, '22023', 'um caso aberto por motivo e aluno') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select c.responsavel_id is not null and c.prazo <= now() + interval '61 hours' and c.prazo > now() + interval '59 hours'
                   and exists (select 1 from public.escopos e where e.usuario_id = c.responsavel_id and e.papel = 'secretaria')
                 from public.casos c where c.id = (select v::bigint from cas where chave = 'c1')), 'roteado para a secretaria; prioridade alta reduz o prazo à metade') $x$;
  execute $x$ insert into cas select 'resp', responsavel_id::text from public.casos where id = (select v::bigint from cas where chave = 'c1') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('financeiro_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_atender_caso((select v::bigint from cas where chave = 'c1'), 'nota', 'Tentando atender caso de outro')$q$, '42501', 'quem não é responsável não atende') $x$;
  execute $x$ select teste.erro($q$select public.rpc_atender_caso((select v::bigint from cas where chave = 'c1'), 'assumir')$q$, '42501', 'não assume caso que já tem dono') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', (select v from cas where chave = 'resp'), false) $x$;
  execute $x$ select teste.ok((public.rpc_atender_caso((select v::bigint from cas where chave = 'c1'), 'passo', 'Conversa de acolhimento feita na secretaria')->>'status') = 'em_atendimento', 'passo concluído põe o caso em atendimento') $x$;
  execute $x$ select teste.erro($q$select public.rpc_atender_caso((select v::bigint from cas where chave = 'c1'), 'agendar', 'Retorno', now() - interval '1 hour')$q$, '22023', 'agendamento no passado recusado') $x$;
  execute $x$ select public.rpc_atender_caso((select v::bigint from cas where chave = 'c1'), 'agendar', 'Retorno com a coordenação', now() + interval '3 days') $x$;
  execute $x$ select teste.erro($q$select public.rpc_atender_caso((select v::bigint from cas where chave = 'c1'), 'encaminhar', 'Para o comercial', null, teste.id('comercial_a'))$q$, '22023', 'encaminhar para quem não atende casos: recusado') $x$;
  execute $x$ select teste.ok((public.rpc_atender_caso((select v::bigint from cas where chave = 'c1'), 'encaminhar', 'Questão de mensalidade surgiu no atendimento', null, teste.id('financeiro_a'))->>'status') = 'em_atendimento',
  'encaminhado ao financeiro') $x$;
  execute $x$ select teste.erro($q$select public.rpc_atender_caso((select v::bigint from cas where chave = 'c1'), 'nota', 'Depois de encaminhar')$q$, '42501', 'quem encaminhou deixa de ser responsável') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('financeiro_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_atender_caso((select v::bigint from cas where chave = 'c1'), 'resolver', 'ok')$q$, '22023', 'resolução exige desfecho descrito') $x$;
  execute $x$ select teste.erro($q$select public.rpc_atender_caso((select v::bigint from cas where chave = 'c1'), 'cancelar', 'Cancelado pelo financeiro')$q$, '42501', 'só a gestão cancela') $x$;
  execute $x$ select teste.ok((select (c->'indicadores'->>'meus')::int = 1 and (select count(*) = 1 from jsonb_array_elements(c->'agenda')) from (select public.rpc_casos(1) c) x),
  'indicadores mostram o caso do usuário e a agenda') $x$;
  execute $x$ select teste.ok((public.rpc_atender_caso((select v::bigint from cas where chave = 'c1'), 'resolver', 'Aluno mudou para o turno da manhã e negociou o boleto de dezembro')->>'status') = 'resolvido', 'caso resolvido com desfecho') $x$;
  execute $x$ select teste.erro($q$select public.rpc_atender_caso((select v::bigint from cas where chave = 'c1'), 'nota', 'Depois de resolvido')$q$, '22023', 'caso encerrado não recebe atendimento') $x$;
  execute $x$ select teste.ok((select (c->'indicadores'->>'resolvidos')::int = 1 and (c->'indicadores'->>'horas_medias_resolucao') is not null
                   and jsonb_array_length(c->'casos'->-1->'eventos') >= 1
                 from (select public.rpc_casos(1, (select v from teste.var where k = 'ing1')) c) x), 'histórico do caso e tempo médio de resolução') $x$;
  execute $x$ reset role $x$;
  execute $x$ insert into public.campanhas_rematricula(ies_id, periodo, abre_em, fecha_em, termo, status)
  values (1, '2028.1', current_date - 1, current_date + 10, repeat('Termo de rematrícula do período 2028.1 conforme contrato. ', 3), 'aberta') $x$;
  execute $x$ insert into public.rematriculas(ies_id, campanha_id, oportunidade_id)
  select 1, c.id, (select v from teste.var where k = 'ing1') from public.campanhas_rematricula c where c.periodo = '2028.1' and c.ies_id = 1 $x$;
  execute $x$ reset role $x$;
  execute $x$ insert into cas select 'r2028', r.id::text from public.rematriculas r join public.campanhas_rematricula c on c.id = r.campanha_id where c.periodo = '2028.1' and r.oportunidade_id = (select v from teste.var where k = 'ing1') $x$;
  execute $x$ set role anon $x$;
  execute $x$ select teste.ok((public.rpc_publico_responder_rematricula((select v from rem where chave = 'tok_ing1'), (select v::bigint from cas where chave = 'r2028'),
  '{"resposta":"recusada","nome":"Ingressante Um","cpf":"529.982.247-25","motivo":"Não consigo pagar a mensalidade"}')->>'status') = 'recusada', 'aluno recusa a rematrícula pelo portal') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select c.origem = 'rematricula' and c.prioridade = 'alta' and c.motivo = 'rematricula_recusada' and c.descricao like '%Não consigo pagar%' and c.aberto_por is null
                 from public.casos c where c.oportunidade_id = (select v from teste.var where k = 'ing1') and c.motivo = 'rematricula_recusada'),
  'recusa no portal abre caso automaticamente, prioridade alta, com o motivo') $x$;
  execute $x$ select teste.ok((select count(*) = 0 from public.casos where oportunidade_id = (select v from teste.var where k = 'ing2') and motivo = 'rematricula_recusada'),
  'recusa registrada pela secretaria não abre caso automático') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_trilha(1, 'frequencia', '{"prazo_horas":24}')$q$, '42501', 'secretaria não edita trilha') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_trilha(1, 'frequencia', '{"prazo_horas":1}')$q$, '23514', 'prazo fora do limite recusado') $x$;
  execute $x$ select teste.ok((public.rpc_salvar_trilha(1, 'frequencia', '{"prazo_horas":48,"passos":["Ligar para o aluno","Reunião com a coordenação"]}')->>'id') is not null, 'gestor edita a trilha') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_casos(1)$q$, 'P0002', 'outra IES não vê os casos') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select cardinality(passos) = 2 and prazo_horas = 48 from public.trilhas_intervencao where ies_id = 1 and motivo = 'frequencia'), 'trilha atualizada') $x$;
  execute $x$ select teste.ok((select count(*) >= 6 from public.auditoria where acao like 'caso.%'), 'casos auditados') $x$;
  execute $x$ reset role $x$;
  execute $x$ select set_config('request.jwt.claims', '', false) $x$;
  execute $x$ select teste.ok((select count(*) = 0 from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
                   and not exists (select 1 from pg_policy p where p.polrelid = c.oid and p.polname = 'mfa_obrigatorio' and not p.polpermissive)),
  'toda tabela com RLS tem a política restritiva de 2FA') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false) $x$;
  execute $x$ select teste.ok((public.rpc_seguranca_conta()->>'ok')::boolean and (public.rpc_me()->'usuario'->>'id') is not null, 'sem fator e sem exigência: acesso normal') $x$;
  execute $x$ reset role $x$;
  execute $x$ insert into auth.mfa_factors(user_id, status) values (teste.id('secretaria_a'), 'verified') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select teste.erro($q$select public.rpc_me()$q$, 'M3601', 'com fator verificado e sessão aal1: pede o código') $x$;
  execute $x$ select teste.ok((select count(*) = 0 from public.oportunidades), 'leitura direta da tabela também bloqueada em aal1') $x$;
  execute $x$ select teste.ok((select r->>'aal' = 'aal1' and (r->>'tem_fator')::boolean and not (r->>'ok')::boolean from (select public.rpc_seguranca_conta() r) x), 'situação da conta responde mesmo sem o código') $x$;
  execute $x$ select set_config('request.jwt.claims', '{"aal":"aal2"}', false) $x$;
  execute $x$ select teste.ok((public.rpc_me()->'usuario'->>'id') is not null and (select count(*) > 0 from public.oportunidades), 'sessão aal2 libera RPC e leitura') $x$;
  execute $x$ select set_config('request.jwt.claims', '', false) $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_configurar_2fa(1, true)$q$, '22023', 'gestor sem fator não exige 2FA da equipe') $x$;
  execute $x$ reset role $x$;
  execute $x$ insert into auth.mfa_factors(user_id, status) values (teste.id('gestor_a'), 'verified') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select teste.erro($q$select public.rpc_configurar_2fa(1, true)$q$, 'M3601', 'gestor com fator precisa estar em aal2') $x$;
  execute $x$ select set_config('request.jwt.claims', '{"aal":"aal2"}', false) $x$;
  execute $x$ select teste.ok((select (r->>'exigir_2fa')::boolean and (r->>'usuarios_sem_fator')::int >= 1 from (select public.rpc_configurar_2fa(1, true) r) x), 'gestor em aal2 exige 2FA e vê quantos ainda não têm fator') $x$;
  execute $x$ select teste.ok((select (s->>'exigir_2fa')::boolean and exists (select 1 from jsonb_array_elements(s->'equipe') e where not (e->>'com_fator')::boolean) from (select public.rpc_situacao_2fa(1) s) x),
  'painel mostra quem ainda não tem fator') $x$;
  execute $x$ select set_config('request.jwt.claims', '', false) $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_me()$q$, 'M3602', 'IES exige 2FA e o usuário não tem fator: pede o cadastro') $x$;
  execute $x$ select teste.ok((select (r->>'exigido')::boolean and not (r->>'tem_fator')::boolean and r->'ies_que_exigem' ? 'Faculdade Alfa' from (select public.rpc_seguranca_conta() r) x)
  or (select (r->>'exigido')::boolean from (select public.rpc_seguranca_conta() r) x), 'situação da conta indica a exigência') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false) $x$;
  execute $x$ select teste.ok((public.rpc_me()->'usuario'->>'id') is not null, 'equipe de outra IES não é afetada') $x$;
  execute $x$ select teste.erro($q$select public.rpc_configurar_2fa(1, false)$q$, 'P0002', 'outra IES não muda a exigência') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select set_config('request.jwt.claims', '{"aal":"aal2"}', false) $x$;
  execute $x$ select teste.ok(not (public.rpc_configurar_2fa(1, false)->>'exigir_2fa')::boolean, 'gestor desliga a exigência') $x$;
  execute $x$ select set_config('request.jwt.claims', '', false) $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select count(*) = 2 from public.auditoria where acao = 'seguranca.2fa'), 'mudanças de exigência auditadas') $x$;
  execute $x$ delete from auth.mfa_factors $x$;
  execute $x$ reset role $x$;
  execute $x$ create temp table cmp (chave text primary key, v text) $x$;
  execute $x$ grant all on cmp to anon, authenticated $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_escola(1, '{"nome":"Escola X","rede":"publica","cidade":"Campo Grande","uf":"MS"}')$q$, '42501', 'secretaria não cadastra escola') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_escola(1, '{"nome":"Escola X","rede":"publica","cidade":"Campo Grande","uf":"ms1"}')$q$, '23514', 'UF inválida recusada') $x$;
  execute $x$ insert into cmp select 'esc', public.rpc_salvar_escola(1, '{"nome":"Escola Estadual Sintética","rede":"publica","cidade":"Campo Grande","uf":"ms","inep":"50000001"}')->>'id' $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_escola(1, '{"nome":"Escola Estadual Sintética","rede":"publica","cidade":"Campo Grande","uf":"MS"}')$q$, '22023', 'escola repetida na mesma cidade recusada') $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_visita(1, '{"titulo":"Feira","tipo":"feira","data":"2026-12-01","campanha":"nao-existe"}')$q$, '22023', 'campanha inexistente recusada') $x$;
  execute $x$ insert into cmp select 'vis', public.rpc_salvar_visita(1, jsonb_build_object('escola_id', (select v from cmp where chave = 'esc'), 'titulo', 'Palestra 3º ano', 'tipo', 'palestra',
  'data', current_date, 'publico_estimado', 120, 'codigo', 'eesint-2026'))->>'id' $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_visita(1, '{"titulo":"Outra","tipo":"visita","data":"2026-12-01","codigo":"eesint-2026"}')$q$, '22023', 'código de visita repetido recusado') $x$;
  execute $x$ select teste.ok((select (r->>'recebidos')::int = 2 and (r->>'contatos_existentes')::int = 1 and jsonb_array_length(r->'rejeitados') = 2
                 from (select public.rpc_captar_campo((select v::bigint from cmp where chave = 'vis'), jsonb_build_array(
    jsonb_build_object('id_local','11111111-1111-4111-8111-111111111111','nome','Aluna Feira Um','telefone','67999990001','curso_id',1,'coorte','2027.1',
      'consentimento',true,'consentimento_hash',repeat('a',64),'capturado_em', now() - interval '2 hours'),
    jsonb_build_object('id_local','22222222-2222-4222-8222-222222222222','nome','Ingressante Um','email','ingressante.um@exemplo.invalid','curso_id',1,'coorte','2027.1',
      'consentimento',true,'consentimento_hash',repeat('a',64)),
    jsonb_build_object('id_local','33333333-3333-4333-8333-333333333333','nome','Sem Consentimento','telefone','67999990003','curso_id',1,'coorte','2027.1','consentimento',false),
    jsonb_build_object('id_local','44444444-4444-4444-8444-444444444444','nome','Sem Contato','curso_id',1,'coorte','2027.1','consentimento',true,'consentimento_hash',repeat('a',64))
  )) r) x), 'lote: 2 recebidos (1 contato já existente), 2 rejeitados com motivo') $x$;
  execute $x$ select teste.ok((select (r->>'recebidos')::int = 0 and (r->>'ja_sincronizados')::int = 1
                 from (select public.rpc_captar_campo((select v::bigint from cmp where chave = 'vis'), jsonb_build_array(
    jsonb_build_object('id_local','11111111-1111-4111-8111-111111111111','nome','Aluna Feira Um','telefone','67999990001','curso_id',1,'coorte','2027.1','consentimento',true,'consentimento_hash',repeat('a',64))
  )) r) x), 'reenvio do mesmo cadastro (sincronização repetida) é ignorado') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select o.visita_id = (select v::bigint from cmp where chave = 'vis') and o.forma_ingresso = 'visita_escolar' and o.responsavel_id = teste.id('comercial_a') and p.base_legal = 'consentimento'
                 from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id where p.telefone = '67999990001'), 'lead criado com a visita, forma de ingresso e responsável') $x$;
  execute $x$ select teste.ok((select visita_id is null from public.oportunidades where id = (select v from teste.var where k = 'ing1')), 'contato existente não muda de origem') $x$;
  execute $x$ select teste.ok((select status = 'realizada' from public.visitas_escola where id = (select v::bigint from cmp where chave = 'vis')), 'visita com captação passa a realizada') $x$;
  execute $x$ select teste.ok((select capturado_em < sincronizado_em - interval '1 hour' from public.captacoes_campo where id_local = '11111111-1111-4111-8111-111111111111'), 'guarda a hora da captura e a da sincronização') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.ok((select (v->>'leads')::int >= 1 and (v->>'capturados')::int = 2 and v->>'escola' like 'Escola Estadual Sintética%'
                 from jsonb_array_elements(public.rpc_campo(1)->'visitas') v where (v->>'id')::bigint = (select v::bigint from cmp where chave = 'vis')), 'painel por visita') $x$;
  execute $x$ select teste.ok((select (e->>'visitas')::int = 1 and (e->>'leads')::int >= 1 from jsonb_array_elements(public.rpc_campo(1)->'escolas') e where (e->>'id')::bigint = (select v::bigint from cmp where chave = 'esc')),
  'painel por escola') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_b')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_captar_campo((select v::bigint from cmp where chave = 'vis'), '[]')$q$, 'P0002', 'outra IES não sincroniza na visita') $x$;
  execute $x$ reset role $x$;
  execute $x$ set role anon $x$;
  execute $x$ insert into cmp select 'qr_tok', public.rpc_publico_inscrever('vestibular-2027', '{"nome":"Aluna do QR","email":"aluna.qr@exemplo.invalid","curso_id":1,"aceite":true,"versao_consentimento":2,"tempo_ms":12000}'::jsonb)->>'portal' $x$;
  execute $x$ select teste.ok((public.rpc_publico_vincular_visita((select v from cmp where chave = 'qr_tok'), 'EESINT-2026')->>'vinculadas')::int = 1, 'QR: inscrição vinculada à visita') $x$;
  execute $x$ select teste.ok((public.rpc_publico_vincular_visita((select v from cmp where chave = 'qr_tok'), 'eesint-2026')->>'vinculadas')::int = 0, 'QR: vínculo não se repete') $x$;
  execute $x$ select teste.ok((public.rpc_publico_vincular_visita((select v from cmp where chave = 'qr_tok'), 'nao-existe')->>'vinculadas')::int = 0, 'QR: código inexistente não vincula') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select o.visita_id = (select v::bigint from cmp where chave = 'vis') from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id where p.email = 'aluna.qr@exemplo.invalid'),
  'oportunidade do QR atribuída à visita') $x$;
  execute $x$ select teste.ok((select count(*) >= 5 from public.auditoria where acao like 'campo.%'), 'captação em campo auditada') $x$;
  execute $x$ reset role $x$;
  execute $x$ create temp table psq (chave text primary key, v text) $x$;
  execute $x$ create temp table psq_tok (op bigint primary key, tok text) $x$;
  execute $x$ grant all on psq, psq_tok to anon, authenticated $x$;
  execute $x$ with alvo as (select id from (select distinct on (o.pessoa_id) o.id from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id
  where o.ies_id = 1 and o.etapa in ('novo','contato') and p.anonimizada_em is null and (select count(*) from public.oportunidades x where x.pessoa_id = o.pessoa_id) = 1 order by o.pessoa_id, o.id) z order by id desc limit 6)
update public.oportunidades set etapa = 'perdido', motivo_perda = 'Escolheu outra instituição' where id in (select id from alvo) $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_pesquisa(1, '{"nome":"X","publico":"perdido","perguntas":[{"id":"p1","tipo":"nps","texto":"Recomendaria?"}]}')$q$, '42501', 'coordenação não cria pesquisa') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_pesquisa(1, '{"nome":"Ruim","publico":"perdido","perguntas":[{"id":"p1","tipo":"nps","texto":"A?"},{"id":"p1","tipo":"texto","texto":"Repetida"}]}')$q$, '22023', 'pergunta com id repetido recusada') $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_pesquisa(1, '{"nome":"Ruim","publico":"perdido","perguntas":[{"id":"p1","tipo":"opcao","texto":"Escolha uma","opcoes":["só uma"]}]}')$q$, '22023', 'opção com menos de 2 alternativas recusada') $x$;
  execute $x$ insert into psq select 'q', public.rpc_salvar_pesquisa(1, '{"nome":"Por que não nos escolheu","publico":"perdido","min_respostas":5,"perguntas":[
  {"id":"motivo","tipo":"opcao","texto":"Principal motivo","opcoes":["Preço","Horário","Distância","Outra instituição","Desisti de estudar agora"]},
  {"id":"nps","tipo":"nps","texto":"De 0 a 10, quanto recomendaria nosso atendimento?"},
  {"id":"atend","tipo":"escala5","texto":"Como avalia o atendimento?"},
  {"id":"coment","tipo":"texto","texto":"O que poderíamos ter feito diferente?"}]}')->>'id' $x$;
  execute $x$ insert into psq_tok select o.id, public.rpc_gerar_acesso_portal(o.id)->>'token' from public.oportunidades o where o.ies_id = 1 and o.etapa = 'perdido' and o.motivo_perda = 'Escolheu outra instituição' $x$;
  execute $x$ reset role $x$;
  execute $x$ set role anon $x$;
  execute $x$ select teste.ok((select count(*) = 0 from psq_tok t, jsonb_array_elements(public.rpc_publico_portal_pesquisas(t.tok)) x), 'pesquisa em rascunho não aparece no portal') $x$;
  execute $x$ reset role $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select teste.ok((public.rpc_salvar_pesquisa(1, '{"status":"ativa"}', (select v::bigint from psq where chave = 'q'))->>'id') is not null, 'pesquisa ativada') $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_pesquisa(1, '{"nome":"Novo nome"}', (select v::bigint from psq where chave = 'q'))$q$, '22023', 'pesquisa ativa não muda perguntas') $x$;
  execute $x$ reset role $x$;
  execute $x$ set role anon $x$;
  execute $x$ select teste.ok((select count(*) = 1 from jsonb_array_elements(public.rpc_publico_portal_pesquisas((select tok from psq_tok order by op limit 1)))), 'perdido vê a pesquisa no portal') $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_responder_pesquisa((select tok from psq_tok order by op limit 1), (select v::bigint from psq where chave = 'q'), (select op from psq_tok order by op limit 1), '{"nps":"11"}')$q$, '22023', 'NPS acima de 10 recusado') $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_responder_pesquisa((select tok from psq_tok order by op limit 1), (select v::bigint from psq where chave = 'q'), (select op from psq_tok order by op limit 1), '{"motivo":"Inventado"}')$q$, '22023', 'opção inexistente recusada') $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_responder_pesquisa((select tok from psq_tok order by op limit 1), (select v::bigint from psq where chave = 'q'), (select op from psq_tok order by op limit 1), '{}')$q$, '22023', 'resposta vazia recusada') $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_responder_pesquisa((select tok from psq_tok order by op limit 1), (select v::bigint from psq where chave = 'q'), (select v from teste.var where k = 'ing1'), '{"nps":"9"}')$q$, 'P0002', 'não responde por oportunidade de outra pessoa') $x$;
  execute $x$ select public.rpc_publico_responder_pesquisa(t.tok, (select v::bigint from psq where chave = 'q'), t.op,
  jsonb_build_object('motivo', (array['Preço','Preço','Horário','Outra instituição'])[n], 'nps', (array['10','9','3','6'])[n], 'atend', '4', 'coment', 'Comentário sintético ' || n))
  from (select op, tok, row_number() over (order by op) n from psq_tok) t where n <= 4 $x$;
  execute $x$ select teste.erro($q$select public.rpc_publico_responder_pesquisa((select tok from psq_tok order by op limit 1), (select v::bigint from psq where chave = 'q'), (select op from psq_tok order by op limit 1), '{"nps":"9"}')$q$, '22023', 'resposta repetida recusada') $x$;
  execute $x$ reset role $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select teste.ok((select r->>'motivo' like 'N/D%' and not (r->>'suficiente')::boolean and r->'por_pergunta' is null and (r->>'respostas')::int = 4
                 from (select q->'resultado' r from jsonb_array_elements(public.rpc_pesquisas(1)->'pesquisas') q where (q->>'id')::bigint = (select v::bigint from psq where chave = 'q')) x),
  'abaixo do mínimo: resultados N/D (protege quem respondeu)') $x$;
  execute $x$ reset role $x$;
  execute $x$ set role anon $x$;
  execute $x$ select public.rpc_publico_responder_pesquisa(t.tok, (select v::bigint from psq where chave = 'q'), t.op, '{"motivo":"Distância","nps":"8","coment":"Muito longe de casa"}')
  from (select op, tok, row_number() over (order by op) n from psq_tok) t where n = 5 $x$;
  execute $x$ reset role $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('reitoria_a')::text, false) $x$;
  execute $x$ select teste.ok((select (r->>'suficiente')::boolean and (r->>'nps')::int = 0 and (r->'por_pergunta'->'motivo'->>'Preço')::int = 2
                   and jsonb_array_length(r->'por_pergunta'->'coment') = 5 and (r->>'elegiveis')::int >= 6 and r::text not like '%@%'
                 from (select q->'resultado' r from jsonb_array_elements(public.rpc_pesquisas(1)->'pesquisas') q where (q->>'id')::bigint = (select v::bigint from psq where chave = 'q')) x),
  'com o mínimo: NPS (2 promotores, 2 detratores em 5 = 0), distribuição e comentários sem identificação') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_pesquisas(1)$q$, '42501', 'comercial não vê resultados de pesquisa') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.ok((public.rpc_salvar_pesquisa(1, '{"status":"encerrada"}', (select v::bigint from psq where chave = 'q'))->>'id') is not null, 'pesquisa encerrada') $x$;
  execute $x$ reset role $x$;
  execute $x$ set role anon $x$;
  execute $x$ select teste.ok((select count(*) = 0 from psq_tok t, jsonb_array_elements(public.rpc_publico_portal_pesquisas(t.tok)) x), 'encerrada some do portal') $x$;
  execute $x$ reset role $x$;
  execute $x$ reset role $x$;
  execute $x$ create temp table bca (chave text primary key, v text) $x$;
  execute $x$ grant all on bca to anon, authenticated $x$;
  execute $x$ insert into public.processos_seletivos(ies_id, coorte, nome, tipo, inscricoes_ate, criado_por) values (1, '2027.1', 'Análise curricular com banca', 'analise_curricular', current_date + 10, teste.id('gestor_a')) $x$;
  execute $x$ insert into bca select 'proc', id::text from public.processos_seletivos where nome = 'Análise curricular com banca' $x$;
  execute $x$ insert into bca select 'op', o.id::text from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id where o.ies_id = 1 and o.curso_id = 1 and o.etapa in ('novo','contato','inscrito') and p.anonimizada_em is null order by o.id limit 1 $x$;
  execute $x$ insert into public.candidaturas(ies_id, processo_id, oportunidade_id) values (1, (select v::bigint from bca where chave = 'proc'), (select v::bigint from bca where chave = 'op')) $x$;
  execute $x$ insert into bca select 'cand', id::text from public.candidaturas where processo_id = (select v::bigint from bca where chave = 'proc') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_avaliar_banca((select v::bigint from bca where chave = 'cand'), '{"a":5}', 'Parecer sem banca configurada')$q$, '22023', 'sem banca configurada: recusado') $x$;
  execute $x$ select teste.erro($q$select public.rpc_configurar_banca((select v::bigint from bca where chave = 'proc'), '[{"id":"hist","texto":"Histórico","peso":0}]', 2)$q$, '22023', 'peso zero recusado') $x$;
  execute $x$ select teste.ok((public.rpc_configurar_banca((select v::bigint from bca where chave = 'proc'),
  '[{"id":"hist","texto":"Histórico escolar","peso":2},{"id":"carta","texto":"Carta de intenção","peso":1}]', 2, 150)->>'soma_pesos')::numeric = 3, 'banca: 2 critérios, 2 avaliadores, divergência máxima 150') $x$;
  execute $x$ select teste.erro($q$select public.rpc_avaliar_candidatura((select v::bigint from bca where chave = 'cand'), '{"resultado":"aprovado","justificativa":"Aprovado sem banca"}')$q$, '22023', 'decidir antes da banca: recusado') $x$;
  execute $x$ select teste.erro($q$select public.rpc_avaliar_banca((select v::bigint from bca where chave = 'cand'), '{"hist":11,"carta":5}', 'Nota fora da escala de zero a dez')$q$, '22023', 'nota acima de 10 recusada') $x$;
  execute $x$ select teste.ok((public.rpc_avaliar_banca((select v::bigint from bca where chave = 'cand'), '{"hist":9,"carta":9}', 'Histórico consistente e carta clara')->>'nota_final')::numeric = 900, 'avaliador 1: nota ponderada 900') $x$;
  execute $x$ select teste.erro($q$select public.rpc_avaliar_banca((select v::bigint from bca where chave = 'cand'), '{"hist":1,"carta":1}', 'Tentando avaliar duas vezes')$q$, '22023', 'mesmo avaliador não avalia duas vezes') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false) $x$;
  execute $x$ select teste.ok((select r->'avaliacoes' = 'null'::jsonb and (r->'situacao'->>'avaliacoes')::int = 1 and not (r->>'ja_avaliei')::boolean from (select public.rpc_banca((select v::bigint from bca where chave = 'cand')) r) x),
  'avaliação às cegas: antes da própria nota, não vê as dos outros') $x$;
  execute $x$ select teste.ok((select (r->'banca'->>'exige_mais_um')::boolean and not (r->'banca'->>'completa')::boolean
                 from (select public.rpc_avaliar_banca((select v::bigint from bca where chave = 'cand'), '{"hist":5,"carta":6}', 'Histórico mediano, carta genérica') r) x),
  'avaliador 2 diverge 333 pontos (> 150): exige terceiro avaliador') $x$;
  execute $x$ select teste.ok((select jsonb_array_length(r->'avaliacoes') = 2 from (select public.rpc_banca((select v::bigint from bca where chave = 'cand')) r) x), 'depois de avaliar, vê as notas da banca') $x$;
  execute $x$ select teste.erro($q$select public.rpc_avaliar_candidatura((select v::bigint from bca where chave = 'cand'), '{"resultado":"aprovado","justificativa":"Média suficiente"}')$q$, '22023', 'divergência sem terceiro avaliador: decisão recusada') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false) $x$;
  execute $x$ select public.rpc_avaliar_banca((select v::bigint from bca where chave = 'cand'), '{"hist":8,"carta":7}', 'Terceira leitura: bom histórico') $x$;
  execute $x$ select teste.ok(((public.rpc_avaliar_candidatura((select v::bigint from bca where chave = 'cand'), '{"resultado":"aprovado","justificativa":"Média da banca 711 com terceira leitura"}'))->>'id') is not null,
  'banca completa: decisão humana registrada') $x$;
  execute $x$ select teste.erro($q$select public.rpc_configurar_banca((select v::bigint from bca where chave = 'proc'), '[{"id":"x","texto":"Outro","peso":1}]', 1)$q$, '42501', 'coordenação não muda a rubrica') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_configurar_banca((select v::bigint from bca where chave = 'proc'), '[{"id":"x","texto":"Outro","peso":1}]', 1)$q$, '22023', 'rubrica não muda depois de a banca avaliar') $x$;
  execute $x$ reset role $x$;
  execute $x$ update public.oportunidades set forma_ingresso = 'transferencia' where id = (select v::bigint from bca where chave = 'op') $x$;
  execute $x$ insert into bca select 'op_vest', o.id::text from public.oportunidades o where o.ies_id = 1 and o.curso_id = 1 and o.forma_ingresso = 'vestibular' and o.etapa in ('novo','contato','inscrito') order by o.id limit 1 $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_aproveitamento((select v::bigint from bca where chave = 'op_vest'), '{"instituicao_origem":"Universidade X","curso_origem":"Direito"}')$q$, '22023', 'aproveitamento só para transferência e afins') $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_aproveitamento((select v::bigint from bca where chave = 'op'), '{"instituicao_origem":"Universidade Sintética","curso_origem":"Direito",
  "disciplinas":[{"nome":"Teoria Geral do Estado","carga":60,"situacao":"aproveitada"}]}')$q$, '22023', 'aproveitada sem disciplina equivalente: recusado') $x$;
  execute $x$ select teste.ok((public.rpc_salvar_aproveitamento((select v::bigint from bca where chave = 'op'), '{"instituicao_origem":"Universidade Sintética","curso_origem":"Direito",
  "disciplinas":[{"nome":"Teoria Geral do Estado","carga":60,"nota":"8,5","situacao":"aproveitada","equivalente":"Ciência Política"},
                 {"nome":"Introdução ao Direito","carga":80,"situacao":"parcial","equivalente":"Introdução ao Estudo do Direito","carga_aproveitada":40},
                 {"nome":"Economia","carga":60,"situacao":"pendente"}]}')->>'carga_aproveitada')::int = 100, 'rascunho da análise: 100 h aproveitadas') $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_aproveitamento((select v::bigint from bca where chave = 'op'), '{"parecer":"Parecer completo da coordenação","semestre_sugerido":2}', true)$q$, '22023', 'não conclui com disciplina pendente') $x$;
  execute $x$ reset role $x$;
  execute $x$ set role anon $x$;
  execute $x$ insert into bca select 'tok', null $x$;
  execute $x$ reset role $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ update bca set v = public.rpc_gerar_acesso_portal((select v::bigint from bca where chave = 'op'))->>'token' where chave = 'tok' $x$;
  execute $x$ reset role $x$;
  execute $x$ set role anon $x$;
  execute $x$ select teste.ok((select x->>'status' = 'em_analise' and x->'disciplinas' = 'null'::jsonb from jsonb_array_elements(public.rpc_publico_portal_aproveitamento((select v from bca where chave = 'tok'))) x),
  'portal: em análise, sem detalhes') $x$;
  execute $x$ reset role $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('coord_dir_a')::text, false) $x$;
  execute $x$ select teste.ok((public.rpc_salvar_aproveitamento((select v::bigint from bca where chave = 'op'), '{"disciplinas":[{"nome":"Teoria Geral do Estado","carga":60,"situacao":"aproveitada","equivalente":"Ciência Política"},
                 {"nome":"Introdução ao Direito","carga":80,"situacao":"parcial","equivalente":"Introdução ao Estudo do Direito","carga_aproveitada":40},
                 {"nome":"Economia","carga":60,"situacao":"nao_aproveitada"}],"parecer":"Aproveitamento parcial conforme ementas comparadas","semestre_sugerido":2}', true)->>'status') = 'concluida',
  'análise concluída com parecer e semestre sugerido') $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_aproveitamento((select v::bigint from bca where chave = 'op'), '{"parecer":"Mudança depois de concluir"}')$q$, '22023', 'análise concluída não muda') $x$;
  execute $x$ reset role $x$;
  execute $x$ set role anon $x$;
  execute $x$ select teste.ok((select (x->>'carga_aproveitada')::int = 100 and (x->>'semestre_sugerido')::int = 2 and jsonb_array_length(x->'disciplinas') = 3
                 from jsonb_array_elements(public.rpc_publico_portal_aproveitamento((select v from bca where chave = 'tok'))) x), 'portal mostra o resultado concluído') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select count(*) >= 6 from public.auditoria where acao in ('seletivo.banca','seletivo.banca_avaliar','aproveitamento.salvar')), 'banca e aproveitamento auditados') $x$;
  execute $x$ reset role $x$;
  execute $x$ create temp table oc (chave text primary key, v text) $x$;
  execute $x$ grant all on oc to anon, authenticated $x$;
  execute $x$ insert into oc select 'op_com', o.id::text from public.oportunidades o where o.ies_id = 1 and o.responsavel_id = teste.id('comercial_a') and o.etapa in ('novo','contato','inscrito') order by o.id limit 1 $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_registrar_recebida((select v::bigint from oc where chave = 'op_com'), 'visita', 'Oi, quero saber o valor')$q$, '22023', 'canal inválido recusado') $x$;
  execute $x$ select teste.erro($q$select public.rpc_registrar_recebida((select v::bigint from oc where chave = 'op_com'), 'whatsapp_manual', 'Futuro', now() + interval '1 day')$q$, '22023', 'data futura recusada') $x$;
  execute $x$ select public.rpc_registrar_recebida((select v::bigint from oc where chave = 'op_com'), 'whatsapp_manual', 'Oi, qual o valor da mensalidade de Direito?', now() - interval '3 hours') $x$;
  execute $x$ select teste.ok((select (f->>'horas')::numeric between 2.9 and 3.1 and f->>'texto' like 'Oi, qual o valor%' from jsonb_array_elements(public.rpc_conversas(1)->'fila') f
                 where (f->>'oportunidade_id')::bigint = (select v::bigint from oc where chave = 'op_com')), 'mensagem recebida entra na fila com o tempo de espera') $x$;
  execute $x$ select public.rpc_registrar_interacao((select v::bigint from oc where chave = 'op_com'), 'whatsapp_manual', 'Respondi com valores e bolsas vigentes') $x$;
  execute $x$ select teste.ok((select count(*) = 0 from jsonb_array_elements(public.rpc_conversas(1)->'fila') f where (f->>'oportunidade_id')::bigint = (select v::bigint from oc where chave = 'op_com')),
  'resposta registrada tira da fila') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_conversas(1)$q$, '42501', 'secretaria não vê a fila comercial') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('financeiro_a')::text, false) $x$;
  execute $x$ select teste.ok((select (r->>'importadas')::int = 3 and jsonb_array_length(r->'rejeitadas') = 2 from (select public.rpc_importar_pendencias(1, jsonb_build_array(
  jsonb_build_object('email','ingressante.um@exemplo.invalid','competencia','2026-09','valor','1.290,00','vencimento',(current_date - 70)::text,'situacao','aberta'),
  jsonb_build_object('email','ingressante.um@exemplo.invalid','competencia','2026-10','valor','1290','vencimento',(current_date - 40)::text),
  jsonb_build_object('oportunidade_id',(select v from teste.var where k = 'ing2'),'competencia','2026-11','valor','1290','vencimento',(current_date - 5)::text),
  jsonb_build_object('email','nao.existe@exemplo.invalid','competencia','2026-11','valor','10','vencimento','2026-11-10'),
  jsonb_build_object('email','ingressante.um@exemplo.invalid','competencia','2026-13','valor','10','vencimento','2026-11-10'))) r) x),
  'importação: 3 pendências, 2 rejeitadas (aluno inexistente, competência inválida)') $x$;
  execute $x$ select teste.ok((public.rpc_importar_pendencias(1, jsonb_build_array(jsonb_build_object('email','ingressante.um@exemplo.invalid','competencia','2026-09','valor','1.290,00','vencimento',(current_date - 70)::text)))->>'importadas')::int = 1,
  'reimportar a mesma competência atualiza (idempotente)') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select count(*) = 3 and sum(valor_centavos) = 387000 from public.pendencias_financeiras), 'valores convertidos para centavos sem duplicar') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select teste.ok((select (i->>'inadimplentes')::int = 1 and (i->>'em_aberto_centavos')::int = 387000 from (select public.rpc_financeiro(1, 30)->'indicadores' i) x), 'inadimplência: 1 aluno com atraso acima de 30 dias') $x$;
  execute $x$ reset role $x$;
  execute $x$ insert into public.campanhas_rematricula(ies_id, periodo, abre_em, fecha_em, termo, status) values (1, '2028.2', current_date - 1, current_date + 10, repeat('Termo de rematrícula do período 2028.2. ', 4), 'aberta') $x$;
  execute $x$ insert into public.rematriculas(ies_id, campanha_id, oportunidade_id) select 1, c.id, x from public.campanhas_rematricula c, unnest(array[(select v from teste.var where k = 'ing1'), (select v from teste.var where k = 'ing2')]) x where c.periodo = '2028.2' and c.ies_id = 1 $x$;
  execute $x$ insert into oc select 'camp', id::text from public.campanhas_rematricula where periodo = '2028.2' and ies_id = 1 $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_bloquear_inadimplentes((select v::bigint from oc where chave = 'camp'), 30)$q$, '42501', 'secretaria não bloqueia em lote') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('financeiro_a')::text, false) $x$;
  execute $x$ select teste.ok((public.rpc_bloquear_inadimplentes((select v::bigint from oc where chave = 'camp'), 30)->>'bloqueadas')::int = 1, 'bloqueio em lote só de quem tem atraso acima de 30 dias') $x$;
  execute $x$ select teste.ok((select (p->>'rematricula_pendente')::boolean is false from jsonb_array_elements(public.rpc_financeiro(1)->'pendencias') p where p->>'competencia' = '2026-09'), 'pendência mostra que a rematrícula não está mais pendente') $x$;
  execute $x$ reset role $x$;
  execute $x$ insert into oc select 'pend', id::text from public.pendencias_financeiras where competencia = '2026-09' $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select teste.erro($q$select public.rpc_negociar_pendencia((select v::bigint from oc where chave = 'pend'), 'negociada', 'ok')$q$, '22023', 'negociação sem descrição recusada') $x$;
  execute $x$ select teste.ok((public.rpc_negociar_pendencia((select v::bigint from oc where chave = 'pend'), 'negociada', 'Acordo em 3 parcelas a partir de dezembro')->>'situacao') = 'negociada', 'negociação registrada') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_polo(1, (select min(id) from public.campus where ies_id = 1), '{"tipo":"polo_parceiro","parceiro":"Parceiro X"}')$q$, '42501', 'comercial não cadastra polo') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_salvar_polo(1, (select min(id) from public.campus where ies_id = 1), '{"tipo":"polo_parceiro"}')$q$, '22023', 'polo parceiro exige o parceiro') $x$;
  execute $x$ select public.rpc_salvar_polo(1, (select min(id) from public.campus where ies_id = 1), '{"tipo":"polo_parceiro","parceiro":"Educa Parceiro Sintético Ltda.","regra_repasse":"Conforme contrato de parceria, cláusula 5","meta_ingressos":40}') $x$;
  execute $x$ select teste.ok((select u->>'tipo' = 'polo_parceiro' and (u->>'leads')::int > 0 and (u->>'ingressos')::int >= 2 and (u->>'meta_ingressos')::int = 40 and u ? 'receita_mensal_centavos'
                 from jsonb_array_elements(public.rpc_polos(1)->'unidades') u where (u->>'id')::bigint = (select min(id) from public.campus where ies_id = 1)), 'painel por unidade com parceiro, meta e funil') $x$;
  execute $x$ select teste.ok((public.rpc_polos(1)->>'aviso') like '%não calcula pagamento%', 'sem cálculo de repasse') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('secretaria_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_registrar_egresso((select v::bigint from oc where chave = 'op_com'), current_date, true)$q$, '22023', 'egresso só de quem foi aluno') $x$;
  execute $x$ select teste.erro($q$select public.rpc_registrar_egresso((select v from teste.var where k = 'ing1'), current_date + 1, true)$q$, '22023', 'conclusão no futuro recusada') $x$;
  execute $x$ insert into oc select 'eg1', public.rpc_registrar_egresso((select v from teste.var where k = 'ing1'), current_date, true, array['pos_graduacao'], 'Interesse em direito digital')->>'id' $x$;
  execute $x$ insert into oc select 'eg2', public.rpc_registrar_egresso((select v from teste.var where k = 'ing2'), current_date, false)->>'id' $x$;
  execute $x$ select teste.erro($q$select public.rpc_ofertar_egresso((select v::bigint from oc where chave = 'eg1'), 1, '2028.1', 'pos_graduacao')$q$, '42501', 'secretaria não oferta') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_ofertar_egresso((select v::bigint from oc where chave = 'eg2'), 1, '2028.1', 'pos_graduacao')$q$, '22023', 'sem consentimento: oferta recusada') $x$;
  execute $x$ select teste.ok(not (public.rpc_ofertar_egresso((select v::bigint from oc where chave = 'eg1'), 1, '2028.1', 'pos_graduacao')->>'duplicada')::boolean, 'oferta cria nova oportunidade') $x$;
  execute $x$ select public.rpc_ofertar_egresso((select v::bigint from oc where chave = 'eg1'), 1, '2028.1', 'pos_graduacao') $x$;
  execute $x$ select teste.ok((select (e->>'ofertas')::int = 1 from jsonb_array_elements(public.rpc_egressos(1)->'egressos') e where (e->>'id')::bigint = (select v::bigint from oc where chave = 'eg1')), 'oferta repetida não duplica: painel conta 1 oferta') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select o.forma_ingresso = 'pos_graduacao' and o.coorte = '2028.1' and o.egresso_origem_id = (select v::bigint from oc where chave = 'eg1')
                 from public.oportunidades o where o.egresso_origem_id is not null), 'oportunidade de pós ligada ao egresso') $x$;
  execute $x$ select teste.ok((select count(*) >= 8 from public.auditoria where acao in ('conversa.recebida','financeiro.importar','financeiro.bloquear_lote','financeiro.negociar','polo.salvar','egresso.registrar','egresso.ofertar')), 'Onda C auditada') $x$;
  execute $x$ reset role $x$;
  execute $x$ create temp table au (chave text primary key, v text) $x$;
  execute $x$ grant all on au to anon, authenticated $x$;
  execute $x$ select teste.ok((select count(*) = 8 and count(*) filter (where not ativa) = 1 and bool_and(ativa or codigo = 'bloqueio_inadimplentes')
                 from public.automacoes where ies_id = 1), 'IES com 8 regras; só o bloqueio de inadimplentes nasce desligado') $x$;
  execute $x$ insert into public.propostas(ies_id, oportunidade_id, desconto_pct, mensalidade_centavos, valor_final_centavos, validade, status, criado_por)
  select o.ies_id, o.id, 5, 100000, 95000, now() - interval '1 day', 'aprovada', teste.id('comercial_a')
    from public.oportunidades o where o.ies_id = 1 and o.etapa in ('contato','inscrito') and not exists (select 1 from public.propostas p where p.oportunidade_id = o.id and p.status in ('aprovada','pendente_aprovacao')) order by o.id limit 1 $x$;
  execute $x$ insert into au select 'prop', max(id)::text from public.propostas where status = 'aprovada' and validade < now() $x$;
  execute $x$ insert into public.casos(ies_id, oportunidade_id, motivo, origem, prioridade, descricao, trilha_id, prazo)
  select 1, (select v from teste.var where k = 'ing2'), 'desempenho', 'equipe', 'baixa', 'Caso sem responsável e vencido', t.id, now() - interval '30 hours'
    from public.trilhas_intervencao t where t.ies_id = 1 and t.motivo = 'desempenho' $x$;
  execute $x$ insert into au select 'caso', max(id)::text from public.casos where descricao = 'Caso sem responsável e vencido' $x$;
  execute $x$ update public.casos set status = 'resolvido', encerrado_em = now() where oportunidade_id = (select v from teste.var where k = 'ing1') and motivo = 'financeiro' and status in ('aberto','em_atendimento') $x$;
  execute $x$ insert into au select 'r', privado.executar_automacoes(1, 'agendador')::text $x$;
  execute $x$ select teste.ok((select status = 'expirada' from public.propostas where id = (select v::bigint from au where chave = 'prop')), 'proposta vencida expirada pela automação') $x$;
  execute $x$ select teste.ok((select responsavel_id is not null and prioridade = 'alta' from public.casos where id = (select v::bigint from au where chave = 'caso')), 'caso sem dono roteado e vencido escalonado para alta') $x$;
  execute $x$ select teste.ok((select count(*) = 1 and bool_and(origem = 'automacao') from public.casos where oportunidade_id = (select v from teste.var where k = 'ing1') and motivo = 'financeiro' and status = 'aberto'),
  'pendência vencida há mais de 30 dias abre caso financeiro identificado como automação') $x$;
  execute $x$ select teste.ok((select (v::jsonb->'1'->'ciclo_maim') ? 'follow_ups' and (v::jsonb->'1'->'regua') ? 'simuladas' and not (v::jsonb->'1') ? 'bloqueio_inadimplentes' from au where chave = 'r'),
  'regras ativas executadas; a desligada não roda') $x$;
  execute $x$ select teste.ok((select count(*) = 0 from public.mensagens where status = 'enviada'), 'automação não envia nada (só simulação)') $x$;
  execute $x$ insert into au select 'r2', privado.executar_automacoes(1, 'agendador')::text $x$;
  execute $x$ select teste.ok((select count(*) = 1 from public.casos where oportunidade_id = (select v from teste.var where k = 'ing1') and motivo = 'financeiro' and status = 'aberto'), 'segunda execução não duplica caso') $x$;
  execute $x$ select teste.ok((select (v::jsonb->'1'->'expirar_propostas'->>'expiradas')::int = 0 from au where chave = 'r2'), 'segunda execução não reexpira') $x$;
  execute $x$ select teste.ok((select count(*) >= 2 and bool_and(fim is not null) from public.automacoes_execucoes where ies_id = 1), 'execuções registradas com início e fim') $x$;
  execute $x$ select teste.ok((select count(*) >= 1 from public.auditoria where acao = 'automacao.executar'), 'execução com efeito é auditada') $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_automacoes(1)$q$, '42501', 'comercial não vê automações') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('reitoria_a')::text, false) $x$;
  execute $x$ select teste.ok((select jsonb_array_length(r->'regras') = 8 and not (r->>'pode_gerir')::boolean from (select public.rpc_automacoes(1) r) x), 'reitoria vê as regras sem poder mudar') $x$;
  execute $x$ select teste.erro($q$select public.rpc_configurar_automacao(1, 'bloqueio_inadimplentes', true)$q$, '42501', 'reitoria não liga automação') $x$;
  execute $x$ select set_config('request.jwt.claim.sub', teste.id('gestor_a')::text, false) $x$;
  execute $x$ select teste.erro($q$select public.rpc_configurar_automacao(1, 'bloqueio_inadimplentes', true, '{"dias_atraso": 0}')$q$, '22023', 'parâmetro fora do intervalo recusado') $x$;
  execute $x$ select teste.erro($q$select public.rpc_configurar_automacao(1, 'nao_existe', true)$q$, 'P0002', 'automação inexistente: 404') $x$;
  execute $x$ select teste.ok((public.rpc_configurar_automacao(1, 'bloqueio_inadimplentes', true, '{"dias_atraso": 30}')->>'ativa')::boolean, 'gestor liga o bloqueio automático com 30 dias') $x$;
  execute $x$ reset role $x$;
  execute $x$ insert into public.campanhas_rematricula(ies_id, periodo, abre_em, fecha_em, termo, status) values (1, '2029.1', current_date - 1, current_date + 10, repeat('Termo de rematrícula do período 2029.1. ', 4), 'aberta') $x$;
  execute $x$ insert into public.rematriculas(ies_id, campanha_id, oportunidade_id) select 1, c.id, (select v from teste.var where k = 'ing1') from public.campanhas_rematricula c where c.periodo = '2029.1' and c.ies_id = 1 $x$;
  execute $x$ set role authenticated $x$;
  execute $x$ select teste.ok((select (r->'bloqueio_inadimplentes'->>'bloqueadas')::int >= 1 from (select public.rpc_executar_automacoes(1) r) x), 'execução manual pelo gestor aplica o bloqueio ligado') $x$;
  execute $x$ reset role $x$;
  execute $x$ select teste.ok((select r.status = 'bloqueada' and r.motivo like 'Bloqueio automático%' from public.rematriculas r join public.campanhas_rematricula c on c.id = r.campanha_id
                 where c.periodo = '2029.1' and r.oportunidade_id = (select v from teste.var where k = 'ing1')), 'rematrícula bloqueada com motivo automático') $x$;
  execute $x$ update public.campanhas_rematricula set fecha_em = current_date - 1, abre_em = current_date - 5 where periodo = '2029.1' and ies_id = 1 $x$;
  execute $x$ select privado.executar_automacoes(1) $x$;
  execute $x$ select teste.ok((select status = 'encerrada' from public.campanhas_rematricula where periodo = '2029.1' and ies_id = 1), 'campanha vencida encerrada pela automação') $x$;
  execute $x$ select teste.ok((select count(*) = 1 from public.auditoria where acao = 'automacao.configurar'), 'mudança de regra auditada') $x$;
  execute $x$ update public.automacoes set ativa = false where codigo = 'bloqueio_inadimplentes' $x$;
  execute $x$ reset role $x$;
  select count(*) into n from teste.resultado;
  raise exception 'RESULTADO: % verificações aprovadas, 0 falhas (tudo desfeito; nada ficou gravado)', n;
end
$bloco$;
