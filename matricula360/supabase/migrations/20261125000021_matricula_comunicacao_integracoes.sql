-- Matrícula 360° — migração 21 (P4): matrícula online (L5), comunicação com réguas (L6) e integrações por arquivo (L8/L9).
--   * Aceite eletrônico pelo portal: proposta aprovada e vigente, contrato versionado, nome completo confirmado; evidências
--     (data, versão e hash do contrato, hash da origem). Leva pré-matrícula → matrícula comercial (transição oficial auditada).
--     [Não verificado] A suficiência jurídica do aceite como assinatura eletrônica simples deve ser validada pelo jurídico.
--   * Comunicação: modelos por gatilho; régua executada sob comando, em MODO SIMULAÇÃO (nada é enviado); bloqueio por opt-out,
--     anonimização e base legal; mensagem para cópia e envio manual pela equipe. Abertura/clique: N/D sem provedor.
--   * Integrações: registro com estado "desligada"; o gestor pode registrar pedido de ativação (não ativa nada).
--     Importação por planilha de vínculos acadêmicos e de custos de mídia, idempotente.
-- Idempotente.

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('contrato.gerir',     'Conversão e Matrículas',  'Publicar o modelo de contrato (nova versão a cada alteração)', array['gestor'], 'ies', 'rpc_salvar_contrato'),
  ('comunicacao.gerir',  'Marketing e Captação',    'Criar modelos e executar a régua (simulação)',                 array['gestor'], 'ies', 'rpc_executar_regua'),
  ('comunicacao.manual', 'CRM Educacional',         'Gerar mensagem para envio manual pela equipe',                 array['gestor','comercial'], 'curso', 'rpc_mensagem_manual'),
  ('integracao.gerir',   'Governança Institucional','Ver integrações e registrar pedido de ativação',              array['gestor'], 'ies', 'rpc_integracoes'),
  ('importacao.vinculos','Relacionamento Estudantil','Importar vínculos acadêmicos por planilha',                    array['gestor','secretaria'], 'curso', 'rpc_importar_vinculos'),
  ('importacao.custos',  'Marketing e Captação',    'Importar custos de mídia por planilha',                        array['gestor','financeiro'], 'ies', 'rpc_importar_custos')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

create table if not exists public.contratos_modelo (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  versao int not null,
  texto text not null check (length(texto) between 100 and 20000),
  ativo boolean not null default true,
  criado_por uuid references public.usuarios(id),
  criado_em timestamptz not null default now(),
  unique (ies_id, versao)
);
create unique index if not exists contrato_um_ativo on public.contratos_modelo(ies_id) where ativo;
create table if not exists public.aceites_matricula (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  oportunidade_id bigint not null unique references public.oportunidades(id),
  proposta_id bigint not null references public.propostas(id),
  contrato_id bigint not null references public.contratos_modelo(id),
  contrato_hash text not null,
  nome_confirmado text not null,
  origem_hash text not null,
  aceito_em timestamptz not null default now()
);
create table if not exists public.modelos_mensagem (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  nome text not null check (length(nome) between 3 and 100),
  canal text not null check (canal in ('email','whatsapp','sms')),
  gatilho text not null check (gatilho in ('etapa_novo','etapa_contato','etapa_inscrito','etapa_pre_matricula','documento_pendente','evento_inscrito','manual')),
  assunto text check (length(assunto) <= 150),
  corpo text not null check (length(corpo) between 10 and 2000),
  ativo boolean not null default true,
  criado_por uuid references public.usuarios(id),
  unique (ies_id, nome)
);
create table if not exists public.mensagens (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  oportunidade_id bigint not null references public.oportunidades(id),
  modelo_id bigint references public.modelos_mensagem(id),
  canal text not null,
  destino_mascarado text,
  corpo text not null,
  status text not null check (status in ('simulada','bloqueada','copiada_manual','enviada')),
  motivo text,
  criado_por uuid references public.usuarios(id),
  criado_em timestamptz not null default now()
);
create unique index if not exists mensagem_regua_unica on public.mensagens(oportunidade_id, modelo_id) where status in ('simulada','enviada');
create table if not exists public.integracoes (
  ies_id bigint not null references public.ies(id),
  tipo text not null check (tipo in ('email','sms','whatsapp','cobranca','assinatura_certificada','meta_ads','google_ads','tiktok_ads','sistema_academico','marketplace_bolsas')),
  status text not null default 'desligada' check (status in ('desligada','pedido_registrado')),
  pedido_por uuid references public.usuarios(id),
  pedido_em timestamptz,
  observacao text check (length(observacao) <= 1000),
  primary key (ies_id, tipo)
);
create index if not exists contratos_ies on public.contratos_modelo(ies_id);
create index if not exists contratos_criado on public.contratos_modelo(criado_por);
create index if not exists aceites_ies on public.aceites_matricula(ies_id);
create index if not exists aceites_proposta on public.aceites_matricula(proposta_id);
create index if not exists aceites_contrato on public.aceites_matricula(contrato_id);
create index if not exists modelos_ies on public.modelos_mensagem(ies_id);
create index if not exists modelos_criado on public.modelos_mensagem(criado_por);
create index if not exists mensagens_ies on public.mensagens(ies_id, criado_em);
create index if not exists mensagens_op on public.mensagens(oportunidade_id);
create index if not exists mensagens_modelo on public.mensagens(modelo_id);
create index if not exists mensagens_criado on public.mensagens(criado_por);
create index if not exists integracoes_pedido on public.integracoes(pedido_por);
alter table public.contratos_modelo enable row level security;
alter table public.aceites_matricula enable row level security;
alter table public.modelos_mensagem enable row level security;
alter table public.mensagens enable row level security;
alter table public.integracoes enable row level security;
revoke all on public.contratos_modelo, public.aceites_matricula, public.modelos_mensagem, public.mensagens, public.integracoes from anon, authenticated;

-- ---------------------------------------------------------------- matrícula online (L5)
create or replace function public.rpc_salvar_contrato(p_ies bigint, p_texto text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v int; v_id bigint;
begin
  perform privado.autorizar(p_ies, 'contrato.gerir');
  if length(coalesce(trim(p_texto), '')) not between 100 and 20000 then raise exception 'Contrato deve ter entre 100 e 20000 caracteres' using errcode = '22023'; end if;
  select coalesce(max(versao), 0) + 1 into v from public.contratos_modelo where ies_id = p_ies;
  update public.contratos_modelo set ativo = false where ies_id = p_ies and ativo;
  insert into public.contratos_modelo(ies_id, versao, texto, criado_por) values (p_ies, v, trim(p_texto), (select auth.uid())) returning id into v_id;
  perform privado.auditar(p_ies, 'contrato.publicar', 'ies', p_ies::text, jsonb_build_object('versao', v, 'hash', encode(sha256(convert_to(trim(p_texto), 'UTF8')), 'hex')));
  return jsonb_build_object('id', v_id, 'versao', v);
end $$;

create or replace function public.rpc_contratos(p_ies bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.autorizar(p_ies, 'contrato.gerir');
  return jsonb_build_object('aviso', '[Não verificado] A suficiência jurídica do aceite eletrônico simples para o contrato de prestação de serviços educacionais deve ser validada pelo jurídico da instituição.',
    'versoes', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'versao', c.versao, 'ativo', c.ativo, 'criado_em', c.criado_em, 'texto', c.texto,
       'aceites', (select count(*) from public.aceites_matricula a where a.contrato_id = c.id)) order by c.versao desc), '[]'::jsonb) from public.contratos_modelo c where c.ies_id = p_ies));
end $$;

-- Portal: o que falta para a matrícula online (proposta aprovada e vigente + contrato ativo).
create or replace function public.rpc_publico_portal_matricula(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.pessoas;
begin
  p := privado.portal_pessoa(p_token);
  return (select coalesce(jsonb_agg(jsonb_build_object('oportunidade_id', o.id, 'curso', c.nome || ' · ' || c.turno, 'coorte', o.coorte, 'etapa', o.etapa,
      'proposta', (select jsonb_build_object('id', x.id, 'mensalidade_centavos', x.mensalidade_centavos, 'desconto_pct', x.desconto_pct,
                     'valor_final_centavos', x.valor_final_centavos, 'validade', x.validade, 'status', x.status)
                   from public.propostas x where x.oportunidade_id = o.id and x.status in ('aprovada','aceita') order by x.id desc limit 1),
      'contrato', (select jsonb_build_object('versao', k.versao, 'texto', k.texto) from public.contratos_modelo k where k.ies_id = o.ies_id and k.ativo),
      'aceite', (select jsonb_build_object('aceito_em', a.aceito_em, 'contrato_versao', (select versao from public.contratos_modelo where id = a.contrato_id)) from public.aceites_matricula a where a.oportunidade_id = o.id),
      'pagamento', 'Integração de cobrança desligada: a instituição informará a forma de pagamento.') order by o.id), '[]'::jsonb)
    from public.oportunidades o join public.cursos c on c.id = o.curso_id where o.pessoa_id = p.id and o.etapa in ('pre_matricula','matricula_comercial','confirmado'));
end $$;

create or replace function public.rpc_publico_aceitar_matricula(p_token text, p_op bigint, p_contrato_versao int, p_nome text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.pessoas; o public.oportunidades; pr public.propostas; k public.contratos_modelo;
begin
  p := privado.portal_pessoa(p_token);
  select * into o from public.oportunidades where id = p_op and pessoa_id = p.id for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if o.etapa <> 'pre_matricula' then raise exception 'A matrícula online está disponível na etapa de pré-matrícula' using errcode = '22023'; end if;
  select * into pr from public.propostas where oportunidade_id = o.id and status = 'aprovada' order by id desc limit 1 for update;
  if not found then raise exception 'Não há proposta aprovada para aceitar' using errcode = '22023'; end if;
  if pr.validade < now() then raise exception 'A proposta expirou: fale com a equipe da instituição' using errcode = '22023'; end if;
  select * into k from public.contratos_modelo where ies_id = o.ies_id and ativo;
  if not found or k.versao <> p_contrato_versao then raise exception 'O contrato foi atualizado: leia a versão vigente antes de aceitar' using errcode = '22023'; end if;
  if lower(regexp_replace(trim(coalesce(p_nome, '')), '\s+', ' ', 'g')) <> lower(regexp_replace(trim(p.nome), '\s+', ' ', 'g')) then
    raise exception 'Digite seu nome completo exatamente como no cadastro' using errcode = '22023';
  end if;
  insert into public.aceites_matricula(ies_id, oportunidade_id, proposta_id, contrato_id, contrato_hash, nome_confirmado, origem_hash)
  values (o.ies_id, o.id, pr.id, k.id, encode(sha256(convert_to(k.texto, 'UTF8')), 'hex'), trim(p_nome), privado.origem_hash());
  update public.propostas set status = 'aceita' where id = pr.id;
  update public.oportunidades set etapa = 'matricula_comercial', matricula_comercial_em = now(), versao = versao + 1, atualizado_em = now() where id = o.id;
  perform privado.auditar(o.ies_id, 'proposta.aceitar', 'oportunidade', o.id::text, jsonb_build_object('proposta_id', pr.id, 'origem', 'portal'));
  perform privado.auditar(o.ies_id, 'oportunidade.etapa', 'oportunidade', o.id::text, jsonb_build_object('de', 'pre_matricula', 'para', 'matricula_comercial', 'motivo', 'Aceite eletrônico no portal'));
  perform privado.auditar(o.ies_id, 'matricula.aceite', 'oportunidade', o.id::text, jsonb_build_object('contrato_versao', k.versao, 'proposta_id', pr.id));
  return jsonb_build_object('aceito', true, 'contrato_versao', k.versao, 'proximo_passo', 'Validações documental, financeira e acadêmica pela instituição.');
exception when unique_violation then raise exception 'Matrícula já aceita' using errcode = '22023';
end $$;

-- ---------------------------------------------------------------- comunicação (L6) — simulação
create or replace function privado.render(p_corpo text, p_op bigint) returns text
language sql stable security definer set search_path = '' as $$
  select replace(replace(replace(p_corpo, '{{nome}}', split_part(p.nome, ' ', 1)), '{{curso}}', c.nome || ' · ' || c.turno), '{{instituicao}}', i.nome)
    from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id join public.cursos c on c.id = o.curso_id join public.ies i on i.id = o.ies_id where o.id = p_op;
$$;
revoke execute on function privado.render(text, bigint) from public, anon, authenticated;

-- Motivo de bloqueio do canal para a oportunidade (null = permitido).
create or replace function privado.bloqueio_canal(p_op bigint, p_canal text) returns text
language sql stable security definer set search_path = '' as $$
  select case when p.anonimizada_em is not null then 'Titular anonimizado'
              when p.base_legal not in ('consentimento','legitimo_interesse') and o.etapa in ('perdido','cancelado') then 'Base legal não permite contato após o encerramento'
              when p_canal = 'email' and (p.optout_email or p.email is null) then 'Opt-out ou sem e-mail'
              when p_canal = 'whatsapp' and (p.optout_whatsapp or p.telefone is null) then 'Opt-out ou sem telefone'
              when p_canal = 'sms' and (p.optout_telefone or p.telefone is null) then 'Opt-out ou sem telefone' end
    from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id where o.id = p_op;
$$;
revoke execute on function privado.bloqueio_canal(bigint, text) from public, anon, authenticated;

create or replace function public.rpc_salvar_modelo_mensagem(p_ies bigint, p_dados jsonb, p_id bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  perform privado.autorizar(p_ies, 'comunicacao.gerir');
  if p_id is null then
    insert into public.modelos_mensagem(ies_id, nome, canal, gatilho, assunto, corpo, criado_por)
    values (p_ies, trim(p_dados->>'nome'), p_dados->>'canal', p_dados->>'gatilho', nullif(trim(p_dados->>'assunto'), ''), trim(p_dados->>'corpo'), (select auth.uid())) returning id into v_id;
  else
    update public.modelos_mensagem set corpo = coalesce(trim(p_dados->>'corpo'), corpo), assunto = coalesce(nullif(trim(p_dados->>'assunto'), ''), assunto),
           ativo = coalesce((p_dados->>'ativo')::boolean, ativo) where id = p_id and ies_id = p_ies returning id into v_id;
    if v_id is null then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  end if;
  perform privado.auditar(p_ies, 'comunicacao.modelo', 'ies', p_ies::text, jsonb_build_object('modelo_id', v_id));
  return jsonb_build_object('id', v_id);
exception
  when unique_violation then perform privado.erro_http(409, '23505', 'Já existe modelo com este nome');
  when check_violation or not_null_violation then raise exception 'Modelo inválido: nome, canal, gatilho e texto (10 a 2000 caracteres)' using errcode = '22023';
end $$;

-- Régua (simulação): gera uma mensagem por oportunidade elegível e modelo ativo; nunca duplica; nada sai do sistema.
create or replace function public.rpc_executar_regua(p_ies bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare m public.modelos_mensagem; o record; bloq text; n_sim int := 0; n_bloq int := 0;
begin
  perform privado.autorizar(p_ies, 'comunicacao.gerir');
  for m in select * from public.modelos_mensagem where ies_id = p_ies and ativo and gatilho <> 'manual' loop
    for o in select x.id from public.oportunidades x where x.ies_id = p_ies
               and ((m.gatilho like 'etapa_%' and x.etapa = substr(m.gatilho, 7))
                 or (m.gatilho = 'documento_pendente' and x.etapa in ('pre_matricula','matricula_comercial') and not privado.checklist_completo(x.id))
                 or (m.gatilho = 'evento_inscrito' and exists (select 1 from public.inscricoes_evento i join public.eventos e on e.id = i.evento_id
                                                                where i.oportunidade_id = x.id and i.status = 'inscrito' and e.inicio > now())))
               and not exists (select 1 from public.mensagens g where g.oportunidade_id = x.id and g.modelo_id = m.id) limit 500 loop
      bloq := privado.bloqueio_canal(o.id, m.canal);
      insert into public.mensagens(ies_id, oportunidade_id, modelo_id, canal, destino_mascarado, corpo, status, motivo, criado_por)
      select p_ies, o.id, m.id, m.canal, case when m.canal = 'email' then privado.mascarar_email(p.email) else privado.mascarar_tel(p.telefone) end,
             privado.render(m.corpo, o.id), case when bloq is null then 'simulada' else 'bloqueada' end,
             coalesce(bloq, 'Modo simulação: integração de ' || m.canal || ' desligada'), (select auth.uid())
        from public.oportunidades x join public.pessoas p on p.id = x.pessoa_id where x.id = o.id;
      if bloq is null then n_sim := n_sim + 1; else n_bloq := n_bloq + 1; end if;
    end loop;
  end loop;
  perform privado.auditar(p_ies, 'comunicacao.regua', 'ies', p_ies::text, jsonb_build_object('simuladas', n_sim, 'bloqueadas', n_bloq));
  return jsonb_build_object('simuladas', n_sim, 'bloqueadas', n_bloq, 'enviadas', 0, 'modo', 'simulação');
end $$;

-- Mensagem para envio manual pela equipe (pelo próprio canal da pessoa atendente). Registra a cópia.
create or replace function public.rpc_mensagem_manual(p_op bigint, p_modelo bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; m public.modelos_mensagem; bloq text; txt text;
begin
  o := privado.carregar_op(p_op, (select papeis from public.matriz_permissoes where operacao = 'comunicacao.manual'));
  select * into m from public.modelos_mensagem where id = p_modelo and ies_id = o.ies_id and ativo;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  bloq := privado.bloqueio_canal(p_op, m.canal);
  if bloq is not null then raise exception 'Contato bloqueado: %', bloq using errcode = '22023'; end if;
  txt := privado.render(m.corpo, p_op);
  insert into public.mensagens(ies_id, oportunidade_id, modelo_id, canal, corpo, status, motivo, criado_por)
  values (o.ies_id, p_op, m.id, m.canal, txt, 'copiada_manual', 'Texto gerado para envio manual pela equipe', (select auth.uid()));
  return jsonb_build_object('canal', m.canal, 'assunto', m.assunto, 'texto', txt);
end $$;

create or replace function public.rpc_comunicacao(p_ies bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.autorizar(p_ies, 'comunicacao.manual');
  return jsonb_build_object('modo', 'simulação', 'pode_gerir', privado.pode(p_ies, 'comunicacao.gerir'),
    'aviso', 'Envio externo desligado: a régua só simula. Abertura e clique ficam indisponíveis (N/D) até haver provedor autorizado.',
    'modelos', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'nome', m.nome, 'canal', m.canal, 'gatilho', m.gatilho, 'assunto', m.assunto, 'corpo', m.corpo, 'ativo', m.ativo,
       'simuladas', (select count(*) from public.mensagens g where g.modelo_id = m.id and g.status = 'simulada'),
       'bloqueadas', (select count(*) from public.mensagens g where g.modelo_id = m.id and g.status = 'bloqueada'),
       'copiadas', (select count(*) from public.mensagens g where g.modelo_id = m.id and g.status = 'copiada_manual'),
       'abertura', null, 'clique', null) order by m.nome), '[]'::jsonb) from public.modelos_mensagem m where m.ies_id = p_ies),
    'recentes', case when privado.pode(p_ies, 'comunicacao.gerir') then (select coalesce(jsonb_agg(x.j), '[]'::jsonb) from (
       select jsonb_build_object('id', g.id, 'canal', g.canal, 'destino', g.destino_mascarado, 'status', g.status, 'motivo', g.motivo, 'em', g.criado_em,
              'nome', p.nome, 'corpo', g.corpo) as j
         from public.mensagens g join public.oportunidades o on o.id = g.oportunidade_id join public.pessoas p on p.id = o.pessoa_id
        where g.ies_id = p_ies order by g.criado_em desc limit 50) x) end);
end $$;

-- ---------------------------------------------------------------- integrações e importações (L8/L9)
create or replace function public.rpc_integracoes(p_ies bigint, p_tipo text default null, p_observacao text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform privado.autorizar(p_ies, 'integracao.gerir');
  insert into public.integracoes(ies_id, tipo)
    select p_ies, t from unnest(array['email','sms','whatsapp','cobranca','assinatura_certificada','meta_ads','google_ads','tiktok_ads','sistema_academico','marketplace_bolsas']) t
  on conflict do nothing;
  if p_tipo is not null then
    if length(coalesce(trim(p_observacao), '')) < 10 then raise exception 'Descreva o fornecedor e a finalidade do pedido' using errcode = '22023'; end if;
    update public.integracoes set status = 'pedido_registrado', pedido_por = (select auth.uid()), pedido_em = now(), observacao = trim(p_observacao)
     where ies_id = p_ies and tipo = p_tipo;
    if not found then raise exception 'Integração inválida' using errcode = '22023'; end if;
    perform privado.auditar(p_ies, 'integracao.pedido', 'ies', p_ies::text, jsonb_build_object('tipo', p_tipo));
  end if;
  return jsonb_build_object('aviso', 'Nenhuma integração externa está ativa. Ativar exige decisão do responsável, fornecedor, contrato e credenciais. Enquanto isso, use as importações por planilha.',
    'itens', (select jsonb_agg(jsonb_build_object('tipo', i.tipo, 'status', i.status, 'pedido_por', privado.nome_usuario(i.pedido_por), 'pedido_em', i.pedido_em, 'observacao', i.observacao) order by i.tipo)
              from public.integracoes i where i.ies_id = p_ies));
end $$;

-- Planilha de vínculos (exportada do sistema acadêmico): linhas {oportunidade_id | email, marco, situacao, data, observacao}.
create or replace function public.rpc_importar_vinculos(p_ies bigint, p_linhas jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare l jsonb; i int := 0; ok int := 0; rej jsonb := '[]'::jsonb; v_op bigint;
begin
  perform privado.autorizar(p_ies, 'importacao.vinculos');
  if jsonb_typeof(p_linhas) <> 'array' or jsonb_array_length(p_linhas) not between 1 and 2000 then raise exception 'Envie de 1 a 2000 linhas' using errcode = '22023'; end if;
  for l in select * from jsonb_array_elements(p_linhas) loop
    i := i + 1;
    begin
      v_op := coalesce(nullif(l->>'oportunidade_id', '')::bigint,
        (select o.id from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id
          where o.ies_id = p_ies and o.etapa = 'confirmado' and p.email = lower(trim(l->>'email')) order by o.confirmada_em desc limit 1));
      if v_op is null or not exists (select 1 from public.oportunidades where id = v_op and ies_id = p_ies) then raise exception 'Ingressante não encontrado'; end if;
      perform public.rpc_registrar_vinculo(v_op, l->>'marco', l->>'situacao', (l->>'data')::date, coalesce(nullif(l->>'observacao', ''), 'Importado do sistema acadêmico'));
      update public.vinculos set fonte = 'sistema_academico' where oportunidade_id = v_op and marco = l->>'marco';
      ok := ok + 1;
    exception when others then
      rej := rej || jsonb_build_object('linha', i, 'motivo', case when sqlstate = 'PGRST' then sqlerrm::jsonb->>'message' else sqlerrm end);
    end;
  end loop;
  perform privado.auditar(p_ies, 'importacao.vinculos', 'ies', p_ies::text, jsonb_build_object('importadas', ok, 'rejeitadas', jsonb_array_length(rej)));
  return jsonb_build_object('importadas', ok, 'rejeitadas', rej);
end $$;

-- Planilha de custos (exportada das plataformas de mídia): linhas {campanha, data, valor_centavos, descricao}. Reimportar não duplica.
create or replace function public.rpc_importar_custos(p_ies bigint, p_linhas jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare l jsonb; i int := 0; ok int := 0; rep int := 0; rej jsonb := '[]'::jsonb; v_camp bigint; r jsonb;
begin
  perform privado.autorizar(p_ies, 'importacao.custos');
  if jsonb_typeof(p_linhas) <> 'array' or jsonb_array_length(p_linhas) not between 1 and 2000 then raise exception 'Envie de 1 a 2000 linhas' using errcode = '22023'; end if;
  for l in select * from jsonb_array_elements(p_linhas) loop
    i := i + 1;
    begin
      select id into v_camp from public.campanhas where ies_id = p_ies and codigo = lower(trim(l->>'campanha'));
      if v_camp is null then raise exception 'Campanha não encontrada: %', l->>'campanha'; end if;
      r := public.rpc_lancar_custo(v_camp, (l->>'data')::date, (l->>'valor_centavos')::bigint, coalesce(nullif(trim(l->>'descricao'), ''), 'Importação de mídia'),
                                   'imp-' || encode(sha256(convert_to(l::text, 'UTF8')), 'hex'));
      if (r->>'repeticao')::boolean then rep := rep + 1; else ok := ok + 1; end if;
    exception when others then
      rej := rej || jsonb_build_object('linha', i, 'motivo', case when sqlstate = 'PGRST' then sqlerrm::jsonb->>'message' else sqlerrm end);
    end;
  end loop;
  perform privado.auditar(p_ies, 'importacao.custos', 'ies', p_ies::text, jsonb_build_object('importadas', ok, 'repetidas', rep, 'rejeitadas', jsonb_array_length(rej)));
  return jsonb_build_object('importadas', ok, 'repetidas', rep, 'rejeitadas', rej);
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.rpc_salvar_contrato(bigint, text), public.rpc_contratos(bigint), public.rpc_salvar_modelo_mensagem(bigint, jsonb, bigint),
  public.rpc_executar_regua(bigint), public.rpc_mensagem_manual(bigint, bigint), public.rpc_comunicacao(bigint), public.rpc_integracoes(bigint, text, text),
  public.rpc_importar_vinculos(bigint, jsonb), public.rpc_importar_custos(bigint, jsonb)
to authenticated;
select privado.conceder_publico();
