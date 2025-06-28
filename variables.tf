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

variable "user_ocid" {
  description = "The OCID of the user"
  type        = string
}

variable "fingerprint" {
  description = "The fingerprint of the user's API key"
  type        = string
}

variable "private_key_path" {
  description = "The path to the user's private key file"
  type        = string
}

variable "region" {
  description = "The OCI region"
  type        = string
  default     = "us-ashburn-1"
}

variable "ssh_public_key" {
  description = "SSH public key for worker nodes"
  type        = string
}

variable "node_count" {
  description = "Number of worker nodes per availability domain"
  type        = number
  default     = 1
}

variable "node_shape" {
  description = "Shape of the worker nodes"
  type        = string
  default     = "VM.Standard.E4.Flex"
}

variable "node_ocpus" {
  description = "Number of OCPUs for worker nodes (for flexible shapes)"
  type        = number
  default     = 2
}

variable "node_memory_gb" {
  description = "Memory in GB for worker nodes (for flexible shapes)"
  type        = number
  default     = 16
}

variable "kubernetes_version" {
  description = "Kubernetes version for the cluster"
  type        = string
  default     = "v1.28.2"  # Check latest supported version
}
