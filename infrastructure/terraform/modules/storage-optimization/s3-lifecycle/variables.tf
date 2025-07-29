# Variables for S3 Lifecycle Submodule

variable "buckets" {
  description = "Map of S3 buckets to configure"
  type        = map(any)
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "enable_intelligent_tiering" {
  description = "Enable intelligent tiering"
  type        = bool
}

variable "enable_inventory" {
  description = "Enable S3 inventory"
  type        = bool
}

variable "enable_storage_lens" {
  description = "Enable Storage Lens"
  type        = bool
}

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
}