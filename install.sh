#!/bin/bash

# Ellmo - Advanced Installer with Comprehensive Logging
# Supports: Raspberry Pi, Radxa, Fedora, Ubuntu, Debian, Arch Linux
# Version: 2.0.1 - Fixed argument parsing

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Application constants
APP_NAME="ellmo"
APP_VERSION="1.0.0"
INSTALL_DIR="/opt/$APP_NAME"
SERVICE_NAME="ellmo"
DESKTOP_FILE="/usr/share/applications/$SERVICE_NAME.desktop"
LOG_DIR="/var/log/ellmo"
LOG_FILE="$LOG_DIR/install.log"
USER_NAME=$(whoami)
INSTALL_START_TIME=$(date +%s)

# Create logging directory
sudo mkdir -p "$LOG_DIR"
sudo chown $USER_NAME:$USER_NAME "$LOG_DIR"

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp] [$level] $message"

    echo "$log_entry" >> "$LOG_FILE"

    case $level in
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" >&2
            ;;
        "WARNING"|"WARN")
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        "DEBUG")
            if [[ "$DEBUG" == "1" ]]; then
                echo -e "${PURPLE}[DEBUG]${NC} $message"
            fi
            ;;
        "STEP")
            echo -e "${CYAN}[STEP]${NC} $message"
            ;;
        *)
            echo -e "${WHITE}[$level]${NC} $message"
            ;;
    esac
}

# Progress tracking
TOTAL_STEPS=15
CURRENT_STEP=0

progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local percentage=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    echo -e "${CYAN}[$CURRENT_STEP/$TOTAL_STEPS] ($percentage%) $1${NC}"
    log "PROGRESS" "[$CURRENT_STEP/$TOTAL_STEPS] $1"
}

# Error handling
handle_error() {
    local exit_code=$?
    local line_number=$1
    log "ERROR" "Script failed at line $line_number with exit code $exit_code"
    log "ERROR" "Installation failed. Check logs at $LOG_FILE"
    echo -e "${RED}Installation failed! Check logs: $LOG_FILE${NC}"

    # Cleanup on error
    cleanup_on_error
    exit $exit_code
}

trap 'handle_error $LINENO' ERR

# Cleanup function
cleanup_on_error() {
    log "INFO" "Performing cleanup after error..."

    # Stop any running services
    sudo systemctl stop $SERVICE_NAME 2>/dev/null || true

    # Remove incomplete installation
    if [[ -d "$INSTALL_DIR" && "$ALLOW_CLEANUP" == "1" ]]; then
        log "INFO" "Removing incomplete installation directory"
        sudo rm -rf "$INSTALL_DIR"
    fi
}

# System detection with detailed logging
detect_system() {
    progress "Detecting system configuration..."

    if [ -f /etc/os-release ]; then
        source /etc/os-release
        OS_NAME="$NAME"
        OS_VERSION="$VERSION_ID"
        OS_ID="$ID"
    else
        log "ERROR" "Cannot detect operating system"
        exit 1
    fi

    ARCH=$(uname -m)
    KERNEL_VERSION=$(uname -r)
    TOTAL_RAM=$(free -h | awk 'NR==2{print $2}')
    TOTAL_DISK=$(df -h / | awk 'NR==2{print $2}')

    # Check for embedded devices
    EMBEDDED=false
    if [[ $(cat /proc/cpuinfo 2>/dev/null | grep -i "raspberry\|radxa\|rockchip\|allwinner\|amlogic") ]]; then
        EMBEDDED=true
        DEVICE_TYPE=$(cat /proc/cpuinfo | grep -i "model\|hardware" | head -1 | cut -d':' -f2 | xargs)
    fi

    log "INFO" "System Detection Complete:"
    log "INFO" "  OS: $OS_NAME $OS_VERSION ($OS_ID)"
    log "INFO" "  Architecture: $ARCH"
    log "INFO" "  Kernel: $KERNEL_VERSION"
    log "INFO" "  RAM: $TOTAL_RAM"
    log "INFO" "  Disk Space: $TOTAL_DISK"
    log "INFO" "  Embedded Device: $EMBEDDED"
    [[ "$EMBEDDED" == "true" ]] && log "INFO" "  Device Type: $DEVICE_TYPE"

    echo -e "${GREEN}✓ Detected: $OS_NAME $OS_VERSION on $ARCH${NC}"
    [[ "$EMBEDDED" == "true" ]] && echo -e "${YELLOW}📱 Embedded device detected: $DEVICE_TYPE${NC}"
}

# Comprehensive system requirements check
check_requirements() {
    progress "Checking system requirements..."

    local requirements_met=true

    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        log "ERROR" "Script should not be run as root"
        echo -e "${RED}Please do not run as root${NC}"
        exit 1
    fi

    # Check disk space (minimum 5GB)
    local available_space=$(df / | awk 'NR==2{print $4}')
    local required_space=5242880  # 5GB in KB

    if [ "$available_space" -lt "$required_space" ]; then
        log "ERROR" "Insufficient disk space. Required: 5GB, Available: $(($available_space/1024/1024))GB"
        requirements_met=false
    else
        log "SUCCESS" "Disk space check passed: $(($available_space/1024/1024))GB available"
    fi

    # Check RAM (minimum 1GB, recommended 2GB)
    local ram_kb=$(free | awk 'NR==2{print $2}')
    local min_ram=1048576  # 1GB in KB
    local rec_ram=2097152  # 2GB in KB

    if [ "$ram_kb" -lt "$min_ram" ]; then
        log "ERROR" "Insufficient RAM. Minimum: 1GB, Available: $(($ram_kb/1024/1024))GB"
        requirements_met=false
    elif [ "$ram_kb" -lt "$rec_ram" ]; then
        log "WARNING" "RAM below recommended. Available: $(($ram_kb/1024/1024))GB, Recommended: 2GB"
    else
        log "SUCCESS" "RAM check passed: $(($ram_kb/1024/1024))GB available"
    fi

    # Check internet connectivity
    if ping -c 1 google.com >/dev/null 2>&1; then
        log "SUCCESS" "Internet connectivity verified"
    else
        log "WARNING" "No internet connectivity detected. Some features may not work."
    fi

    # Check audio devices
    if [ -d "/proc/asound" ] && [ "$(ls -A /proc/asound 2>/dev/null)" ]; then
        log "SUCCESS" "Audio devices detected"
    else
        log "WARNING" "No audio devices detected"
    fi

    if [ "$requirements_met" = false ]; then
        log "ERROR" "System requirements not met. Installation cannot continue."
        exit 1
    fi

    log "SUCCESS" "All system requirements passed"
}

# Enhanced dependency installation with retry logic
install_dependencies() {
    progress "Installing system dependencies..."

    local max_retries=3
    local retry_count=0

    install_deps_with_retry() {
        if command -v dnf &> /dev/null; then
            install_fedora_deps
        elif command -v apt &> /dev/null; then
            install_debian_deps
        elif command -v pacman &> /dev/null; then
            install_arch_deps
        elif command -v zypper &> /dev/null; then
            install_opensuse_deps
        else
            log "ERROR" "Unsupported package manager"
            return 1
        fi
    }

    while [ $retry_count -lt $max_retries ]; do
        if install_deps_with_retry; then
            log "SUCCESS" "Dependencies installed successfully"
            return 0
        else
            retry_count=$((retry_count + 1))
            log "WARNING" "Dependency installation failed (attempt $retry_count/$max_retries)"
            if [ $retry_count -lt $max_retries ]; then
                log "INFO" "Retrying in 10 seconds..."
                sleep 10
            fi
        fi
    done

    log "ERROR" "Failed to install dependencies after $max_retries attempts"
    return 1
}

install_fedora_deps() {
    log "INFO" "Installing Fedora/RHEL dependencies..."

    # Update system
    sudo dnf update -y 2>&1 | tee -a "$LOG_FILE" || true

    # Core packages
    local packages=(
        "curl" "wget" "git" "unzip" "xz" "cmake" "ninja-build"
        "clang" "gtk3-devel" "alsa-lib-devel" "pulseaudio-libs-devel"
        "espeak-ng" "python3" "python3-pip" "systemd-devel"
    )

    # Try different package names for different Fedora versions
    if ! sudo dnf install -y pkgconf-devel 2>/dev/null; then
        if ! sudo dnf install -y pkgconfig 2>/dev/null; then
            log "WARNING" "Could not install pkgconf-devel or pkgconfig"
        fi
    fi

    # Install packages with error handling
    for package in "${packages[@]}"; do
        if sudo dnf install -y "$package" 2>&1 | tee -a "$LOG_FILE"; then
            log "SUCCESS" "Installed: $package"
        else
            log "WARNING" "Failed to install: $package"
        fi
    done

    # Install espeak-ng-devel if available
    sudo dnf install -y espeak-ng-devel 2>/dev/null || log "WARNING" "espeak-ng-devel not available"
}

install_debian_deps() {
    log "INFO" "Installing Debian/Ubuntu dependencies..."

    # Update package lists
    sudo apt update 2>&1 | tee -a "$LOG_FILE"

    local packages=(
        "curl" "wget" "git" "unzip" "xz-utils" "cmake" "ninja-build"
        "clang" "libgtk-3-dev" "pkg-config" "libasound2-dev" "libpulse-dev"
        "espeak-ng" "libespeak-ng-dev" "python3" "python3-pip" "libsystemd-dev"
    )

    # Install packages
    if sudo apt install -y "${packages[@]}" 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Debian dependencies installed"
    else
        log "WARNING" "Some Debian dependencies may have failed"
    fi
}

install_arch_deps() {
    log "INFO" "Installing Arch Linux dependencies..."

    # Update system
    sudo pacman -Syu --noconfirm 2>&1 | tee -a "$LOG_FILE"

    local packages=(
        "curl" "wget" "git" "unzip" "xz" "cmake" "ninja"
        "clang" "gtk3" "pkgconf" "alsa-lib" "pulseaudio"
        "espeak-ng" "python" "python-pip" "systemd"
    )

    if sudo pacman -S --noconfirm "${packages[@]}" 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Arch dependencies installed"
    else
        log "WARNING" "Some Arch dependencies may have failed"
    fi
}

install_opensuse_deps() {
    log "INFO" "Installing openSUSE dependencies..."

    sudo zypper refresh 2>&1 | tee -a "$LOG_FILE"

    local packages=(
        "curl" "wget" "git" "unzip" "xz" "cmake" "ninja"
        "clang" "gtk3-devel" "pkg-config" "alsa-devel" "pulseaudio-devel"
        "espeak-ng" "python3" "python3-pip" "systemd-devel"
    )

    if sudo zypper install -y "${packages[@]}" 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "openSUSE dependencies installed"
    else
        log "WARNING" "Some openSUSE dependencies may have failed"
    fi
}

# Enhanced Python dependencies installation
install_python_deps() {
    progress "Installing Python dependencies..."

    local python_packages=("speechrecognition" "pyttsx3" "requests" "websocket-client")

    # Upgrade pip first
    log "INFO" "Upgrading pip..."
    python3 -m pip install --user --upgrade pip 2>&1 | tee -a "$LOG_FILE" || true

    # Install packages one by one with error handling
    for package in "${python_packages[@]}"; do
        log "INFO" "Installing Python package: $package"

        if python3 -m pip install --user "$package" 2>&1 | tee -a "$LOG_FILE"; then
            log "SUCCESS" "Installed Python package: $package"
        else
            log "WARNING" "Failed to install Python package: $package"
            # Try alternative installation
            if command -v dnf &> /dev/null; then
                sudo dnf install -y "python3-$package" 2>/dev/null || true
            elif command -v apt &> /dev/null; then
                sudo apt install -y "python3-$package" 2>/dev/null || true
            fi
        fi
    done

    # Try to install pyaudio (often problematic)
    log "INFO" "Attempting to install PyAudio..."
    if python3 -m pip install --user pyaudio 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "PyAudio installed via pip"
    else
        log "WARNING" "PyAudio pip installation failed, trying system packages..."
        if command -v dnf &> /dev/null; then
            sudo dnf install -y python3-pyaudio portaudio-devel 2>/dev/null || true
        elif command -v apt &> /dev/null; then
            sudo apt install -y python3-pyaudio portaudio19-dev 2>/dev/null || true
        fi
    fi

    # Verify Python dependencies
    log "INFO" "Verifying Python dependencies..."
    python3 -c "
import sys
modules = ['speech_recognition', 'pyttsx3', 'requests', 'json']
failed = []
for module in modules:
    try:
        __import__(module)
        print(f'✓ {module}')
    except ImportError:
        failed.append(module)
        print(f'✗ {module}')

if failed:
    print(f'Missing modules: {failed}')
    sys.exit(1)
else:
    print('All required Python modules available')
" 2>&1 | tee -a "$LOG_FILE"

    if [ $? -eq 0 ]; then
        log "SUCCESS" "Python dependencies verified"
    else
        log "WARNING" "Some Python dependencies may be missing"
    fi
}

# Enhanced Flutter installation with version management
install_flutter() {
    progress "Installing Flutter SDK..."

    local flutter_version="3.19.6"
    local flutter_channel="stable"

    # Determine architecture
    case "$ARCH" in
        "x86_64")
            local flutter_arch="x64"
            ;;
        "aarch64"|"arm64")
            local flutter_arch="arm64"
            ;;
        "armv7l")
            local flutter_arch="arm"
            ;;
        *)
            log "ERROR" "Unsupported architecture: $ARCH"
            return 1
            ;;
    esac

    local flutter_url="https://storage.googleapis.com/flutter_infra_release/releases/${flutter_channel}/linux/flutter_linux_${flutter_version}-${flutter_channel}.tar.xz"

    if [ -d "/opt/flutter" ]; then
        log "INFO" "Flutter already exists at /opt/flutter"
        local existing_version=$(/opt/flutter/bin/flutter --version 2>/dev/null | head -1 | awk '{print $2}' || echo "unknown")
        log "INFO" "Existing Flutter version: $existing_version"

        if [[ "$existing_version" != "$flutter_version"* ]]; then
            log "INFO" "Updating Flutter to version $flutter_version"
            sudo rm -rf /opt/flutter
        else
            log "INFO" "Flutter is already up to date"
            export PATH="$PATH:/opt/flutter/bin"
            return 0
        fi
    fi

    log "INFO" "Downloading Flutter $flutter_version for $flutter_arch..."

    cd /tmp
    if wget -O flutter.tar.xz "$flutter_url" 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Flutter downloaded successfully"
    else
        log "WARNING" "Failed to download Flutter $flutter_version, trying alternative..."
        # Try fallback version
        flutter_url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.19.0-stable.tar.xz"
        if wget -O flutter.tar.xz "$flutter_url" 2>&1 | tee -a "$LOG_FILE"; then
            log "SUCCESS" "Flutter fallback version downloaded"
        else
            log "ERROR" "Failed to download Flutter"
            return 1
        fi
    fi

    log "INFO" "Extracting Flutter..."
    if sudo tar xf flutter.tar.xz -C /opt/ 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Flutter extracted successfully"
    else
        log "ERROR" "Failed to extract Flutter"
        return 1
    fi

    # Set permissions
    sudo chown -R "$USER_NAME:$USER_NAME" /opt/flutter

    # Add to PATH
    if ! grep -q "flutter/bin" ~/.bashrc; then
        echo 'export PATH="$PATH:/opt/flutter/bin"' >> ~/.bashrc
        log "INFO" "Added Flutter to PATH in ~/.bashrc"
    fi

    export PATH="$PATH:/opt/flutter/bin"

    # Configure Flutter
    log "INFO" "Configuring Flutter..."
    flutter config --enable-linux-desktop 2>&1 | tee -a "$LOG_FILE"
    flutter config --no-analytics 2>&1 | tee -a "$LOG_FILE"

    # Accept licenses
    flutter doctor --android-licenses 2>/dev/null || true

    # Run Flutter doctor
    log "INFO" "Running Flutter doctor..."
    flutter doctor 2>&1 | tee -a "$LOG_FILE"

    # Clean up
    rm -f /tmp/flutter.tar.xz

    log "SUCCESS" "Flutter installation completed"
}

# Enhanced Ollama installation with model management
install_ollama() {
    progress "Installing Ollama AI platform..."

    if command -v ollama &> /dev/null; then
        log "INFO" "Ollama already installed"
        local ollama_version=$(ollama --version 2>/dev/null | head -1 || echo "unknown")
        log "INFO" "Ollama version: $ollama_version"
    else
        log "INFO" "Downloading and installing Ollama..."
        if curl -fsSL https://ollama.ai/install.sh | sh 2>&1 | tee -a "$LOG_FILE"; then
            log "SUCCESS" "Ollama installed successfully"
        else
            log "ERROR" "Failed to install Ollama"
            return 1
        fi
    fi

    # Configure and start Ollama service
    log "INFO" "Configuring Ollama service..."
    sudo systemctl enable ollama 2>&1 | tee -a "$LOG_FILE"
    sudo systemctl start ollama 2>&1 | tee -a "$LOG_FILE"

    # Wait for Ollama to be ready
    log "INFO" "Waiting for Ollama to be ready..."
    local max_wait=60
    local wait_count=0

    while [ $wait_count -lt $max_wait ]; do
        if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
            log "SUCCESS" "Ollama is ready"
            break
        fi

        sleep 2
        wait_count=$((wait_count + 2))

        if [ $((wait_count % 10)) -eq 0 ]; then
            log "INFO" "Still waiting for Ollama... ($wait_count/${max_wait}s)"
        fi
    done

    if [ $wait_count -ge $max_wait ]; then
        log "WARNING" "Ollama may not be ready, continuing anyway..."
    fi

    # Pull required models
    local models=("mistral")

    for model in "${models[@]}"; do
        log "INFO" "Pulling model: $model"

        if ollama pull "$model" 2>&1 | tee -a "$LOG_FILE"; then
            log "SUCCESS" "Model $model pulled successfully"
        else
            log "WARNING" "Failed to pull model $model, will try later"
        fi
    done

    # List available models
    log "INFO" "Available Ollama models:"
    ollama list 2>&1 | tee -a "$LOG_FILE" || true
}

# Create application structure with proper permissions
create_app_structure() {
    progress "Creating application structure..."

    log "INFO" "Creating directory structure..."

    # Create main directory
    sudo mkdir -p "$INSTALL_DIR"
    sudo chown -R "$USER_NAME:$USER_NAME" "$INSTALL_DIR"

    # Create subdirectories
    local directories=("lib" "assets" "scripts" "linux" "logs" "config" "backup")

    for dir in "${directories[@]}"; do
        mkdir -p "$INSTALL_DIR/$dir"
        log "DEBUG" "Created directory: $INSTALL_DIR/$dir"
    done

    # Set proper permissions
    chmod 755 "$INSTALL_DIR"
    chmod 755 "$INSTALL_DIR"/*

    log "SUCCESS" "Application structure created"
}

# Enhanced Flutter app creation with comprehensive error handling
create_flutter_app() {
    progress "Creating Flutter application..."

    cd "$INSTALL_DIR"

    # Initialize Flutter project
    if [ ! -f "pubspec.yaml" ]; then
        log "INFO" "Initializing Flutter project..."
        if flutter create . --org com.ellmo --project-name ellmo 2>&1 | tee -a "$LOG_FILE"; then
            log "SUCCESS" "Flutter project initialized"
        else
            log "ERROR" "Failed to initialize Flutter project"
            return 1
        fi
    else
        log "INFO" "Flutter project already exists"
    fi

    # Create comprehensive main.dart
    log "INFO" "Creating main application file..."
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
        scaffoldBackgroundColor: Color(0xFF1E1E1E),
        cardColor: Color(0xFF2D2D2D),
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFF2D2D2D),
          elevation: 0,
        ),
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

class _EllmoHomeState extends State<EllmoHome> with TickerProviderStateMixin {
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _isProcessing = false;
  bool _ollamaConnected = false;
  String _lastResponse = "";
  String _status = "Initializing...";
  String _lastCommand = "";
  List<String> _conversationHistory = [];

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  Timer? _statusTimer;
  Timer? _connectionTimer;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeApp();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _pulseController.repeat(reverse: true);
  }

  void _initializeApp() async {
    setState(() {
      _status = "Checking Ollama connection...";
    });

    await _checkOllamaConnection();

    setState(() {
      _status = _ollamaConnected ?
          "Ready - Say 'Ellmo' to start" :
          "Ollama not available - Check logs";
    });

    // Start periodic connection checks
    _connectionTimer = Timer.periodic(Duration(seconds: 30), (_) {
      _checkOllamaConnection();
    });
  }

  Future<void> _checkOllamaConnection() async {
    try {
      final response = await http.get(
        Uri.parse('http://localhost:11434/api/tags'),
      ).timeout(Duration(seconds: 5));

      setState(() {
        _ollamaConnected = response.statusCode == 200;
      });
    } catch (e) {
      setState(() {
        _ollamaConnected = false;
      });
    }
  }

  Future<String> _sendToOllama(String message) async {
    if (!_ollamaConnected) {
      return "Ollama is not connected. Please check the service.";
    }

    try {
      final url = Uri.parse('http://localhost:11434/api/generate');
      final headers = {'Content-Type': 'application/json'};

      final body = json.encode({
        'model': 'mistral',
        'prompt': message,
        'stream': false,
        'options': {
          'temperature': 0.7,
          'top_p': 0.9,
        }
      });

      final response = await http.post(
        url,
        headers: headers,
        body: body,
      ).timeout(Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['response']?.toString().trim() ?? 'No response from AI';
      } else {
        return 'AI service returned error: ${response.statusCode}';
      }
    } catch (e) {
      return 'Failed to communicate with AI: $e';
    }
  }

  void _simulateVoiceCommand() {
    setState(() {
      _isProcessing = true;
      _status = "Processing: Hello Ellmo, how are you?";
    });

    _sendToOllama("Hello Ellmo, how are you?").then((response) {
      setState(() {
        _lastResponse = response;
        _isProcessing = false;
        _status = "Response received";
        _conversationHistory.add("User: Hello Ellmo, how are you?");
        _conversationHistory.add("Ellmo: $response");

        if (_conversationHistory.length > 10) {
          _conversationHistory = _conversationHistory.sublist(_conversationHistory.length - 10);
        }
      });
    }).catchError((error) {
      setState(() {
        _isProcessing = false;
        _status = "Error: $error";
      });
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _statusTimer?.cancel();
    _connectionTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.assistant, color: Colors.blue),
            SizedBox(width: 8),
            Text('Ellmo'),
          ],
        ),
        actions: [
          Container(
            margin: EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Icon(
                  _ollamaConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: _ollamaConnected ? Colors.green : Colors.red,
                  size: 20,
                ),
                SizedBox(width: 4),
                Text(
                  _ollamaConnected ? 'Connected' : 'Offline',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            children: [
              // Status display
              _buildStatusDisplay(),
              SizedBox(height: 30),

              // Controls
              _buildControls(),

              SizedBox(height: 20),

              // Conversation history
              Expanded(child: _buildConversationHistory()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusDisplay() {
    Color statusColor = _isProcessing ? Colors.orange :
                       _ollamaConnected ? Colors.green :
                       Colors.red;

    IconData statusIcon = _isProcessing ? Icons.psychology :
                         _ollamaConnected ? Icons.assistant :
                         Icons.error_outline;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _isProcessing ? _pulseAnimation.value : 1.0,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: statusColor, width: 3),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  statusIcon,
                  size: 80,
                  color: statusColor,
                ),
                SizedBox(height: 15),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    _status,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ElevatedButton.icon(
          onPressed: _ollamaConnected ? _simulateVoiceCommand : null,
          icon: Icon(Icons.chat),
          label: Text('Test AI'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
        ElevatedButton.icon(
          onPressed: () => _checkOllamaConnection(),
          icon: Icon(Icons.refresh),
          label: Text('Refresh'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildConversationHistory() {
    if (_conversationHistory.isEmpty) {
      return Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 64,
                color: Colors.grey,
              ),
              SizedBox(height: 16),
              Text(
                'Welcome to Ellmo!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Your AI Voice Assistant is ready.\nConversation history will appear here.',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 20),
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      'System Status',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _ollamaConnected ? Icons.check_circle : Icons.error,
                          color: _ollamaConnected ? Colors.green : Colors.red,
                          size: 16,
                        ),
                        SizedBox(width: 4),
                        Text(
                          _ollamaConnected ? 'AI Ready' : 'AI Offline',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Conversation History',
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _conversationHistory.clear();
                      _lastResponse = "";
                    });
                  },
                  icon: Icon(Icons.clear_all, size: 20),
                  tooltip: 'Clear History',
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _conversationHistory.length,
              itemBuilder: (context, index) {
                final message = _conversationHistory[index];
                final isUser = message.startsWith('User:');

                return Container(
                  margin: EdgeInsets.symmetric(horizontal: 15, vertical: 4),
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isUser ? Colors.blue.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isUser ? Colors.blue : Colors.green,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isUser ? Icons.person : Icons.assistant,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          message.substring(message.indexOf(':') + 2),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
EOF

    # Update pubspec.yaml with comprehensive configuration
    log "INFO" "Creating pubspec.yaml configuration..."
    cat > pubspec.yaml << 'EOF'
name: ellmo
description: Ellmo - AI Voice Assistant with Ollama integration

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

  fonts:
    - family: Roboto
      fonts:
        - asset: fonts/Roboto-Regular.ttf
        - asset: fonts/Roboto-Bold.ttf
          weight: 700
EOF

    # Get dependencies
    log "INFO" "Getting Flutter dependencies..."
    if flutter pub get 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Flutter dependencies resolved"
    else
        log "WARNING" "Some Flutter dependencies may have issues"
    fi

    # Build the application
    log "INFO" "Building Flutter application for Linux..."
    if flutter build linux --release 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS" "Flutter application built successfully"
    else
        log "ERROR" "Failed to build Flutter application"
        return 1
    fi

    # Verify build
    if [ -f "$INSTALL_DIR/build/linux/x64/release/bundle/ellmo" ]; then
        log "SUCCESS" "Executable created successfully"
        chmod +x "$INSTALL_DIR/build/linux/x64/release/bundle/ellmo"
    else
        log "ERROR" "Executable not found after build"
        return 1
    fi
}

# Create enhanced audio handler with comprehensive error handling
create_audio_handler() {
    progress "Creating audio handler..."

    log "INFO" "Creating Python audio handler..."
    cat > "$INSTALL_DIR/linux/audio_handler.py" << 'EOF'
#!/usr/bin/env python3

import speech_recognition as sr
import pyttsx3
import json
import sys
import time
import threading
import queue
import logging
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/ellmo/audio_handler.log'),
        logging.StreamHandler(sys.stderr)
    ]
)

class AudioHandler:
    def __init__(self):
        self.logger = logging.getLogger(__name__)
        self.logger.info("Initializing Audio Handler...")

        try:
            # Initialize speech recognition
            self.recognizer = sr.Recognizer()
            self.microphone = None
            self._init_microphone()

            # Initialize text-to-speech
            self.tts_engine = None
            self._init_tts()

            # Configuration
            self.config = self._load_config()

            self.logger.info("Audio Handler initialized successfully")

        except Exception as e:
            self.logger.error(f"Failed to initialize Audio Handler: {e}")
            raise

    def _init_microphone(self):
        """Initialize microphone with error handling"""
        try:
            # List available microphones
            mic_list = sr.Microphone.list_microphone_names()
            self.logger.info(f"Available microphones: {mic_list}")

            if not mic_list:
                self.logger.warning("No microphones detected")
                return

            # Use default microphone
            self.microphone = sr.Microphone()

            # Adjust for ambient noise
            with self.microphone as source:
                self.logger.info("Adjusting for ambient noise...")
                self.recognizer.adjust_for_ambient_noise(source, duration=2)

            self.logger.info("Microphone initialized successfully")

        except Exception as e:
            self.logger.error(f"Microphone initialization failed: {e}")
            self.microphone = None

    def _init_tts(self):
        """Initialize text-to-speech with error handling"""
        try:
            self.tts_engine = pyttsx3.init()

            # Configure TTS
            voices = self.tts_engine.getProperty('voices')
            if voices:
                # Try to find a suitable voice
                for voice in voices:
                    if 'english' in voice.name.lower() or 'polish' in voice.name.lower():
                        self.tts_engine.setProperty('voice', voice.id)
                        break

            self.tts_engine.setProperty('rate', 150)
            self.tts_engine.setProperty('volume', 0.8)

            self.logger.info("TTS engine initialized successfully")

        except Exception as e:
            self.logger.error(f"TTS initialization failed: {e}")
            self.tts_engine = None

    def _load_config(self):
        """Load configuration from file"""
        try:
            with open('/opt/ellmo/config.json', 'r') as f:
                config = json.load(f)
                self.logger.info("Configuration loaded successfully")
                return config
        except Exception as e:
            self.logger.warning(f"Failed to load config: {e}, using defaults")
            return {
                "language": "pl-PL",
                "wake_words": ["ellmo"],
                "tts_rate": 150,
                "tts_volume": 0.8,
                "audio_timeout": 5
            }

    def listen_for_speech(self, timeout=5):
        """Listen for speech with comprehensive error handling"""
        if not self.microphone:
            self.logger.error("No microphone available")
            return ""

        try:
            self.logger.debug("Starting speech recognition...")

            with self.microphone as source:
                # Listen for audio
                audio = self.recognizer.listen(
                    source,
                    timeout=timeout,
                    phrase_time_limit=10
                )

            # Try multiple recognition methods
            recognition_methods = [
                ("Google", lambda: self.recognizer.recognize_google(audio, language=self.config.get('language', 'pl-PL'))),
                ("Google (English)", lambda: self.recognizer.recognize_google(audio, language='en-US')),
            ]

            # Try Sphinx as fallback if available
            try:
                recognition_methods.append(
                    ("Sphinx", lambda: self.recognizer.recognize_sphinx(audio))
                )
            except:
                pass

            for method_name, method in recognition_methods:
                try:
                    text = method()
                    if text:
                        self.logger.info(f"Speech recognized via {method_name}: {text}")
                        return text
                except sr.UnknownValueError:
                    self.logger.debug(f"{method_name} could not understand audio")
                    continue
                except sr.RequestError as e:
                    self.logger.warning(f"{method_name} error: {e}")
                    continue

            self.logger.debug("No speech recognized")
            return ""

        except sr.WaitTimeoutError:
            self.logger.debug("Listening timeout")
            return ""
        except Exception as e:
            self.logger.error(f"Speech recognition error: {e}")
            return ""

    def speak(self, text):
        """Speak text with error handling"""
        if not self.tts_engine:
            self.logger.error("No TTS engine available")
            return

        try:
            self.logger.info(f"Speaking: {text}")

            # Update TTS settings from config
            self.tts_engine.setProperty('rate', self.config.get('tts_rate', 150))
            self.tts_engine.setProperty('volume', self.config.get('tts_volume', 0.8))

            self.tts_engine.say(text)
            self.tts_engine.runAndWait()

            self.logger.debug("Speech completed")

        except Exception as e:
            self.logger.error(f"TTS error: {e}")

    def get_status(self):
        """Get audio system status"""
        return {
            "microphone_available": self.microphone is not None,
            "tts_available": self.tts_engine is not None,
            "config_loaded": bool(self.config),
            "timestamp": datetime.now().isoformat()
        }

def main():
    """Main audio handler loop"""
    logger = logging.getLogger(__name__)
    logger.info("Starting Ellmo Audio Handler...")

    try:
        audio_handler = AudioHandler()

        # Send initial status
        status = audio_handler.get_status()
        response = {'type': 'status', 'data': status}
        print(json.dumps(response), flush=True)

        logger.info("Audio handler ready, waiting for commands...")

        while True:
            try:
                line = sys.stdin.readline().strip()
                if not line:
                    continue

                command = json.loads(line)
                logger.debug(f"Received command: {command}")

                if command['action'] == 'listen':
                    timeout = command.get('timeout', 5)
                    result = audio_handler.listen_for_speech(timeout)
                    response = {'type': 'speech_result', 'text': result}
                    print(json.dumps(response), flush=True)

                elif command['action'] == 'speak':
                    text = command.get('text', '')
                    audio_handler.speak(text)
                    response = {'type': 'speech_complete'}
                    print(json.dumps(response), flush=True)

                elif command['action'] == 'status':
                    status = audio_handler.get_status()
                    response = {'type': 'status', 'data': status}
                    print(json.dumps(response), flush=True)

                elif command['action'] == 'reload_config':
                    audio_handler.config = audio_handler._load_config()
                    response = {'type': 'config_reloaded'}
                    print(json.dumps(response), flush=True)

                else:
                    logger.warning(f"Unknown command: {command['action']}")

            except json.JSONDecodeError as e:
                logger.warning(f"Invalid JSON received: {e}")
                continue
            except KeyboardInterrupt:
                logger.info("Received interrupt signal")
                break
            except Exception as e:
                logger.error(f"Command processing error: {e}")
                error_response = {'type': 'error', 'message': str(e)}
                print(json.dumps(error_response), flush=True)

    except Exception as e:
        logger.error(f"Fatal error in audio handler: {e}")
        sys.exit(1)

    logger.info("Audio handler shutting down")

if __name__ == "__main__":
    main()
EOF

    chmod +x "$INSTALL_DIR/linux/audio_handler.py"

    log "SUCCESS" "Audio handler created with comprehensive error handling"
}

# Create configuration with validation
create_configuration() {
    progress "Creating system configuration..."

    log "INFO" "Creating application configuration..."
    cat > "$INSTALL_DIR/config.json" << EOF
{
  "ollama_host": "localhost",
  "ollama_port": 11434,
  "model": "mistral",
  "language": "pl-PL",
  "wake_words": ["ellmo"],
  "tts_rate": 150,
  "tts_volume": 0.8,
  "audio_timeout": 5,
  "auto_start": true,
  "headless_mode": false,
  "debug_mode": false,
  "log_level": "INFO",
  "backup_conversations": true,
  "max_conversation_history": 50,
  "installation_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "installation_version": "$APP_VERSION",
  "system_info": {
    "os": "$OS_NAME",
    "version": "$OS_VERSION",
    "arch": "$ARCH",
    "embedded": $EMBEDDED
  }
}
EOF

    # Create logging configuration
    log "INFO" "Creating logging configuration..."
    cat > "$INSTALL_DIR/config/logging.conf" << 'EOF'
[loggers]
keys=root,ellmo

[handlers]
keys=consoleHandler,fileHandler

[formatters]
keys=simpleFormatter,detailedFormatter

[logger_root]
level=INFO
handlers=consoleHandler

[logger_ellmo]
level=INFO
handlers=consoleHandler,fileHandler
qualname=ellmo
propagate=0

[handler_consoleHandler]
class=StreamHandler
level=WARNING
formatter=simpleFormatter
args=(sys.stdout,)

[handler_fileHandler]
class=FileHandler
level=INFO
formatter=detailedFormatter
args=('/var/log/ellmo/ellmo.log',)

[formatter_simpleFormatter]
format=%(levelname)s - %(message)s

[formatter_detailedFormatter]
format=%(asctime)s - %(name)s - %(levelname)s - %(message)s
EOF

    log "SUCCESS" "Configuration files created"
}

# Create advanced systemd service with proper dependencies
create_systemd_service() {
    progress "Creating systemd service..."

    log "INFO" "Creating systemd service unit..."
    sudo tee /etc/systemd/system/$SERVICE_NAME.service > /dev/null << EOF
[Unit]
Description=Ellmo - AI Voice Assistant
Documentation=https://github.com/ellmo/ellmo
After=graphical-session.target sound.target network-online.target ollama.service
Wants=ollama.service network-online.target
Requires=sound.target

[Service]
Type=simple
User=$USER_NAME
Group=audio
Environment=DISPLAY=:0
Environment=PULSE_RUNTIME_PATH=/run/user/$(id -u $USER_NAME)/pulse
Environment=XDG_RUNTIME_DIR=/run/user/$(id -u $USER_NAME)
Environment=HOME=/home/$USER_NAME
Environment=PATH=/opt/flutter/bin:/usr/local/bin:/usr/bin:/bin
WorkingDirectory=$INSTALL_DIR
ExecStartPre=/bin/sleep 10
ExecStart=$INSTALL_DIR/build/linux/x64/release/bundle/ellmo
ExecReload=/bin/kill -USR1 \$MAINPID
Restart=always
RestartSec=10
TimeoutStartSec=60
TimeoutStopSec=30

# Resource limits
MemoryMax=1G
CPUQuota=80%

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=$INSTALL_DIR /var/log/ellmo /tmp

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ellmo

[Install]
WantedBy=default.target
Alias=voice-assistant.service
EOF

    # Create service override directory for custom configuration
    sudo mkdir -p "/etc/systemd/system/$SERVICE_NAME.service.d"

    # Create environment override for embedded devices
    if [[ "$EMBEDDED" == "true" ]]; then
        log "INFO" "Creating embedded device service overrides..."
        sudo tee "/etc/systemd/system/$SERVICE_NAME.service.d/embedded.conf" > /dev/null << 'EOF'
[Service]
# Embedded device optimizations
MemoryMax=512M
CPUQuota=60%
Environment=FLUTTER_ENGINE_SWITCH_HEADLESS=1
EOF
    fi

    # Reload systemd and enable service
    sudo systemctl daemon-reload 2>&1 | tee -a "$LOG_FILE"
    sudo systemctl enable $SERVICE_NAME 2>&1 | tee -a "$LOG_FILE"

    log "SUCCESS" "Systemd service created and enabled"
}

# Create desktop integration
create_desktop_integration() {
    progress "Creating desktop integration..."

    # Create desktop entry
    log "INFO" "Creating desktop entry..."
    sudo tee $DESKTOP_FILE > /dev/null << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Ellmo
GenericName=AI Voice Assistant
Comment=Ellmo - AI Voice Assistant with Ollama integration
Exec=$INSTALL_DIR/build/linux/x64/release/bundle/ellmo
Icon=assistant
Terminal=false
Categories=AudioVideo;Audio;Utility;
Keywords=voice;assistant;AI;speech;
StartupNotify=true
StartupWMClass=ellmo
MimeType=
Actions=

[Desktop Action settings]
Name=Settings
Exec=$INSTALL_DIR/scripts/configure.sh
Icon=preferences-system

[Desktop Action logs]
Name=View Logs
Exec=gnome-terminal -- journalctl -u ellmo -f
Icon=utilities-log-viewer
EOF

    # Create application icon (simple text-based for now)
    sudo mkdir -p /usr/share/pixmaps

    # Create menu integration
    log "INFO" "Updating desktop database..."
    sudo update-desktop-database /usr/share/applications/ 2>/dev/null || true

    log "SUCCESS" "Desktop integration created"
}

# Configure system permissions and security
configure_permissions() {
    progress "Configuring permissions and security..."

    # Add user to required groups
    log "INFO" "Configuring user groups..."
    sudo usermod -a -G audio "$USER_NAME" 2>&1 | tee -a "$LOG_FILE"

    # Create log directory with proper permissions
    sudo mkdir -p "$LOG_DIR"
    sudo chown "$USER_NAME:$USER_NAME" "$LOG_DIR"
    sudo chmod 755 "$LOG_DIR"

    # Set application permissions
    log "INFO" "Setting application permissions..."
    sudo chown -R "$USER_NAME:$USER_NAME" "$INSTALL_DIR"
    find "$INSTALL_DIR" -type d -exec chmod 755 {} \;
    find "$INSTALL_DIR" -type f -exec chmod 644 {} \;
    chmod +x "$INSTALL_DIR/build/linux/x64/release/bundle/ellmo"
    chmod +x "$INSTALL_DIR/linux/audio_handler.py"

    # Configure PulseAudio for user service
    log "INFO" "Configuring audio system..."
    mkdir -p "/home/$USER_NAME/.config/pulse"

    if [ ! -f "/home/$USER_NAME/.config/pulse/client.conf" ]; then
        cat > "/home/$USER_NAME/.config/pulse/client.conf" << 'EOF'
# Ellmo audio configuration
autospawn = yes
default-server = unix:/run/user/1000/pulse/native
EOF
        chown "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.config/pulse/client.conf"
    fi

    # Configure udev rules for microphone access (if needed)
    if [[ "$EMBEDDED" == "true" ]]; then
        log "INFO" "Configuring embedded device audio rules..."
        sudo tee /etc/udev/rules.d/99-ellmo-audio.rules > /dev/null << 'EOF'
# Ellmo audio device rules
SUBSYSTEM=="sound", GROUP="audio", MODE="0664"
KERNEL=="controlC[0-9]*", GROUP="audio", MODE="0664"
EOF
        sudo udevadm control --reload-rules 2>/dev/null || true
    fi

    log "SUCCESS" "Permissions and security configured"
}

# Comprehensive system verification
verify_installation() {
    progress "Verifying installation..."

    local verification_passed=true

    log "INFO" "Running comprehensive installation verification..."

    # Check Flutter app
    if [ -f "$INSTALL_DIR/build/linux/x64/release/bundle/ellmo" ]; then
        log "SUCCESS" "✓ Flutter application executable found"
    else
        log "ERROR" "✗ Flutter application executable missing"
        verification_passed=false
    fi

    # Check Ollama
    if systemctl is-active --quiet ollama; then
        log "SUCCESS" "✓ Ollama service is running"

        if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
            log "SUCCESS" "✓ Ollama API is responding"
        else
            log "WARNING" "⚠ Ollama API not responding (may need time to start)"
        fi
    else
        log "WARNING" "⚠ Ollama service not running"
    fi

    # Check Python dependencies
    python3 -c "
import sys
modules = ['speech_recognition', 'pyttsx3', 'requests']
all_ok = True
for module in modules:
    try:
        __import__(module)
        print(f'✓ {module}')
    except ImportError:
        print(f'✗ {module}')
        all_ok = False
sys.exit(0 if all_ok else 1)
" 2>&1 | tee -a "$LOG_FILE"

    if [ $? -eq 0 ]; then
        log "SUCCESS" "✓ Python dependencies verified"
    else
        log "WARNING" "⚠ Some Python dependencies missing"
    fi

    # Check systemd service
    if systemctl is-enabled --quiet $SERVICE_NAME; then
        log "SUCCESS" "✓ Systemd service enabled"
    else
        log "WARNING" "⚠ Systemd service not enabled"
    fi

    # Check configuration
    if [ -f "$INSTALL_DIR/config.json" ]; then
        if python3 -c "import json; json.load(open('$INSTALL_DIR/config.json'))" 2>/dev/null; then
            log "SUCCESS" "✓ Configuration file valid"
        else
            log "ERROR" "✗ Configuration file invalid"
            verification_passed=false
        fi
    else
        log "ERROR" "✗ Configuration file missing"
        verification_passed=false
    fi

    # Check audio system
    if aplay -l >/dev/null 2>&1; then
        log "SUCCESS" "✓ Audio output devices available"
    else
        log "WARNING" "⚠ No audio output devices detected"
    fi

    if arecord -l >/dev/null 2>&1; then
        log "SUCCESS" "✓ Audio input devices available"
    else
        log "WARNING" "⚠ No audio input devices detected"
    fi

    # Check disk space after installation
    local used_space=$(du -sm "$INSTALL_DIR" | cut -f1)
    log "INFO" "Installation size: ${used_space}MB"

    # Overall verification result
    if [ "$verification_passed" = true ]; then
        log "SUCCESS" "✓ Installation verification passed"
        return 0
    else
        log "ERROR" "✗ Installation verification failed"
        return 1
    fi
}

# Generate installation report
generate_report() {
    local install_end_time=$(date +%s)
    local install_duration=$((install_end_time - INSTALL_START_TIME))

    log "INFO" "Generating installation report..."

    cat > "$INSTALL_DIR/installation_report.txt" << EOF
Ellmo Installation Report
========================
Date: $(date)
Duration: ${install_duration} seconds
User: $USER_NAME
Version: $APP_VERSION

System Information:
- OS: $OS_NAME $OS_VERSION
- Architecture: $ARCH
- Kernel: $KERNEL_VERSION
- RAM: $TOTAL_RAM
- Disk: $TOTAL_DISK
- Embedded Device: $EMBEDDED

Installation Paths:
- Application: $INSTALL_DIR
- Service: /etc/systemd/system/$SERVICE_NAME.service
- Desktop Entry: $DESKTOP_FILE
- Logs: $LOG_DIR

Components Installed:
- Flutter SDK: /opt/flutter
- Ollama: $(which ollama 2>/dev/null || echo "Not in PATH")
- Python Audio Handler: $INSTALL_DIR/linux/audio_handler.py
- Configuration: $INSTALL_DIR/config.json

Service Status:
- Ellmo Service: $(systemctl is-enabled $SERVICE_NAME 2>/dev/null)
- Ollama Service: $(systemctl is-enabled ollama 2>/dev/null)

Next Steps:
1. Start the service: sudo systemctl start $SERVICE_NAME
2. Check status: sudo systemctl status $SERVICE_NAME
3. View logs: journalctl -u $SERVICE_NAME -f
4. Test the application: Say "Ellmo" to activate

Troubleshooting:
- Configuration file: $INSTALL_DIR/config.json
- Log files: $LOG_DIR/
- Audio test: $INSTALL_DIR/linux/audio_handler.py
- Service logs: journalctl -u $SERVICE_NAME

Installation completed successfully!
EOF

    log "SUCCESS" "Installation report generated: $INSTALL_DIR/installation_report.txt"
}

# Create utility scripts
create_utility_scripts() {
    progress "Creating utility scripts..."

    # Create main utility script
    cat > "$INSTALL_DIR/scripts/ellmo-utils.sh" << 'EOF'
#!/bin/bash
# Ellmo Utility Script
# Provides easy management commands for Ellmo

SERVICE_NAME="ellmo"
INSTALL_DIR="/opt/ellmo"

case "$1" in
    start)
        echo "Starting Ellmo..."
        sudo systemctl start $SERVICE_NAME
        ;;
    stop)
        echo "Stopping Ellmo..."
        sudo systemctl stop $SERVICE_NAME
        ;;
    restart)
        echo "Restarting Ellmo..."
        sudo systemctl restart $SERVICE_NAME
        ;;
    status)
        systemctl status $SERVICE_NAME
        ;;
    logs)
        journalctl -u $SERVICE_NAME -f
        ;;
    test)
        echo "Testing Ellmo components..."
        cd $INSTALL_DIR
        python3 linux/audio_handler.py
        ;;
    config)
        ${EDITOR:-nano} $INSTALL_DIR/config.json
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs|test|config}"
        exit 1
        ;;
esac
EOF

    chmod +x "$INSTALL_DIR/scripts/ellmo-utils.sh"

    # Create symlink for global access
    sudo ln -sf "$INSTALL_DIR/scripts/ellmo-utils.sh" /usr/local/bin/ellmo

    # Create configuration script
    cat > "$INSTALL_DIR/scripts/configure.sh" << 'EOF'
#!/bin/bash
# Ellmo Configuration Script

CONFIG_FILE="/opt/ellmo/config.json"

echo "Ellmo Configuration"
echo "=================="

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Configuration file not found!"
    exit 1
fi

echo "Current configuration:"
cat "$CONFIG_FILE" | python3 -m json.tool

echo ""
echo "Would you like to edit the configuration? (y/N)"
read -r response

if [[ "$response" =~ ^[Yy]$ ]]; then
    ${EDITOR:-nano} "$CONFIG_FILE"

    echo "Restarting Ellmo to apply changes..."
    sudo systemctl restart ellmo
    echo "Done!"
fi
EOF

    chmod +x "$INSTALL_DIR/scripts/configure.sh"

    log "SUCCESS" "Utility scripts created"
}

# Parse command line arguments safely
parse_arguments() {
    ALLOW_CLEANUP="0"
    DEBUG="0"

    # Process arguments
    for arg in "$@"; do
        case $arg in
            --debug)
                DEBUG="1"
                log "INFO" "Debug mode enabled"
                ;;
            --allow-cleanup)
                ALLOW_CLEANUP="1"
                log "INFO" "Cleanup on error enabled"
                ;;
            --help|-h)
                echo "Ellmo Advanced Installer"
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --debug         Enable debug output"
                echo "  --allow-cleanup Remove incomplete installation on error"
                echo "  --help          Show this help message"
                exit 0
                ;;
            --self-test)
                echo "Running installer self-test..."
                detect_system
                check_requirements
                echo "Self-test completed successfully!"
                exit 0
                ;;
            -*)
                log "WARNING" "Unknown option: $arg"
                ;;
        esac
    done
}

# Main installation function with comprehensive error handling
main() {
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           Ellmo Installer v2.0         ║${NC}"
    echo -e "${GREEN}║     Advanced AI Voice Assistant        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo

    log "INFO" "Starting Ellmo installation..."
    log "INFO" "Installation started by user: $USER_NAME"
    log "INFO" "Installation directory: $INSTALL_DIR"
    log "INFO" "Log file: $LOG_FILE"

    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        log "ERROR" "Please do not run this installer as root"
        echo -e "${RED}Error: Do not run as root. Use your regular user account.${NC}"
        exit 1
    fi

    # Parse command line arguments
    parse_arguments "$@"

    # Execute installation steps
    detect_system
    check_requirements
    install_dependencies
    install_python_deps
    install_flutter
    install_ollama
    create_app_structure
    create_flutter_app
    create_audio_handler
    create_configuration
    configure_permissions
    create_systemd_service
    create_desktop_integration
    create_utility_scripts

    # Verify installation
    if verify_installation; then
        log "SUCCESS" "Installation verification passed"
    else
        log "WARNING" "Installation verification had issues, but continuing..."
    fi

    generate_report

    # Final success message
    local install_end_time=$(date +%s)
    local install_duration=$((install_end_time - INSTALL_START_TIME))

    echo
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     Installation Completed! 🎉         ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo

    log "SUCCESS" "Ellmo installation completed successfully in ${install_duration} seconds"

    echo -e "${CYAN}📋 Installation Summary:${NC}"
    echo -e "   • Duration: ${install_duration} seconds"
    echo -e "   • Installation Path: ${INSTALL_DIR}"
    echo -e "   • Service Name: ${SERVICE_NAME}"
    echo -e "   • Log Files: ${LOG_DIR}/"
    echo

    echo -e "${YELLOW}🚀 Next Steps:${NC}"
    echo -e "   1. ${WHITE}Start Ellmo:${NC} sudo systemctl start ellmo"
    echo -e "   2. ${WHITE}Check Status:${NC} ellmo status"
    echo -e "   3. ${WHITE}View Logs:${NC} ellmo logs"
    echo -e "   4. ${WHITE}Configure:${NC} ellmo config"
    echo

    echo -e "${BLUE}💡 Usage Tips:${NC}"
    echo -e "   • Say ${WHITE}'Ellmo'${NC} to activate voice commands"
    echo -e "   • Use ${WHITE}'ellmo --help'${NC} for management commands"
    echo -e "   • Configuration file: ${WHITE}${INSTALL_DIR}/config.json${NC}"
    echo -e "   • Full report: ${WHITE}${INSTALL_DIR}/installation_report.txt${NC}"
    echo

    echo -e "${GREEN}🎯 Ellmo is ready to be your AI voice assistant!${NC}"
    echo

    # Offer to start the service
    echo -e "${YELLOW}Would you like to start Ellmo now? (Y/n):${NC}"
    read -r start_now

    if [[ "$start_now" =~ ^[Nn]$ ]]; then
        echo -e "${BLUE}You can start Ellmo later with: ${WHITE}sudo systemctl start ellmo${NC}"
    else
        echo -e "${BLUE}Starting Ellmo...${NC}"
        if sudo systemctl start ellmo; then
            echo -e "${GREEN}✓ Ellmo started successfully!${NC}"
            echo -e "${BLUE}Check status with: ${WHITE}ellmo status${NC}"
        else
            echo -e "${YELLOW}⚠ Ellmo may need a moment to initialize. Check: ${WHITE}ellmo logs${NC}"
        fi
    fi

    log "INFO" "Installation script completed"
}

# Signal handlers for graceful shutdown
cleanup_on_interrupt() {
    log "WARNING" "Installation interrupted by user"
    echo -e "\n${YELLOW}Installation interrupted. Partial installation may remain.${NC}"

    if [[ "$ALLOW_CLEANUP" == "1" ]]; then
        cleanup_on_error
    fi

    exit 130
}

trap cleanup_on_interrupt INT TERM

# Execute main installation
main "$@"