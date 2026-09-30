terraform {
  # 1.11+: ephemeral resources and write-only attributes (the superuser password never
  # touches state); S3 native state locking (use_lockfile) needs 1.10+.
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  # Partial configuration: bucket/key/region come from backend.hcl (local) or -backend-config
  # flags (CI), so the same code can target any account. See README.
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}
