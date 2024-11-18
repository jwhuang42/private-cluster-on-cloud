#!/bin/bash

# Variables (replace these with actual values or pass them as arguments)
CONTROL_NODE_NAME="test-control-node"
ZONE="us-central1-a"
USER="$USER"
SSH_KEY="$HOME/.ssh/control_node_key"
SSH_CONFIG="$HOME/.ssh/config"

# Step 1: Get the Control Node Public IP
echo "Retrieving the public IP of the control node..."
CONTROL_NODE_PUBLIC_IP=$(gcloud compute instances describe "$CONTROL_NODE_NAME" --zone="$ZONE" --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

if [[ -z "$CONTROL_NODE_PUBLIC_IP" ]]; then
    echo "Error: Unable to retrieve the public IP of the control node."
    exit 1
fi
echo "Control Node Public IP: $CONTROL_NODE_PUBLIC_IP"

# Step 2: Update SSH Config
echo "Updating SSH config for the control node..."
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
touch "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"

# Clear the existing SSH config file
> "$SSH_CONFIG"

# Append the new SSH config for the control node
cat >> "$SSH_CONFIG" <<EOF

Host $CONTROL_NODE_PUBLIC_IP
    User $USER
    IdentityFile $SSH_KEY
    BatchMode yes
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host $CONTROL_NODE_NAME
    HostName $CONTROL_NODE_PUBLIC_IP
    User $USER
    IdentityFile $SSH_KEY
    BatchMode yes
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF

echo "Updated SSH Config:"
cat "$SSH_CONFIG"