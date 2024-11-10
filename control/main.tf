provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Generate SSH key pair using a local-exec provisioner
resource "null_resource" "generate_ssh_key" {
  provisioner "local-exec" {
    command = <<EOF
      # Remove existing key files if they exist
      rm -f ~/.ssh/test_cluster_key ~/.ssh/test_cluster_key.pub

      # Generate SSH key for passwordless access
      ssh-keygen -t ecdsa -b 521 -f ~/.ssh/test_cluster_key -N "" -q
    EOF
  }
}

# Load the public key for use in instance metadata
data "local_file" "ssh_public_key" {
  filename = "${pathexpand("~/.ssh/test_cluster_key.pub")}"
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
resource "null_resource" "update_ssh_config" {
  depends_on = [google_compute_instance.control_node]

  provisioner "local-exec" {
    command = <<EOF
      CONTROL_NODE_PUBLIC_IP="$(gcloud compute instances describe ${var.control_node_name} --zone=${var.zone} --format='get(networkInterfaces[0].accessConfigs[0].natIP)')"
      SSH_KEY="$HOME/.ssh/test_cluster_key"
      SSH_CONFIG="$HOME/.ssh/config"

      # Ensure the .ssh directory and config file exist
      mkdir -p "$HOME/.ssh"
      chmod 700 "$HOME/.ssh"
      touch "$SSH_CONFIG"
      chmod 600 "$SSH_CONFIG"

      # Backup existing SSH config file
      if [[ -f "$SSH_CONFIG" ]]; then
          cp "$SSH_CONFIG" "$SSH_CONFIG.bak"
      fi

      # Clean up the existing SSH config file
      > "$SSH_CONFIG"

      # Append the new Host section
      echo "Host ${var.control_node_name}
    HostName $CONTROL_NODE_PUBLIC_IP
    User ${var.user}
    IdentityFile $SSH_KEY
    BatchMode yes
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null" >> "$SSH_CONFIG"

      cat "$SSH_CONFIG"
    EOF
  }
}

# Copy Files and Run Startup Script on Control Node
resource "null_resource" "copy_and_execute_script" {
  depends_on = [null_resource.update_ssh_config]

  provisioner "local-exec" {
    command = <<EOF
      SCRIPT_DIR="$(pwd)"
      scp -p -F $HOME/.ssh/config "$SCRIPT_DIR/main.tf" "$SCRIPT_DIR/control-startup.sh" ${var.control_node_name}:~
      ssh -F $HOME/.ssh/config ${var.control_node_name} 'bash ~/control-startup.sh'
    EOF
  }
}