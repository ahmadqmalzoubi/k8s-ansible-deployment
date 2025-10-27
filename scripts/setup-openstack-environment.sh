#!/bin/bash
#
# OpenStack Environment Setup Script
# Run this after restoring OpenStack to fresh snapshot
# This recreates: domain, project, users, network, image, flavor
#

set -e

echo "=========================================="
echo "OpenStack Environment Setup"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}[INFO]${NC} Creating domain 'learning'..."
openstack domain create learning --description "Learning Domain" --insecure || echo "Domain may already exist"

echo -e "${BLUE}[INFO]${NC} Creating project 'learning-project' in learning domain..."
openstack project create learning-project \
  --domain learning \
  --description "Learning Project" \
  --insecure || echo "Project may already exist"

echo -e "${BLUE}[INFO]${NC} Creating user 'learning-admin' in learning domain..."
openstack user create learning-admin \
  --domain learning \
  --project learning-project \
  --password DomainAdmin123! \
  --insecure || echo "User may already exist"

echo -e "${BLUE}[INFO]${NC} Assigning admin role to learning-admin..."
openstack role add --user learning-admin \
  --project learning-project \
  --user-domain learning \
  --project-domain learning \
  admin \
  --insecure

echo -e "${BLUE}[INFO]${NC} Creating external network 'public'..."
openstack network create public \
  --external \
  --provider-network-type flat \
  --provider-physical-network physnet1 \
  --insecure || echo "Network may already exist"

echo -e "${BLUE}[INFO]${NC} Creating subnet for public network..."
openstack subnet create public-subnet \
  --network public \
  --subnet-range 172.29.248.0/22 \
  --allocation-pool start=172.29.249.100,end=172.29.249.254 \
  --gateway 172.29.248.1 \
  --dns-nameserver 8.8.8.8 \
  --insecure || echo "Subnet may already exist"

echo -e "${BLUE}[INFO]${NC} Downloading Ubuntu Noble image..."
if [ ! -f ~/ubuntu-24.04-server-cloudimg-amd64.img ]; then
  wget -O ~/ubuntu-24.04-server-cloudimg-amd64.img \
    https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
fi

echo -e "${BLUE}[INFO]${NC} Uploading image to Glance as learning-admin..."
# Switch to learning-admin credentials
cat > ~/openrc-learning-admin << 'EOF'
export OS_AUTH_URL=https://172.16.1.4:5000/v3
export OS_PROJECT_NAME=learning-project
export OS_USERNAME=learning-admin
export OS_PASSWORD=DomainAdmin123!
export OS_USER_DOMAIN_NAME=learning
export OS_PROJECT_DOMAIN_NAME=learning
export OS_IDENTITY_API_VERSION=3
export OS_INSECURE=true
EOF

source ~/openrc-learning-admin

openstack image create ubuntu-noble \
  --file ~/ubuntu-24.04-server-cloudimg-amd64.img \
  --disk-format qcow2 \
  --container-format bare \
  --private \
  --insecure || echo "Image may already exist"

echo -e "${BLUE}[INFO]${NC} Creating flavor 'my-large' (2 vCPU, 4GB RAM, 8GB disk)..."
openstack flavor create my-large \
  --vcpus 2 \
  --ram 4096 \
  --disk 8 \
  --insecure || echo "Flavor may already exist"

echo ""
echo -e "${BLUE}=========================================="
echo "Applying Networking Fixes"
echo "==========================================${NC}"
echo ""

echo -e "${BLUE}[INFO]${NC} Checking current NAT rules..."
if sudo iptables -t nat -C POSTROUTING -s 172.29.248.0/22 ! -d 172.29.248.0/22 -j MASQUERADE 2>/dev/null; then
    echo -e "${GREEN}[OK]${NC} NAT rule already exists"
else
    echo -e "${BLUE}[INFO]${NC} Adding NAT rule for external connectivity..."
    sudo iptables -t nat -A POSTROUTING -s 172.29.248.0/22 ! -d 172.29.248.0/22 -j MASQUERADE
    echo -e "${GREEN}[SUCCESS]${NC} NAT rule added"
fi

echo -e "${BLUE}[INFO]${NC} Making NAT rules persistent..."

# Install iptables-persistent if not already installed
if ! dpkg -l | grep -q iptables-persistent; then
    echo -e "${BLUE}[INFO]${NC} Installing iptables-persistent..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
    echo -e "${GREEN}[SUCCESS]${NC} iptables-persistent installed"
else
    echo -e "${GREEN}[OK]${NC} iptables-persistent already installed"
fi

# Save current rules
echo -e "${BLUE}[INFO]${NC} Saving iptables rules..."
sudo netfilter-persistent save
echo -e "${GREEN}[SUCCESS]${NC} Rules saved to /etc/iptables/rules.v4"

# Create startup script as backup
echo -e "${BLUE}[INFO]${NC} Creating backup startup script..."
sudo tee /etc/rc.local > /dev/null << 'RCEOF'
#!/bin/bash
# Ensure OpenStack external network NAT is configured
sleep 30  # Wait for network services
if ! iptables -t nat -C POSTROUTING -s 172.29.248.0/22 ! -d 172.29.248.0/22 -j MASQUERADE 2>/dev/null; then
    iptables -t nat -A POSTROUTING -s 172.29.248.0/22 ! -d 172.29.248.0/22 -j MASQUERADE
fi
exit 0
RCEOF

sudo chmod +x /etc/rc.local
echo -e "${GREEN}[SUCCESS]${NC} Backup startup script created"

echo ""
echo -e "${GREEN}=========================================="
echo "✅ OpenStack Environment Setup Complete!"
echo "==========================================${NC}"
echo ""
echo "Domain: learning"
echo "Project: learning-project"
echo "User: learning-admin / DomainAdmin123!"
echo "Network: public (172.29.248.0/22)"
echo "Image: ubuntu-noble"
echo "Flavor: my-large (2vCPU, 4GB RAM, 8GB disk)"
echo ""
echo "Networking fixes applied:"
echo "  ✅ NAT rule for external connectivity"
echo "  ✅ iptables-persistent installed"
echo "  ✅ Rules persist across reboots"
echo ""
echo "Credentials saved to: ~/openrc-learning-admin"
echo ""
echo -e "${BLUE}[NEXT STEP]${NC} You can now run the Kubernetes deployment:"
echo "  cd /home/ahmad/k8s-automation"
echo "  source ~/openrc-learning-admin"
echo "  ./deploy-complete.sh"
echo ""
