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
  execute $x$ select teste.ok((public.rpc_central(1, '2027.1')->'totais'->>'custo_por_lead_centavos') is null and (public.rpc_central(1, '2027.1')->'totais'->>'custo_motivo') like 'Sem investimento cadastrado%', 'custo por lead N/D com motivo (sem investimento cadastrado)') $x$;
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
  execute $x$ reset role $x$;
  select count(*) into n from teste.resultado;
  raise exception 'RESULTADO: % verificações aprovadas, 0 falhas (tudo desfeito; nada ficou gravado)', n;
end
$bloco$;
