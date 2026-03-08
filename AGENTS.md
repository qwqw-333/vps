# AGENTS.md — AI Agent Guide

Infrastructure as Code for a self-hosted Obsidian sync server, Headscale VPN, and Authelia SSO on Hetzner Cloud: Terraform (Hetzner + Cloudflare), Ansible, Docker Compose, Caddy, CouchDB, Headscale, Headplane, Authelia.

## Project Structure

```
vps/
├── infra/ # Terraform (Hetzner Cloud + Cloudflare DNS)
│ ├── Taskfile.yml # task init, plan, apply, ip
│ ├── main.tf # Hetzner server, firewall, Cloudflare DNS records
│ ├── variables.tf
│ ├── outputs.tf
│ └── terraform.tfvars # in .gitignore
│
├── ansible/ # Server configuration (Ansible)
│ ├── Taskfile.yml # task generate-inventory, play, ping, status
│ ├── ansible.cfg
│ ├── playbook.yml
│ ├── inventory.yml # Generated — do not edit (in .gitignore)
│ ├── inventory.yml.j2 # Inventory template (source of truth)
│ ├── .vault_pass # Vault password (in .gitignore)
│ ├── group_vars/
│ │ └── all/
│ │ └── vault.yml # Encrypted secrets (ansible-vault)
│ └── roles/
│ ├── base/ # hostname, apt, ufw, fail2ban
│ ├── users/ # System user, SSH key, sudo
│ ├── docker/ # Docker CE + Compose plugin + proxy network
│ ├── caddy/ # Shared Caddy reverse proxy (Origin CA cert)
│ ├── authelia/ # Authelia SSO/OIDC provider
│ ├── couchdb/ # CouchDB (compose.yaml), cluster init
│ └── headscale/ # Headscale VPN + Headplane web UI (OIDC via Authelia)
│
├── scripts/ # Helper scripts
│ ├── colors.sh # Shared ANSI color definitions (bash/zsh)
│ └── generate-inventory.py # Renders inventory.yml from Terraform output
│
└── docs/ # Documentation
 ├── terraform.md # Infra, remote state, Cloudflare DNS
 ├── ansible.md # Roles, vault, CouchDB deployment
 └── livesync.md # Obsidian LiveSync setup
```

## Conventions

### Language

- **All files** (code, comments, docs, README): English

### Terraform

- `terraform.tfvars` must NEVER be committed
- Use `Taskfile.yml` in `infra/` for all operations (`task plan`, `task apply`, `task ip`)
- `hcloud_token` and `cloudflare_api_token` stored as HCP Terraform Sensitive variables

### Ansible

- Use `.yml` extension for all YAML files
- `ansible/inventory.yml` is **generated** by `scripts/generate-inventory.py` — never edit manually, edit `inventory.yml.j2` instead
- Role variables with sensible defaults go in `roles/<name>/defaults/main.yml`; project-specific overrides go in `playbook.yml vars:`
- Roles must be idempotent and self-contained (no implicit dependencies on other roles)
- Use FQCN for all modules: `ansible.builtin.*`, `ansible.posix.*`, `community.general.*`, `community.docker.*`
- Secrets are stored in `group_vars/all/vault.yml`, encrypted with `ansible-vault`
- Vault password file: `.vault_pass` (in `.gitignore`), configured via `vault_password_file` in `ansible.cfg`
- Vault variables use the `vault_` prefix: `vault_couchdb_user`, `vault_couchdb_password`, etc.

### Scripts

- Shared ANSI color definitions for **shell scripts and Taskfiles**: `scripts/colors.sh` — source with `source ../scripts/colors.sh`
- Shared ANSI color definitions for **Python scripts**: define inline as a `_colors()` function that respects the `NO_COLOR` env var (https://no-color.org). Do NOT create a separate `colors.py` unless there are 3+ Python scripts that need it
- Python scripts must use **stdlib only** (no `pip install`) — exception: `jinja2` is acceptable (always present as an Ansible dependency)

### Docker

- All services share a single external Docker network `proxy` (created by the `docker` role)
- Caddy runs in `/opt/caddy/` as a shared reverse proxy for all domains
- Authelia runs in `/opt/authelia/` — SSO/OIDC provider for Headplane and other services
- CouchDB runs in `/opt/couchdb/` — accessible via Caddy and `127.0.0.1:5984`
- Headscale + Headplane run in `/opt/headscale/` — accessible via Caddy and `127.0.0.1:8080`
- Caddy terminates TLS using a **Cloudflare Origin Certificate** (wildcard `*.qwqw333.work`, traffic proxied through Cloudflare)
- Docker Compose files are named `compose.yaml` (not `docker-compose.yml`)

### Comments

- Brief (1-2 lines), explain "why" not "what"

## Critical Rules

### Security

- **NEVER** commit API keys (Hetzner, Cloudflare), SSH private keys, passwords, or certificates
- Sensitive Ansible variables live exclusively in `group_vars/all/vault.yml` (encrypted)
- `.vault_pass` must never be committed — it is the only local secret
- CouchDB is protected by: Cloudflare proxy + Origin Certificate + E2E encryption (LiveSync) + CouchDB auth (`require_valid_user = true`)
- Headscale is protected by: Cloudflare proxy + Origin Certificate + Headscale auth (API keys)
- Headplane is protected by: Authelia OIDC (SSO) + Headscale API key
- Authelia is protected by: Cloudflare proxy + Origin Certificate + argon2id password hashing

### Ansible Vault

- Edit encrypted values: `ansible-vault edit group_vars/all/vault.yml`
- View encrypted values: `ansible-vault view group_vars/all/vault.yml`
- Re-encrypt after password change: `ansible-vault rekey group_vars/all/vault.yml`
- Vault is decrypted automatically during `ansible-playbook` via `vault_password_file` in `ansible.cfg`

### Generated Files

| File | Generated by | Source of truth |
|------|-------------|-----------------|
| `ansible/inventory.yml` | `scripts/generate-inventory.py` | `ansible/inventory.yml.j2` + Terraform output |

Do not edit generated files manually.
