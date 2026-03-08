terraform {
  required_version = ">= 1.5"

  cloud {
    organization = "qwqw-org"
    workspaces {
      name = "hetzner-personal"
    }
  }

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# SSH key from Hetzner
data "hcloud_ssh_key" "default" {
  name = "hetzner-ssh-key"
}

# Create Server
resource "hcloud_server" "vps_01" {
  name        = "vps-01"
  image       = var.image
  server_type = var.server_type
  location    = var.location
  ssh_keys    = [data.hcloud_ssh_key.default.id]

  labels = {
    managed-by = "terraform"
    firewall   = "fw-default"
  }

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  lifecycle {
    ignore_changes = [
      ssh_keys,
    ]
  }
}

# Firewall Rules
resource "hcloud_firewall" "fw_default" {
  name = "fw-default"

  labels = {
    managed-by = "terraform"
  }

  apply_to {
    label_selector = "firewall=fw-default"
  }

  # SSH
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0"]
  }

  # HTTPS (Caddy — Cloudflare proxied traffic)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0"]
  }

  # Everything out
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "any"
    destination_ips = ["0.0.0.0/0"]
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "any"
    destination_ips = ["0.0.0.0/0"]
  }

  rule {
    direction       = "out"
    protocol        = "icmp"
    destination_ips = ["0.0.0.0/0"]
  }
}

# Cloudflare DNS — A-record
data "cloudflare_zone" "main" {
  filter = {
    name = var.cloudflare_zone
  }
}

resource "cloudflare_dns_record" "sync" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = var.cloudflare_subdomain
  content = hcloud_server.vps_01.ipv4_address
  type    = "A"
  proxied = true
  ttl     = 1
}

# Cloudflare DNS — VPN (Headscale)
resource "cloudflare_dns_record" "vpn" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "vpn"
  content = hcloud_server.vps_01.ipv4_address
  type    = "A"
  proxied = true
  ttl     = 1
}

# Cloudflare DNS — Auth (Authelia)
resource "cloudflare_dns_record" "auth" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "auth"
  content = hcloud_server.vps_01.ipv4_address
  type    = "A"
  proxied = true
  ttl     = 1
}
