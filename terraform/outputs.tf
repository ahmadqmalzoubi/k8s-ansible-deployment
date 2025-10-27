# Outputs for Ansible integration
output "cluster_name" {
  description = "Name of the Kubernetes cluster"
  value       = var.cluster_name
}

output "master_private_ip" {
  description = "Private IP address of the master node"
  value       = openstack_compute_instance_v2.k8s_master.network[0].fixed_ip_v4
}

output "master_public_ip" {
  description = "Public IP address of the master node"
  value       = openstack_networking_floatingip_v2.master_fip.address
}

output "worker_private_ips" {
  description = "Private IP addresses of worker nodes"
  value       = [for instance in openstack_compute_instance_v2.k8s_workers : instance.network[0].fixed_ip_v4]
}

output "worker_public_ips" {
  description = "Public IP addresses of worker nodes"
  value       = [for fip in openstack_networking_floatingip_v2.worker_fips : fip.address]
}

output "ssh_private_key_path" {
  description = "Path to the SSH private key"
  value       = local_file.private_key.filename
}

output "ssh_user" {
  description = "SSH user for connecting to VMs"
  value       = var.ssh_user
}

output "network_cidr" {
  description = "CIDR of the cluster network"
  value       = var.network_cidr
}

# Generate Ansible inventory
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    master_public_ip   = openstack_networking_floatingip_v2.master_fip.address
    master_private_ip  = openstack_compute_instance_v2.k8s_master.network[0].fixed_ip_v4
    worker_public_ips  = [for fip in openstack_networking_floatingip_v2.worker_fips : fip.address]
    worker_private_ips = [for instance in openstack_compute_instance_v2.k8s_workers : instance.network[0].fixed_ip_v4]
    ssh_user          = var.ssh_user
    ssh_key_path      = abspath(local_file.private_key.filename)
  })
  filename = "${path.module}/../inventory-dynamic.yml"
}