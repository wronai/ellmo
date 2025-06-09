#!/bin/bash

# Check Python dependencies
python3 scripts/check_deps.py | while read -r line; do
    if [[ "$line" == ✓* ]]; then
        echo -e "\033[0;32m$line\033[0m"
    else
        echo -e "\033[0;31m$line\033[0m"
    fi
done
