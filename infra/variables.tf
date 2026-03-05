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
