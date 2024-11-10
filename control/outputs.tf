output "vpc_network" {
  description = "The VPC network name"
  value       = google_compute_network.test_cluster_network.name
}

output "subnet" {
  description = "The subnet name"
  value       = google_compute_subnetwork.test_cluster_subnet.name
}

output "allow_custom_firewall_rule" {
  description = "The custom firewall rule name"
  value       = google_compute_firewall.allow_custom.name
}

output "allow_ssh_firewall_rule" {
  description = "The SSH firewall rule name"
  value       = google_compute_firewall.allow_ssh.name
}

output "control_node_ip" {
  description = "The external IP address of the control node"
  value       = google_compute_instance.control_node.network_interface[0].access_config[0].nat_ip
}