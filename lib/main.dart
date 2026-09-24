import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock to portrait — watch screen is square/round but this prevents rotation
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const CollectorApp());
}

class CollectorApp extends StatelessWidget {
  const CollectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IMU Collector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4FC3F7),
          brightness: Brightness.dark,
          surface: Colors.black,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const RecorderScreen(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Recorder screen
// ─────────────────────────────────────────────────────────────────────────────

class RecorderScreen extends StatefulWidget {
  const RecorderScreen({super.key});

  @override
  State<RecorderScreen> createState() => _RecorderScreenState();
}

class _RecorderScreenState extends State<RecorderScreen>
    with SingleTickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────
  bool _recording = false;
  Duration _elapsed = Duration.zero;
  int _sampleCount = 0;
  String? _lastSavedPath;
  String? _errorMessage;

  // ── Internals ──────────────────────────────────────────────────────
  Timer? _uiTimer;
  DateTime? _startTime;
  IOSink? _sink;
  File? _currentFile;

  // Sensor subscriptions
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  // Latest sensor readings — kept in sync, written together
  AccelerometerEvent? _lastAccel;
  GyroscopeEvent? _lastGyro;

  // Sampling control — target 50 Hz
  static const _targetIntervalMs = 20;
  Timer? _sampleTimer;

  // ── Animation for the record button pulse ─────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _stopRecording();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Recording control ──────────────────────────────────────────────

  Future<void> _startRecording() async {
    _errorMessage = null;

    try {
      // Keep screen on while recording
      await WakelockPlus.enable();

      // Build file path: /sdcard/Android/data/<pkg>/files/imu_<timestamp>.csv
      debugPrint('BUilding file path...');
      final dir = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filename = 'imu_$timestamp.csv';
      _currentFile = File('${dir.path}/$filename');

      // Open file and write CSV header
      _sink = _currentFile!.openWrite();
      _sink!.writeln('timestamp_ms,ax,ay,az,gx,gy,gz');

      _startTime = DateTime.now();
      _sampleCount = 0;
      _lastSavedPath = null;

      // Subscribe to raw sensors — just keep latest values
      debugPrint('Subscribing to sensors...');
      _accelSub = accelerometerEventStream(
        samplingPeriod: SensorInterval.normalInterval,
      ).listen(
        (e) {
          _lastAccel = e;
          print('ACCEL: ${e.x}, ${e.y}, ${e.z}');
        },
        onError: (e) {
          print('ACCEL ERROR: $e');
        },
      );

      _gyroSub = gyroscopeEventStream(
        samplingPeriod: SensorInterval.normalInterval,
      ).listen(
        (e) {
          _lastGyro = e;
          print('GYRO: ${e.x}, ${e.y}, ${e.z}');
        },
        onError: (e) {
          print('GYRO ERROR: $e');
        },
      );

      // Write at fixed 50 Hz regardless of sensor delivery jitter
      _sampleTimer = Timer.periodic(
        const Duration(milliseconds: _targetIntervalMs),
        (_) => _writeSample(),
      );

      // UI clock — updates every second
      _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {
            _elapsed = DateTime.now().difference(_startTime!);
          });
        }
      });

      _pulseCtrl.repeat(reverse: true);

      setState(() {
        _recording = true;
        _elapsed = Duration.zero;
      });
    } catch (e) {
      setState(() => _errorMessage = 'Failed to start: $e');
      await WakelockPlus.disable();
    }
  }

  void _writeSample() {
    final accel = _lastAccel;
    final gyro = _lastGyro;
    if (accel == null || gyro == null) {
      print('Warning: Sensor data not available yet.');
      return;
    }

    final ts = DateTime.now().millisecondsSinceEpoch;
    _sink?.writeln(
      '$ts,'
      '${accel.x.toStringAsFixed(5)},'
      '${accel.y.toStringAsFixed(5)},'
      '${accel.z.toStringAsFixed(5)},'
      '${gyro.x.toStringAsFixed(5)},'
      '${gyro.y.toStringAsFixed(5)},'
      '${gyro.z.toStringAsFixed(5)}',
    );
    _sampleCount++;
  }

  Future<void> _stopRecording() async {
    _sampleTimer?.cancel();
    _sampleTimer = null;
    _uiTimer?.cancel();
    _uiTimer = null;
    _accelSub?.cancel();
    _accelSub = null;
    _gyroSub?.cancel();
    _gyroSub = null;

    await _sink?.flush();
    await _sink?.close();
    _sink = null;

    _pulseCtrl.stop();
    _pulseCtrl.reset();

    await WakelockPlus.disable();

    if (mounted) {
      setState(() {
        _lastSavedPath = _currentFile?.path;
        _recording = false;
      });
    }
  }

  void _toggle() {
    if (_recording) {
      _stopRecording();
    } else {
      _startRecording();
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────

  String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  String _shortPath(String? path) {
    if (path == null) return '';
    final parts = path.split('/');
    return parts.last; // just the filename
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Wear OS screens are typically 384×384 or 450×450 round
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Timer display ──────────────────────────────────
                _TimerDisplay(
                  elapsed: _elapsed,
                  formatElapsed: _formatElapsed,
                  recording: _recording,
                ),

                const SizedBox(height: 28),

                // ── Record / Stop button ───────────────────────────
                ScaleTransition(
                  scale: _pulseAnim,
                  child: _RecordButton(
                    recording: _recording,
                    onTap: _toggle,
                  ),
                ),

                const SizedBox(height: 24),

                // ── Sample counter or saved path ───────────────────
                _StatusLine(
                  recording: _recording,
                  sampleCount: _sampleCount,
                  lastSavedPath: _lastSavedPath,
                  shortPath: _shortPath,
                  errorMessage: _errorMessage,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets — kept small for watch screen real estate
// ─────────────────────────────────────────────────────────────────────────────

class _TimerDisplay extends StatelessWidget {
  final Duration elapsed;
  final String Function(Duration) formatElapsed;
  final bool recording;

  const _TimerDisplay({
    required this.elapsed,
    required this.formatElapsed,
    required this.recording,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          formatElapsed(elapsed),
          style: TextStyle(
            fontSize: 42,
            fontWeight: FontWeight.w200,
            letterSpacing: 2,
            color: recording ? Colors.white : const Color(0xFF37474F),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          recording ? 'RECORDING' : 'READY',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 3,
            color:
                recording ? const Color(0xFFEF5350) : const Color(0xFF37474F),
          ),
        ),
      ],
    );
  }
}

class _RecordButton extends StatelessWidget {
  final bool recording;
  final VoidCallback onTap;

  const _RecordButton({required this.recording, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: recording ? const Color(0xFFB71C1C) : const Color(0xFF1A1A1A),
          border: Border.all(
            color:
                recording ? const Color(0xFFEF5350) : const Color(0xFF37474F),
            width: 2.5,
          ),
          boxShadow: recording
              ? [
                  BoxShadow(
                    color: const Color(0xFFEF5350).withOpacity(0.35),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ]
              : [],
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: recording
                ? const Icon(
                    Icons.stop_rounded,
                    key: ValueKey('stop'),
                    color: Colors.white,
                    size: 36,
                  )
                : Container(
                    key: const ValueKey('rec'),
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFEF5350),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final bool recording;
  final int sampleCount;
  final String? lastSavedPath;
  final String Function(String?) shortPath;
  final String? errorMessage;

  const _StatusLine({
    required this.recording,
    required this.sampleCount,
    required this.lastSavedPath,
    required this.shortPath,
    required this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (errorMessage != null) {
      return Text(
        errorMessage!,
        style: const TextStyle(color: Color(0xFFEF5350), fontSize: 10),
        textAlign: TextAlign.center,
      );
    }

    if (recording) {
      return Text(
        '$sampleCount samples',
        style: const TextStyle(
          color: Color(0xFF546E7A),
          fontSize: 11,
          letterSpacing: 0.5,
        ),
      );
    }

    if (lastSavedPath != null) {
      return Column(
        children: [
          const Icon(Icons.check_circle_outline,
              color: Color(0xFF81C784), size: 16),
          const SizedBox(height: 4),
          Text(
            shortPath(lastSavedPath),
            style: const TextStyle(
              color: Color(0xFF4DB6AC),
              fontSize: 10,
              letterSpacing: 0.3,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }

    return const Text(
      'Tap to begin',
      style:
          TextStyle(color: Color(0xFF37474F), fontSize: 11, letterSpacing: 1),
    );
  }
}
