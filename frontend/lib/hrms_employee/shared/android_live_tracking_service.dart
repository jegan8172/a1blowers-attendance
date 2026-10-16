import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

import '../../services/hrms_tracking_api.dart';
import '../../services/attendance_api.dart';

/// Android's visible foreground service. It owns scheduled GPS updates while
/// the app is backgrounded, and is stopped explicitly with the session.
class AndroidLiveTrackingService {
  static final FlutterBackgroundService _service = FlutterBackgroundService();
  static bool _configured = false;

  static Future<void> configure() async {
    if (kIsWeb || _configured) return;
    _configured = true;
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        initialNotificationTitle: 'Live tracking active',
        initialNotificationContent: 'Location updates are being saved',
        foregroundServiceNotificationId: 71402,
      ),
      iosConfiguration: IosConfiguration(onForeground: _onStart),
    );
  }

  static Future<void> start({required String employeeName, required int pingMinutes}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await configure();
    final running = await _service.isRunning();
    if (!running) await _service.startService();
    _service.invoke('start-live-tracking', {'employeeName': employeeName, 'pingMinutes': pingMinutes});
  }

  static Future<void> stop() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _service.invoke('stop-live-tracking');
  }

  @pragma('vm:entry-point')
  static void _onStart(ServiceInstance service) {
    DartPluginRegistrant.ensureInitialized();
    Timer? pingTimer;
    Timer? reminderTimer;
    Future<void> ping() async {
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
        await HrmsTrackingApi.ping(latitude: position.latitude, longitude: position.longitude, accuracy: position.accuracy, isMocked: position.isMocked);
      } catch (_) {
        // The next foreground-service interval retries automatically.
      }
    }
    Future<void> checkClockOutReminder() async {
      try {
        final reminder = await AttendanceApi.clockOutReminderStatus();
        if (reminder['reminderDue'] == true && service is AndroidServiceInstance) {
          await service.setForegroundNotificationInfo(
            title: 'Clock-out reminder',
            content: 'Your shift has ended. Open GoDigital Attendance to respond.',
          );
        }
      } catch (_) {
        // Auth, network and plugin failures are retried on the next interval.
      }
    }
    service.on('start-live-tracking').listen((event) async {
      final minutes = (event?['pingMinutes'] as num?)?.toInt().clamp(1, 1440) ?? 15;
      final name = '${event?['employeeName'] ?? 'Employee'}'.trim();
      if (service is AndroidServiceInstance) {
        await service.setAsForegroundService();
        await service.setForegroundNotificationInfo(
          title: '$name — Live tracking active',
          content: 'Location updates are being saved',
        );
      }
      pingTimer?.cancel();
      pingTimer = Timer.periodic(Duration(minutes: minutes), (_) => ping());
      reminderTimer?.cancel();
      reminderTimer = Timer.periodic(const Duration(minutes: 1), (_) => checkClockOutReminder());
      checkClockOutReminder();
    });
    service.on('stop-live-tracking').listen((_) {
      pingTimer?.cancel();
      reminderTimer?.cancel();
      service.stopSelf();
    });
  }
}
