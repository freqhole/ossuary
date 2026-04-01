# --- OVH Cloud ---

variable "ovh_endpoint" {
  description = "OVH API endpoint"
  default     = "ovh-us"
}

variable "ovh_application_key" {
  description = "OVH API application key"
  type        = string
  sensitive   = true
}

variable "ovh_application_secret" {
  description = "OVH API application secret"
  type        = string
  sensitive   = true
}

variable "ovh_consumer_key" {
  description = "OVH API consumer key"
  type        = string
  sensitive   = true
}

variable "ovh_project_id" {
  description = "OVH Cloud project ID"
  type        = string
}

variable "ovh_region" {
  description = "OVH Cloud region for the instance"
  type        = string
  default     = "US-EAST-LZ-NYC-A"
}

variable "ovh_s3_region" {
  description = "OVH Cloud region for S3 storage (different from compute region)"
  type        = string
  default     = "US-EAST-VA"
}

variable "instance_flavor" {
  description = "OVH instance flavor (size)"
  type        = string
  default     = "b3-8"
}

variable "instance_image" {
  description = "OS image for the instance"
  type        = string
  default     = "Debian 12"
}

variable "ssh_key_name" {
  description = "name of the SSH key registered in OVH Cloud"
  type        = string
}

# --- Cloudflare ---

variable "cloudflare_api_token" {
  description = "Cloudflare API token with DNS edit permissions for carp.rodeo zone"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for carp.rodeo"
  type        = string
}

variable "domain" {
  description = "base domain"
  type        = string
  default     = "carp.rodeo"
}
