#!/bin/bash

# Flutter Voice Assistant Installer
# Supports: Raspberry Pi, Radxa, Fedora, Ubuntu, Debian

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

APP_NAME="ellmo"
INSTALL_DIR="/opt/$APP_NAME"
SERVICE_NAME="ellmo"
DESKTOP_FILE="/usr/share/applications/$SERVICE_NAME.desktop"

# Detect system
detect_system() {
    echo -e "${BLUE}Detecting system...${NC}"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        echo -e "${RED}Cannot detect OS${NC}"
        exit 1
    fi

    ARCH=$(uname -m)
    echo -e "${GREEN}Detected: $OS $VER on $ARCH${NC}"

    # Check if running on embedded device
    if [[ $(cat /proc/cpuinfo | grep -i "raspberry\|radxa\|rockchip\|allwinner") ]]; then
        EMBEDDED=true
        echo -e "${YELLOW}Embedded device detected${NC}"
    else
        EMBEDDED=false
    fi
}

# Install dependencies
install_dependencies() {
    echo -e "${BLUE}Installing dependencies...${NC}"

    if command -v dnf &> /dev/null; then
        # Fedora/RHEL
        sudo dnf update -y

        # Try to install packages, continue on errors
        sudo dnf install -y curl wget git unzip xz cmake ninja-build \
            clang gtk3-devel \
            alsa-lib-devel pulseaudio-libs-devel \
            espeak-ng espeak-ng-devel \
            python3 python3-pip \
            systemd-devel --skip-unavailable || true

        # Try alternative package names for newer Fedora
        sudo dnf install -y pkgconf-devel || sudo dnf install -y pkgconfig || true

    elif command -v apt &> /dev/null; then
        # Ubuntu/Debian/Raspberry Pi OS
        sudo apt update
        sudo apt install -y curl wget git unzip xz-utils cmake ninja-build \
            clang libgtk-3-dev pkg-config \
            libasound2-dev libpulse-dev \
            espeak-ng libespeak-ng-dev \
            python3 python3-pip \
            libsystemd-dev

    elif command -v pacman &> /dev/null; then
        # Arch Linux
        sudo pacman -Syu --noconfirm
        sudo pacman -S --noconfirm curl wget git unzip xz cmake ninja \
            clang gtk3 pkgconf \
            alsa-lib pulseaudio \
            espeak-ng \
            python3 python3-pip \
            systemd
    else
        echo -e "${RED}Unsupported package manager${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Dependencies installation completed${NC}"
}

# Install Flutter
install_flutter() {
    echo -e "${BLUE}Installing Flutter...${NC}"

    FLUTTER_VERSION="3.19.0"

    if [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
        FLUTTER_ARCH="arm64"
    elif [[ "$ARCH" == "armv7l" ]]; then
        FLUTTER_ARCH="arm"
    else
        FLUTTER_ARCH="x64"
    fi

    FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

    cd /tmp
    wget $FLUTTER_URL -O flutter.tar.xz
    sudo tar xf flutter.tar.xz -C /opt/
    sudo chown -R $USER:$USER /opt/flutter

    # Add Flutter to PATH
    echo 'export PATH="$PATH:/opt/flutter/bin"' >> ~/.bashrc
    export PATH="$PATH:/opt/flutter/bin"

    flutter config --enable-linux-desktop
    flutter doctor
}

# Install Ollama
install_ollama() {
    echo -e "${BLUE}Installing Ollama...${NC}"

    curl -fsSL https://ollama.ai/install.sh | sh

    # Start Ollama service
    sudo systemctl enable ollama
    sudo systemctl start ollama

    # Wait for Ollama to start
    sleep 5

    # Pull Mistral model
    echo -e "${BLUE}Pulling Mistral model...${NC}"
    ollama pull mistral
}

# Install Python dependencies for STT/TTS
install_python_deps() {
    echo -e "${BLUE}Installing Python dependencies...${NC}"

    pip3 install --user speechrecognition pyttsx3 pyaudio requests websocket-client

    # Additional for better STT support
    if ! $EMBEDDED; then
        pip3 install --user torch torchaudio whisper-openai
    fi
}

# Create application directory
create_app_structure() {
    echo -e "${BLUE}Creating application structure...${NC}"

    sudo mkdir -p $INSTALL_DIR
    sudo chown -R $USER:$USER $INSTALL_DIR

    mkdir -p $INSTALL_DIR/{lib,assets,scripts}
}

# Create Flutter app
create_flutter_app() {
    echo -e "${BLUE}Creating Flutter application...${NC}"

    cd $INSTALL_DIR
    flutter create . --org com.ellmo --project-name ellmo

    # Replace main.dart with our implementation
    cat > lib/main.dart << 'EOF'
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() {
  runApp(EllmoApp());
}

class EllmoApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ellmo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
      ),
      home: EllmoHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class EllmoHome extends StatefulWidget {
  @override
  _EllmoHomeState createState() => _EllmoHomeState();
}

class _EllmoHomeState extends State<EllmoHome> {
  bool _isListening = false;
  bool _isSpeaking = false;
  String _lastResponse = "";
  String _status = "Ready";

  static const platform = MethodChannel('ellmo/audio');

  @override
  void initState() {
    super.initState();
    _initializeVoiceAssistant();
  }

  void _initializeVoiceAssistant() async {
    setState(() {
      _status = "Initializing...";
    });

    try {
      await platform.invokeMethod('initialize');
      setState(() {
        _status = "Ready - Say 'Hey Assistant' to start";
      });
      _startListening();
    } catch (e) {
      setState(() {
        _status = "Error: $e";
      });
    }
  }

  void _startListening() async {
    if (_isListening) return;

    setState(() {
      _isListening = true;
      _status = "Listening...";
    });

    try {
      final String result = await platform.invokeMethod('startListening');
      if (result.isNotEmpty) {
        _processVoiceCommand(result);
      }
    } catch (e) {
      print('Error in voice recognition: $e');
    } finally {
      setState(() {
        _isListening = false;
      });

      // Continue listening after a short delay
      Timer(Duration(seconds: 1), _startListening);
    }
  }

  void _processVoiceCommand(String command) async {
    setState(() {
      _status = "Processing: $command";
    });

    // Check for wake word
    if (!command.toLowerCase().contains('hey assistant') &&
        !command.toLowerCase().contains('asystent')) {
      return;
    }

    // Send to Ollama
    try {
      final response = await _sendToOllama(command);
      setState(() {
        _lastResponse = response;
        _status = "Speaking...";
      });

      _speak(response);
    } catch (e) {
      setState(() {
        _status = "Error communicating with AI: $e";
      });
    }
  }

  Future<String> _sendToOllama(String message) async {
    final url = Uri.parse('http://localhost:11434/api/generate');
    final headers = {'Content-Type': 'application/json'};
    final body = jsonEncode({
      'model': 'mistral',
      'prompt': message,
      'stream': false,
    });

    final response = await http.post(url, headers: headers, body: body);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['response'] ?? 'No response';
    } else {
      throw Exception('Failed to get response from Ollama');
    }
  }

  void _speak(String text) async {
    setState(() {
      _isSpeaking = true;
    });

    try {
      await platform.invokeMethod('speak', {'text': text});
    } catch (e) {
      print('Error in text-to-speech: $e');
    } finally {
      setState(() {
        _isSpeaking = false;
        _status = "Ready - Say 'Hey Assistant' to start";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Status indicator
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _isListening ? Colors.red.shade800 :
                         _isSpeaking ? Colors.blue.shade800 :
                         Colors.green.shade800,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  children: [
                    Icon(
                      _isListening ? Icons.mic :
                      _isSpeaking ? Icons.volume_up :
                      Icons.assistant,
                      size: 60,
                      color: Colors.white,
                    ),
                    SizedBox(height: 10),
                    Text(
                      _status,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              SizedBox(height: 40),

              // Last response
              if (_lastResponse.isNotEmpty)
                Container(
                  padding: EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade800,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Last Response:',
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        _lastResponse,
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
EOF

    # Update pubspec.yaml
    cat > pubspec.yaml << 'EOF'
name: ellmo
description: Ellmo - AI Voice Assistant with Ollama integration

version: 1.0.0+1

environment:
  sdk: '>=2.17.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  http: ^0.13.5

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^2.0.0

flutter:
  uses-material-design: true
EOF

    # Get dependencies
    flutter pub get
}

# Create native audio handler
create_audio_handler() {
    echo -e "${BLUE}Creating audio handler...${NC}"

    mkdir -p $INSTALL_DIR/linux

    cat > $INSTALL_DIR/linux/audio_handler.py << 'EOF'
#!/usr/bin/env python3

import speech_recognition as sr
import pyttsx3
import json
import sys
import threading
import queue
import time

class AudioHandler:
    def __init__(self):
        self.recognizer = sr.Recognizer()
        self.microphone = sr.Microphone()
        self.tts_engine = pyttsx3.init()
        self.tts_engine.setProperty('rate', 150)
        self.tts_engine.setProperty('volume', 0.8)

        # Adjust for ambient noise
        with self.microphone as source:
            self.recognizer.adjust_for_ambient_noise(source)

    def listen_for_speech(self, timeout=5):
        try:
            with self.microphone as source:
                # Listen for audio with timeout
                audio = self.recognizer.listen(source, timeout=timeout, phrase_time_limit=5)

            # Recognize speech
            text = self.recognizer.recognize_google(audio, language='pl-PL')
            return text
        except sr.WaitTimeoutError:
            return ""
        except sr.UnknownValueError:
            return ""
        except sr.RequestError as e:
            print(f"Speech recognition error: {e}", file=sys.stderr)
            return ""

    def speak(self, text):
        try:
            self.tts_engine.say(text)
            self.tts_engine.runAndWait()
        except Exception as e:
            print(f"TTS error: {e}", file=sys.stderr)

def main():
    audio_handler = AudioHandler()

    while True:
        try:
            line = sys.stdin.readline().strip()
            if not line:
                continue

            command = json.loads(line)

            if command['action'] == 'listen':
                result = audio_handler.listen_for_speech()
                response = {'type': 'speech_result', 'text': result}
                print(json.dumps(response), flush=True)

            elif command['action'] == 'speak':
                audio_handler.speak(command['text'])
                response = {'type': 'speech_complete'}
                print(json.dumps(response), flush=True)

        except json.JSONDecodeError:
            continue
        except KeyboardInterrupt:
            break
        except Exception as e:
            error_response = {'type': 'error', 'message': str(e)}
            print(json.dumps(error_response), flush=True)

if __name__ == "__main__":
    main()
EOF

    chmod +x $INSTALL_DIR/linux/audio_handler.py
}

# Create platform channel handler
create_platform_channel() {
    echo -e "${BLUE}Creating platform channel handler...${NC}"

    mkdir -p $INSTALL_DIR/linux

    cat > $INSTALL_DIR/linux/main.cc << 'EOF'
#include "my_application.h"

int main(int argc, char** argv) {
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
EOF

    cat > $INSTALL_DIR/linux/my_application.cc << 'EOF'
#include "my_application.h"
#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window = GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  gtk_window_set_default_size(window, 1280, 720);
  gtk_widget_show(GTK_WIDGET(window));

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

static gint my_application_command_line(GApplication* application, GApplicationCommandLine* command_line) {
  gchar** arguments = g_application_command_line_get_arguments(command_line, nullptr);

  self->dart_entrypoint_arguments = g_strdupv(arguments + 1);

  g_application_activate(application);
  return 0;
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->command_line = my_application_command_line;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", "com.voiceassistant.flutter_voice_assistant",
                                     "flags", G_APPLICATION_HANDLES_COMMAND_LINE,
                                     nullptr));
}
EOF
}

# Create systemd service
create_systemd_service() {
    echo -e "${BLUE}Creating systemd service...${NC}"

    sudo tee /etc/systemd/system/$SERVICE_NAME.service > /dev/null << EOF
[Unit]
Description=Ellmo - AI Voice Assistant
After=graphical-session.target sound.target network.target ollama.service
Wants=ollama.service

[Service]
Type=simple
User=$USER
Group=audio
Environment=DISPLAY=:0
Environment=PULSE_RUNTIME_PATH=/run/user/1000/pulse
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/build/linux/x64/release/bundle/ellmo
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=graphical-session.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable $SERVICE_NAME
}

# Create desktop entry
create_desktop_entry() {
    echo -e "${BLUE}Creating desktop entry...${NC}"

    sudo tee $DESKTOP_FILE > /dev/null << EOF
[Desktop Entry]
Name=Ellmo
Comment=Ellmo - AI Voice Assistant with Ollama
Exec=$INSTALL_DIR/build/linux/x64/release/bundle/ellmo
Icon=assistant
Terminal=false
Type=Application
Categories=Utility;AudioVideo;
StartupNotify=true
EOF
}

# Build application
build_application() {
    echo -e "${BLUE}Building Flutter application...${NC}"

    cd $INSTALL_DIR
    flutter build linux --release
}

# Configure audio permissions
configure_audio() {
    echo -e "${BLUE}Configuring audio permissions...${NC}"

    # Add user to audio group
    sudo usermod -a -G audio $USER

    # Configure PulseAudio for system service
    if [ ! -f ~/.config/pulse/client.conf ]; then
        mkdir -p ~/.config/pulse
        echo "autospawn = yes" > ~/.config/pulse/client.conf
    fi
}

# Main installation function
main() {
    echo -e "${GREEN}Flutter Voice Assistant Installer${NC}"
    echo -e "${YELLOW}This will install Flutter, Ollama, and Ellmo${NC}"
    echo

    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        echo -e "${RED}Please do not run as root${NC}"
        exit 1
    fi

    detect_system
    install_dependencies
    install_flutter
    install_ollama
    install_python_deps
    create_app_structure
    create_flutter_app
    create_audio_handler
    create_platform_channel
    build_application
    configure_audio
    create_systemd_service
    create_desktop_entry

    echo
    echo -e "${GREEN}Installation completed successfully!${NC}"
    echo
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Reboot your system or log out and back in"
    echo "2. Ellmo will start automatically"
    echo "3. Say 'Ellmo' to activate voice commands"
    echo
    echo -e "${BLUE}Manual start: sudo systemctl start $SERVICE_NAME${NC}"
    echo -e "${BLUE}Check status: sudo systemctl status $SERVICE_NAME${NC}"
    echo -e "${BLUE}View logs: journalctl -u $SERVICE_NAME -f${NC}"
}

main "$@"