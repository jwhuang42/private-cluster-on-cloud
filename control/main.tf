provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Generate SSH key pair using a local-exec provisioner
resource "null_resource" "generate_ssh_key" {
  provisioner "local-exec" {
    command = "bash ./control-ssh-keygen.sh"
  }

  triggers = {
    ssh_key_exists = fileexists("${pathexpand("~/.ssh/control_node_key.pub")}")
  }
}

# Load the public key for use in instance metadata
data "local_file" "ssh_public_key" {
  filename = "${pathexpand("~/.ssh/control_node_key.pub")}"
  # Explicit dependency on the SSH key generation step
  depends_on = [null_resource.generate_ssh_key]
}

# VPC Network
resource "google_compute_network" "test_cluster_network" {
  name                    = var.vpc_network_name
  auto_create_subnetworks = false
  mtu                     = 1460
  routing_mode            = "REGIONAL"
}

# Subnet
resource "google_compute_subnetwork" "test_cluster_subnet" {
  name                     = var.vpc_subnet_name
  ip_cidr_range            = var.vpc_subnet_range
  region                   = var.region
  network                  = google_compute_network.test_cluster_network.self_link
  stack_type               = "IPV4_ONLY"
  private_ip_google_access = true
}

# Firewall Rule: Allow all traffic within the subnet
resource "google_compute_firewall" "allow_custom" {
  name    = "${var.vpc_network_name}-allow-custom"
  network = google_compute_network.test_cluster_network.self_link

  description = "Allows connection from any source to any instance on the network using custom protocols."
  direction   = "INGRESS"
  priority    = 65534
  allow {
    protocol = "all"
  }
  source_ranges = [var.vpc_subnet_range]
}

# Firewall Rule: Allow SSH from anywhere
resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.vpc_network_name}-allow-ssh"
  network = google_compute_network.test_cluster_network.self_link

  description = "Allow SSH to the VPC nodes from instances outside the VPC."
  direction   = "INGRESS"
  priority    = 1000
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["allow-ssh"]
}

# Firewall rule: Allow egress traffic (internet access)
resource "google_compute_firewall" "allow_egress_internet" {
  name    = "${var.vpc_network_name}-allow-egress-internet"
  network = google_compute_network.test_cluster_network.self_link

  description = "Allows outbound internet access from any instance on the network."
  direction   = "EGRESS"
  priority    = 65534

  allow {
    protocol = "all"
  }

  # Destination ranges for internet access (0.0.0.0/0 allows all destinations)
  destination_ranges = ["0.0.0.0/0"]
}

# Control Node Instance
resource "google_compute_instance" "control_node" {
  name         = var.control_node_name
  machine_type = "e2-small"
  zone         = var.zone
  tags         = ["allow-ssh"]

  boot_disk {
    initialize_params {
      image  = "projects/ubuntu-os-cloud/global/images/ubuntu-2204-jammy-v20240927"
      size   = 10
      type   = "pd-balanced"
    }
    auto_delete = true
  }

  network_interface {
    network    = google_compute_network.test_cluster_network.self_link
    subnetwork = google_compute_subnetwork.test_cluster_subnet.self_link
    stack_type = "IPV4_ONLY"
    access_config {}
  }

  metadata = {
    ssh-keys = "${var.user}:${data.local_file.ssh_public_key.content}"
  }

  scheduling {
    on_host_maintenance = "MIGRATE"
    provisioning_model  = "STANDARD"
  }

  service_account {
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}

# Update SSH Config with Control Node IP
resource "null_resource" "update_ssh_client_config" {
  depends_on = [google_compute_instance.control_node]

  provisioner "local-exec" {
    command = "bash ./update-ssh-config.sh"
  }
}