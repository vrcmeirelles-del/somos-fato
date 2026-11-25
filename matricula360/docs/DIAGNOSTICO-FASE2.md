# Diagnóstico das inconsistências da homologação — Fase 2 (25/11/2026)

**Método:** `scripts/diagnostico-homologacao.mjs`, somente leitura, executado contra o Supabase de homologação (`jbimijcvvekomovodfze`) com as contas sintéticas, mais leitura do código. Nenhuma falha foi presumida sem reprodução.

| # | Ponto | Reproduzido | Evidência | Causa | Tratamento |
|---|---|---|---|---|---|
| 1 | Oportunidades aparentemente duplicadas | Sim, sem falha de deduplicação | 8 × "Candidata Homologação Supabase", todas com e-mails distintos; 0 e-mails repetidos | Roteiro E2E criava uma candidata por rodada; a regra (e-mail/telefone normalizados) funcionou | Roteiro passa a reutilizar uma identidade fixa. Alerta de **possível duplicidade** (mesmo nome normalizado, contatos distintos), sem fusão automática |
| 2 | Propostas repetidas | Sim (defeito) | 5 oportunidades com 2 ou mais propostas ativas (pendente/aprovada) simultâneas | Não havia regra de proposta ativa única | Nova proposta **substitui** a anterior ativa (status `substituida`, auditado); índice único parcial no banco; saneamento dos dados existentes |
| 3 | Projeção de oportunidades necessárias | Sim (método) | Exibia 169 = ceil((16−2)/0,083); 20 das 24 oportunidades ainda em aberto | Taxa calculada sobre todas as oportunidades, inclusive as não decididas | Taxa sobre oportunidades **decididas** (ingresso, perda ou cancelamento); ingressos esperados do pipeline aberto; lacuna da meta; novas oportunidades necessárias. N/D sem base decidida |
| 4 | Elegibilidade do primeiro contato | Sim (defeito) | 18/20 tarefas de primeiro contato em oportunidades fora de "novo"; 4 tarefas comerciais em matrícula comercial | Mudança de etapa não encerrava tarefas incompatíveis | Encerramento automático e auditado ao mudar de etapa; saneamento das tarefas existentes |
| 5 | Carregamento das metas | Sim (tela) | O BI mostra as metas 10 e 6; Configurações abre os campos vazios | A tela não consultava as metas existentes | RPC `rpc_metas` e preenchimento da tela |
| 6 | Agrupamentos do BI | Cálculo íntegro | Somas iguais aos totais nos 5 agrupamentos | — | Observação de cadastro: o curso EAD tem turno "ead", o que confunde turno com modalidade. Revisar o domínio de turnos com a gestão acadêmica |
| 7 | Escopos institucionais | Não reproduzido | Os 9 perfis com exatamente os escopos previstos | — | Testes de acesso cruzado mantidos e ampliados |
| 8 | Envio externo desativado | Comportamento correto; interface enganosa | `rpc_disparar_tarefa` → `enviado:false`, tarefa segue aberta, evento auditado | Botão "Disparar" sugere envio real | Botão removido da interface; o estado "envio externo desativado" passa a ser explícito |
