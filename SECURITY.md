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

### Inventário de credenciais de automação

| Credencial | Tipo | Escopo | Dono | Expira | Onde vive | Status |
|---|---|---|---|---|---|---|
| `satis-upsolve-2026-07` (Satis lê os repos) | fine-grained PAT | `upsolve-br` · All repos · Contents:Read | `fabianolopes76` | 14/out/2026 | `applications/satis/.env` (server-only) | ✅ **ativo** — rotacionado em 2026-07-16 |
| `upsolve-br` | fine-grained PAT | org | `fabianolopes76` | Mar/2027 | ? | revisar necessidade (sem uso há ~2 meses) |
| ~~`satis-packages-upsolve`~~ (classic exposto) | classic PAT `repo` | todos os repos do dono | `fabianolopes76` | — | (era `applications/satis/.env`) | 🗑️ **revogado** 2026-07-16 (exposto em claro em 07-12) |
| ~~`satis-upsolve`~~ | fine-grained PAT | org | `fabianolopes76` | sem expiração | — | 🗑️ **removido** 2026-07-16 (sem uso, sem expiração) |

## Estado atual e roadmap

- [x] **Camada 1 (feito 2026-07-16):** Satis rotacionado do classic `repo` exposto
      para **fine-grained read-only** (`satis-upsolve-2026-07`, Contents:Read); token
      exposto **revogado**. Verificado por `ls-remote` em 5 repos privados + rebuild
      completo do catálogo (todos os ~63 repos) sem erros de auth.
- [x] **Camada 5 (parcial, 2026-07-16):** eliminados o classic exposto
      (`satis-packages-upsolve`) e o fine-grained `satis-upsolve` (sem expiração).
      Falta revisar `upsolve-br` (sem uso há ~2 meses).
- [ ] **Camada 2 (curto prazo):** ligar **rulesets no `main`** de todos os repos.
- [ ] **Camada 4:** ligar 2FA obrigatório + restrição de classic PATs + restrição
      de criação/deleção de repos.
- [ ] **Camada 1 (end-state):** migrar a automação do Satis para um **GitHub App**
      org-owned com installation tokens de vida curta.

## Runbooks relacionados

- **Rotação do token do Satis:** `applications/satis/README.md` → seção
  *"🔐 Rotação de segredos"*.
- **Deploy da infra:** `DEPLOY.md`.
