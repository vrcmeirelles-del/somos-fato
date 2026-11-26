-- Matrícula 360° — migração 36: ambiente de demonstração e treinamento.
-- Para o SQL Editor do projeto jbimijcvvekomovodfze. Requer as migrações anteriores (aplique 035 e depois 036).
-- CONFIRA o projeto na URL antes de executar. Idempotente. Transação única. A última linha deve ser commit;
begin;
-- Matrícula 360° — migração 36: ambiente de demonstração e treinamento.
--   * IES marcada como demonstração, criada pelo Master com cursos padrão e uma carga sintética de 4 coortes que alimenta todas as telas:
--     funil, campanhas e custos, propostas, bolsas, rematrícula, permanência, inadimplência, casos, pesquisas, escolas e visitas.
--   * "Restaurar": apaga os dados de movimento da IES de demonstração (mantém configurações, equipe, convites e auditoria) e recria a carga.
--     Só funciona em IES de demonstração. Leads em aberto são distribuídos entre os atendentes comerciais que já entraram na IES.
--   * Convite coletivo (vários usos) só existe na demonstração (migração 35): uma turma inteira entra com o mesmo link, por perfil.
--   * A demonstração fica fora do consolidado do BI de quem também atua em IES reais; aparece um aviso em todas as telas da IES.
-- Todos os nomes, e-mails e telefones são fictícios (domínio exemplo.invalid). Idempotente.

-- Apaga os dados de movimento de uma IES de demonstração. Configuração, equipe, convites e auditoria ficam.
create or replace function privado.limpar_demo(p_ies bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare t text; n int; total int := 0; passe int; restam int; manter constant text[] := array['ies','campus','cursos','escopos','usuarios','matriz_permissoes','auditoria',
  'convites','convites_usos','automacoes','trilhas_intervencao','documentos_exigidos','contratos_modelo','modelos_mensagem','integracoes','formularios',
  'funis','funil_versoes','funil_etapas','funil_cadencias','funil_metas','trilhas','modulos','rubricas','rubrica_criterios','cenarios','avaliacoes','pdis','progresso_modulos',
  'planos','objetivos','acoes','concorrencia','protocolos'];
begin
  if not coalesce((select demonstracao from public.ies where id = p_ies), false) then raise exception 'Só IES de demonstração podem ser restauradas' using errcode = '42501'; end if;
  update public.oportunidades set recuperada_de = null, egresso_origem_id = null, visita_id = null, campanha_id = null, indicacao_id = null where ies_id = p_ies;
  delete from public.casos_eventos where caso_id in (select id from public.casos where ies_id = p_ies);
  delete from public.documentos_conteudo where documento_id in (select id from public.documentos where ies_id = p_ies);
  delete from public.respostas_pesquisa where pesquisa_id in (select id from public.pesquisas where ies_id = p_ies)
     or oportunidade_id in (select id from public.oportunidades where ies_id = p_ies);
  delete from public.validacoes where oportunidade_id in (select id from public.oportunidades where ies_id = p_ies);
  -- várias passadas: cada uma apaga o que as chaves estrangeiras já permitem
  for passe in 1..20 loop
    restam := 0;
    for t in select c.table_name::text from information_schema.columns c join pg_tables p on p.schemaname = 'public' and p.tablename = c.table_name
              where c.table_schema = 'public' and c.column_name = 'ies_id' and not (c.table_name::text = any (manter)) order by c.table_name loop
      begin
        execute format('delete from public.%I where ies_id = $1', t) using p_ies;
        get diagnostics n = row_count; total := total + n;
      exception when foreign_key_violation then restam := restam + 1;
      end;
    end loop;
    exit when restam = 0;
  end loop;
  if restam > 0 then raise exception 'Não foi possível limpar a demonstração por completo (dependências restantes)'; end if;
  return jsonb_build_object('registros_apagados', total);
end $$;

-- Carga sintética de 4 coortes. p_usuario assina os registros que exigem autor (propostas, custos, vínculos).
create or replace function privado.semear_demo(p_ies bigint, p_usuario uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  nomes constant text[] := array['Ana','Bruno','Carla','Diego','Eduarda','Felipe','Gabriela','Heitor','Isabela','João','Karina','Lucas','Mariana','Nicolas','Olívia','Pedro','Rafaela','Samuel','Tainá','Vitor','Yasmin','Caio','Larissa','Mateus'];
  sobren constant text[] := array['Almeida','Barbosa','Cardoso','Duarte','Esteves','Freitas','Gomes','Henriques','Lima','Moreira','Nogueira','Oliveira','Pereira','Queiroz','Rocha','Souza','Teixeira','Vieira'];
  origens constant text[] := array['site','site','site','indicacao','evento','meta_ads','meta_ads','google_ads','google_ads','site'];
  motivos constant text[] := array['Preço','Preço','Horário','Escolheu outra instituição','Distância','Desistiu de estudar agora','Preço','Horário'];
  coortes text[]; prox text; cursos bigint[]; nc int; j int; k int; h int; qtd int; v_pessoa bigint; v_op bigint; v_curso bigint; etapa text; criado timestamptz;
  conf timestamptz; base timestamptz; mens int; desc_pct numeric; camp_meta bigint; camp_google bigint; prog_prouni bigint; prog_merito bigint; prog_conv bigint;
  camp_remat bigint; pesq_nps bigint; pesq_perda bigint; esc bigint[] := '{}'; vis bigint[] := '{}'; ops_c0 int := 0; total_ops int := 0; origem text; x record;
  comerciais uuid[];
begin
  if not coalesce((select demonstracao from public.ies where id = p_ies), false) then raise exception 'Só IES de demonstração recebem carga sintética' using errcode = '42501'; end if;
  prox := case when extract(month from current_date) <= 6 then to_char(current_date, 'YYYY') || '.2' else (extract(year from current_date)::int + 1)::text || '.1' end;
  coortes := array[prox, privado.coorte_anterior(prox), privado.coorte_anterior(privado.coorte_anterior(prox)), privado.coorte_anterior(privado.coorte_anterior(privado.coorte_anterior(prox)))];
  select array_agg(id order by id) into cursos from public.cursos where ies_id = p_ies; nc := cardinality(cursos);
  if nc is null then raise exception 'Cadastre ao menos um curso na IES de demonstração'; end if;
  select array_agg(distinct usuario_id) into comerciais from public.escopos where ies_id = p_ies and papel = 'comercial' and revogado_em is null;

  -- metas por curso e coorte
  for j in 1..4 loop
    for k in 1..nc loop
      insert into public.metas(ies_id, curso_id, coorte, meta) values (p_ies, cursos[k], coortes[j], (array[30, 20, 16, 12, 10, 8])[1 + (k - 1) % 6] + (4 - j) * 2)
      on conflict (ies_id, curso_id, coorte) do update set meta = excluded.meta;
    end loop;
  end loop;

  -- bolsas e financiamento
  insert into public.programas_bolsa(ies_id, nome, tipo, percentual_max, vagas, cumulativo, requisitos, criado_por) values
    (p_ies, 'ProUni (demonstração)', 'prouni', 100, null, false, 'Conforme edital do MEC (exemplo fictício).', p_usuario),
    (p_ies, 'Bolsa Mérito ENEM (demonstração)', 'bolsa_institucional', 30, 40, false, 'Nota do ENEM acima de 650 (exemplo fictício).', p_usuario),
    (p_ies, 'Convênio Empresas (demonstração)', 'convenio_empresa', 15, null, true, 'Colaboradores de empresas conveniadas (exemplo fictício).', p_usuario);
  select id into prog_prouni from public.programas_bolsa where ies_id = p_ies and nome = 'ProUni (demonstração)';
  select id into prog_merito from public.programas_bolsa where ies_id = p_ies and nome = 'Bolsa Mérito ENEM (demonstração)';
  select id into prog_conv from public.programas_bolsa where ies_id = p_ies and nome = 'Convênio Empresas (demonstração)';

  -- escolas e visitas
  for k in 1..3 loop
    insert into public.escolas(ies_id, nome, rede, cidade, uf, contato, criado_por) values (p_ies, (array['Escola Estadual Horizonte','Colégio Saber','Escola Municipal Aurora'])[k] || ' (fictícia)',
      (array['publica','privada','publica'])[k], (array['Campo Grande','Dourados','Três Lagoas'])[k], 'MS', 'Coordenação pedagógica (contato fictício)', p_usuario) returning id into h;
    esc := esc || h::bigint;
  end loop;

  for j in 1..4 loop
    base := now() - make_interval(days => (j - 1) * 182);
    insert into public.campanhas(ies_id, coorte, nome, codigo, canal, inicio, fim, orcamento_centavos, status, criado_por)
      values (p_ies, coortes[j], 'Meta Ads ' || coortes[j], 'demo-meta-' || replace(coortes[j], '.', '-'), 'meta_ads', (base - interval '90 days')::date, (base + interval '10 days')::date, 1500000,
              case when j = 1 then 'ativa' else 'encerrada' end, p_usuario) returning id into camp_meta;
    insert into public.campanhas(ies_id, coorte, nome, codigo, canal, inicio, fim, orcamento_centavos, status, criado_por)
      values (p_ies, coortes[j], 'Google Ads ' || coortes[j], 'demo-google-' || replace(coortes[j], '.', '-'), 'google_ads', (base - interval '90 days')::date, (base + interval '10 days')::date, 1200000,
              case when j = 1 then 'ativa' else 'encerrada' end, p_usuario) returning id into camp_google;
    for k in 1..6 loop
      insert into public.custos_campanha(ies_id, campanha_id, data, valor_centavos, descricao, lancado_por) values
        (p_ies, camp_meta, (base - make_interval(days => 90 - k * 14))::date, 180000 + k * 12000, 'Investimento quinzenal (fictício)', p_usuario),
        (p_ies, camp_google, (base - make_interval(days => 90 - k * 14))::date, 150000 + k * 9000, 'Investimento quinzenal (fictício)', p_usuario);
    end loop;
    if j = 1 then
      insert into public.visitas_escola(ies_id, escola_id, titulo, tipo, data, responsavel_id, status, publico_estimado, codigo)
      select p_ies, esc[g.n], (array['Palestra 3º ano','Feira de profissões','Aula aberta de Direito'])[g.n], (array['palestra','feira','aula_aberta'])[g.n], (now() - make_interval(days => 20 + g.n * 9))::date,
             p_usuario, 'realizada', 80 + g.n * 30, 'demo-visita-' || g.n || '-' || p_ies from generate_series(1, 3) g(n);
      select array_agg(id order by id) into vis from public.visitas_escola where ies_id = p_ies;
    end if;

    qtd := (array[170, 130, 140, 120])[j];
    for k in 1..qtd loop
      h := abs(hashtext(p_ies || '-' || j || '-' || k));
      v_curso := cursos[1 + h % nc];
      origem := origens[1 + (h / 7) % 10];
      if j = 1 then
        etapa := case when h % 100 < 18 then 'novo' when h % 100 < 38 then 'contato' when h % 100 < 52 then 'inscrito' when h % 100 < 62 then 'pre_matricula'
                      when h % 100 < 70 then 'matricula_comercial' when h % 100 < 81 then 'confirmado' else 'perdido' end;
        criado := now() - make_interval(days => (h / 11) % 84, hours => h % 23);
      else
        etapa := case when h % 100 < 32 then 'confirmado' when h % 100 < 36 then 'cancelado' else 'perdido' end;
        criado := base - make_interval(days => 30 + (h / 11) % 120);
      end if;
      insert into public.pessoas(ies_id, nome, email, telefone, base_legal, origem, criado_em)
      values (p_ies, nomes[1 + h % 24] || ' ' || sobren[1 + (h / 24) % 18] || ' ' || sobren[1 + (h / 432) % 18] || ' (fictício)',
              'demo.' || p_ies || '.' || j || '.' || k || '@exemplo.invalid', '6799' || lpad(((h % 9000000) + 1000000)::text, 7, '0'),
              'consentimento', origem, criado) returning id into v_pessoa;
      conf := least(now() - interval '1 day', criado + make_interval(days => 15 + h % 40));
      insert into public.oportunidades(ies_id, curso_id, pessoa_id, forma_ingresso, coorte, etapa, responsavel_id, motivo_perda,
          val_documental, val_financeira, val_academica, matricula_comercial_em, confirmada_em, cancelada_em, motivo_cancelamento, criado_em, atualizado_em, ultima_interacao_em,
          campanha_id, visita_id)
      values (p_ies, v_curso, v_pessoa, case when origem = 'evento' then 'visita_escolar' when h % 9 = 0 then 'enem' else 'vestibular' end, coortes[j], etapa,
          case when comerciais is not null and etapa not in ('perdido','cancelado','confirmado') then comerciais[1 + h % cardinality(comerciais)] end,
          case when etapa = 'perdido' then motivos[1 + (h / 13) % 8] end,
          etapa in ('confirmado','cancelado'), etapa in ('confirmado','cancelado'), etapa in ('confirmado','cancelado'),
          case when etapa in ('matricula_comercial','confirmado','cancelado') then conf - interval '5 days' end,
          case when etapa in ('confirmado','cancelado') then conf end,
          case when etapa = 'cancelado' then conf + interval '20 days' end, case when etapa = 'cancelado' then 'Mudança de cidade (fictício)' end,
          criado, greatest(criado, coalesce(conf, criado)), criado + interval '2 days',
          case origem when 'meta_ads' then camp_meta when 'google_ads' then camp_google end,
          case when j = 1 and origem = 'evento' then vis[1 + h % greatest(cardinality(vis), 1)] end)
      returning id into v_op;
      total_ops := total_ops + 1; if j = 1 then ops_c0 := ops_c0 + 1; end if;
      if etapa in ('pre_matricula','matricula_comercial','confirmado','cancelado') then
        select mensalidade_centavos into mens from public.cursos where id = v_curso;
        desc_pct := (array[0, 5, 10, 15, 20])[1 + h % 5];
        insert into public.propostas(ies_id, oportunidade_id, mensalidade_centavos, desconto_pct, valor_final_centavos, validade, status, criado_por, criado_em)
        values (p_ies, v_op, mens, desc_pct, round(mens * (1 - desc_pct / 100)), case when etapa = 'pre_matricula' then now() + interval '6 days' else conf end,
                case when etapa = 'pre_matricula' then 'aprovada' else 'aceita' end, p_usuario, criado + interval '7 days');
      end if;
      -- bolsas aprovadas para parte dos ingressos das duas coortes mais recentes; pedidos pendentes na pré-matrícula
      if etapa = 'confirmado' and j <= 2 and h % 7 < 2 then
        insert into public.solicitacoes_bolsa(ies_id, oportunidade_id, programa_id, percentual, status, origem, decidido_em, justificativa, etapa_externa)
        values (p_ies, v_op, case h % 3 when 0 then prog_prouni when 1 then prog_merito else prog_conv end,
                case h % 3 when 0 then (array[50, 100])[1 + h % 2] when 1 then 30 else 15 end, 'aprovada', 'equipe', conf - interval '3 days',
                'Requisitos conferidos (demonstração)', case when h % 3 = 0 then 'contratado' end);
      elsif etapa = 'pre_matricula' and h % 4 = 0 then
        insert into public.solicitacoes_bolsa(ies_id, oportunidade_id, programa_id, percentual, status, origem, declaracao)
        values (p_ies, v_op, prog_merito, 30, 'solicitada', 'portal', 'Nota do ENEM 690 (fictício)');
      end if;
    end loop;
  end loop;

  -- permanência (vínculos 30 e 90 dias) dos ingressos das coortes anteriores
  insert into public.vinculos(ies_id, oportunidade_id, marco, situacao, data_referencia, observacao, registrado_por)
  select o.ies_id, o.id, m.marco, case when abs(hashtext(o.id || m.marco)) % 100 < 92 then 'ativo' when abs(hashtext(o.id || m.marco)) % 2 = 0 then 'trancado' else 'evadido' end,
         least(current_date, (o.confirmada_em + make_interval(days => m.dias))::date),
         case when abs(hashtext(o.id || m.marco)) % 100 >= 92 then 'Informado pela coordenação (fictício)' end, p_usuario
    from public.oportunidades o cross join (values ('d30', 30), ('d90', 90)) m(marco, dias)
   where o.ies_id = p_ies and o.etapa = 'confirmado' and o.coorte <> coortes[1] and o.confirmada_em + make_interval(days => m.dias) <= now()
  on conflict (oportunidade_id, marco) do nothing;

  -- rematrícula do período atual para quem ingressou nas coortes anteriores
  insert into public.campanhas_rematricula(ies_id, periodo, abre_em, fecha_em, termo, meta_pct, status, criado_por)
  values (p_ies, coortes[1], current_date - 10, current_date + 20, 'Termo de rematrícula do período ' || coortes[1] || ' (demonstração). O aluno confirma a continuidade do curso '
          || 'nas condições do contrato vigente e do calendário acadêmico.' || E'\n**Reajuste anual conforme a legislação (texto fictício de demonstração).**', 85, 'aberta', p_usuario)
  returning id into camp_remat;
  insert into public.rematriculas(ies_id, campanha_id, oportunidade_id, status, bloqueio_categoria, motivo, origem, respondido_em)
  select p_ies, camp_remat, e, s.status, case when s.status = 'bloqueada' then 'financeiro' end,
         case s.status when 'bloqueada' then 'Pendência financeira (demonstração)' when 'recusada' then 'Mudança de cidade (fictício)' end,
         case when s.status in ('aceita','recusada') then 'portal' end, case when s.status in ('aceita','recusada') then now() - make_interval(days => abs(hashtext(e::text)) % 9) end
    from (select e, case when abs(hashtext(e::text)) % 100 < 68 then 'aceita' when abs(hashtext(e::text)) % 100 < 76 then 'recusada'
                         when abs(hashtext(e::text)) % 100 < 82 then 'bloqueada' else 'pendente' end status
            from privado.elegiveis_rematricula((select c from public.campanhas_rematricula c where c.id = camp_remat)) e) s;

  -- pendências financeiras de parte dos alunos
  insert into public.pendencias_financeiras(ies_id, oportunidade_id, competencia, valor_centavos, vencimento, situacao, atualizado_por)
  select o.ies_id, o.id, to_char(current_date - make_interval(days => d), 'YYYY-MM'), coalesce(p.valor_final_centavos, 99000), current_date - d,
         case when abs(hashtext(o.id::text)) % 5 = 0 then 'negociada' else 'aberta' end, p_usuario
    from public.oportunidades o left join lateral (select pp.valor_final_centavos from public.propostas pp where pp.oportunidade_id = o.id and pp.status = 'aceita' order by pp.id desc limit 1) p on true
    cross join lateral (select (array[12, 38, 75, 120])[1 + abs(hashtext(o.id || 'p')) % 4] d) dd
   where o.ies_id = p_ies and o.etapa = 'confirmado' and abs(hashtext(o.id || 'f')) % 100 < 11
  on conflict (oportunidade_id, competencia) do nothing;

  -- casos do aluno: alguns abertos, outros resolvidos
  for x in select o.id, row_number() over (order by o.id) n from public.oportunidades o where o.ies_id = p_ies and o.etapa = 'confirmado' and o.coorte <> coortes[1] order by o.id limit 18 loop
    insert into public.casos(ies_id, oportunidade_id, motivo, origem, prioridade, status, descricao, trilha_id, passos_concluidos, prazo, resolucao, aberto_em, encerrado_em)
    select p_ies, x.id, m, 'equipe', (array['baixa','media','alta'])[1 + x.n % 3], case when x.n <= 8 then 'aberto' else 'resolvido' end,
           'Situação registrada para a demonstração (fictício)', t.id, case when x.n <= 8 then 0 else 2 end,
           now() + make_interval(hours => case when x.n % 4 = 0 then -30 else 40 end), case when x.n > 8 then 'Encaminhamento concluído com o aluno (fictício)' end,
           now() - make_interval(days => 3 + x.n::int), case when x.n > 8 then now() - make_interval(days => (x.n % 3)::int) end
      from (select (array['frequencia','desempenho','financeiro','adaptacao','pessoal','outro'])[1 + x.n % 6] m) mm
      join public.trilhas_intervencao t on t.ies_id = p_ies and t.motivo = mm.m;
  end loop;

  -- pesquisas com respostas (NPS do atendimento e motivos de perda)
  insert into public.pesquisas(ies_id, nome, publico, perguntas, min_respostas, status, criado_por) values
    (p_ies, 'Avaliação do atendimento (demonstração)', 'candidato', '[{"id":"nps","tipo":"nps","texto":"De 0 a 10, quanto você recomendaria a instituição a um amigo?"},{"id":"clareza","tipo":"escala5","texto":"As informações sobre curso, valores e matrícula foram claras?"},{"id":"coment","tipo":"texto","texto":"Quer deixar um comentário?"}]', 5, 'ativa', p_usuario)
  returning id into pesq_nps;
  insert into public.pesquisas(ies_id, nome, publico, perguntas, min_respostas, status, criado_por) values
    (p_ies, 'Por que não nos escolheu (demonstração)', 'perdido', '[{"id":"motivo","tipo":"opcao","texto":"Qual foi o principal motivo?","opcoes":["Preço","Horário","Distância","Escolhi outra instituição","Desisti de estudar agora","Outro"]},{"id":"nps","tipo":"nps","texto":"De 0 a 10, quanto você recomendaria o nosso atendimento?"}]', 5, 'ativa', p_usuario)
  returning id into pesq_perda;
  insert into public.respostas_pesquisa(pesquisa_id, oportunidade_id, respostas, nps)
  select pesq_nps, o.id, jsonb_build_object('nps', n::text, 'clareza', (2 + abs(hashtext(o.id || 'c')) % 4)::text, 'coment', (array['Atendimento rápido.','Gostei da visita ao campus.','Demoraram para responder.',''])[1 + abs(hashtext(o.id || 't')) % 4]), n
    from public.oportunidades o cross join lateral (select (array[10, 9, 9, 8, 10, 7, 6, 9, 10, 4, 8, 9])[1 + abs(hashtext(o.id || 'n')) % 12] n) nn
   where o.ies_id = p_ies and o.coorte = coortes[1] and o.etapa in ('contato','inscrito','pre_matricula','matricula_comercial') order by o.id limit 45;
  insert into public.respostas_pesquisa(pesquisa_id, oportunidade_id, respostas, nps)
  select pesq_perda, o.id, jsonb_build_object('motivo', (array['Preço','Preço','Horário','Distância','Escolhi outra instituição','Desisti de estudar agora'])[1 + abs(hashtext(o.id || 'm')) % 6], 'nps', n::text), n
    from public.oportunidades o cross join lateral (select (array[3, 5, 7, 8, 6, 2, 9])[1 + abs(hashtext(o.id || 'n')) % 7] n) nn
   where o.ies_id = p_ies and o.etapa = 'perdido' order by o.id limit 30;

  return jsonb_build_object('coortes', to_jsonb(coortes), 'oportunidades', total_ops, 'oportunidades_coorte_atual', ops_c0,
    'atendentes_com_leads', coalesce(cardinality(comerciais), 0));
end $$;
revoke execute on function privado.limpar_demo(bigint), privado.semear_demo(bigint, uuid) from public, anon, authenticated;

create or replace function public.rpc_master_criar_demo(p_nome text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_ies bigint; r jsonb;
begin
  perform privado.exigir_usuario();
  if not privado.eh_master() then raise exception 'Operação restrita ao Master' using errcode = '42501'; end if;
  v_ies := (public.rpc_provisionar_ies(coalesce(nullif(trim(p_nome), ''), 'Instituição de Demonstração (fictícia)'), 'completo', 'Campus Demonstração',
    '[{"nome":"Direito","turno":"noturno","modalidade":"presencial","mensalidade_centavos":129000,"desconto_max_pct":30},
      {"nome":"Administração","turno":"noturno","modalidade":"presencial","mensalidade_centavos":89000,"desconto_max_pct":30},
      {"nome":"Psicologia","turno":"matutino","modalidade":"presencial","mensalidade_centavos":119000,"desconto_max_pct":25},
      {"nome":"Enfermagem","turno":"noturno","modalidade":"presencial","mensalidade_centavos":105000,"desconto_max_pct":25},
      {"nome":"Gestão de RH","turno":"ead","modalidade":"ead","mensalidade_centavos":32000,"desconto_max_pct":40}]'::jsonb)->>'id')::bigint;
  update public.ies set demonstracao = true where id = v_ies;
  r := privado.semear_demo(v_ies, (select auth.uid()));
  perform privado.auditar(v_ies, 'demo.criar', 'ies', v_ies::text, r);
  return jsonb_build_object('ies_id', v_ies) || r;
end $$;

create or replace function public.rpc_restaurar_demo(p_ies bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a jsonb; r jsonb;
begin
  perform privado.exigir_usuario();
  if not (privado.eh_master() or privado.tem_acesso_ies(p_ies, array['gestor'])) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  if not coalesce((select demonstracao from public.ies where id = p_ies), false) then raise exception 'Só IES de demonstração podem ser restauradas' using errcode = '42501'; end if;
  a := privado.limpar_demo(p_ies);
  r := privado.semear_demo(p_ies, (select auth.uid()));
  perform privado.auditar(p_ies, 'demo.restaurar', 'ies', p_ies::text, a || r);
  return a || r;
end $$;


-- estrutura passa a informar se a IES é de demonstração (aviso na interface)
create or replace function public.rpc_estrutura(p_ies bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare i public.ies;
  todos text[] := array['gestor','reitoria','coordenador','comercial','secretaria','financeiro'];
begin
  perform privado.exigir_usuario();
  if not privado.ve_ies(p_ies) then perform privado.erro_http(404, 'P0002', 'Não encontrado'); end if;
  select * into i from public.ies where id = p_ies;
  return jsonb_build_object(
    'ies', jsonb_build_object('id', i.id, 'nome', i.nome, 'demonstracao', i.demonstracao, 'plano', i.plano, 'sla_horas', i.sla_horas, 'max_followups', i.max_followups,
                              'dias_sem_contato', i.dias_sem_contato, 'capacidade_atendente', i.capacidade_atendente, 'amostra_minima_forecast', i.amostra_minima_forecast),
    'papeis', (select coalesce(jsonb_agg(distinct e.papel), '[]'::jsonb) from public.escopos e
               where e.usuario_id = (select auth.uid()) and e.ies_id = p_ies and e.revogado_em is null),
    'acesso_total', privado.tem_acesso_ies(p_ies, todos),
    'cursos', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.nome, 'turno', c.turno, 'modalidade', c.modalidade,
                 'mensalidade_centavos', c.mensalidade_centavos, 'desconto_max_pct', c.desconto_max_pct, 'campus', cp.nome) order by c.nome), '[]'::jsonb)
               from public.cursos c join public.campus cp on cp.id = c.campus_id
               where c.ies_id = p_ies and privado.tem_acesso(p_ies, c.id, todos)),
    'coortes', (select coalesce(jsonb_agg(x.coorte order by x.coorte desc), '[]'::jsonb) from (
                 select distinct o.coorte from public.oportunidades o where o.ies_id = p_ies and privado.tem_acesso(o.ies_id, o.curso_id, todos)
                 union select distinct m.coorte from public.metas m where m.ies_id = p_ies and privado.tem_acesso(m.ies_id, m.curso_id, todos)) x),
    'etapas', '["novo","contato","inscrito","pre_matricula","matricula_comercial","confirmado","perdido","cancelado"]'::jsonb,
    'formas_ingresso', '["vestibular","enem","transferencia","segunda_graduacao","reingresso","indicacao","convenio","visita_escolar","evento","pos_graduacao"]'::jsonb,
    'bases_legais', '["consentimento","procedimentos_preliminares_contrato","legitimo_interesse"]'::jsonb,
    'canais', '["email","whatsapp","telefone"]'::jsonb);
end $$;

-- BI: a demonstração fica fora do consolidado de quem atua em IES reais
create or replace function public.rpc_bi_executivo(p_coorte text, p_ies bigint[] default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare cen jsonb; v_ies bigint[]; i bigint; ant text := privado.coorte_anterior(p_coorte); c jsonb; cp jsonb; extra jsonb; perm jsonb; item jsonb; lista jsonb := '[]'::jsonb;
  alertas jsonb; tot jsonb; n_meta int; payback numeric;
begin
  perform privado.exigir_usuario();
  if p_coorte !~ '^\d{4}\.[12]$' then raise exception 'Coorte deve ter formato AAAA.1 ou AAAA.2' using errcode = '22023'; end if;
  select array_agg(x.id order by x.nome) into v_ies from public.ies x
   where x.status = 'ativa' and privado.tem_acesso_ies(x.id, array['gestor','reitoria']) and (p_ies is null or x.id = any (p_ies))
     -- a IES de demonstração não entra no consolidado de quem também atua em IES reais
     and (not x.demonstracao or p_ies is not null or not exists (select 1 from public.ies y where not y.demonstracao and y.status = 'ativa' and privado.tem_acesso_ies(y.id, array['gestor','reitoria'])));
  if v_ies is null then raise exception 'O BI da alta gestão exige papel de gestor ou reitoria com abrangência da instituição' using errcode = '42501'; end if;
  foreach i in array v_ies loop
    cen := public.rpc_central(i, p_coorte); c := cen->'totais';
    cp := public.rpc_central(i, ant)->'totais';
    extra := privado.bi_ies(i, p_coorte);
    -- ticket médio na mesma base da receita da Central (receita mensal dos ingressos ÷ ingressos)
    extra := jsonb_set(extra, '{receita,ticket_medio_centavos}', case when coalesce((c->>'ingressantes')::int, 0) = 0 then 'null'::jsonb
               else to_jsonb(round((c->>'receita_mensal_ingressantes_centavos')::numeric / (c->>'ingressantes')::int)) end);
    begin perm := public.rpc_relacionamento(i, p_coorte)->'permanencia'; exception when others then perm := null; end;
    payback := case when (c->>'custo_por_matricula_centavos') is null or (extra->'receita'->>'ticket_medio_centavos') is null
                      or (extra->'receita'->>'ticket_medio_centavos')::numeric = 0 then null
                    else round((c->>'custo_por_matricula_centavos')::numeric / (extra->'receita'->>'ticket_medio_centavos')::numeric, 1) end;
    alertas := '[]'::jsonb;
    if (c->>'atingimento') is not null and (c->>'atingimento')::numeric < 0.6 then
      alertas := alertas || jsonb_build_object('nivel', 'critico', 'texto', format('Atingimento da meta em %s%%: abaixo de 60%%', round((c->>'atingimento')::numeric * 100, 1)));
    elsif (c->>'atingimento') is not null and (c->>'atingimento')::numeric < 0.8 then
      alertas := alertas || jsonb_build_object('nivel', 'atencao', 'texto', format('Atingimento da meta em %s%%: abaixo de 80%%', round((c->>'atingimento')::numeric * 100, 1)));
    end if;
    if (c->>'meta') is null then alertas := alertas || jsonb_build_object('nivel', 'atencao', 'texto', 'Coorte sem meta cadastrada: atingimento N/D'); end if;
    if (extra->'inadimplencia'->>'pct') is not null and (extra->'inadimplencia'->>'pct')::numeric > 10 then
      alertas := alertas || jsonb_build_object('nivel', 'atencao', 'texto', format('Inadimplência de %s%% (acima de 10%%)', extra->'inadimplencia'->>'pct')); end if;
    if coalesce((extra->'casos'->>'vencidos')::int, 0) > 0 then
      alertas := alertas || jsonb_build_object('nivel', 'atencao', 'texto', format('%s caso(s) do aluno com prazo vencido', extra->'casos'->>'vencidos')); end if;
    if extra->'rematricula' is not null and (extra->'rematricula'->>'meta_pct') is not null and (extra->'rematricula'->>'taxa_pct') is not null
       and (extra->'rematricula'->>'taxa_pct')::numeric < (extra->'rematricula'->>'meta_pct')::numeric then
      alertas := alertas || jsonb_build_object('nivel', 'atencao', 'texto', format('Rematrícula %s em %s%%, abaixo da meta de %s%%', extra->'rematricula'->>'periodo',
        extra->'rematricula'->>'taxa_pct', extra->'rematricula'->>'meta_pct')); end if;
    if (extra->'receita'->>'desconto_medio_pct') is not null and (extra->'receita'->>'desconto_medio_pct')::numeric > 25 then
      alertas := alertas || jsonb_build_object('nivel', 'atencao', 'texto', format('Desconto médio de %s%% sobre a mensalidade (acima de 25%%)', extra->'receita'->>'desconto_medio_pct')); end if;
    if payback is not null and payback > 6 then
      alertas := alertas || jsonb_build_object('nivel', 'atencao', 'texto', format('Custo de aquisição equivale a %s mensalidades (acima de 6)', payback)); end if;
    if extra->'nps' is not null and (extra->'nps'->>'nps')::numeric < 0 then
      alertas := alertas || jsonb_build_object('nivel', 'atencao', 'texto', format('NPS negativo (%s) na pesquisa "%s"', extra->'nps'->>'nps', extra->'nps'->>'pesquisa')); end if;
    item := jsonb_build_object('ies_id', i, 'nome', (select nome from public.ies where id = i), 'atual', c, 'anterior', cp,
      'payback_mensalidades', payback, 'permanencia', perm, 'alertas', alertas,
      'graficos', jsonb_build_object('evolucao', cen->'evolucao', 'funil', cen->'funil', 'por_origem', cen->'por_origem', 'por_curso', cen->'por_curso',
        'por_campanha', cen->'por_campanha') || privado.bi_graficos(i, p_coorte)) || extra;
    lista := lista || jsonb_build_array(item);
  end loop;
  select count(*) filter (where x->'atual'->>'meta' is not null) into n_meta from jsonb_array_elements(lista) x;
  select jsonb_build_object(
      'oportunidades', sum((x->'atual'->>'oportunidades')::int), 'matriculas_comerciais', sum((x->'atual'->>'matriculas_comerciais')::int),
      'ingressantes', sum((x->'atual'->>'ingressantes')::int), 'cancelamentos', sum((x->'atual'->>'cancelamentos')::int),
      'meta', case when n_meta = jsonb_array_length(lista) then sum((x->'atual'->>'meta')::int) end,
      'receita_mensal_ingressantes_centavos', sum((x->'atual'->>'receita_mensal_ingressantes_centavos')::bigint),
      'renuncia_mensal_estimada_centavos', sum((x->'bolsas'->>'renuncia_mensal_estimada_centavos')::bigint),
      'anterior_oportunidades', sum((x->'anterior'->>'oportunidades')::int), 'anterior_ingressantes', sum((x->'anterior'->>'ingressantes')::int),
      'anterior_receita_mensal_ingressantes_centavos', sum((x->'anterior'->>'receita_mensal_ingressantes_centavos')::bigint),
      'alunos', sum((x->'inadimplencia'->>'alunos')::int), 'inadimplentes', sum((x->'inadimplencia'->>'inadimplentes')::int),
      'casos_abertos', sum(coalesce((x->'casos'->>'abertos')::int, 0)), 'casos_vencidos', sum(coalesce((x->'casos'->>'vencidos')::int, 0)),
      'alertas', sum(jsonb_array_length(x->'alertas')))
    into tot from jsonb_array_elements(lista) x;
  tot := tot || jsonb_build_object(
    'atingimento', case when (tot->>'meta') is null or (tot->>'meta')::int = 0 then null else round((tot->>'ingressantes')::numeric / (tot->>'meta')::int, 4) end,
    'inadimplencia_pct', case when (tot->>'alunos')::int = 0 then null else round(100.0 * (tot->>'inadimplentes')::int / (tot->>'alunos')::int, 1) end);
  return jsonb_build_object('coorte', p_coorte, 'coorte_anterior', ant, 'consolidado', tot, 'ies', lista,
    'metodos', jsonb_build_object(
      'captacao', 'Oportunidades, matrículas, ingressos, conversão, projeção, custo por lead e por ingressante e receita: mesmos cálculos da Central de Inteligência, por IES.',
      'consolidado', 'Contagens e valores somados entre as IES. Meta e atingimento consolidados só quando todas as IES têm meta; taxas recalculadas sobre as somas, nunca média de percentuais.',
      'desconto', 'Desconto médio = 1 − (soma dos valores finais ÷ soma das mensalidades) das propostas aceitas dos ingressos da coorte.',
      'renuncia', 'Renúncia estimada = soma de (mensalidade de tabela do curso × percentual da bolsa aprovada) dos ingressos da coorte. Estimativa mensal; não considera a interação com o desconto da proposta.',
      'ticket', 'Ticket médio = receita mensal dos ingressos ÷ ingressos (mesma base da Central).',
      'payback', 'Payback = custo por ingressante ÷ ticket médio mensal (quantas mensalidades pagam a aquisição).',
      'inadimplencia', 'Inadimplência = alunos com pendência aberta vencida há mais de 30 dias ÷ alunos com ingresso efetivo (todas as coortes).',
      'alertas', 'Regras fixas: atingimento < 60% (crítico) ou < 80%; sem meta; inadimplência > 10%; casos vencidos; rematrícula abaixo da meta; desconto médio > 25%; payback > 6 mensalidades; NPS negativo.'));
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function public.rpc_master_criar_demo(text), public.rpc_restaurar_demo(bigint), public.rpc_estrutura(bigint), public.rpc_bi_executivo(text, bigint[]) to authenticated;
select privado.conceder_publico();

commit;
