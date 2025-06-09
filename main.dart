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
  bool _isHeadless = false;
  bool _ollamaConnected = false;
  String _status = "Initializing...";
  String _lastResponse = "";
  List<String> _logs = [];

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  Timer? _connectionTimer;
  Timer? _logTimer;

  @override
  void initState() {
    super.initState();
    _detectMode();
    _initializeAnimations();
    _initializeApp();
  }

  void _detectMode() {
    // Check if running in headless mode
    _isHeadless = Platform.environment.containsKey('FLUTTER_ENGINE_SWITCH_HEADLESS') ||
                  Platform.environment['DISPLAY'] == null;

    _addLog("Mode: ${_isHeadless ? 'Headless' : 'GUI'}");
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

    if (!_isHeadless) {
      _pulseController.repeat(reverse: true);
    }
  }

  void _initializeApp() async {
    _addLog("Initializing Ellmo...");

    setState(() {
      _status = "Checking Ollama connection...";
    });

    await _checkOllamaConnection();

    if (_ollamaConnected) {
      setState(() {
        _status = "Ready - Say 'Ellmo' to start";
      });
      _addLog("✓ Ollama connected, system ready");

      if (_isHeadless) {
        _startHeadlessMode();
      }
    } else {
      setState(() {
        _status = "Ollama not available";
      });
      _addLog("✗ Ollama connection failed");
    }

    // Start periodic checks
    _connectionTimer = Timer.periodic(Duration(seconds: 30), (_) {
      _checkOllamaConnection();
    });
  }

  void _startHeadlessMode() {
    _addLog("Starting headless voice assistant mode...");

    // In headless mode, we would start continuous listening
    // For now, we'll simulate with periodic status updates
    Timer.periodic(Duration(seconds: 10), (timer) {
      _addLog("Voice assistant active - listening for 'Ellmo'");

      // Simulate occasional interactions
      if (DateTime.now().second % 30 == 0) {
        _simulateVoiceInteraction();
      }
    });
  }

  void _simulateVoiceInteraction() {
    _addLog("Voice command detected: 'Ellmo, hello'");
    _sendToOllama("Hello, how are you?").then((response) {
      _addLog("AI Response: $response");
      setState(() {
        _lastResponse = response;
      });
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

      if (_ollamaConnected) {
        _addLog("✓ Ollama connection verified");
      }
    } catch (e) {
      setState(() {
        _ollamaConnected = false;
      });
      _addLog("✗ Ollama connection failed: $e");
    }
  }

  Future<String> _sendToOllama(String message) async {
    if (!_ollamaConnected) {
      return "Ollama is not connected";
    }

    try {
      final url = Uri.parse('http://localhost:11434/api/generate');
      final headers = {'Content-Type': 'application/json'};

      final body = json.encode({
        'model': 'mistral',
        'prompt': message,
        'stream': false,
      });

      final response = await http.post(
        url,
        headers: headers,
        body: body,
      ).timeout(Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['response']?.toString().trim() ?? 'No response';
      } else {
        return 'Error: ${response.statusCode}';
      }
    } catch (e) {
      return 'Error: $e';
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

    // Also print to console for headless mode
    print(logEntry);
  }

  void _testAI() {
    _addLog("Testing AI connection...");
    _sendToOllama("Say hello in one sentence").then((response) {
      _addLog("AI Test Result: $response");
      setState(() {
        _lastResponse = response;
      });
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _connectionTimer?.cancel();
    _logTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isHeadless) {
      // In headless mode, return minimal widget
      return MaterialApp(
        home: Scaffold(
          body: Container(
            color: Colors.black,
            child: Center(
              child: Text(
                'Ellmo Running in Headless Mode\nCheck logs for activity',
                style: TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

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

              SizedBox(height: 20),

              // Controls
              _buildControls(),

              SizedBox(height: 20),

              // Logs
              Expanded(child: _buildLogs()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusDisplay() {
    Color statusColor = _ollamaConnected ? Colors.green : Colors.red;
    IconData statusIcon = _ollamaConnected ? Icons.assistant : Icons.error_outline;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(75),
              border: Border.all(color: statusColor, width: 3),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  statusIcon,
                  size: 60,
                  color: statusColor,
                ),
                SizedBox(height: 10),
                Text(
                  _status,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
          onPressed: _ollamaConnected ? _testAI : null,
          icon: Icon(Icons.chat),
          label: Text('Test AI'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
        ),
        ElevatedButton.icon(
          onPressed: () => _checkOllamaConnection(),
          icon: Icon(Icons.refresh),
          label: Text('Refresh'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildLogs() {
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
                  'System Logs',
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _logs.clear();
                    });
                  },
                  icon: Icon(Icons.clear_all, size: 20),
                  tooltip: 'Clear Logs',
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
                final isError = log.contains('✗') || log.contains('Error');
                final isSuccess = log.contains('✓');

                return Container(
                  margin: EdgeInsets.symmetric(horizontal: 15, vertical: 2),
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isError ? Colors.red.withOpacity(0.1) :
                           isSuccess ? Colors.green.withOpacity(0.1) :
                           Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    log,
                    style: TextStyle(
                      color: isError ? Colors.red :
                             isSuccess ? Colors.green :
                             Colors.white70,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
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