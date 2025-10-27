#!/bin/bash

# Kubernetes cluster management script
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"
CONFIG_DIR="$SCRIPT_DIR/config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    echo "Kubernetes Cluster Management Tool"
    echo ""
    echo "Usage: $0 {deploy|destroy|status|ssh-master|ssh-worker|kubeconfig}"
    echo ""
    echo "Commands:"
    echo "  deploy      - Deploy complete Kubernetes cluster (infrastructure + k8s)"
    echo "  destroy     - Destroy the entire cluster and infrastructure"
    echo "  status      - Show cluster status and connection information"
    echo "  ssh-master  - SSH to the master node"
    echo "  ssh-worker  - SSH to worker node (specify number: ssh-worker 1 or 2)"
    echo "  kubeconfig  - Download kubeconfig from master to local machine"
    echo ""
    echo "Prerequisites:"
    echo "  - Source your OpenStack credentials: source ~/openrc-learning-admin"
    echo "  - Ensure Terraform and Ansible are installed"
    echo ""
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check OpenStack authentication
    if ! openstack token issue &>/dev/null; then
        log_error "Cannot authenticate with OpenStack. Please source your openrc file."
        echo "Example: source ~/openrc-learning-admin"
        exit 1
    fi
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform not found. Please install Terraform."
        exit 1
    fi
    
    # Check Ansible
    if ! command -v ansible-playbook &> /dev/null; then
        log_error "Ansible not found. Please install Ansible."
        exit 1
    fi
    
    log_success "All prerequisites satisfied"
}

deploy_cluster() {
    log_info "Starting complete cluster deployment..."
    
    check_prerequisites
    
    cd "$SCRIPT_DIR"
    
    # Run the full stack deployment
    if ansible-playbook deploy-full-stack.yml; then
        log_success "Cluster deployment completed successfully!"
        show_status
    else
        log_error "Cluster deployment failed"
        exit 1
    fi
}

destroy_cluster() {
    log_warning "This will destroy the entire Kubernetes cluster and infrastructure!"
    read -p "Are you sure? Type 'yes' to confirm: " -r
    
    if [[ $REPLY == "yes" ]]; then
        cd "$SCRIPT_DIR"
        scripts/terraform-ops.sh destroy
        log_success "Cluster destroyed successfully"
    else
        log_info "Destroy cancelled"
    fi
}

show_status() {
    cd "$TERRAFORM_DIR"
    
    if ! terraform show &>/dev/null; then
        log_info "No infrastructure found. Use 'deploy' to create a cluster."
        return
    fi
    
    log_info "Cluster Status:"
    echo "======================================"
    
    # Get outputs
    MASTER_IP=$(terraform output -raw master_public_ip 2>/dev/null || echo "N/A")
    WORKER_IPS=($(terraform output -json worker_public_ips 2>/dev/null | jq -r '.[]' || echo "N/A"))
    SSH_USER=$(terraform output -raw ssh_user 2>/dev/null || echo "ubuntu")
    SSH_KEY=$(terraform output -raw ssh_private_key_path 2>/dev/null || echo "N/A")
    
    echo "Master Node:  $MASTER_IP"
    echo "Worker Nodes: ${WORKER_IPS[@]}"
    echo "SSH User:     $SSH_USER"
    echo "SSH Key:      $SSH_KEY"
    echo ""
    
    # Test connectivity if we have the details
    if [[ "$MASTER_IP" != "N/A" ]] && [[ "$SSH_KEY" != "N/A" ]]; then
        if ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USER@$MASTER_IP" "kubectl get nodes" 2>/dev/null; then
            log_success "Cluster is accessible and running"
        else
            log_warning "Cluster infrastructure exists but Kubernetes may not be ready"
        fi
    fi
    
    echo "======================================"
    echo "To SSH to master: $0 ssh-master"
    echo "To get kubeconfig: $0 kubeconfig"
}

ssh_to_master() {
    cd "$TERRAFORM_DIR"
    
    MASTER_IP=$(terraform output -raw master_public_ip 2>/dev/null || echo "")
    SSH_USER=$(terraform output -raw ssh_user 2>/dev/null || echo "ubuntu")
    SSH_KEY=$(terraform output -raw ssh_private_key_path 2>/dev/null || echo "")
    
    if [[ -z "$MASTER_IP" ]] || [[ -z "$SSH_KEY" ]]; then
        log_error "No cluster found or missing connection details"
        exit 1
    fi
    
    log_info "Connecting to master node ($MASTER_IP)..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USER@$MASTER_IP"
}

ssh_to_worker() {
    local worker_num=${1:-1}
    
    cd "$TERRAFORM_DIR"
    
    WORKER_IPS=($(terraform output -json worker_public_ips 2>/dev/null | jq -r '.[]' || echo ""))
    SSH_USER=$(terraform output -raw ssh_user 2>/dev/null || echo "ubuntu")
    SSH_KEY=$(terraform output -raw ssh_private_key_path 2>/dev/null || echo "")
    
    if [[ ${#WORKER_IPS[@]} -eq 0 ]] || [[ -z "$SSH_KEY" ]]; then
        log_error "No cluster found or missing connection details"
        exit 1
    fi
    
    if [[ $worker_num -lt 1 ]] || [[ $worker_num -gt ${#WORKER_IPS[@]} ]]; then
        log_error "Invalid worker number. Available workers: 1-${#WORKER_IPS[@]}"
        exit 1
    fi
    
    local worker_ip=${WORKER_IPS[$((worker_num-1))]}
    log_info "Connecting to worker-$worker_num ($worker_ip)..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USER@$worker_ip"
}

download_kubeconfig() {
    cd "$TERRAFORM_DIR"
    
    MASTER_IP=$(terraform output -raw master_public_ip 2>/dev/null || echo "")
    SSH_USER=$(terraform output -raw ssh_user 2>/dev/null || echo "ubuntu")
    SSH_KEY=$(terraform output -raw ssh_private_key_path 2>/dev/null || echo "")
    
    if [[ -z "$MASTER_IP" ]] || [[ -z "$SSH_KEY" ]]; then
        log_error "No cluster found or missing connection details"
        exit 1
    fi
    
    log_info "Downloading kubeconfig from master..."
    
    # Create local .kube directory if it doesn't exist
    mkdir -p ~/.kube
    
    # Download kubeconfig
    if scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USER@$MASTER_IP:/home/$SSH_USER/.kube/config" ~/.kube/k8s-cluster-config; then
        log_success "Kubeconfig downloaded to ~/.kube/k8s-cluster-config"
        echo ""
        echo "To use this kubeconfig:"
        echo "export KUBECONFIG=~/.kube/k8s-cluster-config"
        echo "kubectl get nodes"
    else
        log_error "Failed to download kubeconfig"
        exit 1
    fi
}

# Main execution
case "${1:-}" in
    deploy)
        deploy_cluster
        ;;
    destroy)
        destroy_cluster
        ;;
    status)
        show_status
        ;;
    ssh-master)
        ssh_to_master
        ;;
    ssh-worker)
        ssh_to_worker "${2:-1}"
        ;;
    kubeconfig)
        download_kubeconfig
        ;;
    *)
        show_usage
        exit 1
        ;;
esac