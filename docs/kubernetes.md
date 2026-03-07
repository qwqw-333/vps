# Kubernetes

GitOps через ArgoCD. Envoy Gateway как API gateway. Sealed Secrets для управления секретами.

## Архитектура

```
Internet → Headscale :443 (native/systemd) → VPN tunnel
VPN clients → Envoy Gateway :8443 (K8s) → HTTPRoute → Services
```

Headscale занимает порты 443/80 нативно. Envoy Gateway слушает на 8443 — доступен только через VPN (UFW блокирует извне).

## ArgoCD Applications

| Application | Источник | Что устанавливает |
|------------|---------|------------------|
| `couchdb` | git: `k8s/apps/couchdb` | CouchDB StatefulSet, Service, ConfigMap, PVC, SealedSecret, HTTPRoute |
| `headscale-ui` | git: `k8s/apps/headscale-ui` | Headscale Web UI |
| `envoy-gateway` | Helm: `envoyproxy/gateway-helm` v1.3.0 | Envoy Gateway controller |
| `gateway-infra` | git: `k8s/infra/gateway` | GatewayClass, Gateway, Headscale API proxy |
| `sealed-secrets` | Helm: `sealed-secrets` v2.17.1 | Sealed Secrets controller |

### Первоначальная установка ArgoCD

```bash
# На сервере
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

# Начальный пароль
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Задеплоить все applications
kubectl apply -f k8s/argocd/
```

## Sealed Secrets

Bitnami Sealed Secrets — приватный ключ живёт только в кластере. SealedSecret ресурсы безопасно хранятся в git.

### Создание SealedSecret

```bash
# Установить kubeseal
brew install kubeseal

# Создать и запечатать секрет
kubectl create secret generic couchdb-credentials \
  --namespace obsidian-sync \
  --from-literal=COUCHDB_USER=admin \
  --from-literal=COUCHDB_PASSWORD=<password> \
  --dry-run=client -o yaml \
| kubeseal --format=yaml --scope=namespace-wide \
> k8s/apps/couchdb/sealed-secret.yml

# Закоммитить — ArgoCD подтянет автоматически
```

### Получение публичного сертификата

```bash
kubeseal --fetch-cert \
  --controller-name=sealed-secrets \
  --controller-namespace=kube-system
```

## Envoy Gateway

`loadBalancerIP: 100.64.0.1` — зафиксирован в `gateway-class.yml`.

### Почему 100.64.0.1 — фиксированный IP

Headscale не поддерживает назначение статических IP ([#1455](https://github.com/juanfont/headscale/issues/1455), [#2151](https://github.com/juanfont/headscale/issues/2151)). IP `100.64.0.1` гарантируется двумя факторами:

1. **`allocation: sequential`** в `config.yaml` — Headscale выдаёт IP из префикса `100.64.0.0/10` последовательно
2. **Сервер всегда регистрируется первым** — headscale-роль генерирует preauthkey, tailscale-роль подключает сервер в одном прогоне playbook, до любых ручных устройств

Если Headscale добавит static IP — перейти на него. До тех пор этот подход надёжен при условии, что первый `task play` выполняется до подключения клиентских устройств.

### Маршруты

| Путь | Сервис | Namespace |
|------|--------|-----------|
| `/couchdb/*` | couchdb:5984 | obsidian-sync |
| `/web/*` | headscale-ui:80 | headscale-ui |
| `/api/v1/*` | headscale-api:443 (host) | envoy-gateway-system |

Доступ: `http://k3s-01.hs.local:8443/<path>`

## Headscale UI

Web-интерфейс для управления устройствами Headscale.

1. Открыть `http://k3s-01.hs.local:8443/web`
2. На сервере: `headscale apikeys create` — скопировать ключ
3. В UI: Settings → вставить API key
4. Создавать preauthkeys, управлять нодами

API проксируется через Envoy Gateway (`/api/v1` → Headscale на хосте), поэтому CORS-проблем нет.
