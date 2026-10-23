import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../services/hrms_tracking_api.dart';
import '../../services/auth_storage.dart';
import '../../services/attendance_api.dart';
import '../../services/attendance_location.dart';
import 'android_live_tracking_service.dart';

/// App-level owner for a Field/Hybrid live-tracking session.  Pages can be
/// created and disposed freely; the timer and active session remain here.
class LiveTrackingCoordinator extends ChangeNotifier with WidgetsBindingObserver {
  LiveTrackingCoordinator() {
    WidgetsBinding.instance.addObserver(this);
  }

  Timer? _pingTimer;
  Timer? _autoClockoutTimer;
  bool _initialized = false;
  bool _busy = false;
  bool _active = false;
  int _pingMinutes = 15;
  Map<String, dynamic>? _autoWarning;

  bool get active => _active;
  bool get busy => _busy;
  Map<String, dynamic>? get autoClockoutWarning => _autoWarning;

  Future<void> restore() async {
    if (_initialized) return;
    _initialized = true;
    await _syncSession();
    _armAutoClockoutMonitor();
  }

  Future<void> refreshFromServer() => _syncSession();

  Future<void> _syncSession() async {
    try {
      final results = await Future.wait([
        HrmsTrackingApi.fieldSession(),
        HrmsTrackingApi.trackingSettings(),
      ]);
      final session = results[0];
      final settings = results[1];
      _active = session['is_active'] == true || session['is_active'] == 1 || session['isActive'] == true;
      final value = settings['field_ping_interval_minutes'] ?? settings['fieldPingIntervalMinutes'];
      _pingMinutes = (value is num ? value.toInt() : int.tryParse('$value'))?.clamp(1, 1440) ?? 15;
      if (_active) {
        if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
          _armTimer();
        } else {
          await AndroidLiveTrackingService.start(employeeName: await _employeeName(), pingMinutes: _pingMinutes);
        }
      } else {
        _cancelTimer();
        await AndroidLiveTrackingService.stop();
      }
      notifyListeners();
    } catch (_) {
      _initialized = false;
      _active = false;
      _cancelTimer();
      await AndroidLiveTrackingService.stop();
      notifyListeners();
    }
  }

  void _armAutoClockoutMonitor() {
    _autoClockoutTimer?.cancel();
    _autoClockoutTimer = Timer.periodic(const Duration(minutes: 1), (_) => _checkAutoClockout());
    _checkAutoClockout();
  }

  Future<void> _checkAutoClockout() async {
    if (_busy || _autoWarning != null) return;
    try {
      final dashboard = await AttendanceApi.dashboard(DateTime.now());
      if (dashboard['status'] != 'checked_in') return;
      final mode = '${dashboard['work_mode'] ?? ''}';
      if (mode != 'Office' && mode != 'Home') return;
      final position = await AttendanceLocation.currentPosition();
      final result = await AttendanceApi.heartbeat(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        capturedAt: position.timestamp,
      );
      final warning = result['autoClockout'];
      if (warning is Map && warning['warning'] == true) {
        _autoWarning = Map<String, dynamic>.from(warning);
        notifyListeners();
      }
    } catch (_) {
      // GPS/network/permission failures must never trigger auto clock-out.
    }
  }

  Future<void> respondToAutoClockoutWarning() async {
    await AttendanceApi.autoClockoutResponse(action: 'still_working');
    _autoWarning = null;
    notifyListeners();
  }

  void dismissAutoClockoutWarning() {
    _autoWarning = null;
    notifyListeners();
  }

  Future<Position> _position({bool requireBackground = false}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Please turn on device location services.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw Exception('Location permission is required for live tracking.');
    }
    // Android foreground service tracking must be granted "Allow all the time".
    // Web keeps browser best-effort tracking and does not expose this permission.
    if (requireBackground && !kIsWeb && permission != LocationPermission.always) {
      throw Exception('Allow location access all the time in Android settings before starting live tracking.');
    }
    // Do not reuse an old provider reading for Start/Stop.  In particular, a
    // stale reading at Stop made the final map point appear far from the
    // employee's actual location. AttendanceLocation rejects readings older
    // than two minutes and has a GPS timeout/error message the user can act on.
    return AttendanceLocation.currentPosition();
  }

  void _armTimer() {
    _cancelTimer();
    _autoClockoutTimer?.cancel();
    _pingTimer = Timer.periodic(Duration(minutes: _pingMinutes), (_) => sendPing());
  }

  void _cancelTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  Future<void> start() async {
    if (_busy || _active) return;
    _busy = true; notifyListeners();
    try {
      final position = await _position(requireBackground: defaultTargetPlatform == TargetPlatform.android);
      final started = await HrmsTrackingApi.startFieldSession(latitude: position.latitude, longitude: position.longitude, accuracy: position.accuracy, isMocked: position.isMocked);
      final template = started['template'];
      final assignedMinutes = template is Map
          ? (template['fieldPingIntervalMinutes'] ?? template['field_ping_interval_minutes'])
          : null;
      final parsedMinutes = assignedMinutes is num ? assignedMinutes.toInt() : int.tryParse('$assignedMinutes');
      if (parsedMinutes != null && parsedMinutes > 0) _pingMinutes = parsedMinutes;
      _active = true;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await AndroidLiveTrackingService.start(employeeName: await _employeeName(), pingMinutes: _pingMinutes);
      } else {
        _armTimer();
      }
    } finally {
      _busy = false; notifyListeners();
    }
  }

  Future<String> _employeeName() async {
    try {
      final stored = await AuthStorage.getString('user_data');
      final parsed = stored == null ? null : jsonDecode(stored);
      final user = parsed is Map ? parsed : const <String, dynamic>{};
      return '${user['fullName'] ?? user['name'] ?? user['username'] ?? 'Employee'}';
    } catch (_) {
      return 'Employee';
    }
  }

  Future<void> stop(String reason) async {
    if (_busy || !_active) return;
    _busy = true; notifyListeners();
    try {
      final position = await _position();
      await HrmsTrackingApi.stopFieldSession(reason: reason, latitude: position.latitude, longitude: position.longitude, accuracy: position.accuracy, isMocked: position.isMocked);
      _active = false;
      _cancelTimer();
      await AndroidLiveTrackingService.stop();
    } finally {
      _busy = false; notifyListeners();
    }
  }

  /// The only deliberate page action that emits an immediate new GPS ping.
  Future<void> sendPing() async {
    if (!_active || _busy) return;
    try {
      final position = await _position();
      await HrmsTrackingApi.ping(latitude: position.latitude, longitude: position.longitude, accuracy: position.accuracy, isMocked: position.isMocked);
    } catch (_) {
      // A later scheduled tick can recover from a temporary GPS/network error.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Sync state after browser/app resume. Do not create an extra ping.
      _syncSession();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelTimer();
    super.dispose();
  }
}

/// Lightweight navigation signal used by the mandatory waiting-comment host.
class EmployeeRouteSignal extends NavigatorObserver {
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  void _changed() => revision.value++;
  @override void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _changed();
  @override void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _changed();
  @override void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _changed();
}

final employeeRouteSignal = EmployeeRouteSignal();
