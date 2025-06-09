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
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFF2D2D2D),
          elevation: 2,
        ),
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

  // System status
  Map<String, dynamic> _systemStatus = {};
  List<Map<String, dynamic>> _audioDevices = [];
  List<String> _logs = [];
  Map<String, double> _audioLevels = {};

  // Timers
  Timer? _statusTimer;
  Timer? _audioTimer;
  Timer? _logTimer;

  // Test states
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

    // Start periodic updates
    _statusTimer = Timer.periodic(Duration(seconds: 10), (_) => _runFullSystemCheck());
    _logTimer = Timer.periodic(Duration(seconds: 5), (_) => _readSystemLogs());
  }

  Future<void> _runFullSystemCheck() async {
    setState(() {
      _systemStatus = {};
    });

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
      _addLog("✅ Flutter: $version");
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
      // Check if Ollama service is running
      final serviceResult = await Process.run('systemctl', ['is-active', 'ollama']);
      final isRunning = serviceResult.stdout.toString().trim() == 'active';

      if (isRunning) {
        // Check API connection
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
              'api_port': 11434
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
          _addLog("⚠️ Ollama: Service running but API issue");
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
      _addLog("❌ Ollama: Check failed - $e");
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
      // Check audio output devices
      final aplayResult = await Process.run('aplay', ['-l']);
      final outputDevices = _parseAudioDevices(aplayResult.stdout.toString(), 'output');

      // Check audio input devices
      final arecordResult = await Process.run('arecord', ['-l']);
      final inputDevices = _parseAudioDevices(arecordResult.stdout.toString(), 'input');

      setState(() {
        _systemStatus['audio'] = {
          'status': (outputDevices.isNotEmpty && inputDevices.isNotEmpty) ? 'ok' : 'warning',
          'message': 'Audio devices: ${outputDevices.length} output, ${inputDevices.length} input',
          'output_devices': outputDevices.length,
          'input_devices': inputDevices.length
        };
      });

      _addLog("✅ Audio: ${outputDevices.length} output, ${inputDevices.length} input devices");
    } catch (e) {
      setState(() {
        _systemStatus['audio'] = {
          'status': 'error',
          'message': 'Audio system check failed: $e'
        };
      });
      _addLog("❌ Audio: System check failed");
    }
  }

  Future<void> _checkSystemResources() async {
    try {
      // Check memory
      final memResult = await Process.run('free', ['-m']);
      final memLines = memResult.stdout.toString().split('\n');
      final memData = memLines[1].split(RegExp(r'\s+'));
      final totalMem = int.parse(memData[1]);
      final usedMem = int.parse(memData[2]);
      final memPercent = (usedMem / totalMem * 100).round();

      // Check disk space
      final dfResult = await Process.run('df', ['-h', '/']);
      final dfLines = dfResult.stdout.toString().split('\n');
      final dfData = dfLines[1].split(RegExp(r'\s+'));
      final diskUse = dfData[4].replaceAll('%', '');

      // Check CPU load
      final loadResult = await Process.run('cat', ['/proc/loadavg']);
      final loadAvg = loadResult.stdout.toString().split(' ')[0];

      setState(() {
        _systemStatus['resources'] = {
          'status': (memPercent < 80 && int.parse(diskUse) < 90) ? 'ok' : 'warning',
          'memory_percent': memPercent,
          'disk_percent': int.parse(diskUse),
          'load_average': double.parse(loadAvg),
          'total_memory_mb': totalMem
        };
      });

      _addLog("📊 Resources: RAM ${memPercent}%, Disk ${diskUse}%, Load $loadAvg");
    } catch (e) {
      _addLog("❌ Resources: Check failed - $e");
    }
  }

  Future<void> _checkEllmoService() async {
    try {
      // Check system service
      final systemResult = await Process.run('systemctl', ['is-active', 'ellmo']);
      final systemActive = systemResult.stdout.toString().trim() == 'active';

      // Check user service
      final userResult = await Process.run('systemctl', ['--user', 'is-active', 'ellmo']);
      final userActive = userResult.stdout.toString().trim() == 'active';

      // Check if executable exists
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

      _addLog("🔧 Ellmo Service: ${systemActive ? 'System' : userActive ? 'User' : 'None'} active");
    } catch (e) {
      _addLog("❌ Ellmo Service: Check failed - $e");
    }
  }

  Future<void> _discoverAudioDevices() async {
    List<Map<String, dynamic>> devices = [];

    try {
      // Get PulseAudio devices
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
            'active': true,
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
            'active': true,
          });
        }
      }
    } catch (e) {
      _addLog("⚠️ PulseAudio discovery failed, trying ALSA...");

      // Fallback to ALSA
      try {
        final alsaResult = await Process.run('aplay', ['-l']);
        final lines = alsaResult.stdout.toString().split('\n');

        for (String line in lines) {
          if (line.contains('card') && line.contains('device')) {
            final cardMatch = RegExp(r'card (\d+)').firstMatch(line);
            final deviceMatch = RegExp(r'device (\d+)').firstMatch(line);
            final nameMatch = RegExp(r'\[(.*?)\]').firstMatch(line);

            if (cardMatch != null && deviceMatch != null) {
              devices.add({
                'id': 'hw:${cardMatch.group(1)},${deviceMatch.group(1)}',
                'name': nameMatch?.group(1) ?? 'Unknown Device',
                'type': 'output',
                'driver': 'alsa',
                'level': 0.0,
                'active': true,
              });
            }
          }
        }
      } catch (e) {
        _addLog("❌ ALSA discovery also failed: $e");
      }
    }

    setState(() {
      _audioDevices = devices;
    });

    _addLog("🎵 Found ${devices.length} audio devices");
  }

  List<String> _parseAudioDevices(String output, String type) {
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

    _addLog("🎤 Starting audio level monitoring...");

    _audioTimer = Timer.periodic(Duration(milliseconds: 100), (timer) async {
      for (var device in _audioDevices) {
        final level = await _getAudioLevel(device);
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

  Future<double> _getAudioLevel(Map<String, dynamic> device) async {
    try {
      if (device['driver'] == 'pulseaudio') {
        if (device['type'] == 'input') {
          // Get microphone level
          final result = await Process.run('pactl', ['get-source-volume', device['name']]);
          return _parsePulseAudioVolume(result.stdout.toString());
        } else {
          // Get speaker level
          final result = await Process.run('pactl', ['get-sink-volume', device['name']]);
          return _parsePulseAudioVolume(result.stdout.toString());
        }
      } else {
        // ALSA devices - simulate levels for now
        return Random().nextDouble() * 0.3 + 0.1;
      }
    } catch (e) {
      return 0.0;
    }
  }

  double _parsePulseAudioVolume(String output) {
    final match = RegExp(r'(\d+)%').firstMatch(output);
    if (match != null) {
      return int.parse(match.group(1)!) / 100.0;
    }
    return 0.0;
  }

  Future<void> _testMicrophone(Map<String, dynamic> device) async {
    setState(() {
      _isTestingMicrophone = true;
    });

    _addLog("🎤 Testing microphone: ${device['name']}");

    try {
      // Record 3 seconds of audio
      final process = await Process.start('arecord', [
        '-D', device['id'],
        '-d', '3',
        '-f', 'cd',
        '/tmp/mic_test.wav'
      ]);

      await process.exitCode;

      // Analyze the recorded audio
      final file = File('/tmp/mic_test.wav');
      if (await file.exists()) {
        final size = await file.length();
        _addLog("✅ Microphone test completed: ${size} bytes recorded");

        // Play back the recording
        await Process.run('aplay', ['/tmp/mic_test.wav']);
        _addLog("🔊 Playback completed");

        // Cleanup
        await file.delete();
      } else {
        _addLog("❌ No audio recorded");
      }
    } catch (e) {
      _addLog("❌ Microphone test failed: $e");
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
      // Generate a test tone
      final process = await Process.start('speaker-test', [
        '-D', device['id'],
        '-t', 'sine',
        '-f', '1000',
        '-l', '1'
      ]);

      await process.exitCode;
      _addLog("✅ Speaker test completed");
    } catch (e) {
      // Fallback to espeak
      try {
        await Process.run('espeak-ng', ['Testing speaker ${device['name']}']);
        _addLog("✅ Speaker test completed (using espeak)");
      } catch (e2) {
        _addLog("❌ Speaker test failed: $e2");
      }
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
        _addLog("✅ Ollama test: $aiResponse");
      } else {
        _addLog("❌ Ollama test failed: HTTP ${response.statusCode}");
      }
    } catch (e) {
      _addLog("❌ Ollama test failed: $e");
    } finally {
      setState(() {
        _isTestingOllama = false;
      });
    }
  }

  void _readSystemLogs() async {
    try {
      // Read Ellmo service logs
      final result = await Process.run('journalctl', [
        '-u', 'ellmo',
        '--since', '10 minutes ago',
        '--no-pager',
        '-n', '5'
      ]);

      final logs = result.stdout.toString().split('\n');
      for (String log in logs) {
        if (log.trim().isNotEmpty && !_logs.contains(log)) {
          _addLog("📋 Service: ${log.trim()}");
        }
      }
    } catch (e) {
      // Ignore errors in log reading
    }
  }

  void _addLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final logEntry = "[$timestamp] $message";

    setState(() {
      _logs.add(logEntry);
      if (_logs.length > 100) {
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
    _logTimer?.cancel();
    super.dispose();
  }

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
            Tab(icon: Icon(Icons.dashboard), text: 'Overview'),
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
        children: [
          _buildSystemStatusCard('Flutter', _systemStatus['flutter']),
          SizedBox(height: 12),
          _buildSystemStatusCard('Ollama', _systemStatus['ollama']),
          SizedBox(height: 12),
          _buildSystemStatusCard('Python', _systemStatus['python']),
          SizedBox(height: 12),
          _buildSystemStatusCard('Audio System', _systemStatus['audio']),
          SizedBox(height: 12),
          _buildSystemStatusCard('System Resources', _systemStatus['resources']),
          SizedBox(height: 12),
          _buildSystemStatusCard('Ellmo Service', _systemStatus['ellmo_service']),
        ],
      ),
    );
  }

  Widget _buildSystemStatusCard(String title, Map<String, dynamic>? status) {
    if (status == null) {
      return Card(
        child: ListTile(
          leading: CircularProgressIndicator(strokeWidth: 2),
          title: Text(title),
          subtitle: Text('Checking...'),
        ),
      );
    }

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
      child: ExpansionTile(
        leading: Icon(statusIcon, color: statusColor),
        title: Text(title),
        subtitle: Text(status['message'] ?? 'No information'),
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: status.entries
                  .where((e) => e.key != 'status' && e.key != 'message')
                  .map((e) => Padding(
                        padding: EdgeInsets.symmetric(vertical: 2),
                        child: Text('${e.key}: ${e.value}',
                               style: TextStyle(fontSize: 12, color: Colors.grey[300])),
                      ))
                  .toList(),
            ),
          ),
        ],
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
                label: Text(_isMonitoringAudio ? 'Stop Monitoring' : 'Start Monitoring'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isMonitoringAudio ? Colors.red : Colors.green,
                ),
              ),
              SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _discoverAudioDevices,
                icon: Icon(Icons.refresh),
                label: Text('Refresh Devices'),
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
                          tooltip: 'Test Microphone',
                        ),
                      if (device['type'] == 'output')
                        IconButton(
                          icon: Icon(Icons.volume_up),
                          onPressed: _isTestingSpeakers ? null : () => _testSpeaker(device),
                          tooltip: 'Test Speaker',
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
              subtitle: Text('Send a test message to the AI'),
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
          SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(Icons.build, color: Colors.orange),
              title: Text('Restart Services'),
              subtitle: Text('Restart Ellmo and Ollama services'),
              trailing: ElevatedButton(
                onPressed: () async {
                  _addLog("🔄 Restarting services...");
                  try {
                    await Process.run('sudo', ['systemctl', 'restart', 'ollama']);
                    await Process.run('sudo', ['systemctl', 'restart', 'ellmo']);
                    _addLog("✅ Services restarted");
                  } catch (e) {
                    _addLog("❌ Failed to restart services: $e");
                  }
                },
                child: Text('Restart'),
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
                label: Text('Clear Logs'),
              ),
              SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _readSystemLogs,
                icon: Icon(Icons.refresh),
                label: Text('Refresh'),
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
              IconData logIcon = Icons.info;

              if (log.contains('✅')) {
                logColor = Colors.green;
                logIcon = Icons.check_circle;
              } else if (log.contains('❌')) {
                logColor = Colors.red;
                logIcon = Icons.error;
              } else if (log.contains('⚠️')) {
                logColor = Colors.orange;
                logIcon = Icons.warning;
              } else if (log.contains('🎵') || log.contains('🎤') || log.contains('🔊')) {
                logColor = Colors.blue;
                logIcon = Icons.audiotrack;
              } else if (log.contains('🤖')) {
                logColor = Colors.purple;
                logIcon = Icons.smart_toy;
              }

              return Container(
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(4),
                  border: Border.left(color: logColor, width: 3),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(logIcon, size: 16, color: logColor),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        log,
                        style: TextStyle(
                          color: logColor,
                          fontSize: 12,
                          fontFamily: 'monospace',
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
    );
  }
}