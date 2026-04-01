output "matrix_ip" {
  description = "public IPv4 of the matrix server"
  value       = local.matrix_ipv4
}

output "synapse_url" {
  description = "synapse API URL"
  value       = "https://synapse.${var.domain}"
}

output "auth_url" {
  description = "Rauthy auth URL"
  value       = "https://auth.${var.domain}"
}

output "ssh_command" {
  description = "SSH into the matrix server"
  value       = "ssh debian@${local.matrix_ipv4}"
}

output "s3_buckets" {
  description = "S3 bucket names"
  value = {
    synapse_media   = ovh_cloud_project_storage.synapse_media.name
    rauthy_backups  = ovh_cloud_project_storage.rauthy_backups.name
    rauthy_pictures = ovh_cloud_project_storage.rauthy_pictures.name
  }
}

# debug: list available flavors (uncomment when troubleshooting)
# output "available_flavors" {
#   description = "Available instance flavors in this region"
#   value       = [for f in data.ovh_cloud_project_flavors.all.flavors : f.name]
# }

# debug: list available images (uncomment when troubleshooting)
# output "available_images" {
#   description = "Available images in this region"
#   value       = [for i in data.ovh_cloud_project_images.all.images : i.name]
# }
