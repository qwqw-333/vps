# VPS Deployment Plan — Obsidian Absolute Sync

Приватная real-time синхронизация Obsidian между macOS, Linux и iPhone.

**Стек:** Hetzner Cloud (`cx23`, x86) → Headscale v0.28.0 (native/systemd) → K3s → ArgoCD → Envoy Gateway → CouchDB → Obsidian LiveSync  
**DNS:** Duck DNS  
**Secrets:** Bitnami Sealed Secrets (зашифрованы в git, расшифровываются только кластером)

> [!NOTE]
> Все команды и версии проверены по официальной документации (март 2025).

---

## Решения по архитектурным вопросам

### Сервер → **cx23 (x86, Hetzner)**
2 vCPU, 4GB RAM, 40GB SSD, `fsn1` (Falkenstein) — минимальный пинг из Украины.

### DNS → **Duck DNS**
Бесплатный, стабильный. Формат: `yourname.duckdns.org`. Поддерживает Let's Encrypt через TXT-записи.

### Headscale → **Нативно (deb package + systemd)**

Официально рекомендуемый способ для Debian — `.deb` пакет, который автоматически:
- Создаёт системного пользователя для headscale
- Устанавливает дефолтный конфиг в `/etc/headscale/config.yaml`
- Регистрирует systemd сервис

> [!IMPORTANT]
> **Не Docker** — Headscale должен быть в host network, без прослоек. Docker bridge конфликтует с K3s CNI (flannel).

### Репозиторий → **Публичный**, секреты через Sealed Secrets

Kubernetes секреты шифруются `kubeseal` (публичным ключом кластера) и безопасно хранятся в git как `SealedSecret`. Приватный ключ для расшифровки живёт только в кластере.

### Сетевой доступ к K8s сервисам → **Envoy Gateway**

Envoy Gateway слушает на порту `8443` на VPN-интерфейсе (Headscale). Все K8s сервисы (CouchDB, Headscale UI, будущие) маршрутизируются через HTTPRoute. Headscale занимает `443/80` нативно — конфликта нет.

### Настройка сервера → **Ansible** (не cloud-init)
Terraform только создаёт сервер. Ansible настраивает. Идемпотентен, безопасно перезапускать.

---

## Структура проекта

```
vps/
├── AGENTS.md
├── README.md
├── plan.md
├── .gitignore
│
├── infra/                       # Terraform
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars         # ⚠️ в .gitignore
│
├── ansible/
│   ├── inventory.yml
│   ├── playbook.yml
│   └── roles/
│       ├── base/                # apt, ufw, fail2ban
│       ├── users/               # системный пользователь, SSH
│       ├── headscale/           # .deb + systemd + config + автосоздание user + preauthkey
│       ├── k3s/                 # K3s installer
│       └── tailscale/           # Tailscale client → self-registration
│
├── k8s/
│   ├── argocd/
│   │   ├── application.yml                # CouchDB
│   │   ├── application-sealed-secrets.yml # Sealed Secrets (Helm)
│   │   ├── application-envoy-gateway.yml  # Envoy Gateway (Helm)
│   │   ├── application-gateway-infra.yml  # Gateway API ресурсы
│   │   └── application-headscale-ui.yml   # Headscale UI
│   ├── infra/
│   │   └── gateway/
│   │       ├── gateway-class.yml           # GatewayClass + EnvoyProxy
│   │       ├── gateway.yml                # Gateway listener :8443
│   │       └── headscale-api-httproute.yml # ExternalName Service + /api/v1 прокси
│   └── apps/
│       ├── couchdb/
│       │   ├── namespace.yml
│       │   ├── configmap.yml
│       │   ├── sealed-secret.yml          # ✅ безопасно в git
│       │   ├── pvc.yml
│       │   ├── statefulset.yml
│       │   ├── service.yml
│       │   └── httproute.yml              # /couchdb маршрут
│       └── headscale-ui/
│           ├── namespace.yml
│           ├── deployment.yml
│           ├── service.yml
│           └── httproute.yml              # /web маршрут
│
├── scripts/
│   ├── colors.sh
│   └── generate-inventory.py
│
└── docs/
    ├── terraform.md
    ├── ansible.md
    └── kubernetes.md
```

---

## Фаза 0: Подготовка (локальная машина)

- [ ] `brew install terraform kubectl helm ansible`
- [ ] `brew install argocd kubeseal`  _(ArgoCD CLI + Sealed Secrets CLI)_
- [ ] Зарегистрировать Duck DNS домен
- [ ] Tailscale установить на macOS, Linux, iPhone
- [ ] Создать публичный Git-репозиторий, `.gitignore`, `AGENTS.md`

---

## Фаза 1: Terraform — создание сервера

- [ ] Hetzner Cloud Console → создать проект → сгенерировать API Token (R/W)
- [ ] Загрузить SSH public key в Security → SSH Keys
- [ ] Описать `infra/main.tf`:
  - Provider: `hetznercloud/hcloud`
  - Сервер: `cx23`, location `fsn1`, OS `debian-12`
  - Firewall: порты `22/tcp`, `443/tcp`, `3478/udp`, `41641/udp`
  - SSH Key resource
- [ ] `terraform init && terraform plan && terraform apply`
- [ ] `ssh root@<SERVER_IP>` — убедиться, что доступен

---

## Фаза 2: Ansible — настройка сервера

### Конфигурация inventory.yml
Генерируется автоматически из Terraform output:
```bash
cd ansible && task generate-inventory
```

### Роли
- **`base`**: apt upgrade, ufw, fail2ban, hostname
- **`users`**: системный пользователь, SSH-ключ, sudo
- **`headscale`**: .deb v0.28.0 + systemd + config.yaml (Jinja2) + создание пользователя + автогенерация preauthkey (5 мин) как Ansible fact
- **`k3s`**: K3s installer + kubeconfig
- **`tailscale`**: установка + самоподключение сервера к Headscale (использует fact из headscale-роли)

### Запуск (один прогон — всё автоматически)
```bash
cd ansible && task play
```

### Vault-переменные (обязательные)
```
vault_server_url               # https://your.duckdns.org
vault_acme_email               # email для Let's Encrypt
vault_tls_letsencrypt_hostname  # your.duckdns.org
vault_headscale_user           # konoval
```

> [!IMPORTANT]
> Headscale конфиг основан на официальном примере для v0.28.0:
> `https://github.com/juanfont/headscale/blob/v0.28.0/config-example.yaml`

---

## Фаза 3: Headscale — подключение устройств

### Сервер подключается автоматически
Headscale-роль генерирует preauthkey (5 мин) и сохраняет как Ansible fact. Tailscale-роль подхватывает его и подключает сервер к Headscale — всё в одном `task play`.

### Подключение клиентских устройств (вручную)
```bash
# На сервере — создать reusable ключ через Headscale UI (http://k3s-01.hs.local:8443/web)
# или через SSH:
ssh root@<SERVER_IP> \
  "headscale preauthkeys create --user 1 --reusable --expiration 24h"

# На каждом устройстве (macOS, Linux, iPhone)
tailscale up --login-server=https://<DUCKDNS_DOMAIN> --authkey=<KEY>

# Проверка
headscale nodes list
tailscale status
```

- [ ] Сервер подключён к Headscale (автоматически через Ansible)
- [ ] macOS, Linux и iPhone подключены
- [ ] Все устройства пингуют сервер по `100.64.x.x`

---

## Фаза 4: ArgoCD + Sealed Secrets + Envoy Gateway + CouchDB

### 4.1 ArgoCD — установка на кластер
```bash
# На сервере (через SSH)
kubectl create namespace argocd
kubectl apply -n argocd \
  --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Дождаться готовности
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

# Начальный пароль
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

> [!NOTE]
> Флаги `--server-side --force-conflicts` обязательны начиная с ArgoCD v2.x — некоторые CRDs превышают лимит 262KB на аннотацию при client-side apply.

### 4.2 Задеплоить все ArgoCD Applications
```bash
kubectl apply -f k8s/argocd/
# ArgoCD установит: Sealed Secrets, Envoy Gateway, Gateway infra, CouchDB, Headscale UI
```

### 4.3 Создать и запечатать CouchDB Secret
```bash
# Установить kubeseal локально
brew install kubeseal

# Создать SealedSecret (дождаться, пока Sealed Secrets controller запустится)
kubectl create secret generic couchdb-credentials \
  --namespace obsidian-sync \
  --from-literal=COUCHDB_USER=admin \
  --from-literal=COUCHDB_PASSWORD=<your-password> \
  --dry-run=client -o yaml \
| kubeseal --format=yaml --scope=namespace-wide \
> k8s/apps/couchdb/sealed-secret.yml

# Закоммитить и запушить — ArgoCD подтянет автоматически
git add k8s/apps/couchdb/sealed-secret.yml && git commit -m "seal couchdb credentials" && git push
```

### 4.4 Проверка
```bash
# Все поды живы
kubectl get pods -A

# Envoy Gateway доступен через VPN
curl http://k3s-01.hs.local:8443/couchdb/

# Headscale UI
# Открыть в браузере: http://k3s-01.hs.local:8443/web
# Settings → вставить API key (headscale apikeys create на сервере)
```

---

## Фаза 5: Obsidian LiveSync

- [ ] Установить плагин **Self-hosted LiveSync** (Community Plugins)
- [ ] CouchDB URL: `http://k3s-01.hs.local:8443/couchdb`, DB: `obsidian`
- [ ] Включить E2EE, задать парольную фразу
- [ ] **Rebuild Everything** на основном устройстве
- [ ] **Copy Setup URI** → настроить Linux и iPhone

---

## Фаза 6: Hardening

- [ ] Let's Encrypt через Duck DNS для Headscale TLS
- [ ] CouchDB backup CronJob (`_replicate` или snapshot PVC)
- [ ] unattended-upgrades на сервере
- [ ] README с финальной архитектурой

---

## Verification Plan

```bash
# Terraform
terraform plan                              # No changes

# K3s
kubectl get nodes                           # STATUS=Ready
kubectl get pods --all-namespaces           # Все Running

# CouchDB через Envoy Gateway (VPN)
curl http://k3s-01.hs.local:8443/couchdb/  # {"couchdb":"Welcome",...}

# Headscale
headscale nodes list                        # 3+ nodes online, STATUS=connected

# Headscale UI
# http://k3s-01.hs.local:8443/web
```

**Ручные проверки:**
1. Создать заметку на macOS → появилась на Linux/iPhone за ~5 сек
2. Перезагрузить сервер → все сервисы поднялись автоматически (systemd + K3s autostart)
3. Отключить Tailscale на устройстве → Envoy Gateway недоступен (изоляция)
