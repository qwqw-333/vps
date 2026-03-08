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
