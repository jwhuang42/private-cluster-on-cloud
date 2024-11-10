#!/bin/bash

PROJECT_ID=$(gcloud config get-value project)

# Update the Terraform configuration with the current project ID
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]:-$0}")"
sed -i "s/\${GCP_PROJECT_ID}/$PROJECT_ID/g" "$SCRIPT_DIR/main.tf"

# Generate the public key on the remote control node and retrieve it
REMOTE_CONTROL_PUBKEY=$(ssh-keygen -t ecdsa -b 384 -f ~/.ssh/test_control_node_key -N '' -q && cat ~/.ssh/test_control_node_key.pub)
echo "Generated test_control_node_key.pub: $REMOTE_CONTROL_PUBKEY"

# Update the Terraform configuration with the new public key
sed -i "s|\${CONTROL_KEY_PUB}|$REMOTE_CONTROL_PUBKEY|g" "$SCRIPT_DIR/main.tf"

echo "Updated main.tf:"
cat "$SCRIPT_DIR/main.tf"


# Update package lists
sudo apt-get update -y

# Install prerequisites
sudo apt-get install -y git wget python3 python3-pip python3-venv gnupg software-properties-common

VENV_NAME="ansible-venv"
VENV_PATH="$HOME/$VENV_NAME"

# Create a virtual environment
python3 -m venv $VENV_PATH

# Activate the virtual environment and upgrade pip
source $VENV_PATH/bin/activate
pip install --upgrade pip

# Install Ansible within the virtual environment
pip install ansible

# Deactivate the virtual environment
deactivate

# Update PATH environment variable
if ! grep -q "export PATH=\"$VENV_PATH/bin:\$PATH\"" ~/.bashrc; then
  echo "export PATH=\"$VENV_PATH/bin:\$PATH\"" >> ~/.bashrc
  echo "Added $VENV_PATH/bin to PATH in .bashrc"
else
  echo "$VENV_PATH/bin is already in PATH in .bashrc"
fi

# Install Terraform
# Add HashiCorp GPG key
wget -O- https://apt.releases.hashicorp.com/gpg | \
gpg --dearmor | \
sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null

gpg --no-default-keyring \
--keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg \
--fingerprint

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
sudo tee /etc/apt/sources.list.d/hashicorp.list

# Update and install Terraform
sudo apt-get update -y
sudo apt-get install -y terraform

# Verify installations
echo "****************************************************"
echo "Ansible command should be available after re-login"
echo "****************************************************"

echo "****************************************************"
echo "Terraform version:"
echo "****************************************************"
terraform --version

mkdir -p terraform-script
mv "$SCRIPT_DIR/main.tf" terraform-script

cd terraform-script
terraform init
