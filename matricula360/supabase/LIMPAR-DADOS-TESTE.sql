-- Matrícula 360° — limpeza dos resíduos dos testes automáticos (homologação), preservando a base de demonstração.
-- Projeto: jbimijcvvekomovodfze. CONFIRA o projeto na URL antes de executar.
--
-- O QUE SAI (só o que foi criado pelos roteiros de teste):
--   * Pessoas com origem 'teste automatizado (E2E)', 'homologação supabase' ou 'formulário: Inscrição E2E',
--     com tudo o que depende delas (oportunidades, tarefas, propostas, validações, interações, objeções, documentos,
--     inscrições em eventos e no seletivo, mensagens, recuperações, vínculos, aceites, links do portal, solicitações).
--   * Formulários de teste (endereço 'e2e-...') e seus registros de inscrição pública.
--   * Em oportunidades da semente: propostas de 55% criadas pelo gestor nos testes e validações com evidência
--     'Conferência ... na homologação Supabase' (os indicadores de validação são recalculados).
-- O QUE FICA: instituições, cursos, usuários, metas, configurações, semente sintética de demonstração e a AUDITORIA
--   (imutável por regra do banco; os eventos antigos dos testes continuam registrados).
--
-- COMO USAR
--   1) Rode com  executar := false  (padrão): mostra a PRÉVIA e desfaz tudo ("PRÉVIA: ... nada foi alterado").
--   2) Se a prévia estiver correta, troque para  executar := true  e rode de novo: apaga e registra na auditoria
--      ("LIMPEZA CONCLUÍDA: ..."). Rodar de novo depois não encontra nada (idempotente).
do $limpeza$
declare
  executar constant boolean := false;   -- <<< troque para true somente depois de conferir a prévia
  pessoas_t bigint[]; ops_t bigint[]; forms_t bigint[]; props_semente bigint[]; vals_semente bigint[]; ops_val bigint[];
  r jsonb := '{}'::jsonb; n int;
begin
  select coalesce(array_agg(id), '{}') into pessoas_t from public.pessoas
   where origem in ('teste automatizado (E2E)', 'homologação supabase', 'formulário: Inscrição E2E');
  select coalesce(array_agg(id), '{}') into ops_t from public.oportunidades where pessoa_id = any (pessoas_t);
  select coalesce(array_agg(id), '{}') into forms_t from public.formularios where slug like 'e2e-%';
  select coalesce(array_agg(x.id), '{}') into props_semente from public.propostas x
   where not (x.oportunidade_id = any (ops_t)) and x.desconto_pct = 55
     and x.criado_por in (select e.usuario_id from public.escopos e where e.papel = 'gestor');
  select coalesce(array_agg(v.id), '{}'), coalesce(array_agg(distinct v.oportunidade_id), '{}') into vals_semente, ops_val from public.validacoes v
   where not (v.oportunidade_id = any (ops_t)) and v.evidencia like 'Conferência % na homologação Supabase';

  r := jsonb_build_object('pessoas_de_teste', cardinality(pessoas_t), 'oportunidades_de_teste', cardinality(ops_t), 'formularios_de_teste', cardinality(forms_t),
    'propostas_de_teste_em_leads_da_semente', cardinality(props_semente), 'validacoes_de_teste_em_leads_da_semente', cardinality(vals_semente),
    'oportunidades_que_permanecem', (select count(*) from public.oportunidades where not (id = any (ops_t))));

  -- dependências das oportunidades e pessoas de teste (ordem respeita as chaves estrangeiras)
  delete from public.documentos_conteudo where documento_id in (select id from public.documentos where oportunidade_id = any (ops_t));
  delete from public.documentos where oportunidade_id = any (ops_t);
  delete from public.aceites_matricula where oportunidade_id = any (ops_t);
  delete from public.mensagens where oportunidade_id = any (ops_t);
  delete from public.candidaturas where oportunidade_id = any (ops_t);
  delete from public.inscricoes_evento where oportunidade_id = any (ops_t) or pessoa_id = any (pessoas_t);
  delete from public.recuperacoes where oportunidade_origem_id = any (ops_t) or oportunidade_nova_id = any (ops_t);
  delete from public.vinculos where oportunidade_id = any (ops_t);
  delete from public.onboarding where oportunidade_id = any (ops_t);
  update public.indicacoes set embaixador_id = null where embaixador_id in (select id from public.embaixadores where oportunidade_id = any (ops_t));
  delete from public.embaixadores where oportunidade_id = any (ops_t);
  delete from public.interacoes where oportunidade_id = any (ops_t);
  delete from public.objecoes where oportunidade_id = any (ops_t);
  delete from public.tarefas where oportunidade_id = any (ops_t);
  delete from public.validacoes where oportunidade_id = any (ops_t);
  delete from public.propostas where oportunidade_id = any (ops_t);
  delete from public.inscricoes_publicas where oportunidade_id = any (ops_t) or formulario_id = any (forms_t);
  update public.oportunidades set recuperada_de = null where recuperada_de = any (ops_t);
  delete from public.oportunidades where id = any (ops_t);
  get diagnostics n = row_count; r := r || jsonb_build_object('oportunidades_apagadas', n);
  delete from public.acessos_candidato where pessoa_id = any (pessoas_t);
  delete from public.solicitacoes_titular where pessoa_id = any (pessoas_t);
  delete from public.pessoas where id = any (pessoas_t);
  get diagnostics n = row_count; r := r || jsonb_build_object('pessoas_apagadas', n);
  delete from public.formularios where id = any (forms_t);

  -- resíduos dos testes em leads da semente
  delete from public.propostas where id = any (props_semente);
  delete from public.validacoes where id = any (vals_semente);
  update public.oportunidades o set
     val_documental = exists (select 1 from (select distinct on (dimensao) dimensao, resultado from public.validacoes v where v.oportunidade_id = o.id order by dimensao, v.id desc) u
                               where u.dimensao = 'documental' and u.resultado in ('valida','isencao_formal')),
     val_financeira = exists (select 1 from (select distinct on (dimensao) dimensao, resultado from public.validacoes v where v.oportunidade_id = o.id order by dimensao, v.id desc) u
                               where u.dimensao = 'financeira' and u.resultado in ('valida','isencao_formal')),
     val_academica = exists (select 1 from (select distinct on (dimensao) dimensao, resultado from public.validacoes v where v.oportunidade_id = o.id order by dimensao, v.id desc) u
                               where u.dimensao = 'academica' and u.resultado in ('valida','isencao_formal'))
   where o.id = any (ops_val) and o.etapa <> 'confirmado';

  if not executar then
    raise exception 'PRÉVIA (nada foi alterado): %', r::text;
  end if;
  if cardinality(pessoas_t) + cardinality(forms_t) + cardinality(props_semente) + cardinality(vals_semente) = 0 then
    raise notice 'NADA A LIMPAR: nenhum resíduo de teste encontrado.';
    return;
  end if;
  perform privado.auditar(i.id, 'manutencao.limpeza_testes', 'ies', i.id::text, r) from public.ies i;
  raise notice 'LIMPEZA CONCLUÍDA: %', r::text;
end
$limpeza$;
