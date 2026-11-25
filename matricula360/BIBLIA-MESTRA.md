# Matrícula 360° — Bíblia-Mestra v0.2
Atualizada em 25/11/2026 com o piloto local. A versão v0.1 está preservada sem alteração em `docs/original/BIBLIA-MESTRA-v0.1.md`.

Produto independente, voltado inicialmente ao ensino superior privado. Nome provisório. Não depende da Vértice nem do Fato & Ordem; integrações futuras são opcionais. IA e envios externos estão desativados. Nenhuma infraestrutura paga foi autorizada.

## Requisitos cumulativos
Preservar `docs/REFERENCIA-COMERCIAL360.md` como histórico conceitual. **[Não recebido no pacote v0.1; precisa ser reenviado.]** Os quatro documentos discutidos (13+22+36+1 páginas) são referências, não material proprietário a reproduzir; conferir os originais antes de atribuições específicas. Sem promessas de resultado comercial. Adaptar SDR/Closer/Farmer, funis, protocolos de recuperação, playbooks, rubricas, academia, propostas, margens e fidelização.

| Código | Requisito | Estado v0.1 | Estado v0.2 (piloto local) |
|---|---|---|---|
| M01 | Página comercial responsiva | HTML local | Preservada; link para o piloto |
| M02 | Master e provisionamento de IES; autenticação, convites, perfis e permissões por operação/campus/curso | Pendente | **Piloto:** login com sessão no servidor; Master provisiona IES, concede e revoga escopos e usuários; permissões por IES e curso validadas no servidor. Convite por e-mail: pendente (envio desligado; senha temporária exibida uma vez) |
| M03 | Cadastro de IES, unidades, cursos, turnos, modalidades, campanhas e metas | Modelo SQL parcial | **Piloto:** IES, campus, cursos, turnos, modalidades e metas por curso e coorte. Campanhas: backlog |
| M04 | CRM, importação deduplicada, histórico, formas de ingresso, pipeline versionado | Demo em memória; motor testado | **Piloto:** Kanban, importação deduplicada (e-mail/telefone) com relatório de rejeições, histórico auditado, 10 formas de ingresso, versão otimista |
| M05 | MAIM: SLA, distribuição, cadências, supressão, aprovação e revalidação | Follow-up interno inicial | **Piloto:** SLA configurável, distribuição por escopo e capacidade, follow-up com limite, supressão por opt-out, revalidação na execução, pendências de validação, disparo bloqueado e auditado |
| M06 | Bolsas, propostas, limites, validade, custos, margens e aprovação | Função de cálculo inicial | **Piloto:** propostas em centavos, limite por curso, aprovação por gestor com segregação (quem cria não aprova), validade e expiração. Custos e margens: pendente |
| M07 | Matrícula comercial, documental, financeira e acadêmica separadas; ingresso efetivo e cancelamentos | Regra inicial de confirmação | **Piloto:** etapas separadas; validação com evidência por papel; confirmação atômica, também protegida no banco; cancelamento sem apagar histórico |
| M08 | Recuperação, indicação e reingresso | Backlog | **Parcial:** recuperação de perdidos com tarefa; indicação e reingresso como formas de ingresso. Protocolos de recuperação: backlog |
| M09 | BI por coorte, período, IES, curso, turno e atendente; indisponível distinto de zero | Métrica e simulador iniciais | **Piloto:** BI por coorte, agrupado por curso, turno, modalidade, forma de ingresso ou atendente; `N/D` distinto de 0; pessoas distintas no consolidado; projeção de oportunidades necessárias |
| M10 | Academia, scripts, rubricas, PDI, reavaliação e treinamento | Backlog | Backlog |
| M11 | Permanência em 30/90 dias, rematrícula, concorrência e planejamento | Backlog | Backlog |
| M12 | Integrações opcionais | Backlog; desligadas | Backlog; desligadas. O servidor recusa iniciar se houver tentativa de ligar envio externo |

## Segurança e governança
Somente dados sintéticos nesta versão. O Master não acessa conteúdo de candidatos por padrão (**implementado e testado**). Reitoria e gestores recebem escopos explícitos. O coordenador vê apenas cursos autorizados, com contatos mascarados (**implementado e testado**). A secretaria valida as dimensões documental e acadêmica; o financeiro valida a financeira, incluindo isenção formal; o comercial não valida nenhuma das três (**implementado e testado**). Perfis são modelos de permissões, não autorização via cliente: toda decisão de acesso ocorre no servidor.

Também implementado no piloto:
- auditoria imutável, garantida por gatilho no banco;
- segregação de funções;
- idempotência por chave;
- versionamento otimista e proteção contra concorrência;
- revogação imediata de sessão e de escopo;
- LGPD: base legal e origem obrigatórias, minimização com mascaramento, opt-out por canal, anonimização e auditoria sem dados pessoais.

Não há pontuação de candidatos; nenhuma pontuação é usada para negar ingresso.

## Funis
Vestibular, ENEM, transferência, segunda graduação, reingresso, indicação, convênios, visitas escolares, eventos e pós-graduação. Portador de diploma foi unificado com segunda graduação para evitar dupla contagem. A mesma pessoa não conta como múltiplos ingressantes no consolidado (**testado**). Pendentes: configuração de funis por IES e reconciliação de IDs com o sistema acadêmico.

## Critérios de aceite
Testar:
- duas IES e dois cursos por IES;
- usuário revogado;
- IDs adulterados;
- alteração direta de campos;
- conflito de versão;
- repetição de evento;
- zero × indisponível;
- denominador por coorte;
- cancelamento;
- confirmação incompleta;
- opt-out;
- falta de base legal;
- desconto excessivo;
- ausência de envio externo.

Homologar em navegador móvel e desktop e registrar evidências e riscos. **Situação v0.2:** todos os critérios têm teste automatizado, e a homologação local foi feita em desktop e celular. Ver `docs/HOMOLOGACAO-PILOTO.md`. Não publicar antes de autorização e validação.

## Estado da entrega
- **v0.2, piloto local:** Node 22 sem dependências externas, SQLite (`node:sqlite`), 42 testes e 83 verificações no navegador. Escuta só em `127.0.0.1`.
- **Supabase (preparado, não aplicado):** `supabase/migrations/` com RLS em todas as tabelas, escrita apenas por RPC com auditoria transacional, e 69 verificações de isolamento aprovadas em Postgres 16 real. Projeto remoto autorizado em 25/11/2026, em org própria gratuita "Matricula360" (decisão: independência da Vértice e custo zero); criação pendente de reconexão do conector.
- **Ainda não é:** produção, Supabase/RLS, React/TypeScript/Tailwind, implantação no Render nem integração externa.
- **Próxima entrega, que depende de autorização de infraestrutura:**
  1. projeto Supabase de homologação e migrações via CLI a partir de `src/schema.sql`;
  2. RLS com testes de isolamento no banco;
  3. RPCs equivalentes às operações de `src/servico.mjs`;
  4. frontend em React/TypeScript/Tailwind;
  5. Playwright e auditoria de acessibilidade com axe.

Preservar o histórico e atualizar esta Bíblia a cada PR.
