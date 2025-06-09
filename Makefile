# Ellmo - AI Voice Assistant Makefile
# Ułatwia zarządzanie projektem na różnych platformach

# Zmienne
APP_NAME = ellmo
INSTALL_DIR = /opt/$(APP_NAME)
SERVICE_NAME = ellmo
USER_NAME = $(shell whoami)

# Kolory dla outputu
RED = \033[0;31m
GREEN = \033[0;32m
YELLOW = \033[1;33m
BLUE = \033[0;34m
NC = \033[0m # No Color

# Domyślny target
.DEFAULT_GOAL := help

# Help
.PHONY: help
help:
	@echo "$(BLUE)Ellmo - AI Voice Assistant - Makefile Commands$(NC)"
	@echo ""
	@echo "$(GREEN)Installation:$(NC)"
	@echo "  install          Full installation of Ellmo"GREEN)Installation:$(NC)"
	@echo "  install          Full installation of the system"
	@echo "  install-deps     Install only system dependencies"
	@echo "  install-flutter  Install only Flutter SDK"
	@echo "  install-ollama   Install only Ollama"
	@echo ""
	@echo "$(GREEN)Development:$(NC)"
	@echo "  build           Build the Flutter application"
	@echo "  dev             Run in development mode"
	@echo "  test            Run tests"
	@echo "  clean           Clean build artifacts"
	@echo "  format          Format code"
	@echo ""
	@echo "$(GREEN)Service Management:$(NC)"
	@echo "  start           Start the voice assistant service"
	@echo "  stop            Stop the voice assistant service"
	@echo "  restart         Restart the voice assistant service"
	@echo "  status          Show service status"
	@echo "  logs            Show service logs"
	@echo "  enable          Enable autostart"
	@echo "  disable         Disable autostart"
	@echo ""
	@echo "$(GREEN)Configuration:$(NC)"
	@echo "  config          Interactive configuration"
	@echo "  config-show     Show current configuration"
	@echo "  config-reset    Reset configuration to defaults"
	@echo ""
	@echo "$(GREEN)Maintenance:$(NC)"
	@echo "  update          Update the application"
	@echo "  backup          Create system backup"
	@echo "  restore         Restore from backup"
	@echo "  uninstall       Completely remove the system"
	@echo ""
	@echo "$(GREEN)Testing & Diagnostics:$(NC)"
	@echo "  check           Run system checks"
	@echo "  test-audio      Test audio system"
	@echo "  test-ollama     Test Ollama connection"
	@echo "  monitor         Monitor system performance"
	@echo "  doctor          Run full system diagnostics"

# Installation targets
.PHONY: install install-deps install-flutter install-ollama
install:
	@echo "$(BLUE)Starting full installation...$(NC)"
	@chmod +x install.sh
	@./install.sh

install-deps:
	@echo "$(BLUE)Installing system dependencies...$(NC)"
	@if command -v dnf >/dev/null 2>&1; then \
		sudo dnf update -y && \
		sudo dnf install -y curl wget git unzip xz cmake ninja-build clang gtk3-devel pkgconf-devel alsa-lib-devel pulseaudio-libs-devel espeak-ng python3 python3-pip; \
	elif command -v apt >/dev/null 2>&1; then \
		sudo apt update && \
		sudo apt install -y curl wget git unzip xz-utils cmake ninja-build clang libgtk-3-dev pkg-config libasound2-dev libpulse-dev espeak-ng python3 python3-pip; \
	elif command -v pacman >/dev/null 2>&1; then \
		sudo pacman -Syu --noconfirm && \
		sudo pacman -S --noconfirm curl wget git unzip xz cmake ninja clang gtk3 pkgconf alsa-lib pulseaudio espeak-ng python3 python3-pip; \
	fi
	@pip3 install --user speechrecognition pyttsx3 pyaudio requests websocket-client
	@echo "$(GREEN)✓ Dependencies installed$(NC)"

install-flutter:
	@echo "$(BLUE)Installing Flutter...$(NC)"
	@if [ ! -d "/opt/flutter" ]; then \
		cd /tmp && \
		wget https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.19.0-stable.tar.xz && \
		sudo tar xf flutter_linux_3.19.0-stable.tar.xz -C /opt/ && \
		sudo chown -R $(USER_NAME):$(USER_NAME) /opt/flutter; \
	fi
	@if ! grep -q "flutter/bin" ~/.bashrc; then \
		echo 'export PATH="$$PATH:/opt/flutter/bin"' >> ~/.bashrc; \
	fi
	@export PATH="$$PATH:/opt/flutter/bin" && flutter config --enable-linux-desktop
	@echo "$(GREEN)✓ Flutter installed$(NC)"

install-ollama:
	@echo "$(BLUE)Installing Ollama...$(NC)"
	@curl -fsSL https://ollama.ai/install.sh | sh
	@sudo systemctl enable ollama
	@sudo systemctl start ollama
	@sleep 5
	@ollama pull mistral
	@echo "$(GREEN)✓ Ollama installed$(NC)"

# Development targets
.PHONY: build dev test clean format
build:
	@echo "$(BLUE)Building Flutter application...$(NC)"
	@cd $(INSTALL_DIR) && flutter build linux --release
	@echo "$(GREEN)✓ Build completed$(NC)"

dev:
	@echo "$(BLUE)Running in development mode...$(NC)"
	@cd $(INSTALL_DIR) && flutter run -d linux

test:
	@echo "$(BLUE)Running tests...$(NC)"
	@cd $(INSTALL_DIR) && flutter test

clean:
	@echo "$(BLUE)Cleaning build artifacts...$(NC)"
	@cd $(INSTALL_DIR) && flutter clean
	@echo "$(GREEN)✓ Clean completed$(NC)"

format:
	@echo "$(BLUE)Formatting code...$(NC)"
	@cd $(INSTALL_DIR) && flutter format .
	@echo "$(GREEN)✓ Code formatted$(NC)"

# Service management targets
.PHONY: start stop restart status logs enable disable
start:
	@echo "$(BLUE)Starting Ellmo...$(NC)"
	@sudo systemctl start $(SERVICE_NAME)
	@sleep 2
	@sudo systemctl status $(SERVICE_NAME) --no-pager

stop:
	@echo "$(BLUE)Stopping Ellmo...$(NC)"
	@sudo systemctl stop $(SERVICE_NAME)
	@echo "$(GREEN)✓ Service stopped$(NC)"

restart:
	@echo "$(BLUE)Restarting Ellmo...$(NC)"
	@sudo systemctl restart $(SERVICE_NAME)
	@sleep 2
	@sudo systemctl status $(SERVICE_NAME) --no-pager

status:
	@echo "$(BLUE)Ellmo Status:$(NC)"
	@sudo systemctl status $(SERVICE_NAME) --no-pager
	@echo ""
	@echo "$(BLUE)Ollama Status:$(NC)"
	@sudo systemctl status ollama --no-pager

logs:
	@echo "$(BLUE)Showing logs (Ctrl+C to exit):$(NC)"
	@journalctl -u $(SERVICE_NAME) -f

enable:
	@echo "$(BLUE)Enabling autostart...$(NC)"
	@sudo systemctl enable $(SERVICE_NAME)
	@echo "$(GREEN)✓ Autostart enabled$(NC)"

disable:
	@echo "$(BLUE)Disabling autostart...$(NC)"
	@sudo systemctl disable $(SERVICE_NAME) 2>/dev/null || true
	@sudo rm -f /etc/systemd/system/$(SERVICE_NAME).service
	@sudo systemctl daemon-reload
	@sudo rm -f /usr/share/applications/$(SERVICE_NAME).desktop
	@sudo rm -rf $(INSTALL_DIR)
	@sed -i '/flutter/d' ~/.bashrc 2>/dev/null || true
	@echo "$(GREEN)✓ Voice assistant uninstalled$(NC)"

# Testing & Diagnostics targets
.PHONY: check test-audio test-ollama monitor doctor
check:
	@echo "$(BLUE)Running system checks...$(NC)"
	@if [ -f "$(INSTALL_DIR)/start.sh" ]; then \
		$(INSTALL_DIR)/start.sh --check; \
	else \
		echo "$(RED)Application not installed$(NC)"; \
	fi

test-audio:
	@echo "$(BLUE)Testing audio system...$(NC)"
	@echo "$(YELLOW)Testing audio output...$(NC)"
	@if command -v speaker-test >/dev/null 2>&1; then \
		timeout 3 speaker-test -t sine -f 1000 -l 1 2>/dev/null || true; \
	fi
	@echo "$(YELLOW)Testing text-to-speech...$(NC)"
	@if command -v espeak-ng >/dev/null 2>&1; then \
		espeak-ng "Audio test successful" 2>/dev/null || true; \
	fi
	@echo "$(YELLOW)Testing microphone...$(NC)"
	@if command -v arecord >/dev/null 2>&1; then \
		echo "Recording 3 seconds..." && \
		timeout 3 arecord -d 3 -f cd /tmp/test_audio.wav 2>/dev/null || true && \
		rm -f /tmp/test_audio.wav; \
	fi
	@echo "$(GREEN)✓ Audio tests completed$(NC)"

test-ollama:
	@echo "$(BLUE)Testing Ollama connection...$(NC)"
	@if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then \
		echo "$(GREEN)✓ Ollama is responding$(NC)"; \
		echo "$(BLUE)Available models:$(NC)"; \
		ollama list; \
	else \
		echo "$(RED)✗ Ollama is not responding$(NC)"; \
		echo "$(YELLOW)Try: sudo systemctl start ollama$(NC)"; \
	fi

monitor:
	@echo "$(BLUE)Monitoring system (Ctrl+C to exit)...$(NC)"
	@if [ -f "utils.sh" ]; then \
		./utils.sh monitor; \
	else \
		watch -n 2 'echo "=== System Status ===" && \
		systemctl is-active $(SERVICE_NAME) && \
		systemctl is-active ollama && \
		echo "=== Resources ===" && \
		ps aux | grep -E "(ellmo|ollama)" | grep -v grep'; \
	fi

doctor:
	@echo "$(BLUE)Running full system diagnostics...$(NC)"
	@echo ""
	@echo "$(BLUE)=== System Information ===$(NC)"
	@echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'\"' -f2)"
	@echo "Architecture: $(uname -m)"
	@echo "Kernel: $(uname -r)"
	@echo ""
	@echo "$(BLUE)=== Flutter Status ===$(NC)"
	@if command -v flutter >/dev/null 2>&1; then \
		echo "$(GREEN)✓ Flutter installed$(NC)"; \
		flutter --version | head -1; \
	else \
		echo "$(RED)✗ Flutter not found$(NC)"; \
	fi
	@echo ""
	@echo "$(BLUE)=== Ollama Status ===$(NC)"
	@if command -v ollama >/dev/null 2>&1; then \
		echo "$(GREEN)✓ Ollama installed$(NC)"; \
		if systemctl is-active --quiet ollama; then \
			echo "$(GREEN)✓ Ollama service running$(NC)"; \
		else \
			echo "$(RED)✗ Ollama service not running$(NC)"; \
		fi; \
	else \
		echo "$(RED)✗ Ollama not found$(NC)"; \
	fi
	@echo ""
	@echo "$(BLUE)=== Audio System ===$(NC)"
	@if command -v pulseaudio >/dev/null 2>&1; then \
		echo "$(GREEN)✓ PulseAudio available$(NC)"; \
	fi
	@if command -v aplay >/dev/null 2>&1; then \
		echo "$(GREEN)✓ ALSA available$(NC)"; \
	fi
	@if [ -c /dev/snd/controlC0 ]; then \
		echo "$(GREEN)✓ Audio devices detected$(NC)"; \
	else \
		echo "$(YELLOW)⚠ No audio devices found$(NC)"; \
	fi
	@echo ""
	@echo "$(BLUE)=== Python Dependencies ===$(NC)"
	@python3 -c "
import sys
modules = ['speech_recognition', 'pyttsx3', 'requests', 'json']
for module in modules:
    try:
        __import__(module)
        print('$(GREEN)✓$(NC) ' + module)
    except ImportError:
        print('$(RED)✗$(NC) ' + module)
" 2>/dev/null
	@echo ""
	@echo "$(BLUE)=== Ellmo Status ===$(NC)"
	@if systemctl is-active --quiet $(SERVICE_NAME); then \
		echo "$(GREEN)✓ Ellmo service running$(NC)"; \
	else \
		echo "$(RED)✗ Ellmo service not running$(NC)"; \
	fi
	@echo ""
	@echo "$(BLUE)=== Configuration ===$(NC)"
	@if [ -f "$(INSTALL_DIR)/config.json" ]; then \
		echo "$(GREEN)✓ Configuration file exists$(NC)"; \
	else \
		echo "$(YELLOW)⚠ No configuration file$(NC)"; \
	fi
	@echo ""
	@echo "$(BLUE)=== Disk Space ===$(NC)"
	@df -h $(INSTALL_DIR) 2>/dev/null || df -h /
	@echo ""
	@echo "$(BLUE)=== Memory Usage ===$(NC)"
	@free -h
	@echo ""
	@echo "$(GREEN)Diagnostics completed$(NC)"

# Advanced targets
.PHONY: setup-dev install-dev-tools benchmark performance-tune
setup-dev:
	@echo "$(BLUE)Setting up development environment...$(NC)"
	@if [ ! -d ".git" ]; then \
		git init; \
		echo "$(GREEN)✓ Git repository initialized$(NC)"; \
	fi
	@if [ ! -f ".gitignore" ]; then \
		echo "build/\n*.log\n.dart_tool/\n.packages\npubspec.lock" > .gitignore; \
		echo "$(GREEN)✓ .gitignore created$(NC)"; \
	fi
	@echo "$(GREEN)✓ Development environment ready$(NC)"

install-dev-tools:
	@echo "$(BLUE)Installing development tools...$(NC)"
	@if command -v flutter >/dev/null 2>&1; then \
		flutter pub global activate devtools; \
		flutter pub global activate flutter_launcher_icons; \
		echo "$(GREEN)✓ Flutter dev tools installed$(NC)"; \
	fi
	@pip3 install --user black pylint mypy
	@echo "$(GREEN)✓ Python dev tools installed$(NC)"

benchmark:
	@echo "$(BLUE)Running performance benchmark...$(NC)"
	@echo "Starting benchmark in 3 seconds..."
	@sleep 3
	@echo "$(YELLOW)CPU Stress Test (10 seconds)...$(NC)"
	@timeout 10 yes > /dev/null 2>&1 || true
	@echo "$(YELLOW)Memory Usage:$(NC)"
	@ps aux | grep -E "(flutter_voice|ollama)" | grep -v grep | awk '{print $11 " - CPU: " $3 "% MEM: " $4 "%"}'
	@echo "$(GREEN)✓ Benchmark completed$(NC)"

performance-tune:
	@echo "$(BLUE)Applying performance optimizations...$(NC)"
	@echo "$(YELLOW)Checking system type...$(NC)"
	@if grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then \
		echo "$(YELLOW)Raspberry Pi detected - applying optimizations...$(NC)"; \
		echo "# Voice Assistant optimizations" | sudo tee -a /boot/config.txt >/dev/null; \
		echo "gpu_mem=128" | sudo tee -a /boot/config.txt >/dev/null; \
		echo "$(GREEN)✓ GPU memory optimized$(NC)"; \
	fi
	@echo "$(YELLOW)Optimizing systemd service...$(NC)"
	@if [ -f "/etc/systemd/system/$(SERVICE_NAME).service" ]; then \
		sudo sed -i '/\[Service\]/a CPUQuota=80%' /etc/systemd/system/$(SERVICE_NAME).service; \
		sudo sed -i '/\[Service\]/a MemoryMax=1G' /etc/systemd/system/$(SERVICE_NAME).service; \
		sudo systemctl daemon-reload; \
		echo "$(GREEN)✓ Service limits applied$(NC)"; \
	fi

# Package targets
.PHONY: package package-deb package-rpm create-installer
package:
	@echo "$(BLUE)Creating distribution package...$(NC)"
	@mkdir -p dist
	@tar -czf dist/$(APP_NAME)-$(shell date +%Y%m%d).tar.gz \
		install.sh utils.sh start.sh Makefile README.md \
		--exclude='.git' --exclude='dist' .
	@echo "$(GREEN)✓ Package created: dist/$(APP_NAME)-$(shell date +%Y%m%d).tar.gz$(NC)"

package-deb:
	@echo "$(BLUE)Creating .deb package...$(NC)"
	@mkdir -p dist/deb/DEBIAN
	@mkdir -p dist/deb/opt/$(APP_NAME)
	@mkdir -p dist/deb/etc/systemd/system
	@echo "Package: $(APP_NAME)" > dist/deb/DEBIAN/control
	@echo "Version: 1.0.0" >> dist/deb/DEBIAN/control
	@echo "Section: utils" >> dist/deb/DEBIAN/control
	@echo "Priority: optional" >> dist/deb/DEBIAN/control
	@echo "Architecture: amd64" >> dist/deb/DEBIAN/control
	@echo "Maintainer: Voice Assistant Team" >> dist/deb/DEBIAN/control
	@echo "Description: AI Voice Assistant with Ollama integration" >> dist/deb/DEBIAN/control
	@cp -r . dist/deb/opt/$(APP_NAME)/ --exclude=dist --exclude=.git
	@dpkg-deb --build dist/deb dist/$(APP_NAME).deb
	@echo "$(GREEN)✓ .deb package created$(NC)"

create-installer:
	@echo "$(BLUE)Creating standalone installer...$(NC)"
	@cat > dist/install-standalone.sh << 'EOF'
#!/bin/bash
# Standalone installer - extracts and runs installation
ARCHIVE_START=$(awk '/^__ARCHIVE_BELOW__$/{print NR + 1; exit 0; }' $0)
tail -n+$ARCHIVE_START $0 | tar xzf -
cd flutter-voice-assistant
chmod +x install.sh
./install.sh
exit 0
__ARCHIVE_BELOW__
EOF
	@tar czf - . --exclude=dist --exclude=.git | cat dist/install-standalone.sh - > dist/install-standalone.sh.tmp
	@mv dist/install-standalone.sh.tmp dist/install-standalone.sh
	@chmod +x dist/install-standalone.sh
	@echo "$(GREEN)✓ Standalone installer created: dist/install-standalone.sh$(NC)"

# Help for specific targets
.PHONY: help-dev help-service help-config
help-dev:
	@echo "$(BLUE)Development Commands:$(NC)"
	@echo "  make dev             - Run Flutter app in development mode"
	@echo "  make build           - Build release version"
	@echo "  make test            - Run all tests"
	@echo "  make clean           - Clean build artifacts"
	@echo "  make format          - Format all code"
	@echo "  make setup-dev       - Initialize development environment"
	@echo "  make install-dev-tools - Install development tools"

help-service:
	@echo "$(BLUE)Service Management Commands:$(NC)"
	@echo "  make start           - Start the service"
	@echo "  make stop            - Stop the service"
	@echo "  make restart         - Restart the service"
	@echo "  make status          - Show service status"
	@echo "  make logs            - Show live logs"
	@echo "  make enable          - Enable autostart"
	@echo "  make disable         - Disable autostart"

help-config:
	@echo "$(BLUE)Configuration Commands:$(NC)"
	@echo "  make config          - Interactive configuration"
	@echo "  make config-show     - Display current config"
	@echo "  make config-reset    - Reset to defaults"

# Install git hooks
.PHONY: install-hooks
install-hooks:
	@echo "$(BLUE)Installing git hooks...$(NC)"
	@mkdir -p .git/hooks
	@echo '#!/bin/bash\nmake format' > .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit
	@echo "$(GREEN)✓ Git hooks installed$(NC)"

# Cleanup temporary files
.PHONY: clean-all
clean-all: clean
	@echo "$(BLUE)Cleaning all temporary files...$(NC)"
	@rm -rf dist/
	@rm -f /tmp/voice_assistant_*
	@rm -f /tmp/test_audio.wav
	@echo "$(GREEN)✓ All cleanup completed$(NC)")
	@echo "$(GREEN)✓ Autostart disabled$(NC)"

# Configuration targets
.PHONY: config config-show config-reset
config:
	@echo "$(BLUE)Opening configuration...$(NC)"
	@if [ -f "utils.sh" ]; then ./utils.sh configure; else echo "$(RED)utils.sh not found$(NC)"; fi

config-show:
	@echo "$(BLUE)Current Configuration:$(NC)"
	@if [ -f "$(INSTALL_DIR)/config.json" ]; then \
		cat $(INSTALL_DIR)/config.json | python3 -m json.tool; \
	else \
		echo "$(YELLOW)No configuration file found$(NC)"; \
	fi

config-reset:
	@echo "$(BLUE)Resetting configuration to defaults...$(NC)"
	@sudo rm -f $(INSTALL_DIR)/config.json
	@echo "$(GREEN)✓ Configuration reset$(NC)"

# Maintenance targets
.PHONY: update backup restore uninstall
update:
	@echo "$(BLUE)Updating application...$(NC)"
	@sudo systemctl stop $(SERVICE_NAME)
	@if [ -d "$(INSTALL_DIR).backup" ]; then sudo rm -rf $(INSTALL_DIR).backup; fi
	@sudo cp -r $(INSTALL_DIR) $(INSTALL_DIR).backup
	@cd $(INSTALL_DIR) && flutter upgrade && flutter pub get && flutter build linux --release
	@sudo systemctl start $(SERVICE_NAME)
	@echo "$(GREEN)✓ Update completed$(NC)"

backup:
	@echo "$(BLUE)Creating backup...$(NC)"
	@BACKUP_NAME="voice_assistant_backup_$(shell date +%Y%m%d_%H%M%S)" && \
	sudo tar -czf /tmp/$$BACKUP_NAME.tar.gz $(INSTALL_DIR) /etc/systemd/system/$(SERVICE_NAME).service && \
	echo "$(GREEN)✓ Backup created: /tmp/$$BACKUP_NAME.tar.gz$(NC)"

restore:
	@echo "$(BLUE)Available backups:$(NC)"
	@ls -la /tmp/voice_assistant_backup_*.tar.gz 2>/dev/null || echo "$(YELLOW)No backups found$(NC)"
	@echo "$(YELLOW)Please specify backup file manually$(NC)"

uninstall:
	@echo "$(RED)This will completely remove the voice assistant$(NC)"
	@echo "$(YELLOW)Are you sure? [y/N]$(NC)" && read ans && [ $${ans:-N} = y ]
	@echo "$(BLUE)Uninstalling...$(NC)"
	@sudo systemctl stop $(SERVICE_NAME) 2>/dev/null || true
	@sudo systemctl disable $(SERVICE_NAME) 2>/dev/null || true
	@sudo rm -rf $(INSTALL_DIR)
	@sudo rm -f /etc/systemd/system/$(SERVICE_NAME).service
	@echo "$(GREEN)✓ Uninstall completed$(NC)"