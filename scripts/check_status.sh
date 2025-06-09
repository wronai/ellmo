#!/bin/bash

SERVICE_NAME=${1:-ellmo}

# Check if service is running
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo -e "\033[0;32m✓ $SERVICE_NAME service is running\033[0m"
else
    echo -e "\033[0;31m✗ $SERVICE_NAME service is not running\033[0m"
fi
