terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "series-api-tf-state-bucket"
    key          = "setup"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true

  }
}


provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Environment = terraform.workspace
      Project     = var.project_name
      Owner       = var.owner
      ManagedBy   = "Terraform/setup"
    }
  }

}