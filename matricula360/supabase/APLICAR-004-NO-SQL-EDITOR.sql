-- Matrícula 360° — migração 4 (índices de FK) para colar no SQL Editor do projeto jbimijcvvekomovodfze.
-- Pode ser executada mais de uma vez sem efeito colateral.
-- Matrícula 360° — migração 4: índices para chaves estrangeiras sem cobertura.
-- Origem: Performance Advisor do Supabase (lint "unindexed_foreign_keys"), 25/11/2026.
-- Evita varreduras completas em junções, nas checagens de FK e em exclusões.
create index if not exists auditoria_usuario on public.auditoria(usuario_id);
create index if not exists cursos_campus on public.cursos(campus_id);
create index if not exists escopos_ies on public.escopos(ies_id);
create index if not exists escopos_curso on public.escopos(curso_id);
create index if not exists escopos_concedido_por on public.escopos(concedido_por);
create index if not exists metas_curso on public.metas(curso_id);
create index if not exists propostas_criado_por on public.propostas(criado_por);
create index if not exists propostas_decidido_por on public.propostas(decidido_por);
create index if not exists validacoes_usuario on public.validacoes(usuario_id);
-- Cobertos apenas por índices parciais (não servem à checagem de FK em exclusões).
-- O advisor não os aponta; incluídos por robustez.
create index if not exists escopos_usuario_todos on public.escopos(usuario_id);
create index if not exists pessoas_ies on public.pessoas(ies_id);
create index if not exists tarefas_responsavel_todos on public.tarefas(responsavel_id);
