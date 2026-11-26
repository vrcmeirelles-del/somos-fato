-- Matrícula 360° — migração 25 (Onda A, L15): sucesso do aluno — casos, trilhas de intervenção e agendamento.
-- Para o SQL Editor do projeto jbimijcvvekomovodfze. Requer as migrações anteriores aplicadas (aplique na ordem 023 → 024 → 025 → 026).
-- CONFIRA o projeto na URL antes de executar. Idempotente. Transação única. A última linha deve ser commit;
begin;
-- Matrícula 360° — migração 25 (Onda A, L15): sucesso do aluno — casos, trilhas de intervenção e agendamento.
--   * Trilha por motivo (frequência, desempenho, financeiro, adaptação, pessoal, rematrícula recusada, outro): passos, prazo e
--     papel responsável. Trilhas padrão criadas por IES; o gestor edita.
--   * Caso do aluno (ingressante efetivo): aberto pela equipe ou automaticamente quando o aluno recusa a rematrícula pelo portal.
--     Roteamento para quem tem o papel da trilha no curso, com menos casos abertos; sem ninguém, fica na fila sem dono.
--   * Atendimento: nota, passo concluído, agendamento, encaminhamento, resolução (texto obrigatório) e cancelamento (gestor).
--   * Indicadores: abertos, vencidos, sem dono, tempo médio de resolução, por motivo; agenda dos próximos atendimentos.
--   * LGPD: não registrar dado sensível (saúde, religião, etc.; art. 11). Nada é enviado ao aluno.
-- Idempotente.

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('caso.ver',     'Relacionamento Estudantil', 'Ver casos de sucesso do aluno e a agenda de atendimentos', array['gestor','secretaria','coordenador','financeiro','reitoria'], 'curso', 'rpc_casos'),
  ('caso.atender', 'Relacionamento Estudantil', 'Abrir e atender casos do aluno',                           array['gestor','secretaria','coordenador','financeiro'], 'curso', 'rpc_atender_caso'),
  ('caso.trilhas', 'Relacionamento Estudantil', 'Editar trilhas de intervenção',                            array['gestor'], 'ies', 'rpc_salvar_trilha')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

create table if not exists public.trilhas_intervencao (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  motivo text not null check (motivo in ('frequencia','desempenho','financeiro','adaptacao','pessoal','rematricula_recusada','outro')),
  nome text not null check (length(nome) between 3 and 100),
  passos text[] not null check (cardinality(passos) between 1 and 10),
  prazo_horas int not null check (prazo_horas between 4 and 720),
  papel_responsavel text not null check (papel_responsavel in ('gestor','secretaria','coordenador','financeiro')),
  unique (ies_id, motivo)
);
create table if not exists public.casos (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  oportunidade_id bigint not null references public.oportunidades(id),
  motivo text not null,
  origem text not null check (origem in ('equipe','rematricula')),
  prioridade text not null default 'media' check (prioridade in ('baixa','media','alta')),
  status text not null default 'aberto' check (status in ('aberto','em_atendimento','resolvido','cancelado')),
  descricao text not null check (length(descricao) between 5 and 1000),
  trilha_id bigint references public.trilhas_intervencao(id),
  passos_concluidos int not null default 0,
  responsavel_id uuid references public.usuarios(id),
  prazo timestamptz not null,
  resolucao text,
  aberto_por uuid references public.usuarios(id),
  aberto_em timestamptz not null default now(),
  encerrado_em timestamptz
);
create unique index if not exists caso_aberto_unico on public.casos(oportunidade_id, motivo) where status in ('aberto','em_atendimento');
create table if not exists public.casos_eventos (
  id bigint generated always as identity primary key,
  caso_id bigint not null references public.casos(id),
  tipo text not null check (tipo in ('abertura','nota','passo','agendamento','encaminhamento','resolucao','cancelamento')),
  texto text not null check (length(texto) between 2 and 1000),
  agendado_para timestamptz,
  por uuid references public.usuarios(id),
  em timestamptz not null default now()
);
create index if not exists casos_ies on public.casos(ies_id);
create index if not exists casos_op on public.casos(oportunidade_id);
create index if not exists casos_resp on public.casos(responsavel_id);
create index if not exists casos_trilha on public.casos(trilha_id);
create index if not exists casos_aberto_por on public.casos(aberto_por);
create index if not exists casos_ev_caso on public.casos_eventos(caso_id);
create index if not exists casos_ev_por on public.casos_eventos(por);
alter table public.trilhas_intervencao enable row level security;
alter table public.casos enable row level security;
alter table public.casos_eventos enable row level security;
revoke all on public.trilhas_intervencao, public.casos, public.casos_eventos from anon, authenticated;

-- Trilhas padrão (adaptáveis pelo gestor).
create or replace function privado.trilhas_padrao(p_ies bigint) returns void
language sql security definer set search_path = '' as $$
  insert into public.trilhas_intervencao(ies_id, motivo, nome, passos, prazo_horas, papel_responsavel) values
    (p_ies, 'frequencia', 'Faltas recorrentes', array['Contato com o aluno para entender as ausências','Conversa com a coordenação do curso','Plano de recuperação de frequência combinado com o aluno'], 72, 'coordenador'),
    (p_ies, 'desempenho', 'Desempenho acadêmico', array['Conversa com o aluno sobre as disciplinas em risco','Encaminhamento a monitoria ou nivelamento','Acompanhamento após a próxima avaliação'], 120, 'coordenador'),
    (p_ies, 'financeiro', 'Dificuldade financeira', array['Atendimento para entender a situação','Apresentar opções de negociação, bolsas e financiamento vigentes','Registrar o acordo ou o encaminhamento'], 72, 'financeiro'),
    (p_ies, 'adaptacao', 'Adaptação à vida acadêmica', array['Acolhimento e escuta','Apresentar serviços de apoio da instituição','Retorno em duas semanas'], 120, 'secretaria'),
    (p_ies, 'pessoal', 'Questão pessoal', array['Acolhimento (sem registrar dado sensível)','Encaminhamento ao serviço adequado da instituição'], 48, 'secretaria'),
    (p_ies, 'rematricula_recusada', 'Recusa de rematrícula', array['Contato para entender o motivo da recusa','Apresentar alternativas (trancamento, bolsa, mudança de turno)','Registrar a decisão final do aluno'], 48, 'secretaria'),
    (p_ies, 'outro', 'Outro motivo', array['Entender a demanda','Encaminhar e registrar o desfecho'], 96, 'secretaria')
  on conflict (ies_id, motivo) do nothing;
$$;
revoke execute on function privado.trilhas_padrao(bigint) from public, anon, authenticated;
select privado.trilhas_padrao(id) from public.ies;

create or replace function privado.ies_trilhas() returns trigger language plpgsql security definer set search_path = '' as $$
begin perform privado.trilhas_padrao(new.id); return new; end $$;
drop trigger if exists ies_trilhas on public.ies;
create trigger ies_trilhas after insert on public.ies for each row execute function privado.ies_trilhas();

-- Quem atende: tem o papel da trilha com escopo sobre o curso, menos casos abertos; empate pelo id.
create or replace function privado.rotear_caso(p_ies bigint, p_curso bigint, p_papel text) returns uuid
language sql stable security definer set search_path = '' as $$
  select e.usuario_id from public.escopos e join public.usuarios u on u.id = e.usuario_id
   where e.ies_id = p_ies and e.papel = p_papel and e.revogado_em is null and u.revogado_em is null
     and privado.escopo_cobre(e.abrangencia, e.campus_id, e.curso_id, p_curso)
   group by e.usuario_id
   order by (select count(*) from public.casos c where c.responsavel_id = e.usuario_id and c.status in ('aberto','em_atendimento')), e.usuario_id
   limit 1
$$;

create or replace function privado.abrir_caso(o public.oportunidades, p_motivo text, p_origem text, p_prioridade text, p_descricao text, p_por uuid) returns bigint
language plpgsql security definer set search_path = '' as $$
declare t public.trilhas_intervencao; v_id bigint; resp uuid;
begin
  select * into t from public.trilhas_intervencao where ies_id = o.ies_id and motivo = p_motivo;
  if not found then raise exception 'Motivo inválido' using errcode = '22023'; end if;
  resp := privado.rotear_caso(o.ies_id, o.curso_id, t.papel_responsavel);
  insert into public.casos(ies_id, oportunidade_id, motivo, origem, prioridade, descricao, trilha_id, responsavel_id, prazo, aberto_por)
  values (o.ies_id, o.id, p_motivo, p_origem, p_prioridade, p_descricao, t.id, resp,
          now() + make_interval(hours => case p_prioridade when 'alta' then greatest(4, t.prazo_horas / 2) else t.prazo_horas end), p_por)
  returning id into v_id;
  insert into public.casos_eventos(caso_id, tipo, texto, por) values (v_id, 'abertura', p_descricao, p_por);
  perform privado.auditar(o.ies_id, 'caso.abrir', 'oportunidade', o.id::text, jsonb_build_object('caso', v_id, 'motivo', p_motivo, 'origem', p_origem, 'roteado', resp is not null));
  return v_id;
end $$;
revoke execute on function privado.rotear_caso(bigint, bigint, text), privado.abrir_caso(public.oportunidades, text, text, text, text, uuid), privado.ies_trilhas() from public, anon, authenticated;

-- Trilha automática: recusa de rematrícula pelo portal abre caso (se já não houver um aberto).
create or replace function privado.caso_recusa_rematricula() returns trigger language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades;
begin
  if new.status = 'recusada' and new.origem = 'portal' and old.status <> 'recusada' then
    select * into o from public.oportunidades where id = new.oportunidade_id;
    if not exists (select 1 from public.casos where oportunidade_id = o.id and motivo = 'rematricula_recusada' and status in ('aberto','em_atendimento')) then
      perform privado.abrir_caso(o, 'rematricula_recusada', 'rematricula', 'alta', 'Recusou a rematrícula pelo portal. Motivo informado: ' || coalesce(new.motivo, 'não informado'), null);
    end if;
  end if;
  return new;
end $$;
revoke execute on function privado.caso_recusa_rematricula() from public, anon, authenticated;
drop trigger if exists rematricula_caso on public.rematriculas;
create trigger rematricula_caso after update of status on public.rematriculas for each row execute function privado.caso_recusa_rematricula();

-- ---------------------------------------------------------------- operações
create or replace function public.rpc_abrir_caso(p_op bigint, p_motivo text, p_descricao text, p_prioridade text default 'media')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o public.oportunidades; v_id bigint;
begin
  o := privado.op_operacao(p_op, 'caso.atender');
  if o.etapa <> 'confirmado' then raise exception 'Casos são para alunos (ingresso efetivo)' using errcode = '22023'; end if;
  if p_prioridade not in ('baixa','media','alta') then raise exception 'Prioridade inválida' using errcode = '22023'; end if;
  if length(coalesce(trim(p_descricao), '')) < 5 then raise exception 'Descreva a situação' using errcode = '22023'; end if;
  v_id := privado.abrir_caso(o, p_motivo, 'equipe', p_prioridade, trim(p_descricao), (select auth.uid()));
  return jsonb_build_object('id', v_id, 'responsavel', privado.nome_usuario((select responsavel_id from public.casos where id = v_id)));
exception when unique_violation then raise exception 'Já há caso aberto deste motivo para o aluno' using errcode = '22023';
end $$;

create or replace function public.rpc_atender_caso(p_id bigint, p_acao text, p_texto text default null, p_agendado_para timestamptz default null, p_responsavel uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c public.casos; o public.oportunidades; t public.trilhas_intervencao; eu uuid := (select auth.uid()); txt text := trim(coalesce(p_texto, ''));
  gestor boolean; novo_status text;
begin
  perform privado.exigir_usuario();
  select * into c from public.casos where id = p_id for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  o := privado.op_operacao(c.oportunidade_id, 'caso.atender');
  if c.status not in ('aberto','em_atendimento') then raise exception 'Caso encerrado' using errcode = '22023'; end if;
  gestor := privado.tem_acesso(o.ies_id, o.curso_id, array['gestor']);
  if p_acao <> 'assumir' and c.responsavel_id is distinct from eu and not gestor then
    raise exception 'Só o responsável pelo caso ou a gestão atende; assuma o caso antes' using errcode = '42501'; end if;
  select * into t from public.trilhas_intervencao where id = c.trilha_id;
  novo_status := 'em_atendimento';
  if p_acao = 'assumir' then
    if c.responsavel_id = eu then raise exception 'O caso já é seu' using errcode = '22023'; end if;
    if c.responsavel_id is not null and not gestor then raise exception 'Caso com responsável: peça o encaminhamento' using errcode = '42501'; end if;
    update public.casos set responsavel_id = eu where id = c.id;
    txt := 'Assumiu o caso';
    insert into public.casos_eventos(caso_id, tipo, texto, por) values (c.id, 'encaminhamento', txt, eu);
  elsif p_acao = 'nota' then
    if length(txt) < 2 then raise exception 'Escreva a nota' using errcode = '22023'; end if;
    insert into public.casos_eventos(caso_id, tipo, texto, por) values (c.id, 'nota', txt, eu);
  elsif p_acao = 'passo' then
    if c.passos_concluidos >= cardinality(t.passos) then raise exception 'Todos os passos da trilha já foram concluídos' using errcode = '22023'; end if;
    if length(txt) < 5 then raise exception 'Registre o que foi feito neste passo' using errcode = '22023'; end if;
    update public.casos set passos_concluidos = passos_concluidos + 1 where id = c.id;
    insert into public.casos_eventos(caso_id, tipo, texto, por) values (c.id, 'passo', t.passos[c.passos_concluidos + 1] || ': ' || txt, eu);
  elsif p_acao = 'agendar' then
    if p_agendado_para is null or p_agendado_para < now() then raise exception 'Informe data e hora futuras' using errcode = '22023'; end if;
    insert into public.casos_eventos(caso_id, tipo, texto, agendado_para, por) values (c.id, 'agendamento', coalesce(nullif(txt, ''), 'Atendimento agendado'), p_agendado_para, eu);
  elsif p_acao = 'encaminhar' then
    if p_responsavel is null or not exists (select 1 from public.escopos e where e.usuario_id = p_responsavel and e.ies_id = o.ies_id and e.revogado_em is null
        and e.papel in (select unnest(mp.papeis) from public.matriz_permissoes mp where mp.operacao = 'caso.atender') and privado.escopo_cobre(e.abrangencia, e.campus_id, e.curso_id, o.curso_id)) then
      raise exception 'Destino sem permissão para atender casos deste curso' using errcode = '22023'; end if;
    if length(txt) < 5 then raise exception 'Explique o encaminhamento' using errcode = '22023'; end if;
    update public.casos set responsavel_id = p_responsavel where id = c.id;
    insert into public.casos_eventos(caso_id, tipo, texto, por) values (c.id, 'encaminhamento', 'Para ' || privado.nome_usuario(p_responsavel) || ': ' || txt, eu);
  elsif p_acao = 'resolver' then
    if length(txt) < 10 then raise exception 'Descreva o desfecho (mínimo 10 caracteres)' using errcode = '22023'; end if;
    novo_status := 'resolvido';
    update public.casos set resolucao = txt, encerrado_em = now() where id = c.id;
    insert into public.casos_eventos(caso_id, tipo, texto, por) values (c.id, 'resolucao', txt, eu);
  elsif p_acao = 'cancelar' then
    if not gestor then raise exception 'Só a gestão cancela caso' using errcode = '42501'; end if;
    if length(txt) < 5 then raise exception 'Motivo do cancelamento obrigatório' using errcode = '22023'; end if;
    novo_status := 'cancelado';
    update public.casos set resolucao = txt, encerrado_em = now() where id = c.id;
    insert into public.casos_eventos(caso_id, tipo, texto, por) values (c.id, 'cancelamento', txt, eu);
  else raise exception 'Ação inválida' using errcode = '22023';
  end if;
  update public.casos set status = novo_status where id = c.id;
  perform privado.auditar(c.ies_id, 'caso.atender', 'oportunidade', c.oportunidade_id::text, jsonb_build_object('caso', c.id, 'acao', p_acao));
  return jsonb_build_object('id', c.id, 'status', novo_status);
end $$;

create or replace function public.rpc_salvar_trilha(p_ies bigint, p_motivo text, p_dados jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare d jsonb := coalesce(p_dados, '{}'::jsonb); v_id bigint;
begin
  perform privado.autorizar(p_ies, 'caso.trilhas');
  update public.trilhas_intervencao set
    nome = coalesce(trim(d->>'nome'), nome),
    passos = case when jsonb_typeof(d->'passos') = 'array' then (select array_agg(trim(x)) from jsonb_array_elements_text(d->'passos') x where length(trim(x)) >= 3) else passos end,
    prazo_horas = coalesce((d->>'prazo_horas')::int, prazo_horas),
    papel_responsavel = coalesce(d->>'papel_responsavel', papel_responsavel)
  where ies_id = p_ies and motivo = p_motivo returning id into v_id;
  if v_id is null then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.auditar(p_ies, 'caso.trilha', 'trilha', v_id::text, jsonb_build_object('motivo', p_motivo));
  return jsonb_build_object('id', v_id);
end $$;

-- ---------------------------------------------------------------- leitura
create or replace function public.rpc_casos(p_ies bigint, p_op bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare papeis text[] := (select papeis from public.matriz_permissoes where operacao = 'caso.ver'); eu uuid := (select auth.uid());
begin
  perform privado.autorizar(p_ies, 'caso.ver');
  return (with vis as (
      select c.*, o.curso_id, o.responsavel_id as resp_op from public.casos c join public.oportunidades o on o.id = c.oportunidade_id
       where c.ies_id = p_ies and (p_op is null or c.oportunidade_id = p_op) and privado.ve_op(o.ies_id, o.curso_id, o.responsavel_id, papeis))
    select jsonb_build_object(
      'pode_atender', privado.pode(p_ies, 'caso.atender'), 'pode_trilhas', privado.pode(p_ies, 'caso.trilhas'), 'eu', eu,
      'aviso', 'Não registre dado sensível (saúde, religião, orientação, etc.; LGPD art. 11). Nada é enviado ao aluno.',
      'indicadores', (select jsonb_build_object('abertos', count(*) filter (where status in ('aberto','em_atendimento')),
          'vencidos', count(*) filter (where status in ('aberto','em_atendimento') and prazo < now()),
          'sem_dono', count(*) filter (where status in ('aberto','em_atendimento') and responsavel_id is null),
          'meus', count(*) filter (where status in ('aberto','em_atendimento') and responsavel_id = eu),
          'resolvidos', count(*) filter (where status = 'resolvido'),
          'horas_medias_resolucao', round(avg(extract(epoch from encerrado_em - aberto_em) / 3600) filter (where status = 'resolvido'), 1),
          'por_motivo', (select coalesce(jsonb_object_agg(m, n), '{}'::jsonb) from (select motivo m, count(*) n from vis where status in ('aberto','em_atendimento') group by motivo) q))
        from vis),
      'trilhas', (select coalesce(jsonb_agg(jsonb_build_object('motivo', t.motivo, 'nome', t.nome, 'passos', t.passos, 'prazo_horas', t.prazo_horas, 'papel_responsavel', t.papel_responsavel) order by t.motivo), '[]'::jsonb)
                  from public.trilhas_intervencao t where t.ies_id = p_ies),
      'agenda', (select coalesce(jsonb_agg(jsonb_build_object('caso', v.id, 'nome', p.nome, 'quando', e.agendado_para, 'texto', e.texto, 'por', privado.nome_usuario(e.por)) order by e.agendado_para), '[]'::jsonb)
                 from vis v join public.casos_eventos e on e.caso_id = v.id join public.oportunidades o on o.id = v.oportunidade_id join public.pessoas p on p.id = o.pessoa_id
                 where e.tipo = 'agendamento' and e.agendado_para >= now() and v.status in ('aberto','em_atendimento')),
      'casos', (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'oportunidade_id', v.oportunidade_id, 'nome', p.nome, 'curso', k.nome || ' · ' || k.turno,
          'motivo', v.motivo, 'origem', v.origem, 'prioridade', v.prioridade, 'status', v.status, 'descricao', v.descricao, 'prazo', v.prazo,
          'vencido', v.status in ('aberto','em_atendimento') and v.prazo < now(), 'responsavel_id', v.responsavel_id, 'responsavel', privado.nome_usuario(v.responsavel_id),
          'passos', t.passos, 'passos_concluidos', v.passos_concluidos, 'resolucao', v.resolucao, 'aberto_em', v.aberto_em, 'encerrado_em', v.encerrado_em,
          'eventos', (select coalesce(jsonb_agg(jsonb_build_object('tipo', e.tipo, 'texto', e.texto, 'agendado_para', e.agendado_para, 'por', coalesce(privado.nome_usuario(e.por), 'sistema'), 'em', e.em) order by e.id), '[]'::jsonb)
                      from public.casos_eventos e where e.caso_id = v.id))
          order by (v.status in ('aberto','em_atendimento')) desc, (v.prazo < now()) desc, case v.prioridade when 'alta' then 0 when 'media' then 1 else 2 end, v.prazo), '[]'::jsonb)
        from vis v join public.oportunidades o on o.id = v.oportunidade_id join public.pessoas p on p.id = o.pessoa_id join public.cursos k on k.id = o.curso_id
        left join public.trilhas_intervencao t on t.id = v.trilha_id),
      'equipe', (select coalesce(jsonb_agg(distinct jsonb_build_object('id', e.usuario_id, 'nome', privado.nome_usuario(e.usuario_id))), '[]'::jsonb)
                 from public.escopos e where e.ies_id = p_ies and e.revogado_em is null and e.papel in (select unnest(mp.papeis) from public.matriz_permissoes mp where mp.operacao = 'caso.atender')))
    from (select 1) um);
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.rpc_abrir_caso(bigint, text, text, text), public.rpc_atender_caso(bigint, text, text, timestamptz, uuid),
  public.rpc_salvar_trilha(bigint, text, jsonb), public.rpc_casos(bigint, bigint) to authenticated;
select privado.conceder_publico();

commit;
