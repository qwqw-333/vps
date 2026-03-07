# AGENTS.md — AI Agent Guide

Infrastructure as Code for a self-hosted Obsidian sync server on Hetzner Cloud: Terraform, Ansible, Headscale, K3s, ArgoCD, Envoy Gateway, CouchDB.

## Project Structure

```
vps/
├── infra/                          # Terraform (Hetzner Cloud provisioning)
│   ├── Taskfile.yml                # task init, plan, apply, ip
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars            # in .gitignore
│
├── ansible/                        # Server configuration (Ansible)
│   ├── Taskfile.yml                # task generate-inventory, play, ping
│   ├── ansible.cfg
│   ├── playbook.yml
│   ├── inventory.yml               # Generated — do not edit (in .gitignore)
│   ├── inventory.yml.j2            # Inventory template (source of truth)
│   ├── .vault_pass                 # Vault password (in .gitignore)
│   ├── group_vars/
│   │   └── all/
│   │       └── vault.yml           # Encrypted secrets (ansible-vault)
│   └── roles/
│       ├── base/                   # apt, ufw, fail2ban
│       ├── users/                  # System users, SSH keys, sudo
│       ├── headscale/              # .deb + systemd + config template
│       ├── k3s/                    # K3s installer
│       └── tailscale/              # Tailscale client → Headscale
│
├── k8s/                            # Kubernetes manifests (GitOps)
│   ├── argocd/
│   │   ├── application.yml                 # CouchDB
│   │   ├── application-sealed-secrets.yml  # Sealed Secrets controller (Helm)
│   │   ├── application-envoy-gateway.yml   # Envoy Gateway (Helm)
│   │   ├── application-gateway-infra.yml   # Gateway API resources
│   │   ├── application-headscale-ui.yml    # Headscale UI
│   ├── infra/
│   │   └── gateway/                # GatewayClass, Gateway, Headscale API proxy
│   └── apps/
│       ├── couchdb/                # Namespace, ConfigMap, SealedSecret, PVC, StatefulSet, Service, HTTPRoute
│       └── headscale-ui/           # Deployment, Service, HTTPRoute
│
├── scripts/                        # Helper scripts
│   ├── colors.sh                   # Shared ANSI color definitions (bash/zsh)
│   └── generate-inventory.py       # Renders inventory.yml from Terraform output
│
└── docs/                           # Documentation (Russian)
    ├── terraform.md                # Infra, remote state, variables
    ├── ansible.md                  # Roles, vault, preauthkey flow
    └── kubernetes.md               # ArgoCD, Sealed Secrets, Envoy Gateway, routes
```

## Conventions

### Language

- **Code, comments, AGENTS.md**: English
- **README.md, user-facing docs**: Russian

### Terraform

- `terraform.tfvars` must NEVER be committed
- Use `Taskfile.yml` in `infra/` for all operations (`task plan`, `task apply`, `task ip`)

### Ansible

- Use `.yml` extension for all YAML files
- `ansible/inventory.yml` is **generated** by `scripts/generate-inventory.py` — never edit manually, edit `inventory.yml.j2` instead
- Role variables with sensible defaults go in `roles/<name>/defaults/main.yml`; project-specific overrides go in `playbook.yml vars:`
- Roles must be idempotent and self-contained (no implicit dependencies on other roles)
- Use FQCN for all modules: `ansible.builtin.*`, `ansible.posix.*`, `community.general.*`
- Secrets are stored in `group_vars/all/vault.yml`, encrypted with `ansible-vault`
- Vault password file: `.vault_pass` (in `.gitignore`), configured via `vault_password_file` in `ansible.cfg`
- Vault variables use the `vault_` prefix: `vault_server_url`, `vault_acme_email`, etc.

### Scripts

- Shared ANSI color definitions for **shell scripts and Taskfiles**: `scripts/colors.sh` — source with `source ../scripts/colors.sh`
- Shared ANSI color definitions for **Python scripts**: define inline as a `_colors()` function that respects the `NO_COLOR` env var (https://no-color.org). Do NOT create a separate `colors.py` unless there are 3+ Python scripts that need it
- Python scripts must use **stdlib only** (no `pip install`) — exception: `jinja2` is acceptable (always present as an Ansible dependency)

### Kubernetes

- Declarative GitOps via ArgoCD
- Secrets encrypted with **Sealed Secrets** (Bitnami) — safe to commit to git, only the cluster can decrypt
- Gateway API via **Envoy Gateway** on port 8443, accessible only through Headscale VPN

### Comments

- Brief (1-2 lines), explain "why" not "what"

## Critical Rules

### Security

- **NEVER** commit API keys (Hetzner), SSH private keys, or passwords
- Kubernetes secrets are encrypted with **Sealed Secrets** — `SealedSecret` manifests are safe to commit, the private key never leaves the cluster
- Envoy Gateway listens on port 8443 only on the Headscale VPN interface — not reachable from the internet
- Sensitive Ansible variables live exclusively in `group_vars/all/vault.yml` (encrypted)
- `.vault_pass` must never be committed — it is the only local secret

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
