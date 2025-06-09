#!/bin/bash

# Fix Ellmo Service Display Issues
# This script fixes the "cannot open display" error

echo "🔧 Fixing Ellmo service display issues..."

USER_NAME=$(whoami)
SERVICE_NAME="ellmo"
INSTALL_DIR="/opt/ellmo"

# Stop current service
echo "Stopping current service..."
sudo systemctl stop ellmo 2>/dev/null || true

# Method 1: Create a proper user service (recommended)
echo "Creating user-level systemd service..."

# Create user systemd directory
mkdir -p ~/.config/systemd/user

# Create user service file
cat > ~/.config/systemd/user/ellmo.service << EOF
[Unit]
Description=Ellmo AI Voice Assistant
After=graphical-session.target pulseaudio.service
Wants=pulseaudio.service

[Service]
Type=simple
Environment=DISPLAY=:0
Environment=XDG_RUNTIME_DIR=%h/.local/share
Environment=PULSE_RUNTIME_PATH=%h/.local/share/pulse
Environment=PATH=/opt/flutter/bin:/usr/local/bin:/usr/bin:/bin
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/build/linux/x64/release/bundle/ellmo
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

# Enable user service
systemctl --user daemon-reload
systemctl --user enable ellmo
echo "✓ User service created and enabled"

# Method 2: Fix system service for headless mode
echo "Creating alternative system service with headless support..."

sudo tee /etc/systemd/system/ellmo-headless.service > /dev/null << EOF
[Unit]
Description=Ellmo AI Voice Assistant (Headless)
After=network.target ollama.service
Wants=ollama.service

[Service]
Type=simple
User=$USER_NAME
Group=audio
Environment=FLUTTER_ENGINE_SWITCH_HEADLESS=1
Environment=HOME=/home/$USER_NAME
Environment=PATH=/opt/flutter/bin:/usr/local/bin:/usr/bin:/bin
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/build/linux/x64/release/bundle/ellmo --disable-gpu --headless
Restart=always
RestartSec=10
TimeoutStartSec=30

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ellmo

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ellmo-headless
echo "✓ Headless service created"

# Method 3: Create a desktop startup script
echo "Creating desktop autostart entry..."

mkdir -p ~/.config/autostart

cat > ~/.config/autostart/ellmo.desktop << EOF
[Desktop Entry]
Type=Application
Name=Ellmo
Exec=$INSTALL_DIR/build/linux/x64/release/bundle/ellmo
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Comment=Ellmo AI Voice Assistant
EOF

echo "✓ Desktop autostart created"

# Method 4: Create a simple launcher script
echo "Creating launcher script..."

cat > $INSTALL_DIR/scripts/launch_ellmo.sh << 'EOF'
#!/bin/bash

# Ellmo Launcher Script
# Automatically detects and sets up the display environment

USER_NAME=$(whoami)
INSTALL_DIR="/opt/ellmo"

# Function to detect display
detect_display() {
    # Try to find an active X11 display
    for display in $(w -h | awk '{print $3}' | grep ':' | sort -u); do
        if xset -display "$display" q >/dev/null 2>&1; then
            export DISPLAY="$display"
            echo "Found display: $DISPLAY"
            return 0
        fi
    done

    # Try common displays
    for display in ":0" ":1" ":10"; do
        if xset -display "$display" q >/dev/null 2>&1; then
            export DISPLAY="$display"
            echo "Found display: $DISPLAY"
            return 0
        fi
    done

    # Try Wayland
    if [ -n "$WAYLAND_DISPLAY" ]; then
        echo "Using Wayland display: $WAYLAND_DISPLAY"
        return 0
    fi

    echo "No display found, running in headless mode"
    export FLUTTER_ENGINE_SWITCH_HEADLESS=1
    return 1
}

# Setup environment
setup_environment() {
    export PATH="/opt/flutter/bin:$PATH"
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"

    # Setup PulseAudio
    if [ -d "$XDG_RUNTIME_DIR/pulse" ]; then
        export PULSE_RUNTIME_PATH="$XDG_RUNTIME_DIR/pulse"
    fi

    # Change to application directory
    cd "$INSTALL_DIR"
}

# Main execution
main() {
    echo "Starting Ellmo..."

    setup_environment
    detect_display

    # Log environment
    echo "Environment:"
    echo "  DISPLAY: $DISPLAY"
    echo "  XDG_RUNTIME_DIR: $XDG_RUNTIME_DIR"
    echo "  PULSE_RUNTIME_PATH: $PULSE_RUNTIME_PATH"
    echo "  Working directory: $(pwd)"

    # Start the application
    exec "$INSTALL_DIR/build/linux/x64/release/bundle/ellmo" "$@"
}

main "$@"
EOF

chmod +x $INSTALL_DIR/scripts/launch_ellmo.sh
echo "✓ Launcher script created"

# Method 5: Update existing system service to use launcher
echo "Updating system service to use launcher..."

sudo tee /etc/systemd/system/ellmo.service > /dev/null << EOF
[Unit]
Description=Ellmo AI Voice Assistant
After=graphical-session.target sound.target network.target ollama.service
Wants=ollama.service

[Service]
Type=simple
User=$USER_NAME
Group=audio
ExecStart=$INSTALL_DIR/scripts/launch_ellmo.sh
Restart=always
RestartSec=10
TimeoutStartSec=60

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ellmo

[Install]
WantedBy=graphical-session.target
EOF

sudo systemctl daemon-reload
echo "✓ System service updated"

echo ""
echo "🎯 Service options created:"
echo "1. User service: systemctl --user start ellmo"
echo "2. Headless service: sudo systemctl start ellmo-headless"
echo "3. Desktop autostart: Will start with your desktop session"
echo "4. System service: sudo systemctl start ellmo (uses smart launcher)"
echo "5. Manual launch: $INSTALL_DIR/scripts/launch_ellmo.sh"

echo ""
echo "Choose your preferred method:"
echo "[1] User service (recommended for desktop)"
echo "[2] Headless service (for servers/headless systems)"
echo "[3] System service with launcher"
echo "[4] Test manual launch first"

read -p "Enter choice (1-4): " choice

case $choice in
    1)
        echo "Starting user service..."
        systemctl --user start ellmo
        systemctl --user status ellmo
        ;;
    2)
        echo "Starting headless service..."
        sudo systemctl start ellmo-headless
        sudo systemctl status ellmo-headless
        ;;
    3)
        echo "Starting system service..."
        sudo systemctl start ellmo
        sudo systemctl status ellmo
        ;;
    4)
        echo "Testing manual launch..."
        $INSTALL_DIR/scripts/launch_ellmo.sh
        ;;
    *)
        echo "No choice made. You can start services manually later."
        ;;
esac

echo ""
echo "✅ Fix completed! Check the status above."