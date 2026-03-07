# Ansible

Настройка сервера: base packages, пользователь, Headscale, K3s, Tailscale.

## Роли

| Роль | Назначение |
|------|-----------|
| **base** | apt upgrade, hostname, ufw, fail2ban |
| **users** | Системный пользователь, SSH-ключ, passwordless sudo |
| **headscale** | Headscale v0.28.0 .deb, systemd, config, создание user, генерация preauthkey |
| **k3s** | K3s installer, kubeconfig symlink |
| **tailscale** | Tailscale client, systemd ordering, подключение к Headscale |

## Запуск

```bash
cd ansible

# Сгенерировать inventory из Terraform output
task generate-inventory

# Проверить SSH-доступ
task ping

# Запустить все роли
task play
```

Один `task play` делает всё: устанавливает Headscale, генерирует preauthkey, ставит K3s, подключает сервер к Headscale через Tailscale.

## Vault

Секреты хранятся в `group_vars/all/vault.yml`, зашифрованы `ansible-vault`. Пароль в `.vault_pass` (в .gitignore).

### Обязательные переменные

| Переменная | Описание |
|------------|---------|
| `vault_server_url` | `https://your.duckdns.org` |
| `vault_acme_email` | Email для Let's Encrypt |
| `vault_tls_letsencrypt_hostname` | `your.duckdns.org` |
| `vault_headscale_user` | Имя пользователя Headscale |

### Управление

```bash
# Редактировать секреты
ansible-vault edit group_vars/all/vault.yml

# Просмотреть
ansible-vault view group_vars/all/vault.yml

# Сменить пароль
ansible-vault rekey group_vars/all/vault.yml
```

## Headscale preauthkey flow

Headscale и Tailscale роли работают в одном playbook. Headscale-роль:
1. Устанавливает и запускает Headscale
2. Создаёт пользователя
3. Получает user ID через `headscale users list -o json` (v0.28.0 требует числовой ID)
4. Генерирует короткоживущий preauthkey (5 мин)
5. Публикует его как `tailscale_authkey` fact

Tailscale-роль подхватывает fact и выполняет `tailscale up`.

## Конфигурация

- `ansible.cfg` — основные настройки (inventory path, vault, SSH pipelining)
- `inventory.yml` — **генерируется** из `inventory.yml.j2`, не редактировать
- `playbook.yml` — подключает роли, задаёт project-specific переменные
