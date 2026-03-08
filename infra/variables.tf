variable "hcloud_token" {
  description = "Hetzner Cloud API Token"
  type        = string
  sensitive   = true
}

variable "server_type" {
  description = "Type of the server (e.g. cx23)"
  type        = string
  default     = "cx23"
}

variable "location" {
  description = "Data center location (e.g. fsn1)"
  type        = string
  default     = "fsn1"
}

variable "image" {
  description = "OS Image to use"
  type        = string
  default     = "debian-12"
}

variable "cloudflare_api_token" {
  description = "Cloudflare API Token with DNS edit permissions"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone" {
  description = "Cloudflare zone name (domain)"
  type        = string
  default     = "qwqw333.work"
}

variable "cloudflare_subdomain" {
  description = "Subdomain for CouchDB sync endpoint"
  type        = string
  default     = "obsidian"
}
