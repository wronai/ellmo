#!/bin/bash

# Ellmo Diagnostics Installer
# Comprehensive system diagnostics and testing tool

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║      Ellmo Diagnostics Installer    ║${NC}"
echo -e "${CYAN}║   Advanced System Testing Suite     ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
echo

USER_NAME=$(whoami)
DIAGNOSTICS_DIR="/opt/ellmo/diagnostics"
ELLMO_DIR="/opt/ellmo"

# Check prerequisites
echo -e "${BLUE}🔍 Checking prerequisites...${NC}"

if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}❌ Please do not run as root${NC}"
    exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
    echo -e "${RED}❌ Flutter not found. Please install Flutter first.${NC}"
    exit 1
fi

if [ ! -d "$ELLMO_DIR" ]; then
    echo -e "${YELLOW}⚠️ Ellmo not found at $ELLMO_DIR. Creating directory...${NC}"
    sudo mkdir -p "$ELLMO_DIR"
    sudo chown -R "$USER_NAME:$USER_NAME" "$ELLMO_DIR"
fi

echo -e "${GREEN}✅ Prerequisites check passed${NC}"

# Create diagnostics project
echo -e "${BLUE}📦 Creating diagnostics project...${NC}"

sudo mkdir -p "$DIAGNOSTICS_DIR"
sudo chown -R "$USER_NAME:$USER_NAME" "$DIAGNOSTICS_DIR"
cd "$DIAGNOSTICS_DIR"

if [ ! -f "pubspec.yaml" ]; then
    flutter create . --org com.ellmo --project-name ellmo_diagnostics
fi

# Install main diagnostics app
echo -e "${BLUE}💻 Installing diagnostics application...${NC}"

cat > lib/main.dart << 'FLUTTER_APP_EOF'
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;

void main() {
  runApp(EllmoDiagnosticsApp());
}

class EllmoDiagnosticsApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ellmo Diagnostics',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Color(0xFF1E1E1E),
        cardColor: Color(0xFF2D2D2D),
      ),
      home: DiagnosticsHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class DiagnosticsHome extends StatefulWidget {
  @override
  _DiagnosticsHomeState createState() => _DiagnosticsHomeState();
}

class _DiagnosticsHomeState extends State<DiagnosticsHome> with TickerProviderStateMixin {
  late TabController _tabController;

  Map<String, dynamic> _systemStatus = {};
  List<Map<String, dynamic>> _audioDevices = [];
  List<String> _logs = [];
  Map<String, double> _audioLevels = {};

  Timer? _statusTimer;
  Timer? _audioTimer;

  bool _isTestingMicrophone = false;
  bool _isTestingSpeakers = false;
  bool _isTestingOllama = false;
  bool _isMonitoringAudio = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _initializeDiagnostics();
  }

  void _initializeDiagnostics() {
    _addLog("🚀 Starting Ellmo Diagnostics...");
    _runFullSystemCheck();
    _discoverAudioDevices();

    _statusTimer = Timer.periodic(Duration(seconds: 30), (_) => _runFullSystemCheck());
  }

  Future<void> _runFullSystemCheck() async {
    await Future.wait([
      _checkFlutter(),
      _checkOllama(),
      _checkPython(),
      _checkAudio(),
      _checkSystemResources(),
      _checkEllmoService(),
    ]);
  }

  Future<void> _checkFlutter() async {
    try {
      final result = await Process.run('flutter', ['--version']);
      final version = result.stdout.toString().split('\n')[0];

      setState(() {
        _systemStatus['flutter'] = {
          'status': 'ok',
          'version': version,
          'message': 'Flutter is available'
        };
      });
      _addLog("✅ Flutter: Available");
    } catch (e) {
      setState(() {
        _systemStatus['flutter'] = {
          'status': 'error',
          'message': 'Flutter not found: $e'
        };
      });
      _addLog("❌ Flutter: Not found");
    }
  }

  Future<void> _checkOllama() async {
    try {
      final serviceResult = await Process.run('systemctl', ['is-active', 'ollama']);
      final isRunning = serviceResult.stdout.toString().trim() == 'active';

      if (isRunning) {
        final response = await http.get(
          Uri.parse('http://localhost:11434/api/tags'),
        ).timeout(Duration(seconds: 5));

        if (response.statusCode == 200) {
          final models = json.decode(response.body)['models'] ?? [];
          setState(() {
            _systemStatus['ollama'] = {
              'status': 'ok',
              'message': 'Ollama running and accessible',
              'models': models.map((m) => m['name']).toList(),
            };
          });
          _addLog("✅ Ollama: Running with ${models.length} models");
        } else {
          setState(() {
            _systemStatus['ollama'] = {
              'status': 'warning',
              'message': 'Ollama running but API not responding'
            };
          });
          _addLog("⚠️ Ollama: API issue");
        }
      } else {
        setState(() {
          _systemStatus['ollama'] = {
            'status': 'error',
            'message': 'Ollama service not running'
          };
        });
        _addLog("❌ Ollama: Service not active");
      }
    } catch (e) {
      setState(() {
        _systemStatus['ollama'] = {
          'status': 'error',
          'message': 'Error checking Ollama: $e'
        };
      });
      _addLog("❌ Ollama: Check failed");
    }
  }

  Future<void> _checkPython() async {
    final modules = ['speech_recognition', 'pyttsx3', 'requests'];
    Map<String, bool> moduleStatus = {};

    for (String module in modules) {
      try {
        final result = await Process.run('python3', ['-c', 'import $module; print("OK")']);
        moduleStatus[module] = result.exitCode == 0;
      } catch (e) {
        moduleStatus[module] = false;
      }
    }

    final allOk = moduleStatus.values.every((status) => status);

    setState(() {
      _systemStatus['python'] = {
        'status': allOk ? 'ok' : 'warning',
        'message': allOk ? 'All Python modules available' : 'Some modules missing',
        'modules': moduleStatus
      };
    });

    _addLog(allOk ? "✅ Python: All modules OK" : "⚠️ Python: Missing modules");
  }

  Future<void> _checkAudio() async {
    try {
      final aplayResult = await Process.run('aplay', ['-l']);
      final outputDevices = _parseAudioDevices(aplayResult.stdout.toString());

      final arecordResult = await Process.run('arecord', ['-l']);
      final inputDevices = _parseAudioDevices(arecordResult.stdout.toString());

      setState(() {
        _systemStatus['audio'] = {
          'status': (outputDevices.isNotEmpty && inputDevices.isNotEmpty) ? 'ok' : 'warning',
          'message': 'Audio: ${outputDevices.length} output, ${inputDevices.length} input',
          'output_devices': outputDevices.length,
          'input_devices': inputDevices.length
        };
      });

      _addLog("✅ Audio: ${outputDevices.length} out, ${inputDevices.length} in");
    } catch (e) {
      setState(() {
        _systemStatus['audio'] = {
          'status': 'error',
          'message': 'Audio system check failed'
        };
      });
      _addLog("❌ Audio: Check failed");
    }
  }

  Future<void> _checkSystemResources() async {
    try {
      final memResult = await Process.run('free', ['-m']);
      final memLines = memResult.stdout.toString().split('\n');
      final memData = memLines[1].split(RegExp(r'\s+'));
      final totalMem = int.parse(memData[1]);
      final usedMem = int.parse(memData[2]);
      final memPercent = (usedMem / totalMem * 100).round();

      final dfResult = await Process.run('df', ['-h', '/']);
      final dfLines = dfResult.stdout.toString().split('\n');
      final dfData = dfLines[1].split(RegExp(r'\s+'));
      final diskUse = dfData[4].replaceAll('%', '');

      setState(() {
        _systemStatus['resources'] = {
          'status': (memPercent < 80 && int.parse(diskUse) < 90) ? 'ok' : 'warning',
          'memory_percent': memPercent,
          'disk_percent': int.parse(diskUse),
          'total_memory_mb': totalMem
        };
      });

      _addLog("📊 Resources: RAM ${memPercent}%, Disk ${diskUse}%");
    } catch (e) {
      _addLog("❌ Resources: Check failed");
    }
  }

  Future<void> _checkEllmoService() async {
    try {
      final systemResult = await Process.run('systemctl', ['is-active', 'ellmo']);
      final systemActive = systemResult.stdout.toString().trim() == 'active';

      final userResult = await Process.run('systemctl', ['--user', 'is-active', 'ellmo']);
      final userActive = userResult.stdout.toString().trim() == 'active';

      final executableExists = await File('/opt/ellmo/build/linux/x64/release/bundle/ellmo').exists();

      setState(() {
        _systemStatus['ellmo_service'] = {
          'status': (systemActive || userActive) ? 'ok' : 'warning',
          'system_service': systemActive,
          'user_service': userActive,
          'executable_exists': executableExists,
          'message': systemActive ? 'System service active' :
                    userActive ? 'User service active' : 'No service running'
        };
      });

      _addLog("🔧 Ellmo: ${systemActive ? 'System' : userActive ? 'User' : 'None'} active");
    } catch (e) {
      _addLog("❌ Ellmo: Check failed");
    }
  }

  Future<void> _discoverAudioDevices() async {
    List<Map<String, dynamic>> devices = [];

    try {
      final paResult = await Process.run('pactl', ['list', 'sinks', 'short']);
      final sinks = paResult.stdout.toString().split('\n').where((line) => line.isNotEmpty);

      for (String sink in sinks) {
        final parts = sink.split('\t');
        if (parts.length >= 2) {
          devices.add({
            'id': parts[0],
            'name': parts[1],
            'type': 'output',
            'driver': 'pulseaudio',
            'level': 0.0,
          });
        }
      }

      final sourceResult = await Process.run('pactl', ['list', 'sources', 'short']);
      final sources = sourceResult.stdout.toString().split('\n').where((line) => line.isNotEmpty);

      for (String source in sources) {
        final parts = source.split('\t');
        if (parts.length >= 2 && !parts[1].contains('monitor')) {
          devices.add({
            'id': parts[0],
            'name': parts[1],
            'type': 'input',
            'driver': 'pulseaudio',
            'level': 0.0,
          });
        }
      }
    } catch (e) {
      _addLog("⚠️ PulseAudio discovery failed");
    }

    setState(() {
      _audioDevices = devices;
    });

    _addLog("🎵 Found ${devices.length} audio devices");
  }

  List<String> _parseAudioDevices(String output) {
    final devices = <String>[];
    final lines = output.split('\n');

    for (String line in lines) {
      if (line.contains('card') && line.contains('device')) {
        final match = RegExp(r'\[(.*?)\]').firstMatch(line);
        if (match != null) {
          devices.add(match.group(1)!);
        }
      }
    }

    return devices;
  }

  void _startAudioMonitoring() {
    if (_isMonitoringAudio) return;

    setState(() {
      _isMonitoringAudio = true;
    });

    _addLog("🎤 Starting audio monitoring...");

    _audioTimer = Timer.periodic(Duration(milliseconds: 500), (timer) async {
      for (var device in _audioDevices) {
        final level = Random().nextDouble() * 0.5; // Simulated for demo
        setState(()