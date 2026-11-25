-- Semente SINTÉTICA para testes de isolamento: 2 IES × 2 cursos, todos os perfis.
-- Executada como dono do banco; as oportunidades são criadas pelas RPCs, como um cliente faria.
create schema teste;
create table teste.usuario (apelido text primary key, id uuid not null);
insert into teste.usuario values
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
  ('revogado_a',  '00000000-0000-0000-0000-0000000000a9');
insert into auth.users select id from teste.usuario;
insert into public.usuarios(id, nome, master) select id, apelido, apelido = 'master' from teste.usuario;

insert into public.ies(nome) values ('Faculdade Alfa (fictícia)'), ('Centro Universitário Beta (fictício)');
insert into public.campus(ies_id, nome) values (1, 'Centro'), (2, 'Norte');
insert into public.cursos(ies_id, campus_id, nome, turno, modalidade, mensalidade_centavos, desconto_max_pct) values
  (1, 1, 'Direito', 'noturno', 'presencial', 129000, 30),
  (1, 1, 'Administração', 'ead', 'ead', 39900, 40),
  (2, 2, 'Psicologia', 'matutino', 'presencial', 115000, 25),
  (2, 2, 'Enfermagem', 'noturno', 'presencial', 98000, 25);

insert into public.escopos(usuario_id, ies_id, curso_id, papel)
select u.id, x.ies, x.curso, x.papel from (values
  ('gestor_a', 1, null::bigint, 'gestor'), ('reitoria_a', 1, null, 'reitoria'), ('coord_dir_a', 1, 1, 'coordenador'),
  ('comercial_a', 1, null, 'comercial'), ('com_dir_a', 1, 1, 'comercial'), ('secretaria_a', 1, null, 'secretaria'),
  ('financeiro_a', 1, null, 'financeiro'), ('gestor_b', 2, null, 'gestor'), ('comercial_b', 2, null, 'comercial'),
  ('revogado_a', 1, null, 'comercial')) as x(apelido, ies, curso, papel)
join teste.usuario u on u.apelido = x.apelido;
update public.usuarios set revogado_em = now() where id = (select id from teste.usuario where apelido = 'revogado_a');
insert into public.metas values (1, 1, '2027.1', 10), (1, 2, '2027.1', 6);

-- Utilitários de teste
create function teste.id(p text) returns uuid language sql stable as $$ select id from teste.usuario where apelido = p $$;
create function teste.ok(p boolean, p_nome text) returns void language plpgsql as $$
begin
  if p is distinct from true then raise exception 'FALHOU: %', p_nome; end if;
  raise notice 'OK  %', p_nome;
end $$;
-- Executa SQL esperando um SQLSTATE específico.
create function teste.erro(p_sql text, p_codigo text, p_nome text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlstate = p_codigo then raise notice 'OK  % (SQLSTATE %)', p_nome, sqlstate; return; end if;
    raise exception 'FALHOU: % — esperado %, obtido % (%)', p_nome, p_codigo, sqlstate, sqlerrm;
  end;
  raise exception 'FALHOU: % — deveria ter falhado com %', p_nome, p_codigo;
end $$;
grant usage on schema teste to anon, authenticated;
grant select on teste.usuario to anon, authenticated;
grant execute on all functions in schema teste to anon, authenticated;
-- Tabela de apoio para trocar valores entre blocos de teste (não exposta em produção).
create table teste.var (k text primary key, v bigint);
grant all on teste.var to authenticated;

-- Oportunidades criadas via RPC pelos comerciais.
set role authenticated;
select set_config('request.jwt.claim.sub', teste.id('comercial_a')::text, false);
select public.rpc_criar_oportunidade(1, jsonb_build_object('nome', 'Cand ' || g, 'email', 'a' || g || '@exemplo.invalid',
  'curso_id', 1 + (g % 2), 'forma_ingresso', 'enem', 'coorte', '2027.1', 'base_legal', 'consentimento', 'origem', 'site'))
from generate_series(1, 8) g;
select set_config('request.jwt.claim.sub', teste.id('comercial_b')::text, false);
select public.rpc_criar_oportunidade(2, jsonb_build_object('nome', 'Cand B' || g, 'email', 'b' || g || '@exemplo.invalid',
  'curso_id', 3 + (g % 2), 'forma_ingresso', 'vestibular', 'coorte', '2027.1', 'base_legal', 'consentimento', 'origem', 'evento'))
from generate_series(1, 4) g;
reset role;
