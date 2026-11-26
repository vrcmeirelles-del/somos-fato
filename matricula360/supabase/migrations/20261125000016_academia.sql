-- Matrícula 360° — migração 16: Academia de Captação (E08) e MAIM Learning. Bíblia v0.2 §2, §5 e §8.
--   * Trilhas por papel (SDR, Closer, Farmer, liderança, produtos, ética e LGPD) com módulos e competência; progresso.
--   * Rubricas versionadas (rascunho → publicada imutável → arquivada) sobre 7 competências, 4 níveis descritos.
--   * Roleplay apenas com cenários SINTÉTICOS.
--   * Avaliação HUMANA: avaliador ≠ avaliado; evidência obrigatória; finalizada é imutável; o avaliado vê tudo.
--     Nenhuma nota automática por texto ou IA: a consolidação é só a média ponderada dos níveis dados pela pessoa.
--   * PDI com objetivo, ações, prazo e reavaliação; histórico longitudinal por competência.
--   * MAIM Learning (learning-v1): lacuna = nível ≤ 2 na avaliação finalizada mais recente; recomenda módulos.
-- Conteúdo inicial é próprio da plataforma e editável. Idempotente.

insert into public.matriz_permissoes(operacao, modulo, descricao, papeis, abrangencia_minima, rpc) values
  ('academia.ver',     'Academia de Captação', 'Ver trilhas, cenários, próprias avaliações, PDI e recomendações', array['gestor','reitoria','comercial'], 'curso', 'rpc_academia'),
  ('academia.equipe',  'Academia de Captação', 'Ver avaliações, PDIs e lacunas da equipe',                        array['gestor','reitoria'], 'curso', 'rpc_academia'),
  ('academia.avaliar', 'Academia de Captação', 'Avaliar atendente por rubrica publicada (nunca a si mesmo)',      array['gestor'], 'curso', 'rpc_salvar_avaliacao'),
  ('academia.gerir',   'Academia de Captação', 'Editar trilhas, rubricas e cenários; abrir PDI',                  array['gestor'], 'ies', 'rpc_salvar_rubrica')
on conflict (operacao) do update set modulo = excluded.modulo, descricao = excluded.descricao, papeis = excluded.papeis,
  abrangencia_minima = excluded.abrangencia_minima, rpc = excluded.rpc;

create table if not exists public.trilhas (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  nome text not null check (length(nome) between 3 and 100),
  papel_alvo text not null check (papel_alvo in ('sdr','closer','farmer','lideranca','todos')),
  descricao text check (length(descricao) <= 1000),
  ativa boolean not null default true,
  unique (ies_id, nome)
);
create table if not exists public.modulos (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  trilha_id bigint not null references public.trilhas(id),
  ordem int not null check (ordem between 1 and 50),
  titulo text not null check (length(titulo) between 3 and 120),
  conteudo text not null check (length(conteudo) between 10 and 8000),
  competencia text not null check (competencia in ('comunicacao','escuta','dominio_tecnico','negociacao_etica','objecoes','registro','disciplina_operacional')),
  carga_minutos int not null default 30 check (carga_minutos between 5 and 600),
  unique (trilha_id, ordem)
);
create table if not exists public.progresso_modulos (
  usuario_id uuid not null references public.usuarios(id),
  modulo_id bigint not null references public.modulos(id),
  ies_id bigint not null references public.ies(id),
  concluido_em timestamptz not null default now(),
  primary key (usuario_id, modulo_id)
);
create table if not exists public.rubricas (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  nome text not null check (length(nome) between 3 and 100),
  versao int not null,
  status text not null default 'rascunho' check (status in ('rascunho','publicada','arquivada')),
  publicada_em timestamptz,
  unique (ies_id, nome, versao)
);
create unique index if not exists rubrica_uma_publicada on public.rubricas(ies_id, nome) where status = 'publicada';
create table if not exists public.rubrica_criterios (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  rubrica_id bigint not null references public.rubricas(id),
  competencia text not null check (competencia in ('comunicacao','escuta','dominio_tecnico','negociacao_etica','objecoes','registro','disciplina_operacional')),
  descricao text not null check (length(descricao) between 3 and 400),
  niveis jsonb not null check (jsonb_typeof(niveis) = 'array' and jsonb_array_length(niveis) = 4),
  peso int not null default 1 check (peso between 1 and 5),
  unique (rubrica_id, competencia)
);
create table if not exists public.cenarios (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  titulo text not null check (length(titulo) between 3 and 120),
  perfil_sintetico text not null check (length(perfil_sintetico) between 10 and 2000),
  objetivo text not null check (length(objetivo) between 3 and 400),
  objecoes text check (length(objecoes) <= 1000),
  etapa_base text check (etapa_base in ('novo','contato','inscrito','pre_matricula','matricula_comercial')),
  ativo boolean not null default true,
  unique (ies_id, titulo)
);
create table if not exists public.avaliacoes (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  avaliado_id uuid not null references public.usuarios(id),
  avaliador_id uuid not null references public.usuarios(id),
  rubrica_id bigint not null references public.rubricas(id),
  cenario_id bigint references public.cenarios(id),
  tipo text not null check (tipo in ('roleplay','observacao_atendimento')),
  niveis jsonb not null default '{}'::jsonb,
  evidencias text not null check (length(evidencias) between 10 and 4000),
  comentario text check (length(comentario) <= 2000),
  status text not null default 'rascunho' check (status in ('rascunho','finalizada')),
  criado_em timestamptz not null default now(),
  finalizada_em timestamptz,
  check (avaliado_id <> avaliador_id)
);
create table if not exists public.pdis (
  id bigint generated always as identity primary key,
  ies_id bigint not null references public.ies(id),
  usuario_id uuid not null references public.usuarios(id),
  competencia text not null check (competencia in ('comunicacao','escuta','dominio_tecnico','negociacao_etica','objecoes','registro','disciplina_operacional')),
  objetivo text not null check (length(objetivo) between 3 and 400),
  acoes text not null check (length(acoes) between 3 and 2000),
  prazo date not null,
  reavaliar_em date,
  status text not null default 'aberto' check (status in ('aberto','em_andamento','concluido','cancelado')),
  avaliacao_origem bigint references public.avaliacoes(id),
  criado_por uuid references public.usuarios(id),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create index if not exists trilhas_ies on public.trilhas(ies_id);
create index if not exists modulos_trilha on public.modulos(trilha_id);
create index if not exists modulos_ies on public.modulos(ies_id);
create index if not exists progresso_modulo on public.progresso_modulos(modulo_id);
create index if not exists progresso_ies on public.progresso_modulos(ies_id);
create index if not exists rubricas_ies on public.rubricas(ies_id);
create index if not exists criterios_ies on public.rubrica_criterios(ies_id);
create index if not exists cenarios_ies on public.cenarios(ies_id);
create index if not exists avaliacoes_ies on public.avaliacoes(ies_id);
create index if not exists avaliacoes_avaliado on public.avaliacoes(avaliado_id);
create index if not exists avaliacoes_avaliador on public.avaliacoes(avaliador_id);
create index if not exists avaliacoes_rubrica on public.avaliacoes(rubrica_id);
create index if not exists avaliacoes_cenario on public.avaliacoes(cenario_id);
create index if not exists pdis_ies on public.pdis(ies_id);
create index if not exists pdis_usuario on public.pdis(usuario_id);
create index if not exists pdis_avaliacao on public.pdis(avaliacao_origem);
create index if not exists pdis_criado on public.pdis(criado_por);

alter table public.trilhas enable row level security;
alter table public.modulos enable row level security;
alter table public.progresso_modulos enable row level security;
alter table public.rubricas enable row level security;
alter table public.rubrica_criterios enable row level security;
alter table public.cenarios enable row level security;
alter table public.avaliacoes enable row level security;
alter table public.pdis enable row level security;
revoke all on public.trilhas, public.modulos, public.progresso_modulos, public.rubricas, public.rubrica_criterios,
  public.cenarios, public.avaliacoes, public.pdis from anon, authenticated;

-- ---------------------------------------------------------------- conteúdo inicial próprio (editável)
create or replace function privado.criar_academia_padrao(p_ies bigint) returns void
language plpgsql security definer set search_path = '' as $$
declare t bigint; r bigint;
begin
  if exists (select 1 from public.trilhas where ies_id = p_ies) then return; end if;
  insert into public.trilhas(ies_id, nome, papel_alvo, descricao) values (p_ies, 'Atendimento inicial (SDR)', 'sdr', 'Primeiro contato, qualificação e registro.') returning id into t;
  insert into public.modulos(ies_id, trilha_id, ordem, titulo, conteudo, competencia, carga_minutos) values
    (p_ies, t, 1, 'Preparação e acolhimento', 'Antes do contato, leia a ficha e a origem do lead. Apresente-se, diga por que está ligando e confirme se é um bom momento. O objetivo do primeiro contato é entender, não vender.', 'comunicacao', 30),
    (p_ies, t, 2, 'Diagnóstico com perguntas abertas', 'Pergunte sobre objetivo profissional, rotina, horários e experiências anteriores. Escute até o fim, resuma o que ouviu e confirme. Anote o que for relevante para a próxima conversa.', 'escuta', 40),
    (p_ies, t, 3, 'Registro que serve à equipe', 'Todo contato vira registro: o que foi conversado, objeções e próximo passo com data. Registro incompleto faz o colega recomeçar do zero e expõe o candidato a repetições.', 'registro', 20);
  insert into public.trilhas(ies_id, nome, papel_alvo, descricao) values (p_ies, 'Condução e fechamento ético (Closer)', 'closer', 'Apresentação, condições e tratamento de objeções sem pressão indevida.') returning id into t;
  insert into public.modulos(ies_id, trilha_id, ordem, titulo, conteudo, competencia, carga_minutos) values
    (p_ies, t, 1, 'Apresentação do curso pelo que importa ao candidato', 'Conecte o curso ao objetivo que o candidato contou no diagnóstico. Use informações oficiais do curso; não prometa resultado profissional nem condições que não estejam aprovadas.', 'dominio_tecnico', 40),
    (p_ies, t, 2, 'Objeções: entender antes de responder', 'Trate a objeção como informação. Pergunte o que está por trás (preço, horário, distância, família), registre a categoria e responda com fatos. Objeção não superada também é registro válido.', 'objecoes', 40),
    (p_ies, t, 3, 'Condições e próximos passos', 'Apresente valores e bolsas dentro do limite aprovado, com validade clara. Combine o próximo passo com data. Descontos acima do limite exigem aprovação de outra pessoa.', 'negociacao_etica', 30);
  insert into public.trilhas(ies_id, nome, papel_alvo, descricao) values (p_ies, 'Relacionamento e reativação (Farmer)', 'farmer', 'Base perdida, reingresso e indicações com respeito às escolhas do titular.') returning id into t;
  insert into public.modulos(ies_id, trilha_id, ordem, titulo, conteudo, competencia, carga_minutos) values
    (p_ies, t, 1, 'Retomar contato com quem disse não', 'Leia o motivo da perda antes de ligar. Reconheça a decisão anterior, informe o que mudou (nova turma, condição, modalidade) e aceite um novo não. Respeite opt-out e carência.', 'comunicacao', 30),
    (p_ies, t, 2, 'Disciplina de cadência', 'Siga a cadência do funil e registre cada tentativa. Cadência não é insistência: depois do último passo, encerre ou devolva ao gestor.', 'disciplina_operacional', 20);
  insert into public.trilhas(ies_id, nome, papel_alvo, descricao) values (p_ies, 'Liderança comercial', 'lideranca', 'Acompanhamento da equipe por indicadores com denominador e por avaliação humana.') returning id into t;
  insert into public.modulos(ies_id, trilha_id, ordem, titulo, conteudo, competencia, carga_minutos) values
    (p_ies, t, 1, 'Ler indicadores sem tirar conclusões apressadas', 'Olhe sempre o denominador e o tamanho da amostra. Indicador é ponto de partida para conversa e treinamento, não sentença. Combine dados com observação do atendimento.', 'dominio_tecnico', 40),
    (p_ies, t, 2, 'Feedback e PDI', 'Feedback descreve comportamento observado com evidência, não a pessoa. Todo PDI tem objetivo, ações, prazo e data de reavaliação combinados com o atendente.', 'comunicacao', 40);
  insert into public.trilhas(ies_id, nome, papel_alvo, descricao) values (p_ies, 'Ética e LGPD na captação', 'todos', 'Base legal, minimização, opt-out e direitos do titular.') returning id into t;
  insert into public.modulos(ies_id, trilha_id, ordem, titulo, conteudo, competencia, carga_minutos) values
    (p_ies, t, 1, 'Base legal e origem do contato', 'Todo lead precisa de base legal e origem registradas. Sem isso, o cadastro é recusado. Não use listas de origem desconhecida.', 'negociacao_etica', 25),
    (p_ies, t, 2, 'Opt-out e minimização', 'Quando o titular pede para não ser contatado por um canal, o sistema suprime as tarefas daquele canal. Registre apenas o necessário e nunca compartilhe dados fora da plataforma.', 'registro', 25);
  insert into public.rubricas(ies_id, nome, versao, status, publicada_em) values (p_ies, 'Atendimento comercial', 1, 'publicada', now()) returning id into r;
  insert into public.rubrica_criterios(ies_id, rubrica_id, competencia, descricao, niveis, peso) values
    (p_ies, r, 'comunicacao', 'Clareza, cordialidade e adequação da linguagem', '["Confuso ou inadequado","Claro em parte","Claro e cordial","Claro, cordial e adaptado ao candidato"]', 1),
    (p_ies, r, 'escuta', 'Diagnóstico por perguntas abertas e confirmação do entendimento', '["Não investiga","Investiga pouco","Investiga e resume","Investiga, resume e usa o que ouviu"]', 2),
    (p_ies, r, 'dominio_tecnico', 'Informações corretas sobre curso, ingresso e condições', '["Informações incorretas","Informações incompletas","Informações corretas","Corretas e conectadas ao objetivo do candidato"]', 1),
    (p_ies, r, 'negociacao_etica', 'Condições dentro do aprovado, sem pressão ou promessa indevida', '["Pressão ou promessa indevida","Condição pouco clara","Condição clara e aprovada","Clara, aprovada e com prazo explicado"]', 2),
    (p_ies, r, 'objecoes', 'Entendimento e tratamento das objeções', '["Ignora a objeção","Responde sem entender","Entende e responde com fatos","Entende, responde e registra"]', 1),
    (p_ies, r, 'registro', 'Registro completo do contato e do próximo passo', '["Sem registro","Registro incompleto","Registro completo","Completo e útil para a equipe"]', 1),
    (p_ies, r, 'disciplina_operacional', 'Cumprimento de SLA, cadência e agenda', '["Descumpre","Cumpre parcialmente","Cumpre","Cumpre e antecipa"]', 1);
  insert into public.cenarios(ies_id, titulo, perfil_sintetico, objetivo, objecoes, etapa_base) values
    (p_ies, 'Trabalhador do turno da noite interessado em EAD', 'Pessoa fictícia de 32 anos, trabalha em turnos, concluiu o ensino médio há 12 anos e quer uma graduação para promoção interna.', 'Fazer o diagnóstico e apresentar a rotina do EAD.', 'Tempo disponível; receio de não acompanhar.', 'contato'),
    (p_ies, 'Candidato comparando mensalidades', 'Pessoa fictícia de 19 anos, recém-aprovada no ENEM, pesquisando três instituições.', 'Tratar a objeção de preço com fatos e condições aprovadas.', 'Concorrente mais barato; família decide.', 'pre_matricula');
end $$;
revoke execute on function privado.criar_academia_padrao(bigint) from public, anon, authenticated;
select privado.criar_academia_padrao(id) from public.ies;
create or replace function privado.ies_academia_padrao() returns trigger
language plpgsql security definer set search_path = '' as $$ begin perform privado.criar_academia_padrao(new.id); return new; end $$;
revoke execute on function privado.ies_academia_padrao() from public, anon, authenticated;
drop trigger if exists ies_cria_academia on public.ies;
create trigger ies_cria_academia after insert on public.ies for each row execute function privado.ies_academia_padrao();

-- Usuário é da equipe comercial desta IES (alvo de avaliação/PDI)?
create or replace function privado.eh_comercial(p_ies bigint, p_usuario uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.escopos e join public.usuarios u on u.id = e.usuario_id
                  where e.usuario_id = p_usuario and e.ies_id = p_ies and e.papel = 'comercial' and e.revogado_em is null and u.revogado_em is null);
$$;
revoke execute on function privado.eh_comercial(bigint, uuid) from public, anon, authenticated;

-- Consolidação determinística da avaliação humana (média ponderada dos níveis 1–4 atribuídos pelo avaliador).
create or replace function privado.consolidado(p_avaliacao bigint) returns numeric
language sql stable security definer set search_path = '' as $$
  select round(sum((a.niveis->>c.id::text)::int * c.peso)::numeric / nullif(sum(c.peso), 0), 2)
    from public.avaliacoes a join public.rubrica_criterios c on c.rubrica_id = a.rubrica_id
   where a.id = p_avaliacao and a.niveis ? c.id::text;
$$;
revoke execute on function privado.consolidado(bigint) from public, anon, authenticated;

-- ---------------------------------------------------------------- leitura
create or replace function public.rpc_academia(p_ies bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare equipe boolean; eu uuid := (select auth.uid());
begin
  perform privado.autorizar(p_ies, 'academia.ver');
  equipe := privado.pode(p_ies, 'academia.equipe');
  return jsonb_build_object('regra', 'learning-v1', 've_equipe', equipe,
    'pode_avaliar', privado.pode(p_ies, 'academia.avaliar'), 'pode_gerir', privado.pode(p_ies, 'academia.gerir'),
    'aviso', 'Avaliação formativa e humana, com evidência. Nenhuma nota automática por texto ou IA. Não use isoladamente para decisões laborais. O avaliado acessa integralmente as próprias avaliações e o PDI.',
    'trilhas', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'nome', t.nome, 'papel_alvo', t.papel_alvo, 'descricao', t.descricao,
        'modulos', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'ordem', m.ordem, 'titulo', m.titulo, 'conteudo', m.conteudo, 'competencia', m.competencia,
                      'carga_minutos', m.carga_minutos, 'concluido', exists (select 1 from public.progresso_modulos g where g.modulo_id = m.id and g.usuario_id = eu)) order by m.ordem), '[]'::jsonb)
                    from public.modulos m where m.trilha_id = t.id)) order by t.id), '[]'::jsonb)
      from public.trilhas t where t.ies_id = p_ies and t.ativa),
    'rubricas', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'nome', r.nome, 'versao', r.versao, 'status', r.status,
        'criterios', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'competencia', c.competencia, 'descricao', c.descricao, 'niveis', c.niveis, 'peso', c.peso) order by c.id), '[]'::jsonb)
                      from public.rubrica_criterios c where c.rubrica_id = r.id)) order by r.nome, r.versao desc), '[]'::jsonb)
      from public.rubricas r where r.ies_id = p_ies and r.status <> 'arquivada'),
    'cenarios', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'titulo', c.titulo, 'perfil_sintetico', c.perfil_sintetico, 'objetivo', c.objetivo,
        'objecoes', c.objecoes, 'etapa_base', c.etapa_base) order by c.id), '[]'::jsonb) from public.cenarios c where c.ies_id = p_ies and c.ativo),
    'equipe', case when equipe then (select coalesce(jsonb_agg(distinct jsonb_build_object('id', u.id, 'nome', u.nome)), '[]'::jsonb)
        from public.escopos e join public.usuarios u on u.id = e.usuario_id where e.ies_id = p_ies and e.papel = 'comercial' and e.revogado_em is null and u.revogado_em is null) end,
    'avaliacoes', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'avaliado', privado.nome_usuario(a.avaliado_id), 'avaliado_id', a.avaliado_id,
        'avaliador', privado.nome_usuario(a.avaliador_id), 'meu_rascunho', a.avaliador_id = eu and a.status = 'rascunho',
        'rubrica', r.nome || ' v' || r.versao, 'rubrica_id', a.rubrica_id, 'cenario', (select c.titulo from public.cenarios c where c.id = a.cenario_id), 'tipo', a.tipo,
        'niveis', a.niveis, 'evidencias', a.evidencias, 'comentario', a.comentario, 'status', a.status, 'criado_em', a.criado_em, 'finalizada_em', a.finalizada_em,
        'consolidado', privado.consolidado(a.id)) order by a.criado_em desc), '[]'::jsonb)
      from public.avaliacoes a join public.rubricas r on r.id = a.rubrica_id
     where a.ies_id = p_ies and (a.avaliado_id = eu or (equipe and (a.status = 'finalizada' or a.avaliador_id = eu)))),
    'pdis', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'usuario', privado.nome_usuario(p.usuario_id), 'meu', p.usuario_id = eu, 'competencia', p.competencia,
        'objetivo', p.objetivo, 'acoes', p.acoes, 'prazo', p.prazo, 'reavaliar_em', p.reavaliar_em, 'status', p.status,
        'reavaliacao_vencida', p.reavaliar_em < current_date and p.status in ('aberto','em_andamento')) order by p.prazo), '[]'::jsonb)
      from public.pdis p where p.ies_id = p_ies and (p.usuario_id = eu or equipe)),
    -- MAIM Learning: lacunas por pessoa e competência na avaliação finalizada mais recente, com módulos recomendados.
    'lacunas', (select coalesce(jsonb_agg(jsonb_build_object('usuario', privado.nome_usuario(x.avaliado_id), 'meu', x.avaliado_id = eu, 'competencia', x.competencia,
        'nivel', x.nivel, 'avaliada_em', x.finalizada_em,
        'historico', (select jsonb_agg(jsonb_build_object('em', a2.finalizada_em, 'nivel', (a2.niveis->>c2.id::text)::int) order by a2.finalizada_em)
                        from public.avaliacoes a2 join public.rubrica_criterios c2 on c2.rubrica_id = a2.rubrica_id
                       where a2.avaliado_id = x.avaliado_id and a2.ies_id = p_ies and a2.status = 'finalizada' and c2.competencia = x.competencia and a2.niveis ? c2.id::text),
        'recomendados', (select coalesce(jsonb_agg(jsonb_build_object('modulo_id', m.id, 'titulo', m.titulo, 'trilha', t.nome,
                            'concluido', exists (select 1 from public.progresso_modulos g where g.modulo_id = m.id and g.usuario_id = x.avaliado_id))), '[]'::jsonb)
                         from public.modulos m join public.trilhas t on t.id = m.trilha_id where t.ies_id = p_ies and t.ativa and m.competencia = x.competencia),
        'pdi_aberto', exists (select 1 from public.pdis p where p.usuario_id = x.avaliado_id and p.competencia = x.competencia and p.status in ('aberto','em_andamento')))
        order by x.nivel, x.competencia), '[]'::jsonb)
      from (select distinct on (a.avaliado_id, c.competencia) a.avaliado_id, c.competencia, (a.niveis->>c.id::text)::int as nivel, a.finalizada_em
              from public.avaliacoes a join public.rubrica_criterios c on c.rubrica_id = a.rubrica_id
             where a.ies_id = p_ies and a.status = 'finalizada' and a.niveis ? c.id::text and (a.avaliado_id = eu or equipe)
             order by a.avaliado_id, c.competencia, a.finalizada_em desc) x where x.nivel <= 2));
end $$;

-- ---------------------------------------------------------------- escrita
create or replace function public.rpc_concluir_modulo(p_modulo bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare m public.modulos;
begin
  perform privado.exigir_usuario();
  select * into m from public.modulos where id = p_modulo;
  if not found or not privado.ve_ies(m.ies_id) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  perform privado.autorizar(m.ies_id, 'academia.ver');
  insert into public.progresso_modulos(usuario_id, modulo_id, ies_id) values ((select auth.uid()), p_modulo, m.ies_id) on conflict do nothing;
  perform privado.auditar(m.ies_id, 'academia.modulo', 'modulo', p_modulo::text);
  return jsonb_build_object('modulo', p_modulo, 'concluido', true);
end $$;

create or replace function public.rpc_salvar_modulo(p_ies bigint, p_dados jsonb, p_id bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id bigint; t bigint := (p_dados->>'trilha_id')::bigint;
begin
  perform privado.autorizar(p_ies, 'academia.gerir');
  if p_id is null then
    if not exists (select 1 from public.trilhas where id = t and ies_id = p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
    insert into public.modulos(ies_id, trilha_id, ordem, titulo, conteudo, competencia, carga_minutos)
    values (p_ies, t, coalesce((select max(ordem) from public.modulos where trilha_id = t), 0) + 1, trim(p_dados->>'titulo'), trim(p_dados->>'conteudo'),
            p_dados->>'competencia', coalesce((p_dados->>'carga_minutos')::int, 30)) returning id into v_id;
  else
    update public.modulos set titulo = coalesce(trim(p_dados->>'titulo'), titulo), conteudo = coalesce(trim(p_dados->>'conteudo'), conteudo),
           competencia = coalesce(p_dados->>'competencia', competencia), carga_minutos = coalesce((p_dados->>'carga_minutos')::int, carga_minutos)
     where id = p_id and ies_id = p_ies returning id into v_id;
    if v_id is null then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  end if;
  perform privado.auditar(p_ies, 'academia.conteudo', 'modulo', v_id::text);
  return jsonb_build_object('id', v_id);
exception when check_violation or not_null_violation then
  raise exception 'Módulo inválido: título (3 a 120), conteúdo (10 a 8000), competência válida' using errcode = '22023';
end $$;

-- Nova versão de rubrica (rascunho) clonada da publicada; publicar arquiva a anterior. Avaliações já feitas mantêm a versão usada.
create or replace function public.rpc_salvar_rubrica(p_ies bigint, p_acao text, p_rubrica bigint, p_criterios jsonb default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.rubricas; v_id bigint;
begin
  perform privado.autorizar(p_ies, 'academia.gerir');
  select * into r from public.rubricas where id = p_rubrica and ies_id = p_ies for update;
  if not found then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if p_acao = 'nova_versao' then
    if exists (select 1 from public.rubricas where ies_id = p_ies and nome = r.nome and status = 'rascunho') then raise exception 'Já existe rascunho desta rubrica' using errcode = '22023'; end if;
    insert into public.rubricas(ies_id, nome, versao) values (p_ies, r.nome, (select max(versao) + 1 from public.rubricas where ies_id = p_ies and nome = r.nome)) returning id into v_id;
    insert into public.rubrica_criterios(ies_id, rubrica_id, competencia, descricao, niveis, peso)
      select p_ies, v_id, competencia, descricao, niveis, peso from public.rubrica_criterios where rubrica_id = p_rubrica;
  elsif p_acao = 'salvar' then
    if r.status <> 'rascunho' then raise exception 'Rubrica publicada é imutável; crie nova versão' using errcode = '22023'; end if;
    delete from public.rubrica_criterios where rubrica_id = p_rubrica;
    insert into public.rubrica_criterios(ies_id, rubrica_id, competencia, descricao, niveis, peso)
      select p_ies, p_rubrica, c->>'competencia', trim(c->>'descricao'), c->'niveis', coalesce((c->>'peso')::int, 1) from jsonb_array_elements(p_criterios) c;
    if (select count(*) from public.rubrica_criterios where rubrica_id = p_rubrica) < 3 then raise exception 'Rubrica precisa de ao menos 3 critérios' using errcode = '22023'; end if;
    v_id := p_rubrica;
  elsif p_acao = 'publicar' then
    if r.status <> 'rascunho' then raise exception 'Só rascunho pode ser publicado' using errcode = '22023'; end if;
    update public.rubricas set status = 'arquivada' where ies_id = p_ies and nome = r.nome and status = 'publicada';
    update public.rubricas set status = 'publicada', publicada_em = now() where id = p_rubrica;
    v_id := p_rubrica;
  else raise exception 'Ação inválida' using errcode = '22023'; end if;
  perform privado.auditar(p_ies, 'rubrica.' || p_acao, 'rubrica', v_id::text, jsonb_build_object('nome', r.nome));
  return jsonb_build_object('id', v_id);
exception when unique_violation or check_violation or not_null_violation then
  raise exception 'Critérios inválidos: competência válida e única, descrição e exatamente 4 níveis' using errcode = '22023';
end $$;

create or replace function public.rpc_salvar_cenario(p_ies bigint, p_dados jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  perform privado.autorizar(p_ies, 'academia.gerir');
  -- Cenário é sintético: recusa texto com padrão de e-mail ou telefone (evita dado pessoal real no roleplay).
  if concat_ws(' ', p_dados->>'perfil_sintetico', p_dados->>'objecoes', p_dados->>'titulo') ~ '[^\s@]+@[^\s@]+\.[a-z]{2,}|\d{8,}|\(\d{2}\)\s?\d{4,5}-?\d{4}' then
    raise exception 'Cenário deve ser sintético: não inclua e-mail ou telefone' using errcode = '22023';
  end if;
  insert into public.cenarios(ies_id, titulo, perfil_sintetico, objetivo, objecoes, etapa_base)
  values (p_ies, trim(p_dados->>'titulo'), trim(p_dados->>'perfil_sintetico'), trim(p_dados->>'objetivo'), nullif(trim(p_dados->>'objecoes'), ''), nullif(p_dados->>'etapa_base', ''))
  returning id into v_id;
  perform privado.auditar(p_ies, 'academia.cenario', 'cenario', v_id::text);
  return jsonb_build_object('id', v_id);
exception
  when unique_violation then perform privado.erro_http(409, '23505', 'Já existe cenário com este título');
  when check_violation or not_null_violation then raise exception 'Cenário inválido: título, perfil sintético (10+ caracteres) e objetivo obrigatórios' using errcode = '22023';
end $$;

-- Avaliação humana: rascunho editável pelo avaliador; finalizar exige todos os critérios e torna imutável.
create or replace function public.rpc_salvar_avaliacao(p_ies bigint, p_dados jsonb, p_id bigint default null, p_finalizar boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a public.avaliacoes; v_id bigint; v_avaliado uuid := (p_dados->>'avaliado_id')::uuid; v_rub bigint := (p_dados->>'rubrica_id')::bigint; k text; n int;
begin
  perform privado.autorizar(p_ies, 'academia.avaliar');
  if p_id is null then
    if v_avaliado = (select auth.uid()) then raise exception 'Ninguém avalia a si mesmo' using errcode = '42501'; end if;
    if not privado.eh_comercial(p_ies, v_avaliado) then raise exception 'Avaliado precisa ser atendente comercial ativo desta instituição' using errcode = '22023'; end if;
    if not exists (select 1 from public.rubricas where id = v_rub and ies_id = p_ies and status = 'publicada') then
      raise exception 'Use uma rubrica publicada' using errcode = '22023';
    end if;
    if nullif(p_dados->>'cenario_id', '') is not null and not exists (select 1 from public.cenarios where id = (p_dados->>'cenario_id')::bigint and ies_id = p_ies) then
      raise exception 'Cenário não pertence à IES' using errcode = '22023';
    end if;
    insert into public.avaliacoes(ies_id, avaliado_id, avaliador_id, rubrica_id, cenario_id, tipo, niveis, evidencias, comentario)
    values (p_ies, v_avaliado, (select auth.uid()), v_rub, nullif(p_dados->>'cenario_id', '')::bigint, p_dados->>'tipo', coalesce(p_dados->'niveis', '{}'::jsonb),
            trim(p_dados->>'evidencias'), nullif(trim(p_dados->>'comentario'), '')) returning * into a;
  else
    select * into a from public.avaliacoes where id = p_id and ies_id = p_ies for update;
    if not found or a.avaliador_id <> (select auth.uid()) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
    if a.status = 'finalizada' then raise exception 'Avaliação finalizada é imutável' using errcode = '22023'; end if;
    update public.avaliacoes set niveis = coalesce(p_dados->'niveis', niveis), evidencias = coalesce(trim(p_dados->>'evidencias'), evidencias),
           comentario = coalesce(nullif(trim(p_dados->>'comentario'), ''), comentario) where id = p_id returning * into a;
  end if;
  -- níveis só para critérios da rubrica e entre 1 e 4
  for k in select jsonb_object_keys(a.niveis) loop
    if not exists (select 1 from public.rubrica_criterios c where c.rubrica_id = a.rubrica_id and c.id::text = k) then raise exception 'Critério % não pertence à rubrica', k using errcode = '22023'; end if;
    n := (a.niveis->>k)::int;
    if n not between 1 and 4 then raise exception 'Nível deve ser de 1 a 4' using errcode = '22023'; end if;
  end loop;
  if p_finalizar then
    if exists (select 1 from public.rubrica_criterios c where c.rubrica_id = a.rubrica_id and not a.niveis ? c.id::text) then
      raise exception 'Para finalizar, avalie todos os critérios da rubrica' using errcode = '22023';
    end if;
    update public.avaliacoes set status = 'finalizada', finalizada_em = now() where id = a.id;
  end if;
  perform privado.auditar(p_ies, case when p_finalizar then 'avaliacao.finalizar' else 'avaliacao.salvar' end, 'avaliacao', a.id::text,
    jsonb_build_object('avaliado_id', a.avaliado_id, 'tipo', a.tipo));
  return jsonb_build_object('id', a.id, 'status', case when p_finalizar then 'finalizada' else 'rascunho' end, 'consolidado', privado.consolidado(a.id));
exception
  when check_violation or not_null_violation then raise exception 'Avaliação inválida: tipo, evidências (10+ caracteres) e avaliador diferente do avaliado' using errcode = '22023';
  when invalid_text_representation then raise exception 'Nível deve ser número de 1 a 4' using errcode = '22023';
end $$;

create or replace function public.rpc_salvar_pdi(p_ies bigint, p_dados jsonb, p_id bigint default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id bigint; pd public.pdis; v_usuario uuid := (p_dados->>'usuario_id')::uuid;
begin
  perform privado.exigir_usuario();
  if p_id is null then
    perform privado.autorizar(p_ies, 'academia.gerir');
    if not privado.eh_comercial(p_ies, v_usuario) then raise exception 'PDI é para atendente comercial ativo desta instituição' using errcode = '22023'; end if;
    if nullif(p_dados->>'avaliacao_origem', '') is not null and not exists (select 1 from public.avaliacoes where id = (p_dados->>'avaliacao_origem')::bigint and avaliado_id = v_usuario and status = 'finalizada') then
      raise exception 'Avaliação de origem precisa ser finalizada e da mesma pessoa' using errcode = '22023';
    end if;
    insert into public.pdis(ies_id, usuario_id, competencia, objetivo, acoes, prazo, reavaliar_em, avaliacao_origem, criado_por)
    values (p_ies, v_usuario, p_dados->>'competencia', trim(p_dados->>'objetivo'), trim(p_dados->>'acoes'), (p_dados->>'prazo')::date,
            nullif(p_dados->>'reavaliar_em', '')::date, nullif(p_dados->>'avaliacao_origem', '')::bigint, (select auth.uid())) returning id into v_id;
  else
    -- O próprio atendente atualiza o andamento; o gestor também.
    select * into pd from public.pdis where id = p_id and ies_id = p_ies for update;
    if not found or not (pd.usuario_id = (select auth.uid()) or privado.pode(p_ies, 'academia.gerir')) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
    if p_dados ?| array['objetivo','acoes','prazo','competencia','usuario_id'] and not privado.pode(p_ies, 'academia.gerir') then
      raise exception 'O atendente atualiza apenas o andamento do PDI' using errcode = '42501';
    end if;
    update public.pdis set status = coalesce(p_dados->>'status', status), objetivo = coalesce(trim(p_dados->>'objetivo'), objetivo),
           acoes = coalesce(trim(p_dados->>'acoes'), acoes), prazo = coalesce((p_dados->>'prazo')::date, prazo),
           reavaliar_em = coalesce(nullif(p_dados->>'reavaliar_em', '')::date, reavaliar_em), atualizado_em = now() where id = p_id returning id into v_id;
  end if;
  perform privado.auditar(p_ies, 'pdi.salvar', 'pdi', v_id::text, jsonb_build_object('status', p_dados->>'status'));
  return jsonb_build_object('id', v_id);
exception when check_violation or not_null_violation then
  raise exception 'PDI inválido: competência, objetivo, ações e prazo obrigatórios' using errcode = '22023';
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.rpc_academia(bigint), public.rpc_concluir_modulo(bigint), public.rpc_salvar_modulo(bigint, jsonb, bigint),
  public.rpc_salvar_rubrica(bigint, text, bigint, jsonb), public.rpc_salvar_cenario(bigint, jsonb),
  public.rpc_salvar_avaliacao(bigint, jsonb, bigint, boolean), public.rpc_salvar_pdi(bigint, jsonb, bigint)
to authenticated;
