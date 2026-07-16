# Modelo de Segurança — Organização `upsolve-br`

> Playbook interno de **controle de acesso e hardening** da organização GitHub
> `upsolve-br` (repositórios de produto da UpSolve). **Não** é uma política de
> divulgação de vulnerabilidades — é a arquitetura de *"quem pode ler e escrever
> o quê"*, e como a automação (Satis, CI) se encaixa nela.
>
> Owner da org: `fabianolopes76`. Automação sensível (o token do Satis) vive
> neste repositório (`applications/satis/.env`, server-only).

## Princípio central

**Automação lê; humanos escrevem.** São dois controles distintos e independentes:

- **Escrita** nos repositórios é gated por *rulesets* + review (Camadas 2–3). É
  aqui — e **só** aqui — que *"apenas o owner atualiza os repositórios"* é imposto.
  Não se constrói essa barreira no token de automação.
- **Leitura** por automação (Satis lê os ~63 repos pra montar o catálogo Composer)
  usa credencial **read-only de menor privilégio** (Camada 1), de modo que um
  vazamento dessa credencial **nunca** consiga tocar na integridade do código.

O modo de falha a evitar: um único token `repo` amplo (read **+ write** em tudo),
atrelado a uma **conta pessoal**, morando num serviço. Se vaza, o blast radius é
o código inteiro. (Foi o estado do token do Satis até jul/2026 — ver Camada 5.)

## Camada 1 — Automação lê, nunca escreve

Alvos, do bom ao ótimo:

- **Bom (estado atual alvo):** *fine-grained PAT* — resource owner `upsolve-br`,
  **All repositories**, permissão **Contents: Read-only** (+ Metadata: Read-only,
  obrigatória). Se vazar, blast radius = **somente leitura**. Não escreve em nada.
  Definir **expiração** (ex.: 90 dias) e registrar no inventário (Camada 5).
- **Ótimo (end-state):** um **GitHub App** instalado na org com **Contents:
  Read-only**. Ele emite *installation tokens* de vida curta (~1 h, auto-rotacionam)
  → não há segredo longevo pra vazar, e a **identidade é da org**, não de uma pessoa.
  Desacopla a automação de qualquer conta individual (essencial quando entrarem
  colaboradores ou ao trocar de máquina/conta).

> Regra: **automação = sempre read-only.** Token de escrita nunca mora em serviço.

## Camada 2 — Escrita gated (o verdadeiro *"só o owner atualiza"*)

**Branch protection / rulesets** no `main` (ou branch default) de **todos** os repos:

- Exigir **Pull Request** antes de merge → proíbe push direto no `main`.
- **Restrict who can push to matching branches → apenas o owner** (ou lista curta).
- Exigir **review aprovado** (via `CODEOWNERS` apontando para o owner).
- Bloquear **force-push** e **deleção** de branch protegido.
- (Opcional) exigir **status checks** (CI) verdes antes do merge.

→ Colaborador trabalha em branch/fork e abre PR; **nada entra no `main` sem
aprovação do owner**. A barreira é a *regra*, não a confiança.

> ⚠️ Branch protection / rulesets em repositórios **privados** pode exigir plano
> **GitHub Team** ou superior — confirmar o plano da org.

## Camada 3 — Papéis, times e CODEOWNERS (quando entrarem colaboradores)

- Colaborador = **Member** da org, adicionado a **Teams** com role **Write**
  (nunca **Admin**, nunca **Owner**) apenas nos repos que precisa.
- **Admin de repo bypassa branch protection** → colaborador nunca é Admin. Marcar
  **"Do not allow bypassing the above settings" / include administrators** (o owner
  decide se se mantém como exceção deliberada).
- **`CODEOWNERS`** para exigir review do owner em caminhos sensíveis.
- Princípio transversal: **menor privilégio por pessoa e por repo**.

## Camada 4 — Políticas da org (hardening global)

- **Exigir 2FA** de todos os membros.
- **Personal access tokens:** restringir **classic PATs** de acessar a org e
  **exigir aprovação** de fine-grained PATs (Org → Settings → Personal access
  tokens). Fechar a porta do classic amplo depois que a automação virar
  read-only/App.
- **Restringir criação/deleção de repositórios** a owners.
- **Secret scanning + push protection** em todos os repos (pega segredo commitado).
  *Em repos privados pode exigir GitHub Advanced Security — verificar plano.*

## Camada 5 — Higiene de segredos

- Preferir **curto prazo** (installation token de App) a PAT longevo.
- Todo segredo de automação com **dono + expiração + local** registrados abaixo.
- Segredo que apareceu em **texto claro fora do cofre** se **rotaciona** — não se
  racionaliza. (Ver runbook de rotação: `applications/satis/README.md`.)
- Eliminar tokens **sem expiração** e **não usados**.

## Camada 6 — Chaves SSH de deploy (GitHub Actions → VPS)

Distinta da Camada 1 (PAT read-only): estas são **chaves SSH com poder de escrita**
que dão ao runner do GitHub Actions um **shell na VPS** (via `appleboy/scp-action` +
`appleboy/ssh-action`). São a credencial de **maior valor** de todo o footprint — se
uma vaza, o blast radius é **shell na máquina**, não "somente leitura".

> Nuance do princípio central: essas chaves não escrevem nos *repositórios* GitHub
> (a barreira de integridade do código segue nas Camadas 2–3); elas escrevem no
> **sistema de arquivos da VPS**. É um eixo de risco diferente — e precisa de controle
> próprio, porque um PAT read-only não protege contra uma deploy key vazada.

**Não confundir com os 65 webhooks** `upsolve-br/*` → `packages.upsolve.com.br/webhook`:
aqueles só disparam um POST assinado (HMAC `WEBHOOK_SECRET`) que faz o Satis *puxar* —
não abrem shell. Deploy key ≠ webhook.

Regras:

- **Uma chave por repo — nunca compartilhada.** Se N repos usam a MESMA
  `SSH_PRIVATE_KEY`, revogar uma obriga rotacionar todas. Confirmar na VPS com
  `ssh-keygen -lf ~/.ssh/authorized_keys` (1 entrada p/ N repos = compartilhada = corrigir).
- **`authorized_keys` restrito.** Cada entrada com `restrict` + `command=` (ou ao menos
  `no-agent-forwarding,no-X11-forwarding,no-port-forwarding`) limita o estrago se a chave vazar.
- **Rotação com cadência** (ex.: anual): substituir o par (Actions secret + `authorized_keys`)
  atomicamente. Deploy key é credencial de escrita — não é "set and forget".
- **Domínios de VPS são isolados.** Nunca reusar a mesma chave entre a VPS UpSolve
  (`srv857637`) e a VPS UFMA — são instituições/máquinas distintas (ver inventário).

## Inventário de credenciais (todas as camadas)

**VPS → GitHub (leitura — Camada 1):**

| Credencial | Tipo | Escopo | Dono | Expira | Onde vive | Status |
|---|---|---|---|---|---|---|
| `satis-upsolve-2026-07` (Satis lê os repos) | fine-grained PAT | `upsolve-br` · All repos · Contents:Read | `fabianolopes76` | 14/out/2026 | `applications/satis/.env` (server-only) | ✅ **ativo** — rotacionado em 2026-07-16 |
| `upsolve-br` | fine-grained PAT | org | `fabianolopes76` | Mar/2027 | ? | revisar necessidade (sem uso há ~2 meses) |
| ~~`satis-packages-upsolve`~~ (classic exposto) | classic PAT `repo` | todos os repos do dono | `fabianolopes76` | — | (era `applications/satis/.env`) | 🗑️ **revogado** 2026-07-16 (exposto em claro em 07-12) |
| ~~`satis-upsolve`~~ | fine-grained PAT | org | `fabianolopes76` | sem expiração | — | 🗑️ **removido** 2026-07-16 (sem uso, sem expiração) |

**GitHub → VPS (gatilho de rebuild — webhook):**

| Credencial | Tipo | Escopo | Onde vive | Status |
|---|---|---|---|---|
| `WEBHOOK_SECRET` | HMAC compartilhado | **63 webhooks** `upsolve-br/*` (evento `push`) → `/webhook` | Satis `.env` + config de cada hook | ✅ **validado 2026-07-16** (ping → 200/OK, HMAC bate) — **1 segredo p/ 63 hooks** (rotação = atualizar os 63) |

> Os 7 repos **sem** webhook (`upsolve-workspace`, `upsolve-ai`, `app-template-{simple,tenant-single,tenant-multi}`, `new-flcon`, `playground-legal`) são corretos — nenhum é pacote Composer servido pelo Satis. Verificação: os 63 hooks apontam **todos** p/ `/webhook`, zero destino inesperado, zero falha (4xx/5xx). Estavam `unused` (nenhum push desde 07-12, não segredo quebrado — o ping confirmou o HMAC).

**GitHub Actions → VPS produção UpSolve `srv857637` (escrita — Camada 6):**

| Repo (deploy) | Secrets | Workflow | Último run OK | Status / risco |
|---|---|---|---|---|
| `fabianolopes76/upsolve-infra` | `HOST` · `USERNAME` · `SSH_PRIVATE_KEY` | `deploy.yml` ✅ ativo | **2026-07-16** (success) | 🟢 viva/ativa — **nunca rotacionada** |
| `fabianolopes76/flcon` | `HOST` · `USERNAME` · `SSH_PRIVATE_KEY` | `deploy.yml` ✅ ativo | 2026-03-30 (success) | 🟡 válida mas **ociosa ~3,5 meses** — nunca rotacionada |
| `fabianolopes76/prof.fabianolopes` | `HOST` · `USERNAME` · `SSH_PRIVATE_KEY` | `deploy.yml` ✅ ativo (+ `__deploy.xxx` desativado) | 2026-07-13 (success) | 🟢 viva/ativa — **nunca rotacionada** |

> `HOST` é um secret (valor oculto): que os três apontem para o **mesmo** `srv857637`
> é a hipótese pelo agrupamento de perfil + convenção de nomes, confirmável só na VPS
> (comparar `authorized_keys` / valor de `HOST`).

**Fora do escopo deste playbook — VPS UFMA (perfil docente, outra instituição):**

| Repo (deploy) | Secrets | Workflow | Último run OK | Nota |
|---|---|---|---|---|
| `fabianolopes76/gedid-ufma` | `VPS_HOST` · `VPS_USER` · `VPS_SSH_KEY` | `deploy.yml` ✅ ativo (+ `___deploy.xxx`) | 2026-06-26 (success) | 🟢 VPS da Universidade Federal do Maranhão |
| `fabianolopes76/gedid-ufma-infra` | `VPS_HOST` · `VPS_USER` · `VPS_SSH_KEY` | `deploy.yml` ✅ ativo (stub 385B) | 2026-03-01 (success) | 🟡 UFMA — ociosa ~4,5 meses; credenciais independentes |

> `fabianolopes76/gedid` (sem sufixo) tem `deploy.yml` mas **zero Actions secrets** →
> workflow morto (referencia segredos inexistentes; não deploya). Candidato a limpeza.

## Estado atual e roadmap

- [x] **Camada 1 (feito 2026-07-16):** Satis rotacionado do classic `repo` exposto
      para **fine-grained read-only** (`satis-upsolve-2026-07`, Contents:Read); token
      exposto **revogado**. Verificado por `ls-remote` em 5 repos privados + rebuild
      completo do catálogo (todos os ~63 repos) sem erros de auth.
- [x] **Camada 5 (parcial, 2026-07-16):** eliminados o classic exposto
      (`satis-packages-upsolve`) e o fine-grained `satis-upsolve` (sem expiração).
      Falta revisar `upsolve-br` (sem uso há ~2 meses).
- [x] **Camada 6 (inventariado + verificado 2026-07-16):** mapeadas **3 chaves SSH
      de deploy** p/ `srv857637` (`upsolve-infra`, `flcon`, `prof.fabianolopes`) + 2 p/
      UFMA (`gedid-ufma`, `gedid-ufma-infra`). **Liveness confirmada** — as 5 com último
      run `success` (2 dormentes há meses, mas válidas). Nenhuma rotacionada desde a criação.
- [x] **Webhook (verificado 2026-07-16):** os 63 hooks → `/webhook` limpos (destino
      certo, zero falha); `WEBHOOK_SECRET` **confirmado válido** por ping (200/OK).
- [ ] **Camada 6 (hardening):** na VPS, rodar `ssh-keygen -lf ~/.ssh/authorized_keys`
      para confirmar **1 chave por repo** (não compartilhada); aplicar `restrict` nas
      entradas do `authorized_keys`; definir rotação (anual) das deploy keys; remover
      o `deploy.yml` morto de `fabianolopes76/gedid`.
- [ ] **Camada 2 (curto prazo):** ligar **rulesets no `main`** de todos os repos.
- [ ] **Camada 4:** ligar 2FA obrigatório + restrição de classic PATs + restrição
      de criação/deleção de repos.
- [ ] **Camada 1 (end-state):** migrar a automação do Satis para um **GitHub App**
      org-owned com installation tokens de vida curta.

## Runbooks relacionados

- **Rotação do token do Satis:** `applications/satis/README.md` → seção
  *"🔐 Rotação de segredos"*.
- **Deploy da infra:** `DEPLOY.md`.
