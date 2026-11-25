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
  execute $x$ insert into public.escopos(usuario_id, ies_id, curso_id, papel)
select u.id, x.ies, x.curso, x.papel from (values
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
  execute $x$ select teste.erro('select public.rpc_concluir_tarefa((select v from teste.var where k=''t2''), ''tentativa'')', '42501', 'atendente não conclui tarefa de outro no mesmo curso') $x$;
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
  execute $x$ select teste.ok((select count(*) from public.oportunidades) = (select count(*) from public.oportunidades where curso_id = 1) and (select count(*) from public.oportunidades) > 0,
  'novo atendente enxerga só o curso concedido') $x$;
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
  execute $x$ select teste.ok((public.rpc_bi(1, '2027.1')->'totais'->>'projecao_metodo') like 'Novas oportunidades necessárias%', 'método da projeção explicitado') $x$;
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
  execute $x$ reset role $x$;
  select count(*) into n from teste.resultado;
  raise exception 'RESULTADO: % verificações aprovadas, 0 falhas (tudo desfeito; nada ficou gravado)', n;
end
$bloco$;
