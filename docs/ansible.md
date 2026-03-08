# Ansible

Server configuration: base hardening, SSH user, Docker CE, and CouchDB + Caddy deployment.

## Roles

| Role | Purpose |
|------|---------|
| **base** | apt upgrade, hostname, UFW (22/443), fail2ban |
| **users** | System user with SSH key and passwordless sudo |
| **docker** | Docker CE + Compose plugin, user added to `docker` group |
| **couchdb** | Docker Compose stack: Caddy (Origin Certificate TLS) + CouchDB, single-node cluster init |

## Commands

```bash
cd ansible

task generate-inventory   # Generate inventory from Terraform output
task ping                 # Verify SSH connectivity
task play                 # Run all roles
task status               # Show CouchDB stack status on the server
```

A single `task play` does everything: installs Docker, deploys CouchDB and Caddy with TLS, and initializes the CouchDB cluster.

## Vault

Secrets are stored in `group_vars/all/vault.yml`, encrypted with `ansible-vault`. The vault password lives in `.vault_pass` (excluded from git).

### Required Variables

| Variable | Description |
|----------|-------------|
| `vault_couchdb_user` | CouchDB admin username |
| `vault_couchdb_password` | CouchDB admin password |
| `vault_couchdb_domain` | FQDN (e.g. `obsidian.qwqw333.work`) |
| `vault_origin_cert` | Cloudflare Origin Certificate (PEM, multiline) |
| `vault_origin_key` | Origin Certificate private key (PEM, multiline) |

### Management

```bash
ansible-vault edit group_vars/all/vault.yml    # Edit secrets
ansible-vault view group_vars/all/vault.yml    # View secrets
ansible-vault rekey group_vars/all/vault.yml   # Change vault password
```

Vault is decrypted automatically during playbook runs via `vault_password_file` in `ansible.cfg`.

## CouchDB + Caddy Stack

Deployed to `/opt/couchdb/` on the server via Docker Compose:

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Caddy and CouchDB services, internal network |
| `Caddyfile` | Reverse proxy: `domain:443` → `couchdb:5984` |
| `local.ini` | CouchDB config: CORS, auth, single-node cluster |
| `certs/` | Cloudflare Origin Certificate + private key |

### TLS Model

Caddy uses a **Cloudflare Origin Certificate** (not Let's Encrypt). This certificate is trusted only by Cloudflare's edge servers, which is sufficient since all traffic is proxied through Cloudflare (`proxied = true` in Terraform).

The certificate is generated manually in the Cloudflare Dashboard (SSL/TLS → Origin Server) and stored in Ansible Vault.

### CouchDB Initialization

On first deploy, the role automatically:
1. Waits for CouchDB to become healthy
2. Runs `finish_cluster` via the `/_cluster_setup` API
3. This creates required system databases (`_users`, `_replicator`, `_global_changes`)

The task is idempotent — subsequent runs skip initialization if the cluster is already set up.

### Network

- **Caddy** listens on `0.0.0.0:443` (external) — serves HTTPS
- **CouchDB** listens on `127.0.0.1:5984` (localhost only) — for local debugging and Ansible init
- CouchDB is also reachable from Caddy via Docker's internal network

## Configuration Files

- `ansible.cfg` — SSH pipelining, vault password path, inventory location
- `inventory.yml` — **generated** from `inventory.yml.j2` by `scripts/generate-inventory.py` (do not edit)
- `playbook.yml` — role list and project-specific variable overrides
