# Satis

Composer repository privada do ecossistema **upsolve-br** — serve metadados de pacotes para `https://packages.upsolve.com.br`.

O container roda **long-lived** (nginx + php-fpm + cron). Builds ocorrem por três caminhos: entrypoint inicial, cron a cada 6h, e webhook do GitHub (POST em `/webhook.php` após push de tag).

## Operação no servidor

### Build ad-hoc (executar dentro do container)

**Use esse comando** quando precisar forçar rebuild manual (ex: webhook não disparou, debugging):

```bash
cd /opt/Infra-com-Traefik/Applications/satis
./scripts/satis-run.sh
```

O wrapper chama `docker compose exec satis satis-build` — roda o build **dentro do container já vivo**, sem criar processo zumbi.

### ⚠️ NÃO use `docker compose run` para builds ad-hoc

```bash
# ERRADO — deixa container zumbi vivo após o build terminar
docker compose run satis satis-build

# ERRADO — variação do erro acima (mesmo problema)
docker compose run -d satis satis-build
```

`docker compose run` **cria um novo container a cada chamada** e não o remove ao final (mesmo após `set -e` falhar). Em 2026-05-19, 4 containers `satis-satis-run-*` vivos há 5 semanas seguraram o inode antigo do bind-mount de `satis.json` e causaram **1h de debug do CI workflow**.

Se precisar mesmo de `docker compose run` (ex: testar comando que não existe no container), **sempre passe `--rm`**:

```bash
# Correto SE precisar mesmo de docker compose run
docker compose run --rm satis bash -c "echo teste"
```

### Limpar containers zumbis

Se desconfiar de zumbis acumulados:

```bash
# Listar
docker ps -a --filter "name=satis-satis-run-*"

# Matar todos
docker ps -aq --filter "name=satis-satis-run-*" | xargs -r docker rm -f
```

Os zumbis impedem inodes de bind-mounts atualizarem corretamente (causa raiz do incidente 2026-05-19).

### Rebuild completo (deploy ou config change)

Quando o `satis.json` for editado ou pacote novo registrado:

```bash
cd /opt/Infra-com-Traefik/Applications/satis
git pull
docker compose up -d --build
./scripts/satis-run.sh
```

`up -d --build` reaproveita o container existente se nada mudou na imagem; só recria se o Dockerfile/Compose mudou. Combinado com o exec do `satis-run.sh`, evita o caminho `run`.

## Bind-mount de diretório (não de arquivo)

`docker-compose.yml` faz bind do **diretório** `./config`, não do arquivo `./config/satis.json`:

```yaml
volumes:
  - ./config:/var/satis/config:ro
```

**Por quê:** bind de arquivo individual cacheia o inode original. Quando o host substitui o arquivo via SCP/rsync (que faz replace atomic — novo arquivo, novo inode), o container continua vendo o conteúdo antigo, **mesmo após `docker compose down/up`**. Bind do diretório resolve porque o container resolve o caminho a cada syscall.

## Webhook

`config/webhook.php` recebe POSTs do GitHub. Validação HMAC via `$WEBHOOK_SECRET`. Dispara `satis-build` async via `exec('nohup ... &')`.

Logs:

```bash
docker compose exec satis tail -100 /var/log/satis-build.log
docker compose exec satis tail -100 /var/log/nginx/access.log | grep webhook
```

Se webhook não está atualizando, ver `upsolve-br/upsolve-workspace#28` (issue rastreando comportamento).

## Registrar pacote novo

Editar `config/satis.json`:

```json
{
    "type": "vcs",
    "url": "git@github.com:upsolve-br/<package-name>.git"
}
```

Commit, push do `Infra-com-Traefik`, deploy no servidor, `satis-run.sh`.

Skill em desenvolvimento: `upsolve-register-satis` (issue `upsolve-br/upsolve-workspace#29`).

## Schema do `satis.json`

O `composer/satis` valida o JSON contra um schema strict. Campos **não suportados** que rejeitam o build:

- `version` (no root)
- `description` (no root)

Mantenha o `satis.json` minimalista — só `name`, `homepage`, `repositories`, `require-all` (ou `require`), e `archive` (se aplicável).
