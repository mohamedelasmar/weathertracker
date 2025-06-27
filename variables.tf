variable "tenancy_ocid" {}
variable "compartment_ocid" {}



variable "project_name" {
  description = "Name of the project (used for resource naming)"
  type        = string
  default     = "weather-tracker"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "bucket_name" {
  description = "Name of the Object Storage bucket"
  type        = string
  default     = ""
}