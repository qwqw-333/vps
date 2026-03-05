output "server_ip" {
  description = "Public IP of the server"
  value       = hcloud_server.k3s_01.ipv4_address
}

output "server_status" {
  description = "Current status of the server"
  value       = hcloud_server.k3s_01.status
}
