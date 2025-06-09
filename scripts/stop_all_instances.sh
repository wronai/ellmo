#!/bin/bash

# Find and kill all running instances of the application
echo "Looking for running Ellmo instances..."

# Find and kill Flutter processes
pkill -f "flutter run"

# Find and kill any other related processes
pkill -f "ellmo"

# If you want to be more specific, you can use:
# pgrep -f "ellmo" | xargs -r kill -9

echo -e "\033[0;32m✓ All Ellmo instances have been stopped\033[0m"
