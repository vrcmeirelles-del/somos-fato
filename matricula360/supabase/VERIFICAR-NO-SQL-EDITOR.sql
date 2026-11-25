-- Verificação pós-aplicação. Cole no SQL Editor e envie o resultado (uma linha) para conferência.
-- Só lê metadados do banco; não altera nada.
select
  (select count(*) from pg_tables where schemaname = 'public'
     and tablename in ('ies','campus','cursos','usuarios','escopos','pessoas','oportunidades','validacoes','propostas','tarefas','metas','auditoria')) as tabelas_esperadas_12,
  (select count(*) from pg_tables where schemaname in ('public','privado') and not rowsecurity) as tabelas_sem_rls_0,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname like 'rpc\_%') as rpcs_24,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public','privado') and not coalesce(array_to_string(p.proconfig, ',') like '%search_path=%', false)) as funcoes_sem_search_path_0,
  (select count(*) from information_schema.role_table_grants
     where table_schema = 'public' and grantee in ('anon','authenticated') and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE')) as escritas_diretas_cliente_0,
  (select count(*) from information_schema.role_table_grants where table_schema = 'public' and grantee = 'anon') as permissoes_anon_0,
  (select count(*) from pg_trigger where tgname in ('auditoria_sem_update','auditoria_sem_truncate','confirmacao_integra')) as gatilhos_defesa_3,
  (select count(*) from public.ies) as ies_cadastradas;
