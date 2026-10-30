import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const SarvaShieldApp());
}

class SarvaShieldApp extends StatelessWidget {
  const SarvaShieldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SARVA-SHIELD v5',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF070B19),
        primaryColor: const Color(0xFFFF1744),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF1744),
          secondary: Color(0xFF00E5FF),
          surface: Color(0xFF111827),
        ),
      ),
      home: const RoleSelectionScreen(),
    );
  }
}

// ============================================================================
// SCREEN 1: STARTUP HUB (WEARER BLUETOOTH MODE OR GUARDIAN REMOTE TRACKER)
// ============================================================================
class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  List<BluetoothDevice> _devices = [];
  bool _isConnecting = false;
  String _statusText = "Initializing SARVA-SHIELD Hardware Bridge...";
  String _mySyncCode = "------";
  final TextEditingController _guardianCodeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initSystem();
  }

  Future<void> _initSystem() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? savedCode = prefs.getString('sarva_sync_code');
      if (savedCode == null || savedCode.length != 6) {
        savedCode = (100000 + Random().nextInt(900000)).toString();
        await prefs.setString('sarva_sync_code', savedCode);
      }
      if (mounted) {
        setState(() {
          _mySyncCode = savedCode!;
        });
      }
    } catch (_) {}

    try {
      await [
        Permission.bluetooth,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.location,
        Permission.locationWhenInUse,
      ].request();
    } catch (_) {}

    await _scanPairedDevices();
  }

  Future<void> _scanPairedDevices() async {
    try {
      List<BluetoothDevice> bonded =
          await FlutterBluetoothSerial.instance.getBondedDevices();
      bonded.sort((a, b) {
        bool aSarva = (a.name ?? "").toUpperCase().contains("SARVA");
        bool bSarva = (b.name ?? "").toUpperCase().contains("SARVA");
        if (aSarva && !bSarva) return -1;
        if (!aSarva && bSarva) return 1;
        return (a.name ?? "").compareTo(b.name ?? "");
      });

      if (!mounted) return;
      setState(() {
        _devices = bonded;
        _statusText = bonded.isEmpty
            ? "No paired Bluetooth devices found. Pair 'SARVA-SHIELD-v4' in Android Bluetooth Settings first."
            : "Select your SARVA-SHIELD wearable to arm live protection:";
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusText =
            "Bluetooth scan notice: Please enable Bluetooth & Location permissions.";
      });
    }
  }

  Future<void> _connectToWearable(BluetoothDevice device) async {
    setState(() {
      _isConnecting = true;
      _statusText =
          "Linking with ${device.name ?? 'Wearable'} (${device.address})...";
    });

    try {
      BluetoothConnection connection =
          await BluetoothConnection.toAddress(device.address)
              .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => MasterCommandScreen(
            initialConnection: connection,
            deviceAddress: device.address,
            deviceName: device.name ?? "SARVA-SHIELD-v4",
            syncCode: _mySyncCode,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _statusText =
            "Connection Failed! Ensure ESP32 is powered ON and disconnected from Serial Bluetooth Terminal app.";
      });
    }
  }

  void _openGuardianOnlyMode() {
    String code = _guardianCodeCtrl.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Enter a valid 6-digit Victim Sync ID to track!"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StandaloneGuardianScreen(targetSyncCode: code),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        elevation: 4,
        title: const Row(
          children: [
            Icon(Icons.shield, color: Color(0xFFFF1744)),
            SizedBox(width: 10),
            Text(
              "SARVA-SHIELD v5",
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.1),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF00E5FF)),
            onPressed: _scanPairedDevices,
            tooltip: "Refresh Paired Devices",
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // TOP IDENTITY CARD
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF00E5FF).withOpacity(0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "WEARER CLOUD SYNC ID (SHARE WITH GUARDIAN)",
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF00E5FF),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _mySyncCode,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 6,
                          color: Colors.white,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _mySyncCode));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Sync ID Copied!")),
                          );
                        },
                        icon: const Icon(
                          Icons.copy,
                          size: 18,
                          color: Color(0xFF00E5FF),
                        ),
                        label: const Text(
                          "COPY ID",
                          style: TextStyle(color: Color(0xFF00E5FF)),
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    "Zero Fake Data Architecture • Direct ESP32 Hardware Telemetry + 3-Tier Indoor Location Fail-Safe",
                    style: TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // MODE 1: WEARER HARDWARE LINK
            const Text(
              "1. WEARER MODE (CONNECT ESP32 HARDWARE)",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.amberAccent,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _statusText,
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 12),

            if (_isConnecting)
              const Padding(
                padding: EdgeInsets.all(24.0),
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF1744)),
                ),
              )
            else if (_devices.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  "No paired devices found. Open Android Settings -> Bluetooth -> Pair with 'SARVA-SHIELD-v4', then tap Refresh above.",
                  style: TextStyle(color: Colors.orangeAccent),
                ),
              )
            else
              ..._devices.map((device) {
                bool isSarva =
                    (device.name ?? "").toUpperCase().contains("SARVA");
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: isSarva
                        ? const Color(0xFF1F1235)
                        : const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSarva
                          ? const Color(0xFFFF1744)
                          : Colors.white12,
                      width: isSarva ? 1.8 : 1.0,
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(
                      Icons.bluetooth_connected,
                      color: isSarva
                          ? const Color(0xFFFF1744)
                          : Colors.blueGrey,
                      size: 32,
                    ),
                    title: Text(
                      device.name ?? "Unknown Device",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    subtitle: Text(
                      isSarva
                          ? "⚡ SARVA-SHIELD Hardware (${device.address})"
                          : device.address,
                      style: TextStyle(
                        color: isSarva ? Colors.greenAccent : Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSarva
                            ? const Color(0xFFFF1744)
                            : Colors.blueGrey.shade700,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => _connectToWearable(device),
                      child: const Text("ARM"),
                    ),
                  ),
                );
              }),

            const SizedBox(height: 24),
            const Divider(color: Colors.white24),
            const SizedBox(height: 12),

            // MODE 2: GUARDIAN REMOTE LIVE TRACKER
            const Text(
              "2. GUARDIAN MODE (TRACK VICTIM LIVE OVER INTERNET)",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFF00E5FF),
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    "Parents, Guardians, or Police can enter the wearer's 6-Digit Sync ID below to watch live Vitals, Impact Alerts, and Real-Time Map location from anywhere:",
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _guardianCodeCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    style: const TextStyle(
                      fontSize: 20,
                      letterSpacing: 6,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      counterText: "",
                      hintText: "Enter 6-Digit Sync ID",
                      hintStyle:
                          const TextStyle(fontSize: 14, letterSpacing: 1),
                      filled: true,
                      fillColor: const Color(0xFF070B19),
                      prefixIcon: const Icon(
                        Icons.radar,
                        color: Color(0xFF00E5FF),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _openGuardianOnlyMode,
                    icon: const Icon(Icons.track_changes),
                    label: const Text(
                      "LAUNCH LIVE GUARDIAN RADAR",
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// SCREEN 2: MASTER 4-TAB COMMAND STATION (WEARER CONNECTED TO ESP32)
// ============================================================================
class MasterCommandScreen extends StatefulWidget {
  final BluetoothConnection initialConnection;
  final String deviceAddress;
  final String deviceName;
  final String syncCode;

  const MasterCommandScreen({
    super.key,
    required this.initialConnection,
    required this.deviceAddress,
    required this.deviceName,
    required this.syncCode,
  });

  @override
  State<MasterCommandScreen> createState() => _MasterCommandScreenState();
}

class _MasterCommandScreenState extends State<MasterCommandScreen> {
  BluetoothConnection? _connection;
  bool _btConnected = true;
  bool _reconnecting = false;
  int _selectedTab = 0;
  String _btBuffer = "";

  // REAL HARDWARE TELEMETRY STATE (ZERO FAKE DATA)
  int bpm = 0;
  int finger = 0;
  int irValue = 0;
  double currentG = 1.00;
  double sessionPeakG = 1.00;
  int gpsFix = 0;
  int satellites = 0;
  int hasCache = 0;
  double lat = 26.349211;
  double lng = 92.707514;
  int sosFlag = 0;
  String triggerSource = "NONE";
  int packetsReceived = 0;

  // 3-TIER HYBRID INDOOR LOCATION STATE
  int activeLocationTier = 1; // 1 = Satellite, 2 = Indoor Fused, 3 = Cache
  String locationMode = "Waiting for ESP32 Telemetry...";
  double indoorAccuracyMeters = 0.0;
  DateTime? _lastIndoorFetch;
  final List<LatLng> _breadcrumbs = [];
  final MapController _mapController = MapController();

  // EMERGENCY COUNTDOWN & DISPATCH STATE
  bool isEmergencyActive = false;
  int countdownSeconds = 10;
  Timer? _countdownTimer;
  bool emergencyDispatched = false;

  // GUARDIAN CONTACTS & BLACKBOX LOGS
  List<String> _emergencyContacts = ["112"];
  final TextEditingController _contactInputCtrl = TextEditingController();
  final List<String> _blackboxLogs = [];
  DateTime? _lastCloudPush;

  @override
  void initState() {
    super.initState();
    _connection = widget.initialConnection;
    _loadContacts();
    _attachStreamListener(_connection!);
  }

  Future<void> _loadContacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('sarva_contacts');
      if (saved != null && saved.isNotEmpty && mounted) {
        setState(() {
          _emergencyContacts = saved;
        });
      }
    } catch (_) {}
  }

  Future<void> _addContact(String phone) async {
    String clean = phone.trim();
    if (clean.isEmpty) return;
    if (!_emergencyContacts.contains(clean)) {
      setState(() {
        _emergencyContacts.add(clean);
      });
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('sarva_contacts', _emergencyContacts);
      } catch (_) {}
    }
    _contactInputCtrl.clear();
  }

  Future<void> _removeContact(String phone) async {
    setState(() {
      _emergencyContacts.remove(phone);
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('sarva_contacts', _emergencyContacts);
    } catch (_) {}
  }

  void _attachStreamListener(BluetoothConnection conn) {
    setState(() {
      _btConnected = true;
    });

    conn.input?.listen((Uint8List data) {
      _btBuffer += utf8.decode(data, allowMalformed: true);
      int newlineIdx = _btBuffer.indexOf('\n');
      while (newlineIdx >= 0) {
        String rawLine = _btBuffer.substring(0, newlineIdx).trim();
        _btBuffer = _btBuffer.substring(newlineIdx + 1);
        if (rawLine.isNotEmpty) {
          _processIncomingLine(rawLine);
        }
        newlineIdx = _btBuffer.indexOf('\n');
      }
    }).onDone(() {
      if (mounted) {
        setState(() {
          _btConnected = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "⚠️ ESP32 Bluetooth Disconnected! Tap the Reconnect icon in top bar.",
            ),
            backgroundColor: Colors.redAccent,
            duration: Duration(seconds: 4),
          ),
        );
      }
    });
  }

  Future<void> _reconnectBluetooth() async {
    if (_reconnecting) return;
    setState(() {
      _reconnecting = true;
    });

    try {
      try {
        _connection?.dispose();
      } catch (_) {}

      BluetoothConnection newConn =
          await BluetoothConnection.toAddress(widget.deviceAddress)
              .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      _connection = newConn;
      _attachStreamListener(newConn);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🟢 Reconnected to SARVA-SHIELD Hardware!"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Reconnect failed. Check if ESP32 is powered on."),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _reconnecting = false;
        });
      }
    }
  }

  void _processIncomingLine(String line) {
    final DateTime now = DateTime.now();
    final String timestamp =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

    if (mounted) {
      setState(() {
        _blackboxLogs.insert(0, "[$timestamp] $line");
        if (_blackboxLogs.length > 60) {
          _blackboxLogs.removeLast();
        }
      });
    }

    int startIdx = line.indexOf('{');
    int endIdx = line.lastIndexOf('}');
    if (startIdx == -1 || endIdx == -1 || endIdx <= startIdx) return;

    String cleanJson = line.substring(startIdx, endIdx + 1);

    try {
      final Map<String, dynamic> data = jsonDecode(cleanJson);
      if (!mounted) return;

      setState(() {
        packetsReceived++;

        bpm = ((data['bpm'] ?? 0) as num).toInt();
        finger = ((data['finger'] ?? 0) as num).toInt();
        irValue = ((data['ir'] ?? 0) as num).toInt();
        currentG = ((data['g'] ?? 1.0) as num).toDouble();
        if (currentG > sessionPeakG) {
          sessionPeakG = currentG;
        }

        gpsFix = ((data['gps_fix'] ?? 0) as num).toInt();
        satellites = ((data['sats'] ?? 0) as num).toInt();
        hasCache = ((data['has_cache'] ?? 0) as num).toInt();

        double espLat = ((data['lat'] ?? 0.0) as num).toDouble();
        double espLng = ((data['lng'] ?? 0.0) as num).toDouble();

        sosFlag = ((data['sos'] ?? 0) as num).toInt();
        triggerSource = (data['trig'] ?? "NONE").toString();

        // TIER 1: SATELLITE GPS ACTIVE
        if (gpsFix == 1 && espLat != 0.0 && espLng != 0.0) {
          lat = espLat;
          lng = espLng;
          activeLocationTier = 1;
          locationMode =
              "🛰️ TIER-1 ACTIVE: Direct Satellite Lock ($satellites Sats)";
          _addBreadcrumb(LatLng(lat, lng));
          if (_selectedTab == 1) {
            try {
              _mapController.move(LatLng(lat, lng), 16.5);
            } catch (_) {}
          }
        } else {
          // TIER 2: INDOOR MOBILE NETWORK TRIANGULATION FALLBACK
          _triggerIndoorHybridFallback(espLat, espLng);
        }

        // EMERGENCY DETECTION (MANUAL SOS OR >= 2.5G IMPACT)
        if (sosFlag == 1 || currentG >= 2.50) {
          if (triggerSource == "NONE" && currentG >= 2.50) {
            triggerSource = "AUTO_IMPACT (${currentG.toStringAsFixed(2)}G)";
          }
          _activateEmergencyProtocol();
        }
      });

      _syncToGuardianCloud(forceImmediate: sosFlag == 1 || currentG >= 2.50);
    } catch (_) {}
  }

  Future<void> _triggerIndoorHybridFallback(
      double cachedEspLat, double cachedEspLng) async {
    final now = DateTime.now();
    if (_lastIndoorFetch != null &&
        now.difference(_lastIndoorFetch!).inSeconds < 4) {
      return;
    }
    _lastIndoorFetch = now;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception("Location off");
      }

      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 4));

      if (!mounted) return;
      setState(() {
        lat = pos.latitude;
        lng = pos.longitude;
        indoorAccuracyMeters = pos.accuracy;
        activeLocationTier = 2;
        locationMode =
            "🏢 TIER-2 INDOOR ACTIVE: Phone Wi-Fi/Cell Triangulation (±${pos.accuracy.toStringAsFixed(0)}m)";
        _addBreadcrumb(LatLng(lat, lng));
        if (_selectedTab == 1) {
          try {
            _mapController.move(LatLng(lat, lng), 17.0);
          } catch (_) {}
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        activeLocationTier = 3;
        if (hasCache == 1 && cachedEspLat != 0.0 && cachedEspLng != 0.0) {
          lat = cachedEspLat;
          lng = cachedEspLng;
          locationMode =
              "📌 TIER-3 CACHE ACTIVE: Last Verified Outdoor Satellite Coordinate";
        } else {
          locationMode =
              "🔍 Searching Satellites ($satellites Sats) — Enable Phone Location for Indoor Lock";
        }
      });
    }
  }

  void _addBreadcrumb(LatLng point) {
    if (_breadcrumbs.isEmpty ||
        (_breadcrumbs.last.latitude - point.latitude).abs() > 0.00002 ||
        (_breadcrumbs.last.longitude - point.longitude).abs() > 0.00002) {
      _breadcrumbs.add(point);
      if (_breadcrumbs.length > 100) {
        _breadcrumbs.removeAt(0);
      }
    }
  }

  void _activateEmergencyProtocol() {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);

    if (isEmergencyActive) return;

    setState(() {
      isEmergencyActive = true;
      countdownSeconds = 10;
      emergencyDispatched = false;
    });

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);

      setState(() {
        if (countdownSeconds > 1) {
          countdownSeconds--;
        } else {
          timer.cancel();
          if (!emergencyDispatched) {
            _dispatchEmergencySMS();
          }
        }
      });
    });
  }

  void _cancelFalseAlarm() {
    _countdownTimer?.cancel();
    setState(() {
      isEmergencyActive = false;
      emergencyDispatched = false;
      sosFlag = 0;
      triggerSource = "NONE";
    });
    _syncToGuardianCloud(forceImmediate: true);
  }

  Future<void> _dispatchEmergencySMS() async {
    _countdownTimer?.cancel();
    setState(() {
      emergencyDispatched = true;
    });

    final String mapUrl =
        "https://maps.google.com/?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}";
    final String msg =
        "🚨 SARVA-SHIELD EMERGENCY ALERT 🚨\n"
        "Trigger: $triggerSource\n"
        "Heart Rate: ${finger == 1 ? '$bpm BPM' : 'No Finger on Sensor'}\n"
        "Peak Impact: ${sessionPeakG.toStringAsFixed(2)} G\n"
        "Pos Mode: $locationMode\n"
        "Live Map: $mapUrl\n"
        "Guardian Sync ID: ${widget.syncCode}";

    final String recipients = _emergencyContacts.join(",");
    final Uri smsUri =
        Uri.parse("sms:$recipients?body=${Uri.encodeComponent(msg)}");
    try {
      await launchUrl(smsUri);
    } catch (_) {}
  }

  Future<void> _syncToGuardianCloud({bool forceImmediate = false}) async {
    final now = DateTime.now();
    if (!forceImmediate &&
        _lastCloudPush != null &&
        now.difference(_lastCloudPush!).inMilliseconds < 2500) {
      return;
    }
    _lastCloudPush = now;

    final Map<String, dynamic> cloudPayload = {
      "sync_id": widget.syncCode,
      "bpm": finger == 1 ? bpm : 0,
      "finger": finger,
      "ir": irValue,
      "g": currentG,
      "peak_g": sessionPeakG,
      "gps_fix": gpsFix,
      "sats": satellites,
      "lat": lat,
      "lng": lng,
      "tier": activeLocationTier,
      "loc_mode": locationMode,
      "sos": isEmergencyActive ? 1 : sosFlag,
      "trig": triggerSource,
      "ts":
          "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}",
    };

    try {
      await http
          .post(
            Uri.parse("https://ntfy.sh/sarva_shield_v5_${widget.syncCode}"),
            body: jsonEncode(cloudPayload),
          )
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  Future<void> _openExternalGoogleMaps() async {
    final Uri url = Uri.parse(
        "https://www.google.com/maps/search/?api=1&query=$lat,$lng");
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  String _getFingerCoachingText() {
    if (finger == 0 || irValue < 20000) {
      return "🔴 No Finger Detected — Rest fingertip gently on MAX30102 Red LED";
    }
    if (irValue > 145000) {
      return "⚠️ Pressing Too Hard! Relax finger pressure slightly for accurate BPM";
    }
    if (bpm == 0) {
      return "🟡 Finger Detected (IR: $irValue) — Locking onto pulse wave...";
    }
    return "🟢 Optimal Pulse Lock (IR: $irValue) — Live Heart Rate Active";
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    try {
      _connection?.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: isEmergencyActive
            ? const Color(0xFFB71C1C)
            : const Color(0xFF111827),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEmergencyActive
                  ? "🚨 EMERGENCY PROTOCOL ACTIVE"
                  : "🛡️ ${widget.deviceName}",
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            Text(
              "Sync ID: ${widget.syncCode} • Packets: $packetsReceived",
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          if (!_btConnected)
            IconButton(
              icon: _reconnecting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bluetooth_searching,
                      color: Colors.amberAccent),
              onPressed: _reconnectBluetooth,
              tooltip: "Reconnect ESP32",
            ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _btConnected
                  ? Colors.green.withOpacity(0.2)
                  : Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _btConnected ? Colors.greenAccent : Colors.redAccent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 8,
                  color: _btConnected ? Colors.greenAccent : Colors.redAccent,
                ),
                const SizedBox(width: 5),
                Text(
                  _btConnected ? "LIVE BT" : "OFFLINE",
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // PERSISTENT EMERGENCY OVERRIDE BANNER
          if (isEmergencyActive)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Color(0xFFD50000),
                border:
                    Border(bottom: BorderSide(color: Colors.white, width: 2)),
              ),
              child: Column(
                children: [
                  Text(
                    emergencyDispatched
                        ? "🚨 SOS ALERT DISPATCHED TO GUARDIANS!"
                        : "🚨 EMERGENCY TRIGGERED ($triggerSource) — AUTO SMS IN ${countdownSeconds}s",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.red.shade900,
                          ),
                          onPressed: _cancelFalseAlarm,
                          icon: const Icon(Icons.cancel),
                          label: const Text(
                            "FALSE ALARM (CANCEL)",
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.yellowAccent,
                          ),
                          onPressed: _dispatchEmergencySMS,
                          icon: const Icon(Icons.send),
                          label: const Text(
                            "SEND SOS NOW",
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // MAIN BODY CONTENT BY SELECTED TAB
          Expanded(
            child: _buildSelectedTabBody(),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedTab,
        onTap: (idx) => setState(() => _selectedTab = idx),
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF111827),
        selectedItemColor: const Color(0xFF00E5FF),
        unselectedItemColor: Colors.white54,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard), label: "SHIELD"),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: "LIVE MAP"),
          BottomNavigationBarItem(icon: Icon(Icons.radar), label: "GUARDIAN"),
          BottomNavigationBarItem(
              icon: Icon(Icons.terminal), label: "BLACKBOX"),
        ],
      ),
    );
  }

  Widget _buildSelectedTabBody() {
    switch (_selectedTab) {
      case 0:
        return _buildShieldDashboardTab();
      case 1:
        return _buildLiveMapTab();
      case 2:
        return StandaloneGuardianView(
          targetSyncCode: widget.syncCode,
          isEmbedded: true,
        );
      case 3:
        return _buildContactsAndBlackboxTab();
      default:
        return _buildShieldDashboardTab();
    }
  }

  // --------------------------------------------------------------------------
  // TAB 1: SHIELD LIVE SENSOR TELEMETRY DASHBOARD
  // --------------------------------------------------------------------------
  Widget _buildShieldDashboardTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // VITALS ROW: HEART RATE & G-FORCE
          Row(
            children: [
              // MAX30102 HEART RATE CARD
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: finger == 1 ? Colors.redAccent : Colors.white12,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("MAX30102",
                              style: TextStyle(
                                  fontSize: 11, color: Colors.white54)),
                          Icon(Icons.favorite,
                              color: Color(0xFFFF1744), size: 22),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "${finger == 1 ? bpm : 0}",
                        style: const TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      const Text(
                        "BPM (LIVE PULSE)",
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white60,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: finger == 1
                              ? Colors.green.withOpacity(0.15)
                              : Colors.orange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          finger == 1 ? "🟢 FINGER ON" : "🔴 NO FINGER",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: finger == 1
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // MPU6500 G-FORCE IMPACT CARD
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: currentG >= 2.5
                          ? Colors.amberAccent
                          : Colors.white12,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("MPU6500",
                              style: TextStyle(
                                  fontSize: 11, color: Colors.white54)),
                          Icon(Icons.speed,
                              color: Colors.amberAccent, size: 22),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "${currentG.toStringAsFixed(2)}G",
                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          color: currentG >= 2.5
                              ? Colors.redAccent
                              : Colors.white,
                        ),
                      ),
                      Text(
                        "PEAK: ${sessionPeakG.toStringAsFixed(2)}G (LIM: 2.5G)",
                        style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white60,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: currentG >= 2.5
                              ? Colors.red.withOpacity(0.2)
                              : Colors.cyan.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          currentG >= 2.5
                              ? "⚠️ IMPACT ALERT"
                              : "🟢 STABLE MOTION",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: currentG >= 2.5
                                ? Colors.redAccent
                                : const Color(0xFF00E5FF),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // MAX30102 IR OPTICAL COACH BAR
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                const Icon(Icons.fingerprint,
                    color: Color(0xFF00E5FF), size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _getFingerCoachingText(),
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // HYBRID 3-TIER LOCATION PIPELINE CARD (JUDGE PROOF MATRIX)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: const Color(0xFF00E5FF).withOpacity(0.45)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.satellite_alt, color: Color(0xFF00E5FF)),
                        SizedBox(width: 8),
                        Text(
                          "3-TIER INDOOR/OUTDOOR LOCATION ENGINE",
                          style: TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 12),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: gpsFix == 1
                            ? Colors.green.shade900
                            : Colors.orange.shade900,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        "SATS: $satellites",
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.white24, height: 18),

                // VISUAL 3-TIER STATUS ROWS FOR JUDGES
                _buildTierRow(
                  tierNum: 1,
                  title: "Tier-1: ESP32 NEO-6M Satellite GPS",
                  status: gpsFix == 1
                      ? "ACTIVE ($satellites Satellites Locked)"
                      : "ROOF OBSTRUCTION — SWITCHED TO TIER-2",
                  isActive: activeLocationTier == 1 && gpsFix == 1,
                ),
                const SizedBox(height: 6),
                _buildTierRow(
                  tierNum: 2,
                  title: "Tier-2: Indoor Wi-Fi / Cellular Triangulation",
                  status: activeLocationTier == 2
                      ? "ACTIVE INDOOR OVERRIDE (±${indoorAccuracyMeters.toStringAsFixed(0)}m)"
                      : "STANDBY (Auto-Activates Indoors)",
                  isActive: activeLocationTier == 2,
                ),
                const SizedBox(height: 6),
                _buildTierRow(
                  tierNum: 3,
                  title: "Tier-3: Last Verified Satellite Cache",
                  status: hasCache == 1
                      ? "READY IN MEMORY"
                      : "WAITING FOR FIRST LOCK",
                  isActive: activeLocationTier == 3,
                ),

                const Divider(color: Colors.white24, height: 18),
                Text(
                  locationMode,
                  style: const TextStyle(
                    color: Colors.amberAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "LAT: ${lat.toStringAsFixed(6)}",
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        "LNG: ${lng.toStringAsFixed(6)}",
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () => setState(() => _selectedTab = 1),
                        icon: const Icon(Icons.map),
                        label: const Text(
                          "LIVE MAP",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                        ),
                        onPressed: _openExternalGoogleMaps,
                        icon: const Icon(Icons.open_in_new),
                        label: const Text("GOOGLE MAPS"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // MANUAL SOFTWARE SOS OVERRIDE BUTTON
          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF1744),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () {
                setState(() {
                  sosFlag = 1;
                  triggerSource = "APP_MANUAL_SOS";
                });
                _activateEmergencyProtocol();
                _syncToGuardianCloud(forceImmediate: true);
              },
              icon: const Icon(Icons.sos, size: 28),
              label: const Text(
                "TRIGGER INSTANT SOS DISPATCH",
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTierRow({
    required int tierNum,
    required String title,
    required String status,
    required bool isActive,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isActive
            ? Colors.green.withOpacity(0.15)
            : const Color(0xFF070B19),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive ? Colors.greenAccent : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isActive ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16,
            color: isActive ? Colors.greenAccent : Colors.white38,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isActive ? Colors.white : Colors.white70,
                  ),
                ),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 10,
                    color: isActive ? Colors.greenAccent : Colors.white54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // TAB 2: INTERACTIVE LIVE OPENSTREETMAP WITH BREADCRUMB TRAIL
  // --------------------------------------------------------------------------
  Widget _buildLiveMapTab() {
    final LatLng currentPos = LatLng(lat, lng);
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: currentPos,
            initialZoom: 16.5,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.tml.sarvashield',
            ),
            if (_breadcrumbs.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _breadcrumbs,
                    color: const Color(0xFF00E5FF),
                    strokeWidth: 4.5,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                Marker(
                  point: currentPos,
                  width: 75,
                  height: 75,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              isEmergencyActive ? Colors.red : Colors.black87,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          "${finger == 1 ? bpm : 0} BPM",
                          style: const TextStyle(
                              fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Icon(
                        Icons.location_on,
                        color: isEmergencyActive
                            ? const Color(0xFFFF1744)
                            : const Color(0xFF00E5FF),
                        size: 40,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF070B19).withOpacity(0.92),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  locationMode,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.amberAccent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Coords: ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)} • Trail Points: ${_breadcrumbs.length}",
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton.extended(
            backgroundColor: const Color(0xFF00E5FF),
            foregroundColor: Colors.black,
            onPressed: () {
              try {
                _mapController.move(currentPos, 17.0);
              } catch (_) {}
            },
            icon: const Icon(Icons.my_location),
            label: const Text("RE-CENTER",
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // TAB 4: EMERGENCY CONTACTS & LIVE BLACKBOX TELEMETRY CONSOLE
  // --------------------------------------------------------------------------
  Widget _buildContactsAndBlackboxTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "EMERGENCY GUARDIAN CONTACTS (AUTO-SMS RECIPIENTS)",
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF00E5FF)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _contactInputCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: "Enter Guardian Phone Number",
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFF111827),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF1744)),
                onPressed: () => _addContact(_contactInputCtrl.text),
                child: const Text("ADD"),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _emergencyContacts
                .map(
                  (c) => Chip(
                    backgroundColor: const Color(0xFF1E293B),
                    label:
                        Text(c, style: const TextStyle(color: Colors.white)),
                    onDeleted: () => _removeContact(c),
                  ),
                )
                .toList(),
          ),
          const Divider(color: Colors.white24, height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "LIVE ESP32 BLACKBOX JSON STREAM",
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.amberAccent),
              ),
              TextButton(
                onPressed: () => setState(() => _blackboxLogs.clear()),
                child: const Text("CLEAR LOG"),
              ),
            ],
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: Colors.greenAccent.withOpacity(0.3)),
              ),
              child: _blackboxLogs.isEmpty
                  ? const Center(
                      child: Text(
                        "Waiting for JSON packets from SARVA-SHIELD-v4...",
                        style: TextStyle(
                            color: Colors.white38, fontFamily: 'monospace'),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _blackboxLogs.length,
                      itemBuilder: (context, idx) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          _blackboxLogs[idx],
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SCREEN 3: GUARDIAN REMOTE LIVE TRACKING PORTAL (WORKS OVER INTERNET)
// ============================================================================
class StandaloneGuardianScreen extends StatelessWidget {
  final String targetSyncCode;

  const StandaloneGuardianScreen({super.key, required this.targetSyncCode});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        title: Text("👁️ GUARDIAN RADAR • ID: $targetSyncCode"),
      ),
      body: StandaloneGuardianView(
        targetSyncCode: targetSyncCode,
        isEmbedded: false,
      ),
    );
  }
}

class StandaloneGuardianView extends StatefulWidget {
  final String targetSyncCode;
  final bool isEmbedded;

  const StandaloneGuardianView({
    super.key,
    required this.targetSyncCode,
    required this.isEmbedded,
  });

  @override
  State<StandaloneGuardianView> createState() =>
      _StandaloneGuardianViewState();
}

class _StandaloneGuardianViewState extends State<StandaloneGuardianView> {
  Timer? _pollTimer;
  Map<String, dynamic>? _latestVictimData;
  String _guardianStatus = "Connecting to SARVA-SHIELD Cloud Channel...";
  String _lastAlertTimestamp = "";
  final MapController _guardianMapCtrl = MapController();

  @override
  void initState() {
    super.initState();
    _pollCloudTelemetry();
    _pollTimer = Timer.periodic(
        const Duration(seconds: 3), (_) => _pollCloudTelemetry());
  }

  Future<void> _pollCloudTelemetry() async {
    try {
      final res = await http
          .get(Uri.parse(
              "https://ntfy.sh/sarva_shield_v5_${widget.targetSyncCode}/json?poll=1&since=15m"))
          .timeout(const Duration(seconds: 4));

      if (res.statusCode == 200 && res.body.trim().isNotEmpty) {
        final List<String> lines = res.body.trim().split('\n');
        for (int i = lines.length - 1; i >= 0; i--) {
          final Map<String, dynamic> wrapper = jsonDecode(lines[i]);
          if (wrapper['event'] == 'message' && wrapper['message'] != null) {
            final Map<String, dynamic> payload =
                jsonDecode(wrapper['message']);
            if (!mounted) return;
            final String packetTs = (payload['ts'] ?? "").toString();
            final int sosState = ((payload['sos'] ?? 0) as num).toInt();
            final double newLat =
                ((payload['lat'] ?? 26.349211) as num).toDouble();
            final double newLng =
                ((payload['lng'] ?? 92.707514) as num).toDouble();

            setState(() {
              _latestVictimData = payload;
              _guardianStatus =
                  "🟢 Live Cloud Sync Active (Last Update: $packetTs)";
            });

            try {
              _guardianMapCtrl.move(LatLng(newLat, newLng), 16.5);
            } catch (_) {}

            if (sosState == 1 && packetTs != _lastAlertTimestamp) {
              _lastAlertTimestamp = packetTs;
              HapticFeedback.heavyImpact();
              SystemSound.play(SystemSoundType.alert);
            }
            break;
          }
        }
      } else {
        if (!mounted) return;
        setState(() {
          _guardianStatus =
              "Waiting for wearer (ID: ${widget.targetSyncCode}) to broadcast live telemetry...";
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _latestVictimData;
    final double vLat = data != null
        ? ((data['lat'] ?? 26.349211) as num).toDouble()
        : 26.349211;
    final double vLng = data != null
        ? ((data['lng'] ?? 92.707514) as num).toDouble()
        : 92.707514;
    final int vBpm =
        data != null ? ((data['bpm'] ?? 0) as num).toInt() : 0;
    final double vG =
        data != null ? ((data['g'] ?? 1.0) as num).toDouble() : 1.0;
    final int vSos =
        data != null ? ((data['sos'] ?? 0) as num).toInt() : 0;
    final String vTrig =
        data != null ? (data['trig'] ?? "NONE").toString() : "NONE";
    final String vLocMode =
        data != null ? (data['loc_mode'] ?? "Unknown").toString() : "Waiting...";

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: vSos == 1 ? const Color(0xFFD50000) : const Color(0xFF1E293B),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                vSos == 1
                    ? "🚨 CRITICAL SOS ALERT FROM WEARER ($vTrig)!"
                    : "👁️ GUARDIAN LIVE TRACKING • SYNC ID: ${widget.targetSyncCode}",
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(_guardianStatus,
                  style: const TextStyle(fontSize: 11, color: Colors.white70)),
              if (data != null) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("❤️ Pulse: $vBpm BPM",
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text("⚡ Impact: ${vG.toStringAsFixed(2)}G",
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                        "📍 ${vLat.toStringAsFixed(4)}, ${vLng.toStringAsFixed(4)}",
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(vLocMode,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.amberAccent)),
              ],
            ],
          ),
        ),
        Expanded(
          child: FlutterMap(
            mapController: _guardianMapCtrl,
            options: MapOptions(
              initialCenter: LatLng(vLat, vLng),
              initialZoom: 16.5,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.tml.sarvashield',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(vLat, vLng),
                    width: 80,
                    height: 80,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: vSos == 1 ? Colors.red : Colors.black87,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            "$vBpm BPM",
                            style: const TextStyle(
                                fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Icon(
                          Icons.person_pin_circle,
                          color: vSos == 1
                              ? Colors.redAccent
                              : const Color(0xFF00E5FF),
                          size: 44,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}