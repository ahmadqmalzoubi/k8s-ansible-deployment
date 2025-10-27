# Variables for the Kubernetes cluster deployment
variable "cluster_name" {
  description = "Name prefix for the Kubernetes cluster resources"
  type        = string
  default     = "k8s-cluster"
}

variable "image_name" {
  description = "Name of the Ubuntu image to use for VMs"
  type        = string
  default     = "ubuntu-noble"  # From the OpenStack setup
}

variable "flavor_master" {
  description = "Flavor for the master node"
  type        = string
  default     = "my-large"  # Using existing flavor from learning domain
}

variable "flavor_worker" {
  description = "Flavor for the worker nodes"
  type        = string
  default     = "my-large"  # Using existing flavor from learning domain
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "ssh_key_name" {
  description = "Name for the SSH keypair"
  type        = string
  default     = "k8s-cluster-key"
}

variable "public_network_name" {
  description = "Name of the external/public network"
  type        = string
  default     = "public"
}

variable "network_cidr" {
  description = "CIDR for the Kubernetes cluster network"
  type        = string
  default     = "192.168.100.0/24"
}

variable "ssh_user" {
  description = "SSH user for the Ubuntu VMs"
  type        = string
  default     = "ubuntu"
}