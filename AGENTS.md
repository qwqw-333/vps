# AGENTS.md - AI Agent Guide

## Project Purpose

This repository contains Infrastructure as Code (IaC) and configuration for a self-hosted Obsidian sync server deployed on Hetzner Cloud.

### Key Components:
- **Hetzner Cloud** (cx23 VM)
- **Headscale** (Native VPN layer)
- **K3s** (Kubernetes)
- **ArgoCD** (GitOps)
- **CouchDB** (Database for LiveSync)

## Project Structure

```
vps/
├── infra/                       # Terraform (Server provisioning)
│   └── Taskfile.yml             # Task runner for Terraform commands
├── ansible/                     # Server configuration rules
│   ├── ansible.cfg              # Ansible configuration
│   ├── Taskfile.yml             # Task runner: inventory, play, ping
│   ├── inventory.yml            # Generated — do not edit manually (in .gitignore)
│   ├── inventory.yml.j2         # Inventory template (source of truth)
│   ├── playbook.yml
│   └── roles/
│       ├── base/                # apt, ufw, fail2ban
│       ├── headscale/           # .deb + systemd + config
│       ├── k3s/                 # K3s installer
│       └── users/               # System users, SSH keys, sudo
├── k8s/                         # Kubernetes manifests
│   ├── argocd/
│   └── apps/
└── scripts/                     # Helper scripts
    ├── colors.sh                # Shared ANSI color definitions (bash/zsh)
    ├── generate-inventory.py    # Generates ansible/inventory.yml from terraform output
    └── setup-devices.sh         # Register devices with Headscale
```

## Conventions & Standards

- **Terraform**:
  - `terraform.tfvars` must NEVER be committed.
  - Keep resources simple and modular.
  - Use `Taskfile.yml` in `infra/` for common operations (`task plan`, `task apply`, `task ip`).
- **Scripts**:
  - Shared ANSI color definitions for **shell scripts and Taskfiles**: `scripts/colors.sh` — source it with `source ../scripts/colors.sh`.
  - Shared ANSI color definitions for **Python scripts**: define inline as a `_colors()` function that respects the `NO_COLOR` env var (https://no-color.org). Do NOT create a separate `colors.py` unless there are 3+ Python scripts that need it — that would be overengineering.
  - Python scripts must use **stdlib only** (no `pip install`) — with one exception: `jinja2` is acceptable because it is always present as an Ansible dependency. Use it for rendering `.j2` templates.
- **Ansible**:
  - Use `.yml` extension for all YAML files.
  - `ansible/inventory.yml` is **generated** by `scripts/generate-inventory.py` — never edit it manually, edit `ansible/inventory.yml.j2` instead.
  - Role variables with sensible defaults go in `roles/<name>/defaults/main.yml`. Project-specific overrides go in `playbook.yml vars:`.
  - Roles must be idempotent and self-contained (no implicit dependencies on other roles).
  - Use FQCN for all modules: `ansible.builtin.*`, `ansible.posix.*`, `community.general.*`.
- **Kubernetes**:
  - Declarative GitOps via ArgoCD.
  - Secrets should be templated and populated via SOPS or Kubernetes Secrets externally.
- **Commits / Docs**: Russian language for user documentation (README.md), English for code and AI instructions.

## Security Reminders

- **NEVER** commit API keys (Hetzner), SSH keys, or passwords.
- Ensure CouchDB binds to `0.0.0.0` but only within the K3s/Headscale network layer.

---
**Last updated**: $(date)
