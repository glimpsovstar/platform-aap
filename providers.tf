provider "aws" {
  region = var.aws_region
}

provider "acme" {
  server_url = "https://acme-v02.api.letsencrypt.org/directory"
}

provider "vault" {
  # VAULT_ADDR, VAULT_TOKEN, etc.
}

provider "tls" {
  # No configuration needed
}


provider "aap" {
  host                 = local.aap_url
  insecure_skip_verify = true
  timeout              = 300
}

provider "hcp" {
  # Authenticates via HCP_CLIENT_ID and HCP_CLIENT_SECRET environment variables
}
