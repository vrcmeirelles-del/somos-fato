# Homologação do piloto local — v0.2 (25/11/2026)

**Escopo:** homologação **local**, com dados sintéticos. Não houve homologação em ambiente remoto, porque nenhuma infraestrutura foi autorizada. Este documento não atesta prontidão para produção.

## Resultado

| Bateria | Comando | Resultado |
|---|---|---|
| Unitários, domínio e API (HTTP real) | `npm test` | **42/42 aprovados** (`evidencias/saida-testes.txt`) |
| Navegador, desktop 1366×860 e iPhone 13 | `npm run homologar` | **83/83 verificações** (`evidencias/resultado.json`) |

A verificação no navegador cobre seis perfis: público, gestor, comercial, secretaria, coordenação e Master. Em cada tela checa:

- ausência de rolagem horizontal da página;
- campos com rótulo acessível;
- nenhum erro de console ou de CSP.

Também cobre os fluxos: cadastro com base legal, proposta acima do limite indo para aprovação, validação com evidência, ciclo MAIM, mascaramento de dados para a coordenação e bloqueio do Master sem escopo.

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
2. **SQLite local, não Supabase/Postgres.** Isolamento e permissões estão no serviço e em gatilhos do banco, sem RLS. A migração para Postgres com RLS e testes de isolamento no banco depende de autorização de infraestrutura.
3. **Stack:** JavaScript sem build, sem React, TypeScript ou Tailwind. Foi escolha deliberada para manter zero dependências no piloto. A migração está na próxima entrega.
4. **`node:sqlite` é experimental no Node 22.** Serve para o piloto, não para produção.
5. **Controle de tentativas de login em memória:** zera quando o servidor reinicia.
6. **Sem verificação de acessibilidade com axe.** A homologação checa rótulos, idioma e teclado nativo, mas não faz auditoria WCAG completa.
7. **Campanhas e Academia** aparecem como backlog na interface, sem funcionalidade.
8. **Senha padrão do piloto** está documentada no README. Uso exclusivamente local.

## Reversão

O piloto fica isolado em `matricula360/`. Reverter é remover o diretório ou reverter o commit. Nenhum recurso remoto foi criado e nenhum outro produto foi alterado.
