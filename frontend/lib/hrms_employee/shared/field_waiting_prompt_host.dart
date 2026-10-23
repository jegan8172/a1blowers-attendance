import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';

import '../../services/auth_service.dart';
import '../../services/hrms_tracking_api.dart';
import '../../services/attendance_api.dart';
import 'live_tracking_coordinator.dart';
import 'android_live_tracking_service.dart';

/// Keeps the mandatory field-waiting comment prompt active while an employee
/// moves between pages. A prompt is only shown for a currently active field
/// session; office/home sessions and old alerts are ignored.
class FieldWaitingPromptHost extends StatefulWidget {
  const FieldWaitingPromptHost({
    super.key,
    required this.child,
    required this.navigatorKey,
    required this.routeRevision,
  });
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final ValueListenable<int> routeRevision;

  @override
  State<FieldWaitingPromptHost> createState() => _FieldWaitingPromptHostState();
}

class _FieldWaitingPromptHostState extends State<FieldWaitingPromptHost> with WidgetsBindingObserver {
  // A manual page refresh used to make this prompt appear because it calls
  // _check immediately, while the background check ran only once a minute.
  // Poll the server more frequently so a newly due waiting alert is displayed
  // automatically. This does not obtain GPS or create a location ping.
  static const _alertCheckInterval = Duration(seconds: 10);
  Timer? _timer;
  Timer? _soundTimer;
  Timer? _feedbackSessionTimer;
  final AudioPlayer _soundPlayer = AudioPlayer();
  bool _checking = false;
  bool _dialogOpen = false;
  AuthService? _auth;
  LiveTrackingCoordinator? _coordinator;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LiveTrackingCoordinator>().restore();
      _check();
      _coordinator = context.read<LiveTrackingCoordinator>()..addListener(_onCoordinatorChanged);
    });
    WidgetsBinding.instance.addObserver(this);
    widget.routeRevision.addListener(_onRouteChanged);
    _auth = context.read<AuthService>()..addListener(_onAuthChanged);
    _timer = Timer.periodic(_alertCheckInterval, (_) => _check());
    AndroidLiveTrackingService.pendingWaitingReasonId.addListener(_onNotificationTap);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.routeRevision.removeListener(_onRouteChanged);
    _auth?.removeListener(_onAuthChanged);
    _coordinator?.removeListener(_onCoordinatorChanged);
    _timer?.cancel();
    _stopPromptFeedback();
    _soundPlayer.dispose();
    AndroidLiveTrackingService.pendingWaitingReasonId.removeListener(_onNotificationTap);
    super.dispose();
  }

  void _onNotificationTap() {
    final id = AndroidLiveTrackingService.pendingWaitingReasonId.value;
    if (id == null || !mounted) return;
    AndroidLiveTrackingService.pendingWaitingReasonId.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _dialogOpen) return;
      final alert = await HrmsTrackingApi.waitingAlert();
      if (alert == null || int.tryParse('${alert['id']}') != id) return;
      _dialogOpen = true;
      try {
        await _showDialog(reasonId: id, waitingMinutes: alert['waiting_minutes'] ?? 0);
      } finally {
        _dialogOpen = false;
      }
    });
  }

  void _onAuthChanged() {
    final auth = _auth;
    if (auth?.isAuthenticated == true && auth?.userType?.toLowerCase() == 'employee') {
      context.read<LiveTrackingCoordinator>().restore();
      _onRouteChanged();
    }
  }

  void _onRouteChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _onCoordinatorChanged() {
    final warning = _coordinator?.autoClockoutWarning;
    if (warning == null || _dialogOpen || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_dialogOpen) _showAutoClockoutDialog(warning);
    });
  }

  Future<void> _showAutoClockoutDialog(Map<String, dynamic> warning) async {
    final rootContext = widget.navigatorKey.currentContext;
    if (rootContext == null || _dialogOpen) return;
    _dialogOpen = true;
    SystemSound.play(SystemSoundType.alert);
    try {
      if (await Vibration.hasVibrator() == true) {
        await Vibration.vibrate(pattern: [0, 120, 80, 120]);
      }
    } catch (_) {}
    try {
      await showDialog<void>(
        context: rootContext,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('You appear to be outside your work location.'),
          content: Text(
            'If you are still working, confirm now. Auto clock-out will occur after ${warning['warningSeconds'] ?? 60} seconds if there is no response.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                try {
                  await _coordinator?.respondToAutoClockoutWarning();
                } finally {
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('Still working'),
            ),
          ],
        ),
      );
    } finally {
      _dialogOpen = false;
      _coordinator?.dismissAutoClockoutWarning();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onRouteChanged();
  }

  void _startPromptFeedback(Duration repeatInterval) {
    _stopPromptFeedback();
    Future<void> play() async {
      try {
        await _soundPlayer.play(
          AssetSource('sounds/notification.mp3'),
          volume: 0.8,
        );
      } catch (_) {
        // The mandatory prompt remains usable if a device cannot play audio.
      }
    }

    Future<void> vibrate() async {
      try {
        if (await Vibration.hasVibrator() == true) {
          await Vibration.vibrate(pattern: [0, 120, 80, 120]);
        }
      } catch (_) {
        // Unsupported platforms and blocked browser/device vibration are safe.
      }
    }

    void notify() {
      play();
      vibrate();
    }

    notify();
    _soundTimer = Timer.periodic(repeatInterval, (_) => notify());
    _feedbackSessionTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _stopFeedbackForInactiveSession(),
    );
  }

  Future<void> _stopFeedbackForInactiveSession() async {
    try {
      final session = await HrmsTrackingApi.fieldSession();
      final active =
          session['is_active'] == 1 ||
          session['is_active'] == true ||
          session['isActive'] == true;
      if (!active) {
        _stopPromptFeedback();
      }
    } catch (_) {
      // A temporary network failure must not stop a mandatory local prompt.
    }
  }

  void _stopPromptFeedback() {
    _soundTimer?.cancel();
    _soundTimer = null;
    _feedbackSessionTimer?.cancel();
    _feedbackSessionTimer = null;
    _soundPlayer.stop();
    Vibration.cancel().catchError((_) {});
  }

  Future<Duration> _popupAlertRepeatInterval() async {
    try {
      final settings = await HrmsTrackingApi.trackingSettings();
      final seconds =
          int.tryParse('${settings['popup_alert_repeat_seconds'] ?? 5}') ?? 5;
      return Duration(seconds: seconds.clamp(1, 30).toInt());
    } catch (_) {
      return const Duration(seconds: 5);
    }
  }

  Future<void> _check() async {
    if (_checking || _dialogOpen || !mounted) return;
    final auth = context.read<AuthService>();
    if (!auth.isAuthenticated || auth.userType?.toLowerCase() != 'employee') {
      return;
    }

    _checking = true;
    try {
      await HrmsTrackingApi.flushQueuedWaitingReasons();
      await _checkClockOutReminder();
      if (_dialogOpen || !mounted) return;
      final session = await HrmsTrackingApi.fieldSession();
      final active =
          session['is_active'] == 1 ||
          session['is_active'] == true ||
          session['isActive'] == true;
      if (!active || !mounted) return;

      final alert = await HrmsTrackingApi.waitingAlert();
      if (alert == null || !mounted || _dialogOpen) return;
      final reasonId = int.tryParse('${alert['id']}');
      if (reasonId == null) return;

      _dialogOpen = true;
      try {
        await _showDialog(
          reasonId: reasonId,
          waitingMinutes: alert['waiting_minutes'] ?? 0,
        );
      } finally {
        _dialogOpen = false;
      }
    } catch (_) {
      // A tracking/network failure must not interrupt the employee's page.
    } finally {
      _checking = false;
    }
  }

  Future<void> _checkClockOutReminder() async {
    try {
      final reminder = await AttendanceApi.clockOutReminderStatus();
      if (_dialogOpen || reminder['reminderDue'] != true) return;
      final eventId = int.tryParse('${reminder['reminderEventId']}');
      if (eventId == null) return;
      _dialogOpen = true;
      try {
        await _showClockOutReminder(eventId, reminder);
      } finally {
        _dialogOpen = false;
      }
    } catch (_) {
      // Expired sessions and transient network/GPS failures fall back to the
      // next scheduled check without disrupting the active attendance screen.
    }
  }

  Future<void> _showClockOutReminder(
    int eventId,
    Map<String, dynamic> reminder,
  ) async {
    final rootContext = widget.navigatorKey.currentContext;
    if (rootContext == null) return;
    final sound = '${reminder['sound'] ?? 'notification.mp3'}';
    final repeat = Duration(
      minutes: (int.tryParse('${reminder['repeatMinutes'] ?? 1}') ?? 1)
          .clamp(1, 60)
          .toInt(),
    );
    _startClockOutFeedback(sound, repeat);
    try {
      await showDialog<void>(
        context: rootContext,
        barrierDismissible: true,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Clock-out reminder'),
          content: SingleChildScrollView(
            child: Semantics(
              liveRegion: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${reminder['employeeName'] ?? 'Employee'} is currently checked in.',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text('You are still checked in after your scheduled shift end.'),
                  const SizedBox(height: 12),
                  Text('Shift end: ${reminder['shiftEnd'] ?? '-'}'),
                  Text('Time after shift: ${reminder['elapsedAfterShiftMinutes'] ?? 0} minutes'),
                  Text('Reminder sound: $sound'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await AttendanceApi.respondToClockOutReminder(
                  eventId: eventId,
                  action: 'snooze',
                );
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              },
              child: const Text('Snooze'),
            ),
            TextButton(
              onPressed: () async {
                await AttendanceApi.respondToClockOutReminder(
                  eventId: eventId,
                  action: 'still_working',
                );
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              },
              child: const Text('Still Working'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await AttendanceApi.respondToClockOutReminder(
                    eventId: eventId,
                    action: 'clock_out_now',
                  );
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                } catch (error) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
                  );
                }
              },
              child: const Text('Clock Out Now'),
            ),
          ],
        ),
      );
    } finally {
      _stopPromptFeedback();
    }
  }

  void _startClockOutFeedback(String sound, Duration repeat) {
    _stopPromptFeedback();
    Future<void> play() async {
      try { await _soundPlayer.play(AssetSource('sounds/$sound'), volume: 0.8); } catch (_) {}
    }
    play();
    _soundTimer = Timer.periodic(repeat, (_) => play());
  }

  Future<void> _showDialog({
    required int reasonId,
    required dynamic waitingMinutes,
  }) async {
    final rootContext = widget.navigatorKey.currentContext;
    if (rootContext == null) return;
    final controller = TextEditingController();
    var submitting = false;
    String? errorMessage;
    String selectedReason = 'Other';
    const reasons = <String>[
      'Client/customer meeting',
      'Traffic or travel delay',
      'Vehicle or equipment issue',
      'Work paused / waiting for instructions',
      'Break',
      'Other',
    ];
    final repeatInterval = await _popupAlertRepeatInterval();
    if (!mounted || !rootContext.mounted) {
      controller.dispose();
      return;
    }
    _startPromptFeedback(repeatInterval);
    try {
      await showDialog<void>(
        context: rootContext,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('Field waiting reason'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'You have been at this location for $waitingMinutes minutes. '
                  'Please enter the reason for waiting.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedReason,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Reason type',
                    border: OutlineInputBorder(),
                  ),
                  items: reasons
                      .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                      .toList(),
                  onChanged: submitting ? null : (value) {
                    if (value != null) setDialogState(() => selectedReason = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Reason for waiting',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: submitting
                    ? null
                    : () async {
                        final details = controller.text.trim();
                        final reason = selectedReason == 'Other'
                            ? details
                            : details.isEmpty ? selectedReason : '$selectedReason: $details';
                        if (reason.isEmpty) {
                          setDialogState(
                            () => errorMessage = 'Please enter a reason.',
                          );
                          return;
                        }
                        setDialogState(() {
                          submitting = true;
                          errorMessage = null;
                        });
                        try {
                          if (reason.length > 500) {
                            throw Exception('Reason must be 500 characters or less.');
                          }
                          await HrmsTrackingApi.submitWaitingReason(
                            reasonId: reasonId,
                            reason: reason,
                          );
                          if (dialogContext.mounted) {
                            Navigator.of(
                              dialogContext,
                              rootNavigator: true,
                            ).pop();
                          }
                        } catch (_) {
                          await HrmsTrackingApi.queueWaitingReason(
                            reasonId: reasonId,
                            reason: reason,
                          );
                          if (dialogContext.mounted) {
                            setDialogState(() {
                              submitting = false;
                              errorMessage =
                                  'Saved on this device. It will retry automatically when online.';
                            });
                          }
                        }
                      },
                child: Text(submitting ? 'Submitting…' : 'Submit'),
              ),
            ],
          ),
        ),
      );
    } finally {
      _stopPromptFeedback();
      // The dialog route may still be completing its pop animation. Dispose
      // after the next transition frame so TextField listeners are not torn
      // down while Flutter is rebuilding the dialog.
      Future<void>.delayed(const Duration(milliseconds: 350), controller.dispose);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
