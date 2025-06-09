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
      ),
      home: EllmoHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AppConfig {
  String ollamaHost;
  int ollamaPort;
  String model;
  String language;
  List<String> wakeWords;
  int ttsRate;
  double ttsVolume;
  int audioTimeout;
  bool autoStart;

  AppConfig({
    this.ollamaHost = 'localhost',
    this.ollamaPort = 11434,
    this.model = 'mistral',
    this.language = 'pl-PL',
    this.wakeWords = const ['ellmo'],
    this.ttsRate = 150,
    this.ttsVolume = 0.8,
    this.audioTimeout = 5,
    this.autoStart = true,
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      ollamaHost: json['ollama_host'] ?? 'localhost',
      ollamaPort: json['ollama_port'] ?? 11434,
      model: json['model'] ?? 'mistral',
      language: json['language'] ?? 'pl-PL',
      wakeWords: List<String>.from(json['wake_words'] ?? ['ellmo']),
      ttsRate: json['tts_rate'] ?? 150,
      ttsVolume: (json['tts_volume'] ?? 0.8).toDouble(),
      audioTimeout: json['audio_timeout'] ?? 5,
      autoStart: json['auto_start'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ollama_host': ollamaHost,
      'ollama_port': ollamaPort,
      'model': model,
      'language': language,
      'wake_words': wakeWords,
      'tts_rate': ttsRate,
      'tts_volume': ttsVolume,
      'audio_timeout': audioTimeout,
      'auto_start': autoStart,
    };
  }
}

class EllmoHome extends StatefulWidget {
  @override
  _EllmoHomeState createState() => _EllmoHomeState();
}

class _EllmoHomeState extends State<EllmoHome>
    with TickerProviderStateMixin {
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _isProcessing = false;
  String _lastResponse = "";
  String _status = "Initializing...";
  String _lastCommand = "";
  List<String> _conversationHistory = [];

  late AppConfig _config;
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _waveAnimation;

  Process? _audioProcess;
  Timer? _listeningTimer;

  static const platform = MethodChannel('ellmo/audio');

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadConfiguration();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    );
    _waveController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _waveAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _waveController,
      curve: Curves.easeInOut,
    ));

    _pulseController.repeat(reverse: true);
  }

  Future<void> _loadConfiguration() async {
    try {
      final configFile = File('/opt/ellmo/config.json');
      if (await configFile.exists()) {
        final configString = await configFile.readAsString();
        final configJson = json.decode(configString);
        _config = AppConfig.fromJson(configJson);
      } else {
        _config = AppConfig();
        await _saveConfiguration();
      }

      await _initializeVoiceAssistant();
    } catch (e) {
      _config = AppConfig();
      await _initializeVoiceAssistant();
    }
  }

  Future<void> _saveConfiguration() async {
    try {
      final configFile = File('/opt/ellmo/config.json');
      await configFile.writeAsString(json.encode(_config.toJson()));
    } catch (e) {
      print('Error saving configuration: $e');
    }
  }

  Future<void> _initializeVoiceAssistant() async {
    setState(() {
      _status = "Starting audio system...";
    });

    try {
      await _startAudioHandler();
      setState(() {
        _status = "Ready - Say '${_config.wakeWords.first}' to start";
      });

      if (_config.autoStart) {
        _startContinuousListening();
      }
    } catch (e) {
      setState(() {
        _status = "Error: $e";
      });
    }
  }

  Future<void> _startAudioHandler() async {
    try {
      _audioProcess = await Process.start(
        'python3',
        ['/opt/ellmo/linux/audio_handler.py'],
        workingDirectory: '/opt/ellmo',
      );

      // Listen to audio handler responses
      _audioProcess!.stdout
          .transform(utf8.decoder)
          .transform(LineSplitter())
          .listen(_handleAudioResponse);

      _audioProcess!.stderr
          .transform(utf8.decoder)
          .transform(LineSplitter())
          .listen((line) => print('Audio Error: $line'));

    } catch (e) {
      throw Exception('Failed to start audio handler: $e');
    }
  }

  void _handleAudioResponse(String line) {
    try {
      final response = json.decode(line);

      switch (response['type']) {
        case 'speech_result':
          final text = response['text'] as String;
          if (text.isNotEmpty) {
            _processVoiceCommand(text);
          }
          break;
        case 'speech_complete':
          setState(() {
            _isSpeaking = false;
            _status = "Ready - Say '${_config.wakeWords.first}' to start";
          });
          break;
        case 'error':
          print('Audio handler error: ${response['message']}');
          break;
      }
    } catch (e) {
      print('Error parsing audio response: $e');
    }
  }

  void _startContinuousListening() {
    if (_isListening || _audioProcess == null) return;

    setState(() {
      _isListening = true;
      _status = "Listening for wake word...";
    });

    _waveController.repeat();

    // Send listen command to audio handler
    _audioProcess!.stdin.writeln(json.encode({'action': 'listen'}));

    // Set timeout for listening session
    _listeningTimer?.cancel();
    _listeningTimer = Timer(Duration(seconds: _config.audioTimeout), () {
      if (_isListening && !_isProcessing) {
        _startContinuousListening(); // Restart listening
      }
    });
  }

  void _processVoiceCommand(String command) {
    setState(() {
      _lastCommand = command;
      _isListening = false;
    });

    _waveController.stop();

    // Check for wake word
    bool hasWakeWord = _config.wakeWords.any((wake) =>
        command.toLowerCase().contains(wake.toLowerCase())
    );

    if (!hasWakeWord) {
      // No wake word detected, continue listening
      _startContinuousListening();
      return;
    }

    setState(() {
      _isProcessing = true;
      _status = "Processing: $command";
    });

    // Send to Ollama
    _sendToOllama(command).then((response) {
      setState(() {
        _lastResponse = response;
        _isProcessing = false;
        _status = "Speaking...";
        _conversationHistory.add("User: $command");
        _conversationHistory.add("Assistant: $response");

        // Keep only last 10 exchanges
        if (_conversationHistory.length > 20) {
          _conversationHistory = _conversationHistory.sublist(_conversationHistory.length - 20);
        }
      });

      _speak(response);
    }).catchError((error) {
      setState(() {
        _isProcessing = false;
        _status = "Error: $error";
      });
      _startContinuousListening();
    });
  }

  Future<String> _sendToOllama(String message) async {
    try {
      final url = Uri.parse('http://${_config.ollamaHost}:${_config.ollamaPort}/api/generate');
      final headers = {'Content-Type': 'application/json'};

      // Build context from conversation history
      String context = "";
      if (_conversationHistory.isNotEmpty) {
        context = _conversationHistory.takeLast(6).join('\n') + '\n';
      }

      final body = json.encode({
        'model': _config.model,
        'prompt': context + message,
        'stream': false,
        'options': {
          'temperature': 0.7,
          'top_p': 0.9,
          'max_tokens': 150,
        }
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
        throw Exception('Ollama returned status ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to communicate with Ollama: $e');
    }
  }

  void _speak(String text) {
    setState(() {
      _isSpeaking = true;
    });

    // Send speak command to audio handler
    _audioProcess?.stdin.writeln(json.encode({
      'action': 'speak',
      'text': text,
    }));

    // Fallback timer in case speech_complete is not received
    Timer(Duration(seconds: text.length ~/ 10 + 5), () {
      if (_isSpeaking) {
        setState(() {
          _isSpeaking = false;
          _status = "Ready - Say '${_config.wakeWords.first}' to start";
        });
        _startContinuousListening();
      }
    });
  }

  void _toggleListening() {
    if (_isListening) {
      _listeningTimer?.cancel();
      setState(() {
        _isListening = false;
        _status = "Stopped listening";
      });
      _waveController.stop();
    } else {
      _startContinuousListening();
    }
  }

  void _clearHistory() {
    setState(() {
      _conversationHistory.clear();
      _lastResponse = "";
      _lastCommand = "";
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    _listeningTimer?.cancel();
    _audioProcess?.kill();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            children: [
              // Header
              _buildHeader(),

              SizedBox(height: 30),

              // Main status display
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

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Ellmo',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Row(
          children: [
            IconButton(
              icon: Icon(Icons.settings, color: Colors.grey),
              onPressed: _showSettingsDialog,
            ),
            IconButton(
              icon: Icon(Icons.clear_all, color: Colors.grey),
              onPressed: _clearHistory,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusDisplay() {
    Color statusColor = _isListening ? Colors.red :
                       _isSpeaking ? Colors.blue :
                       _isProcessing ? Colors.orange :
                       Colors.green;

    IconData statusIcon = _isListening ? Icons.mic :
                         _isSpeaking ? Icons.volume_up :
                         _isProcessing ? Icons.psychology :
                         Icons.assistant;

    return AnimatedBuilder(
      animation: _isListening ? _waveAnimation : _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _isListening ? (1.0 + _waveAnimation.value * 0.1) :
                 _pulseAnimation.value * 0.8 + 0.2,
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
                SizedBox(height: 10),
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
                    maxLines: 2,
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
          onPressed: _toggleListening,
          icon: Icon(_isListening ? Icons.stop : Icons.mic),
          label: Text(_isListening ? 'Stop' : 'Listen'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _isListening ? Colors.red : Colors.blue,
            foregroundColor: Colors.white,
          ),
        ),
        ElevatedButton.icon(
          onPressed: _isProcessing ? null : () => _processVoiceCommand("Test message"),
          icon: Icon(Icons.chat),
          label: Text('Test'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildConversationHistory() {
    if (_conversationHistory.isEmpty) {
      return Center(
        child: Text(
          'Conversation history will appear here',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(15),
            child: Text(
              'Recent Conversation',
              style: TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _conversationHistory.length,
              itemBuilder: (context, index) {
                final message = _conversationHistory[index];
                final isUser = message.startsWith('User:');

                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isUser ? Icons.person : Icons.assistant,
                        color: isUser ? Colors.blue : Colors.green,
                        size: 20,
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

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Model: ${_config.model}'),
              trailing: Icon(Icons.edit),
              onTap: () => _showModelSelector(),
            ),
            ListTile(
              title: Text('Language: ${_config.language}'),
              trailing: Icon(Icons.edit),
              onTap: () => _showLanguageSelector(),
            ),
            ListTile(
              title: Text('Wake Words'),
              subtitle: Text(_config.wakeWords.join(', ')),
              trailing: Icon(Icons.edit),
              onTap: () => _showWakeWordEditor(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showModelSelector() {
    // Implementation for model selection
    // This would show available Ollama models
  }

  void _showLanguageSelector() {
    // Implementation for language selection
  }

  void _showWakeWordEditor() {
    // Implementation for wake word editing
  }
}