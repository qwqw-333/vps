# Ansible

Server configuration: base hardening, SSH user, Docker CE, Caddy reverse proxy, Authelia SSO, CouchDB, and Headscale VPN deployment.

## Roles

| Role | Purpose |
|------|---------|
| **base** | apt upgrade, hostname, UFW (22/443), fail2ban |
| **users** | System user with SSH key and passwordless sudo |
| **docker** | Docker CE + Compose plugin, user added to `docker` group, shared `proxy` network |
| **caddy** | Shared Caddy reverse proxy with Cloudflare Origin Certificate (TLS) |
| **authelia** | Self-hosted SSO/OIDC provider (file users, SQLite storage) |
| **couchdb** | CouchDB Docker Compose stack, single-node cluster init |
| **headscale** | Headscale VPN control server + Headplane web UI (OIDC via Authelia) |

## Commands

```bash
cd ansible

task generate-inventory   # Generate inventory from Terraform output
task ping                 # Verify SSH connectivity
task play                 # Run all roles
task status               # Show all services status on the server
```

A single `task play` does everything: installs Docker, deploys Caddy, Authelia, CouchDB, Headscale, and Headplane.

## Vault

Secrets are stored in `group_vars/all/vault.yml`, encrypted with `ansible-vault`. The vault password lives in `.vault_pass` (excluded from git).

### Required Variables

| Variable | Description |
|----------|-------------|
| `vault_couchdb_user` | CouchDB admin username |
| `vault_couchdb_password` | CouchDB admin password |
| `vault_couchdb_domain` | FQDN (e.g. `obsidian.qwqw333.work`) |
| `vault_origin_cert` | Cloudflare Origin Certificate (PEM, wildcard) |
| `vault_origin_key` | Origin Certificate private key (PEM) |
| `vault_headscale_domain` | Headscale FQDN (e.g. `vpn.qwqw333.work`) |
| `vault_headscale_base_domain` | MagicDNS base domain (must differ from headscale_domain) |
| `vault_headplane_cookie_secret` | 32-char random secret for Headplane sessions |
| `vault_authelia_domain` | Authelia FQDN (e.g. `auth.qwqw333.work`) |
| `vault_authelia_session_secret` | 64-char hex secret for Authelia sessions |
| `vault_authelia_storage_encryption_key` | 64-char hex key for SQLite encryption |
| `vault_authelia_oidc_hmac_secret` | 64-char hex HMAC secret for OIDC |
| `vault_authelia_oidc_jwks_private_key` | RSA 4096-bit private key for OIDC token signing |
| `vault_authelia_headplane_client_secret` | Plaintext OIDC client secret for Headplane |
| `vault_authelia_headplane_client_secret_hash` | pbkdf2-sha512 hash of Headplane client secret |
| `vault_authelia_user` | Authelia username |
| `vault_authelia_user_displayname` | Authelia display name |
| `vault_authelia_user_email` | Authelia user email |
| `vault_authelia_user_password_hash` | argon2id hash of Authelia user password |
| `vault_headplane_headscale_api_key` | Long-lived Headscale API key for Headplane OIDC mode |

### Management

```bash
ansible-vault edit group_vars/all/vault.yml    # Edit secrets
ansible-vault view group_vars/all/vault.yml    # View secrets
ansible-vault rekey group_vars/all/vault.yml   # Change vault password
```

Vault is decrypted automatically during playbook runs via `vault_password_file` in `ansible.cfg`.

## Docker Network Architecture

All services share a single external Docker network `proxy`, created by the `docker` role. Each service runs in its own Docker Compose stack:

| Stack | Directory | Services |
|-------|-----------|----------|
| Caddy | `/opt/caddy/` | Caddy (reverse proxy, port 443) |
| Authelia | `/opt/authelia/` | Authelia (port 127.0.0.1:9091) |
| CouchDB | `/opt/couchdb/` | CouchDB (port 127.0.0.1:5984) |
| Headscale | `/opt/headscale/` | Headscale (port 127.0.0.1:8080), Headplane |

## Caddy (Shared Reverse Proxy)

Deployed to `/opt/caddy/` on the server:

| File | Purpose |
|------|---------|
| `compose.yaml` | Caddy service, connected to `proxy` network |
| `Caddyfile` | Routing for all domains |
| `certs/` | Cloudflare Origin Certificate + private key |

### TLS Model

Caddy uses a **Cloudflare Origin Certificate** (wildcard `*.qwqw333.work`, not Let's Encrypt). This certificate is trusted only by Cloudflare's edge servers, which is sufficient since all traffic is proxied through Cloudflare (`proxied = true` in Terraform).

The certificate is generated manually in the Cloudflare Dashboard (SSL/TLS → Origin Server) and stored in Ansible Vault.

### Routing

- `obsidian.qwqw333.work` → CouchDB (:5984)
- `auth.qwqw333.work` → Authelia (:9091) — with `X-Forwarded-Proto` and `Host` headers for correct OIDC issuer
- `vpn.qwqw333.work /` → Headscale (:8080)
- `vpn.qwqw333.work /admin/*` → Headplane (:3000)

## CouchDB

Deployed to `/opt/couchdb/`:

| File | Purpose |
|------|---------|
| `compose.yaml` | CouchDB service, connected to `proxy` network |
| `local.ini` | CouchDB config: CORS, auth, single-node cluster |

### CouchDB Initialization

On first deploy, the role automatically:
1. Waits for CouchDB to become healthy
2. Runs `finish_cluster` via the `/_cluster_setup` API
3. This creates required system databases (`_users`, `_replicator`, `_global_changes`)

The task is idempotent — subsequent runs skip initialization if the cluster is already set up.

## Headscale VPN

Deployed to `/opt/headscale/`:

| File | Purpose |
|------|---------|
| `compose.yaml` | Headscale + Headplane services, connected to `proxy` network |
| `config/headscale.yaml` | Headscale server configuration |
| `config/headplane.yaml` | Headplane web UI configuration (OIDC via Authelia) |

### ACL Policy

ACL policy is managed via the database (`policy.mode: database` in headscale config). Edit ACLs through the Headplane web UI at `https://vpn.qwqw333.work/admin`.

### Post-deploy steps

1. Generate a long-lived API key for Headplane:

```bash
docker exec headscale headscale apikeys create --expiration 9999d
```

2. Add the key to vault as `vault_headplane_headscale_api_key` and run the playbook again.

3. Generate an argon2id password hash for your Authelia user:

```bash
ssh root@<VPS_IP> "docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password 'your_password'"
```

4. Add the hash to vault as `vault_authelia_user_password_hash` and run the playbook again.

5. Open `https://vpn.qwqw333.work/admin` — click "Sign in with Authelia".

## Authelia SSO

Deployed to `/opt/authelia/`:

| File | Purpose |
|------|---------|
| `compose.yaml` | Authelia service, connected to `proxy` network |
| `config/configuration.yml` | Main Authelia config (OIDC clients, session, storage) |
| `config/users_database.yml` | File-based user database (argon2id hashed passwords) |
| `config/db.sqlite3` | SQLite storage (generated at runtime) |

### OIDC Clients

| Client | Redirect URI | Scopes |
|--------|-------------|--------|
| `headplane` | `https://vpn.qwqw333.work/admin/oidc/callback` | openid, profile, email |

### Generating secret hashes

```bash
# argon2id hash for user password
docker run --rm authelia/authelia:latest \
  authelia crypto hash generate argon2 --password 'your_password'

# pbkdf2-sha512 hash for OIDC client secret
docker run --rm authelia/authelia:latest \
  authelia crypto hash generate pbkdf2 --variant sha512 --password 'your_client_secret'
```

## Configuration Files

- `ansible.cfg` — SSH pipelining, vault password path, inventory location
- `inventory.yml` — **generated** from `inventory.yml.j2` by `scripts/generate-inventory.py` (do not edit)
- `playbook.yml` — role list and project-specific variable overrides
