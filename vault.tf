# Lookup latest AAP controller AMI from HCP Packer Registry
data "hcp_packer_artifact" "rhel9_aap" {
  bucket_name  = "rhel9-aap"
  platform     = "aws"
  region       = var.aws_region
  channel_name = "latest"
}

# Dedicated KV v2 secrets engine for the AAP demo
resource "vault_mount" "aap_kv" {
  path        = var.kvv2_mount_path
  type        = "kv"
  options     = { version = "2" }
  description = "KV v2 secrets engine for AAP demo"
}
