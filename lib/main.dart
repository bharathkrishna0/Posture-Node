// main.dart — PostureNet Complete App
// Screens: Splash → Scanner → Dashboard (with Drawer + Emergency)
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() => runApp(const PostureNetApp());

class PostureNetApp extends StatelessWidget {
  const PostureNetApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PostureNet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A2B4C)),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const SplashScreen(),
    );
  }
}

// ─────────────────────────────────────────────
// SPLASH SCREEN
// ─────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const ScanScreen()));
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A2B4C),
      body: FadeTransition(
        opacity: _fade,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo placeholder — spine icon
              Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.accessibility_new,
                    size: 72, color: Colors.white),
              ),
              const SizedBox(height: 24),
              const Text("PostureNet",
                  style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 2)),
              const SizedBox(height: 8),
              Text("Smart Posture Monitoring",
                  style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.7))),
              const SizedBox(height: 48),
              const CircularProgressIndicator(color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SCAN SCREEN
// ─────────────────────────────────────────────
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  List<ScanResult> _results = [];
  bool _scanning = false;
  StreamSubscription? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  void startScan() async {
    setState(() { _results = []; _scanning = true; });

    _sub = FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          _results = results
              .where((r) => r.device.platformName.isNotEmpty)
              .toList()
            ..sort((a, b) => b.rssi.compareTo(a.rssi));
        });
      }
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
    if (mounted) setState(() => _scanning = false);
  }

  void stopScan() async {
    await FlutterBluePlus.stopScan();
    _sub?.cancel();
    if (mounted) setState(() => _scanning = false);
  }

  void selectDevice(BluetoothDevice dev) async {
    await FlutterBluePlus.stopScan();
    _sub?.cancel();
    if (!mounted) return;
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => DashboardScreen(device: dev)));
  }

  bool isSpineGuard(String name) =>
      name.toUpperCase().contains("SPINEGUARD") ||
      name.toUpperCase().contains("IMU") ||
      name.toUpperCase().contains("POSTURENET");

  Color rssiColor(int rssi) {
    if (rssi >= -70) return Colors.green;
    if (rssi >= -85) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A2B4C),
        foregroundColor: Colors.white,
        title: Row(children: [
          const Icon(Icons.accessibility_new, color: Colors.white),
          const SizedBox(width: 8),
          const Text("PostureNet",
              style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        actions: [
          if (_scanning)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2)),
            ),
        ],
      ),
      body: Column(children: [
        // Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          color: Colors.white,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Select your node",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                    color: Color(0xFF1A2B4C))),
            const SizedBox(height: 4),
            Text(
              _scanning
                  ? "Scanning for nearby devices..."
                  : _results.isEmpty
                      ? "Tap scan to find devices"
                      : "${_results.length} device(s) found",
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ]),
        ),

        // Device list
        Expanded(
          child: _results.isEmpty
              ? Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bluetooth_searching,
                        size: 64, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    Text(_scanning ? "Looking for devices..."
                        : "No devices found",
                        style: TextStyle(color: Colors.grey[400])),
                  ]))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _results.length,
                  itemBuilder: (ctx, i) {
                    final r = _results[i];
                    final name = r.device.platformName;
                    final spine = isSpineGuard(name);

                    return Card(
                      elevation: spine ? 3 : 1,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: spine
                            ? const BorderSide(color: Color(0xFF1A2B4C), width: 2)
                            : BorderSide.none,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(children: [
                          // Icon
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: spine
                                ? const Color(0xFF1A2B4C)
                                : Colors.grey[200],
                            child: Icon(
                              spine ? Icons.sensors : Icons.bluetooth,
                              color: spine ? Colors.white : Colors.grey,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Flexible(
                                    child: Text(name,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: spine
                                            ? const Color(0xFF1A2B4C)
                                            : Colors.black87,
                                      )),
                                  ),
                                  if (spine) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1A2B4C),
                                        borderRadius: BorderRadius.circular(8)),
                                      child: const Text("NODE",
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ]),
                                const SizedBox(height: 3),
                                Text(r.device.remoteId.toString(),
                                    style: TextStyle(
                                        color: Colors.grey[500], fontSize: 11)),
                                const SizedBox(height: 4),
                                Row(children: [
                                  Icon(Icons.wifi, size: 13,
                                      color: rssiColor(r.rssi)),
                                  const SizedBox(width: 4),
                                  Text("${r.rssi} dBm",
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: rssiColor(r.rssi),
                                          fontWeight: FontWeight.w500)),
                                ]),
                              ],
                            ),
                          ),

                          // Connect button
                          ElevatedButton(
                            onPressed: () => selectDevice(r.device),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: spine
                                  ? const Color(0xFF1A2B4C)
                                  : Colors.grey[200],
                              foregroundColor:
                                  spine ? Colors.white : Colors.black87,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                            ),
                            child: const Text("Connect"),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
        ),

        // Scan button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _scanning ? stopScan : startScan,
              icon: Icon(_scanning ? Icons.stop : Icons.search),
              label: Text(_scanning ? "Stop Scan" : "Scan for Devices"),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _scanning ? Colors.red : const Color(0xFF1A2B4C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// DASHBOARD SCREEN
// ─────────────────────────────────────────────
class DashboardScreen extends StatefulWidget {
  final BluetoothDevice device;
  const DashboardScreen({super.key, required this.device});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  double pitch = 0, roll = 0, score = 100;
  String fatigue = "Alert";
  String status = "Connecting...";
  bool _live = false;
  StreamSubscription? _dataSub;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  // History data for drawer
  final List<Map<String, dynamic>> _history = [];

  final serviceUuid = Guid("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
  final txUuid      = Guid("6E400003-B5A3-F393-E0A9-E50E24DCCA9E");

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulse = Tween(begin: 0.6, end: 1.0).animate(_pulseCtrl);
    connectAndSubscribe();
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _pulseCtrl.dispose();
    widget.device.disconnect();
    super.dispose();
  }

  void connectAndSubscribe() async {
    try {
      await widget.device.connect(timeout: const Duration(seconds: 10));
      if (mounted) setState(() => status = "Discovering...");

      final services = await widget.device.discoverServices();
      bool found = false;

      for (final s in services) {
        for (final c in s.characteristics) {
          if ((c.uuid == txUuid || c.properties.notify) && !found) {
            await c.setNotifyValue(true);
            _dataSub = c.onValueReceived.listen((data) {
              parseData(String.fromCharCodes(data));
            });
            found = true;
            if (mounted) setState(() { status = "Streaming ✓"; _live = true; });
          }
        }
      }
      if (!found && mounted) setState(() => status = "No stream found");
    } catch (e) {
      if (mounted) setState(() => status = "Error: $e");
    }
  }

  void parseData(String msg) {
    try {
      double p = double.parse(msg.split("P:")[1].split(",")[0]);
      double r = double.parse(msg.split("R:")[1].split(",")[0]);
      double s = double.parse(msg.split("S:")[1].split(",")[0]);
      String f = msg.contains("F:")
          ? msg.split("F:")[1].trim().replaceAll("\n", "")
          : fatigue;
      if (mounted) {
        setState(() { pitch = p; roll = r; score = s; fatigue = f; });
        // Save to history
        _history.add({
          "time": TimeOfDay.now().format(context),
          "pitch": p, "roll": r, "score": s, "fatigue": f,
        });
        if (_history.length > 100) _history.removeAt(0);
      }
    } catch (_) {}
  }

  void showEmergencyDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.local_hospital, color: Colors.red),
          SizedBox(width: 8),
          Text("Emergency Help"),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text("Current Status:",
              style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 8),
          Text("Score: ${score.toInt()} | Fatigue: $fatigue",
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Text(
            "Do you want to alert your emergency contact?",
            textAlign: TextAlign.center,
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel")),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: Colors.red,
                  content: Text(
                    "🚨 Alert sent: Score ${score.toInt()}, $fatigue"),
                ));
            },
            icon: const Icon(Icons.send),
            label: const Text("Send Alert"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            )),
        ],
      ),
    );
  }

  Color scoreColor() {
    if (score >= 75) return Colors.green;
    if (score >= 45) return Colors.orange;
    return Colors.red;
  }

  Color fatigueColor() {
    if (fatigue == "Alert")     return Colors.green;
    if (fatigue == "Fatiguing") return Colors.orange;
    return Colors.red;
  }

  String postureLabel() {
    if (score >= 75) return "✅ Good Posture";
    if (score >= 45) return "⚠️ Moderate";
    return "❌ Bad Posture";
  }

  Color pitchBg() => pitch.abs() > 15
      ? Colors.orange.withOpacity(0.1)
      : Colors.white;

  Color rollBg() => roll.abs() > 15
      ? Colors.orange.withOpacity(0.1)
      : Colors.white;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      drawer: _buildDrawer(),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A2B4C),
        foregroundColor: Colors.white,
        title: Text(
          widget.device.platformName.isEmpty
              ? "SPINEGUARD"
              : widget.device.platformName,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_live)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(_pulse.value),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.circle, size: 8, color: Colors.white),
                      const SizedBox(width: 5),
                      const Text("LIVE",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: showEmergencyDialog,
        backgroundColor: Colors.red,
        child: const Icon(Icons.local_hospital, color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [

          // Score circle
          Center(
            child: Container(
              width: 180, height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scoreColor(),
                boxShadow: [BoxShadow(
                  color: scoreColor().withOpacity(0.35),
                  blurRadius: 24, spreadRadius: 6,
                )],
              ),
              child: Center(child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("${score.toInt()}",
                      style: const TextStyle(
                          fontSize: 54, fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const Text("/ 100",
                      style: TextStyle(color: Colors.white70, fontSize: 16)),
                ],
              )),
            ),
          ),
          const SizedBox(height: 18),

          Text(postureLabel(),
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),

          // Fatigue badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
            decoration: BoxDecoration(
              color: fatigueColor().withOpacity(0.1),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: fatigueColor(), width: 1.5),
            ),
            child: Text("Fatigue: $fatigue",
                style: TextStyle(
                    color: fatigueColor(), fontWeight: FontWeight.w600,
                    fontSize: 15)),
          ),
          const SizedBox(height: 24),

          // Pitch and Roll cards
          Row(children: [
            Expanded(child: _angleCard(
                "PITCH", "${pitch.toStringAsFixed(1)}°",
                "Forward tilt", pitchBg())),
            const SizedBox(width: 12),
            Expanded(child: _angleCard(
                "ROLL", "${roll.toStringAsFixed(1)}°",
                "Lateral lean", rollBg())),
          ]),
          const SizedBox(height: 20),

          // Score bar
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Posture Score",
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: score / 100,
                minHeight: 14,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation(scoreColor()),
              ),
            ),
          ]),
          const SizedBox(height: 20),

          // Status
          Text(status,
              style: TextStyle(color: Colors.grey[500], fontSize: 12)),

          const SizedBox(height: 80), // space for FAB
        ]),
      ),
    );
  }

  Widget _angleCard(String label, String value, String sub, Color bg) {
    return Card(
      elevation: 2,
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text(label,
              style: TextStyle(
                  color: Colors.grey[500], fontSize: 12, letterSpacing: 1)),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontSize: 30, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(sub,
              style: TextStyle(fontSize: 12, color: Colors.grey[400])),
        ]),
      ),
    );
  }

  Widget _buildDrawer() {
    double avgScore = _history.isEmpty
        ? 0
        : _history.map((h) => h["score"] as double).reduce((a, b) => a + b) /
            _history.length;

    int fatigueAlerts = _history
        .where((h) => h["fatigue"] == "Fatigued")
        .length;

    return Drawer(
      child: Column(children: [
        DrawerHeader(
          decoration: const BoxDecoration(color: Color(0xFF1A2B4C)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Icon(Icons.accessibility_new,
                  color: Colors.white, size: 40),
              const SizedBox(height: 8),
              const Text("PostureNet",
                  style: TextStyle(color: Colors.white,
                      fontSize: 20, fontWeight: FontWeight.bold)),
              Text("Session data",
                  style: TextStyle(color: Colors.white.withOpacity(0.7),
                      fontSize: 13)),
            ],
          ),
        ),

        ListTile(
          leading: const Icon(Icons.dashboard, color: Color(0xFF1A2B4C)),
          title: const Text("Dashboard"),
          onTap: () => Navigator.pop(context),
        ),

        ListTile(
          leading: const Icon(Icons.history, color: Color(0xFF1A2B4C)),
          title: const Text("Session History"),
          onTap: () {
            Navigator.pop(context);
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20))),
              builder: (_) => _HistorySheet(
                history: _history,
                avgScore: avgScore,
                fatigueAlerts: fatigueAlerts,
              ),
            );
          },
        ),

        ListTile(
          leading: const Icon(Icons.settings, color: Color(0xFF1A2B4C)),
          title: const Text("Settings"),
          onTap: () => Navigator.pop(context),
        ),

        const Divider(),

        ListTile(
          leading: const Icon(Icons.bluetooth_disabled, color: Colors.red),
          title: const Text("Disconnect",
              style: TextStyle(color: Colors.red)),
          onTap: () {
            widget.device.disconnect();
            Navigator.pop(context);
            Navigator.pop(context);
          },
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// HISTORY BOTTOM SHEET
// ─────────────────────────────────────────────
class _HistorySheet extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  final double avgScore;
  final int fatigueAlerts;

  const _HistorySheet({
    required this.history,
    required this.avgScore,
    required this.fatigueAlerts,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2)),
          )),
          const SizedBox(height: 16),

          const Text("Session History",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          // Summary cards
          Row(children: [
            _summaryCard("Avg Score",
                "${avgScore.toStringAsFixed(0)}%", Colors.indigo),
            const SizedBox(width: 12),
            _summaryCard("Fatigue Alerts",
                "$fatigueAlerts", Colors.orange),
            const SizedBox(width: 12),
            _summaryCard("Readings",
                "${history.length}", Colors.green),
          ]),
          const SizedBox(height: 20),

          const Text("Recent Readings",
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          history.isEmpty
              ? const Center(child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text("No data yet",
                      style: TextStyle(color: Colors.grey))))
              : Expanded(
                  child: ListView.builder(
                    controller: ctrl,
                    itemCount: history.length,
                    itemBuilder: (_, i) {
                      final h = history[history.length - 1 - i];
                      final s = (h["score"] as double).toInt();
                      Color c = s >= 75
                          ? Colors.green
                          : s >= 45
                              ? Colors.orange
                              : Colors.red;
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: c.withOpacity(0.2),
                          child: Text("$s",
                              style: TextStyle(
                                  fontSize: 11, color: c,
                                  fontWeight: FontWeight.bold)),
                        ),
                        title: Text(
                          "P:${(h["pitch"] as double).toStringAsFixed(1)}°  "
                          "R:${(h["roll"] as double).toStringAsFixed(1)}°",
                          style: const TextStyle(fontSize: 13)),
                        subtitle: Text(h["fatigue"] as String,
                            style: TextStyle(fontSize: 11, color: c)),
                        trailing: Text(h["time"] as String,
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 11)),
                      );
                    },
                  ),
                ),
        ]),
      ),
    );
  }

  Widget _summaryCard(String label, String value, Color color) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(children: [
        Text(value,
            style: TextStyle(fontSize: 20,
                fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: Colors.grey[600])),
      ]),
    ));
  }
}