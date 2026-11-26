-- Matrícula 360° — migração 22 (aceite eletrônico reforçado) para o SQL Editor do projeto jbimijcvvekomovodfze.
-- Requer as migrações 1 a 21 já aplicadas. CONFIRA o projeto na URL antes de executar. Idempotente. Transação única. A última linha deve ser commit;
begin;
-- Matrícula 360° — migração 22: aceite eletrônico reforçado (revisão jurídica do aceite da migração 21).
--   1. Menor de idade: o candidato informa a data de nascimento; abaixo de 18 anos o aceite exige o representante legal
--      (nome, CPF, data de nascimento, vínculo e declaração), que aceita junto com o candidato.
--   2. Identificação e confirmação: CPF do candidato (dígitos verificadores conferidos) e código de 6 dígitos enviado ao contato
--      do cadastro (validade de 15 min, 5 tentativas, 1 pedido por minuto). ENQUANTO A INTEGRAÇÃO DE E-MAIL/SMS ESTIVER DESLIGADA
--      o código é exibido na tela, em modo simulação, e a evidência registra "modo: simulacao".
--   3. Evidência única: contrato (versão e hash), condições econômicas, identificação, declarações, confirmação, origem e data
--      reunidos em um JSON canônico; o SHA-256 desse texto fica gravado e é reconferido ao emitir o comprovante.
--   4. Declarações separadas: "li o contrato", "concordo com as condições", "ciência do prazo de arrependimento".
--   5. Comprovante para o candidato (portal) e para a equipe (ficha), com o texto integral do contrato aceito.
--   6. Arrependimento em 7 dias pelo portal: a matrícula é cancelada, com registro e auditoria.
--   7. Destaque de cláusulas no contrato com **texto** (a publicação recusa marcação aberta).
--   [Não verificado] Enquadramento jurídico (MP 2.200-2/2001 art. 10 §2º; CDC arts. 46, 49 e 54; Decreto 7.962/2013;
--   CC arts. 3º-5º) a validar pelo jurídico da instituição.
-- Idempotente.

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('matricula.comprovante', 'Conversão e Matrículas', 'Ver o comprovante do aceite (contém CPF; cada consulta é auditada)',
   array['gestor','secretaria','financeiro','coordenador','comercial'], 'curso', 'rpc_comprovante_aceite')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

alter table public.aceites_matricula
  add column if not exists cpf_candidato text,
  add column if not exists nascimento_candidato date,
  add column if not exists menor boolean,
  add column if not exists responsavel_nome text,
  add column if not exists responsavel_cpf text,
  add column if not exists responsavel_nascimento date,
  add column if not exists responsavel_vinculo text,
  add column if not exists confirmacao_canal text,
  add column if not exists confirmacao_destino text,
  add column if not exists confirmacao_modo text,
  add column if not exists evidencia jsonb,
  add column if not exists evidencia_hash text,
  add column if not exists arrependimento_ate timestamptz,
  add column if not exists desistencia_em timestamptz,
  add column if not exists desistencia_motivo text;

create table if not exists public.codigos_aceite (
  oportunidade_id bigint primary key references public.oportunidades(id),
  ies_id bigint not null references public.ies(id),
  codigo_hash text not null,
  canal text not null,
  destino_mascarado text,
  modo text not null check (modo in ('simulacao','enviado')),
  expira_em timestamptz not null,
  tentativas int not null default 0,
  criado_em timestamptz not null default now()
);
create index if not exists codigos_aceite_ies on public.codigos_aceite(ies_id);
alter table public.codigos_aceite enable row level security;
revoke all on public.codigos_aceite from anon, authenticated;

-- ---------------------------------------------------------------- auxiliares
create or replace function privado.cpf_valido(p text) returns boolean
language plpgsql immutable set search_path = '' as $$
declare d text := regexp_replace(coalesce(p, ''), '\D', '', 'g'); s int; r int; i int;
begin
  if length(d) <> 11 or d ~ '^(\d)\1{10}$' then return false; end if;
  s := 0; for i in 1..9 loop s := s + substr(d, i, 1)::int * (11 - i); end loop;
  r := (s * 10) % 11; if r = 10 then r := 0; end if;
  if r <> substr(d, 10, 1)::int then return false; end if;
  s := 0; for i in 1..10 loop s := s + substr(d, i, 1)::int * (12 - i); end loop;
  r := (s * 10) % 11; if r = 10 then r := 0; end if;
  return r = substr(d, 11, 1)::int;
end $$;

create or replace function privado.utc(t timestamptz) returns text
language sql immutable set search_path = '' as $$ select to_char(t at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') $$;

create or replace function privado.nome_norm(t text) returns text
language sql immutable set search_path = '' as $$ select lower(regexp_replace(trim(coalesce(t, '')), '\s+', ' ', 'g')) $$;

-- Elegibilidade comum ao pedido de código e ao aceite (só valida; quem chama carrega oportunidade, proposta e contrato).
create or replace function privado.aceite_elegivel(p public.pessoas, p_op bigint) returns void
language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; pr public.propostas;
begin
  select * into o from public.oportunidades where id = p_op and pessoa_id = p.id for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if exists (select 1 from public.aceites_matricula where oportunidade_id = o.id) then raise exception 'Matrícula já aceita' using errcode = '22023'; end if;
  if o.etapa <> 'pre_matricula' then raise exception 'A matrícula online está disponível na etapa de pré-matrícula' using errcode = '22023'; end if;
  select * into pr from public.propostas where oportunidade_id = o.id and status = 'aprovada' order by id desc limit 1 for update;
  if not found then raise exception 'Não há proposta aprovada para aceitar' using errcode = '22023'; end if;
  if pr.validade < now() then raise exception 'A proposta expirou: fale com a equipe da instituição' using errcode = '22023'; end if;
  if not exists (select 1 from public.contratos_modelo where ies_id = o.ies_id and ativo) then
    raise exception 'Não há contrato publicado pela instituição' using errcode = '22023'; end if;
end $$;

revoke execute on function privado.cpf_valido(text), privado.utc(timestamptz), privado.nome_norm(text),
  privado.aceite_elegivel(public.pessoas, bigint) from public, anon, authenticated;

-- ---------------------------------------------------------------- contrato: destaque com **texto**
create or replace function public.rpc_salvar_contrato(p_ies bigint, p_texto text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v int; v_id bigint; t text := trim(coalesce(p_texto, ''));
begin
  perform privado.autorizar(p_ies, 'contrato.gerir');
  if length(t) not between 100 and 20000 then raise exception 'Contrato deve ter entre 100 e 20000 caracteres' using errcode = '22023'; end if;
  if ((length(t) - length(replace(t, '**', ''))) / 2) % 2 <> 0 then
    raise exception 'Marcação de destaque incompleta: cada ** aberto precisa ser fechado' using errcode = '22023';
  end if;
  select coalesce(max(versao), 0) + 1 into v from public.contratos_modelo where ies_id = p_ies;
  update public.contratos_modelo set ativo = false where ies_id = p_ies and ativo;
  insert into public.contratos_modelo(ies_id, versao, texto, criado_por) values (p_ies, v, t, (select auth.uid())) returning id into v_id;
  perform privado.auditar(p_ies, 'contrato.publicar', 'ies', p_ies::text, jsonb_build_object('versao', v, 'hash', encode(sha256(convert_to(t, 'UTF8')), 'hex'),
    'destaques', (length(t) - length(replace(t, '**', ''))) / 4));
  return jsonb_build_object('id', v_id, 'versao', v);
end $$;

-- ---------------------------------------------------------------- portal: situação da matrícula online
create or replace function public.rpc_publico_portal_matricula(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.pessoas;
begin
  p := privado.portal_pessoa(p_token);
  return (select coalesce(jsonb_agg(jsonb_build_object('oportunidade_id', o.id, 'curso', c.nome || ' · ' || c.turno, 'coorte', o.coorte, 'etapa', o.etapa,
      'procedimento', 'aceite-v2', 'prazo_arrependimento_dias', 7,
      'confirmacao', jsonb_build_object('canal', case when p.email is not null then 'email' else 'sms' end,
                       'destino', case when p.email is not null then privado.mascarar_email(p.email) else privado.mascarar_tel(p.telefone) end),
      'proposta', (select jsonb_build_object('id', x.id, 'mensalidade_centavos', x.mensalidade_centavos, 'desconto_pct', x.desconto_pct,
                     'valor_final_centavos', x.valor_final_centavos, 'validade', x.validade, 'status', x.status)
                   from public.propostas x where x.oportunidade_id = o.id and x.status in ('aprovada','aceita') order by x.id desc limit 1),
      'contrato', (select jsonb_build_object('versao', k.versao, 'texto', k.texto) from public.contratos_modelo k where k.ies_id = o.ies_id and k.ativo),
      'aceite', (select jsonb_build_object('aceito_em', a.aceito_em, 'contrato_versao', (select versao from public.contratos_modelo where id = a.contrato_id),
                   'evidencia_hash', a.evidencia_hash, 'arrependimento_ate', coalesce(a.arrependimento_ate, a.aceito_em + interval '7 days'),
                   'desistencia_em', a.desistencia_em,
                   'pode_desistir', a.desistencia_em is null and now() <= coalesce(a.arrependimento_ate, a.aceito_em + interval '7 days') and o.etapa in ('matricula_comercial','confirmado'))
                 from public.aceites_matricula a where a.oportunidade_id = o.id),
      'pagamento', 'Integração de cobrança desligada: a instituição informará a forma de pagamento.') order by o.id), '[]'::jsonb)
    from public.oportunidades o join public.cursos c on c.id = o.curso_id
   where o.pessoa_id = p.id and (o.etapa in ('pre_matricula','matricula_comercial','confirmado')
         or exists (select 1 from public.aceites_matricula a where a.oportunidade_id = o.id)));
end $$;

-- ---------------------------------------------------------------- portal: código de confirmação
create or replace function public.rpc_publico_codigo_aceite(p_token text, p_op bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.pessoas; o public.oportunidades; ant public.codigos_aceite; cod text; can text; dest text;
begin
  p := privado.portal_pessoa(p_token);
  perform privado.aceite_elegivel(p, p_op);
  select * into o from public.oportunidades where id = p_op;
  select * into ant from public.codigos_aceite where oportunidade_id = p_op;
  if found and ant.criado_em > now() - interval '60 seconds' then
    perform privado.erro_http(429, '54000', 'Aguarde um minuto para pedir outro código.');
  end if;
  cod := lpad(((('x' || substr(md5(gen_random_uuid()::text), 1, 8))::bit(32)::bigint) % 1000000)::text, 6, '0');
  can := case when p.email is not null then 'email' else 'sms' end;
  dest := case when p.email is not null then privado.mascarar_email(p.email) else privado.mascarar_tel(p.telefone) end;
  insert into public.codigos_aceite(oportunidade_id, ies_id, codigo_hash, canal, destino_mascarado, modo, expira_em)
  values (p_op, o.ies_id, encode(sha256(convert_to(p_op::text || ':' || cod, 'UTF8')), 'hex'), can, dest, 'simulacao', now() + interval '15 minutes')
  on conflict (oportunidade_id) do update set codigo_hash = excluded.codigo_hash, canal = excluded.canal, destino_mascarado = excluded.destino_mascarado,
    modo = excluded.modo, expira_em = excluded.expira_em, tentativas = 0, criado_em = now();
  insert into public.mensagens(ies_id, oportunidade_id, canal, destino_mascarado, corpo, status, motivo)
  values (o.ies_id, p_op, can, dest, 'Seu código de confirmação da matrícula é ******. Ele vale por 15 minutos. Se não foi você, ignore esta mensagem.',
          'simulada', 'Modo simulação: integração de ' || can || ' desligada; código exibido no portal');
  perform privado.auditar(o.ies_id, 'matricula.codigo', 'oportunidade', p_op::text, jsonb_build_object('canal', can, 'modo', 'simulacao'));
  return jsonb_build_object('canal', can, 'destino', dest, 'expira_em', now() + interval '15 minutes', 'modo', 'simulacao', 'codigo_simulacao', cod,
    'aviso', 'Modo simulação: o envio de ' || case when can = 'email' then 'e-mail' else 'SMS' end ||
             ' está desligado, por isso o código aparece aqui. Com a integração ativa, ele será enviado para ' || dest || ' e não aparecerá na tela.');
end $$;

-- ---------------------------------------------------------------- portal: aceite reforçado
drop function if exists public.rpc_publico_aceitar_matricula(text, bigint, int, text);
create or replace function public.rpc_publico_aceitar_matricula(p_token text, p_op bigint, p_dados jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.pessoas; o public.oportunidades; pr public.propostas; k public.contratos_modelo; ca public.codigos_aceite; i public.ies; c public.cursos;
  cpf text := regexp_replace(coalesce(p_dados->>'cpf', ''), '\D', '', 'g');
  nasc date; idade int; menor boolean; r jsonb := p_dados->'responsavel';
  r_cpf text; r_nasc date; ev jsonb; ev_hash text; agora timestamptz := now(); k_hash text;
begin
  p := privado.portal_pessoa(p_token);
  perform privado.aceite_elegivel(p, p_op);
  select * into o from public.oportunidades where id = p_op;
  select * into pr from public.propostas where oportunidade_id = p_op and status = 'aprovada' order by id desc limit 1;
  select * into k from public.contratos_modelo where ies_id = o.ies_id and ativo;
  if (p_dados->>'contrato_versao')::int is distinct from k.versao then
    raise exception 'O contrato foi atualizado: leia a versão vigente antes de aceitar' using errcode = '22023'; end if;
  if (p_dados->>'proposta_id')::bigint is distinct from pr.id then
    raise exception 'As condições da proposta mudaram: confira os valores antes de aceitar' using errcode = '22023'; end if;
  if not (coalesce((p_dados->>'li_contrato')::boolean, false) and coalesce((p_dados->>'concordo_condicoes')::boolean, false)
          and coalesce((p_dados->>'ciente_arrependimento')::boolean, false)) then
    raise exception 'Marque as três declarações para aceitar' using errcode = '22023'; end if;
  if privado.nome_norm(p_dados->>'nome') <> privado.nome_norm(p.nome) then
    raise exception 'Digite o nome completo do candidato exatamente como no cadastro' using errcode = '22023'; end if;
  if not privado.cpf_valido(cpf) then raise exception 'CPF do candidato inválido' using errcode = '22023'; end if;
  begin nasc := (p_dados->>'nascimento')::date; exception when others then nasc := null; end;
  if nasc is null then raise exception 'Informe a data de nascimento do candidato' using errcode = '22023'; end if;
  idade := extract(year from age(current_date, nasc))::int;
  if idade < 14 or idade > 100 then raise exception 'Data de nascimento fora do esperado: fale com a equipe da instituição' using errcode = '22023'; end if;
  menor := idade < 18;
  if menor then
    if r is null or jsonb_typeof(r) <> 'object' then
      raise exception 'Candidato menor de 18 anos: o aceite exige o representante legal' using errcode = '22023'; end if;
    r_cpf := regexp_replace(coalesce(r->>'cpf', ''), '\D', '', 'g');
    begin r_nasc := (r->>'nascimento')::date; exception when others then r_nasc := null; end;
    if length(privado.nome_norm(r->>'nome')) < 5 or position(' ' in privado.nome_norm(r->>'nome')) = 0 then
      raise exception 'Informe o nome completo do representante legal' using errcode = '22023'; end if;
    if not privado.cpf_valido(r_cpf) or r_cpf = cpf then raise exception 'CPF do representante legal inválido' using errcode = '22023'; end if;
    if r_nasc is null or extract(year from age(current_date, r_nasc)) < 18 then
      raise exception 'O representante legal deve ser maior de 18 anos' using errcode = '22023'; end if;
    if coalesce(r->>'vinculo', '') not in ('mae','pai','tutor') then raise exception 'Informe o vínculo do representante legal' using errcode = '22023'; end if;
    if not coalesce((r->>'declaro')::boolean, false) then
      raise exception 'O representante legal precisa declarar que representa ou assiste o candidato' using errcode = '22023'; end if;
  end if;

  -- código de confirmação (erro de código não desfaz a contagem de tentativas: devolve em vez de lançar)
  select * into ca from public.codigos_aceite where oportunidade_id = p_op for update;
  if not found or ca.expira_em < now() then raise exception 'Código expirado ou não solicitado: peça um novo código' using errcode = '22023'; end if;
  if ca.tentativas >= 5 then raise exception 'Muitas tentativas: peça um novo código' using errcode = '22023'; end if;
  if ca.codigo_hash <> encode(sha256(convert_to(p_op::text || ':' || coalesce(trim(p_dados->>'codigo'), ''), 'UTF8')), 'hex') then
    update public.codigos_aceite set tentativas = tentativas + 1 where oportunidade_id = p_op;
    return jsonb_build_object('aceito', false, 'erro', 'Código incorreto', 'tentativas_restantes', 4 - ca.tentativas);
  end if;

  select * into i from public.ies where id = o.ies_id;
  select * into c from public.cursos where id = o.curso_id;
  k_hash := encode(sha256(convert_to(k.texto, 'UTF8')), 'hex');
  ev := jsonb_build_object(
    'procedimento', 'aceite-v2',
    'instituicao', jsonb_build_object('id', i.id, 'nome', i.nome),
    'matricula', jsonb_build_object('oportunidade_id', o.id, 'curso', c.nome || ' · ' || c.turno, 'coorte', o.coorte),
    'candidato', jsonb_build_object('nome', p.nome, 'cpf', cpf, 'nascimento', nasc::text, 'menor_de_18', menor),
    'representante_legal', case when menor then jsonb_build_object('nome', trim(regexp_replace(r->>'nome', '\s+', ' ', 'g')), 'cpf', r_cpf,
                             'nascimento', r_nasc::text, 'vinculo', r->>'vinculo', 'declarou_representar_ou_assistir', true) end,
    'contrato', jsonb_build_object('versao', k.versao, 'sha256', k_hash),
    'condicoes', jsonb_build_object('proposta_id', pr.id, 'mensalidade_centavos', pr.mensalidade_centavos, 'desconto_pct', pr.desconto_pct,
                   'valor_final_centavos', pr.valor_final_centavos, 'validade', privado.utc(pr.validade)),
    'declaracoes', jsonb_build_object('li_o_contrato', true, 'concordo_com_as_condicoes', true, 'ciente_do_prazo_de_arrependimento', true),
    'confirmacao', jsonb_build_object('canal', ca.canal, 'destino', ca.destino_mascarado, 'modo', ca.modo, 'codigo_conferido', true),
    'origem_hash', privado.origem_hash(),
    'aceito_em', privado.utc(agora),
    'arrependimento_ate', privado.utc(agora + interval '7 days'));
  ev_hash := encode(sha256(convert_to(ev::text, 'UTF8')), 'hex');

  insert into public.aceites_matricula(ies_id, oportunidade_id, proposta_id, contrato_id, contrato_hash, nome_confirmado, origem_hash, aceito_em,
      cpf_candidato, nascimento_candidato, menor, responsavel_nome, responsavel_cpf, responsavel_nascimento, responsavel_vinculo,
      confirmacao_canal, confirmacao_destino, confirmacao_modo, evidencia, evidencia_hash, arrependimento_ate)
  values (o.ies_id, o.id, pr.id, k.id, k_hash, trim(p_dados->>'nome'), privado.origem_hash(), agora,
      cpf, nasc, menor, case when menor then trim(regexp_replace(r->>'nome', '\s+', ' ', 'g')) end, case when menor then r_cpf end,
      case when menor then r_nasc end, case when menor then r->>'vinculo' end,
      ca.canal, ca.destino_mascarado, ca.modo, ev, ev_hash, agora + interval '7 days');
  delete from public.codigos_aceite where oportunidade_id = p_op;
  update public.propostas set status = 'aceita' where id = pr.id;
  update public.oportunidades set etapa = 'matricula_comercial', matricula_comercial_em = now(), versao = versao + 1, atualizado_em = now() where id = o.id;
  perform privado.auditar(o.ies_id, 'proposta.aceitar', 'oportunidade', o.id::text, jsonb_build_object('proposta_id', pr.id, 'origem', 'portal'));
  perform privado.auditar(o.ies_id, 'oportunidade.etapa', 'oportunidade', o.id::text, jsonb_build_object('de', 'pre_matricula', 'para', 'matricula_comercial', 'motivo', 'Aceite eletrônico no portal'));
  perform privado.auditar(o.ies_id, 'matricula.aceite', 'oportunidade', o.id::text, jsonb_build_object('contrato_versao', k.versao, 'proposta_id', pr.id,
    'evidencia_sha256', ev_hash, 'menor_de_18', menor, 'confirmacao', ca.modo));
  return jsonb_build_object('aceito', true, 'contrato_versao', k.versao, 'evidencia_hash', ev_hash, 'arrependimento_ate', agora + interval '7 days',
    'proximo_passo', 'Validações documental, financeira e acadêmica pela instituição.');
end $$;

-- ---------------------------------------------------------------- comprovante
create or replace function privado.comprovante(p_op bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('instituicao', i.nome, 'curso', c.nome || ' · ' || c.turno, 'coorte', o.coorte, 'aceito_em', a.aceito_em,
    'procedimento', coalesce(a.evidencia->>'procedimento', 'aceite-v1'),
    'evidencia', a.evidencia, 'evidencia_texto', a.evidencia::text, 'evidencia_hash', a.evidencia_hash,
    'evidencia_integra', case when a.evidencia is null then null else encode(sha256(convert_to(a.evidencia::text, 'UTF8')), 'hex') = a.evidencia_hash end,
    'contrato_versao', k.versao, 'contrato_texto', k.texto, 'contrato_hash', a.contrato_hash,
    'contrato_integro', encode(sha256(convert_to(k.texto, 'UTF8')), 'hex') = a.contrato_hash,
    'nome_confirmado', a.nome_confirmado,
    'arrependimento_ate', coalesce(a.arrependimento_ate, a.aceito_em + interval '7 days'),
    'desistencia_em', a.desistencia_em, 'desistencia_motivo', a.desistencia_motivo)
  from public.aceites_matricula a join public.oportunidades o on o.id = a.oportunidade_id join public.ies i on i.id = a.ies_id
  join public.cursos c on c.id = o.curso_id join public.contratos_modelo k on k.id = a.contrato_id
  where a.oportunidade_id = p_op
$$;
revoke execute on function privado.comprovante(bigint) from public, anon, authenticated;

create or replace function public.rpc_publico_comprovante_aceite(p_token text, p_op bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.pessoas; r jsonb;
begin
  p := privado.portal_pessoa(p_token);
  if not exists (select 1 from public.oportunidades where id = p_op and pessoa_id = p.id) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  r := privado.comprovante(p_op);
  if r is null then perform privado.erro_http(404, 'P0002', 'Não há aceite registrado'); end if;
  return r;
end $$;

create or replace function public.rpc_comprovante_aceite(p_op bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; r jsonb;
begin
  perform privado.exigir_usuario();
  select * into o from public.oportunidades where id = p_op;
  if not found or not privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, (select papeis from public.matriz_permissoes where operacao = 'matricula.comprovante')) then
    perform privado.erro_http(404, 'P0002', 'Não encontrado');
  end if;
  r := privado.comprovante(p_op);
  if r is null then perform privado.erro_http(404, 'P0002', 'Não há aceite registrado'); end if;
  perform privado.auditar(o.ies_id, 'matricula.comprovante_ver', 'oportunidade', p_op::text, '{}'::jsonb);
  return r;
end $$;

-- ---------------------------------------------------------------- arrependimento (7 dias) pelo portal
create or replace function public.rpc_publico_desistir_matricula(p_token text, p_op bigint, p_motivo text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.pessoas; o public.oportunidades; a public.aceites_matricula; mot text := nullif(left(trim(coalesce(p_motivo, '')), 500), '');
begin
  p := privado.portal_pessoa(p_token);
  select * into o from public.oportunidades where id = p_op and pessoa_id = p.id for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  select * into a from public.aceites_matricula where oportunidade_id = p_op for update;
  if not found then raise exception 'Não há aceite de matrícula para desistir' using errcode = '22023'; end if;
  if a.desistencia_em is not null then raise exception 'A desistência já foi registrada' using errcode = '22023'; end if;
  if now() > coalesce(a.arrependimento_ate, a.aceito_em + interval '7 days') then
    raise exception 'O prazo de 7 dias para desistir pelo portal terminou: fale com a secretaria da instituição' using errcode = '22023'; end if;
  if o.etapa not in ('matricula_comercial','confirmado') then raise exception 'A matrícula não está ativa' using errcode = '22023'; end if;
  update public.aceites_matricula set desistencia_em = now(), desistencia_motivo = coalesce(mot, 'não informado') where id = a.id;
  update public.oportunidades set etapa = 'cancelado', cancelada_em = now(), versao = versao + 1, atualizado_em = now(),
    motivo_cancelamento = 'Arrependimento pelo portal no prazo de 7 dias' || coalesce(': ' || mot, '') where id = p_op;
  update public.tarefas set status = 'cancelada', encerrada_em = now(), resultado = 'matrícula cancelada (arrependimento)'
   where oportunidade_id = p_op and status = 'aberta';
  perform privado.auditar(o.ies_id, 'oportunidade.cancelar', 'oportunidade', p_op::text, jsonb_build_object('de', o.etapa, 'motivo', 'Arrependimento pelo portal'));
  perform privado.auditar(o.ies_id, 'matricula.arrependimento', 'oportunidade', p_op::text, jsonb_build_object('aceito_em', a.aceito_em, 'motivo', coalesce(mot, 'não informado')));
  return jsonb_build_object('cancelado', true,
    'mensagem', 'Desistência registrada e matrícula cancelada. A equipe da instituição tratará eventuais valores pagos.');
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.rpc_salvar_contrato(bigint, text), public.rpc_comprovante_aceite(bigint) to authenticated;
select privado.conceder_publico();

commit;
