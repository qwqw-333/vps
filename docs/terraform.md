# Terraform

Infrastructure provisioning on Hetzner Cloud with Cloudflare DNS management. Remote state is stored in HCP Terraform (Terraform Cloud).

## Structure

```
infra/
├── main.tf           # Providers, backend, server, firewall, Cloudflare DNS
├── variables.tf      # Input variables
├── outputs.tf        # Output values
├── Taskfile.yml      # task plan, apply, ip
└── terraform.tfvars  # Local overrides (in .gitignore, not committed)
```

## Resources

| Resource | Name | Description |
|----------|------|-------------|
| `hcloud_server` | `vps-01` | Debian 12, cx23, fsn1 datacenter |
| `hcloud_firewall` | `fw-default` | Inbound: 22/tcp (SSH), 443/tcp (HTTPS). Applied via label selector |
| `cloudflare_dns_record` | `sync` | Proxied A-record → server IP |

## Remote State — HCP Terraform

State is stored in [HCP Terraform](https://app.terraform.io) (organization `qwqw-org`, workspace `hetzner-personal`).

- **CLI-driven workflow** — commands run locally, execution happens remotely
- No local `*.tfstate` files

## Variables

| Variable | Source | Description |
|----------|--------|-------------|
| `hcloud_token` | HCP Terraform (sensitive) | Hetzner Cloud API token |
| `cloudflare_api_token` | HCP Terraform (sensitive) | Cloudflare API token (DNS edit) |
| `server_type` | Default: `cx23` | Server type |
| `location` | Default: `fsn1` | Datacenter location |
| `image` | Default: `debian-12` | OS image |
| `cloudflare_zone` | Default: `qwqw333.work` | Cloudflare DNS zone |
| `cloudflare_subdomain` | Default: `obsidian` | Subdomain for CouchDB endpoint |

> A local `terraform.tfvars` overrides HCP Terraform variables. Use it only for temporary experiments.

## Outputs

| Output | Description |
|--------|-------------|
| `server_ip` | Public IPv4 address |
| `server_name` | Server hostname |
| `server_status` | Current server status |
| `couchdb_domain` | FQDN for CouchDB (e.g. `obsidian.qwqw333.work`) |

## Cloudflare DNS

The Cloudflare provider manages the DNS A-record automatically on `terraform apply`.

- **Proxied mode** (`proxied = true`) — traffic goes through Cloudflare's edge network
- Caddy uses a Cloudflare Origin Certificate for the Cloudflare ↔ origin connection
- On server recreation, the DNS record updates automatically with the new IP

## Initial Setup

```bash
# 1. Install Terraform
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# 2. Authenticate with HCP Terraform
terraform login

# 3. Initialize (downloads Hetzner + Cloudflare providers)
cd infra/
terraform init
```

## Commands

```bash
task plan       # Preview changes
task apply      # Apply changes
terraform output  # Show outputs
```

## Security

- `terraform.tfvars` is in `.gitignore` — never committed
- `hcloud_token` and `cloudflare_api_token` are stored exclusively in HCP Terraform as sensitive variables
- No secrets in Terraform files or state (state is remote and encrypted by HCP)
