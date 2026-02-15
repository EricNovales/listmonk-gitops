terraform {
  backend "s3" {
    bucket = "terraform-state"
    key    = "k3s/infra.tfstate"
    region = "eu-west-1"

    access_key = "test"
    secret_key = "test"

    endpoints = {
      s3 = "http://localstack.local"
    }

    # Evita llamadas a AWS real / STS / IAM
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }
}
