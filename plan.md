# VPS Deployment Plan — Obsidian Absolute Sync

Приватная real-time синхронизация Obsidian между macOS, Linux и iPhone.

**Стек:** Hetzner Cloud (`cx23`, x86) → Headscale v0.28.0 (native/systemd) → K3s → ArgoCD → CouchDB → Obsidian LiveSync  
**DNS:** Duck DNS

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

### Репозиторий → **Публичный**, секреты через K8s Secrets / SOPS

### Настройка сервера → **Ansible** (не cloud-init)
Terraform только создаёт сервер. Ansible настраивает. Идемпотентен, безопасно перезапускать.

---

## Структура проекта

```
vps/
├── AGENTS.md                    # AI Agent Guide
├── README.md
├── plan.md                      # Оригинальный план
├── .gitignore                   # terraform.tfvars, *.pem, kubeconfig
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
│       │   └── tasks/
│       │       └── main.yml
│       ├── headscale/           # .deb + systemd + config
│       │   ├── tasks/
│       │   │   └── main.yml
│       │   └── templates/
│       │       └── config.yaml.j2
│       └── k3s/
│           └── tasks/
│               └── main.yml
│
├── k8s/                         # GitOps манифесты
│   ├── argocd/
│   │   └── application.yml
│   └── apps/
│       └── couchdb/
│           ├── namespace.yml
│           ├── configmap.yml    # CORS settings
│           ├── secret.yml       # Template (реальный в SOPS)
│           ├── pvc.yml
│           ├── statefulset.yml
│           └── service.yml
│
└── scripts/
    └── setup-devices.sh         # Регистрация устройств
```

---

## Фаза 0: Подготовка (локальная машина)

- [ ] `brew install terraform kubectl helm ansible`
- [ ] `brew install argocd`  _(ArgoCD CLI)_
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
```yaml
all:
  hosts:
    vps:
      ansible_host: "<SERVER_IP>"
      ansible_user: root
      ansible_ssh_private_key_file: ~/.ssh/id_ed25519
```

### Роли
- **`base`**: `apt update/upgrade`, установка `curl htop fail2ban`, настройка `ufw`
- **`headscale`**: скачать `.deb` Headscale v0.28.0 (amd64), `apt install ./headscale.deb`, задеплоить `config.yaml` из шаблона Jinja2, `systemctl enable --now headscale`
- **`k3s`**: установить K3s с флагами `--disable traefik --node-external-ip <SERVER_IP>`

### Запуск
```bash
ansible-playbook -i ansible/inventory.yml ansible/playbook.yml
```

> [!IMPORTANT]
> Headscale конфиг берётся из официального примера для v0.28.0:  
> `https://github.com/juanfont/headscale/blob/v0.28.0/config-example.yaml`  
> Основные поля: `server_url`, `listen_addr`, `ip_prefixes`, `db_path`

---

## Фаза 3: Headscale — подключение устройств

```bash
# На сервере
headscale users create konoval
headscale preauthkeys create --user konoval --reusable --expiration 24h
# → копируем ключ

# На каждом устройстве
tailscale up --login-server=https://<DUCKDNS_DOMAIN> --authkey=<KEY>

# Проверка
headscale nodes list
tailscale status
```

- [ ] macOS, Linux и iPhone подключены
- [ ] Все три пингуют сервер по `100.64.x.x`

---

## Фаза 4: ArgoCD + CouchDB

### ArgoCD установка
```bash
kubectl create namespace argocd
kubectl apply -n argocd \
  --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Начальный пароль
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Доступ к UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# → https://localhost:8080  (admin / <password>)
```

> [!NOTE]
> Флаги `--server-side --force-conflicts` обязательны начиная с ArgoCD v2.x — некоторые CRDs (ApplicationSet) превышают лимит 262KB на аннотацию при client-side apply.

### CouchDB манифесты
- **namespace.yml**: `obsidian-sync`
- **configmap.yml**: CORS — `origins = *`, `credentials = true`, `methods = GET, POST, PUT, DELETE, HEAD`
- **secret.yml**: `COUCHDB_USER`, `COUCHDB_PASSWORD`
- **pvc.yml**: 10Gi, `local-path` (K3s default StorageClass)
- **statefulset.yml**: 1 реплика, mount PVC в `/opt/couchdb/data`
- **service.yml**: ClusterIP, порт 5984

### Деплой и проверка
```bash
# ArgoCD подтянет автоматически после коммита

# Проверка pod
kubectl get pods -n obsidian-sync

# Проверка CouchDB
kubectl port-forward svc/couchdb -n obsidian-sync 5984:5984
curl http://admin:password@localhost:5984/
curl -X PUT http://admin:password@localhost:5984/obsidian
```

---

## Фаза 5: Obsidian LiveSync

- [ ] Установить плагин **Self-hosted LiveSync** (Community Plugins)
- [ ] CouchDB URL: `http://100.64.x.x:5984`, DB: `obsidian`
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

# CouchDB
curl http://admin:pass@100.64.x.x:5984/    # {"couchdb":"Welcome",...}

# Headscale
headscale nodes list                        # 3 nodes online, STATUS=connected
```

**Ручные проверки:**
1. Создать заметку на macOS → появилась на Linux/iPhone за ~5 сек
2. Перезагрузить сервер → все сервисы поднялись автоматически (systemd)
3. Отключить Tailscale на устройстве → CouchDB недоступен (изоляция)
