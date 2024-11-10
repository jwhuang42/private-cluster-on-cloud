variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "user" {
  description = "The SSH user for accessing the instance"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "vpc_network_name" {
  description = "The name of the VPC network"
  type        = string
  default     = "test-cluster-network"
}

variable "vpc_subnet_name" {
  description = "The name of the subnet"
  type        = string
  default     = "test-cluster-subnet"
}

variable "vpc_subnet_range" {
  description = "The IP range for the subnet"
  type        = string
  default     = "192.168.0.0/24"
}

variable "control_node_name" {
  description = "The name of the control node instance"
  type        = string
  default     = "test-control-node"
}