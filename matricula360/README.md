# Matrícula 360° — v0.2 piloto local

Produto independente de gestão comercial de matrículas para ensino superior privado. Esta versão é um **piloto local**: tem login, permissões por instituição e curso, persistência, auditoria e fila de acompanhamento. Roda numa máquina só, com **dados sintéticos**, sem infraestrutura paga, **sem IA e sem envio externo**.

## Como executar

Requisito: Node.js 22.13 ou superior. O projeto não tem dependências externas.

```bash
npm test            # 42 testes: motor, domínio e API por HTTP
npm start           # http://127.0.0.1:4173  (cria dados/piloto.sqlite com dados sintéticos)
npm run piloto:reset  # apaga o banco do piloto; o próximo start recria
npm run homologar   # homologação no navegador (desktop + celular), evidências em docs/evidencias/
```

O servidor escuta só em `127.0.0.1`. **Não exponha à internet.**

## Usuários do piloto (fictícios)

Senha local padrão: `piloto-local-2026`. Pode ser trocada com `M360_SENHA_PILOTO` antes do primeiro `npm start`.

| E-mail | Perfil | Escopo |
|---|---|---|
| master@piloto.invalid | Master | Plataforma (não vê candidatos) |
| gestor.alfa@piloto.invalid | Gestor | Faculdade Alfa inteira |
| reitoria.alfa@piloto.invalid | Reitoria | Alfa, só leitura, contatos mascarados |
| coord.direito.alfa@piloto.invalid | Coordenação | Alfa, somente Direito |
| comercial1.alfa@piloto.invalid | Comercial | Alfa inteira |
| comercial2.alfa@piloto.invalid | Comercial | Alfa, somente Direito |
| secretaria.alfa@piloto.invalid | Secretaria | Valida documental e acadêmica |
| financeiro.alfa@piloto.invalid | Financeiro | Valida financeira, inclusive isenção formal |
| gestor.beta@piloto.invalid (e comercial/secretaria/financeiro.beta) | — | Centro Universitário Beta |
| revogado.alfa@piloto.invalid | — | Revogado: não entra |

## Estrutura

| Caminho | Conteúdo |
|---|---|
| `src/motor.mjs` | Regras puras: etapas, transições, confirmação, taxas, projeção e proposta |
| `src/schema.sql` | Esquema SQLite com gatilhos: auditoria imutável e ingresso só com as 3 validações |
| `src/servico.mjs` | Domínio: autorização por escopo, versão otimista, auditoria transacional, MAIM e BI |
| `src/app.mjs` | HTTP: rotas, guardas de página no servidor, CSRF, idempotência e cabeçalhos de segurança |
| `src/semente.mjs` | Dados sintéticos: 2 IES × 2 cursos, todos os perfis, funil completo |
| `public/` | Página pública e demo v0.1 preservadas, mais login e área autenticada |
| `test/` | Testes de motor, domínio e API |
| `docs/original/` | Pacote v0.1 recebido, preservado sem alteração |

Requisitos e limites ficam em `BIBLIA-MESTRA.md`. O roteiro está em `INSTRUCOES-DESENVOLVEDOR.md`. As evidências e os riscos estão em `docs/HOMOLOGACAO-PILOTO.md`.
