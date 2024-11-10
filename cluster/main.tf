provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}

resource "null_resource" "generate_ssh_key" {
  provisioner "local-exec" {
    command = "bash ./cluster-ssh-keygen.sh"
  }

  triggers = {
    ssh_key_exists = fileexists("${pathexpand("~/.ssh/test_cluster_key.pub")}")
  }
}

# Load the public key for use in instance metadata
data "local_file" "ssh_public_key" {
  filename = "${pathexpand("~/.ssh/test_cluster_key.pub")}"
  # Explicit dependency on the SSH key generation step
  depends_on = [null_resource.generate_ssh_key]
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
    ssh-keys = "root:${data.local_file.ssh_public_key.content}"
  }
}

# Generate SSH config file using a shell script
resource "null_resource" "generate_ssh_config" {
  depends_on = [google_compute_instance.vm_instances]

  # Trigger the resource if the instances list or SSH key changes
  triggers = {
    instances_json = jsonencode(local.instances)
    key_exists = fileexists(pathexpand("~/.ssh/test_cluster_key"))
    key_checksum = fileexists(pathexpand("~/.ssh/test_cluster_key")) ? filemd5(pathexpand("~/.ssh/test_cluster_key")) : "missing"
  }

  provisioner "local-exec" {
    command = "bash ./update-cluster-ssh-config.sh ~/.ssh/config ~/.ssh/test_cluster_key '${jsonencode(local.instances)}'"
  }
}