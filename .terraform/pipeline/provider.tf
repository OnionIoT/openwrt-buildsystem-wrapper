provider "aws" {
  region = var.region
}

terraform {
  required_version = ">= 1"
  backend "s3" {
    bucket               = "devops-openwrt-terraform-state"
    key                  = "buildsystem_wrapper_state"
    region               = "us-east-1"
    dynamodb_table       = "devops-openwrt-terraform-lock"
    workspace_key_prefix = "buildsystem_wrapper_state"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.60.0"
    }
  }
}
