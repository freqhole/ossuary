provider "ovh" {
  endpoint           = var.ovh_endpoint
  application_key    = var.ovh_application_key
  application_secret = var.ovh_application_secret
  consumer_key       = var.ovh_consumer_key
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# --- look up flavor and image IDs ---

data "ovh_cloud_project_flavors" "all" {
  service_name = var.ovh_project_id
  region       = var.ovh_region
}

data "ovh_cloud_project_images" "all" {
  service_name = var.ovh_project_id
  region       = var.ovh_region
  os_type      = "linux"
}

locals {
  # find flavor by name (e.g., "b3-8")
  matching_flavors = [for f in data.ovh_cloud_project_flavors.all.flavors : f if f.name == var.instance_flavor]
  flavor = length(local.matching_flavors) > 0 ? local.matching_flavors[0] : null
  # find image by name prefix (e.g., "Debian 12")
  matching_images = [for i in data.ovh_cloud_project_images.all.images : i if can(regex("^${var.instance_image}", i.name))]
  image = length(local.matching_images) > 0 ? local.matching_images[0] : null
}

# --- matrix server instance ---

resource "ovh_cloud_project_instance" "matrix" {
  service_name   = var.ovh_project_id
  name           = "carp-rodeo-matrix"
  region         = var.ovh_region
  billing_period = "hourly"

  boot_from {
    image_id = local.image.id
  }

  flavor {
    flavor_id = local.flavor.id
  }

  ssh_key {
    name = var.ssh_key_name
  }

  network {
    public = true
  }

  user_data = file("${path.module}/cloud-init.yaml")
}

# extract public IPv4 from addresses set
locals {
  matrix_ipv4 = [for addr in ovh_cloud_project_instance.matrix.addresses : addr.ip if addr.version == 4][0]
}

# --- S3 buckets ---

# synapse media storage (avatars, attachments, etc.)
resource "ovh_cloud_project_storage" "synapse_media" {
  service_name = var.ovh_project_id
  region_name  = var.ovh_s3_region
  name         = "carp-rodeo-synapse-media"
}

# rauthy encrypted backups
resource "ovh_cloud_project_storage" "rauthy_backups" {
  service_name = var.ovh_project_id
  region_name  = var.ovh_s3_region
  name         = "carp-rodeo-rauthy-backups"
}

# rauthy user profile pictures
resource "ovh_cloud_project_storage" "rauthy_pictures" {
  service_name = var.ovh_project_id
  region_name  = var.ovh_s3_region
  name         = "carp-rodeo-rauthy-pictures"
}

# --- cloudflare DNS records ---

# synapse API endpoint
resource "cloudflare_record" "synapse" {
  zone_id = var.cloudflare_zone_id
  name    = "synapse"
  content = local.matrix_ipv4
  type    = "A"
  ttl     = 300
  proxied = false
}

# rauthy auth endpoint
resource "cloudflare_record" "auth" {
  zone_id = var.cloudflare_zone_id
  name    = "auth"
  content = local.matrix_ipv4
  type    = "A"
  ttl     = 300
  proxied = false
}

# base domain — needed for .well-known/matrix delegation
resource "cloudflare_record" "root" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  content = local.matrix_ipv4
  type    = "A"
  ttl     = 300
  proxied = false
}

# element web (placeholder — uncomment when ready)
# resource "cloudflare_record" "chat" {
#   zone_id = var.cloudflare_zone_id
#   name    = "chat"
#   content = ovh_cloud_project_instance.matrix.addresses[0].ip
#   type    = "A"
#   ttl     = 300
#   proxied = false
# }

# --- MX + email routing (cloudflare email routing configured in dashboard) ---
# SPF record for outbound email via Resend
resource "cloudflare_record" "spf" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  content = "v=spf1 include:amazonses.com include:_spf.mx.cloudflare.net ~all"
  type    = "TXT"
  ttl     = 300
}

# DMARC
resource "cloudflare_record" "dmarc" {
  zone_id = var.cloudflare_zone_id
  name    = "_dmarc"
  content = "v=DMARC1; p=quarantine; rua=mailto:admin@${var.domain}"
  type    = "TXT"
  ttl     = 300
}
