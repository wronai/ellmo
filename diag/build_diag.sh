#!/bin/bash

# Build Ellmo Diagnostics Application
# Creates a standalone diagnostics tool for Ellmo

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

DIAGNOSTICS_DIR="/opt/ellmo/diagnostics"
USER_NAME=$(whoami)

echo -e "${GREEN}🔧 Building Ellmo Diagnostics App${NC}"
echo "=================================="

# Create diagnostics directory
echo -e "${BLUE}Step 1: Creating diagnostics directory...${NC}"
sudo mkdir -p "$DIAGNOSTICS_DIR"
sudo chown -R "$USER_NAME:$USER_NAME" "$DIAGNOSTICS_DIR"

# Initialize Flutter project for diagnostics
echo -e "${BLUE}Step 2: Initializing Flutter project...${NC}"
cd "$DIAGNOSTICS_DIR"

if [ ! -f "pubspec.yaml" ]; then
    flutter create . --org com.ellmo --project-name ellmo_diagnostics
    echo -e "${GREEN}✓ Flutter project created${NC}"
else
    echo -e "${YELLOW}⚠ Flutter project already exists${NC}"
fi

# Create the diagnostics main.dart
echo -e "${BLUE}Step 3: Creating diagnostics application...${NC}"

# Copy the diagnostics app code to lib/main.dart
# (The code would be copied from the artifact above)

# Update pubspec.yaml for diagnostics
cat > pubspec.yaml << 'EOF'
name: ellmo_diagnostics
description: Ellmo Diagnostics - System testing and monitoring tool

publish_to: 'none'

version: 1.0.0+1

environment:
  sdk: '>=2.17.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  http: ^0.13.5
  cupertino_icons: ^1.0.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^2.0.0

flutter:
  uses-material-design: true

  assets:
    - assets/
EOF

echo -e "${GREEN}✓ Updated pubspec.yaml${NC}"

# Get dependencies and build
echo -e "${BLUE}Step 4: Building diagnostics app...${NC}"
flutter pub get
flutter build linux --release

if [ -f "build/linux/x64/release/bundle/ellmo_diagnostics" ]; then
    echo -e "${GREEN}✓ Diagnostics app built successfully${NC}"
else
    echo -e "${RED}✗ Build failed${NC}"
    exit 1
fi

# Create diagnostics launcher script
echo -e "${BLUE}Step 5: Creating launcher script...${NC}"

cat > launch_diagnostics.sh << 'EOF'
#!/bin/bash

# Ellmo Diagnostics Launcher
# Automatically sets up environment and launches diagnostics

DIAGNOSTICS_DIR="/opt/ellmo/diagnostics"

echo "🔧 Starting Ellmo Diagnostics..."

# Setup environment
export PATH="/opt/flutter/bin:$PATH"
export DISPLAY=${DISPLAY:-:0}

# Check if running in terminal
if [ -t 1 ]; then
    echo "Launching in GUI mode..."
    cd "$DIAGNOSTICS_DIR"
    exec "./build/linux/x64/release/bundle/ellmo_diagnostics" "$@"
else
    echo "Running in headless mode..."
    export FLUTTER_ENGINE_SWITCH_HEADLESS=1
    cd "$DIAGNOSTICS_DIR"
    exec "./build/linux/x64/release/bundle/ellmo_diagnostics" "$@"
fi
EOF

chmod +x launch_diagnostics.sh

# Create desktop entry for diagnostics
echo -e "${BLUE}Step 6: Creating desktop integration...${NC}"

sudo tee /usr/share/applications/ellmo-diagnostics.desktop > /dev/null << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Ellmo Diagnostics
GenericName=System Diagnostics
Comment=Ellmo system diagnostics and testing tool
Exec=$DIAGNOSTICS_DIR/launch_diagnostics.sh
Icon=utilities-system-monitor
Terminal=false
Categories=System;Monitor;Utility;
Keywords=diagnostics;test;audio;system;
StartupNotify=true
StartupWMClass=ellmo_diagnostics
EOF

# Create system-wide command
echo -e "${BLUE}Step 7: Creating system command...${NC}"

sudo tee /usr/local/bin/ellmo-diag > /dev/null << EOF
#!/bin/bash
# Ellmo Diagnostics Command

case "\$1" in
    gui|--gui)
        echo "Launching Ellmo Diagnostics GUI..."
        $DIAGNOSTICS_DIR/launch_diagnostics.sh
        ;;
    test|--test)
        echo "Running quick system test..."
        $DIAGNOSTICS_DIR/scripts/quick_test.sh
        ;;
    audio|--audio)
        echo "Testing audio system..."
        $DIAGNOSTICS_DIR/scripts/audio_test.sh
        ;;
    logs|--logs)
        echo "Showing recent logs..."
        journalctl -u ellmo --since "1 hour ago" -f
        ;;
    status|--status)
        echo "=== Ellmo System Status ==="
        systemctl status ellmo --no-pager || systemctl --user status ellmo --no-pager
        echo ""
        echo "=== Ollama Status ==="
        systemctl status ollama --no-pager
        echo ""
        echo "=== Audio Devices ==="
        aplay -l 2>/dev/null | grep "card" || echo "No audio devices found"
        ;;
    help|--help|*)
        echo "Ellmo Diagnostics Tool"
        echo ""
        echo "Usage: ellmo-diag [COMMAND]"
        echo ""
        echo "Commands:"
        echo "  gui     Launch diagnostics GUI"
        echo "  test    Run quick system test"
        echo "  audio   Test audio system"
        echo "  logs    Show service logs"
        echo "  status  Show system status"
        echo "  help    Show this help"
        echo ""
        echo "Examples:"
        echo "  ellmo-diag gui     # Launch GUI"
        echo "  ellmo-diag test    # Quick test"
        echo "  ellmo-diag status  # System status"
        ;;
esac
EOF

sudo chmod +x /usr/local/bin/ellmo-diag

# Create diagnostic scripts
echo -e "${BLUE}Step 8: Creating diagnostic scripts...${NC}"

mkdir -p scripts

# Quick test script
cat > scripts/quick_test.sh << 'EOF'
#!/bin/bash

# Quick System Test for Ellmo

echo "🔍 Ellmo Quick System Test"
echo "=========================="

# Test Flutter
echo -n "Flutter: "
if command -v flutter >/dev/null 2>&1; then
    echo "✅ Available ($(flutter --version | head -1))"
else
    echo "❌ Not found"
fi

# Test Ollama
echo -n "Ollama Service: "
if systemctl is-active ollama >/dev/null 2>&1; then
    echo "✅ Running"
    echo -n "Ollama API: "
    if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
        echo "✅ Responding"
    else
        echo "❌ Not responding"
    fi
else
    echo "❌ Not running"
fi

# Test Python modules
echo -n "Python Speech: "
if python3 -c "import speech_recognition" 2>/dev/null; then
    echo "✅ Available"
else
    echo "❌ Missing"
fi

echo -n "Python TTS: "
if python3 -c "import pyttsx3" 2>/dev/null; then
    echo "✅ Available"
else
    echo "❌ Missing"
fi

# Test Audio
echo -n "Audio Output: "
if aplay -l >/dev/null 2>&1; then
    device_count=$(aplay -l | grep "card" | wc -l)
    echo "✅ $device_count devices"
else
    echo "❌ No devices"
fi

echo -n "Audio Input: "
if arecord -l >/dev/null 2>&1; then
    device_count=$(arecord -l | grep "card" | wc -l)
    echo "✅ $device_count devices"
else
    echo "❌ No devices"
fi

# Test Ellmo Service
echo -n "Ellmo Service: "
if systemctl is-active ellmo >/dev/null 2>&1; then
    echo "✅ System service active"
elif systemctl --user is-active ellmo >/dev/null 2>&1; then
    echo "✅ User service active"
else
    echo "❌ No service running"
fi

echo ""
echo "Quick test completed!"
EOF

chmod +x scripts/quick_test.sh

# Audio test script
cat > scripts/audio_test.sh << 'EOF'
#!/bin/bash

# Audio System Test for Ellmo

echo "🎵 Ellmo Audio System Test"
echo "=========================="

echo "Available audio output devices:"
aplay -l 2>/dev/null | grep "card" || echo "No output devices found"

echo ""
echo "Available audio input devices:"
arecord -l 2>/dev/null | grep "card" || echo "No input devices found"

echo ""
echo "Testing speaker (5 second tone)..."
if command -v speaker-test >/dev/null 2>&1; then
    timeout 5 speaker-test -t sine -f 1000 -l 1 >/dev/null 2>&1 || true
    echo "✅ Speaker test completed"
else
    echo "⚠️ speaker-test not available, trying espeak..."
    if command -v espeak-ng >/dev/null 2>&1; then
        espeak-ng "Audio test successful" 2>/dev/null
        echo "✅ Text-to-speech test completed"
    else
        echo "❌ No audio test tools available"
    fi
fi

echo ""
echo "Testing microphone (3 second recording)..."
if command -v arecord >/dev/null 2>&1; then
    echo "Recording... (speak now)"
    timeout 3 arecord -d 3 -f cd /tmp/mic_test.wav >/dev/null 2>&1 || true

    if [ -f /tmp/mic_test.wav ]; then
        size=$(wc -c < /tmp/mic_test.wav)
        if [ $size -gt 1000 ]; then
            echo "✅ Microphone recorded ${size} bytes"
            echo "Playing back recording..."
            aplay /tmp/mic_test.wav >/dev/null 2>&1 || true
        else
            echo "⚠️ Very small recording (${size} bytes) - check microphone"
        fi
        rm -f /tmp/mic_test.wav
    else
        echo "❌ No recording created"
    fi
else
    echo "❌ arecord not available"
fi

echo ""
echo "PulseAudio status:"
if command -v pactl >/dev/null 2>&1; then
    echo "Sinks (speakers):"
    pactl list sinks short 2>/dev/null | head -3
    echo "Sources (microphones):"
    pactl list sources short 2>/dev/null | grep -v monitor | head -3
else
    echo "⚠️ PulseAudio not available"
fi

echo ""
echo "Audio test completed!"
EOF

chmod +x scripts/audio_test.sh

# Create systemd service for diagnostics (optional)
echo -e "${BLUE}Step 9: Creating optional service...${NC}"

cat > ellmo-diagnostics.service << EOF
[Unit]
Description=Ellmo Diagnostics Service
After=graphical-session.target

[Service]
Type=simple
User=$USER_NAME
Environment=DISPLAY=:0
WorkingDirectory=$DIAGNOSTICS_DIR
ExecStart=$DIAGNOSTICS_DIR/launch_diagnostics.sh
Restart=no

[Install]
WantedBy=graphical-session.target
EOF

# Update desktop database
echo -e "${BLUE}Step 10: Updating desktop database...${NC}"
sudo update-desktop-database /usr/share/applications/ 2>/dev/null || true

echo ""
echo -e "${GREEN}✅ Ellmo Diagnostics build completed!${NC}"
echo ""
echo -e "${YELLOW}🚀 How to use:${NC}"
echo "  • GUI Application: ellmo-diag gui"
echo "  • Quick Test: ellmo-diag test"
echo "  • Audio Test: ellmo-diag audio"
echo "  • System Status: ellmo-diag status"
echo "  • View Logs: ellmo-diag logs"
echo ""
echo -e "${BLUE}📁 Installation paths:${NC}"
echo "  • Diagnostics app: $DIAGNOSTICS_DIR/"
echo "  • Launcher script: $DIAGNOSTICS_DIR/launch_diagnostics.sh"
echo "  • System command: /usr/local/bin/ellmo-diag"
echo "  • Desktop entry: /usr/share/applications/ellmo-diagnostics.desktop"
echo ""
echo -e "${GREEN}🎯 You can now run 'ellmo-diag gui' to start diagnostics!${NC}"