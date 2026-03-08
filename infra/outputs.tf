output "server_ip" {
  description = "Public IP of the server"
  value       = hcloud_server.vps_01.ipv4_address
}

output "server_name" {
  description = "Name of the server"
  value       = hcloud_server.vps_01.name
}

output "server_status" {
  description = "Current status of the server"
  value       = hcloud_server.vps_01.status
}

output "couchdb_domain" {
  description = "FQDN for CouchDB sync endpoint"
  value       = "${var.cloudflare_subdomain}.${var.cloudflare_zone}"
}

output "headscale_domain" {
  description = "FQDN for Headscale VPN control server"
  value       = "vpn.${var.cloudflare_zone}"
}

output "authelia_domain" {
  description = "FQDN for Authelia SSO portal"
  value       = "auth.${var.cloudflare_zone}"
}
