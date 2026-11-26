# Matrícula 360° — Bíblia-Mestra cumulativa v0.2

# Incremento v0.2 — Redesign e evolução funcional
Data: 25/11/2026. Estado: especificação de desenvolvimento, não homologação.
A seção histórica v0.1 abaixo permanece integralmente preservada. Os estados de implementação daquela versão são históricos; os estados atuais devem ser verificados no repositório e ambiente de homologação.

## 1. Evidências da homologação
Fonte: oito capturas fornecidas pelo responsável do produto, ambiente https://matricula360-homologacao.onrender.com/ies/1/dashboard.
- Dashboard: coorte 2027.1, 24 oportunidades, 6 matrículas comerciais, 2 ingressantes, conversão 8,3%, meta 16, atingimento 12,5%, zero cancelamentos e projeção de 169 oportunidades. Fila MAIM com 24 tarefas abertas, zero atrasadas; apenas dez exibidas.
- CRM: Kanban com oito estados visíveis, importação deduplicada e cadastro de oportunidade; nomes repetidos requerem investigação, não provam duplicidade.
- Matrículas: validações documental, financeira e acadêmica separadas; controles de confirmação e cancelamento.
- Propostas: aprovação de descontos acima do limite, segregação declarada; exemplos repetidos exigem conferência de versões.
- Campanhas e Academia: explicitamente fora do piloto; páginas informativas, não módulos operacionais.
- Configurações: SLA, frequência de follow-up, capacidade, metas e auditoria em JSON.
- Master: duas IES fictícias, provisionamento, acessos e suspensão.
- Faixa informa dados sintéticos, IA e envio externo desativados; não comprova configuração efetiva do servidor.
Não foram inspecionados código remoto, RLS, persistência, logs ou execução autenticada. Não afirmar segurança ou funcionamento ponta a ponta com base em imagens.

## 2. Arquitetura funcional vinculante
| ID | Ambiente | Escopo mínimo | Prioridade |
|---|---|---|---|
| E01 | Central de Inteligência | Dashboard, BI por curso, metas, alertas, intervenções | P0 |
| E02 | Planejamento Estratégico | Diagnóstico comercial, objetivos, orçamento, metas semestrais, 5W2H, concorrência | P1 |
| E03 | Marketing e Captação | Campanhas, canais, landing pages, atribuição, custos; conectores desligados | P1 |
| E04 | CRM Educacional | Kanban, ficha, timeline, tarefas, agenda, distribuição, importação, busca | P0 |
| E05 | Funis Comerciais | Construtor versionado, etapas, scripts, cadências, metas por ingresso | P1 |
| E06 | Conversão e Matrículas | Propostas, bolsas, validações, ingresso, cancelamento e qualidade | P0 |
| E07 | Recuperação e Aceleração | Sales Farming, perdas, reingresso, protocolos, sprints | P2 |
| E08 | Academia de Captação | Onboarding, trilhas, rubricas, roleplay, PDI, reavaliação | P2 |
| E09 | Relacionamento Estudantil | Indicações, embaixadores, permanência, rematrícula | P3 |
| E10 | Governança Institucional | Master, escopos, configurações, auditoria, planos e integrações | P0 |

O portal comercial público permanece requisito M01; apresentar apenas capacidades comprovadas e identificar demonstrações. Não reescrever a aplicação: inventariar e evoluir o repositório existente.

## 3. Design system e experiência
- Menu lateral hierárquico, recolhível; cabeçalho institucional; breadcrumbs; filtros globais persistentes por IES, campus, curso, turno, modalidade, campanha e coorte; busca e navegação responsiva.
- Identidade própria: azul-marinho, azul tecnológico, branco e cinza-claro; contraste acessível, tipografia legível, componentes consistentes, foco visível e navegação por teclado.
- Remover selo técnico REACT; preservar indicação inequívoca de homologação e dados sintéticos.
- Cards com definição, período e origem da métrica; gráficos proporcionais aos dados, tooltips com valores reais, estados de carregamento, indisponibilidade, vazio, erro e sucesso.
- Ações destrutivas com confirmação, justificativa e autorização; feedback de sucesso somente após confirmação do servidor. Não criar botões decorativos.
- Dashboard: evolução temporal realizado versus meta, funil, origem, desempenho por curso e atendente, custos, qualidade da matrícula e fila de decisões. Filtros e detalhamento respeitam escopo.

## 4. CRM, conversão e operação
Candidato e oportunidade são entidades distintas. Uma pessoa pode ter múltiplas oportunidades legítimas; não unir apenas por nome. Normalizar identificadores autorizados, detectar conflitos e exigir revisão humana em correspondências ambíguas. Importação com prévia, relatório por linha, idempotência e trilha.
Cartão: curso, turno, coorte, ingresso, origem, responsável, última interação, próxima tarefa, SLA, proposta e score explicável. Ficha: timeline, documentos protegidos, objeções, propostas versionadas, tarefas, consentimentos e histórico de mudanças.
Pipeline configurável por modalidade; validar transições no servidor, inclusive drag-and-drop. Preservar estados existentes via mapeamento explícito. Histórico de etapa não deve ser sobrescrito. Propostas com validade, versão, moeda, memória de cálculo, limite e aprovação por pessoa diferente do criador. Não aprovar proposta expirada.
Matrícula comercial não equivale a ingresso efetivo. Secretaria valida documental e acadêmica; financeiro valida condição financeira, inclusive isenção formal; comercial não valida essas dimensões. Confirmar somente após três validações válidas; alterações posteriores requerem revalidação conforme regra institucional. Cancelamento justificado, auditado e refletido no BI.

## 5. MAIM 360° — catálogo de componentes
| Componente | Regra / saída | Prioridade |
|---|---|---|
| Score | Pontuação configurável por sinais objetivos de interesse e completude; razões explícitas | P1 |
| Distribution | Distribuição por escopo, capacidade, disponibilidade e desempate estável | P0 |
| Follow-up | SLA, estágio, elegibilidade, limite e próxima tarefa | P0 |
| Recovery | Oportunidades perdidas elegíveis, motivo e protocolo | P2 |
| Forecast | Meta restante, conversão observada, projeção e incerteza | P0 |
| Performance | Gargalos e indicadores por etapa/equipe, com denominadores | P1 |
| Learning | Lacunas em rubricas e recomendação de treinamento | P2 |
| Pricing | Limite, validade, custo e aprovação de ofertas | P0 |
| Quality | Pendências e divergências de validação e ingresso | P0 |
| Retention | Alertas de permanência e rematrícula com dados autorizados | P3 |
| Strategy | Propostas 5W2H vinculadas aos indicadores | P1 |
Fluxo: snapshot autorizado → regra pura versionada → proposta com justificativa → fila → aprovação quando necessária → revalidação → execução autorizada → auditoria e medição.
Chave idempotente por IES, oportunidade, regra, versão e evento/revisão; restrição única e transação para evitar duplicidade concorrente. Configurar timezone, limites, pausas, prioridade, orçamento e escopo. Inventariar scheduler e jobs existentes antes de criar novos. Execução programada somente após homologação e autorização de infraestrutura. Nenhuma API generativa, nenhuma mensagem externa; ação de simulação identificada como tal. Opt-out, elegibilidade, dados desatualizados e estados finais suprimem tarefas incompatíveis. Score não decide acesso à educação nem decisões laborais.

## 6. Dicionário mínimo de BI
| Indicador | Definição / regra |
|---|---|
| Oportunidades | IDs únicos no escopo e coorte; explicitar regra de inclusão |
| Matrículas comerciais | Fechamentos conforme evento e política de cancelamento explicitada |
| Ingressantes efetivos | Pessoas distintas com confirmação válida, reconciliadas com sistema acadêmico quando disponível |
| Conversão | Ingressantes efetivos / oportunidades da mesma coorte |
| Atingimento | Ingressantes efetivos / meta válida do mesmo escopo |
| Meta restante | max(meta - ingressantes, 0) |
| Oportunidades adicionais projetadas | ceil(meta restante / conversão observada não arredondada), se conversão positiva e amostra adequada |
| CPL | custo atribuído / leads elegíveis |
| Custo por matrícula | custo atribuído / matrículas, explicitando qual conceito |
| Receita potencial | soma das mensalidades ofertadas válidas, com período e natureza de projeção |
| Permanência 30/90 | ingressantes elegíveis com vínculo ativo na data de referência / coorte elegível |
Sem denominador ou fonte incompleta: N/D, nunca zero. Se meta cumprida: necessidade adicional zero; se meta não cumprida e conversão zero: projeção indisponível. Exibir cobertura, atualização, tamanho da amostra e regra de cancelamento. Paginação/aggregação completa no servidor; não limitar silenciosamente a 5.000 linhas. Comparar coortes e períodos equivalentes. Na captura, 14/(2/24)=168 sob a fórmula proposta; o valor 169 pode decorrer de arredondamento intermediário ou outra regra, a investigar. Não alterar sem reproduzir.

## 7. Planejamento, campanhas e aceleração
Planejamento com objetivos, metas por curso, orçamento, responsáveis, prazos, 5W2H, indicadores e revisão periódica. Campanhas com canal, coorte, vigência, orçamento, atribuição de origem, custo e resultados; distinguir atribuição desconhecida. Integrações Meta, Google, TikTok e WhatsApp opt-in, desligadas por padrão.
Protocolos próprios adaptados às referências: oferta educacional, networking/convênios, prospecção autorizada, webinar, evento, recuperação de base, embaixadores e indicações. Cada protocolo: elegibilidade, responsável, prazo, checklist, meta, custo e resultado. Sprints com entregas, impedimentos e reavaliação. Concorrência baseada em fontes verificáveis, datas e revisão humana; sem inventar ofertas.

## 8. Academia e relacionamento
Trilhas SDR, Closer, Farmer, liderança, produtos, ética e LGPD. Playbooks editáveis por funil, incluindo preparação, acolhimento, diagnóstico, apresentação, condições e próximos passos. Roleplay com cenários sintéticos, avaliação humana por rubricas versionadas, evidências, PDI, formação e reavaliação longitudinal. Competências: comunicação, escuta, domínio técnico, negociação ética, objeções, registro e disciplina operacional. Nenhuma nota automática definitiva por texto ou IA.
Relacionamento: indicações rastreáveis, embaixadores com regras transparentes, onboarding de ingressantes, acompanhamento 30/90 dias e rematrícula; integrações acadêmicas opcionais. Não presumir ausência de aluno a partir de dados incompletos.

## 9. Governança, segurança e infraestrutura
Manter GitHub, banco, autenticação e Render independentes de Vértice e Fato & Ordem. Reutilizar infraestrutura atual do próprio produto se confirmada. Master provisiona e concede escopos sem acesso automático a candidatos. RBAC granular por operação, IES, campus, curso; escopo nulo não significa curinga. Autorização em servidor e RLS, não apenas filtros UI. Testar acesso direto a APIs, alteração de IDs, revogação, escalonamento e exportação. Segredos somente no servidor. Auditoria legível com detalhe técnico restrito, sem PII desnecessária. Minimização, retenção, opt-out e base legal; documentos privados. Não contratar serviços, aplicar migração remota ou publicar produção sem autorização específica.

## 10. Backlog de investigação e aceite
| ID | Evidência / hipótese | Teste obrigatório |
|---|---|---|
| R01 | Nomes repetidos no CRM | Duas pessoas homônimas, mesma pessoa em dois funis, importação repetida |
| R02 | Propostas aparentemente repetidas | Reenvio idempotente, versões legítimas, aprovação por terceiro, expiração |
| R03 | Projeção 169 | Reproduzir coorte, fórmula, arredondamento final, taxa zero, meta cumprida |
| R04 | 24 tarefas de primeiro contato | Elegibilidade por etapa, estado final, opt-out, reexecução e concorrência |
| R05 | Campos de metas vazios apesar de valores no BI | Carregamento, edição, persistência, isolamento, erro de rede |
| R06 | Agrupamento por curso inclui turno/modalidade | Conferir chave de agrupamento, filtro e totais |
| R07 | Botão Disparar em modo desativado | Simulação clara, nenhuma entrega externa, registro de tentativa |
| R08 | Auditoria JSON bruto | Visualização legível sem perder evento original; acesso restrito |
| R09 | Rotas /ies/1 e ?ies=1 | Alteração de URL, API direta, duas IES, escopo de curso |
| R10 | Campanhas e Academia informativas | CRUD, persistência, autorização, integração e testes antes de marcar concluído |
Além destes: testes de regressão v0.1, responsividade, teclado, contraste, loading/error/empty, paginação, limites de volume, cálculos, auditoria, transações e rollback. Usar dados sintéticos. Cada entrega exige PR, SHA, testes com saída, evidências de navegador, revisão de segurança e lista de pendências.

## 11. Ondas de entrega e reversão
P0: inventário do código e rotas; design system; dashboard; CRM; conversão; governança; R01–R09. P1: planejamento, campanhas, funis, MAIM ampliado. P2: recuperação, academia, competências. P3: relacionamento, permanência, rematrícula, integrações.
Cada onda deve ser incremental, com migrações compatíveis, feature flags desativadas por padrão para novas automações, backup e procedimento de reversão testado. Reverter UI por versão; pausar regras e scheduler; preservar eventos e registros históricos; não apagar matrículas para desfazer release.
Não marcar módulo como concluído por página estática, mock ou teste isolado. Estados: especificado, implementado, testado localmente, homologado, publicado; exigir evidência para cada avanço.

## 12. Referências e registro cumulativo
Referências conceituais: Scan_20261125_110622.pdf (13 páginas, operação e funis); Scan_20261125_112105.pdf (22 páginas, aceleração, formação e relacionamento); Scan_20261125_113230(1).pdf (36 páginas, processo de vendas e competências); Scan_20261125_114015.pdf (1 página, composição de ofertas). Total 72 páginas. Preservar autoria e desenvolver conteúdo próprio; não assumir eficácia ou valores comerciais anunciados. Oito capturas de homologação de 25/11/2026 (image(1).png a image(8).png).
| Versão | Entrega | Evidência | Pendência |
|---|---|---|---|
| v0.1 | Base local | Documento histórico e testes locais relatados | Infraestrutura e segurança |
| v0.2 | Atualização cumulativa de requisitos | Oito capturas e quatro materiais, análise visual | Inventário remoto, implementação e homologação |
Esta atualização é exclusivamente documental. Nenhum código remoto, banco, publicação ou configuração foi alterado. Nenhum teste de execução foi realizado nesta atualização.

---

# Anexo histórico — v0.1 integral

# Matrícula 360° — Bíblia-Mestra v0.1
25/11/2026 — produto independente, inicialmente ensino superior privado. Nome provisório. Não depende da Vértice ou Fato & Ordem; integrações futuras opcionais. IA e envios externos desativados. Nenhuma infraestrutura paga autorizada.

## Requisitos cumulativos
Preservar docs/REFERENCIA-COMERCIAL360.md como histórico conceitual. Os quatro documentos discutidos (13+22+36+1 páginas) são referências, não material proprietário a reproduzir; conferir originais antes de atribuições específicas. Sem promessas de resultado comercial. Adaptar SDR/Closer/Farmer, funis, protocolos de recuperação, playbooks, rubricas, academia, propostas, margens e fidelização.

| Código | Requisito | Estado |
|---|---|---|
| M01 | Página comercial responsiva | HTML local |
| M02 | Master e provisionamento de IES; autenticação, convites, perfis e permissões por operação/campus/curso | Pendente |
| M03 | Cadastro IES, unidades, cursos, turnos, modalidades, campanhas e metas | Modelo SQL parcial |
| M04 | CRM, importação deduplicada, histórico, formas de ingresso, pipeline versionado | Demo em memória; motor testado |
| M05 | MAIM: SLA, distribuição, cadências, supressão, aprovação e revalidação | Follow-up interno inicial; restante pendente |
| M06 | Bolsas, propostas, limites, validade, custos, margens e aprovação | Função de cálculo inicial |
| M07 | Matrícula comercial, documental, financeira e acadêmica separadas; ingresso efetivo e cancelamentos | Regra inicial de confirmação |
| M08 | Recuperação, indicação e reingresso | Backlog |
| M09 | BI por coorte, período, IES, curso, turno e atendente; indisponível distinto de zero | Métrica e simulador iniciais |
| M10 | Academia, scripts, rubricas, PDI, reavaliação e treinamento | Backlog |
| M11 | Permanência em 30/90 dias, rematrícula, concorrência e planejamento | Backlog |
| M12 | Integrações opcionais: WhatsApp, Meta, Google, TikTok, sistemas acadêmicos, Vértice, Fato & Ordem | Backlog; desligadas |

## Segurança e governança
Somente dados sintéticos nesta versão. Master não tem acesso irrestrito ao conteúdo de candidatos por padrão. Reitoria e gestores recebem escopos explícitos. Coordenador apenas cursos autorizados. Secretaria valida documentação/academia; financeiro valida condição financeira (incluindo isenção formal); comercial não valida as três dimensões. Perfis são modelos de permissões, não autorização via cliente. Auditoria imutável para usuários comuns, segregação de funções, idempotência, versionamento, proteção contra concorrência e revogação. LGPD: finalidade, base legal, minimização, retenção, exclusão, acesso, opt-out por canal; não importar listas sem origem e elegibilidade. Sem uso de pontuação para negar ingresso.

## Funis
Vestibular, ENEM, transferência, segunda graduação, portador de diploma (evitar duplicidade de categoria quando equivalentes), reingresso, indicação, convênios, visitas escolares, eventos, pós-graduação. Configurar por IES. Não contar uma mesma pessoa como múltiplos ingressantes no BI consolidado; reconciliar IDs com sistema acadêmico.

## Critérios de aceite
Testar duas IES e dois cursos por IES, usuário revogado, IDs adulterados, alteração direta de campos, conflito de versão, repetição de evento, zero vs indisponível, denominador por coorte, cancelamento, confirmação incompleta, opt-out, falta de base legal, desconto excessivo, ausência de envio externo. Homologar no navegador móvel e desktop; registrar evidências e riscos. Não publicar antes de autorização e validação.

## Estado da entrega
16 testes unitários locais. SQL é proposta não executada; não há login, API real, escrita remota, integração ou persistência. Demo apenas em memória. React/TypeScript/Tailwind, Supabase Auth, RLS, Render e GitHub são destino arquitetural, não componentes já implantados. Próxima entrega: projeto novo, migrações geradas via CLI, RPCs com autorização e auditoria transacional, UI autenticada e testes de isolamento reais. Preservar histórico e atualizar Bíblia a cada PR.
