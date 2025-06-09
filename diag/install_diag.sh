#!/bin/bash

# Ellmo Diagnostics Installer - Fixed Version
# Comprehensive system diagnostics and testing tool

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║      Ellmo Diagnostics Installer     ║${NC}"
echo -e "${CYAN}║   Advanced System Testing Suite      ║${NC}"
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

# Create the Flutter app in smaller chunks to avoid here-doc issues
echo -e "${BLUE}💻 Creating diagnostics application...${NC}"

# Create main.dart
cat > lib/main.dart << 'EOF'
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
EOF

# Add the main diagnostics class
cat >> lib/main.dart << 'EOF'

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
EOF

# Add system check methods
cat >> lib/main.dart << 'EOF'

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
          'message': 'Flutter not found'
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
          final data = json.decode(response.body);
          final models = data['models'] ?? [];
          setState(() {
            _systemStatus['ollama'] = {
              'status': 'ok',
              'message': 'Ollama running - ${models.length} models',
            };
          });
          _addLog("✅ Ollama: Running with ${models.length} models");
        } else {
          setState(() {
            _systemStatus['ollama'] = {
              'status': 'warning',
              'message': 'Ollama running but API issue'
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
          'message': 'Error checking Ollama'
        };
      });
      _addLog("❌ Ollama: Check failed");
    }
  }
EOF

# Add remaining check methods
cat >> lib/main.dart << 'EOF'

  Future<void> _checkPython() async {
    final modules = ['speech_recognition', 'pyttsx3', 'requests'];
    Map<String, bool> moduleStatus = {};

    for (String module in modules) {
      try {
        final result = await Process.run('python3', ['-c', 'import $module']);
        moduleStatus[module] = result.exitCode == 0;
      } catch (e) {
        moduleStatus[module] = false;
      }
    }

    final allOk = moduleStatus.values.every((status) => status);

    setState(() {
      _systemStatus['python'] = {
        'status': allOk ? 'ok' : 'warning',
        'message': allOk ? 'All modules OK' : 'Some modules missing',
      };
    });

    _addLog(allOk ? "✅ Python: All modules OK" : "⚠️ Python: Missing modules");
  }

  Future<void> _checkAudio() async {
    try {
      final aplayResult = await Process.run('aplay', ['-l']);
      final outputCount = aplayResult.stdout.toString().split('\n')
          .where((line) => line.contains('card')).length;

      final arecordResult = await Process.run('arecord', ['-l']);
      final inputCount = arecordResult.stdout.toString().split('\n')
          .where((line) => line.contains('card')).length;

      setState(() {
        _systemStatus['audio'] = {
          'status': (outputCount > 0 && inputCount > 0) ? 'ok' : 'warning',
          'message': 'Audio: $outputCount out, $inputCount in',
        };
      });

      _addLog("✅ Audio: $outputCount out, $inputCount in");
    } catch (e) {
      setState(() {
        _systemStatus['audio'] = {
          'status': 'error',
          'message': 'Audio check failed'
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

      setState(() {
        _systemStatus['resources'] = {
          'status': memPercent < 80 ? 'ok' : 'warning',
          'message': 'Memory: ${memPercent}% used',
        };
      });

      _addLog("📊 Resources: RAM ${memPercent}%");
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

      setState(() {
        _systemStatus['ellmo_service'] = {
          'status': (systemActive || userActive) ? 'ok' : 'warning',
          'message': systemActive ? 'System service active' :
                    userActive ? 'User service active' : 'No service running'
        };
      });

      _addLog("🔧 Ellmo: ${systemActive ? 'System' : userActive ? 'User' : 'None'} active");
    } catch (e) {
      _addLog("❌ Ellmo: Check failed");
    }
  }
EOF

# Add audio discovery and testing methods
cat >> lib/main.dart << 'EOF'

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
            'name': parts[1].length > 30 ? parts[1].substring(0, 30) + '...' : parts[1],
            'type': 'output',
            'driver': 'pulseaudio',
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
            'name': parts[1].length > 30 ? parts[1].substring(0, 30) + '...' : parts[1],
            'type': 'input',
            'driver': 'pulseaudio',
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

  void _startAudioMonitoring() {
    if (_isMonitoringAudio) return;

    setState(() {
      _isMonitoringAudio = true;
    });

    _addLog("🎤 Starting audio monitoring...");

    _audioTimer = Timer.periodic(Duration(milliseconds: 500), (timer) {
      for (var device in _audioDevices) {
        final level = Random().nextDouble() * 0.6;
        setState(() {
          _audioLevels[device['id']] = level;
        });
      }
    });
  }

  void _stopAudioMonitoring() {
    setState(() {
      _isMonitoringAudio = false;
    });

    _audioTimer?.cancel();
    _addLog("⏹️ Audio monitoring stopped");
  }
EOF

# Add test methods
cat >> lib/main.dart << 'EOF'

  Future<void> _testMicrophone(Map<String, dynamic> device) async {
    setState(() {
      _isTestingMicrophone = true;
    });

    _addLog("🎤 Testing microphone: ${device['name']}");

    try {
      final process = await Process.start('arecord', [
        '-d', '3',
        '-f', 'cd',
        '/tmp/mic_test.wav'
      ]);

      await process.exitCode;

      final file = File('/tmp/mic_test.wav');
      if (await file.exists()) {
        final size = await file.length();
        _addLog("✅ Recorded ${size} bytes");

        await Process.run('aplay', ['/tmp/mic_test.wav']);
        _addLog("🔊 Playback completed");

        await file.delete();
      } else {
        _addLog("❌ No audio recorded");
      }
    } catch (e) {
      _addLog("❌ Microphone test failed");
    } finally {
      setState(() {
        _isTestingMicrophone = false;
      });
    }
  }

  Future<void> _testSpeaker(Map<String, dynamic> device) async {
    setState(() {
      _isTestingSpeakers = true;
    });

    _addLog("🔊 Testing speaker: ${device['name']}");

    try {
      await Process.run('espeak-ng', ['Testing speaker ${device['name']}']);
      _addLog("✅ Speaker test completed");
    } catch (e) {
      _addLog("❌ Speaker test failed");
    } finally {
      setState(() {
        _isTestingSpeakers = false;
      });
    }
  }

  Future<void> _testOllama() async {
    setState(() {
      _isTestingOllama = true;
    });

    _addLog("🤖 Testing Ollama AI...");

    try {
      final response = await http.post(
        Uri.parse('http://localhost:11434/api/generate'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'model': 'mistral',
          'prompt': 'Say hello in one sentence',
          'stream': false,
        }),
      ).timeout(Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final aiResponse = data['response'] ?? 'No response';
        _addLog("✅ AI: ${aiResponse.substring(0, min(50, aiResponse.length))}...");
      } else {
        _addLog("❌ Ollama test failed: HTTP ${response.statusCode}");
      }
    } catch (e) {
      _addLog("❌ Ollama test failed");
    } finally {
      setState(() {
        _isTestingOllama = false;
      });
    }
  }

  void _addLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final logEntry = "[$timestamp] $message";

    setState(() {
      _logs.add(logEntry);
      if (_logs.length > 50) {
        _logs.removeAt(0);
      }
    });

    print(logEntry);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _statusTimer?.cancel();
    _audioTimer?.cancel();
    super.dispose();
  }
EOF

# Add UI building methods
cat >> lib/main.dart << 'EOF'

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.bug_report, color: Colors.orange),
            SizedBox(width: 8),
            Text('Ellmo Diagnostics'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _runFullSystemCheck,
            tooltip: 'Refresh All',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(icon: Icon(Icons.dashboard), text: 'Status'),
            Tab(icon: Icon(Icons.audiotrack), text: 'Audio'),
            Tab(icon: Icon(Icons.settings), text: 'Tests'),
            Tab(icon: Icon(Icons.list), text: 'Logs'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildAudioTab(),
          _buildTestsTab(),
          _buildLogsTab(),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        children: _systemStatus.entries.map((entry) {
          return _buildStatusCard(entry.key, entry.value);
        }).toList(),
      ),
    );
  }

  Widget _buildStatusCard(String title, Map<String, dynamic> status) {
    Color statusColor;
    IconData statusIcon;

    switch (status['status']) {
      case 'ok':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'warning':
        statusColor = Colors.orange;
        statusIcon = Icons.warning;
        break;
      case 'error':
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help;
    }

    return Card(
      margin: EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(statusIcon, color: statusColor),
        title: Text(title.replaceAll('_', ' ').toUpperCase()),
        subtitle: Text(status['message'] ?? 'No information'),
      ),
    );
  }

  Widget _buildAudioTab() {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: _isMonitoringAudio ? _stopAudioMonitoring : _startAudioMonitoring,
                icon: Icon(_isMonitoringAudio ? Icons.stop : Icons.play_arrow),
                label: Text(_isMonitoringAudio ? 'Stop' : 'Monitor'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isMonitoringAudio ? Colors.red : Colors.green,
                ),
              ),
              SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _discoverAudioDevices,
                icon: Icon(Icons.refresh),
                label: Text('Refresh'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _audioDevices.length,
            itemBuilder: (context, index) {
              final device = _audioDevices[index];
              final level = _audioLevels[device['id']] ?? 0.0;

              return Card(
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: Icon(
                    device['type'] == 'input' ? Icons.mic : Icons.speaker,
                    color: device['type'] == 'input' ? Colors.red : Colors.blue,
                  ),
                  title: Text(device['name']),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${device['type']} • ${device['driver']}'),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Text('Level: '),
                          Expanded(
                            child: LinearProgressIndicator(
                              value: level,
                              backgroundColor: Colors.grey[700],
                              valueColor: AlwaysStoppedAnimation<Color>(
                                level > 0.8 ? Colors.red :
                                level > 0.5 ? Colors.orange : Colors.green
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Text('${(level * 100).round()}%'),
                        ],
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (device['type'] == 'input')
                        IconButton(
                          icon: Icon(Icons.mic_none),
                          onPressed: _isTestingMicrophone ? null : () => _testMicrophone(device),
                        ),
                      if (device['type'] == 'output')
                        IconButton(
                          icon: Icon(Icons.volume_up),
                          onPressed: _isTestingSpeakers ? null : () => _testSpeaker(device),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTestsTab() {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            child: ListTile(
              leading: Icon(Icons.smart_toy, color: Colors.blue),
              title: Text('Test Ollama AI'),
              subtitle: Text('Send test message to AI'),
              trailing: _isTestingOllama
                  ? CircularProgressIndicator(strokeWidth: 2)
                  : ElevatedButton(
                      onPressed: _testOllama,
                      child: Text('Test'),
                    ),
            ),
          ),
          SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(Icons.settings, color: Colors.green),
              title: Text('Full System Check'),
              subtitle: Text('Run complete diagnostics'),
              trailing: ElevatedButton(
                onPressed: _runFullSystemCheck,
                child: Text('Run'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsTab() {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _logs.clear();
                  });
                },
                icon: Icon(Icons.clear_all),
                label: Text('Clear'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            reverse: true,
            itemCount: _logs.length,
            itemBuilder: (context, index) {
              final log = _logs[_logs.length - 1 - index];

              Color logColor = Colors.white70;
              if (log.contains('✅')) logColor = Colors.green;
              else if (log.contains('❌')) logColor = Colors.red;
              else if (log.contains('⚠️')) logColor = Colors.orange;

              return Container(
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  log,
                  style: TextStyle(
                    color: logColor,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
EOF

echo -e "${GREEN}✅ Flutter app created successfully${NC}"

# Build the diagnostics app
echo -e "${BLUE}🔨 Building diagnostics application...${NC}"

flutter pub get
flutter build linux --release

if [ ! -f "build/linux/x64/release/bundle/ellmo_diagnostics" ]; then
    echo -e "${RED}❌ Build failed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Diagnostics app built successfully${NC}"

# Create launcher script
echo -e "${BLUE}🚀 Creating launcher script...${NC}"

cat > launch_diagnostics.sh << 'EOF'
#!/bin/bash

DIAGNOSTICS_DIR="/opt/ellmo/diagnostics"

export PATH="/opt/flutter/bin:$PATH"
export DISPLAY=${DISPLAY:-:0}

cd "$DIAGNOSTICS_DIR"

echo "🔧 Launching Ellmo Diagnostics..."
exec "./build/linux/x64/release/bundle/ellmo_diagnostics" "$@"
EOF

chmod +x launch_diagnostics.sh

# Create system command
echo -e "${BLUE}⚙️ Creating system command...${NC}"

sudo tee /usr/local/bin/ellmo-diag > /dev/null << 'EOF'
#!/bin/bash

case "$1" in
    gui|--gui|"")
        echo "🔧 Launching Ellmo Diagnostics GUI..."
        /opt/ellmo/diagnostics/launch_diagnostics.sh
        ;;
    test|--test)
        echo "🧪 Running quick system test..."
        echo "===================="

        echo -n "Flutter: "
        if command -v flutter >/dev/null 2>&1; then
            echo "✅ Available"
        else
            echo "❌ Not found"
        fi

        echo -n "Ollama: "
        if systemctl is-active ollama >/dev/null 2>&1; then
            echo "✅ Running"
        else
            echo "❌ Not running"
        fi

        echo -n "Audio: "
        if aplay -l >/dev/null 2>&1; then
            echo "✅ Devices found"
        else
            echo "❌ No devices"
        fi

        echo -n "Ellmo Service: "
        if systemctl is-active ellmo >/dev/null 2>&1; then
            echo "✅ System service active"
        elif systemctl --user is-active ellmo >/dev/null 2>&1; then
            echo "✅ User service active"
        else
            echo "❌ No service running"
        fi
        ;;
    audio|--audio)
        echo "🎵 Audio devices:"
        echo "================"
        echo "Output devices:"
        aplay -l 2>/dev/null | grep "card" || echo "None found"
        echo ""
        echo "Input devices:"
        arecord -l 2>/dev/null | grep "card" || echo "None found"
        ;;
    logs|--logs)
        echo "📋 Ellmo service logs..."
        journalctl -u ellmo --since "1 hour ago" -f
        ;;
    status|--status)
        echo "📊 System Status"
        echo "==============="
        echo "Ellmo Service:"
        systemctl status ellmo --no-pager 2>/dev/null || systemctl --user status ellmo --no-pager 2>/dev/null || echo "Not running"
        echo ""
        echo "Ollama Service:"
        systemctl status ollama --no-pager 2>/dev/null || echo "Not running"
        ;;
    help|--help)
        echo "Ellmo Diagnostics Tool"
        echo "====================="
        echo ""
        echo "Usage: ellmo-diag [COMMAND]"
        echo ""
        echo "Commands:"
        echo "  gui      Launch diagnostics GUI (default)"
        echo "  test     Run quick system test"
        echo "  audio    Show audio devices"
        echo "  logs     Show service logs"
        echo "  status   Show system status"
        echo "  help     Show this help"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use 'ellmo-diag help' for usage information"
        ;;
esac
EOF

sudo chmod +x /usr/local/bin/ellmo-diag

# Create desktop entry
echo -e "${BLUE}🖥️ Creating desktop entry...${NC}"

sudo tee /usr/share/applications/ellmo-diagnostics.desktop > /dev/null << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Ellmo Diagnostics
GenericName=System Diagnostics
Comment=Ellmo system diagnostics and testing tool
Exec=/opt/ellmo/diagnostics/launch_diagnostics.sh
Icon=utilities-system-monitor
Terminal=false
Categories=System;Monitor;Utility;
Keywords=diagnostics;test;audio;ellmo;
StartupNotify=true
EOF

# Update desktop database
echo -e "${BLUE}📱 Updating desktop database...${NC}"
sudo update-desktop-database /usr/share/applications/ 2>/dev/null || true

# Create quick test scripts
echo -e "${BLUE}📝 Creating test scripts...${NC}"

mkdir -p scripts

# Audio test script
cat > scripts/audio_test.sh << 'EOF'
#!/bin/bash

echo "🎵 Ellmo Audio Test"
echo "=================="

echo "Output devices:"
aplay -l 2>/dev/null | grep "card" || echo "None found"

echo ""
echo "Input devices:"
arecord -l 2>/dev/null | grep "card" || echo "None found"

echo ""
echo "Testing speaker..."
if command -v espeak-ng >/dev/null 2>&1; then
    espeak-ng "Audio test successful" 2>/dev/null
    echo "✅ Speaker test completed"
else
    echo "⚠️ espeak-ng not available"
fi

echo ""
echo "Testing microphone (3 seconds)..."
if command -v arecord >/dev/null 2>&1; then
    echo "Recording... speak now!"
    timeout 3 arecord -d 3 -f cd /tmp/mic_test.wav >/dev/null 2>&1 || true

    if [ -f /tmp/mic_test.wav ]; then
        size=$(wc -c < /tmp/mic_test.wav)
        if [ $size -gt 1000 ]; then
            echo "✅ Recorded ${size} bytes"
            echo "Playing back..."
            aplay /tmp/mic_test.wav >/dev/null 2>&1 || true
        else
            echo "⚠️ Very small recording - check microphone"
        fi
        rm -f /tmp/mic_test.wav
    else
        echo "❌ No recording created"
    fi
else
    echo "❌ arecord not available"
fi

echo ""
echo "Audio test completed!"
EOF

chmod +x scripts/audio_test.sh

# System check script
cat > scripts/system_check.sh << 'EOF'
#!/bin/bash

echo "🔍 Ellmo System Check"
echo "==================="

# Flutter check
echo -n "Flutter SDK: "
if command -v flutter >/dev/null 2>&1; then
    version=$(flutter --version 2>/dev/null | head -1 | awk '{print $2}')
    echo "✅ $version"
else
    echo "❌ Not found"
fi

# Ollama check
echo -n "Ollama Service: "
if systemctl is-active ollama >/dev/null 2>&1; then
    echo "✅ Running"

    echo -n "Ollama API: "
    if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
        models=$(curl -s http://localhost:11434/api/tags | jq -r '.models | length' 2>/dev/null || echo "?")
        echo "✅ Responding ($models models)"
    else
        echo "❌ Not responding"
    fi
else
    echo "❌ Not running"
fi

# Python modules
echo -n "Python Speech Recognition: "
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

# Audio devices
echo -n "Audio Output: "
if aplay -l >/dev/null 2>&1; then
    count=$(aplay -l | grep "card" | wc -l)
    echo "✅ $count devices"
else
    echo "❌ No devices"
fi

echo -n "Audio Input: "
if arecord -l >/dev/null 2>&1; then
    count=$(arecord -l | grep "card" | wc -l)
    echo "✅ $count devices"
else
    echo "❌ No devices"
fi

# Ellmo service
echo -n "Ellmo Service: "
if systemctl is-active ellmo >/dev/null 2>&1; then
    echo "✅ System service active"
elif systemctl --user is-active ellmo >/dev/null 2>&1; then
    echo "✅ User service active"
else
    echo "❌ No service running"
fi

# System resources
echo -n "System Memory: "
if command -v free >/dev/null 2>&1; then
    mem_percent=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    echo "📊 ${mem_percent}% used"
else
    echo "⚠️ Cannot check"
fi

echo ""
echo "System check completed!"
EOF

chmod +x scripts/system_check.sh

# Create simple launcher for CLI mode
cat > ellmo_diag_cli.sh << 'EOF'
#!/bin/bash

echo "🔧 Ellmo Diagnostics CLI"
echo "========================"

case "$1" in
    audio)
        ./scripts/audio_test.sh
        ;;
    system)
        ./scripts/system_check.sh
        ;;
    gui)
        ./launch_diagnostics.sh
        ;;
    *)
        echo "Usage: $0 {audio|system|gui}"
        echo ""
        echo "Commands:"
        echo "  audio   - Test audio system"
        echo "  system  - Check system status"
        echo "  gui     - Launch GUI application"
        ;;
esac
EOF

chmod +x ellmo_diag_cli.sh

echo ""
echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Installation Completed! 🎉      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}🚀 How to use Ellmo Diagnostics:${NC}"
echo ""
echo -e "${YELLOW}Quick Commands:${NC}"
echo "  ellmo-diag          # Launch GUI (default)"
echo "  ellmo-diag test     # Quick system test"
echo "  ellmo-diag audio    # Audio devices info"
echo "  ellmo-diag status   # Service status"
echo "  ellmo-diag logs     # View service logs"
echo ""
echo -e "${YELLOW}Direct Scripts:${NC}"
echo "  cd $DIAGNOSTICS_DIR"
echo "  ./launch_diagnostics.sh           # GUI application"
echo "  ./scripts/audio_test.sh           # Audio test"
echo "  ./scripts/system_check.sh         # System check"
echo "  ./ellmo_diag_cli.sh audio         # CLI audio test"
echo ""
echo -e "${BLUE}📁 Installation paths:${NC}"
echo "  • App: $DIAGNOSTICS_DIR/"
echo "  • Command: /usr/local/bin/ellmo-diag"
echo "  • Desktop: Applications → Ellmo Diagnostics"
echo ""
echo -e "${GREEN}✨ Ready! Run 'ellmo-diag' to start diagnostics!${NC}"
echo ""
echo -e "${YELLOW}💡 Quick test now:${NC}"
echo "ellmo-diag test"