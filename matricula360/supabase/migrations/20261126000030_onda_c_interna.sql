-- Matrícula 360° — migração 30 (Onda C, partes sem custo): conversas (L21), pendências financeiras (L13), polos e parceiros (L18) e egressos (L20).
--   * L21 Conversas: registro de mensagem RECEBIDA (WhatsApp, e-mail, ligação) colada pela equipe; fila "aguardando resposta" com tempo
--     desde a entrada; a resposta é a interação de saída já existente. Integração real com WhatsApp/SMS continua desligada (custo).
--   * L13 Financeiro: pendências por aluno e competência importadas por planilha (idempotente), negociação registrada, indicadores de
--     inadimplência e bloqueio da rematrícula SOB COMANDO de quem trata (nunca automático). Cobrança real continua desligada.
--   * L18 Polos e parceiros: tipo de unidade (sede, polo próprio, polo parceiro), parceiro e meta de ingressos; painel por unidade.
--     O acesso do parceiro usa o escopo por campus que já existe. Repasse: regra contratual descrita em texto, SEM cálculo de pagamento.
--   * L20 Egressos: registro de conclusão com consentimento de contato e interesses; oferta de pós-graduação ou segunda graduação
--     cria nova oportunidade (deduplicada) só com consentimento.
-- Idempotente.

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('conversa.registrar', 'CRM Educacional', 'Registrar mensagem recebida e ver a fila de respostas', array['gestor','comercial'], 'curso', 'rpc_conversas'),
  ('financeiro.ver',     'Relacionamento Estudantil', 'Ver pendências financeiras e inadimplência', array['gestor','financeiro','secretaria','reitoria'], 'curso', 'rpc_financeiro'),
  ('financeiro.gerir',   'Relacionamento Estudantil', 'Importar pendências, registrar negociação e bloquear rematrícula de inadimplentes', array['gestor','financeiro'], 'ies', 'rpc_importar_pendencias'),
  ('polo.gerir',         'Governança Institucional', 'Cadastrar polos e parceiros e suas metas', array['gestor'], 'ies', 'rpc_salvar_polo'),
  ('polo.ver',           'Central de Inteligência', 'Ver o painel por unidade (sede e polos)', array['gestor','reitoria','coordenador','comercial'], 'curso', 'rpc_polos'),
  ('egresso.gerir',      'Relacionamento Estudantil', 'Registrar conclusão de curso (egresso)', array['gestor','secretaria'], 'curso', 'rpc_registrar_egresso'),
  ('egresso.ofertar',    'Relacionamento Estudantil', 'Ofertar pós-graduação ou segunda graduação a egressos', array['gestor','comercial'], 'curso', 'rpc_ofertar_egresso')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

-- ================================================================ L21 conversas
alter table public.interacoes add column if not exists direcao text not null default 'saida' check (direcao in ('saida','entrada'));

create or replace function public.rpc_registrar_recebida(p_op bigint, p_tipo text, p_texto text, p_recebida_em timestamptz default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; v_id bigint; quando timestamptz := coalesce(p_recebida_em, now());
begin
  o := privado.op_operacao(p_op, 'conversa.registrar');
  if p_tipo not in ('ligacao','whatsapp_manual','email_manual') then raise exception 'Canal inválido' using errcode = '22023'; end if;
  if length(coalesce(trim(p_texto), '')) not between 3 and 1000 then raise exception 'Texto da mensagem recebida obrigatório (3 a 1000 caracteres)' using errcode = '22023'; end if;
  if quando > now() + interval '5 minutes' or quando < now() - interval '30 days' then raise exception 'Data de recebimento inválida' using errcode = '22023'; end if;
  insert into public.interacoes(ies_id, oportunidade_id, tipo, resumo, usuario_id, em, direcao) values (o.ies_id, o.id, p_tipo, trim(p_texto), (select auth.uid()), quando, 'entrada')
  returning id into v_id;
  perform privado.auditar(o.ies_id, 'conversa.recebida', 'oportunidade', o.id::text, jsonb_build_object('interacao_id', v_id, 'tipo', p_tipo));
  return jsonb_build_object('id', v_id);
end $$;

create or replace function public.rpc_conversas(p_ies bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare papeis text[] := (select papeis from public.matriz_permissoes where operacao = 'conversa.registrar');
begin
  perform privado.autorizar(p_ies, 'conversa.registrar');
  return jsonb_build_object('aviso', 'Integração com WhatsApp e SMS desligada: cole aqui a mensagem recebida e responda pelo seu canal; registre a resposta na ficha. A fila mostra quem aguarda resposta.',
    'sla_horas', (select sla_horas from public.ies where id = p_ies),
    'fila', (select coalesce(jsonb_agg(x order by x->>'recebida_em'), '[]'::jsonb) from (
      select jsonb_build_object('oportunidade_id', o.id, 'nome', p.nome, 'curso', c.nome || ' · ' || c.turno, 'etapa', o.etapa, 'responsavel', privado.nome_usuario(o.responsavel_id),
        'tipo', u.tipo, 'texto', u.resumo, 'recebida_em', u.em, 'horas', round(extract(epoch from now() - u.em) / 3600, 1)) x
      from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id join public.cursos c on c.id = o.curso_id
      join lateral (select i.* from public.interacoes i where i.oportunidade_id = o.id order by i.em desc, i.id desc limit 1) u on true
      where o.ies_id = p_ies and u.direcao = 'entrada' and o.etapa not in ('perdido','cancelado') and privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, papeis)) z));
end $$;

-- ================================================================ L13 pendências financeiras
create table if not exists public.pendencias_financeiras (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  oportunidade_id bigint not null references public.oportunidades(id),
  competencia text not null check (competencia ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  valor_centavos int not null check (valor_centavos > 0),
  vencimento date not null,
  situacao text not null check (situacao in ('aberta','paga','negociada','cancelada')),
  acordo text check (length(acordo) <= 1000),
  atualizado_por uuid references public.usuarios(id),
  atualizado_em timestamptz not null default now(),
  unique (oportunidade_id, competencia)
);
create index if not exists pend_fin_ies on public.pendencias_financeiras(ies_id);
create index if not exists pend_fin_usuario on public.pendencias_financeiras(atualizado_por);
alter table public.pendencias_financeiras enable row level security;
revoke all on public.pendencias_financeiras from anon, authenticated;

-- Linhas: { "oportunidade_id" ou "email", "competencia": "2026-11", "valor": "1290,00", "vencimento": "2026-11-10", "situacao": "aberta" }
create or replace function public.rpc_importar_pendencias(p_ies bigint, p_linhas jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare l jsonb; v_op bigint; ok int := 0; rej jsonb := '[]'::jsonb; n int := 0; v_val int;
begin
  perform privado.autorizar(p_ies, 'financeiro.gerir');
  if jsonb_typeof(p_linhas) <> 'array' or jsonb_array_length(p_linhas) > 5000 then raise exception 'Envie até 5000 linhas' using errcode = '22023'; end if;
  for l in select * from jsonb_array_elements(p_linhas) loop
    n := n + 1;
    begin
      if nullif(l->>'oportunidade_id', '') is not null then
        select id into v_op from public.oportunidades where id = (l->>'oportunidade_id')::bigint and ies_id = p_ies and etapa = 'confirmado';
      else
        select o.id into v_op from public.oportunidades o join public.pessoas p on p.id = o.pessoa_id
         where o.ies_id = p_ies and o.etapa = 'confirmado' and p.email = lower(trim(l->>'email')) order by o.confirmada_em desc limit 1;
      end if;
      if v_op is null then raise exception 'Aluno (ingresso efetivo) não encontrado'; end if;
      v_val := round(replace(replace(coalesce(l->>'valor', ''), '.', ''), ',', '.')::numeric * 100);
      insert into public.pendencias_financeiras(ies_id, oportunidade_id, competencia, valor_centavos, vencimento, situacao, atualizado_por)
      values (p_ies, v_op, l->>'competencia', v_val, (l->>'vencimento')::date, coalesce(nullif(l->>'situacao', ''), 'aberta'), (select auth.uid()))
      on conflict (oportunidade_id, competencia) do update set valor_centavos = excluded.valor_centavos, vencimento = excluded.vencimento,
        situacao = excluded.situacao, atualizado_por = excluded.atualizado_por, atualizado_em = now();
      ok := ok + 1;
    exception when others then rej := rej || jsonb_build_object('linha', n, 'motivo', sqlerrm);
    end;
    v_op := null;
  end loop;
  perform privado.auditar(p_ies, 'financeiro.importar', 'ies', p_ies::text, jsonb_build_object('importadas', ok, 'rejeitadas', jsonb_array_length(rej)));
  return jsonb_build_object('importadas', ok, 'rejeitadas', rej);
end $$;

create or replace function public.rpc_negociar_pendencia(p_id bigint, p_situacao text, p_acordo text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare pf public.pendencias_financeiras;
begin
  perform privado.exigir_usuario();
  select * into pf from public.pendencias_financeiras where id = p_id for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(pf.ies_id, 'financeiro.gerir');
  if p_situacao not in ('paga','negociada','cancelada','aberta') then raise exception 'Situação inválida' using errcode = '22023'; end if;
  if length(coalesce(trim(p_acordo), '')) < 5 then raise exception 'Descreva o acordo ou a baixa' using errcode = '22023'; end if;
  update public.pendencias_financeiras set situacao = p_situacao, acordo = trim(p_acordo), atualizado_por = (select auth.uid()), atualizado_em = now() where id = pf.id;
  perform privado.auditar(pf.ies_id, 'financeiro.negociar', 'oportunidade', pf.oportunidade_id::text, jsonb_build_object('competencia', pf.competencia, 'situacao', p_situacao));
  return jsonb_build_object('id', pf.id, 'situacao', p_situacao);
end $$;

create or replace function public.rpc_financeiro(p_ies bigint, p_dias int default 30)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare papeis text[] := (select papeis from public.matriz_permissoes where operacao = 'financeiro.ver');
begin
  perform privado.autorizar(p_ies, 'financeiro.ver');
  return (with vis as (select f.*, o.curso_id, o.responsavel_id, p.nome, c.nome || ' · ' || c.turno curso
                         from public.pendencias_financeiras f join public.oportunidades o on o.id = f.oportunidade_id join public.pessoas p on p.id = o.pessoa_id
                         join public.cursos c on c.id = o.curso_id where f.ies_id = p_ies and privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, papeis)),
               alunos as (select count(*) n from public.oportunidades o where o.ies_id = p_ies and o.etapa = 'confirmado' and privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, papeis))
    select jsonb_build_object('pode_gerir', privado.pode(p_ies, 'financeiro.gerir'), 'dias_atraso', p_dias,
      'aviso', 'Cobrança real desligada. Pendências vêm da planilha do financeiro. O bloqueio da rematrícula é sempre decisão de quem trata.',
      'indicadores', jsonb_build_object('alunos', (select n from alunos),
        'inadimplentes', (select count(distinct oportunidade_id) from vis where situacao = 'aberta' and vencimento < current_date - p_dias),
        'inadimplencia_pct', case when (select n from alunos) = 0 then null else round(100.0 * (select count(distinct oportunidade_id) from vis where situacao = 'aberta' and vencimento < current_date - p_dias) / (select n from alunos), 1) end,
        'em_aberto_centavos', (select coalesce(sum(valor_centavos), 0) from vis where situacao = 'aberta'),
        'negociadas', (select count(*) from vis where situacao = 'negociada')),
      'pendencias', (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'oportunidade_id', v.oportunidade_id, 'nome', v.nome, 'curso', v.curso, 'competencia', v.competencia,
          'valor_centavos', v.valor_centavos, 'vencimento', v.vencimento, 'situacao', v.situacao, 'acordo', v.acordo, 'dias_atraso', greatest(0, current_date - v.vencimento),
          'rematricula_pendente', exists (select 1 from public.rematriculas r join public.campanhas_rematricula k on k.id = r.campanha_id
                                          where r.oportunidade_id = v.oportunidade_id and r.status = 'pendente' and k.status = 'aberta'))
          order by v.situacao = 'aberta' desc, v.vencimento), '[]'::jsonb) from vis v))
    from (select 1) um);
end $$;

-- Bloqueio sob comando: rematrículas pendentes de alunos com pendência aberta vencida há mais de N dias.
create or replace function public.rpc_bloquear_inadimplentes(p_campanha bigint, p_dias int default 30)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c public.campanhas_rematricula; n int;
begin
  perform privado.exigir_usuario();
  select * into c from public.campanhas_rematricula where id = p_campanha;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(c.ies_id, 'financeiro.gerir');
  if c.status <> 'aberta' then raise exception 'Campanha não está aberta' using errcode = '22023'; end if;
  if p_dias < 1 then raise exception 'Dias de atraso inválidos' using errcode = '22023'; end if;
  update public.rematriculas r set status = 'bloqueada', bloqueio_categoria = 'financeiro', tratado_por = (select auth.uid()), atualizado_em = now(),
    motivo = 'Pendência financeira vencida há mais de ' || p_dias || ' dias (bloqueio em lote pelo financeiro)'
   where r.campanha_id = c.id and r.status = 'pendente'
     and exists (select 1 from public.pendencias_financeiras f where f.oportunidade_id = r.oportunidade_id and f.situacao = 'aberta' and f.vencimento < current_date - p_dias);
  get diagnostics n = row_count;
  perform privado.auditar(c.ies_id, 'financeiro.bloquear_lote', 'campanha_rematricula', c.id::text, jsonb_build_object('periodo', c.periodo, 'bloqueadas', n, 'dias', p_dias));
  return jsonb_build_object('bloqueadas', n);
end $$;

-- ================================================================ L18 polos e parceiros
alter table public.campus
  add column if not exists tipo text not null default 'sede' check (tipo in ('sede','polo_proprio','polo_parceiro')),
  add column if not exists parceiro text check (length(parceiro) <= 200),
  add column if not exists regra_repasse text check (length(regra_repasse) <= 2000),
  add column if not exists meta_ingressos int check (meta_ingressos is null or meta_ingressos >= 0);

create or replace function public.rpc_salvar_polo(p_ies bigint, p_campus bigint, p_dados jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare d jsonb := coalesce(p_dados, '{}'::jsonb); v_id bigint;
begin
  perform privado.autorizar(p_ies, 'polo.gerir');
  if coalesce(d->>'tipo', 'sede') = 'polo_parceiro' and length(coalesce(trim(d->>'parceiro'), '')) < 3 then
    raise exception 'Polo parceiro exige o nome do parceiro' using errcode = '22023'; end if;
  update public.campus set tipo = coalesce(d->>'tipo', tipo), parceiro = case when d ? 'parceiro' then nullif(trim(d->>'parceiro'), '') else parceiro end,
    regra_repasse = case when d ? 'regra_repasse' then nullif(trim(d->>'regra_repasse'), '') else regra_repasse end,
    meta_ingressos = case when d ? 'meta_ingressos' then nullif(d->>'meta_ingressos', '')::int else meta_ingressos end
  where id = p_campus and ies_id = p_ies returning id into v_id;
  if v_id is null then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.auditar(p_ies, 'polo.salvar', 'campus', v_id::text, jsonb_build_object('tipo', d->>'tipo', 'parceiro', d->>'parceiro'));
  return jsonb_build_object('id', v_id);
end $$;

create or replace function public.rpc_polos(p_ies bigint, p_coorte text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare papeis text[] := (select papeis from public.matriz_permissoes where operacao = 'polo.ver');
begin
  perform privado.autorizar(p_ies, 'polo.ver');
  return jsonb_build_object('pode_gerir', privado.pode(p_ies, 'polo.gerir'),
    'aviso', 'Repasse a parceiros: a regra contratual aparece como texto; o sistema não calcula pagamento. Receita mensal = soma das propostas aceitas dos ingressos.',
    'unidades', (select coalesce(jsonb_agg(u order by u->>'tipo', u->>'nome'), '[]'::jsonb) from (
      select jsonb_build_object('id', k.id, 'nome', k.nome, 'tipo', k.tipo, 'parceiro', k.parceiro, 'regra_repasse', k.regra_repasse, 'meta_ingressos', k.meta_ingressos,
        'leads', count(o.id), 'inscritos', count(o.id) filter (where o.etapa in ('inscrito','pre_matricula','matricula_comercial','confirmado')),
        'matriculas', count(o.id) filter (where o.etapa in ('matricula_comercial','confirmado')), 'ingressos', count(o.id) filter (where o.etapa = 'confirmado'),
        'conversao_pct', case when count(o.id) = 0 then null else round(100.0 * count(o.id) filter (where o.etapa = 'confirmado') / count(o.id), 1) end,
        'receita_mensal_centavos', (select coalesce(sum(pr.valor_final_centavos), 0) from public.propostas pr join public.oportunidades x on x.id = pr.oportunidade_id
                                     join public.cursos y on y.id = x.curso_id where y.campus_id = k.id and x.etapa = 'confirmado' and pr.status = 'aceita'
                                       and (p_coorte is null or x.coorte = p_coorte))) u
      from public.campus k left join public.cursos c on c.campus_id = k.id
      left join public.oportunidades o on o.curso_id = c.id and (p_coorte is null or o.coorte = p_coorte) and privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, papeis)
      where k.ies_id = p_ies group by k.id) z));
end $$;

-- ================================================================ L20 egressos
create table if not exists public.egressos (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  oportunidade_id bigint not null unique references public.oportunidades(id),
  conclusao date not null,
  consentimento_contato boolean not null default false,
  interesses text[] not null default '{}',
  observacao text check (length(observacao) <= 500),
  registrado_por uuid references public.usuarios(id),
  registrado_em timestamptz not null default now()
);
create index if not exists egressos_ies on public.egressos(ies_id);
create index if not exists egressos_reg on public.egressos(registrado_por);
alter table public.egressos enable row level security;
revoke all on public.egressos from anon, authenticated;
alter table public.oportunidades add column if not exists egresso_origem_id bigint references public.egressos(id);
create index if not exists oportunidades_egresso on public.oportunidades(egresso_origem_id);

create or replace function public.rpc_registrar_egresso(p_op bigint, p_conclusao date, p_consentimento boolean, p_interesses text[] default '{}', p_observacao text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; v_id bigint;
begin
  o := privado.op_operacao(p_op, 'egresso.gerir');
  if o.etapa <> 'confirmado' then raise exception 'Egresso precisa ter sido aluno (ingresso efetivo)' using errcode = '22023'; end if;
  if p_conclusao is null or p_conclusao > current_date or p_conclusao < o.confirmada_em::date then raise exception 'Data de conclusão entre o ingresso e hoje' using errcode = '22023'; end if;
  if exists (select 1 from unnest(coalesce(p_interesses, '{}')) i where i not in ('pos_graduacao','segunda_graduacao','extensao')) then raise exception 'Interesse inválido' using errcode = '22023'; end if;
  insert into public.egressos(ies_id, oportunidade_id, conclusao, consentimento_contato, interesses, observacao, registrado_por)
  values (o.ies_id, o.id, p_conclusao, coalesce(p_consentimento, false), coalesce(p_interesses, '{}'), nullif(trim(p_observacao), ''), (select auth.uid()))
  on conflict (oportunidade_id) do update set conclusao = excluded.conclusao, consentimento_contato = excluded.consentimento_contato, interesses = excluded.interesses,
    observacao = excluded.observacao, registrado_por = excluded.registrado_por, registrado_em = now()
  returning id into v_id;
  perform privado.auditar(o.ies_id, 'egresso.registrar', 'oportunidade', o.id::text, jsonb_build_object('conclusao', p_conclusao, 'consentimento', p_consentimento));
  return jsonb_build_object('id', v_id);
end $$;

create or replace function public.rpc_ofertar_egresso(p_egresso bigint, p_curso bigint, p_coorte text, p_forma text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare e public.egressos; o public.oportunidades; p public.pessoas; r jsonb;
begin
  perform privado.exigir_usuario();
  select * into e from public.egressos where id = p_egresso;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(e.ies_id, 'egresso.ofertar');
  if not e.consentimento_contato then raise exception 'Egresso sem consentimento para contato comercial' using errcode = '22023'; end if;
  if p_forma not in ('pos_graduacao','segunda_graduacao') then raise exception 'Oferta: pós-graduação ou segunda graduação' using errcode = '22023'; end if;
  select * into o from public.oportunidades where id = e.oportunidade_id;
  select * into p from public.pessoas where id = o.pessoa_id;
  if p.anonimizada_em is not null then raise exception 'Titular anonimizado' using errcode = '22023'; end if;
  r := public.rpc_criar_oportunidade(e.ies_id, jsonb_build_object('nome', p.nome, 'email', p.email, 'telefone', p.telefone, 'curso_id', p_curso, 'coorte', p_coorte,
         'forma_ingresso', p_forma, 'base_legal', 'consentimento', 'origem', 'egresso'), 'egresso-' || e.id || '-' || p_curso || '-' || p_coorte);
  if not (r->>'duplicada')::boolean then update public.oportunidades set egresso_origem_id = e.id where id = (r->>'id')::bigint; end if;
  perform privado.auditar(e.ies_id, 'egresso.ofertar', 'oportunidade', r->>'id', jsonb_build_object('egresso', e.id, 'forma', p_forma, 'duplicada', r->'duplicada'));
  return r;
end $$;

create or replace function public.rpc_egressos(p_ies bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare papeis text[] := array['gestor','secretaria','comercial','coordenador','reitoria'];
begin
  perform privado.exigir_usuario();
  if not (privado.pode(p_ies, 'egresso.gerir') or privado.pode(p_ies, 'egresso.ofertar')) then raise exception 'Seu perfil não tem permissão para esta operação' using errcode = '42501'; end if;
  return jsonb_build_object('pode_gerir', privado.pode(p_ies, 'egresso.gerir'), 'pode_ofertar', privado.pode(p_ies, 'egresso.ofertar'),
    'egressos', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'oportunidade_id', o.id, 'nome', p.nome, 'curso', c.nome || ' · ' || c.turno, 'conclusao', e.conclusao,
        'consentimento', e.consentimento_contato, 'interesses', e.interesses, 'observacao', e.observacao,
        'ofertas', (select count(*) from public.oportunidades x where x.egresso_origem_id = e.id),
        'ofertas_convertidas', (select count(*) from public.oportunidades x where x.egresso_origem_id = e.id and x.etapa = 'confirmado')) order by e.conclusao desc), '[]'::jsonb)
      from public.egressos e join public.oportunidades o on o.id = e.oportunidade_id join public.pessoas p on p.id = o.pessoa_id join public.cursos c on c.id = o.curso_id
      where e.ies_id = p_ies and privado.tem_acesso(o.ies_id, o.curso_id, papeis)));
end $$;

do $$ begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'privado' and p.proname = 'mfa_ok') then
    execute 'drop policy if exists mfa_obrigatorio on public.pendencias_financeiras; create policy mfa_obrigatorio on public.pendencias_financeiras as restrictive for all to authenticated using ((select privado.mfa_ok()))';
    execute 'drop policy if exists mfa_obrigatorio on public.egressos; create policy mfa_obrigatorio on public.egressos as restrictive for all to authenticated using ((select privado.mfa_ok()))';
  end if;
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.rpc_registrar_recebida(bigint, text, text, timestamptz), public.rpc_conversas(bigint),
  public.rpc_importar_pendencias(bigint, jsonb), public.rpc_negociar_pendencia(bigint, text, text), public.rpc_financeiro(bigint, int), public.rpc_bloquear_inadimplentes(bigint, int),
  public.rpc_salvar_polo(bigint, bigint, jsonb), public.rpc_polos(bigint, text),
  public.rpc_registrar_egresso(bigint, date, boolean, text[], text), public.rpc_ofertar_egresso(bigint, bigint, text, text), public.rpc_egressos(bigint) to authenticated;
select privado.conceder_publico();
