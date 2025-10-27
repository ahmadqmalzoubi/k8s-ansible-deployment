#!/bin/bash
# Complete Kubernetes Cluster Deployment Script
# Automates all three deployment steps

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}COMPLETE KUBERNETES CLUSTER DEPLOYMENT${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# Check if OpenStack credentials are sourced
if [ -z "$OS_AUTH_URL" ]; then
    echo -e "${YELLOW}OpenStack credentials not found. Sourcing openrc file...${NC}"
    if [ -f ~/openrc-learning-admin ]; then
        source ~/openrc-learning-admin
        echo -e "${GREEN}✓ OpenStack credentials loaded${NC}"
    else
        echo -e "${YELLOW}Error: ~/openrc-learning-admin not found${NC}"
        echo "Please source your OpenStack credentials first:"
        echo "  source ~/openrc-learning-admin"
        exit 1
    fi
fi

echo ""
echo -e "${BLUE}Step A: Infrastructure Provisioning${NC}"
echo "-------------------------------------"
ansible-playbook step-a-provision-infrastructure.yml || {
    echo -e "${YELLOW}Step A failed. Exiting.${NC}"
    exit 1
}

echo ""
echo -e "${BLUE}Step B: Kubernetes Initialization${NC}"
echo "-------------------------------------"
ansible-playbook -i inventory-dynamic.yml step-b-kubernetes-init.yml || {
    echo -e "${YELLOW}Step B failed. Exiting.${NC}"
    exit 1
}

echo ""
echo -e "${BLUE}Step C: Workers Join and Verification${NC}"
echo "-------------------------------------"
ansible-playbook -i inventory-dynamic.yml step-c-workers-join.yml || {
    echo -e "${YELLOW}Step C failed. Exiting.${NC}"
    exit 1
}

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}🎉 DEPLOYMENT COMPLETED SUCCESSFULLY! 🎉${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""

# Get cluster info
MASTER_IP=$(cd terraform && terraform output -raw master_public_ip 2>/dev/null)
WORKER_IPS=$(cd terraform && terraform output -json worker_public_ips 2>/dev/null | jq -r '.[]' | tr '\n' ' ')

echo "Cluster Information:"
echo "-------------------"
echo "Master IP: $MASTER_IP"
echo "Worker IPs: $WORKER_IPS"
echo "SSH Key: config/k8s-cluster-key.pem"
echo ""
echo "Quick Commands:"
echo "  SSH to master: ssh -i config/k8s-cluster-key.pem ubuntu@$MASTER_IP"
echo "  Get status: ./cluster-manager.sh status"
echo "  Download kubeconfig: ./cluster-manager.sh kubeconfig"
echo ""

# Save deployment info
cat > DEPLOYMENT-INFO.txt <<EOF
Kubernetes Cluster Deployment
==============================
Deployed: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Master: $MASTER_IP
Workers: $WORKER_IPS

Access:
ssh -i config/k8s-cluster-key.pem ubuntu@$MASTER_IP
EOF

echo "Deployment info saved to DEPLOYMENT-INFO.txt"
