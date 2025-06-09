#!/bin/bash

# Configuration management utilities

CONFIG_FILE="$1"
ACTION="$2"

case "$ACTION" in
    show)
        echo "Current Configuration:"
        if [ -f "$CONFIG_FILE" ]; then
            python3 -m json.tool "$CONFIG_FILE"
        else
            echo -e "\033[0;33mNo configuration file found\033[0m"
        fi
        ;;
    reset)
        echo "Resetting configuration to defaults..."
        rm -f "$CONFIG_FILE"
        ;;
    *)
        echo "Opening configuration..."
        if [ -f "utils.sh" ]; then
            ./utils.sh configure
        else
            echo -e "\033[0;31mutils.sh not found\033[0m"
        fi
        ;;
esac
