#!/bin/bash

VPC_NETWORK_NAME=test-cluster-network
VPC_SUBNET_NAME=test-cluster-subnet
VPC_SUBNET_RANGE=192.168.0.0/24
PROJECT_ID=$(gcloud config get-value project)
REGION=us-central1
ZONE=us-central1-a

# Create VPC with customized subnet and firewall rules.
if ! gcloud compute networks describe "$VPC_NETWORK_NAME" >/dev/null 2>&1; then
    echo "Network $VPC_NETWORK_NAME does not exist. Creating it..."
    gcloud compute networks create "$VPC_NETWORK_NAME" --project="$PROJECT_ID" --subnet-mode=custom --mtu=1460 --bgp-routing-mode=regional 
else
    echo "Network $VPC_NETWORK_NAME already exists. Skipping creation."
fi

if ! gcloud compute networks subnets describe "$VPC_SUBNET_NAME" --region="$REGION" >/dev/null 2>&1; then
    echo "Subnet $VPC_SUBNET_NAME does not exist in region $REGION. Creating it..."
    gcloud compute networks subnets create "$VPC_SUBNET_NAME" --project="$PROJECT_ID" --range="$VPC_SUBNET_RANGE" \
        --stack-type=IPV4_ONLY --network="$VPC_NETWORK_NAME" --region="$REGION" --enable-private-ip-google-access 
else
    echo "Subnet $VPC_SUBNET_NAME already exists in region $REGION. Skipping creation."
fi

ALLOW_CUSTOM_FIREWALL_RULE_NAME="$VPC_NETWORK_NAME"-allow-custom
if ! gcloud compute firewall-rules describe $ALLOW_CUSTOM_FIREWALL_RULE_NAME >/dev/null 2>&1; then
    echo "Firewall rule $FIREWALL_RULE_NAME does not exist. Creating it..."
    gcloud compute firewall-rules create $ALLOW_CUSTOM_FIREWALL_RULE_NAME --project="$PROJECT_ID" \
        --network=projects/"$PROJECT_ID"/global/networks/"$VPC_NETWORK_NAME" \
        --description="Allows connection from any source to any instance on the network using custom protocols." \
        --direction=INGRESS --priority=65534 --source-ranges="$VPC_SUBNET_RANGE" --action=ALLOW --rules=all
else
    echo "Firewall rule $ALLOW_CUSTOM_FIREWALL_RULE_NAME already exists. Skipping creation."
fi

ALLOW_SSH_FIREWALL_RULE_NAME="$VPC_NETWORK_NAME"-allow-ssh
if ! gcloud compute firewall-rules describe $ALLOW_SSH_FIREWALL_RULE_NAME >/dev/null 2>&1; then
    echo "Firewall rule $FIREWALL_RULE_NAME does not exist. Creating it..."
    gcloud compute --project="$PROJECT_ID" firewall-rules create $ALLOW_SSH_FIREWALL_RULE_NAME \
        --description="Allow ssh to the VPC nodes from instances outside the VPC." --direction=INGRESS --priority=1000 --network="$VPC_NETWORK_NAME" \
        --action=ALLOW --rules=tcp:22 --source-ranges=0.0.0.0/0 --target-tags=allow-ssh
else
    echo "Firewall rule $ALLOW_SSH_FIREWALL_RULE_NAME already exists. Skipping creation."
fi

# Generate SSH key on cloud shell to enable passwordless access.
ssh-keygen -t ecdsa -b 521 -f ~/.ssh/test_cluster_key -N "" -q
if [ -f ~/.ssh/known_hosts ]; then
    > ~/.ssh/known_hosts
    echo "Cleared the contents of ~/.ssh/known_hosts"
fi

# Provision the control node.
CONTROL_NODE_NAME=test-control-node
# Check if the instance exists
if gcloud compute instances describe "$CONTROL_NODE_NAME" --zone "$ZONE" >/dev/null 2>&1; then
    echo "Instance $CONTROL_NODE_NAME exists. Deleting it before creating new one..."
    gcloud compute instances delete "$CONTROL_NODE_NAME" --zone "$ZONE" --quiet
    echo "Instance $CONTROL_NODE_NAME deleted."
fi
echo "Instance $CONTROL_NODE_NAME does not exist. Proceeding with creation..."
gcloud compute instances create "$CONTROL_NODE_NAME" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --machine-type=e2-small \
    --tags=allow-ssh \
    --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet="$VPC_SUBNET_NAME" \
    --metadata=ssh-keys="$USER":"$(cat ~/.ssh/test_cluster_key.pub)" \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
    --create-disk=auto-delete=yes,boot=yes,device-name="$CONTROL_NODE_NAME",image=projects/ubuntu-os-cloud/global/images/ubuntu-2204-jammy-v20240927,mode=rw,size=10,type=pd-balanced \
    --no-shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --labels=goog-ec-src=vm_add-gcloud \
    --reservation-affinity=any

CONTROL_NODE_PUBLIC_IP="$(gcloud compute instances describe "$CONTROL_NODE_NAME" --zone="$ZONE" --format="get(networkInterfaces[0].accessConfigs[0].natIP)")"

echo "******************************************************************"
echo "Created $CONTROL_NODE_NAME with public IP: $CONTROL_NODE_PUBLIC_IP"
echo "******************************************************************"

SSH_KEY="$HOME/.ssh/test_cluster_key"
SSH_CONFIG="$HOME/.ssh/config"

# Ensure the .ssh directory exists
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
# Ensure the SSH config file exists
touch "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"

# Backup existing SSH config file
if [[ -f "$SSH_CONFIG" ]]; then
    echo "Backing up existing SSH config file to $SSH_CONFIG.bak"
    cp "$SSH_CONFIG" "$SSH_CONFIG.bak"
fi

# Clean up the existing SSH config file
echo "Cleaning up $SSH_CONFIG file..."
> "$SSH_CONFIG"

# Append the new Host section to the ~/.ssh/config file
echo "Adding SSH configuration for "$CONTROL_NODE_NAME"..."
cat >> "$SSH_CONFIG" <<EOF

Host $CONTROL_NODE_NAME
    HostName $CONTROL_NODE_PUBLIC_IP
    User $USER
    IdentityFile $SSH_KEY
    BatchMode yes
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF

# Attempt to SSH using the 'test-control-node' alias
echo "Attempting SSH connection to '"$CONTROL_NODE_NAME"'..."
if ssh "$CONTROL_NODE_NAME" "true"; then
    echo "SSH connection successful."
else
    echo "Error: SSH connection failed. Here are some possible issues and debugging steps:"
    echo
    echo "1. **Unknown Host**:"
    echo "   - The hostname '"$CONTROL_NODE_NAME"' could not be resolved."
    echo "   - Ensure the IP address in the SSH config is correct (\`HostName $CONTROL_NODE_PUBLIC_IP\`)."
    echo
    echo "2. **Connection Closed by Remote Host**:"
    echo "   - The SSH server may have terminated the connection. Check the SSH server logs on the remote host (e.g., /var/log/auth.log or /var/log/secure)."
    echo "   - Ensure the SSH service is running on the remote host: \`sudo systemctl status ssh\` or \`sudo systemctl status sshd\`."
    echo
    echo "3. **Connection Refused**:"
    echo "   - The SSH service may not be running or listening on the default port (22)."
    echo "   - Check if the SSH port is correct: \`nmap -p 22 $CONTROL_NODE_PUBLIC_IP\`."
    echo "   - Ensure there is no firewall blocking the SSH port (e.g., iptables or cloud firewall rules)."
    echo
    echo "4. **Permission Denied (Public Key Authentication Failed)**:"
    echo "   - Verify that the SSH key is correct and has the right permissions: \`chmod 600 $SSH_KEY\`."
    echo "   - Ensure the public key is added to the \`~/.ssh/authorized_keys\` file on the remote host."
    echo "   - Check if the correct user is specified in the SSH config (e.g., $USER)."
    echo
    echo "5. **Host Unreachable or Network Issues**:"
    echo "   - Confirm the IP address of the control node: \`ping $CONTROL_NODE_PUBLIC_IP\`."
    echo "   - Verify network connectivity and routing: \`traceroute $CONTROL_NODE_PUBLIC_IP\`."
    echo "   - Check if there are any VPNs or proxies affecting the connection."
    exit 1
fi

# Update the Terraform configuration with the current project ID
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]:-$0}")"
sed -i "s/\${GCP_PROJECT_ID}/$PROJECT_ID/g" "$SCRIPT_DIR/main.tf"

# Generate the public key on the remote control node and retrieve it
REMOTE_CONTROL_PUBKEY=$(ssh $CONTROL_NODE_NAME "ssh-keygen -t ecdsa -b 384 -f ~/.ssh/test_control_node_key -N '' -q && cat ~/.ssh/test_control_node_key.pub")
echo "Got public key generated on $CONTROL_NODE_NAME: $REMOTE_CONTROL_PUBKEY"

# Update the Terraform configuration with the new public key
sed -i "s|\${CONTROL_KEY_PUB}|$REMOTE_CONTROL_PUBKEY|g" "$SCRIPT_DIR/main.tf"

echo "Updated main.tf:"
cat "$SCRIPT_DIR/main.tf"

# Install rsync if not already installed
sudo apt-get update -y
sudo apt-get install -y rsync

# Use rsync to transfer files to the control node
rsync -av -e "ssh $CONTROL_NODE_NAME" --include 'control-startup.sh' --include 'main.tf' --exclude '*' "$SCRIPT_DIR/" "$CONTROL_NODE_NAME:~/test-cluster-terraform/"

# Execute the startup script on the control node
ssh $CONTROL_NODE_NAME 'bash ~/test-cluster-terraform/control-startup.sh'
