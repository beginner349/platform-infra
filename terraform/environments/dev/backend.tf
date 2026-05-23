terraform {
  backend "s3" {
    bucket       = "terraform-state-bucket-542776678091-ap-southeast-1-an"
    key          = "terraform/state/platform-infra.tfstate"
    region       = "ap-southeast-1" # Matches your existing configuration [5]
    use_lockfile = true             # Enables native S3 state locking [3]
  }
}
