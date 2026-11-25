-- Matrícula 360° — semente SINTÉTICA de homologação para o SQL Editor do Supabase.
-- Projeto: jbimijcvvekomovodfze. Pré-requisito: as 9 contas m360.*@example.com já existem no Supabase Auth.
-- Tudo é feito pelas RPCs, com a identidade de cada perfil, gerando auditoria real.
-- Roda numa única transação: se algo falhar, nada fica gravado. Aborta se o banco já tiver IES.
do $semente$
declare
  contas constant text[][] := array[
    ['m360.master@example.com',       'Master da Plataforma',          'master'],
    ['m360.gestor.alfa@example.com',  'Gestora Alfa',                  'gestor'],
    ['m360.reitoria.alfa@example.com','Reitoria Alfa',                 'reitoria'],
    ['m360.coord.alfa@example.com',   'Coordenação Direito Alfa',      'coordenador'],
    ['m360.comercial.alfa@example.com','Atendente Alfa',               'comercial'],
    ['m360.secretaria.alfa@example.com','Secretaria Alfa',             'secretaria'],
    ['m360.financeiro.alfa@example.com','Financeiro Alfa',             'financeiro'],
    ['m360.gestor.beta@example.com',  'Gestor Beta',                   'gestor'],
    ['m360.comercial.beta@example.com','Atendente Beta',               'comercial']];
  u jsonb := '{}'; v_id uuid; faltam text := ''; i int;
  alfa bigint; beta bigint; dir bigint; adm bigint; psi bigint; enf bigint;
  r jsonb; v int; alvo text; nomes text[] := array['Ana','Bruno','Carla','Diego','Elisa','Fábio','Gabriela','Heitor','Íris','João','Karina','Lucas','Marina','Nuno','Olívia','Paulo'];
begin
  if exists (select 1 from public.ies) then raise exception 'ABORTADO: o banco já tem IES; a semente só roda em banco vazio.'; end if;
  for i in 1 .. array_length(contas, 1) loop
    select id into v_id from auth.users where lower(email) = contas[i][1];
    if v_id is null then faltam := faltam || ' ' || contas[i][1]; else u := u || jsonb_build_object(contas[i][1], v_id); end if;
  end loop;
  if faltam <> '' then raise exception 'ABORTADO: contas ausentes no Supabase Auth:%', faltam; end if;

  -- Perfis de aplicação (feito pelo dono do banco; é o único passo fora das RPCs).
  for i in 1 .. array_length(contas, 1) loop
    insert into public.usuarios(id, nome, master) values ((u->>contas[i][1])::uuid, contas[i][2], contas[i][3] = 'master');
  end loop;

  -- A partir daqui, cada passo roda com a identidade do perfil, pelas RPCs.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', u->>'m360.master@example.com', true);
  alfa := (public.rpc_provisionar_ies('Faculdade Alfa (fictícia)', 'piloto', 'Campus Centro',
    '[{"nome":"Direito","turno":"noturno","modalidade":"presencial","mensalidade_centavos":129000,"desconto_max_pct":30},
      {"nome":"Administração","turno":"ead","modalidade":"ead","mensalidade_centavos":39900,"desconto_max_pct":40}]')->>'id')::bigint;
  beta := (public.rpc_provisionar_ies('Centro Universitário Beta (fictício)', 'piloto', 'Campus Norte',
    '[{"nome":"Psicologia","turno":"matutino","modalidade":"presencial","mensalidade_centavos":115000,"desconto_max_pct":25},
      {"nome":"Enfermagem","turno":"noturno","modalidade":"presencial","mensalidade_centavos":98000,"desconto_max_pct":25}]')->>'id')::bigint;
  execute 'reset role';
  select id into dir from public.cursos where ies_id = alfa and nome = 'Direito';
  select id into adm from public.cursos where ies_id = alfa and nome = 'Administração';
  select id into psi from public.cursos where ies_id = beta and nome = 'Psicologia';
  select id into enf from public.cursos where ies_id = beta and nome = 'Enfermagem';
  execute 'set local role authenticated';
  for i in 2 .. array_length(contas, 1) loop
    perform public.rpc_conceder_escopo((u->>contas[i][1])::uuid,
      case when contas[i][1] like '%.beta@%' then beta else alfa end,
      case when contas[i][3] = 'coordenador' then dir end, contas[i][3]);
  end loop;

  -- Metas (gestores)
  perform set_config('request.jwt.claim.sub', u->>'m360.gestor.alfa@example.com', true);
  perform public.rpc_definir_meta(alfa, dir, '2027.1', 10);
  perform public.rpc_definir_meta(alfa, adm, '2027.1', 6);
  perform set_config('request.jwt.claim.sub', u->>'m360.gestor.beta@example.com', true);
  perform public.rpc_definir_meta(beta, psi, '2027.1', 5);

  -- Oportunidades sintéticas distribuídas pelo funil (Alfa: 16; Beta: 8)
  for i in 1 .. 24 loop
    perform set_config('request.jwt.claim.sub', u->>(case when i <= 16 then 'm360.comercial.alfa@example.com' else 'm360.comercial.beta@example.com' end), true);
    r := public.rpc_criar_oportunidade(case when i <= 16 then alfa else beta end, jsonb_build_object(
      'nome', nomes[1 + (i - 1) % 16] || ' Sintético ' || i, 'email', 'candidato' || i || '@example.com',
      'curso_id', case when i <= 16 then (case when i % 2 = 0 then dir else adm end) else (case when i % 2 = 0 then psi else enf end) end,
      'forma_ingresso', (array['vestibular','enem','transferencia','segunda_graduacao','indicacao'])[1 + i % 5],
      'coorte', '2027.1', 'base_legal', 'consentimento', 'origem', 'semente de homologação'));
    v := (r->>'versao')::int;
    alvo := (array['novo','contato','inscrito','pre_matricula','matricula_comercial','confirmado','perdido','matricula_comercial'])[1 + (i - 1) % 8];
    if alvo = 'perdido' then
      v := (public.rpc_mover_etapa((r->>'id')::bigint, 'contato', v)->>'versao')::int;
      perform public.rpc_mover_etapa((r->>'id')::bigint, 'perdido', v, 'Optou por outra instituição');
      continue;
    end if;
    if alvo in ('contato','inscrito','pre_matricula','matricula_comercial','confirmado') then v := (public.rpc_mover_etapa((r->>'id')::bigint, 'contato', v)->>'versao')::int; end if;
    if alvo in ('inscrito','pre_matricula','matricula_comercial','confirmado') then v := (public.rpc_mover_etapa((r->>'id')::bigint, 'inscrito', v)->>'versao')::int; end if;
    if alvo in ('inscrito','pre_matricula') then perform public.rpc_criar_proposta((r->>'id')::bigint, case when i % 3 = 0 then 45 else 15 end); end if;
    if alvo in ('pre_matricula','matricula_comercial','confirmado') then v := (public.rpc_mover_etapa((r->>'id')::bigint, 'pre_matricula', v)->>'versao')::int; end if;
    if alvo in ('matricula_comercial','confirmado') then v := (public.rpc_mover_etapa((r->>'id')::bigint, 'matricula_comercial', v)->>'versao')::int; end if;
    if alvo = 'confirmado' then
      perform set_config('request.jwt.claim.sub', u->>(case when i <= 16 then 'm360.secretaria.alfa@example.com' else 'm360.gestor.beta@example.com' end), true);
      if i <= 16 then
        v := (public.rpc_validar((r->>'id')::bigint, 'documental', 'valida', 'Documentos conferidos (sintético)', v)->>'versao')::int;
        v := (public.rpc_validar((r->>'id')::bigint, 'academica', 'valida', 'Requisitos atendidos (sintético)', v)->>'versao')::int;
        perform set_config('request.jwt.claim.sub', u->>'m360.financeiro.alfa@example.com', true);
        v := (public.rpc_validar((r->>'id')::bigint, 'financeira', 'valida', 'Primeira mensalidade conciliada (sintético)', v)->>'versao')::int;
        perform set_config('request.jwt.claim.sub', u->>'m360.secretaria.alfa@example.com', true);
        perform public.rpc_confirmar((r->>'id')::bigint, v);
      end if;
    end if;
  end loop;
  execute 'reset role';
  raise notice 'Semente concluída: % IES, % usuários, % oportunidades.',
    (select count(*) from public.ies), (select count(*) from public.usuarios), (select count(*) from public.oportunidades);
end
$semente$;

-- Conferência (uma linha):
select (select count(*) from public.ies) as ies_2, (select count(*) from public.cursos) as cursos_4,
       (select count(*) from public.usuarios) as usuarios_9, (select count(*) from public.escopos) as escopos_8,
       (select count(*) from public.oportunidades) as oportunidades_24,
       (select count(*) from public.oportunidades where etapa = 'confirmado') as confirmados_2,
       (select count(*) from public.auditoria) as eventos_auditoria;
