#!/bin/bash

# Clean up temporary files
echo "Cleaning all temporary files..."
rm -rf dist/
rm -f /tmp/voice_assistant_*
rm -f /tmp/test_audio.wav
echo -e "\033[0;32m✓ All cleanup completed\033[0m"
