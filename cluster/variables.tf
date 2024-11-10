variable "project" {
  description = "Your GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  default     = "us-central1"
  type        = string
}

variable "zone" {
  description = "The GCP zone"
  default     = "us-central1-a"
  type        = string
}