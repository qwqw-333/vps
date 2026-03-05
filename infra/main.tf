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
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

# SSH key from Hetzner
data "hcloud_ssh_key" "default" {
  name = "hetzner-ssh-key"
}

# Create Server
resource "hcloud_server" "k3s_01" {
  name        = "k3s-01"
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

  # HTTP (Let's Encrypt ACME challenge)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0"]
  }

  # Headscale / HTTPS
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0"]
  }

  # Headscale DERP (STUN)
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "3478"
    source_ips = ["0.0.0.0/0"]
  }

  # Headscale WireGuard
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "41641"
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
