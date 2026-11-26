# Homologação do piloto local — v0.2 (25/11/2026)

**Escopo:** homologação **local**, com dados sintéticos. Não houve homologação em ambiente remoto, porque nenhuma infraestrutura foi autorizada. Este documento não atesta prontidão para produção.

## Resultado

| Bateria | Comando | Resultado |
|---|---|---|
| Unitários, domínio e API (HTTP real) | `npm test` | **42/42 aprovados** (`evidencias/saida-testes.txt`) |
| Navegador, desktop 1366×860 e iPhone 13 | `npm run homologar` | **83/83 verificações** (`evidencias/resultado.json`) |
| Bateria de RLS no **Supabase real** (projeto de homologação) | SQL Editor: `supabase/TESTAR-NO-SQL-EDITOR.sql` | **138/138** com as migrações 1 a 5 (rodada anterior: 107/107 com as migrações 1 a 4); tudo desfeito ao final |
| **Telas ligadas ao Supabase real**, desktop e iPhone 13, 7 perfis | `npm run` → `scripts/homologar-supabase.mjs` | **63/63** (`evidencias/supabase/resultado.json`) |
| **Interface React/TypeScript/Tailwind** ligada ao Supabase real (desktop + iPhone 13) | `npm run homologar:supabase` | **66/66** (`evidencias/supabase/resultado.json`); telas legadas no mesmo roteiro: 66/66 |
| **Site publicado no Render** (`matricula360-homologacao.onrender.com`), desktop + iPhone 13 | `M360_BASE_EXTERNA=… npm run homologar:supabase` | **66/66** (`evidencias/publicado/resultado.json`) |
| **Nova interface (Fase 2) no site publicado**, desktop + iPhone 13 | `M360_BASE_EXTERNA=… npm run homologar:supabase` | **83/83** (`evidencias/publicado/resultado.json`) |
| Unitários da interface React (Vitest) | `npm run web:test` | **12/12** |
| Migrações Supabase em **Postgres 16 real** (RLS, RPCs, gatilhos) | `npm run testar:postgres` | **107/107 verificações de RLS e regras + corrida real entre 2 sessões + lint (RLS em 100% das tabelas, search_path fixo em 100% das funções)** |

A verificação no navegador cobre seis perfis: público, gestor, comercial, secretaria, coordenação e Master. Em cada tela checa:

- ausência de rolagem horizontal da página;
- campos com rótulo acessível;
- nenhum erro de console ou de CSP.

Também cobre os fluxos: cadastro com base legal, proposta acima do limite indo para aprovação, validação com evidência, ciclo MAIM, mascaramento de dados para a coordenação e bloqueio do Master sem escopo.

## Supabase remoto — projeto de homologação `jbimijcvvekomovodfze` (25/11/2026)

O usuário aplicou `supabase/APLICAR-NO-SQL-EDITOR.sql` pelo SQL Editor. A conferência externa foi feita pela API REST, com a chave publicável (papel `anon`):

| Verificação | Resposta obtida | Conclusão |
|---|---|---|
| GET `ies`, `oportunidades`, `pessoas`, `auditoria` | 401, `42501 permission denied for table` | Tabelas existem; `anon` sem acesso |
| GET tabela inexistente (controle) | 404, `PGRST205` | Distingue "existe e bloqueado" de "não existe" |
| POST `rpc/rpc_bi` | 401, `42501 permission denied for function` | RPCs existem; `anon` não executa |
| POST `rpc/auditar` (auxiliar interno) | `PGRST202` não encontrada | Schema `privado` não exposto pela API |

**Bateria de isolamento no banco real (25/11/2026):** o usuário executou `supabase/TESTAR-NO-SQL-EDITOR.sql` no SQL Editor do projeto. A bateria troca de papel entre `anon` e `authenticated` e simula o JWT de cada perfil. Resultado devolvido pelo Supabase:

```
ERROR: P0001: RESULTADO: 107 verificações aprovadas, 0 falhas (tudo desfeito; nada ficou gravado)
```

O "erro" é proposital: a exceção final desfaz a semente e os testes. As 107 verificações cobrem:
- isolamento entre IES e entre cursos;
- Master sem acesso a candidatos;
- revogação de usuário e de escopo;
- escrita direta bloqueada;
- segregação de funções;
- versão otimista;
- idempotência;
- LGPD;
- BI com N/D;
- MAIM;
- anonimização.

**Pendente no remoto:**
- **Security Advisor (25/11/2026):** 0 erros, 24 avisos e 1 sugestão (a sugestão ainda não foi conferida).
  - Os 24 avisos são todos do tipo *"Signed-In Users Can Execute SECURITY DEFINER Function"*, um para cada uma das 24 RPCs `public.rpc_*`.
  - **Risco aceito, por desenho:** o cliente não tem permissão de escrita nas tabelas, e as RPCs são a única via de escrita. Cada RPC valida `auth.uid()`, o escopo (IES e curso) e o papel antes de gravar, usa `search_path` vazio e grava a auditoria na mesma transação.
  - Mitigações comprovadas pela bateria de 107 verificações no banco real.
  - Os auxiliares `SECURITY DEFINER` ficam no schema `privado`, não exposto, e por isso não entram no aviso.
  - **Reavaliar se:** alguma RPC passar a aceitar SQL dinâmico vindo do cliente, ou alguma deixar de chamar `privado.exigir_usuario()`/`carregar_op()`.
- **Security Advisor, item Info:** *"RLS Enabled No Policy"* em `privado.idempotencia`. **Proposital:** a tabela deve ser invisível ao cliente, e isso está coberto por um teste da bateria.
- **Performance Advisor (25/11/2026):** 0 erros, 0 avisos e 14 sugestões.
  - **9 *Unindexed foreign keys*:** corrigidas na migração 4 (`20261125000004_indices_fk.sql`), que inclui ainda mais 3 FKs cobertas só por índices parciais. Verificação local: nenhuma FK fica sem índice; a migração é idempotente; os 107 testes continuam verdes.
  - **5 *Unused Index*:** não se aplicam por ora, porque o banco está vazio e sem uso. Reavaliar após uso real.
- **Migração 5 (RPCs de leitura) aplicada em 25/11/2026.** Na sequência, a bateria completa rodou no banco real: `RESULTADO: 138 verificações aprovadas, 0 falhas`.
- **Migração 4 aplicada no projeto em 25/11/2026**, segundo o usuário. Não houve conferência independente por esta sessão, porque os índices não são visíveis pela API com a chave publicável. Confirmar no próximo Performance Advisor: devem restar só os avisos de *Unused Index*.
- mapear os códigos HTTP para usuário autenticado via login real no Supabase Auth: 401/42501 para `anon` já foi confirmado; para `authenticated` são esperados 403/404/409.

## Telas ligadas ao Supabase (25/11/2026, sem publicação)

O servidor local escuta só em `127.0.0.1` e entrega as telas; dados e regras ficam no Supabase. O login é pelo Supabase Auth e toda ação é uma RPC. As contas são sintéticas (`m360.*@example.com`), com senhas aleatórias guardadas apenas em `dados/` (fora do Git). A semente foi aplicada via RPCs: 2 IES, 4 cursos, 9 usuários, 8 escopos, 24 oportunidades e 111 eventos de auditoria.

**Achados e correções da homologação real:**
1. **SQLSTATE P0002 chegava como HTTP 500.** Corrigido na migração 6 (agora 404).
2. **SQLSTATE 40001 travava a requisição.** O PostgREST repetia a transação até `upstream request timeout`, o que, num conflito de versão real, deixaria a tela travada. Corrigido na migração 6 (agora 409 imediato, com a versão atual em `details`).
3. **Mapeamento conferido no Supabase real** após a migração 6:

   | Situação | Resposta |
   |---|---|
   | Fora do escopo | 404 |
   | Sem permissão | 403 |
   | Regra violada | 400 |
   | Conflito de versão | 409 (≈0,5 s) |

   Para `anon`, "sem permissão" chega como 401.
4. **Conta recém-criada no Auth, sem perfil de aplicação:** faz login, mas não acessa nada (RPCs 403; leitura direta vazia).

**Configuração do Auth restaurada e conferida em `/auth/v1/settings`** (25/11/2026):
- `disable_signup = true`: sem cadastro aberto; novos usuários entram por convite;
- `mailer_autoconfirm = false`: confirmação de e-mail ligada.

**Bateria no navegador (63/63)**, cobrindo gestor, comercial, secretaria, financeiro e coordenação da Alfa, além do gestor da Beta e do Master:
- isolamento entre IES contra adulteração feita no cliente;
- curso autorizado, com contatos mascarados;
- LGPD (base legal obrigatória);
- etapa com versão;
- proposta acima do limite e segregação na aprovação;
- validações por papel, com evidência;
- auditoria;
- Master sem acesso a candidatos;
- ausência de rolagem horizontal e de erros de console ou CSP.

A primeira rodada deu 56/63. As 7 falhas foram 1 contagem do próprio teste e 6 respostas 500 (achado 1).

## Migração para React/TypeScript/Tailwind (25/11/2026)

**Stack (versões exatas e `package-lock.json`):**
- React 18.3.1, React Router 6.28.0;
- TypeScript 5.6.3 em modo estrito (`noUncheckedIndexedAccess`);
- Tailwind 3.4.17, Vite 5.4.11, Vitest 2.1.9.

**Arquitetura:**
- Sem SDK do Supabase: um cliente mínimo tipado (Auth + RPC) com renovação de token e mapeamento dos códigos do banco (P0002→404, 42501→403, 40001→409, 22023→422).
- Uma função tipada por RPC.
- Nenhuma regra de autorização no cliente: a interface só esconde ações por conveniência, e o banco decide.

**Paridade com as telas anteriores:** o mesmo roteiro de navegador passa nas duas interfaces (66/66 cada).

**Ajustes do roteiro nesta etapa:**
- esperas explícitas, porque a interface React renderiza a estrutura antes dos dados;
- a proposta usada no teste de segregação passa a ser criada pelo comercial em cada rodada, o que deixa o teste independente do estado do banco.

**Pendências da interface:**
- auditoria de acessibilidade com axe;
- divisão do pacote por rota (217 KB, 69 KB comprimido, hoje em um único arquivo);
- remoção das telas legadas após aceite.

## Publicação de homologação no Render (25/11/2026, autorizada pelo usuário)

- Static Site `matricula360-homologacao`, separado do site institucional, a partir da branch do PR #1.
- `config.json` publicado contém só a URL do projeto e a chave **publicável**.
- `noindex` na página e no cabeçalho.
- **Conferido no ar:** os seis cabeçalhos de segurança (CSP com `connect-src` restrito ao Supabase do projeto, `X-Frame-Options DENY`, entre outros), mais `Strict-Transport-Security` do Render.
- Rotas internas servem a aplicação (200); arquivo inexistente dá 404.

**Ajustes durante a configuração:**
1. **Faltava a regra de rewrite:** rotas internas davam 404.
2. **Destino da regra sem a barra inicial:** rotas internas respondiam 200 vazio.
3. **Cabeçalhos preenchidos na coluna errada:** corrigido no painel.

**Domínio `matricula360.somosfato.com.br`:** CNAME criado no Registro.br (→ `matricula360-homologacao.onrender.com`), aguardando propagação do DNS no momento deste registro.

## Fase 2, P0 — correções, redesign e Central de Inteligência (25/11/2026)

**Migrações 7 e 8 aplicadas no Supabase de homologação.** O diagnóstico refeito no banco real (`scripts/diagnostico-homologacao.mjs`) confirma os efeitos:

| Ponto | Antes | Depois |
|---|---|---|
| Oportunidades com mais de uma proposta ativa | 5 | 0 |
| Primeiro contato aberto fora de "novo" | 18 | 0 |
| Tarefas comerciais em matrícula comercial/encerrada | 4 | 0 |
| Projeção de oportunidades necessárias | 169 (método incorreto) | 8 (taxa das decididas e pipeline esperado) |

- **Central no banco real:** funil 24 › 22 › 15 › 8 › 6 › 2, alertas reais (SLA vencido e propostas pendentes) e metas lidas (10 + 6).
- **Isolamento:** gestor da Beta → 404 na Central da Alfa; coordenação de Direito filtrando Administração → 0 oportunidades.

**Navegador no site publicado (nova interface, desktop + iPhone 13): 83/83.**

Cobertura:
- Central: funil, turno/modalidade, custo por lead N/D com motivo, alertas, ausência do rótulo técnico e filtro global de curso refletido na URL.
- Metas carregadas em Configurações; auditoria sem nenhum evento em código cru; fila sem o botão de disparo externo.
- CRM, propostas com segregação, validações e Master.
- Isolamento contra adulteração no cliente; ausência de rolagem horizontal e de erros de console/CSP.

Ajustes do roteiro nesta rodada (nenhum de produto):
- nova navegação pelo menu lateral (no celular, pela gaveta);
- candidata de teste identificada como "Teste automatizado E2E" e origem "teste automatizado (E2E)";
- verificação de auditoria trocada de uma frase específica para "nenhum evento em código cru".

**Dados de teste visíveis na homologação:** 9 oportunidades criadas por roteiros, identificáveis pela origem ("homologação supabase", "teste automatizado (E2E)"). Não são removidas, porque a plataforma não apaga registros.

## Conformidade com a Bíblia v0.2 §6 — migração 9 (25/11/2026)
Aplicada pelo usuário no projeto de homologação. Conferência no banco real (gestor da Alfa, coorte 2027.1):

| Item | Valor |
|---|---|
| Conversão da coorte | 0,0741 (2/27) |
| Meta restante | 14 |
| Amostra | 27, mínimo 30 |
| Oportunidades adicionais projetadas (oficial) | N/D, com o motivo "Amostra insuficiente: 27 oportunidades (mínimo configurado: 30)" |
| Cenário complementar | Identificado; 5 novas oportunidades pelo pipeline |
| Receita potencial ofertada | R$ 4.782,45 (13 propostas válidas) |

Comercial tentando alterar a amostra mínima: 403. Cenário R03 reproduzido localmente: 168 (antes, 169, por artefato de precisão).

Navegador no site publicado: 83/83. O build publicado é idêntico ao do repositório.

## CRM avançado — migração 10 (26/11/2026)
Aplicada pelo usuário no projeto de homologação. Conferido no banco real: `rpc_agenda` existe e recusa o acesso anônimo (42501).

**O que entrou**
- Interações e objeções, com tratamento registrado.
- Agenda comercial.
- Reatribuição pelo gestor, com motivo obrigatório; as tarefas abertas acompanham o novo responsável.
- Score explicável `score-v1`, que não decide ingresso.
- Busca por nome (e-mail e telefone só para perfil pleno) e filtros combinados.
- Alerta de possível duplicidade, sem mesclagem automática.
- Linha do tempo única na ficha.

**Testes**

| Onde | Resultado |
|---|---|
| Banco local (migrações 1–10) | 213/213; RLS e `search_path` em 100% |
| Bateria remota gerada | 213/213 localmente, tudo desfeito ao final |
| Arquivo de aplicação | aplicado duas vezes seguidas sem erro |
| Navegador no site publicado (`matricula360-homologacao.onrender.com`, mesma publicação do domínio próprio) | **90/90** |

As 7 verificações novas do navegador:
- interação registrada aparece na linha do tempo;
- objeção registrada como aberta;
- agendamento aparece na ficha;
- score com o aviso de não decisão;
- busca filtra o quadro;
- arrastar para transição inválida: o servidor recusa ("Transição inválida: inscrito → novo") e o cartão permanece na coluna;
- agenda comercial lista o agendamento.

**Falha encontrada e corrigida:** o atalho de arrasto do Playwright (`dragTo`) não disparava os eventos HTML5. O teste passou a arrastar com o mouse em passos. A interface também passou a guardar o arrasto numa referência síncrona, o que evita a perda do drop num arrasto muito rápido.

**Observação de rede:** nesta rodada, o domínio `matricula360.somosfato.com.br` falhou no handshake TLS a partir do ambiente de testes, enquanto o endereço do Render respondeu normalmente. Precisa ser conferido num navegador comum.

## Governança (migração 11) e Planejamento e Campanhas (migração 12) — 26/11/2026
Aplicadas pelo usuário no projeto de homologação, nesta ordem. Conferido no banco real: `rpc_permissoes`, `rpc_exportar_oportunidades`, `rpc_planejamento` e `rpc_campanhas` existem e recusam acesso anônimo (42501).

| Teste | Resultado |
|---|---|
| Banco local (migrações 1–12) | 317/317; RLS e `search_path` em 100% |
| Bateria remota gerada | 320/320, tudo desfeito ao final |
| Aplicação | 011 e 012 aplicadas duas vezes sobre o estado anterior do banco, sem erro |
| Navegador no site publicado (build idêntica ao repositório) | **104/104** |

Verificações novas no navegador:
- matriz de permissões visível;
- exportação CSV do gestor com contato e registro na auditoria;
- exportação da coordenação só do seu curso e com contato mascarado;
- atendente vê só as oportunidades atribuídas a si;
- R09: `/ies/2/crm` e `?ies=2` sem dados da Beta;
- página de Planejamento com concorrência;
- Campanhas com atribuição desconhecida e integrações desligadas.

Decisão do responsável do produto (26/11/2026): o atendente comercial vê apenas as oportunidades atribuídas a ele; o chefe do setor (gestor) vê as da equipe.

## Critérios de aceite da Bíblia-Mestra

| Critério | Onde está provado |
|---|---|
| Duas IES e dois cursos por IES | `servico.test` › isolamento; semente |
| Usuário revogado | `servico.test` › revogação; `api.test` › revogação encerra a sessão em uso |
| IDs adulterados / IDOR | `api.test` › IDOR (outra IES → 404; IDs malformados → 400) |
| Alteração direta de campos | `api.test` › campos não permitidos → 400; gatilho no banco recusa `confirmado` sem validações |
| Conflito de versão | `servico.test` › conflito; `api.test` › corrida simultânea (uma vence, outra 409) |
| Repetição de evento | `api.test` › idempotência (mesma chave = mesma resposta, sem reexecução) |
| Zero × indisponível | `motor.test`, `servico.test` › BI e `api.test` › BI: `null` (N/D), nunca 0 |
| Denominador por coorte | `servico.test` › BI: denominador = oportunidades da coorte |
| Cancelamento | `servico.test` › cancelamento preserva validações, datas e histórico |
| Confirmação incompleta | `motor.test` e `servico.test` (aplicação e banco) |
| Opt-out | `servico.test` › suprime tarefas do canal e revalida na execução |
| Falta de base legal | `servico.test` › LGPD: cadastro e importação recusam |
| Desconto excessivo | `servico.test` › exige aprovação; criador não aprova; acima de 100% é recusado |
| Ausência de envio externo | `servico.test` › disparo sempre bloqueado e auditado; `api.test` › código sem rede de saída nem SDK de IA |
| Pessoa contada uma vez no consolidado | `servico.test` › BI com duas matrículas da mesma pessoa = 1 ingressante |

## Riscos e limitações conhecidas

1. **Peças do pacote v0.1 não chegaram.** Faltavam `server.mjs`, `src/motor.mjs`, os 16 testes, `db/schema-proposto.sql` e `docs/REFERENCIA-COMERCIAL360.md`. O motor foi reconstruído a partir do contrato que a demo usa; o esquema SQL foi feito do zero. Antes de qualquer atribuição específica a esses originais, é preciso conferi-los.
2. **Migrações Supabase aplicadas no projeto de homologação `jbimijcvvekomovodfze`** (ver seção acima). `supabase/migrations/` traz o esquema com RLS, sem escrita direta do cliente, e 24 RPCs. O que falta só pode ser verificado no projeto remoto: a criação do projeto (bloqueada porque o conector ainda não enxerga a org Matricula360), o mapeamento HTTP dos códigos de erro pelo PostgREST, os advisors do Supabase e o login pelo Supabase Auth. As 24 RPCs cobrem todas as operações do piloto: funil, validações, propostas, MAIM, LGPD, metas, configurações e funções do Master.
2b. **O piloto rodável continua em SQLite local.** Isolamento e permissões estão no serviço e em gatilhos do banco, sem RLS. A migração para Postgres com RLS e testes de isolamento no banco depende de autorização de infraestrutura.
3. **Stack:** JavaScript sem build, sem React, TypeScript ou Tailwind. Foi escolha deliberada para manter zero dependências no piloto. A migração está na próxima entrega.
4. **`node:sqlite` é experimental no Node 22.** Serve para o piloto, não para produção.
5. **Controle de tentativas de login em memória:** zera quando o servidor reinicia.
6. **Sem verificação de acessibilidade com axe.** A homologação checa rótulos, idioma e teclado nativo, mas não faz auditoria WCAG completa.
7. **Campanhas e Academia** aparecem como backlog na interface, sem funcionalidade.
8. **Senha padrão do piloto** está documentada no README. Uso exclusivamente local.

## Reversão

O piloto fica isolado em `matricula360/`. Reverter é remover o diretório ou reverter o commit. Nenhum recurso remoto foi criado e nenhum outro produto foi alterado.
