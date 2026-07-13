# GRAFANA

Documentação do Grafana

[https://grafana.com/docs/](https://grafana.com/docs/)

Docker image

[grafana/grafana](https://hub.docker.com/r/grafana/grafana)

## Usage

Ajustar o endpoint do traefik no arquivo docker-compose.yml

```yaml
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.grafana.rule=Host(`grafana.yourdomain.com.br`)"
      - "traefik.http.routers.grafana.entrypoints=websecure"
      - "traefik.http.services.grafana.loadbalancer.server.port=3000"
      - "traefik.docker.network=production"
```

Crie o arquivo .env.

```bash
cp .env.example .env
```

```dotenv
# Define usuário admin
GF_SECURITY_ADMIN_USER=youremail@example.com
# Defina uma senha segura
GF_SECURITY_ADMIN_PASSWORD=password
# Domínio usado no Traefik
GF_SERVER_DOMAIN=traefik.yourdomain.com.br
# URL base correta para evitar erros de proxy reverso
GF_SERVER_ROOT_URL=https://grafana.yourdomain.com.br
# Desativa acesso anônimo
GF_AUTH_ANONYMOUS_ENABLED=false
# Mantém o login ativado
GF_AUTH_DISABLE_LOGIN_FORM=false

# Bloco Configuração SMTP
GF_SMTP_ENABLED=true
GF_SMTP_HOST=smtp.seu-servidor.com:587
GF_SMTP_USER=seu-email@seu-dominio.com
GF_SMTP_PASSWORD="$suaSenha123#"
GF_SMTP_FROM_ADDRESS=grafana@seu-dominio.com
GF_SMTP_FROM_NAME="Grafana Alertas"
GF_SMTP_SKIP_VERIFY=true
```

## Provisionamento como código (datasource + dashboards)

Nada é importado à mão. No boot, o Grafana lê `provisioning/` e `dashboards/`
(montados no compose) e cria tudo automaticamente — reproduzível e versionado:

```
provisioning/
  datasources/datasource.yml   # Prometheus (uid=prometheus, default) + Alertmanager
  dashboards/provider.yml       # provider file -> /var/lib/grafana/dashboards (pasta "Infra")
dashboards/                     # JSON versionado, baixado do grafana.com e com datasource fixado
  node-exporter-full.json       # host  (ID 1860)
  cadvisor.json                 # containers (ID 14282)
  postgresql.json               # ID 9628
  mysql-overview.json           # ID 7362
  redis.json                    # oliver006 redis_exporter (ID 763)
  traefik.json                  # v3 oficial (ID 17346)
  blackbox.json                 # uptime/probe HTTPS (ID 13659)
```

Os dashboards aparecem na pasta **Infra** do Grafana com o datasource já ligado —
zero clique. Para atualizar/adicionar um dashboard:

```bash
# baixa o JSON oficial e fixa o datasource provisionado (uid=prometheus)
curl -s https://grafana.com/api/dashboards/<ID>/revisions/latest/download \
  | sed 's/${DS_PROMETHEUS}/prometheus/g; s/${DS_PROM}/prometheus/g' \
  > dashboards/<nome>.json
git add dashboards/<nome>.json && git commit -m "grafana: dashboard <nome>"
```

O provider recarrega a cada 30s; após `docker compose up -d` o novo painel já entra.

> **Datasource:** o uid `prometheus` é fixo no `datasource.yml` e os JSONs apontam
> para ele. Não selecione datasource ao usar — já vem conectado.

To browse ready-to-use community dashboards: 🔗 https://grafana.com/grafana/dashboards

## Comands

```bash
docker compose build
```

```bash
docker compose up -d
```

```bash
docker compose down
```

```bash
docker compose rm
```
