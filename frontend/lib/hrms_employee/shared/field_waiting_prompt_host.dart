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
import 'employee_ui.dart';

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

/// A compact anchored selector that avoids the platform's full-screen native
/// dropdown while retaining keyboard and tap accessibility.
class _WaitingReasonMenu extends StatelessWidget {
  const _WaitingReasonMenu({
    required this.value,
    required this.options,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final List<String> options;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        minimumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 0)),
        maximumSize: const WidgetStatePropertyAll(Size(double.infinity, 270)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 5),
        ),
        elevation: const WidgetStatePropertyAll(10),
        backgroundColor: const WidgetStatePropertyAll(Colors.white),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.white),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFBBD6FF)),
          ),
        ),
      ),
      menuChildren: options.map((option) {
        final selected = option == value;
        return MenuItemButton(
          onPressed: enabled ? () => onChanged(option) : null,
          style: const ButtonStyle(
            padding: WidgetStatePropertyAll(EdgeInsets.zero),
            minimumSize: WidgetStatePropertyAll(Size.fromHeight(0)),
          ),
          child: Container(
            width: constraints.maxWidth,
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFEAF3FF) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 17,
                  color: selected ? employeeBlue : const Color(0xFF94A3B8),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    option,
                    style: TextStyle(
                      color: selected ? employeeBlue : employeeNavy,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
      builder: (context, controller, child) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: !enabled
              ? null
              : (controller.isOpen ? controller.close : controller.open),
          borderRadius: BorderRadius.circular(15),
          child: Ink(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFCFF),
              border: Border.all(color: employeeBlue, width: 1.7),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: employeeNavy,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: controller.isOpen ? .5 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Color(0xFF31557E),
                    size: 23,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _FieldWaitingPromptHostState extends State<FieldWaitingPromptHost>
    with WidgetsBindingObserver {
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
      _coordinator = context.read<LiveTrackingCoordinator>()
        ..addListener(_onCoordinatorChanged);
    });
    WidgetsBinding.instance.addObserver(this);
    widget.routeRevision.addListener(_onRouteChanged);
    _auth = context.read<AuthService>()..addListener(_onAuthChanged);
    _timer = Timer.periodic(_alertCheckInterval, (_) => _check());
    AndroidLiveTrackingService.pendingWaitingReasonId.addListener(
      _onNotificationTap,
    );
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
    AndroidLiveTrackingService.pendingWaitingReasonId.removeListener(
      _onNotificationTap,
    );
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
        await _showDialog(
          reasonId: id,
          waitingMinutes: alert['waiting_minutes'] ?? 0,
        );
      } finally {
        _dialogOpen = false;
      }
    });
  }

  void _onAuthChanged() {
    final auth = _auth;
    if (auth?.isAuthenticated == true &&
        auth?.userType?.toLowerCase() == 'employee') {
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
      final session = await HrmsTrackingApi.fieldSession();
      final sessionValue =
          session['popup_alert_repeat_seconds'] ??
          session['popupAlertRepeatSeconds'];
      final sessionSeconds = sessionValue is num
          ? sessionValue.toInt()
          : int.tryParse('$sessionValue');
      if (sessionSeconds != null && sessionSeconds > 0) {
        return Duration(seconds: sessionSeconds.clamp(2, 60).toInt());
      }

      // Older sessions can predate the per-template snapshot columns. Keep
      // the global setting only as a compatibility fallback for those rows.
      final settings = await HrmsTrackingApi.trackingSettings();
      final value =
          settings['popup_alert_repeat_seconds'] ??
          settings['popupAlertRepeatSeconds'];
      final seconds = value is num ? value.toInt() : int.tryParse('$value');
      return Duration(seconds: (seconds ?? 5).clamp(2, 60).toInt());
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
                  const Text(
                    'You are still checked in after your scheduled shift end.',
                  ),
                  const SizedBox(height: 12),
                  Text('Shift end: ${reminder['shiftEnd'] ?? '-'}'),
                  Text(
                    'Time after shift: ${reminder['elapsedAfterShiftMinutes'] ?? 0} minutes',
                  ),
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
                    SnackBar(
                      content: Text(
                        error.toString().replaceFirst('Exception: ', ''),
                      ),
                    ),
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
      try {
        await _soundPlayer.play(AssetSource('sounds/$sound'), volume: 0.8);
      } catch (_) {}
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
          builder: (dialogContext, setDialogState) => EmployeeActionDialog(
            title: 'Field waiting reason',
            subtitle:
                'You have been at this location for $waitingMinutes minutes. Please enter the reason for waiting.',
            icon: Icons.hourglass_top_rounded,
            maxWidth: 420,
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
            iconExtent: 50,
            titleSize: 22,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFE7F0FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '${waitingMinutes.toString().padLeft(2, '0')}:00',
                style: const TextStyle(
                  color: employeeBlue,
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            body: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reason type',
                  style: TextStyle(
                    color: employeeBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                _WaitingReasonMenu(
                  value: selectedReason,
                  options: reasons,
                  enabled: !submitting,
                  onChanged: (value) =>
                      setDialogState(() => selectedReason = value),
                ),
                const SizedBox(height: 17),
                Row(
                  children: [
                    const Text(
                      'Reason for waiting',
                      style: TextStyle(
                        color: employeeNavy,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${controller.text.length}/500',
                      style: const TextStyle(
                        color: employeeMuted,
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                TextField(
                  controller: controller,
                  minLines: 3,
                  maxLines: 3,
                  maxLength: 500,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Reason for waiting',
                    filled: true,
                    fillColor: const Color(0xFFFAFCFF),
                    counterText: '',
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(17),
                      borderSide: const BorderSide(color: employeeLine),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(17),
                      borderSide: const BorderSide(
                        color: employeeBlue,
                        width: 1.7,
                      ),
                    ),
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
            actions: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1559DC),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(54),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  elevation: 3,
                  shadowColor: const Color(0x4D1559DC),
                ),
                onPressed: submitting
                    ? null
                    : () async {
                        final details = controller.text.trim();
                        final reason = selectedReason == 'Other'
                            ? details
                            : details.isEmpty
                            ? selectedReason
                            : '$selectedReason: $details';
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
                            throw Exception(
                              'Reason must be 500 characters or less.',
                            );
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
                icon: const Icon(Icons.send_rounded, size: 17),
                label: Text(
                  submitting ? 'Submitting…' : 'Submit',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ),
      );
    } finally {
      _stopPromptFeedback();
      // The dialog route may still be completing its pop animation. Dispose
      // after the next transition frame so TextField listeners are not torn
      // down while Flutter is rebuilding the dialog.
      Future<void>.delayed(
        const Duration(milliseconds: 350),
        controller.dispose,
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
