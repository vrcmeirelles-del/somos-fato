-- Matrícula 360° — migração 29 (Onda B, L19): avaliação por banca e aproveitamento de estudos.
-- Para o SQL Editor do projeto jbimijcvvekomovodfze. Requer as migrações anteriores aplicadas (aplique na ordem 023 → 030).
-- CONFIRA o projeto na URL antes de executar. Idempotente. Transação única. A última linha deve ser commit;
begin;
-- Matrícula 360° — migração 29 (Onda B, L19): avaliação por banca e aproveitamento de estudos.
--   * Banca no processo seletivo: rubrica com critérios e pesos, número mínimo de avaliadores e divergência máxima.
--     Cada avaliador registra notas por critério e parecer sem ver as notas dos outros (avaliação às cegas) até registrar a sua.
--     Divergência acima do limite exige mais um avaliador. A decisão final continua humana e justificada (rpc_avaliar_candidatura);
--     um gatilho impede decidir antes de a banca estar completa.
--   * Aproveitamento de estudos (transferência, segunda graduação, reingresso): disciplinas de origem, equivalência, carga
--     aproveitada, parecer e semestre de ingresso sugerido. O candidato vê o resultado no portal depois da conclusão.
-- Idempotente.

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('aproveitamento.analisar', 'Conversão e Matrículas', 'Analisar aproveitamento de estudos (transferência, segunda graduação, reingresso)',
   array['gestor','coordenador','secretaria'], 'curso', 'rpc_salvar_aproveitamento')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

alter table public.processos_seletivos
  add column if not exists rubrica jsonb,
  add column if not exists avaliadores_minimos int not null default 0 check (avaliadores_minimos between 0 and 5),
  add column if not exists divergencia_max numeric(6,2) check (divergencia_max is null or divergencia_max > 0);

create table if not exists public.avaliacoes_banca (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  candidatura_id bigint not null references public.candidaturas(id),
  avaliador_id uuid not null references public.usuarios(id),
  notas jsonb not null,
  nota_final numeric(6,2) not null check (nota_final between 0 and 1000),
  parecer text not null check (length(parecer) between 10 and 2000),
  em timestamptz not null default now(),
  unique (candidatura_id, avaliador_id)
);
create table if not exists public.aproveitamentos (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  oportunidade_id bigint not null unique references public.oportunidades(id),
  instituicao_origem text not null check (length(instituicao_origem) between 3 and 200),
  curso_origem text not null check (length(curso_origem) between 3 and 200),
  disciplinas jsonb not null default '[]'::jsonb check (jsonb_typeof(disciplinas) = 'array'),
  status text not null default 'em_analise' check (status in ('em_analise','concluida')),
  carga_aproveitada int not null default 0,
  semestre_sugerido int check (semestre_sugerido between 1 and 12),
  parecer text check (length(parecer) <= 3000),
  analisado_por uuid references public.usuarios(id),
  concluida_em timestamptz,
  atualizado_em timestamptz not null default now()
);
create index if not exists banca_ies on public.avaliacoes_banca(ies_id);
create index if not exists banca_avaliador on public.avaliacoes_banca(avaliador_id);
create index if not exists aprov_ies on public.aproveitamentos(ies_id);
create index if not exists aprov_analisado on public.aproveitamentos(analisado_por);
alter table public.avaliacoes_banca enable row level security;
alter table public.aproveitamentos enable row level security;
revoke all on public.avaliacoes_banca, public.aproveitamentos from anon, authenticated;
do $$ begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'privado' and p.proname = 'mfa_ok') then
    execute 'drop policy if exists mfa_obrigatorio on public.avaliacoes_banca; create policy mfa_obrigatorio on public.avaliacoes_banca as restrictive for all to authenticated using ((select privado.mfa_ok()))';
    execute 'drop policy if exists mfa_obrigatorio on public.aproveitamentos; create policy mfa_obrigatorio on public.aproveitamentos as restrictive for all to authenticated using ((select privado.mfa_ok()))';
  end if;
end $$;

-- ---------------------------------------------------------------- banca
create or replace function public.rpc_configurar_banca(p_processo bigint, p_rubrica jsonb, p_minimos int, p_divergencia numeric default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare pr public.processos_seletivos; c jsonb; soma numeric := 0;
begin
  perform privado.exigir_usuario();
  select * into pr from public.processos_seletivos where id = p_processo for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(pr.ies_id, 'seletivo.gerir');
  if pr.resultado_divulgado_em is not null then raise exception 'Resultado já divulgado' using errcode = '22023'; end if;
  if exists (select 1 from public.avaliacoes_banca b join public.candidaturas x on x.id = b.candidatura_id where x.processo_id = pr.id) then
    raise exception 'A banca já começou a avaliar: a rubrica não muda' using errcode = '22023'; end if;
  if p_minimos not between 1 and 5 then raise exception 'Entre 1 e 5 avaliadores' using errcode = '22023'; end if;
  if jsonb_typeof(p_rubrica) <> 'array' or jsonb_array_length(p_rubrica) not between 1 and 10 then raise exception 'Rubrica com 1 a 10 critérios' using errcode = '22023'; end if;
  for c in select * from jsonb_array_elements(p_rubrica) loop
    if coalesce(c->>'id', '') !~ '^[a-z0-9_]{1,20}$' or length(coalesce(c->>'texto', '')) < 3 or coalesce((c->>'peso')::numeric, 0) <= 0 then
      raise exception 'Critério inválido: id, texto e peso positivo' using errcode = '22023'; end if;
    soma := soma + (c->>'peso')::numeric;
  end loop;
  if (select count(distinct x->>'id') from jsonb_array_elements(p_rubrica) x) <> jsonb_array_length(p_rubrica) then raise exception 'Critério repetido' using errcode = '22023'; end if;
  update public.processos_seletivos set rubrica = p_rubrica, avaliadores_minimos = p_minimos, divergencia_max = p_divergencia where id = pr.id;
  perform privado.auditar(pr.ies_id, 'seletivo.banca', 'processo', pr.id::text, jsonb_build_object('criterios', jsonb_array_length(p_rubrica), 'avaliadores', p_minimos, 'divergencia', p_divergencia));
  return jsonb_build_object('id', pr.id, 'soma_pesos', soma);
end $$;

-- Situação da banca: avaliações, divergência e se já pode decidir.
create or replace function privado.situacao_banca(p_candidatura bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('minimos', pr.avaliadores_minimos, 'avaliacoes', count(b.id), 'media', round(avg(b.nota_final), 2),
    'divergencia', max(b.nota_final) - min(b.nota_final),
    'exige_mais_um', pr.divergencia_max is not null and count(b.id) >= pr.avaliadores_minimos and max(b.nota_final) - min(b.nota_final) > pr.divergencia_max
                     and count(b.id) < pr.avaliadores_minimos + 1,
    'completa', count(b.id) >= pr.avaliadores_minimos and not (pr.divergencia_max is not null and max(b.nota_final) - min(b.nota_final) > pr.divergencia_max
                     and count(b.id) < pr.avaliadores_minimos + 1))
  from public.candidaturas c join public.processos_seletivos pr on pr.id = c.processo_id left join public.avaliacoes_banca b on b.candidatura_id = c.id
  where c.id = p_candidatura group by pr.avaliadores_minimos, pr.divergencia_max
$$;
revoke execute on function privado.situacao_banca(bigint) from public, anon, authenticated;

create or replace function public.rpc_avaliar_banca(p_candidatura bigint, p_notas jsonb, p_parecer text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c public.candidaturas; o public.oportunidades; pr public.processos_seletivos; cr jsonb; v numeric; total numeric := 0; pesos numeric := 0; limpo jsonb := '{}'::jsonb;
begin
  perform privado.exigir_usuario();
  select * into c from public.candidaturas where id = p_candidatura for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  select * into o from public.oportunidades where id = c.oportunidade_id;
  if not privado.tem_acesso(o.ies_id, o.curso_id, (select papeis from public.matriz_permissoes where operacao = 'seletivo.avaliar')) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  select * into pr from public.processos_seletivos where id = c.processo_id;
  if pr.rubrica is null or pr.avaliadores_minimos = 0 then raise exception 'Processo sem banca configurada' using errcode = '22023'; end if;
  if c.resultado <> 'pendente' or pr.resultado_divulgado_em is not null then raise exception 'Candidatura já decidida' using errcode = '22023'; end if;
  if length(coalesce(trim(p_parecer), '')) < 10 then raise exception 'Parecer obrigatório (10+ caracteres)' using errcode = '22023'; end if;
  for cr in select * from jsonb_array_elements(pr.rubrica) loop
    begin v := (p_notas->>(cr->>'id'))::numeric; exception when others then v := null; end;
    if v is null or v < 0 or v > 10 then raise exception 'Nota de 0 a 10 para o critério "%"', cr->>'texto' using errcode = '22023'; end if;
    limpo := limpo || jsonb_build_object(cr->>'id', v);
    total := total + v * (cr->>'peso')::numeric; pesos := pesos + (cr->>'peso')::numeric;
  end loop;
  insert into public.avaliacoes_banca(ies_id, candidatura_id, avaliador_id, notas, nota_final, parecer)
  values (o.ies_id, c.id, (select auth.uid()), limpo, round(100 * total / pesos, 2), trim(p_parecer));
  perform privado.auditar(o.ies_id, 'seletivo.banca_avaliar', 'oportunidade', o.id::text, jsonb_build_object('candidatura', c.id, 'nota', round(100 * total / pesos, 2)));
  return jsonb_build_object('nota_final', round(100 * total / pesos, 2), 'banca', privado.situacao_banca(c.id));
exception when unique_violation then raise exception 'Você já avaliou esta candidatura' using errcode = '22023';
end $$;

-- Avaliação às cegas: antes de registrar a própria nota, o avaliador só vê quantas avaliações existem.
create or replace function public.rpc_banca(p_candidatura bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c public.candidaturas; o public.oportunidades; pr public.processos_seletivos; minha boolean;
begin
  perform privado.exigir_usuario();
  select * into c from public.candidaturas where id = p_candidatura;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  select * into o from public.oportunidades where id = c.oportunidade_id;
  if not privado.tem_acesso(o.ies_id, o.curso_id, (select papeis from public.matriz_permissoes where operacao = 'seletivo.avaliar')) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  select * into pr from public.processos_seletivos where id = c.processo_id;
  minha := exists (select 1 from public.avaliacoes_banca where candidatura_id = c.id and avaliador_id = (select auth.uid()));
  return jsonb_build_object('rubrica', pr.rubrica, 'situacao', privado.situacao_banca(c.id), 'ja_avaliei', minha,
    'avaliacoes', case when minha or c.resultado <> 'pendente' then (select coalesce(jsonb_agg(jsonb_build_object('avaliador', privado.nome_usuario(b.avaliador_id), 'notas', b.notas,
        'nota_final', b.nota_final, 'parecer', b.parecer, 'em', b.em) order by b.em), '[]'::jsonb) from public.avaliacoes_banca b where b.candidatura_id = c.id) end);
end $$;

-- Gatilho: decisão (aprovado/reprovado) só com a banca completa, quando o processo exige banca.
create or replace function privado.exigir_banca() returns trigger language plpgsql security definer set search_path = '' as $$
declare s jsonb;
begin
  if new.resultado in ('aprovado','reprovado') and old.resultado = 'pendente' then
    s := privado.situacao_banca(new.id);
    if (s->>'minimos')::int > 0 and not (s->>'completa')::boolean then
      raise exception 'Banca incompleta: % de % avaliação(ões)%', s->>'avaliacoes', s->>'minimos',
        case when (s->>'exige_mais_um')::boolean then '; divergência acima do limite exige mais um avaliador' else '' end using errcode = '22023';
    end if;
  end if;
  return new;
end $$;
revoke execute on function privado.exigir_banca() from public, anon, authenticated;
drop trigger if exists candidatura_banca on public.candidaturas;
create trigger candidatura_banca before update of resultado on public.candidaturas for each row execute function privado.exigir_banca();

-- ---------------------------------------------------------------- aproveitamento de estudos
create or replace function public.rpc_salvar_aproveitamento(p_op bigint, p_dados jsonb, p_concluir boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; a public.aproveitamentos; d jsonb := coalesce(p_dados, '{}'::jsonb); disc jsonb; x jsonb; carga int := 0; limpo jsonb := '[]'::jsonb; cg int; ca int;
begin
  o := privado.op_operacao(p_op, 'aproveitamento.analisar');
  if o.forma_ingresso not in ('transferencia','segunda_graduacao','reingresso') then
    raise exception 'Aproveitamento só para transferência, segunda graduação ou reingresso' using errcode = '22023'; end if;
  select * into a from public.aproveitamentos where oportunidade_id = o.id for update;
  if found and a.status = 'concluida' then raise exception 'Análise concluída não muda' using errcode = '22023'; end if;
  disc := coalesce(d->'disciplinas', a.disciplinas, '[]'::jsonb);
  if jsonb_typeof(disc) <> 'array' or jsonb_array_length(disc) > 80 then raise exception 'Até 80 disciplinas' using errcode = '22023'; end if;
  for x in select * from jsonb_array_elements(disc) loop
    begin cg := (x->>'carga')::int; ca := coalesce(nullif(x->>'carga_aproveitada', '')::int, 0); exception when others then raise exception 'Carga horária inválida' using errcode = '22023'; end;
    if length(coalesce(trim(x->>'nome'), '')) < 2 or cg is null or cg not between 1 and 1000 or ca not between 0 and cg then
      raise exception 'Disciplina inválida: nome, carga (1–1000 h) e carga aproveitada até a carga' using errcode = '22023'; end if;
    if coalesce(x->>'situacao', 'pendente') not in ('pendente','aproveitada','parcial','nao_aproveitada') then raise exception 'Situação inválida' using errcode = '22023'; end if;
    if x->>'situacao' = 'aproveitada' then ca := cg; elsif x->>'situacao' in ('nao_aproveitada','pendente') then ca := 0; end if;
    if x->>'situacao' in ('aproveitada','parcial') and length(coalesce(trim(x->>'equivalente'), '')) < 2 then
      raise exception 'Informe a disciplina equivalente de "%"', x->>'nome' using errcode = '22023'; end if;
    limpo := limpo || jsonb_build_array(jsonb_build_object('nome', trim(x->>'nome'), 'carga', cg, 'nota', nullif(x->>'nota', ''), 'equivalente', nullif(trim(coalesce(x->>'equivalente', '')), ''),
      'situacao', coalesce(x->>'situacao', 'pendente'), 'carga_aproveitada', ca));
    carga := carga + ca;
  end loop;
  if p_concluir then
    if exists (select 1 from jsonb_array_elements(limpo) z where z->>'situacao' = 'pendente') or jsonb_array_length(limpo) = 0 then
      raise exception 'Decida todas as disciplinas antes de concluir' using errcode = '22023'; end if;
    if length(coalesce(trim(d->>'parecer'), a.parecer, '')) < 10 or coalesce(nullif(d->>'semestre_sugerido', '')::int, a.semestre_sugerido) is null then
      raise exception 'Parecer e semestre sugerido obrigatórios para concluir' using errcode = '22023'; end if;
  end if;
  insert into public.aproveitamentos(ies_id, oportunidade_id, instituicao_origem, curso_origem, disciplinas, carga_aproveitada, semestre_sugerido, parecer, analisado_por, status, concluida_em)
  values (o.ies_id, o.id, coalesce(trim(d->>'instituicao_origem'), a.instituicao_origem), coalesce(trim(d->>'curso_origem'), a.curso_origem), limpo, carga,
          coalesce(nullif(d->>'semestre_sugerido', '')::int, a.semestre_sugerido), coalesce(nullif(trim(d->>'parecer'), ''), a.parecer), (select auth.uid()),
          case when p_concluir then 'concluida' else 'em_analise' end, case when p_concluir then now() end)
  on conflict (oportunidade_id) do update set instituicao_origem = excluded.instituicao_origem, curso_origem = excluded.curso_origem, disciplinas = excluded.disciplinas,
    carga_aproveitada = excluded.carga_aproveitada, semestre_sugerido = excluded.semestre_sugerido, parecer = excluded.parecer, analisado_por = excluded.analisado_por,
    status = excluded.status, concluida_em = excluded.concluida_em, atualizado_em = now();
  perform privado.auditar(o.ies_id, 'aproveitamento.salvar', 'oportunidade', o.id::text, jsonb_build_object('disciplinas', jsonb_array_length(limpo), 'carga', carga, 'concluida', p_concluir));
  return jsonb_build_object('carga_aproveitada', carga, 'status', case when p_concluir then 'concluida' else 'em_analise' end);
exception when check_violation then raise exception 'Dados inválidos (instituição e curso de origem com 3+ caracteres, semestre 1–12)' using errcode = '22023';
  when not_null_violation then raise exception 'Informe instituição e curso de origem' using errcode = '22023';
end $$;

create or replace function public.rpc_aproveitamento(p_op bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades;
begin
  perform privado.exigir_usuario();
  select * into o from public.oportunidades where id = p_op;
  if not found or not privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, array['gestor','reitoria','coordenador','comercial','secretaria','financeiro']) then
    perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  return jsonb_build_object('aplicavel', o.forma_ingresso in ('transferencia','segunda_graduacao','reingresso'),
    'pode_analisar', privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, (select papeis from public.matriz_permissoes where operacao = 'aproveitamento.analisar')),
    'analise', (select jsonb_build_object('instituicao_origem', a.instituicao_origem, 'curso_origem', a.curso_origem, 'disciplinas', a.disciplinas, 'status', a.status,
        'carga_aproveitada', a.carga_aproveitada, 'semestre_sugerido', a.semestre_sugerido, 'parecer', a.parecer, 'analisado_por', privado.nome_usuario(a.analisado_por),
        'concluida_em', a.concluida_em) from public.aproveitamentos a where a.oportunidade_id = o.id));
end $$;

create or replace function public.rpc_publico_portal_aproveitamento(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.pessoas;
begin
  p := privado.portal_pessoa(p_token);
  return (select coalesce(jsonb_agg(jsonb_build_object('curso', c.nome || ' · ' || c.turno, 'status', a.status,
      'carga_aproveitada', case when a.status = 'concluida' then a.carga_aproveitada end, 'semestre_sugerido', case when a.status = 'concluida' then a.semestre_sugerido end,
      'disciplinas', case when a.status = 'concluida' then a.disciplinas end, 'parecer', case when a.status = 'concluida' then a.parecer end)), '[]'::jsonb)
    from public.aproveitamentos a join public.oportunidades o on o.id = a.oportunidade_id join public.cursos c on c.id = o.curso_id where o.pessoa_id = p.id);
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.rpc_configurar_banca(bigint, jsonb, int, numeric), public.rpc_avaliar_banca(bigint, jsonb, text), public.rpc_banca(bigint),
  public.rpc_salvar_aproveitamento(bigint, jsonb, boolean), public.rpc_aproveitamento(bigint) to authenticated;
select privado.conceder_publico();

commit;
