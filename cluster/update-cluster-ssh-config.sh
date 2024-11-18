#!/bin/bash

# Arguments
CONFIG_FILE=$1
KEY_FILE=$2
INSTANCES_JSON=$3

touch "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"

# Clear the existing SSH config file
> "$CONFIG_FILE"

# Iterate over the instances JSON and append configuration entries
echo "$INSTANCES_JSON" | jq -c '.[]' | while read -r instance; do
  NAME=$(echo "$instance" | jq -r '.name')
  INTERNAL_IP=$(echo "$instance" | jq -r '.internal_ip')

  cat <<CONFIG_ENTRY >> "$CONFIG_FILE"
Host $INTERNAL_IP
  User root
  IdentityFile $KEY_FILE
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  BatchMode yes

Host $NAME
  HostName $INTERNAL_IP
  User root
  IdentityFile $KEY_FILE
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  BatchMode yes

CONFIG_ENTRY
done

echo "SSH config file created at $CONFIG_FILE"
cat $CONFIG_FILE