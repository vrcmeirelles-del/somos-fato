# Matrícula 360° — o que falta para ser "360°" frente à concorrência (26/11/2026)

**Método.** Pesquisa web em fontes públicas, feita em 26/11/2026.
- **Produtos pesquisados:** Slate (Technolutions), Salesforce Education Cloud, Anthology Reach, Ellucian CRM Recruit, RD Station, materiais da Rubeus, TOTVS, Pipedrive, Quero Educação e Fundacred.
- **Ressalva:** a maior parte é material dos próprios fornecedores. Não foram verificadas integrações, preços nem o desempenho real dos produtos. Os módulos da Rubeus não estão publicados em detalhe. Não encontrei documentação pública de integração com Quero Bolsa ou Educa Mais Brasil, nem informação sobre os produtos "Gioconda" e "Lyceum CRM".

## 1. Onde o Matrícula 360° já está no nível do mercado ou acima
- **Funil completo e auditado:** do lead ao ingresso efetivo, com as três validações separadas (documental, financeira e acadêmica) e cancelamento refletido no BI.
- **Indicadores com denominador e N/D:** projeção da Bíblia §6, CPL, custo por ingressante e permanência com cobertura. Nos materiais consultados, os concorrentes destacam painéis, mas não esse rigor metodológico.
- **Governança:**
  - escopo explícito por instituição, campus e curso;
  - matriz de permissões verificada por teste;
  - visibilidade por atribuição;
  - auditoria legível;
  - exportação com minimização de dados.
- **Camadas de gestão que os CRMs de captação não trazem nativamente:** planejamento com 5W2H, funis versionados, recuperação com elegibilidade LGPD, Academia (avaliação humana e PDI) e relacionamento sem presumir evasão.

## 2. Lacunas em relação à concorrência

| # | Lacuna | Onde aparece no mercado | Impacto no "360°" | Depende de serviço externo ou autorização? |
|---|---|---|---|---|
| L1 | **Formulários e landing pages públicos** que criam o lead sozinhos, com consentimento LGPD e código de campanha | Caso UCDB/RD Station: landing com 4 perguntas e custo por matrícula 58% menor; Cognita com mais de 100 formulários roteando para funis; microsites do Slate | **Crítico.** Hoje o lead só entra por cadastro manual ou importação. Sem isso não há topo de funil digital. | Banco: não. Exige proteção antirrobô (captcha), um serviço externo sujeito a autorização. Também se pode publicar sob o domínio atual. |
| L2 | **Portal do candidato**: status da inscrição, pendências e próximos passos | Slate (portal mobile-first e página de status), Salesforce (barra de status e lista de tarefas), Ellucian (portal de autoatendimento) | **Alto.** O candidato não acompanha nada sozinho. | Login do candidato por e-mail = envio externo. Exige autorização. |
| L3 | **Documentos com upload seguro e checklist** | Salesforce (checklist documental com upload), Bíblia §4 ("documentos protegidos") | **Alto.** A validação documental hoje é só um registro, sem o documento. | Armazenamento privado no Supabase (plano Free). Sem novo contrato. |
| L4 | **Inscrição e processo seletivo online** (prova objetiva/redação, agendamento, nota do ENEM) e **divulgação do resultado** | Slate (application management, decision release), Fundacred e Quero (vestibular digital) | **Alto** para a captação de vestibular. | Correção de redação é humana. Sem IA (Bíblia). |
| L5 | **Matrícula online**: aceite de contrato com assinatura eletrônica e emissão da 1ª cobrança | TOTVS (matrícula e rematrícula online), Pipedrive (assinatura eletrônica) | **Alto.** Fecha o ciclo comercial sem papel. | Assinatura eletrônica e cobrança são serviços externos pagos. Exigem contrato. |
| L6 | **Comunicação omnicanal com réguas automáticas** (e-mail, SMS, WhatsApp) e métricas de abertura e clique | Ellucian (planos de comunicação multicanal), Anthology Reach, Rubeus com Infobip, Slate (e-mail e SMS) | **Crítico** para a operação diária. | Hoje o envio está desligado por regra. Exige provedor (custo), consentimento e autorização expressa. |
| L7 | **Eventos e visitas** (open house, tour, aula experimental) com inscrição e check-in | Ellucian (eventos com check-in), Slate e Brandeis (eventos), Kent State | **Médio-alto.** Eventos e visitas escolares são forte canal no Brasil. | Não. |
| L8 | **Integração com o sistema acadêmico/ERP** (matrícula efetiva, vínculo, rematrícula) | Ellucian (Banner e Colleague), Salesforce (ciclo completo), Anthology com Blackboard | **Alto** para permanência real. Hoje o vínculo é registrado à mão. | Depende do sistema da instituição. Exige credenciais e autorização. |
| L9 | **Integrações de mídia e de marketplaces de bolsas** (Meta, Google, TikTok, Quero Bolsa, Educa Mais Brasil) para leads e custos automáticos | RD Station (integração com CRMs educacionais); Quero (sem documentação pública de integração) | **Médio.** Elimina o lançamento manual de custo e de leads. | Sim: contas, credenciais e autorização. |
| L10 | **Atendimento conversacional 24h** (agente ou chatbot) | Salesforce (agente de recrutamento, em beta), Quero IA | **Exclusão deliberada.** A Bíblia proíbe IA generativa neste estágio. | Decisão do responsável, se um dia mudar a regra. |
| L11 | **Alerta precoce acadêmico** a partir do ambiente virtual (frequência, notas) | Anthology Reach com Blackboard (engagement score) | **Médio** (P3). Depende da L8. | Sim. |

## 3. Proposta de sequência (fase P4: "ponta a ponta digital")
Ordenada por impacto e por dependência de autorização. Itens sem serviço externo vêm primeiro.
1. **L1 Formulário público de captação**
   - Página pública por curso e campanha, com aceite LGPD e base legal registrada.
   - Gravação por RPC anônima com limites (taxa por origem, validação, sem leitura pública).
   - Antirrobô: começar com proteção própria (campo-isca e limite por IP no banco). Captcha externo só com autorização.
2. **L3 Documentos protegidos**: armazenamento privado no Supabase, acesso por RLS, checklist por forma de ingresso, validação documental vinculada ao arquivo.
3. **L7 Eventos e visitas**: cadastro, inscrição pelo formulário público, presença (check-in) e conversão por evento.
4. **L4 Inscrição e processo seletivo online**: inscrição, agendamento, nota do ENEM declarada e conferida, redação corrigida por pessoa, resultado auditado.
5. **L2 Portal do candidato**: depende de envio de e-mail (login por link). **Requer autorização.**
6. **L6 Comunicação omnicanal**: régua por etapa do funil, usando a cadência já existente. **Requer provedor, custo e autorização**; opt-out já implementado.
7. **L5, L8 e L9**: matrícula online, integração acadêmica e mídia/marketplaces. **Requerem contratos e credenciais.**

## Fontes
- Slate: [technolutions.com/solutions](https://technolutions.com/solutions), [application management](https://technolutions.com/admissions/application-management), [microsites](https://technolutions.com/admissions/microsites), [G2](https://www.g2.com/products/slate-by-technolutions/features), [Brandeis](https://www.brandeis.edu/its/software-systems/slate.html), [Kent State](https://www.kent.edu/node/958877), [Framingham](https://framingham.teamdynamix.com/TDClient/1792/ServiceHub/KB/PrintArticle?ID=157179), [Capterra](https://www.capterra.com/p/140281/Slate/)
- Salesforce Education Cloud: [recruitment & admissions](https://salesforce.com/education/recruitment-admissions-software), [datasheet FY26 Q3](https://www.salesforce.com/en-us/wp-content/uploads/sites/4/Industry%20-%20Education/FY26-Q3-EDU-Recruitment-and-Admissions-Datasheet_v15.pdf), [Education Cloud](https://salesforce.com/education/cloud)
- Anthology Reach: [capabilities](https://www.anthology.com/products/lifecycle-engagement/enrollment-and-retention/anthology-reach/capabilities), [release jul/2025](https://www.businesswire.com/news/home/20250716388523/en/Anthology-Reach-Redefines-Student-Success-with-Real-Time-Alerts-Intelligent-Outreach-and-Personalized-Communications), [datasheet](https://backstage.anthology.com/sites/default/files/2025-11/Reach-Datasheet_11-25.pdf)
- Ellucian CRM Recruit: [solução](https://Ellucian.com/solutions/ellucian-crm-recruit), [solution sheet](https://www.ellucian.com/assets/en/solution-sheet/ellucian-crm-recruit.pdf), [G2](https://www.g2.com/products/ellucian-crm-recruit), [G2 vs Slate](https://g2.com/compare/ellucian-crm-recruit-vs-slate-by-technolutions), [TrustRadius](https://www.trustradius.com/products/ellucian-crm-recruit)
- Brasil: [RD Station — caso UCDB](https://www.rdstation.com/historias-de-sucesso/ucdb/), [ActiveCampaign — Cognita](https://www.activecampaign.com/br/customers/cognita-schools-brasil), [TOTVS — CRM educacional](https://www.totvs.com/blog/instituicao-de-ensino/crm-educacional/), [Pipedrive — ensino superior](https://www.pipedrive.com/pt/industries/higher-education-crm), [RD Station — integração CRM Rubeus](https://www.rdstation.com/integracoes/crm-rubeus), [Infobip — Rubeus](https://www.infobip.com/pt/cliente/rubeus), [Fundacred — vestibular digital](https://www.baguete.com.br/noticias/fundacred-cria-plataforma-de-vestibular-digital), [ABMES — Quero Educação](https://www.abmes.org.br/blog/detalhe/18346/quero-educacao-ajuda-na-expansao-do-ead)

## 4. Segunda rodada (26/11/2026, depois da P4 e da migração 22)

**Situação.** As lacunas L1 a L9 estão implementadas. L5 foi reforçada pela migração 22. L6, L8 e L9 funcionam por simulação ou planilha e esperam fornecedor e autorização. L10 é uma exclusão deliberada, e L11 depende da L8. Esta rodada compara o produto com o **ciclo de vida completo**: candidato, ingressante, aluno, rematrícula e egresso. Esse é o recorte que Salesforce, Anthology e EAB usam ao vender "360".

**Ressalva.** A pesquisa usou fontes públicas, na maior parte material dos próprios fornecedores e avaliações de usuários. Não verifiquei preço, versão nem funcionamento real dos produtos. A Rubeus não publica detalhes de rematrícula. Não achei produto de CRM específico para polos de EAD; o item L18 se apoia em páginas de parceiros e na regulação.

| # | Lacuna | Onde aparece | Situação no Matrícula 360° | Impacto | Depende de serviço externo? |
|---|---|---|---|---|---|
| L12 | **Bolsas, descontos e financiamento**: ProUni, FIES, financiamento próprio ou privado, convênios com empresas; política por curso, elegibilidade, documentos e efeito no tíquete | Slate (gestão de bolsas e de pedidos de bolsa); regras do ProUni (bolsa integral ou parcial de 50%) e do FIES (seguro prestamista, contrato com o banco) | Só o desconto da proposta, com aprovação por limite | **Alto.** No Brasil, financiamento e bolsa decidem boa parte das matrículas | Não para a gestão. Consulta a sistemas do MEC ou de bancos: sim |
| L13 | **Financeiro do ingresso e inadimplência**: 1ª mensalidade, situação de pagamento, renegociação, bloqueio de rematrícula de inadimplente | TOTVS (Meu eduCONNECT: renegociação pelo aluno; parâmetro "bloquear matrícula para inadimplentes") | Integração de cobrança registrada, mas desligada | **Alto** para receita | Cobrança real: sim, paga. Conciliação por planilha: não |
| L14 | **Rematrícula ativa**: campanha semestral, aceite de rematrícula pelo portal, pendências e meta por curso | TOTVS (matrícula e rematrícula online pelo portal do aluno) | Só o marco "rematrícula" do vínculo (migração 17) e o alerta retention-v1 | **Alto.** É a receita recorrente | Não. Reaproveita o aceite reforçado |
| L15 | **Sucesso do aluno**: casos com triagem e roteamento, trilhas de intervenção por tipo de alerta, agendamento de atendimento, lista de acompanhamento, plano de ação do aluno | Salesforce Student Success (casos, roteamento, lista de observação, agendamento, plano de ação); EAB Navigate (alertas, casos, relatórios de progresso, trilhas de intervenção) | Alertas sem fluxo de tratamento | **Alto** para permanência | Não. Dados do ambiente virtual: L11 |
| L16 | **Pesquisas de pulso e de satisfação**: atendimento, ingressante, quem desistiu ou se perdeu ("por que não escolheu") | Salesforce (pesquisas de pulso periódicas) | Não existe | **Médio.** Qualifica a análise de perdas e de permanência | Não, se respondida no portal. Envio: L6 |
| L17 | **Captação em campo**: feiras, visitas a escolas de ensino médio, cadastro de escolas, QR code do representante, captura sem internet com sincronização | Slate (viagens, visitas a escolas, feiras, check-in por QR, acompanhamento automático); Gecko e Handshake (captura offline por QR) | Eventos e formulário público só online; sem cadastro de escolas | **Médio-alto.** Visita a escola é canal forte no Brasil | Não. PWA offline não tem custo |
| L18 | **Canal de parceiros e polos EAD**: acesso restrito do parceiro, metas, funil e repasse | Modelo de polos parceiros (ex.: Uninter); regulação de polos pelo MEC, com limite por conceito institucional | Escopo por campus serve de base, mas não há parceiro externo | **Médio** (alto se houver EAD com polos) | Não para a gestão. Cálculo de repasse depende de regra contratual e jurídica |
| L19 | **Banca e análise acadêmica**: vários avaliadores, rubrica calibrada, comitê; aproveitamento de estudos para transferência e segunda graduação | Slate Reader (formulários de avaliação, rubricas, comitês, distribuição para avaliadores; avaliações de usuários apontam usabilidade fraca) | Decisão humana única, com justificativa (migração 20) | **Médio** | Não |
| L20 | **Egressos e ciclo de vida**: portal do egresso, pós-graduação e segunda graduação para ex-alunos, indicações | Salesforce (portal de egressos), Anthology Raise (módulo pago de egressos) | Não existe | **Médio-baixo** no piloto. Alto para pós-graduação | Não |
| L21 | **Caixa de entrada conversacional humana**: WhatsApp e SMS dentro do CRM, com histórico na ficha; não é robô | Rubeus com Infobip (WhatsApp e SMS em toda a jornada, conversas antes feitas fora do CRM) | Interações registradas à mão; texto para envio manual | **Crítico na operação brasileira** | Sim: API oficial do WhatsApp e provedor, pagos |
| L22 | **Plataforma**: 2FA da equipe, auditoria de acessibilidade (WCAG), API e webhooks, campos personalizados, construtor de relatórios, app instalável | [Inferência] padrão de mercado; não conferido produto a produto nesta rodada | 2FA, WCAG e API ausentes; exportação existe | **Médio.** 2FA é alto para segurança | 2FA: [Não verificado] se o plano gratuito do Supabase Auth inclui TOTP. API própria: não |

### Sequência recomendada
- **Onda A (sem custo externo e de maior impacto):**
  - L12 bolsas e financiamento;
  - L14 rematrícula ativa;
  - L15 sucesso do aluno (casos e trilhas);
  - L22, só a parte de segurança e acessibilidade: 2FA e WCAG.
- **Onda B:**
  - L17 captação em campo (escolas, QR, offline);
  - L16 pesquisas;
  - L19 banca e aproveitamento.
- **Onda C (depende de decisão, contrato ou custo):**
  - L21 WhatsApp no CRM;
  - L13 cobrança;
  - L18 polos com repasse;
  - L20 egressos;
  - L11.

### Fontes da segunda rodada
- Salesforce: [student success software](https://www.salesforce.com/education/student-success-software/), [Education Cloud](https://salesforce.com/education/cloud)
- EAB Navigate: [produto](https://eab.com/navigate), [guia de alertas, casos e relatórios de progresso](https://www.wisconsin.edu/ss-eab-project/download/EAB-Guide-to-Alerts-Cases-and-Progress-Reports-12-04-18.pdf), [módulo de recrutamento](https://eab.com/about/newsroom/press/eabs-navigate-platform-now-supports-student-recruitment-and-retention/)
- Slate: [solutions](https://technolutions.com/solutions), [application management](https://technolutions.com/admissions/application-management), [G2 reviews](https://g2.com/products/slate-by-technolutions/reviews), [TrustRadius](https://www.trustradius.com/products/technolutions-slate)
- Anthology: [Reach capabilities](https://www.anthology.com/products/lifecycle-engagement/enrollment-and-retention/anthology-reach/capabilities), [Reach](https://anthology.com/solutions/enterprise-applications/reach)
- Rubeus: [caso Infobip](https://www.infobip.com/pt/cliente/rubeus), [integração RD Station](https://www.rdstation.com/integracoes/crm-rubeus)
- TOTVS: [Meu eduCONNECT](https://www.totvs.com/educacional/meu-educonnect/), [CRM educacional](https://www.totvs.com/blog/instituicao-de-ensino/crm-educacional/), [rematrícula (TDN)](https://tdn.totvs.com.br/download/attachments/4814795/Como%20Fazer%20TOTVS%20-%2010%20-%20Cadastros%20e%20processo%20de%20Rematricula.pdf?api=v2)
- Captação em campo: [Gecko Event Inquiry Capture](https://geckoengage.com/platform/inquiry-capture), [Handshake](https://support.joinhandshake.com/hc/en-us/articles/17156393056407), [StriveScan](https://apps.apple.com/us/app/strivescan/id1149041297)
- Regulação e polos: [ABMES FAQ (FIES)](https://abmes.org.br/index.php/faq), [MEC — acesso à educação superior](https://www.gov.br/mec/pt-br/centrais-de-conteudo/publicacoes/acesso-educacao-superior), [ABMES — regulamentação EAD](https://abmes.org.br/blog/detalhe/13406), [gov.br — inserção de polo EAD](https://www.gov.br/pt-br/servicos/informar-criacao-de-polo-ead), [Uninter — seja parceiro](https://www.uninter.com/seja-parceiro/)
