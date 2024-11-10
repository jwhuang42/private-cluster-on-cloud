#!/bin/bash

# Define the SSH key path
SSH_KEY_PATH="$HOME/.ssh/test_cluster_key"

# Generate the SSH key pair only if it does not already exist
if [[ -f "$SSH_KEY_PATH" && -f "${SSH_KEY_PATH}.pub" ]]; then
    echo "SSH key pair already exists at $SSH_KEY_PATH. Skipping key generation."
else
    echo "Generating new SSH key pair..."
    ssh-keygen -t ecdsa -b 521 -f "$SSH_KEY_PATH" -N "" -q

    if [[ $? -eq 0 ]]; then
        echo "SSH key pair generated successfully:"
        ls -l "$SSH_KEY_PATH" "${SSH_KEY_PATH}.pub"
    else
        echo "Error: Failed to generate SSH key pair."
        exit 1
    fi
fi