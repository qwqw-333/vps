# Obsidian Sync — Self-hosted

Приватная real-time синхронизация Obsidian между macOS, Linux и iPhone через собственный VPN.

## Архитектура

```
┌─────────────────┐
│  Hetzner cx23   │
│  Debian 12      │
│                 │
│  ┌───────────┐  │
│  │ Headscale │◄─────── Tailscale (macOS, Linux, iPhone)
│  │ (systemd) │  │
│  └───────────┘  │
│                 │
│  ┌───────────┐  │
│  │    K3s    │  │
│  │  ┌─────┐  │  │
│  │  │Argo │  │  │
│  │  │ CD  │  │  │
│  │  └──┬──┘  │  │
│  │     │     │  │
│  │  ┌──▼──┐  │  │
│  │  │Couch│◄─────── Obsidian LiveSync
│  │  │ DB  │  │  │
│  │  └─────┘  │  │
│  └───────────┘  │
└─────────────────┘
```

**Стек:** Terraform → Ansible → Headscale v0.28 → K3s → ArgoCD → CouchDB

## Структура проекта

```
vps/
├── infra/                      # Terraform (Hetzner Cloud)
│   ├── Taskfile.yml            # Task-автоматизация Terraform
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars        # ⚠ в .gitignore
│
├── ansible/
│   ├── inventory.yml
│   ├── playbook.yml
│   └── roles/
│       ├── base/               # apt, ufw, fail2ban
│       ├── headscale/          # .deb + systemd + config
│       └── k3s/                # K3s installer
│
├── k8s/
│   ├── argocd/
│   │   └── application.yml    # ArgoCD Application
│   └── apps/
│       └── couchdb/           # Namespace, ConfigMap, Secret, PVC, StatefulSet, Service
│
└── scripts/
    ├── colors.sh              # Общие цвета для скриптов и Taskfile
    └── setup-devices.sh       # Подключение устройств к Headscale
```

## Требования

- macOS с Homebrew
- Hetzner Cloud аккаунт + API токен
- Duck DNS домен
- Tailscale на всех устройствах

### Локальные инструменты

```bash
brew install terraform ansible kubectl helm argocd
brew install tailscale go-task
```

## Быстрый старт

### 1. Terraform — создание сервера

```bash
cd infra
# Подставить Hetzner API токен в terraform.tfvars

# Через Taskfile:
task plan
task apply
task ip          # Вывести IP сервера

# Или вручную:
terraform init && terraform plan && terraform apply
```

### 2. Ansible — настройка сервера

```bash
# Подставить IP в ansible/inventory.yml
# Подставить Duck DNS домен и IP в ansible/playbook.yml
ansible-playbook -i ansible/inventory.yml ansible/playbook.yml
```

### 3. Headscale — подключение устройств

```bash
# На сервере:
headscale users create konoval
headscale preauthkeys create --user konoval --reusable --expiration 24h

# На каждом устройстве:
./scripts/setup-devices.sh <duckdns-домен> <auth-key>

# Проверка:
headscale nodes list
```

### 4. ArgoCD + CouchDB

```bash
# Установить ArgoCD (один раз):
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Создать секрет CouchDB:
kubectl create secret generic couchdb-credentials \
  --namespace obsidian-sync \
  --from-literal=COUCHDB_USER=admin \
  --from-literal=COUCHDB_PASSWORD=<пароль>

# Подставить URL репозитория в k8s/argocd/application.yml
kubectl apply -f k8s/argocd/application.yml

# Проверка:
kubectl get pods -n obsidian-sync
```

### 5. Obsidian LiveSync

1. Установить плагин **Self-hosted LiveSync** (Community Plugins)
2. CouchDB URL: `http://100.64.x.x:5984`, DB: `obsidian`
3. Включить E2EE, задать парольную фразу
4. **Rebuild Everything** на основном устройстве
5. **Copy Setup URI** → настроить остальные устройства

## Проверка работоспособности

```bash
# Terraform
terraform plan                              # No changes

# K3s
kubectl get nodes                           # STATUS = Ready

# CouchDB
kubectl port-forward svc/couchdb -n obsidian-sync 5984:5984
curl http://admin:pass@localhost:5984/       # {"couchdb":"Welcome",...}

# Headscale
headscale nodes list                        # Все устройства online
```

## Безопасность

- CouchDB доступен **только** через Headscale VPN (100.64.x.x)
- API ключи и пароли **не хранятся** в репозитории
- `terraform.tfvars` в `.gitignore`
- fail2ban + unattended-upgrades на сервере

### Двойной файрвол (defense-in-depth)

| Слой | Где | Управление |
|------|-----|------------|
| **Hetzner Cloud Firewall** | На уровне гипервизора, до VM | Terraform (`infra/main.tf`) |
| **UFW** | На уровне ОС внутри VM | Ansible (`roles/base/`) |

Оба настроены на одинаковые порты: `22/tcp`, `80/tcp`, `443/tcp`, `3478/udp`, `41641/udp`.
Если один слой скомпрометирован или неправильно настроен — второй продолжает защищать.
