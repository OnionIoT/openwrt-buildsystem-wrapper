variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Deployment project name: will be used as prefix for resources"
}

variable "deployment_bucket" {
  type        = string
  description = "Deployment Bucket to host the packages and images"
}

variable "repository" {
  type        = string
  description = "Source Github repository containing files and buildspec"
}

variable "stage_vars" {
  description = "Stage Specific Variables"
  type        = map(object({ branch = string }))
}
