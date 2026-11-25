# Homologação do piloto local — v0.2 (25/11/2026)

**Escopo:** homologação **local**, com dados sintéticos. Não houve homologação em ambiente remoto, porque nenhuma infraestrutura foi autorizada. Este documento não atesta prontidão para produção.

## Resultado

| Bateria | Comando | Resultado |
|---|---|---|
| Unitários, domínio e API (HTTP real) | `npm test` | **42/42 aprovados** (`evidencias/saida-testes.txt`) |
| Navegador, desktop 1366×860 e iPhone 13 | `npm run homologar` | **83/83 verificações** (`evidencias/resultado.json`) |
| Bateria de RLS no **Supabase real** (projeto de homologação) | SQL Editor: `supabase/TESTAR-NO-SQL-EDITOR.sql` | **138/138** com as migrações 1 a 5 (rodada anterior: 107/107 com as migrações 1 a 4); tudo desfeito ao final |
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
