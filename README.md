# Kubernetes Cluster Automation on OpenStack

**Complete automation for deploying production-ready Kubernetes clusters using Terraform and Ansible.**

Deploy a 3-node Kubernetes cluster (1 master + 2 workers) with Cilium CNI in ~15 minutes!

---

# Automation Workflow Documentation

## 1. AUTOMATION ENTRY POINT

### Main Entry Point: `deploy-complete.sh`

**Single command deployment:**
```bash
./deploy-complete.sh
```

This script orchestrates the entire deployment in 3 sequential steps:
- Automatically sources OpenStack credentials if needed
- Executes Step A (Infrastructure)
- Executes Step B (Kubernetes Init)
- Executes Step C (Workers Join)
- Displays cluster information and saves deployment details

**Total deployment time: 10-15 minutes**

---

## 2. DETAILED EXECUTION FLOW

### 📊 High-Level Flow

```
deploy-complete.sh
    ↓
    ├─→ Step A: step-a-provision-infrastructure.yml
    │       ↓
    │       └─→ scripts/terraform-ops.sh (init/plan/apply)
    │               ↓
    │               └─→ Terraform files:
    │                   ├─ provider.tf
    │                   ├─ variables.tf
    │                   ├─ infrastructure.tf (MERGED: network+security+compute)
    │                   ├─ outputs.tf
    │                   ├─ cloud-init.yaml
    │                   └─ inventory.tpl
    │                       ↓
    │                       Generates: inventory-dynamic.yml & k8s-cluster-key.pem
    ↓
    ├─→ Step B: step-b-kubernetes-init.yml
    │       ↓
    │       ├─→ Phase 1: Common Setup (all nodes)
    │       │   - Disable swap + reboot
    │       │   - Load kernel modules
    │       │   - Install containerd
    │       │   - Install Kubernetes components
    │       │   - Configure /etc/hosts
    │       ↓
    │       ├─→ Phase 2: playbooks/master-init.yml
    │       │   - Generate kubeadm config from template
    │       │   - Run kubeadm init
    │       │   - Setup kubeconfig
    │       │   - Generate join command
    │       ↓
    │       └─→ Phase 3: playbooks/install-cilium.yml
    │           - Install Cilium CLI
    │           - Deploy Cilium v1.16.4
    │           - Wait for Cilium ready
    ↓
    └─→ Step C: step-c-workers-join.yml
            ↓
            ├─→ Phase 1: playbooks/workers-join.yml
            │   - Retrieve join command from master
            │   - Join workers to cluster
            ↓
            ├─→ Phase 2: Wait for cluster readiness
            │   - All nodes Ready (10m timeout)
            │   - Cilium DaemonSet rollout (10m timeout)
            ↓
            └─→ Phase 3: playbooks/verify-cluster.yml
                - Verify nodes Ready
                - Verify pods Running
                - Check Cilium status
                - Display summary
```

---

## 3. FILE-BY-FILE EXPLANATION (Execution Order)

### 🎯 Entry Point

#### `deploy-complete.sh`
**Purpose:** Main orchestration script  
**What it does:**
- Checks for OpenStack credentials
- Calls 3 step playbooks sequentially
- Displays cluster information
- Saves deployment info to file

**Exit on error:** Yes (set -e)  
**Calls:** step-a, step-b, step-c playbooks

---

### 📦 STEP A: Infrastructure (Terraform)

#### `step-a-provision-infrastructure.yml`
**Purpose:** Ansible wrapper for Terraform operations  
**What it does:**
1. Validates OpenStack authentication
2. Calls `terraform-ops.sh init`
3. Calls `terraform-ops.sh plan`
4. Pauses for confirmation
5. Calls `terraform-ops.sh apply`
6. Verifies inventory and SSH key generated
7. Tests SSH connectivity (non-blocking)
8. Checks/adds route to floating IP network

**Dependencies:** OpenStack credentials sourced  
**Generates:** inventory-dynamic.yml, config/k8s-cluster-key.pem

---

#### `scripts/terraform-ops.sh`
**Purpose:** Terraform operations wrapper  
**What it does:**
- `init`: Initialize Terraform
- `plan`: Show execution plan
- `apply`: Apply configuration with auto-approve
- `destroy`: Destroy infrastructure with confirmation
- `show`: Display current state
- `output`: Display outputs
- `wait`: Wait for VMs and cloud-init completion

**Key feature:** Validates OpenStack auth before each operation

---

#### Terraform Files (executed by terraform-ops.sh):

**`terraform/provider.tf`**
- Configures OpenStack provider
- Sets `insecure = true` for self-signed certs
- Uses `endpoint_type = "public"`
- Reads credentials from environment variables

**`terraform/variables.tf`**
- Defines all configurable parameters:
  - `cluster_name` = "k8s-cluster"
  - `image_name` = "ubuntu-noble"
  - `flavor_master` = "my-large" (2 vCPU, 4GB RAM, 8GB disk)
  - `flavor_worker` = "my-large"
  - `worker_count` = 2
  - `network_cidr` = "192.168.100.0/24"
  - `public_network_name` = "public"

**`terraform/infrastructure.tf`** (MERGED FILE)
- **Network Resources:**
  - `openstack_networking_network_v2.k8s_network` - Private network
  - `openstack_networking_subnet_v2.k8s_subnet` - Subnet with DNS
  - `openstack_networking_router_v2.k8s_router` - Router
  - `openstack_networking_router_interface_v2` - Router interface

- **Security Resources:**
  - `openstack_compute_keypair_v2.k8s_keypair` - SSH keypair
  - `local_file.private_key` - Save private key to config/
  - `openstack_networking_secgroup_v2.k8s_secgroup` - Security group
  - 13x `openstack_networking_secgroup_rule_v2.*` - Security rules:
    - SSH (22)
    - ICMP (ping)
    - K8s API (6443)
    - etcd (2379-2380)
    - Kubelet (10250)
    - kube-scheduler (10259)
    - kube-controller-manager (10257)
    - NodePort services (30000-32767)
    - Cilium health (4240)
    - Cilium VXLAN (8472)
    - Internal cluster traffic (all)

- **Compute Resources:**
  - `openstack_compute_instance_v2.k8s_master` - Master VM
  - `openstack_compute_instance_v2.k8s_workers[2]` - Worker VMs (count=2)
  - `openstack_networking_floatingip_v2.master_fip` - Master floating IP
  - `openstack_networking_floatingip_v2.worker_fips[2]` - Worker floating IPs
  - `openstack_compute_floatingip_associate_v2.*` - FIP associations

**`terraform/outputs.tf`**
- Outputs all IPs (public/private)
- Outputs SSH key path
- **Generates dynamic inventory:** `local_file.ansible_inventory`
  - Uses `inventory.tpl` template
  - Creates `inventory-dynamic.yml` in project root
  - Uses `abspath()` for SSH key path

**`terraform/cloud-init.yaml`**
- Basic VM initialization
- Updates packages
- Installs basic utilities (curl, wget, git, unzip, htop)
- Creates ubuntu user with sudo access
- Disables UFW firewall

**`terraform/inventory.tpl`**
- Jinja2 template for Ansible inventory
- Dynamic host generation based on worker count
- Includes SSH settings and private IPs

**Total resources created: 28**

---

### ⚙️ STEP B: Kubernetes Initialization

#### `step-b-kubernetes-init.yml`
**Purpose:** Initialize Kubernetes on all nodes  
**What it does:**

**Phase 1: Common Setup (runs on all nodes)**
- Disable swap:
  - `swapoff -a`
  - Remove swap from fstab
  - Delete swap file
  - **Reboot system**
  
- Load kernel modules:
  - overlay
  - br_netfilter
  - Create persistent config in /etc/modules-load.d/
  
- Configure sysctl:
  - net.bridge.bridge-nf-call-iptables = 1
  - net.ipv4.ip_forward = 1
  - Apply settings

- Install containerd:
  - Add Docker GPG key
  - Add Docker repository
  - Install containerd.io package
  - Configure with SystemdCgroup = true
  - Restart containerd

- Install Kubernetes:
  - Add Kubernetes apt key
  - Add Kubernetes repository (v1.33)
  - Install kubeadm, kubelet, kubectl
  - Hold packages from auto-update
  - Enable kubelet service

- Update /etc/hosts:
  - Add all cluster nodes

**Phase 2: Import playbooks/master-init.yml**

**Phase 3: Import playbooks/install-cilium.yml**

**Phase 4: Final checks**
- Wait for API server readiness
- Display node status

**Duration:** ~5-8 minutes (includes reboot)

---

#### `playbooks/master-init.yml`
**Purpose:** Initialize Kubernetes master node  
**What it does:**
1. Generate kubeadm config from `config/kubeadm-config.yaml.j2` template
2. Run `kubeadm init --config /tmp/kubeadm-config.yaml`
3. Create .kube directory for ubuntu user
4. Copy admin.conf to user's kubeconfig
5. Generate join command: `kubeadm token create --print-join-command`
6. Save join command to `config/k8s-join-command`

**Template used:** `config/kubeadm-config.yaml.j2`
- Sets advertiseAddress to private_ip
- Kubernetes version: v1.33.0
- Service subnet: 10.96.0.0/12
- Pod subnet: 10.244.0.0/16
- DNS domain: cluster.local
- CRI socket: unix:///var/run/containerd/containerd.sock
- Cgroup driver: systemd

**Generates:** /etc/kubernetes/admin.conf, join command

---

#### `playbooks/install-cilium.yml`
**Purpose:** Install Cilium CNI  
**What it does:**
1. Check if Cilium CLI already installed
2. Download Cilium CLI from GitHub (latest)
3. Extract and install to /usr/local/bin/cilium
4. Run `cilium install --version 1.16.4`
5. Wait for Cilium to be ready: `cilium status --wait`
6. Display Cilium status

**Cilium components deployed:**
- cilium DaemonSet (runs on all nodes)
- cilium-operator Deployment
- cilium-envoy DaemonSet

**Duration:** ~2-3 minutes for Cilium to be fully ready

---

### 🔗 STEP C: Workers Join & Verification

#### `step-c-workers-join.yml`
**Purpose:** Complete cluster setup  
**What it does:**

**Phase 1: Import playbooks/workers-join.yml**

**Phase 2: Wait for cluster readiness**
- `kubectl wait --for=condition=Ready node --all --timeout=10m`
- `kubectl rollout status ds/cilium -n kube-system --timeout=10m`

**Phase 3: Import playbooks/verify-cluster.yml**

**Phase 4: Final summary**
- Get cluster info
- Get all nodes (wide)
- Get all pods (all namespaces)
- Get Cilium status
- Display connection details

**Duration:** ~2-3 minutes

---

#### `playbooks/workers-join.yml`
**Purpose:** Join worker nodes to cluster  
**What it does:**
1. Retrieve join command from master (from file or regenerate)
2. Set join command as fact for all workers
3. Check if node already joined (check kubelet.conf)
4. Execute join command if not already joined
5. Ensure kubelet service is running

**Join command format:**
```bash
kubeadm join 192.168.100.x:6443 --token <TOKEN> \
    --discovery-token-ca-cert-hash sha256:<HASH>
```

---

#### `playbooks/verify-cluster.yml`
**Purpose:** Verify cluster health  
**What it does:**
1. Check all nodes are in Ready state
2. Count total nodes vs ready nodes
3. Verify all system pods are Running
4. Check Cilium status
5. Display cluster health summary

**Expected state:**
- Nodes: 3 total, 3 Ready
- Pods: 16 total Running
  - cilium: 3 (DaemonSet)
  - cilium-operator: 1
  - cilium-envoy: 3 (DaemonSet)
  - coredns: 2
  - kube-proxy: 3 (DaemonSet)
  - etcd: 1
  - kube-apiserver: 1
  - kube-controller-manager: 1
  - kube-scheduler: 1

---

### 🛠️ Supporting Files

#### `playbooks/common-setup.yml`
**Purpose:** Reusable common setup tasks  
**Used by:** Various playbooks for common node configuration

#### `playbooks/reset-cluster.yml`
**Purpose:** Reset cluster to clean state  
**What it does:**
- Run `kubeadm reset` on all nodes
- Remove kubeconfig files
- Stop kubelet and containerd
- Clean CNI and Kubernetes directories

#### `cluster-manager.sh`
**Purpose:** Cluster lifecycle management  
**Commands:**
- `status` - Show cluster status
- `ssh-master` - SSH to master node
- `kubeconfig` - Download kubeconfig
- `destroy` - Destroy cluster
- `nodes` - List all nodes
- `pods` - List all pods

#### `scripts/setup-openstack-environment.sh`
**Purpose:** Initial OpenStack environment setup (ONE-TIME SETUP)

**When to use:**
- Fresh OpenStack AIO installation
- After restoring OpenStack from snapshot
- Need to recreate learning domain/project

**How to run:**
```bash
# Copy to OpenStack host and execute there
scp scripts/setup-openstack-environment.sh openstack:~/
ssh openstack
./setup-openstack-environment.sh
```

**What it does:**
1. **Domain & Project Setup**
   - Creates `learning` domain
   - Creates `learning-project` in learning domain
   - Creates `learning-admin` user (password: DomainAdmin123!)
   - Grants admin role to user

2. **Network Infrastructure**
   - Creates `public` external network (172.29.248.0/22)
   - Creates subnet with gateway 172.29.248.1
   - Sets allocation pool: 172.29.249.100 - 172.29.249.200
   - Enables DHCP

3. **Image Management**
   - Downloads Ubuntu 24.04 Noble cloud image
   - Uploads to Glance as `ubuntu-noble`
   - Sets image properties (hw_disk_bus=scsi, etc.)

4. **Flavor Creation**
   - Creates `my-large` flavor
   - Specs: 2 vCPU, 4GB RAM, 8GB disk
   - Optimized to prevent disk exhaustion on AIO

5. **Networking Fix (Critical for VM connectivity)**
   - Applies iptables NAT MASQUERADE rule
   - Rule: `-s 172.29.248.0/22 ! -d 172.29.248.0/22 -j MASQUERADE`
   - Installs `iptables-persistent` package
   - Saves rules for persistence across reboots

6. **OpenRC File Generation**
   - Creates `~/openrc-learning-admin` with credentials
   - Ready to source for cluster deployments

**Dependencies:**
- Requires `openstack` CLI installed on host (`/snap/bin/openstack`)
- Must run on OpenStack host (not local machine)
- Needs root/sudo access for iptables rules

**Run time:** ~5-10 minutes

**Output:**
- OpenStack learning environment ready
- Credentials file: `~/openrc-learning-admin`
- Network routing configured and persistent

**Note:** This script was updated to use direct `openstack` CLI instead of LXC utility container wrapper

#### `ansible.cfg`
**Purpose:** Ansible configuration  
**Settings:**
- host_key_checking = False
- retry_files_enabled = False
- inventory = inventory-dynamic.yml
- remote_user = ubuntu
- private_key_file = config/k8s-cluster-key.pem

---

## 4. EXECUTION SUMMARY

### Total Deployment Timeline

```
00:00 - Start deploy-complete.sh
00:01 - Step A: Terraform init/plan (30 seconds)
00:02 - Step A: Terraform apply (1 minute)
00:03 - Step A: Wait for VMs + SSH test (30 seconds)
00:03 - Step B starts
00:04 - Step B: Common setup on all nodes (2 minutes)
00:06 - Step B: System reboot (1 minute)
00:07 - Step B: Master init with kubeadm (2 minutes)
00:09 - Step B: Install Cilium CNI (2 minutes)
00:11 - Step C starts
00:11 - Step C: Workers join (30 seconds)
00:12 - Step C: Wait for cluster ready (2 minutes)
00:14 - Step C: Verification and summary (30 seconds)
00:15 - COMPLETE ✅
```

**Total: ~15 minutes for complete 3-node cluster**

---

## 5. GIT REPOSITORY STRUCTURE

### Project Structure

```
k8s-automation/
├── .gitignore                          
├── README.md                           
├── GIT-SETUP.md                        
├── deploy-complete.sh                  
├── cluster-manager.sh                  
├── ansible.cfg                         
├── step-a-provision-infrastructure.yml 
├── step-b-kubernetes-init.yml          
├── step-c-workers-join.yml             
├── terraform/                          
│   ├── provider.tf
│   ├── variables.tf
│   ├── infrastructure.tf
│   ├── outputs.tf
│   ├── cloud-init.yaml
│   └── inventory.tpl
├── playbooks/                          
│   ├── common-setup.yml
│   ├── master-init.yml
│   ├── install-cilium.yml
│   ├── workers-join.yml
│   ├── verify-cluster.yml
│   └── reset-cluster.yml
├── scripts/                            
│   ├── setup-openstack-environment.sh
│   └── terraform-ops.sh
└── config/                             
    └── kubeadm-config.yaml.j2
```

---

## 6. QUICK REFERENCE

### One Command to Deploy Everything
```bash
./deploy-complete.sh
```

### Individual Steps (for debugging)
```bash
# Step A only
ansible-playbook step-a-provision-infrastructure.yml

# Step B only (requires Step A completed)
ansible-playbook -i inventory-dynamic.yml step-b-kubernetes-init.yml

# Step C only (requires Steps A & B completed)
ansible-playbook -i inventory-dynamic.yml step-c-workers-join.yml
```

### Terraform Operations
```bash
cd terraform
terraform init
terraform plan
terraform apply
terraform destroy
```

### Cluster Management
```bash
./cluster-manager.sh status      # Show cluster status
./cluster-manager.sh ssh-master  # SSH to master
./cluster-manager.sh kubeconfig  # Download kubeconfig
./cluster-manager.sh destroy     # Destroy cluster
```

---

**Documentation complete! Your automation is ready for production use. 🚀**
