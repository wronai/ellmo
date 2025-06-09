#!/bin/bash

# Flutter Voice Assistant Startup Script
# This script ensures all dependencies are running before starting the app

APP_NAME="ellmo"
INSTALL_DIR="/opt/$APP_NAME"
SERVICE_NAME="ellmo"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> /var/log/$SERVICE_NAME.log
    echo -e "$1"
}

# Check if running as the correct user
if [ "$USER" = "root" ]; then
    log "${RED}Error: Do not run as root${NC}"
    exit 1
fi

# Set environment variables
export DISPLAY=:0
export PULSE_RUNTIME_PATH="/run/user/$(id -u)/pulse"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# Function to check Ollama status
check_ollama() {
    log "${BLUE}Checking Ollama status...${NC}"

    # Wait for Ollama to be ready
    for i in {1..30}; do
        if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
            log "${GREEN}✓ Ollama is running${NC}"
            return 0
        fi
        log "${YELLOW}Waiting for Ollama... ($i/30)${NC}"
        sleep 2
    done

    log "${RED}✗ Ollama is not responding${NC}"
    return 1
}

# Function to check audio system
check_audio() {
    log "${BLUE}Checking audio system...${NC}"

    # Check PulseAudio
    if pgrep -x pulseaudio >/dev/null; then
        log "${GREEN}✓ PulseAudio is running${NC}"
    else
        log "${YELLOW}Starting PulseAudio...${NC}"
        pulseaudio --start --exit-idle-time=-1 >/dev/null 2>&1 || true
    fi

    # Check ALSA
    if [ -c /dev/snd/controlC0 ]; then
        log "${GREEN}✓ Audio devices available${NC}"
    else
        log "${YELLOW}⚠ No audio devices found${NC}"
    fi

    # Test microphone access
    if arecord -l >/dev/null 2>&1; then
        log "${GREEN}✓ Microphone access available${NC}"
    else
        log "${YELLOW}⚠ Microphone access limited${NC}"
    fi
}

# Function to check Python dependencies
check_python_deps() {
    log "${BLUE}Checking Python dependencies...${NC}"

    python3 -c "
import sys
required_modules = ['speech_recognition', 'pyttsx3', 'requests']
missing = []

for module in required_modules:
    try:
        __import__(module)
        print(f'✓ {module}')
    except ImportError:
        missing.append(module)
        print(f'✗ {module}')

if missing:
    print(f'Missing modules: {missing}')
    sys.exit(1)
" 2>/dev/null

    if [ $? -eq 0 ]; then
        log "${GREEN}✓ Python dependencies available${NC}"
        return 0
    else
        log "${RED}✗ Missing Python dependencies${NC}"
        return 1
    fi
}

# Function to check display server
check_display() {
    log "${BLUE}Checking display server...${NC}"

    if [ -n "$DISPLAY" ] && xset q >/dev/null 2>&1; then
        log "${GREEN}✓ X11 display available${NC}"
        return 0
    elif [ -n "$WAYLAND_DISPLAY" ]; then
        log "${GREEN}✓ Wayland display available${NC}"
        return 0
    else
        log "${YELLOW}⚠ No display server detected (headless mode)${NC}"
        return 0
    fi
}

# Function to initialize configuration
init_config() {
    log "${BLUE}Initializing configuration...${NC}"

    CONFIG_FILE="$INSTALL_DIR/config.json"

    if [ ! -f "$CONFIG_FILE" ]; then
        log "${YELLOW}Creating default configuration...${NC}"

        cat > "$CONFIG_FILE" << 'EOF'
{
  "ollama_host": "localhost",
  "ollama_port": 11434,
  "model": "mistral",
  "language": "pl-PL",
  "wake_words": ["hey assistant", "asystent"],
  "tts_rate": 150,
  "tts_volume": 0.8,
  "audio_timeout": 5,
  "auto_start": true,
  "headless_mode": false
}
EOF

        log "${GREEN}✓ Configuration created${NC}"
    else
        log "${GREEN}✓ Configuration exists${NC}"
    fi
}

# Function to check Ollama model
check_model() {
    log "${BLUE}Checking Ollama model...${NC}"

    MODEL=$(grep -o '"model": "[^"]*"' "$INSTALL_DIR/config.json" 2>/dev/null | cut -d'"' -f4)
    MODEL=${MODEL:-mistral}

    if ollama list | grep -q "$MODEL"; then
        log "${GREEN}✓ Model '$MODEL' is available${NC}"
        return 0
    else
        log "${YELLOW}Model '$MODEL' not found, pulling...${NC}"
        if ollama pull "$MODEL"; then
            log "${GREEN}✓ Model '$MODEL' downloaded${NC}"
            return 0
        else
            log "${RED}✗ Failed to download model '$MODEL'${NC}"
            return 1
        fi
    fi
}

# Function to set permissions
set_permissions() {
    log "${BLUE}Setting permissions...${NC}"

    # Add user to audio group if not already
    if ! groups | grep -q audio; then
        log "${YELLOW}Adding user to audio group...${NC}"
        sudo usermod -a -G audio $USER
        log "${GREEN}✓ User added to audio group (restart required)${NC}"
    fi

    # Set executable permissions
    chmod +x "$INSTALL_DIR/linux/audio_handler.py" 2>/dev/null || true
    chmod +x "$INSTALL_DIR/build/linux/x64/release/bundle/$APP_NAME" 2>/dev/null || true
}

# Function to start the application
start_app() {
    log "${BLUE}Starting Flutter Voice Assistant...${NC}"

    cd "$INSTALL_DIR"

    # Check if headless mode is configured
    if grep -q '"headless_mode": true' "$INSTALL_DIR/config.json" 2>/dev/null; then
        log "${YELLOW}Running in headless mode${NC}"
        export FLUTTER_ENGINE_SWITCH_HEADLESS=1
    fi

    # Start the Flutter application
    exec "$INSTALL_DIR/build/linux/x64/release/bundle/$APP_NAME" "$@"
}

# Function to cleanup on exit
cleanup() {
    log "${YELLOW}Shutting down Voice Assistant...${NC}"

    # Kill any remaining processes
    pkill -f "audio_handler.py" 2>/dev/null || true
    pkill -f "$APP_NAME" 2>/dev/null || true

    log "${GREEN}✓ Cleanup completed${NC}"
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Main execution
main() {
    log "${GREEN}=== Flutter Voice Assistant Startup ===${NC}"

    # Pre-flight checks
    if ! check_display; then
        log "${YELLOW}Display check failed, continuing anyway${NC}"
    fi

    if ! check_audio; then
        log "${RED}Audio system check failed${NC}"
        exit 1
    fi

    if ! check_python_deps; then
        log "${RED}Python dependencies check failed${NC}"
        log "${YELLOW}Try running: pip3 install speech_recognition pyttsx3 requests${NC}"
        exit 1
    fi

    if ! check_ollama; then
        log "${RED}Ollama is not available${NC}"
        log "${YELLOW}Try running: sudo systemctl start ollama${NC}"
        exit 1
    fi

    init_config

    if ! check_model; then
        log "${RED}Model check failed${NC}"
        exit 1
    fi

    set_permissions

    # Wait a moment for everything to stabilize
    sleep 2

    log "${GREEN}✓ All systems ready${NC}"
    log "${BLUE}Starting application...${NC}"

    start_app "$@"
}

# Help function
show_help() {
    echo "Flutter Voice Assistant Startup Script"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --help, -h     Show this help message"
    echo "  --check        Run system checks only"
    echo "  --headless     Force headless mode"
    echo "  --debug        Enable debug output"
    echo
    echo "Environment Variables:"
    echo "  FLUTTER_VOICE_DEBUG=1    Enable debug mode"
    echo "  FLUTTER_VOICE_CONFIG=path    Custom config file path"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            exit 0
            ;;
        --check)
            check_display
            check_audio
            check_python_deps
            check_ollama
            init_config
            check_model
            log "${GREEN}✓ All checks completed${NC}"
            exit 0
            ;;
        --headless)
            export FLUTTER_ENGINE_SWITCH_HEADLESS=1
            log "${YELLOW}Headless mode enabled${NC}"
            shift
            ;;
        --debug)
            export FLUTTER_VOICE_DEBUG=1
            set -x
            shift
            ;;
        *)
            break
            ;;
    esac
done

# Run main function
main "$@"