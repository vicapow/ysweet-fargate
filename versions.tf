terraform {
  backend "s3" {
    bucket         = "ysweet-terraform-state"
    key            = "ysweet-fargate/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile   = true
  }

  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.1" }
  }
}

provider "aws" {
  region = var.region
}
