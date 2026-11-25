variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "tfpipe"
}

variable "github_owner" {
  type    = string
  default = "MuhammadAbraiz"
}

variable "github_owner_id" {
  description = "Numeric ID of the repo owner (GET /repos/OWNER/REPO -> .owner.id)"
  type        = string
  default     = "98274826"
}

variable "github_repo" {
  type    = string
  default = "terraform-aws-pipeline"
}

variable "github_repo_id" {
  description = "Numeric ID of the repo (GET /repos/OWNER/REPO -> .id)"
  type        = string
  default     = "1472314568"
}

variable "create_oidc_provider" {
  description = "Set to false if the account already has the GitHub OIDC provider"
  type        = bool
  default     = false
}

variable "environment" {
  description = "GitHub environment that gates the apply job"
  type        = string
  default     = "production"
}
