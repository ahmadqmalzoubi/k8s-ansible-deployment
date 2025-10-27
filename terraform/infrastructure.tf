# Get the external network
data "openstack_networking_network_v2" "external" {
  name = var.public_network_name
}

# Create a private network for the Kubernetes cluster
resource "openstack_networking_network_v2" "k8s_network" {
  name           = "${var.cluster_name}-network"
  admin_state_up = "true"
}

# Create subnet for the Kubernetes cluster
resource "openstack_networking_subnet_v2" "k8s_subnet" {
  name            = "${var.cluster_name}-subnet"
  network_id      = openstack_networking_network_v2.k8s_network.id
  cidr            = var.network_cidr
  ip_version      = 4
  dns_nameservers = ["8.8.8.8", "8.8.4.4"]
  
  allocation_pool {
    start = cidrhost(var.network_cidr, 10)
    end   = cidrhost(var.network_cidr, 100)
  }
}

# Create router
resource "openstack_networking_router_v2" "k8s_router" {
  name                = "${var.cluster_name}-router"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.external.id
}

# Attach subnet to router
resource "openstack_networking_router_interface_v2" "k8s_router_interface" {
  router_id = openstack_networking_router_v2.k8s_router.id
  subnet_id = openstack_networking_subnet_v2.k8s_subnet.id
}# SSH Keypair for accessing the VMs
resource "openstack_compute_keypair_v2" "k8s_keypair" {
  name = var.ssh_key_name
}

# Save the private key locally for Ansible
resource "local_file" "private_key" {
  content         = openstack_compute_keypair_v2.k8s_keypair.private_key
  filename        = "${path.module}/../config/k8s-cluster-key.pem"
  file_permission = "0600"
}

# Security group for Kubernetes cluster
resource "openstack_networking_secgroup_v2" "k8s_secgroup" {
  name        = "${var.cluster_name}-secgroup"
  description = "Security group for Kubernetes cluster nodes"
}

# SSH access
resource "openstack_networking_secgroup_rule_v2" "ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# ICMP (ping)
resource "openstack_networking_secgroup_rule_v2" "icmp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# Kubernetes API server (6443)
resource "openstack_networking_secgroup_rule_v2" "k8s_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# etcd (2379-2380)
resource "openstack_networking_secgroup_rule_v2" "etcd" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 2379
  port_range_max    = 2380
  remote_ip_prefix  = "192.168.100.0/24"
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# Kubelet API (10250)
resource "openstack_networking_secgroup_rule_v2" "kubelet" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 10250
  port_range_max    = 10250
  remote_ip_prefix  = "192.168.100.0/24"
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# kube-scheduler (10259)
resource "openstack_networking_secgroup_rule_v2" "kube_scheduler" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 10259
  port_range_max    = 10259
  remote_ip_prefix  = "192.168.100.0/24"
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# kube-controller-manager (10257)
resource "openstack_networking_secgroup_rule_v2" "kube_controller" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 10257
  port_range_max    = 10257
  remote_ip_prefix  = "192.168.100.0/24"
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# NodePort services (30000-32767)
resource "openstack_networking_secgroup_rule_v2" "nodeport" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 30000
  port_range_max    = 32767
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# Cilium health check (4240)
resource "openstack_networking_secgroup_rule_v2" "cilium_health" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 4240
  port_range_max    = 4240
  remote_ip_prefix  = "192.168.100.0/24"
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# Cilium VXLAN (8472)
resource "openstack_networking_secgroup_rule_v2" "cilium_vxlan" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 8472
  port_range_max    = 8472
  remote_ip_prefix  = "192.168.100.0/24"
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# Allow all traffic between nodes in the same security group
resource "openstack_networking_secgroup_rule_v2" "internal" {
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_group_id   = openstack_networking_secgroup_v2.k8s_secgroup.id
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# Master node
resource "openstack_compute_instance_v2" "k8s_master" {
  name            = "${var.cluster_name}-master"
  image_name      = var.image_name
  flavor_name     = var.flavor_master
  key_pair        = openstack_compute_keypair_v2.k8s_keypair.name
  security_groups = [openstack_networking_secgroup_v2.k8s_secgroup.name]

  network {
    uuid = openstack_networking_subnet_v2.k8s_subnet.network_id
  }

  depends_on = [
    openstack_networking_subnet_v2.k8s_subnet,
    openstack_networking_router_interface_v2.k8s_router_interface
  ]

  # Cloud-init configuration for basic setup
  user_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
    ssh_user = var.ssh_user
  }))

  metadata = {
    role = "master"
    cluster = var.cluster_name
  }
}

# Worker nodes
resource "openstack_compute_instance_v2" "k8s_workers" {
  count           = var.worker_count
  name            = "${var.cluster_name}-worker-${count.index + 1}"
  image_name      = var.image_name
  flavor_name     = var.flavor_worker
  key_pair        = openstack_compute_keypair_v2.k8s_keypair.name
  security_groups = [openstack_networking_secgroup_v2.k8s_secgroup.name]

  network {
    uuid = openstack_networking_subnet_v2.k8s_subnet.network_id
  }

  depends_on = [
    openstack_networking_subnet_v2.k8s_subnet,
    openstack_networking_router_interface_v2.k8s_router_interface
  ]

  # Cloud-init configuration for basic setup
  user_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
    ssh_user = var.ssh_user
  }))

  metadata = {
    role = "worker"
    cluster = var.cluster_name
  }
}

# Floating IP for master node
resource "openstack_networking_floatingip_v2" "master_fip" {
  pool = var.public_network_name
}

resource "openstack_compute_floatingip_associate_v2" "master_fip_associate" {
  floating_ip = openstack_networking_floatingip_v2.master_fip.address
  instance_id = openstack_compute_instance_v2.k8s_master.id
}

# Floating IPs for worker nodes
resource "openstack_networking_floatingip_v2" "worker_fips" {
  count = var.worker_count
  pool  = var.public_network_name
}

resource "openstack_compute_floatingip_associate_v2" "worker_fip_associates" {
  count       = var.worker_count
  floating_ip = openstack_networking_floatingip_v2.worker_fips[count.index].address
  instance_id = openstack_compute_instance_v2.k8s_workers[count.index].id
}