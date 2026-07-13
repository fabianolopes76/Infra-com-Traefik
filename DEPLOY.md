# Deploy — Infra UpSolve (VPS srv857637)

Documentação do pipeline de entrega contínua (CD) e dos pré-requisitos na VPS.
O deploy é disparado por **push na branch `main`** e definido em
[`.github/workflows/deploy.yml`](.github/workflows/deploy.yml).

---

## 1. Visão geral do pipeline

```
push na main
   │
   ├─ 0. VALIDATE → promtool check da config/regras do Prometheus.
   │               Se falhar, o deploy NÃO roda (job `build_deploy` needs `validate`).
   │
   ├─ 1. Checkout do repositório (GitHub Actions runner)
   │
   ├─ 2. SCP  → copia os arquivos para /home/fabiano/infra na VPS
   │            (NÃO apaga nada no destino → secrets/certs preservados)
   │
   └─ 3. SSH  → recria SOMENTE a stack do Traefik:
                docker network create --internal socket   (idempotente)
                docker compose config                     (valida)
                docker compose up -d --remove-orphans      (aplica compose)
                [se config/dynamic mudou] restart traefik  (releitura limpa)
```

> **Por que o restart condicional:** o scp escreve os arquivos de forma não
> atômica. O file provider (`file.watch`) pode ler um `config/dynamic/*.yml`
> pela metade, falhar o parse, descartar TODOS os middlewares e "grudar" nesse
> estado (routers em erro → 404 geral). Um checksum guardado em
> `.deploy-traefik-sum` detecta mudança na config dinâmica e força um
> `restart traefik` só nesse caso — leitura limpa, sem race.

> **Só o Traefik é recriado automaticamente.** As demais stacks
> (prometheus, grafana, node_exporter, portainer, apps, databases) são
> copiadas pelo SCP, mas **recriadas manualmente** — ver seção 6.

---

## 2. Pré-requisitos

### 2.1 Secrets do repositório (GitHub → Settings → Secrets and variables → Actions)

| Secret | Descrição |
|---|---|
| `HOST` | IP/host da VPS |
| `USERNAME` | usuário SSH (`fabiano`) |
| `SSH_PRIVATE_KEY` | chave privada com acesso SSH à VPS |

### 2.2 Arquivos provisionados só na VPS (gitignored — nunca no repo)

Estes existem apenas em `/home/fabiano/infra/infrastructure/traefik/` e são
**preservados** a cada deploy (o `scp-action` não deleta):

| Arquivo | Como criar |
|---|---|
| `secrets/usersfile` | `htpasswd -cbBC 12 secrets/usersfile admin 'SENHA'` (**sem `-c` se já existir**) |
| `secrets/cloudflare-token.secret` | token de API da Cloudflare (ver 2.4) |
| `secrets/cloudflare-email.secret` | e-mail da conta Cloudflare |
| `certs/acme.json` | gerado pelo Traefik em runtime (`chmod 600`) |

### 2.3 Redes Docker externas

O compose do Traefik depende de 3 redes externas. `production`/`monitoring`
já existem; a `socket` é criada pelo próprio workflow, mas pode criar à mão:

```bash
docker network ls | grep -E 'production|monitoring|socket'
docker network create --internal socket   # se faltar (o workflow também faz)
```

### 2.4 Cloudflare (configuração por zona — feita 1x no painel)

Domínios servidos por este Traefik (todos **proxied 🟠**):
`upsolve.com.br`, `fabianolopes.com`, `fabianolopes.com.br`,
`fabianolopes.adv.br`, `prospere.academy`, `asset.cnt.br`.

Para **cada zona**:

- **SSL/TLS → Overview → Full (strict)** — obrigatório. Em "Flexible" o
  domínio entra em loop de redirect (o Traefik força HTTPS e a CF fala HTTP).
- Registros A → IP da VPS, com proxy 🟠 ligado.

**Token de API** (`secrets/cloudflare-token.secret`) usado no desafio DNS-01
do Let's Encrypt precisa alcançar **TODAS as 6 zonas**:
- Permissions: `Zone → DNS → Edit` + `Zone → Zone → Read`
- Zone Resources: **All zones** (ou as 6 zonas listadas). **Não** estreitar
  para uma só zona.

---

## 3. Certificados TLS (wildcard por zona)

O entrypoint `websecure` pré-emite um **wildcard por zona** via DNS-01
(`domains[0..5]` em [`docker-compose.yml`](infrastructure/traefik/docker-compose.yml)):

```
upsolve.com.br + *.upsolve.com.br
fabianolopes.com + *.fabianolopes.com
fabianolopes.com.br + *.fabianolopes.com.br
fabianolopes.adv.br + *.fabianolopes.adv.br
prospere.academy + *.prospere.academy
asset.cnt.br + *.asset.cnt.br
```

Vantagem: qualquer subdomínio novo já tem cert na hora, longe do rate limit
da Let's Encrypt, e o `sniStrict: true` (em `config/dynamic/tls.yml`) fica
seguro. **Ao adicionar uma zona nova:** crie um novo `domains[n]` no compose
**e** libere a zona no token da Cloudflare.

---

## 4. Middlewares — o que é global vs. o que é só painel

Definidos em
[`config/dynamic/middlewares.yml`](infrastructure/traefik/config/dynamic/middlewares.yml).

- **`default-chain` (GLOBAL — todo tráfego `websecure`, todos os domínios):**
  `security-headers` (headers seguros, **sem** `frameDeny` e **sem**
  `stsIncludeSubdomains`, para não quebrar apps com iframe/câmera como o
  `prospere.academy`) + `rate-limit` (100 req/s por IP) + `compress`.
  Aplicada via `--entrypoints.websecure.http.middlewares=default-chain@file`.

- **`admin-chain` (só painéis: traefik/prometheus/grafana):**
  `panel-headers` (`frameDeny` + HSTS forte + trava câmera/mic) + `admin-auth`
  (basicAuth via `usersfile`) + `rate-limit-strict`.

- **`portainer-protect` (Portainer, que tem login próprio):**
  `panel-headers` + `rate-limit-strict` (sem basicAuth).

Anexe as chains de painel nas labels dos routers correspondentes:
`traefik.http.routers.<nome>.middlewares=admin-chain@file` (ou
`portainer-protect@file`). O router do dashboard do Traefik já usa
`admin-chain@file`.

### IP real atrás da Cloudflare
Como os domínios são proxied, o compose confia nos ranges da Cloudflare
(`--entrypoints.websecure.forwardedheaders.trustedips=...`) para que
`rate-limit` e CrowdSec enxerguem o IP real do visitante, não o da CF.

---

## 5. Fluxo de trabalho normal

```bash
# 1) editar os arquivos localmente
# 2) commitar e enviar
git add -A
git commit -m "feat(traefik): ..."
git push origin main
# 3) acompanhar o deploy em GitHub → Actions → "Deploy Infra"
```

**Config dinâmica recarrega sozinha:** mudanças em
`config/dynamic/*.yml` (middlewares, tls) são aplicadas em runtime pelo
`--providers.file.watch=true` assim que o SCP as entrega — não precisa
recriar o container. Só mudanças no `docker-compose.yml` exigem o `up -d`
(que o workflow já faz).

---

## 6. Recriar as demais stacks (manual)

O workflow só recria o Traefik. Após um push que altere outras stacks, na VPS:

```bash
cd /home/fabiano/infra/infrastructure/prometheus && docker compose up -d
cd /home/fabiano/infra/infrastructure/grafana    && docker compose up -d
cd /home/fabiano/infra/infrastructure/node_exporter && docker compose up -d
cd /home/fabiano/infra/infrastructure/portainer  && docker compose up -d
```

> Para automatizar, dá para estender o step SSH do workflow com um loop
> pelas pastas desejadas — não foi feito por padrão para evitar downtime
> em todas as stacks a cada push.

---

## 7. Validação pós-deploy

```bash
# Painel do Traefik responde por HTTPS e pede auth (basicAuth):
curl -I https://traefik.upsolve.com.br         # esperado: HTTP/2 401

# App público de outra zona carrega (cert wildcard OK, sem loop):
curl -I https://<algo>.prospere.academy        # esperado: 200/3xx, sem loop

# IP real chegando (não o da Cloudflare) — no access log:
docker logs traefik 2>&1 | tail
# ou o access.log JSON no volume traefik_logs

# Traefik NÃO monta o docker.sock direto (usa o socket-proxy):
docker inspect traefik --format '{{ range .Mounts }}{{ .Source }}{{"\n"}}{{ end }}'
```

No dashboard (`https://traefik.upsolve.com.br`, login pelo `usersfile`),
confira se os serviços aparecem. Se vierem vazios, o gargalo costuma ser o
`allowGET` do `socket-proxy` no compose.

---

## 8. Limpeza única (pós-migração para config/dynamic)

O SCP não apaga arquivos; a pasta antiga `dynamic/` pode ter sobrado na VPS.
Como o provider agora lê `config/dynamic/`, remova o resíduo uma vez:

```bash
rm -rf /home/fabiano/infra/infrastructure/traefik/dynamic
```

---

## 9. Rollback

```bash
cd /home/fabiano/infra
git checkout <tag-ou-commit-anterior> -- infrastructure/traefik/
cd infrastructure/traefik && docker compose up -d --remove-orphans
```

O `acme.json` não é versionado e não muda no rollback — os certificados
não se perdem.
