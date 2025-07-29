variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "layer_source_dir" {
  description = "Source directory for Lambda layers"
  type        = string
  default     = ""
}

variable "python_runtime" {
  description = "Python runtime version"
  type        = string
  default     = "python3.9"
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}