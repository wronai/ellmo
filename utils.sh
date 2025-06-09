#!/bin/bash

# Flutter Voice Assistant Utility Scripts

APP_NAME="ellmo"
INSTALL_DIR="/opt/$APP_NAME"
SERVICE_NAME="ellmo"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to show usage
show_usage() {
    echo "Flutter Voice Assistant Utilities"
    echo
    echo "Usage: $0 [COMMAND]"
    echo
    echo "Commands:"
    echo "  start         Start the voice assistant service"
    echo "  stop          Stop the voice assistant service"
    echo "  restart       Restart the voice assistant service"
    echo "  status        Show service status"
    echo "  logs          Show service logs"
    echo "  install-model Install a new Ollama model"
    echo "  list-models   List available Ollama models"
    echo "  test-audio    Test audio input/output"
    echo "  update        Update the application"
    echo "  uninstall     Remove the application"
    echo "  configure     Configure settings"
}

# Service management functions
start_service() {
    echo -e "${BLUE}Starting voice assistant...${NC}"
    sudo systemctl start $SERVICE_NAME
    sleep 2
    sudo systemctl status $SERVICE_NAME --no-pager
}

stop_service() {
    echo -e "${BLUE}Stopping voice assistant...${NC}"
    sudo systemctl stop $SERVICE_NAME
    echo -e "${GREEN}Voice assistant stopped${NC}"
}

restart_service() {
    echo -e "${BLUE}Restarting voice assistant...${NC}"
    sudo systemctl restart $SERVICE_NAME
    sleep 2
    sudo systemctl status $SERVICE_NAME --no-pager
}

show_status() {
    echo -e "${BLUE}Voice Assistant Status:${NC}"
    sudo systemctl status $SERVICE_NAME --no-pager
    echo
    echo -e "${BLUE}Ollama Status:${NC}"
    sudo systemctl status ollama --no-pager
}

show_logs() {
    echo -e "${BLUE}Voice Assistant Logs (press Ctrl+C to exit):${NC}"
    journalctl -u $SERVICE_NAME -f
}

# Ollama model management
install_model() {
    if [ -z "$2" ]; then
        echo -e "${YELLOW}Available models:${NC}"
        echo "  mistral (default)"
        echo "  llama2"
        echo "  codellama"
        echo "  vicuna"
        echo "  orca-mini"
        echo
        read -p "Enter model name: " model_name
    else
        model_name=$2
    fi

    if [ -n "$model_name" ]; then
        echo -e "${BLUE}Installing model: $model_name${NC}"
        ollama pull $model_name

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Model $model_name installed successfully${NC}"
            echo -e "${YELLOW}To use this model, update the configuration${NC}"
        else
            echo -e "${RED}Failed to install model $model_name${NC}"
        fi
    fi
}

list_models() {
    echo -e "${BLUE}Installed Ollama models:${NC}"
    ollama list
}

# Audio testing
test_audio() {
    echo -e "${BLUE}Testing audio system...${NC}"

    # Test audio output
    echo -e "${YELLOW}Testing audio output...${NC}"
    if command -v speaker-test &> /dev/null; then
        timeout 3 speaker-test -t sine -f 1000 -l 1 2>/dev/null || true
    elif command -v aplay &> /dev/null; then
        echo "Testing with aplay..."
        timeout 2 aplay /usr/share/sounds/alsa/Front_Left.wav 2>/dev/null || true
    fi

    # Test TTS
    echo -e "${YELLOW}Testing text-to-speech...${NC}"
    if command -v espeak-ng &> /dev/null; then
        espeak-ng "Audio test successful" 2>/dev/null
    elif command -v espeak &> /dev/null; then
        espeak "Audio test successful" 2>/dev/null
    fi

    # Test microphone
    echo -e "${YELLOW}Testing microphone (speak for 3 seconds)...${NC}"
    if command -v arecord &> /dev/null; then
        timeout 3 arecord -d 3 -f cd /tmp/test_audio.wav 2>/dev/null || true
        if [ -f /tmp/test_audio.wav ]; then
            echo -e "${GREEN}Microphone test completed${NC}"
            rm -f /tmp/test_audio.wav
        fi
    fi

    # Test Python audio dependencies
    echo -e "${YELLOW}Testing Python audio libraries...${NC}"
    python3 -c "
import speech_recognition as sr
import pyttsx3
print('✓ Speech recognition available')
print('✓ Text-to-speech available')
try:
    r = sr.Recognizer()
    m = sr.Microphone()
    print('✓ Microphone accessible')
except:
    print('✗ Microphone access issue')
" 2>/dev/null || echo -e "${RED}Python audio libraries not properly installed${NC}"
}

# Update application
update_app() {
    echo -e "${BLUE}Updating voice assistant...${NC}"

    # Stop service
    sudo systemctl stop $SERVICE_NAME

    # Backup current version
    if [ -d "$INSTALL_DIR.backup" ]; then
        sudo rm -rf "$INSTALL_DIR.backup"
    fi
    sudo cp -r $INSTALL_DIR "$INSTALL_DIR.backup"

    cd $INSTALL_DIR

    # Update Flutter
    flutter upgrade
    flutter pub get

    # Rebuild application
    flutter build linux --release

    # Restart service
    sudo systemctl start $SERVICE_NAME

    echo -e "${GREEN}Update completed${NC}"
}

# Uninstall application
uninstall_app() {
    echo -e "${YELLOW}This will completely remove the voice assistant${NC}"
    read -p "Are you sure? (y/N): " confirm

    if [[ $confirm =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Uninstalling voice assistant...${NC}"

        # Stop and disable service
        sudo systemctl stop $SERVICE_NAME 2>/dev/null || true
        sudo systemctl disable $SERVICE_NAME 2>/dev/null || true

        # Remove service file
        sudo rm -f /etc/systemd/system/$SERVICE_NAME.service
        sudo systemctl daemon-reload

        # Remove desktop entry
        sudo rm -f /usr/share/applications/$SERVICE_NAME.desktop

        # Remove application directory
        sudo rm -rf $INSTALL_DIR

        # Remove from PATH (if added)
        sed -i '/flutter/d' ~/.bashrc 2>/dev/null || true

        echo -e "${GREEN}Voice assistant uninstalled${NC}"
        echo -e "${YELLOW}Note: Ollama and system dependencies were not removed${NC}"
    else
        echo -e "${YELLOW}Uninstall cancelled${NC}"
    fi
}

# Configuration
configure_app() {
    echo -e "${BLUE}Voice Assistant Configuration${NC}"
    echo

    CONFIG_FILE="$INSTALL_DIR/config.json"

    if [ ! -f "$CONFIG_FILE" ]; then
        # Create default config
        cat > "$CONFIG_FILE" << EOF
{
  "ollama_host": "localhost",
  "ollama_port": 11434,
  "model": "mistral",
  "language": "pl-PL",
  "wake_words": ["hey assistant", "asystent"],
  "tts_rate": 150,
  "tts_volume": 0.8,
  "audio_timeout": 5,
  "auto_start": true
}
EOF
    fi

    echo "Current configuration:"
    cat "$CONFIG_FILE"
    echo

    echo "Configuration options:"
    echo "1. Change AI model"
    echo "2. Change language"
    echo "3. Modify wake words"
    echo "4. Adjust TTS settings"
    echo "5. Edit manually"
    echo "6. Reset to defaults"
    echo

    read -p "Choose option (1-6): " choice

    case $choice in
        1)
            echo "Available models:"
            ollama list
            read -p "Enter model name: " new_model
            if [ -n "$new_model" ]; then
                sed -i "s/\"model\": \".*\"/\"model\": \"$new_model\"/" "$CONFIG_FILE"
                echo -e "${GREEN}Model updated to: $new_model${NC}"
            fi
            ;;
        2)
            echo "Language options:"
            echo "  pl-PL (Polish)"
            echo "  en-US (English)"
            echo "  de-DE (German)"
            echo "  fr-FR (French)"
            read -p "Enter language code: " new_lang
            if [ -n "$new_lang" ]; then
                sed -i "s/\"language\": \".*\"/\"language\": \"$new_lang\"/" "$CONFIG_FILE"
                echo -e "${GREEN}Language updated to: $new_lang${NC}"
            fi
            ;;
        3)
            read -p "Enter wake words (comma separated): " wake_words
            if [ -n "$wake_words" ]; then
                # Convert to JSON array format
                json_array=$(echo "$wake_words" | sed 's/,/","/g' | sed 's/^/["/' | sed 's/$/"]/')
                sed -i "s/\"wake_words\": \[.*\]/\"wake_words\": $json_array/" "$CONFIG_FILE"
                echo -e "${GREEN}Wake words updated${NC}"
            fi
            ;;
        4)
            read -p "Enter TTS rate (50-300, default 150): " tts_rate
            read -p "Enter TTS volume (0.0-1.0, default 0.8): " tts_volume
            if [ -n "$tts_rate" ]; then
                sed -i "s/\"tts_rate\": [0-9]*/\"tts_rate\": $tts_rate/" "$CONFIG_FILE"
            fi
            if [ -n "$tts_volume" ]; then
                sed -i "s/\"tts_volume\": [0-9.]*/\"tts_volume\": $tts_volume/" "$CONFIG_FILE"
            fi
            echo -e "${GREEN}TTS settings updated${NC}"
            ;;
        5)
            ${EDITOR:-nano} "$CONFIG_FILE"
            ;;
        6)
            rm "$CONFIG_FILE"
            configure_app
            return
            ;;
        *)
            echo -e "${YELLOW}Invalid option${NC}"
            ;;
    esac

    echo
    echo -e "${BLUE}Restart the service to apply changes:${NC}"
    echo "sudo systemctl restart $SERVICE_NAME"
}

# System information
show_system_info() {
    echo -e "${BLUE}System Information:${NC}"
    echo
    echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo "Architecture: $(uname -m)"
    echo "Kernel: $(uname -r)"
    echo
    echo -e "${BLUE}Flutter Information:${NC}"
    if command -v flutter &> /dev/null; then
        flutter --version | head -1
        echo "Flutter location: $(which flutter)"
    else
        echo "Flutter not installed"
    fi
    echo
    echo -e "${BLUE}Ollama Information:${NC}"
    if command -v ollama &> /dev/null; then
        echo "Ollama version: $(ollama --version 2>/dev/null || echo 'Unknown')"
        echo "Ollama location: $(which ollama)"
        echo "Installed models:"
        ollama list 2>/dev/null || echo "Cannot connect to Ollama"
    else
        echo "Ollama not installed"
    fi
    echo
    echo -e "${BLUE}Audio System:${NC}"
    if command -v pulseaudio &> /dev/null; then
        echo "PulseAudio: Available"
    fi
    if command -v alsamixer &> /dev/null; then
        echo "ALSA: Available"
    fi
    echo "Audio devices:"
    aplay -l 2>/dev/null | grep "card" || echo "No audio devices found"
}

# Performance monitoring
monitor_performance() {
    echo -e "${BLUE}Performance Monitor (press Ctrl+C to exit)${NC}"
    echo "Monitoring CPU, Memory, and Service Status..."
    echo

    while true; do
        clear
        echo -e "${BLUE}=== Voice Assistant Performance Monitor ===${NC}"
        echo "Time: $(date)"
        echo

        # Service status
        if systemctl is-active --quiet $SERVICE_NAME; then
            echo -e "${GREEN}✓ Voice Assistant: Running${NC}"
        else
            echo -e "${RED}✗ Voice Assistant: Stopped${NC}"
        fi

        if systemctl is-active --quiet ollama; then
            echo -e "${GREEN}✓ Ollama: Running${NC}"
        else
            echo -e "${RED}✗ Ollama: Stopped${NC}"
        fi
        echo

        # System resources
        echo -e "${BLUE}System Resources:${NC}"
        echo "CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)%"
        echo "Memory: $(free -h | awk 'NR==2{printf "%.1f/%.1f GB (%.2f%%)", $3/1024/1024, $2/1024/1024, $3*100/$2}')"
        echo "Disk: $(df -h / | awk 'NR==2{printf "%s/%s (%s used)", $3, $2, $5}')"
        echo

        # Process information
        echo -e "${BLUE}Process Information:${NC}"
        ps aux | grep -E "(flutter_voice|ollama)" | grep -v grep | while read line; do
            echo "$line" | awk '{printf "%-20s CPU: %s%% MEM: %s%%\n", $11, $3, $4}'
        done

        sleep 5
    done
}

# Main script logic
case "$1" in
    start)
        start_service
        ;;
    stop)
        stop_service
        ;;
    restart)
        restart_service
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs
        ;;
    install-model)
        install_model "$@"
        ;;
    list-models)
        list_models
        ;;
    test-audio)
        test_audio
        ;;
    update)
        update_app
        ;;
    uninstall)
        uninstall_app
        ;;
    configure)
        configure_app
        ;;
    info)
        show_system_info
        ;;
    monitor)
        monitor_performance
        ;;
    *)
        show_usage
        exit 1
        ;;
esac