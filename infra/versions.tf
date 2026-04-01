terraform {
  required_version = ">= 1.5"

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "~> 2.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }

  # remote state in OVH S3 — shared between local dev and CI
  # create the bucket first: OVH Cloud dashboard → Object Storage → Create Container
  # no state locking (OVH S3 doesn't support DynamoDB) — don't run concurrent applies
  backend "s3" {
    bucket                      = "ossuary-tfstate"
    key                         = "carp-rodeo/terraform.tfstate"
    region                      = "us-east-va"
    encrypt                     = true
    endpoints                   = { s3 = "https://s3.us-east-va.perf.cloud.ovh.us" }
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }
}
