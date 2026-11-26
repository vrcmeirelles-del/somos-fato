-- Matrícula 360° — migração 18 (P4): captação pública (L1), portal do candidato (L2) e direitos do titular.
--   * Formulário público por instituição/campanha: o lead se cadastra sozinho, com consentimento LGPD versionado.
--   * Proteções sem serviço externo: campo-isca, tempo mínimo de preenchimento, limites por origem (IP com hash
--     diário, sem guardar IP), por formulário e por e-mail; respostas que não revelam se a pessoa já existe.
--   * Portal do candidato por link secreto (token de 244 bits, só o hash fica no banco), sem envio de e-mail:
--     o link aparece ao concluir a inscrição ou é gerado pela equipe para envio manual. Validade de 90 dias.
--   * Titular: vê seus dados, faz opt-out por canal e solicita acesso, correção ou eliminação (fila do gestor).
--   * Acesso anônimo SOMENTE às funções rpc_publico_*; privado.conceder_publico() reaplica isso ao fim de cada migração.
-- Idempotente.

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('formulario.gerir', 'Marketing e Captação', 'Criar e publicar formulários públicos de captação', array['gestor'], 'ies', 'rpc_salvar_formulario'),
  ('portal.acesso',    'CRM Educacional',      'Gerar link de acesso do candidato ao portal (envio manual)', array['gestor','comercial'], 'curso', 'rpc_gerar_acesso_portal'),
  ('titular.tratar',   'Governança Institucional', 'Tratar solicitações de titulares (LGPD)', array['gestor'], 'ies', 'rpc_tratar_solicitacao')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

alter table public.pessoas add column if not exists consentimento_versao int;
alter table public.pessoas add column if not exists consentimento_em timestamptz;
alter table public.pessoas add column if not exists consentimento_hash text;

create table if not exists public.formularios (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{3,60}$'),
  titulo text not null check (length(titulo) between 3 and 120),
  descricao text check (length(descricao) <= 1000),
  cursos bigint[] not null check (cardinality(cursos) between 1 and 100),
  coorte text not null check (coorte ~ '^\d{4}\.[12]$'),
  forma_ingresso text not null default 'vestibular' check (forma_ingresso in ('vestibular','enem','transferencia','segunda_graduacao','reingresso','indicacao','convenio','visita_escolar','evento','pos_graduacao')),
  campanha_id bigint references public.campanhas(id),
  texto_consentimento text not null check (length(texto_consentimento) between 40 and 3000),
  versao_consentimento int not null default 1,
  pede_telefone boolean not null default true,
  ativo boolean not null default true,
  criado_por uuid references public.usuarios(id),
  criado_em timestamptz not null default now()
);
create table if not exists public.inscricoes_publicas (
  id bigint generated always as identity primary key,
  formulario_id bigint not null references public.formularios(id),
  ies_id bigint not null references public.ies(id),
  origem_hash text not null,
  email_hash text,
  resultado text not null check (resultado in ('criada','duplicada','isca','rapida','limite','invalida')),
  oportunidade_id bigint references public.oportunidades(id),
  criado_em timestamptz not null default now()
);
create table if not exists public.acessos_candidato (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  pessoa_id bigint not null references public.pessoas(id),
  token_hash text not null unique,
  criado_por uuid references public.usuarios(id),
  criado_em timestamptz not null default now(),
  expira_em timestamptz not null default now() + interval '90 days',
  revogado_em timestamptz,
  ultimo_uso timestamptz
);
create table if not exists public.solicitacoes_titular (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  pessoa_id bigint not null references public.pessoas(id),
  tipo text not null check (tipo in ('acesso','correcao','eliminacao')),
  detalhe text check (length(detalhe) <= 1000),
  status text not null default 'aberta' check (status in ('aberta','atendida','recusada')),
  resposta text check (length(resposta) <= 1000),
  tratado_por uuid references public.usuarios(id),
  criado_em timestamptz not null default now(),
  tratado_em timestamptz
);
create index if not exists formularios_ies on public.formularios(ies_id);
create index if not exists formularios_campanha on public.formularios(campanha_id);
create index if not exists formularios_criado on public.formularios(criado_por);
create index if not exists inscricoes_publicas_form on public.inscricoes_publicas(formulario_id, criado_em);
create index if not exists inscricoes_publicas_origem on public.inscricoes_publicas(origem_hash, criado_em);
create index if not exists inscricoes_publicas_email on public.inscricoes_publicas(email_hash, criado_em);
create index if not exists inscricoes_publicas_ies on public.inscricoes_publicas(ies_id);
create index if not exists inscricoes_publicas_op on public.inscricoes_publicas(oportunidade_id);
create index if not exists acessos_pessoa on public.acessos_candidato(pessoa_id);
create index if not exists acessos_ies on public.acessos_candidato(ies_id);
create index if not exists acessos_criado on public.acessos_candidato(criado_por);
create index if not exists solicitacoes_ies on public.solicitacoes_titular(ies_id);
create index if not exists solicitacoes_pessoa on public.solicitacoes_titular(pessoa_id);
create index if not exists solicitacoes_tratado on public.solicitacoes_titular(tratado_por);

alter table public.formularios enable row level security;
alter table public.inscricoes_publicas enable row level security;
alter table public.acessos_candidato enable row level security;
alter table public.solicitacoes_titular enable row level security;
revoke all on public.formularios, public.inscricoes_publicas, public.acessos_candidato, public.solicitacoes_titular from anon, authenticated;

-- ---------------------------------------------------------------- utilitários
create or replace function privado.conceder_publico() returns void
language plpgsql security definer set search_path = '' as $$
declare f record;
begin
  for f in select p.oid::regprocedure as assinatura from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname like 'rpc\_publico\_%' loop
    execute format('grant execute on function %s to anon, authenticated', f.assinatura);
  end loop;
end $$;
revoke execute on function privado.conceder_publico() from public, anon, authenticated;

-- Hash diário da origem (IP do proxy) para limitar abuso sem guardar o IP.
create or replace function privado.origem_hash() returns text
language sql stable set search_path = '' as $$
  select encode(sha256(convert_to(coalesce(split_part(nullif(current_setting('request.headers', true), '')::json->>'x-forwarded-for', ',', 1), 'local')
                                  || '|m360|' || current_date::text, 'UTF8')), 'hex');
$$;
revoke execute on function privado.origem_hash() from public, anon, authenticated;

create or replace function privado.novo_token() returns text
language sql volatile set search_path = '' as $$
  select replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
$$;
revoke execute on function privado.novo_token() from public, anon, authenticated;

create or replace function privado.hash_token(p_token text) returns text
language sql immutable set search_path = '' as $$ select encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex'); $$;
revoke execute on function privado.hash_token(text) from public, anon, authenticated;

-- Pessoa dona de um token válido (atualiza o último uso). Token inválido: 404 genérico.
create or replace function privado.portal_pessoa(p_token text) returns public.pessoas
language plpgsql security definer set search_path = '' as $$
declare a public.acessos_candidato; p public.pessoas;
begin
  if p_token is null or length(p_token) <> 64 then perform privado.erro_http(404, 'P0002', 'Link inválido ou expirado'); end if;
  select * into a from public.acessos_candidato where token_hash = privado.hash_token(p_token) for update;
  if not found or a.revogado_em is not null or a.expira_em < now() then perform privado.erro_http(404, 'P0002', 'Link inválido ou expirado'); end if;
  update public.acessos_candidato set ultimo_uso = now() where id = a.id;
  select * into p from public.pessoas where id = a.pessoa_id;
  if p.anonimizada_em is not null then perform privado.erro_http(404, 'P0002', 'Link inválido ou expirado'); end if;
  return p;
end $$;
revoke execute on function privado.portal_pessoa(text) from public, anon, authenticated;

create or replace function privado.emitir_acesso(p_pessoa bigint, p_por uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare t text := privado.novo_token(); v_ies bigint;
begin
  select ies_id into v_ies from public.pessoas where id = p_pessoa;
  update public.acessos_candidato set revogado_em = now() where pessoa_id = p_pessoa and revogado_em is null;
  insert into public.acessos_candidato(ies_id, pessoa_id, token_hash, criado_por) values (v_ies, p_pessoa, privado.hash_token(t), p_por);
  return t;
end $$;
revoke execute on function privado.emitir_acesso(bigint, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- público (anon): formulário
create or replace function public.rpc_publico_formulario(p_slug text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare f public.formularios;
begin
  select * into f from public.formularios where slug = lower(p_slug) and ativo;
  if not found or not exists (select 1 from public.ies where id = f.ies_id and status = 'ativa') then perform privado.erro_http(404, 'P0002', 'Formulário não encontrado'); end if;
  return jsonb_build_object('titulo', f.titulo, 'descricao', f.descricao, 'instituicao', (select nome from public.ies where id = f.ies_id),
    'pede_telefone', f.pede_telefone, 'texto_consentimento', f.texto_consentimento, 'versao_consentimento', f.versao_consentimento,
    'cursos', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.nome, 'turno', c.turno, 'modalidade', c.modalidade, 'campus', cp.nome) order by c.nome, c.turno), '[]'::jsonb)
               from public.cursos c join public.campus cp on cp.id = c.campus_id where c.id = any (f.cursos) and c.ies_id = f.ies_id));
end $$;

-- Inscrição pública. Resposta sempre neutra (não revela se a pessoa já existe); link do portal só para cadastro novo.
create or replace function public.rpc_publico_inscrever(p_slug text, p_dados jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare f public.formularios; v_origem text := privado.origem_hash(); v_email text := nullif(lower(trim(p_dados->>'email')), '');
  v_tel text := nullif(regexp_replace(coalesce(p_dados->>'telefone', ''), '\D', '', 'g'), ''); v_curso bigint := nullif(p_dados->>'curso_id', '')::bigint;
  v_nome text := trim(coalesce(p_dados->>'nome', '')); v_pessoa public.pessoas; v_op public.oportunidades; v_resp uuid; v_canal text; v_sla int;
  v_ehash text; v_token text; neutra constant jsonb := jsonb_build_object('status', 'recebida', 'mensagem', 'Inscrição recebida. A equipe da instituição entrará em contato.');
begin
  select * into f from public.formularios where slug = lower(p_slug) and ativo;
  if not found or not exists (select 1 from public.ies where id = f.ies_id and status = 'ativa') then perform privado.erro_http(404, 'P0002', 'Formulário não encontrado'); end if;
  v_ehash := case when v_email is null then null else encode(sha256(convert_to(v_email, 'UTF8')), 'hex') end;
  -- campo-isca preenchido: robô. Resposta neutra, nada é criado.
  if coalesce(p_dados->>'site', '') <> '' then
    insert into public.inscricoes_publicas(formulario_id, ies_id, origem_hash, resultado) values (f.id, f.ies_id, v_origem, 'isca');
    return neutra;
  end if;
  if coalesce((p_dados->>'tempo_ms')::bigint, 0) < 3000 then
    insert into public.inscricoes_publicas(formulario_id, ies_id, origem_hash, resultado) values (f.id, f.ies_id, v_origem, 'rapida');
    raise exception 'Preenchimento muito rápido. Revise os dados e envie novamente.' using errcode = '22023';
  end if;
  if (select count(*) from public.inscricoes_publicas where origem_hash = v_origem and criado_em > now() - interval '10 minutes') >= 5
     or (select count(*) from public.inscricoes_publicas where formulario_id = f.id and criado_em > now() - interval '1 hour') >= 300
     or (v_ehash is not null and (select count(*) from public.inscricoes_publicas where email_hash = v_ehash and criado_em > now() - interval '1 day') >= 3) then
    insert into public.inscricoes_publicas(formulario_id, ies_id, origem_hash, email_hash, resultado) values (f.id, f.ies_id, v_origem, v_ehash, 'limite');
    perform privado.erro_http(429, '54000', 'Muitas tentativas. Aguarde alguns minutos.');
  end if;
  if coalesce((p_dados->>'aceite')::boolean, false) is not true or coalesce((p_dados->>'versao_consentimento')::int, -1) <> f.versao_consentimento then
    raise exception 'É preciso aceitar o termo de consentimento vigente' using errcode = '22023';
  end if;
  if length(v_nome) not between 3 and 120 then raise exception 'Informe seu nome completo' using errcode = '22023'; end if;
  if v_email is null or v_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' then raise exception 'Informe um e-mail válido' using errcode = '22023'; end if;
  if v_tel is not null and length(v_tel) not between 10 and 13 then raise exception 'Telefone inválido' using errcode = '22023'; end if;
  if v_curso is null or not (v_curso = any (f.cursos)) then raise exception 'Escolha um dos cursos do formulário' using errcode = '22023'; end if;

  select * into v_pessoa from public.pessoas where ies_id = f.ies_id and ((email is not null and email = v_email) or (v_tel is not null and telefone = v_tel)) limit 1 for update;
  if found then
    -- Pessoa já cadastrada: registra novo consentimento só se ela não tiver opt-out; não emite link (evita acesso por terceiros).
    update public.pessoas set consentimento_versao = f.versao_consentimento, consentimento_em = now(), consentimento_hash = encode(sha256(convert_to(f.texto_consentimento, 'UTF8')), 'hex')
     where id = v_pessoa.id and anonimizada_em is null;
    select * into v_op from public.oportunidades where pessoa_id = v_pessoa.id and curso_id = v_curso and coorte = f.coorte;
    if found then
      insert into public.inscricoes_publicas(formulario_id, ies_id, origem_hash, email_hash, resultado, oportunidade_id) values (f.id, f.ies_id, v_origem, v_ehash, 'duplicada', v_op.id);
      return neutra;
    end if;
  else
    insert into public.pessoas(ies_id, nome, email, telefone, base_legal, origem, consentimento_versao, consentimento_em, consentimento_hash)
    values (f.ies_id, v_nome, v_email, v_tel, 'consentimento', 'formulário: ' || f.titulo, f.versao_consentimento, now(),
            encode(sha256(convert_to(f.texto_consentimento, 'UTF8')), 'hex')) returning * into v_pessoa;
    v_token := privado.emitir_acesso(v_pessoa.id, null);
  end if;
  v_resp := privado.distribuir(f.ies_id, v_curso);
  insert into public.oportunidades(ies_id, curso_id, pessoa_id, forma_ingresso, coorte, responsavel_id, campanha_id)
  values (f.ies_id, v_curso, v_pessoa.id, f.forma_ingresso, f.coorte, v_resp, f.campanha_id) returning * into v_op;
  v_canal := case when not v_pessoa.optout_whatsapp and v_pessoa.telefone is not null then 'whatsapp'
                  when not v_pessoa.optout_email and v_pessoa.email is not null then 'email'
                  when not v_pessoa.optout_telefone and v_pessoa.telefone is not null then 'telefone' end;
  if v_canal is not null then
    select sla_horas into v_sla from public.ies where id = f.ies_id;
    insert into public.tarefas(ies_id, oportunidade_id, tipo, canal, responsavel_id, vence_em) values (f.ies_id, v_op.id, 'primeiro_contato', v_canal, v_resp, now() + make_interval(hours => v_sla));
  end if;
  perform privado.auditar(f.ies_id, 'oportunidade.criar', 'oportunidade', v_op.id::text,
    jsonb_build_object('curso_id', v_curso, 'forma_ingresso', f.forma_ingresso, 'coorte', f.coorte, 'origem', 'formulário público', 'formulario_id', f.id,
                       'campanha_id', f.campanha_id, 'consentimento_versao', f.versao_consentimento, 'responsavel_id', v_resp));
  insert into public.inscricoes_publicas(formulario_id, ies_id, origem_hash, email_hash, resultado, oportunidade_id) values (f.id, f.ies_id, v_origem, v_ehash, 'criada', v_op.id);
  return neutra || case when v_token is not null then jsonb_build_object('portal', v_token) else '{}'::jsonb end;
end $$;

-- ---------------------------------------------------------------- público (anon): portal do candidato
create or replace function privado.etapa_candidato(p_etapa text) returns text
language sql immutable set search_path = '' as $$
  select case p_etapa when 'novo' then 'Inscrição recebida' when 'contato' then 'Em atendimento' when 'inscrito' then 'Inscrito no processo seletivo'
    when 'pre_matricula' then 'Pré-matrícula' when 'matricula_comercial' then 'Matrícula em validação' when 'confirmado' then 'Matrícula confirmada'
    when 'perdido' then 'Inscrição encerrada' when 'cancelado' then 'Matrícula cancelada' end;
$$;
revoke execute on function privado.etapa_candidato(text) from public, anon, authenticated;

create or replace function public.rpc_publico_portal(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.pessoas;
begin
  p := privado.portal_pessoa(p_token);
  return jsonb_build_object('nome', p.nome, 'email', p.email, 'telefone', p.telefone, 'instituicao', (select nome from public.ies where id = p.ies_id),
    'optout', jsonb_build_object('email', p.optout_email, 'whatsapp', p.optout_whatsapp, 'telefone', p.optout_telefone),
    'consentimento', jsonb_build_object('versao', p.consentimento_versao, 'em', p.consentimento_em, 'base_legal', p.base_legal),
    'inscricoes', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'curso', c.nome, 'turno', c.turno, 'modalidade', c.modalidade, 'coorte', o.coorte,
        'situacao', privado.etapa_candidato(o.etapa), 'etapa', o.etapa,
        'validacoes', case when o.etapa in ('matricula_comercial','confirmado') then jsonb_build_object('documental', o.val_documental, 'financeira', o.val_financeira, 'academica', o.val_academica) end,
        'proposta', (select jsonb_build_object('valor_final_centavos', x.valor_final_centavos, 'validade', x.validade, 'status', x.status)
                       from public.propostas x where x.oportunidade_id = o.id and x.status in ('aprovada','aceita') order by x.id desc limit 1))
        order by o.criado_em desc), '[]'::jsonb)
      from public.oportunidades o join public.cursos c on c.id = o.curso_id where o.pessoa_id = p.id),
    'solicitacoes', (select coalesce(jsonb_agg(jsonb_build_object('tipo', s.tipo, 'status', s.status, 'resposta', s.resposta, 'criado_em', s.criado_em) order by s.criado_em desc), '[]'::jsonb)
      from public.solicitacoes_titular s where s.pessoa_id = p.id));
end $$;

create or replace function public.rpc_publico_portal_optout(p_token text, p_canal text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.pessoas; n int;
begin
  p := privado.portal_pessoa(p_token);
  if p_canal not in ('email','whatsapp','telefone') then raise exception 'Canal inválido' using errcode = '22023'; end if;
  update public.pessoas set optout_email = optout_email or p_canal = 'email', optout_whatsapp = optout_whatsapp or p_canal = 'whatsapp',
         optout_telefone = optout_telefone or p_canal = 'telefone' where id = p.id;
  update public.tarefas t set status = 'suprimida', resultado = 'opt-out pelo titular no portal', encerrada_em = now()
    from public.oportunidades o where o.id = t.oportunidade_id and o.pessoa_id = p.id and t.status = 'aberta' and t.canal = p_canal;
  get diagnostics n = row_count;
  perform privado.auditar(p.ies_id, 'pessoa.optout', 'pessoa', p.id::text, jsonb_build_object('canal', p_canal, 'tarefas_suprimidas', n, 'origem', 'portal do titular'));
  return jsonb_build_object('canal', p_canal, 'tarefas_suprimidas', n);
end $$;

create or replace function public.rpc_publico_portal_solicitar(p_token text, p_tipo text, p_detalhe text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.pessoas; v_id bigint;
begin
  p := privado.portal_pessoa(p_token);
  if p_tipo not in ('acesso','correcao','eliminacao') then raise exception 'Tipo inválido' using errcode = '22023'; end if;
  if exists (select 1 from public.solicitacoes_titular where pessoa_id = p.id and tipo = p_tipo and status = 'aberta') then
    raise exception 'Já existe solicitação deste tipo em análise' using errcode = '22023';
  end if;
  insert into public.solicitacoes_titular(ies_id, pessoa_id, tipo, detalhe) values (p.ies_id, p.id, p_tipo, nullif(trim(p_detalhe), '')) returning id into v_id;
  perform privado.auditar(p.ies_id, 'titular.solicitar', 'pessoa', p.id::text, jsonb_build_object('tipo', p_tipo, 'solicitacao_id', v_id));
  return jsonb_build_object('id', v_id, 'status', 'aberta');
end $$;

-- ---------------------------------------------------------------- equipe
create or replace function public.rpc_formularios(p_ies bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.autorizar(p_ies, 'formulario.gerir');
  return (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'slug', f.slug, 'titulo', f.titulo, 'descricao', f.descricao, 'cursos', f.cursos, 'coorte', f.coorte,
      'forma_ingresso', f.forma_ingresso, 'campanha_id', f.campanha_id, 'texto_consentimento', f.texto_consentimento, 'versao_consentimento', f.versao_consentimento,
      'pede_telefone', f.pede_telefone, 'ativo', f.ativo,
      'resultados', (select jsonb_object_agg(x.resultado, x.n) from (select resultado, count(*) as n from public.inscricoes_publicas where formulario_id = f.id group by 1) x)) order by f.criado_em desc), '[]'::jsonb)
    from public.formularios f where f.ies_id = p_ies);
end $$;

create or replace function public.rpc_salvar_formulario(p_ies bigint, p_dados jsonb, p_id bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id bigint; v_cursos bigint[]; v_camp bigint := nullif(p_dados->>'campanha_id', '')::bigint; atual public.formularios;
begin
  perform privado.autorizar(p_ies, 'formulario.gerir');
  if p_dados ? 'cursos' then
    v_cursos := array(select (jsonb_array_elements_text(p_dados->'cursos'))::bigint);
    if exists (select 1 from unnest(v_cursos) c where not exists (select 1 from public.cursos x where x.id = c and x.ies_id = p_ies)) then
      raise exception 'Curso não pertence à IES' using errcode = '22023';
    end if;
  end if;
  if v_camp is not null and not exists (select 1 from public.campanhas where id = v_camp and ies_id = p_ies) then raise exception 'Campanha não pertence à IES' using errcode = '22023'; end if;
  if p_id is null then
    insert into public.formularios(ies_id, slug, titulo, descricao, cursos, coorte, forma_ingresso, campanha_id, texto_consentimento, pede_telefone, criado_por)
    values (p_ies, lower(trim(p_dados->>'slug')), trim(p_dados->>'titulo'), nullif(trim(p_dados->>'descricao'), ''), v_cursos, p_dados->>'coorte',
            coalesce(p_dados->>'forma_ingresso', 'vestibular'), v_camp, trim(p_dados->>'texto_consentimento'), coalesce((p_dados->>'pede_telefone')::boolean, true), (select auth.uid()))
    returning id into v_id;
  else
    select * into atual from public.formularios where id = p_id and ies_id = p_ies for update;
    if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
    update public.formularios set titulo = coalesce(trim(p_dados->>'titulo'), titulo), descricao = coalesce(nullif(trim(p_dados->>'descricao'), ''), descricao),
      cursos = coalesce(v_cursos, cursos), coorte = coalesce(p_dados->>'coorte', coorte), forma_ingresso = coalesce(p_dados->>'forma_ingresso', forma_ingresso),
      campanha_id = case when p_dados ? 'campanha_id' then v_camp else campanha_id end, pede_telefone = coalesce((p_dados->>'pede_telefone')::boolean, pede_telefone),
      ativo = coalesce((p_dados->>'ativo')::boolean, ativo),
      -- termo alterado = nova versão de consentimento (o aceite anterior continua registrado com a versão antiga)
      texto_consentimento = coalesce(trim(p_dados->>'texto_consentimento'), texto_consentimento),
      versao_consentimento = versao_consentimento + case when p_dados ? 'texto_consentimento' and trim(p_dados->>'texto_consentimento') <> atual.texto_consentimento then 1 else 0 end
     where id = p_id returning id into v_id;
  end if;
  perform privado.auditar(p_ies, 'formulario.salvar', 'formulario', v_id::text, jsonb_build_object('ativo', p_dados->>'ativo'));
  return jsonb_build_object('id', v_id);
exception
  when unique_violation then perform privado.erro_http(409, '23505', 'Endereço (slug) já usado');
  when check_violation or not_null_violation then raise exception 'Formulário inválido: endereço (letras minúsculas, números e hífen), título, cursos, coorte e termo de consentimento (40+ caracteres)' using errcode = '22023';
end $$;

-- Link do portal para envio manual pela equipe (revoga o anterior). O token só aparece nesta resposta.
create or replace function public.rpc_gerar_acesso_portal(p_op bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; t text;
begin
  o := privado.carregar_op(p_op, (select papeis from public.matriz_permissoes where operacao = 'portal.acesso'));
  if exists (select 1 from public.pessoas where id = o.pessoa_id and anonimizada_em is not null) then raise exception 'Titular anonimizado' using errcode = '22023'; end if;
  t := privado.emitir_acesso(o.pessoa_id, (select auth.uid()));
  perform privado.auditar(o.ies_id, 'portal.gerar_acesso', 'oportunidade', p_op::text, jsonb_build_object('validade_dias', 90));
  return jsonb_build_object('token', t, 'validade_dias', 90);
end $$;

create or replace function public.rpc_solicitacoes_titular(p_ies bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.autorizar(p_ies, 'titular.tratar');
  return (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'tipo', s.tipo, 'detalhe', s.detalhe, 'status', s.status, 'resposta', s.resposta,
      'criado_em', s.criado_em, 'nome', p.nome, 'pessoa_id', s.pessoa_id, 'prazo', s.criado_em + interval '15 days',
      'oportunidade_id', (select min(o.id) from public.oportunidades o where o.pessoa_id = s.pessoa_id)) order by s.status = 'aberta' desc, s.criado_em), '[]'::jsonb)
    from public.solicitacoes_titular s join public.pessoas p on p.id = s.pessoa_id where s.ies_id = p_ies);
end $$;

create or replace function public.rpc_tratar_solicitacao(p_id bigint, p_status text, p_resposta text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare s public.solicitacoes_titular;
begin
  perform privado.exigir_usuario();
  select * into s from public.solicitacoes_titular where id = p_id for update;
  if not found or not privado.ve_ies(s.ies_id) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(s.ies_id, 'titular.tratar');
  if s.status <> 'aberta' then raise exception 'Solicitação já tratada' using errcode = '22023'; end if;
  if p_status not in ('atendida','recusada') or length(coalesce(trim(p_resposta), '')) < 10 then
    raise exception 'Informe a decisão e uma resposta ao titular (10+ caracteres)' using errcode = '22023';
  end if;
  update public.solicitacoes_titular set status = p_status, resposta = trim(p_resposta), tratado_por = (select auth.uid()), tratado_em = now() where id = p_id;
  perform privado.auditar(s.ies_id, 'titular.tratar', 'pessoa', s.pessoa_id::text, jsonb_build_object('solicitacao_id', p_id, 'tipo', s.tipo, 'status', p_status));
  return jsonb_build_object('id', p_id, 'status', p_status);
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.rpc_formularios(bigint), public.rpc_salvar_formulario(bigint, jsonb, bigint), public.rpc_gerar_acesso_portal(bigint),
  public.rpc_solicitacoes_titular(bigint), public.rpc_tratar_solicitacao(bigint, text, text)
to authenticated;
select privado.conceder_publico();
