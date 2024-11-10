#!/bin/bash

# Define the SSH key path
SSH_KEY_PATH="$HOME/.ssh/test_cluster_key"

# Remove existing key files if they exist
if [[ -f "$SSH_KEY_PATH" ]] || [[ -f "${SSH_KEY_PATH}.pub" ]]; then
    echo "Removing existing SSH key files..."
    rm -f "$SSH_KEY_PATH" "${SSH_KEY_PATH}.pub"
fi

# Generate SSH key for passwordless access
echo "Generating new SSH key pair..."
ssh-keygen -t ecdsa -b 521 -f "$SSH_KEY_PATH" -N "" -q

# Verify that the key was created successfully
if [[ -f "$SSH_KEY_PATH" && -f "${SSH_KEY_PATH}.pub" ]]; then
    echo "SSH key pair generated successfully:"
    ls -l "$SSH_KEY_PATH" "${SSH_KEY_PATH}.pub"
else
    echo "Error: Failed to generate SSH key pair."
    exit 1
fi