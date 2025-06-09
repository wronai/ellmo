#!/bin/bash

SERVICE_NAME=${1:-ellmo}

echo "Stopping $SERVICE_NAME service..."
sudo systemctl stop "$SERVICE_NAME"

echo -e "\033[0;32m✓ Service $SERVICE_NAME has been stopped\033[0m"
