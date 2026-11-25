# Publicar a homologação no Render — `matricula360.somosfato.com.br`

Site estático no Render, **separado** do site institucional (que não é alterado).
Dados sintéticos. Só entra quem tem conta (login pelo Supabase Auth; cadastro aberto desligado).
Validado antes da publicação com `M360_ESTATICO=1 npm run homologar:supabase`, que simula esta hospedagem: **66/66**.

## 1. Criar o serviço (painel do Render)

**New → Static Site** → conectar o repositório `vrcmeirelles-del/somos-fato`.

| Campo | Valor |
|---|---|
| Name | `matricula360-homologacao` |
| Branch | `ccr-c2153ae4-iykoe6` (branch do PR #1; depois do merge, trocar para `main`) |
| Root Directory | `matricula360/web` |
| Build Command | `npm ci && npm run build` |
| Publish Directory | `dist` |

**Environment Variables:**

| Variável | Valor |
|---|---|
| `NODE_VERSION` | `22` |
| `M360_SUPABASE_URL` | `https://jbimijcvvekomovodfze.supabase.co` |
| `M360_SUPABASE_CHAVE_PUBLICAVEL` | a chave **publicável** atual (`sb_publishable_...`) |

O build **recusa** qualquer chave que não seja publicável. A chave secreta nunca vai para o Render.

## 2. Rotas (Redirects/Rewrites)

| Source | Destination | Action |
|---|---|---|
| `/*` | `/index.html` | Rewrite |

## 3. Cabeçalhos de segurança (Headers), caminho `/*`

| Nome | Valor |
|---|---|
| `Content-Security-Policy` | `default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self' https://jbimijcvvekomovodfze.supabase.co; frame-ancestors 'none'; base-uri 'none'; form-action 'self'` |
| `X-Content-Type-Options` | `nosniff` |
| `X-Frame-Options` | `DENY` |
| `Referrer-Policy` | `no-referrer` |
| `Permissions-Policy` | `camera=(), microphone=(), geolocation=()` |
| `X-Robots-Tag` | `noindex, nofollow` |

## 4. Domínio

1. No serviço, abra **Settings → Custom Domains → Add** e informe `matricula360.somosfato.com.br`.
2. O Render mostra um destino (`<algo>.onrender.com`).
3. Onde o DNS do somosfato.com.br é gerenciado, crie o registro **CNAME** `matricula360` → esse destino.
4. O certificado HTTPS é emitido automaticamente pelo Render.

## 5. Supabase

Em **Authentication → URL Configuration → Site URL**, informe `https://matricula360.somosfato.com.br`. Os e-mails de convite e de redefinição de senha passam a apontar para lá.

## Antes de fazer merge do PR #1 no `main`

Confira o serviço **atual** do somosfato.com.br no Render: o **Publish Directory** deve ser `dist`.
- Se for `.` (a raiz do repositório), o merge exporia `matricula360/` (código, SQL e documentos) no site institucional.
- Nesse caso, ajuste o serviço para `dist` antes do merge.

## Reversão

Suspender ou excluir o serviço `matricula360-homologacao` no Render e remover o CNAME. O site institucional não é afetado.
