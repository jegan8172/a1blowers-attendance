import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

import '../../services/hrms_tracking_api.dart';
import '../../services/attendance_api.dart';

/// Android's visible foreground service. It owns scheduled GPS updates while
/// the app is backgrounded, and is stopped explicitly with the session.
class AndroidLiveTrackingService {
  static final FlutterBackgroundService _service = FlutterBackgroundService();
  static bool _configured = false;
  static const _waitingAlertChannel = AndroidNotificationChannel(
    'field_waiting_alerts',
    'Field waiting alerts',
    description: 'Alerts that require a field employee to enter a waiting reason.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );
  static const _waitingAlertNotificationId = 71403;

  static Future<void> configure() async {
    if (kIsWeb || _configured) return;
    _configured = true;
    // Android 13+ blocks all notification sound/vibration until the employee
    // grants this permission. Ask when they deliberately start live tracking.
    final notifications = FlutterLocalNotificationsPlugin();
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await notifications.initialize(initializationSettings);
    final androidNotifications = notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidNotifications?.requestNotificationsPermission();
    await androidNotifications?.createNotificationChannel(_waitingAlertChannel);
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
  static Future<void> _onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    final notifications = FlutterLocalNotificationsPlugin();
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await notifications.initialize(initializationSettings);
    final androidNotifications = notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidNotifications?.createNotificationChannel(_waitingAlertChannel);

    Timer? pingTimer;
    Timer? reminderTimer;
    Timer? waitingAlertTimer;
    int? notifiedWaitingReasonId;
    DateTime? lastWaitingAlertNotificationAt;
    var waitingAlertRepeatSeconds = 5;
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
    Future<void> checkWaitingAlert() async {
      try {
        final alert = await HrmsTrackingApi.waitingAlert();
        final reasonId = int.tryParse('${alert?['id'] ?? ''}');
        if (reasonId == null) {
          notifiedWaitingReasonId = null;
          lastWaitingAlertNotificationAt = null;
          await notifications.cancel(_waitingAlertNotificationId);
          return;
        }

        // Keep alerting while this same reason remains unresolved. The Android
        // channel supplies the device sound and vibration on every update.
        // The server/admin setting controls the repeat frequency.
        final now = DateTime.now();
        if (notifiedWaitingReasonId == reasonId &&
            lastWaitingAlertNotificationAt != null &&
            now.difference(lastWaitingAlertNotificationAt!).inSeconds <
                waitingAlertRepeatSeconds) {
          return;
        }

        final waitingMinutes = alert?['waiting_minutes'] ?? 0;
        await notifications.show(
          _waitingAlertNotificationId,
          'Waiting reason required',
          'You have been at this location for $waitingMinutes minutes. Tap to enter a reason.',
          NotificationDetails(
            android: AndroidNotificationDetails(
              _waitingAlertChannel.id,
              _waitingAlertChannel.name,
              channelDescription: _waitingAlertChannel.description,
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              onlyAlertOnce: false,
              vibrationPattern: Int64List.fromList([0, 180, 100, 180]),
              category: AndroidNotificationCategory.reminder,
            ),
          ),
          payload: 'field-waiting-reason:$reasonId',
        );
        notifiedWaitingReasonId = reasonId;
        lastWaitingAlertNotificationAt = now;
      } catch (_) {
        // A temporary network failure is retried by the next service tick.
      }
    }
    Future<void> startWaitingAlertMonitor() async {
      try {
        final settings = await HrmsTrackingApi.trackingSettings();
        final value = settings['popup_alert_repeat_seconds'] ??
            settings['popupAlertRepeatSeconds'];
        final parsed = value is num ? value.toInt() : int.tryParse('$value');
        // Android may throttle extremely fast notification updates, but this
        // preserves the administrator's chosen repeat interval where allowed.
        waitingAlertRepeatSeconds = (parsed ?? 5).clamp(2, 60).toInt();
      } catch (_) {
        waitingAlertRepeatSeconds = 5;
      }
      waitingAlertTimer?.cancel();
      waitingAlertTimer = Timer.periodic(
        Duration(seconds: waitingAlertRepeatSeconds),
        (_) => checkWaitingAlert(),
      );
      await checkWaitingAlert();
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
      await startWaitingAlertMonitor();
    });
    service.on('stop-live-tracking').listen((_) {
      pingTimer?.cancel();
      reminderTimer?.cancel();
      waitingAlertTimer?.cancel();
      notifications.cancel(_waitingAlertNotificationId);
      service.stopSelf();
    });
  }
}
