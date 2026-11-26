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
