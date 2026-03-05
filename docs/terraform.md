# Terraform

Управление инфраструктурой на Hetzner Cloud через Terraform с remote state в HCP Terraform (Terraform Cloud).

## Структура

```
infra/
├── main.tf           # Провайдер, backend, основные ресурсы
├── variables.tf      # Объявление переменных
├── outputs.tf        # Выходные значения
└── terraform.tfvars  # Локальные переменные (не коммитить, в .gitignore)
```

## Ресурсы

| Ресурс | Имя | Описание |
|---|---|---|
| `hcloud_server` | `k3s-01` | Основной сервер (cx23, Debian 12, fsn1) |
| `hcloud_primary_ip` | `ip-k3s-01` | Статический IPv4, не удаляется при пересоздании сервера |
| `hcloud_firewall` | `fw-default` | Правила фаервола, применяется по label |

## Remote State — HCP Terraform

State хранится в [HCP Terraform](https://app.terraform.io) (организация `qwqw-org`, workspace `hetzner-personal`).

- Workflow: **CLI-driven** — команды запускаются локально, выполняются удалённо
- `terraform plan` и `terraform apply` выполняются на серверах HCP Terraform
- Локальные `*.tfstate` файлы не используются

## Переменные

| Переменная | Где хранится | Описание |
|---|---|---|
| `hcloud_token` | HCP Terraform (Sensitive) | API токен Hetzner Cloud |
| `server_type` | `variables.tf` (default: `cx23`) | Тип сервера |
| `location` | `variables.tf` (default: `fsn1`) | Датацентр |
| `image` | `variables.tf` (default: `debian-12`) | Образ ОС |

> Локальный `terraform.tfvars` имеет приоритет над переменными в HCP Terraform.
> Используй его только для временных экспериментов.

## Первоначальная настройка на новой машине

```bash
# 1. Установить Terraform из официального tap
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# 2. Авторизоваться в HCP Terraform
terraform login

# 3. Инициализировать
cd infra/
terraform init
```

## Основные команды

```bash
# Посмотреть планируемые изменения
terraform plan

# Применить изменения
terraform apply

# Посмотреть текущий state
terraform show

# Посмотреть outputs
terraform output
```

## Безопасность

- `terraform.tfvars` добавлен в `.gitignore` — никогда не коммитить
- `hcloud_token` хранится только в HCP Terraform как Sensitive переменная
- Primary IP создан с `auto_delete = false` — не удалится случайно вместе с сервером
