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
