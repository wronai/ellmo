#!/bin/bash

# Ellmo Simple Installer
# Fallback version for basic installation

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}Ellmo Simple Installer${NC}"
echo "====================="

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}Please do not run as root${NC}"
    exit 1
fi

USER_NAME=$(whoami)
INSTALL_DIR="/opt/ellmo"

echo -e "${BLUE}Step 1/10: Creating directories...${NC}"
sudo mkdir -p "$INSTALL_DIR"
sudo chown -R "$USER_NAME:$USER_NAME" "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"/{lib,linux,scripts}

echo -e "${BLUE}Step 2/10: Installing system dependencies...${NC}"
if command -v dnf &> /dev/null; then
    sudo dnf install -y curl wget git python3 python3-pip espeak-ng
elif command -v apt &> /dev/null; then
    sudo apt update
    sudo apt install -y curl wget git python3 python3-pip espeak-ng
fi

echo -e "${BLUE}Step 3/10: Installing Python dependencies...${NC}"
pip3 install --user speechrecognition pyttsx3 requests || true

echo -e "${BLUE}Step 4/10: Installing Flutter...${NC}"
if [ ! -d "/opt/flutter" ]; then
    cd /tmp
    wget "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.19.0-stable.tar.xz"
    sudo tar xf flutter_linux_3.19.0-stable.tar.xz -C /opt/
    sudo chown -R "$USER_NAME:$USER_NAME" /opt/flutter
    rm flutter_linux_3.19.0-stable.tar.xz
fi

export PATH="$PATH:/opt/flutter/bin"
echo 'export PATH="$PATH:/opt/flutter/bin"' >> ~/.bashrc

echo -e "${BLUE}Step 5/10: Installing Ollama...${NC}"
if ! command -v ollama &> /dev/null; then
    curl -fsSL https://ollama.ai/install.sh | sh
fi

sudo systemctl enable ollama
sudo systemctl start ollama
sleep 5
ollama pull mistral || echo "Will try to pull Mistral later"

echo -e "${BLUE}Step 6/10: Creating Flutter app...${NC}"
cd "$INSTALL_DIR"
flutter create . --org com.ellmo --project-name ellmo

# Simple main.dart
cat > lib/main.dart << 'EOF'
import 'package:flutter/material.dart';

void main() {
  runApp(EllmoApp());
}

class EllmoApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ellmo',
      theme: ThemeData.dark(),
      home: EllmoHome(),
    );
  }
}

class EllmoHome extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Ellmo')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assistant, size: 100, color: Colors.blue),
            SizedBox(height: 20),
            Text('Ellmo AI Assistant', style: TextStyle(fontSize: 24)),
            SizedBox(height: 20),
            Text('Installation Complete!'),
            SizedBox(height: 10),
            Text('Say "Ellmo" to activate'),
          ],
        ),
      ),
    );
  }
}
EOF

echo -e "${BLUE}Step 7/10: Building Flutter app...${NC}"
flutter pub get
flutter build linux --release

echo -e "${BLUE}Step 8/10: Creating configuration...${NC}"
cat > config.json << 'EOF'
{
  "ollama_host": "localhost",
  "ollama_port": 11434,
  "model": "mistral",
  "language": "pl-PL",
  "wake_words": ["ellmo"],
  "auto_start": true
}
EOF

echo -e "${BLUE}Step 9/10: Creating systemd service...${NC}"
sudo tee /etc/systemd/system/ellmo.service > /dev/null << EOF
[Unit]
Description=Ellmo AI Voice Assistant
After=network.target ollama.service

[Service]
Type=simple
User=$USER_NAME
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/build/linux/x64/release/bundle/ellmo
Restart=always

[Install]
WantedBy=default.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ellmo

echo -e "${BLUE}Step 10/10: Setting permissions...${NC}"
sudo usermod -a -G audio "$USER_NAME"
sudo chown -R "$USER_NAME:$USER_NAME" "$INSTALL_DIR"

echo
echo -e "${GREEN}✓ Ellmo installation completed!${NC}"
echo
echo "Next steps:"
echo "1. Start Ellmo: sudo systemctl start ellmo"
echo "2. Check status: sudo systemctl status ellmo"
echo "3. View logs: journalctl -u ellmo -f"
echo
echo "You may need to log out and back in for audio permissions."