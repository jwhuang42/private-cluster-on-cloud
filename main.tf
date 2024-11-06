provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}

variable "project" {
  description = "Your GCP project ID"
  default     = "${GCP_PROJECT_ID}"
}

variable "region" {
  description = "The GCP region"
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone"
  default     = "us-central1-a"
}

variable "control_pub_key" {
  description = "The public key of the control node"
  default     = "${CONTROL_KEY_PUB}"
}

data "google_compute_network" "custom_network" {
  name          = "test-cluster-network"
}

data "google_compute_subnetwork" "custom_subnet" {
  name          = "test-cluster-subnet"
  region        = var.region
}

locals {
  instances = [
    {
      name        = "test-node-1"
      internal_ip = "192.168.0.101"
    },
    {
      name        = "test-node-2"
      internal_ip = "192.168.0.102"
    },
    {
      name        = "test-node-3"
      internal_ip = "192.168.0.103"
    },
    # Add more instances as needed
  ]
}

resource "google_compute_instance" "vm_instances" {
  for_each = { for instance in local.instances : instance.name => instance }

  name         = each.value.name
  machine_type = "e2-medium"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "projects/ubuntu-os-cloud/global/images/ubuntu-2204-jammy-v20240927"
    }
  }

  network_interface {
    network    = data.google_compute_network.custom_network.id
    subnetwork = data.google_compute_subnetwork.custom_subnet.id
    network_ip = each.value.internal_ip
  }

  metadata = {
    ssh-keys = "root:${var.control_pub_key}"
  }
}