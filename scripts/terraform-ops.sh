#!/bin/bash

# Terraform operations script for Kubernetes cluster
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"
CONFIG_DIR="$SCRIPT_DIR/../config"

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
    echo "Usage: $0 {init|plan|apply|destroy|show|output}"
    echo ""
    echo "Commands:"
    echo "  init     - Initialize Terraform"
    echo "  plan     - Show Terraform execution plan"
    echo "  apply    - Apply Terraform configuration"
    echo "  destroy  - Destroy Terraform-managed infrastructure"
    echo "  show     - Show current Terraform state"
    echo "  output   - Show Terraform outputs"
    echo ""
}

check_credentials() {
    log_info "Checking OpenStack credentials..."
    
    # Check if we can authenticate with OpenStack
    if ! openstack --insecure token issue &>/dev/null; then
        log_error "Cannot authenticate with OpenStack. Please source your openrc file."
        echo "Example: source ~/openrc-learning-admin"
        exit 1
    fi
    
    log_success "OpenStack authentication successful"
}

terraform_init() {
    log_info "Initializing Terraform..."
    cd "$TERRAFORM_DIR"
    
    if terraform init; then
        log_success "Terraform initialized successfully"
    else
        log_error "Terraform initialization failed"
        exit 1
    fi
}

terraform_plan() {
    log_info "Creating Terraform execution plan..."
    cd "$TERRAFORM_DIR"
    
    if terraform plan; then
        log_success "Terraform plan created successfully"
    else
        log_error "Terraform plan failed"
        exit 1
    fi
}

terraform_apply() {
    log_info "Applying Terraform configuration..."
    cd "$TERRAFORM_DIR"
    
    if terraform apply -auto-approve; then
        log_success "Terraform apply completed successfully"
        
        # Show outputs
        log_info "Terraform outputs:"
        terraform output
        
        # Verify inventory file was created
        if [[ -f "$SCRIPT_DIR/../inventory-dynamic.yml" ]]; then
            log_success "Dynamic inventory file created"
        else
            log_warning "Dynamic inventory file not found"
        fi
        
    else
        log_error "Terraform apply failed"
        exit 1
    fi
}

terraform_destroy() {
    log_warning "This will destroy all Terraform-managed infrastructure!"
    read -p "Are you sure? Type 'yes' to confirm: " -r
    
    if [[ $REPLY == "yes" ]]; then
        log_info "Destroying Terraform-managed infrastructure..."
        cd "$TERRAFORM_DIR"
        
        if terraform destroy -auto-approve; then
            log_success "Infrastructure destroyed successfully"
            
            # Clean up generated files
            rm -f "$SCRIPT_DIR/../inventory-dynamic.yml"
            rm -f "$CONFIG_DIR/k8s-cluster-key.pem"
            rm -f "$CONFIG_DIR/k8s-join-command"
            
            log_info "Cleaned up generated files"
        else
            log_error "Terraform destroy failed"
            exit 1
        fi
    else
        log_info "Destroy cancelled"
    fi
}

terraform_show() {
    log_info "Showing Terraform state..."
    cd "$TERRAFORM_DIR"
    terraform show
}

terraform_output() {
    log_info "Showing Terraform outputs..."
    cd "$TERRAFORM_DIR"
    terraform output
}

wait_for_vms() {
    log_info "Waiting for VMs to be ready..."
    
    # Get the master IP from Terraform output
    cd "$TERRAFORM_DIR"
    MASTER_IP=$(terraform output -raw master_public_ip 2>/dev/null || echo "")
    SSH_USER=$(terraform output -raw ssh_user 2>/dev/null || echo "ubuntu")
    SSH_KEY=$(terraform output -raw ssh_private_key_path 2>/dev/null || echo "")
    
    if [[ -z "$MASTER_IP" ]] || [[ -z "$SSH_KEY" ]]; then
        log_error "Could not get VM connection details from Terraform"
        return 1
    fi
    
    log_info "Waiting for SSH connectivity to master ($MASTER_IP)..."
    
    # Wait for SSH to be available (max 10 minutes)
    max_attempts=60
    attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USER@$MASTER_IP" "echo 'SSH connection successful'" &>/dev/null; then
            log_success "SSH connection to master established"
            break
        fi
        
        log_info "Attempt $attempt/$max_attempts - waiting for SSH connectivity..."
        sleep 10
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        log_error "Timeout waiting for SSH connectivity"
        return 1
    fi
    
    # Additional wait for cloud-init to complete
    log_info "Waiting for cloud-init to complete..."
    if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USER@$MASTER_IP" "cloud-init status --wait" &>/dev/null; then
        log_success "Cloud-init completed successfully"
    else
        log_warning "Cloud-init status check failed, but continuing..."
    fi
    
    return 0
}

# Main execution
case "${1:-}" in
    init)
        check_credentials
        terraform_init
        ;;
    plan)
        check_credentials
        terraform_plan
        ;;
    apply)
        check_credentials
        terraform_apply
        wait_for_vms
        ;;
    destroy)
        check_credentials
        terraform_destroy
        ;;
    show)
        terraform_show
        ;;
    output)
        terraform_output
        ;;
    wait)
        wait_for_vms
        ;;
    *)
        show_usage
        exit 1
        ;;
esac