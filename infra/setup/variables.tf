variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-west-2"

}

variable "tf_state_bucket" {
  description = "The name of the S3 bucket to store Terraform state"
  type        = string
  default     = "series-api-tf-state-bucket"

}

variable "dynamodb_table" {
  description = "The name of the DynamoDB table for Terraform state locking"
  type        = string
  default     = "series-api-tf-lock-table"

}

variable "project_name" {
  description = "The name of the project"
  type        = string
  default     = "series-api"

}

variable "owner" {
  description = "The owner of the infrastructure"
  default     = "heshmat"

}

