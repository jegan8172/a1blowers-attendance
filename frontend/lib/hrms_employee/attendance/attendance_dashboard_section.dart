import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/api_config.dart';
import '../../services/attendance_location.dart';
import '../../services/auth_service.dart';
import '../../services/auth_storage.dart';
import '../../services/hrms_tracking_api.dart';
import '../shared/employee_ui.dart';
import '../shared/live_tracking_coordinator.dart';

/// Attendance on the employee home screen. Other modules retain their own state.
class AttendanceDashboardSection extends StatefulWidget {
  const AttendanceDashboardSection({super.key, this.client});
  final http.Client? client;

  @override
  State<AttendanceDashboardSection> createState() =>
      _AttendanceDashboardSectionState();
}

class _AttendanceDashboardSectionState extends State<AttendanceDashboardSection>
    with WidgetsBindingObserver {
  late final http.Client _client;
  final _elapsed = Stopwatch();
  Timer? _timer;
  String? _token;
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  bool _punching = false;
  bool _breakCommentDialogOpen = false;
  bool _trackingBusy = false;
  bool _fieldTrackingEnabled = false;
  String _workMode = 'Office';
  String _workLocation = 'Main Office';
  bool _trackingActive = false;
  int _request = 0;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? http.Client();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      if (_data?['status'] == 'checked_in') setState(() {});
      if (++_ticks % 60 == 0 && !_loading && !_punching) {
        final token = _token;
        if (_data?['status'] == 'checked_in' && token != null) {
          try {
            await _call('heartbeat', token, post: true);
          } catch (_) {
            // The live display still runs; the next dashboard refresh retries.
          }
        }
        if (mounted) _load();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthService>();
    // Wait for the persisted session to finish loading. Without this guard,
    // the first attendance render could mistake a still-loading session for a
    // logged-out employee.
    if (!auth.isInitialized) return;

    final token = auth.token;
    if (_token != token || (_loading && _request == 0)) {
      _token = token;
      _data = null;
      _punching = false;
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_punching) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _client.close();
    super.dispose();
  }

  Future<Map<String, dynamic>> _call(
    String endpoint,
    String token, {
    bool post = false,
    Map<String, dynamic>? payload,
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/attendance/$endpoint');
    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      if (post) 'Content-Type': 'application/json',
    };
    final response =
        await (post
                ? _client.post(
                    url,
                    headers: headers,
                    body: jsonEncode(payload ?? {}),
                  )
                : _client.get(url, headers: headers))
            .timeout(const Duration(seconds: 15));
    if (response.statusCode == 401) {
      throw const _AttendanceError(
        'Your session expired. Please sign in again.',
      );
    }
    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const _AttendanceError('Attendance is unavailable. Please retry.');
    }
    if (response.statusCode != 200 || body['success'] != true) {
      throw _AttendanceError(
        body['message']?.toString() ?? 'Attendance is unavailable.',
      );
    }
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  String _message(Object error) {
    if (error is _AttendanceError) return error.message;
    if (error is AttendanceLocationError) return error.message;
    if (error is Exception) {
      return error.toString().replaceFirst('Exception: ', '');
    }
    return 'Could not reach attendance. Check your connection and retry.';
  }

  String _durationLabel(int minutes) =>
      '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';

  Future<void> _load() async {
    var token = _token;
    final request = ++_request;
    if (token == null || token.isEmpty) {
      // The session token is written during login. Read the persisted value
      // once as a fallback before showing a sign-in error.
      token = await AuthStorage.getString('auth_token');
      if (token != null && token.isNotEmpty) {
        _token = token;
      }
    }
    if (token == null || token.isEmpty) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _data = null;
        _error = 'Please sign in to view attendance.';
      });
      await _loadTrackingState();
      return;
    }
    setState(() => _loading = true);
    try {
      final data = await _call('dashboard', token);
      if (!mounted || request != _request || token != _token) return;
      setState(() {
        _data = data;
        _error = null;
        _elapsed
          ..reset()
          ..start();
      });
      // Load the tracking permission/session alongside the dashboard data on
      // every normal employee login. Previously this only ran after a tracking
      // action (or when no token existed), so Field/Hybrid users saw a plain
      // Check In button and could not see Start Live Tracking on first load.
      await _loadTrackingState();
      final activeBreak = data['active_break'];
      if (activeBreak is Map && activeBreak['comment_required'] == true) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _showBreakCommentDialog(),
        );
      }
    } catch (error) {
      if (!mounted || request != _request || token != _token) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted && request == _request && token == _token) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadTrackingState() async {
    try {
      await context.read<LiveTrackingCoordinator>().restore();
      final results = await Future.wait([
        HrmsTrackingApi.trackingPermissions(),
      ]);
      if (!mounted) return;
      final permissions = results[0];
      setState(() {
        _fieldTrackingEnabled =
            permissions['fieldTrackingEnabled'] == true ||
            permissions['field_tracking_enabled'] == true;
        _workMode =
            '${permissions['workMode'] ?? permissions['work_mode'] ?? 'Office'}';
        _workLocation =
            '${permissions['workLocation'] ?? permissions['work_location'] ?? (_workMode == 'Home'
                    ? 'Home location'
                    : _workMode == 'Field'
                    ? 'Field assignment'
                    : 'Main Office')}';
        _trackingActive = context.read<LiveTrackingCoordinator>().active;
      });
    } catch (_) {}
  }

  Map _dialogWorkTime() {
    final overview = _data?['month_overview'];
    if (overview is! Map) return const {};
    final workTime = overview['work_time'];
    return workTime is Map ? workTime : const {};
  }

  String _dialogShiftName() {
    final value = _data?['shift_name'] ?? _data?['shiftName'];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
    return _workMode == 'Field' ? 'Field Shift' : 'General Shift';
  }

  String _dialogLocationName() {
    final value =
        _data?['work_location'] ??
        _data?['workLocation'] ??
        _data?['office_name'] ??
        _data?['officeName'];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
    return _workLocation;
  }

  String _dialogShiftStart() {
    final value = _dialogWorkTime()['shift_start']?.toString().trim() ?? '';
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value);
    if (match == null) return 'Scheduled time';
    final hour = int.tryParse(match.group(1)!) ?? 0;
    final minute = int.tryParse(match.group(2)!) ?? 0;
    return DateFormat('hh:mm a').format(DateTime(2026, 1, 1, hour, minute));
  }

  Future<String?> _trackingStopReason() async {
    final controller = TextEditingController();
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => EmployeeActionDialog(
          title: 'Stop live tracking',
          subtitle: 'Provide a brief reason before ending GPS tracking.',
          icon: Icons.location_off_rounded,
          accent: const Color(0xFFDC3C4D),
          showTopAccent: true,
          topAccent: const Color(0xFFE9262D),
          maxWidth: 480,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          iconExtent: 54,
          titleSize: 24,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  EmployeeQuickReasonChip(
                    label: 'Reached base',
                    onTap: () => setDialogState(
                      () => controller.text = 'Reached office base',
                    ),
                  ),
                  EmployeeQuickReasonChip(
                    label: 'Visit completed',
                    onTap: () => setDialogState(
                      () => controller.text = 'Field visit completed',
                    ),
                  ),
                  EmployeeQuickReasonChip(
                    label: 'Shift ended',
                    onTap: () => setDialogState(
                      () => controller.text = 'Shift ended for the day',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Text(
                    'Reason',
                    style: TextStyle(
                      color: employeeNavy,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${controller.text.length}/1000',
                    style: const TextStyle(
                      color: employeeMuted,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                minLines: 3,
                maxLines: 3,
                maxLength: 1000,
                onChanged: (_) => setDialogState(() {}),
                decoration: InputDecoration(
                  hintText: 'Reason',
                  errorText: error,
                  counterText: '',
                  filled: true,
                  fillColor: const Color(0xFFF9FBFE),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(17),
                    borderSide: const BorderSide(color: employeeLine),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(17),
                    borderSide: const BorderSide(
                      color: Color(0xFFE9262D),
                      width: 1.7,
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: Row(
            children: [
              Expanded(
                flex: 4,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    foregroundColor: employeeNavy,
                    side: const BorderSide(color: employeeLine),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 6,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE9262D),
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  onPressed: () {
                    final value = controller.text.trim();
                    if (value.length < 3) {
                      setDialogState(
                        () => error = 'Enter at least 3 characters.',
                      );
                      return;
                    }
                    Navigator.pop(dialogContext, value);
                  },
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: const Text(
                    'Stop tracking',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // Let the dialog's pop transition finish before disposing the controller.
    // Disposing immediately can make the TextField rebuild during the route
    // animation and trigger "controller used after disposed" assertions.
    Future<void>.delayed(const Duration(milliseconds: 300), controller.dispose);
    return result;
  }

  Future<void> _toggleLiveTracking() async {
    if (_trackingBusy) return;
    setState(() => _trackingBusy = true);
    try {
      final coordinator = context.read<LiveTrackingCoordinator>();
      if (_trackingActive) {
        final reason = await _trackingStopReason();
        if (reason == null) return;
        await coordinator.stop(reason);
      } else {
        if (!await coordinator.start(context)) return;
      }
      await _loadTrackingState();
      if (mounted) {
        _showPremiumToast(
          title: _trackingActive ? 'GPS Verified' : 'GPS Tracking Disabled',
          message: _trackingActive
              ? 'Geo-fence active. Check In is now unlocked.'
              : 'Live location tracking has been turned off.',
          success: _trackingActive,
        );
      }
    } catch (error) {
      if (error.toString().contains(
        'signed out because this account signed in on another device',
      )) {
        await context.read<AuthService>().logout();
      }
      if (mounted) {
        _showPremiumToast(
          title: 'Tracking unavailable',
          message: _message(error),
          success: false,
        );
      }
    } finally {
      if (mounted) setState(() => _trackingBusy = false);
    }
  }

  Future<void> _punch() async {
    final token = _token;
    if (token == null || _loading || _punching || _error != null) return;
    if (_fieldTrackingEnabled && !_trackingActive) {
      _showPremiumToast(
        title: 'Live GPS Tracking Required',
        message: 'Enable live tracking before you Check In.',
        success: false,
      );
      return;
    }
    final clockOut = _data?['status'] == 'checked_in';
    final shiftName = _dialogShiftName();
    final locationName = _dialogLocationName();
    final shiftStart = _dialogShiftStart();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => EmployeeActionDialog(
        title: clockOut ? 'Clock out?' : 'Clock in?',
        subtitle: clockOut
            ? 'Confirm that you want to end your work session.'
            : 'Confirm that you want to start your work session.',
        icon: clockOut ? Icons.logout_rounded : Icons.login_rounded,
        dark: !clockOut,
        showTopAccent: !clockOut,
        topAccent: employeeBlue,
        maxWidth: 480,
        iconExtent: 56,
        titleSize: 26,
        padding: const EdgeInsets.fromLTRB(26, 26, 26, 26),
        body: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: clockOut
                  ? const Color(0xFFF6F8FC)
                  : const Color(0xFF1B2941),
              border: Border.all(
                color: clockOut ? employeeLine : const Color(0xFF295080),
              ),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.verified_outlined,
                  size: 18,
                  color: clockOut ? employeeBlue : const Color(0xFF9BC5FF),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '$shiftName • $locationName',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: clockOut ? employeeMuted : const Color(0xFFE5F0FF),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  shiftStart,
                  style: TextStyle(
                    color: clockOut ? employeeNavy : Colors.white,
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: clockOut ? employeeNavy : Colors.white,
                  minimumSize: const Size.fromHeight(56),
                  side: BorderSide(
                    color: clockOut ? employeeLine : const Color(0xFF53739D),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: clockOut ? employeeNavy : employeeBlue,
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(true),
                icon: Icon(
                  clockOut
                      ? Icons.task_alt_rounded
                      : Icons.check_circle_rounded,
                  size: 18,
                ),
                label: Text(
                  clockOut ? 'Check Out' : 'Check In',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    String? clockOutReason;
    if (clockOut) {
      clockOutReason = await _clockOutReason();
      if (clockOutReason == null || !mounted) return;
    }
    setState(() => _punching = true);
    String message;
    try {
      final payload = clockOut
          ? <String, dynamic>{
              'reason': clockOutReason,
              ...await AttendanceLocation.optionalClockLocation(),
            }
          : await AttendanceLocation.checkInPayload(
              client: _client,
              token: token,
            );
      if (!mounted || token != _token) return;
      await _call(
        clockOut ? 'clock-out' : 'clock-in',
        token,
        post: true,
        payload: payload,
      );
      // Clock out may stop the field session server-side with the same reason.
      // Refresh the app-level owner so its Android service/timer also stops.
      if (clockOut) {
        await context.read<LiveTrackingCoordinator>().refreshFromServer();
      }
      message = clockOut
          ? 'You have been clocked out.'
          : 'You are now checked in.';
    } catch (error) {
      message = '${_message(error)} Refresh attendance before trying again.';
    }
    // Also reconcile after a timeout: the server may have saved the punch.
    if (!mounted || token != _token) return;
    await _load();
    if (!mounted || token != _token) return;
    setState(() => _punching = false);
    _showPremiumToast(
      title: clockOut ? 'Checked Out' : 'Checked In',
      message: message,
      success: !message.contains('Refresh attendance'),
    );
  }

  void _showPremiumToast({
    required String title,
    required String message,
    required bool success,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _PremiumToast(
        title: title,
        message: message,
        success: success,
        onDismissed: entry.remove,
      ),
    );
    overlay.insert(entry);
  }

  Future<String?> _clockOutReason() async {
    final controller = TextEditingController();
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Text('Clock Out reason'),
          content: TextField(
            controller: controller,
            minLines: 3,
            maxLines: 5,
            maxLength: 1000,
            decoration: InputDecoration(
              labelText: 'Reason',
              errorText: error,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.length < 3) {
                  setDialogState(() => error = 'Enter at least 3 characters.');
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: const Text('Clock Out'),
            ),
          ],
        ),
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 300), controller.dispose);
    return result;
  }

  Future<void> _requestAnotherClockIn({
    required String date,
    required String clockIn,
    required String clockOut,
  }) async {
    final token = _token;
    if (token == null || _loading || _punching || _error != null) return;
    final controller = TextEditingController();
    var submitting = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Clock In request'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Send Admin a request to reopen today\'s attendance. After approval, Clock In will be available again.',
                ),
                const SizedBox(height: 14),
                Text('Date: $date'),
                Text('Original Clock In: $clockIn'),
                Text('Original Clock Out: $clockOut'),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  enabled: !submitting,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 350,
                  decoration: const InputDecoration(
                    labelText: 'Reason for requesting another Clock In',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      final reason = controller.text.trim();
                      if (reason.length < 3) {
                        setDialogState(
                          () => error = 'Enter at least 3 characters.',
                        );
                        return;
                      }
                      setDialogState(() {
                        submitting = true;
                        error = null;
                      });
                      try {
                        await _call(
                          'reclock-in-request',
                          token,
                          post: true,
                          payload: {'reason': reason},
                        );
                        if (!mounted) return;
                        Navigator.of(dialogContext).pop();
                        await _load();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Clock In request sent to Admin.'),
                          ),
                        );
                      } catch (e) {
                        setDialogState(() {
                          submitting = false;
                          error = _message(e);
                        });
                      }
                    },
              child: Text(submitting ? 'Sending…' : 'Send request'),
            ),
          ],
        ),
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 300), controller.dispose);
  }

  Future<void> _toggleBreak() async {
    final token = _token;
    if (token == null || _loading || _punching || _error != null) return;
    final activeBreak = _data?['active_break'] != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(activeBreak ? 'Resume work?' : 'Start break?'),
        content: Text(
          activeBreak
              ? 'Confirm that you want to end your break and resume your work session.'
              : 'Confirm that you want to start your lunch break.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(activeBreak ? 'Resume' : 'Start Break'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _punching = true);
    String message;
    try {
      await _call(activeBreak ? 'break-out' : 'break-in', token, post: true);
      message = activeBreak
          ? 'Break ended. You are back at work.'
          : 'Break started. You remain checked in.';
    } catch (error) {
      message = _message(error);
    }
    if (!mounted || token != _token) return;
    await _load();
    if (!mounted || token != _token) return;
    setState(() => _punching = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showBreakCommentDialog() async {
    if (!mounted || _breakCommentDialogOpen) return;
    final token = _token;
    if (token == null) return;
    _breakCommentDialogOpen = true;
    final controller = TextEditingController();
    var submitting = false;
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Fixed lunch time ended'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the reason for continuing after your fixed lunch end time. This will be sent to Admin.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                enabled: !submitting,
                maxLength: 1000,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  border: OutlineInputBorder(),
                ),
              ),
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.red)),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      final comment = controller.text.trim();
                      if (comment.length < 3) {
                        setDialogState(
                          () => error = 'Enter at least 3 characters.',
                        );
                        return;
                      }
                      setDialogState(() {
                        submitting = true;
                        error = null;
                      });
                      try {
                        await _call(
                          'break-exceeded-comment',
                          token,
                          post: true,
                          payload: {'comment': comment},
                        );
                        if (!mounted) return;
                        Navigator.of(dialogContext).pop();
                        await _load();
                      } catch (e) {
                        setDialogState(() {
                          submitting = false;
                          error = _message(e);
                        });
                      }
                    },
              child: Text(submitting ? 'Sending…' : 'Send to Admin'),
            ),
          ],
        ),
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 300), controller.dispose);
    _breakCommentDialogOpen = false;
  }

  String _formatPunchTime(dynamic rawTimestamp) {
    if (rawTimestamp == null || rawTimestamp.toString().trim().isEmpty) {
      return '--:--';
    }
    try {
      final str = rawTimestamp.toString();
      DateTime dt;
      if (str.contains('T') || str.contains('-')) {
        dt = DateTime.parse(str).toLocal();
      } else {
        return str; // Return as-is if already formatted like "09:30 AM"
      }
      return DateFormat('hh:mm a').format(dt);
    } catch (_) {
      return rawTimestamp.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    final data = _data;
    if (data == null) {
      return EmployeeCard(
        child: Column(
          children: [
            if (_loading)
              const CircularProgressIndicator()
            else ...[
              Text(_error ?? 'Attendance is unavailable.'),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ],
        ),
      );
    }
    final employee = data['employee'] as Map;
    final session = data['session'] as Map?;
    final overview = data['month_overview'] as Map;
    final workTime = overview['work_time'] as Map? ?? const {};
    final actualMinutes = (workTime['actual_minutes'] as num?)?.toInt() ?? 0;
    final targetMinutes = (workTime['target_minutes'] as num?)?.toInt() ?? 0;
    final monthlyProgress = targetMinutes == 0
        ? 0.0
        : (actualMinutes / targetMinutes).clamp(0.0, 1.0);
    final workingDays = (workTime['working_days'] as num?)?.toInt() ?? 0;
    final overtimeMinutes =
        (workTime['overtime_minutes'] as num?)?.toInt() ?? 0;
    final actions = data['actions'] as Map;
    final checkedIn = data['status'] == 'checked_in';
    final onBreak = data['active_break'] != null;
    final breakCompleted = data['break_completed'] == true;
    final activeBreak = data['active_break'] as Map?;
    var breakTimeLeftLabel = '';
    var breakStartedLabel = '';
    if (onBreak && activeBreak != null) {
      try {
        final started = DateTime.parse(
          activeBreak['started_at'].toString().replaceFirst(' ', 'T'),
        ).toLocal();
        breakStartedLabel =
            'Break started: ${DateFormat('hh:mm a').format(started)}';
        final lunchEnd = activeBreak['lunch_end']?.toString() ?? '';
        final normalizedLunchEnd = lunchEnd.length == 5
            ? '$lunchEnd:00'
            : lunchEnd;
        final endsAt = DateTime.parse(
          '${data['date']} $normalizedLunchEnd'.replaceFirst(' ', 'T'),
        ).toLocal();
        final remainingSeconds = endsAt.difference(DateTime.now()).inSeconds;
        final safeSeconds = remainingSeconds < 0 ? 0 : remainingSeconds;
        final minutes = safeSeconds ~/ 60;
        final seconds = safeSeconds % 60;
        breakTimeLeftLabel =
            'Lunch ends at ${DateFormat('hh:mm a').format(endsAt)} • ${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m ${seconds.toString().padLeft(2, '0')}s left';
      } catch (_) {
        breakTimeLeftLabel = 'Break is active';
      }
    }
    final checkedOut = data['status'] == 'checked_out';
    final reclockRequest = data['reclock_in_request'] as Map?;
    final seconds = (session?['worked_seconds'] as num?)?.toInt() ?? 0;
    final worked = seconds + (checkedIn ? _elapsed.elapsed.inSeconds : 0);
    // The workday ring represents today's current shift, not the month's
    // accumulated target. The mobile card explicitly states an 8-hour shift.
    final workdayProgress = (worked / const Duration(hours: 8).inSeconds).clamp(
      0.0,
      1.0,
    );
    final today = DateTime.parse(data['date'] as String);
    final overnight = session != null && session['work_date'] != data['date'];

    final punchInDisplay = _formatPunchTime(
      session?['punch_in'] ?? session?['clock_in'] ?? session?['check_in'],
    );
    final punchOutDisplay = _formatPunchTime(
      session?['punch_out'] ?? session?['clock_out'] ?? session?['check_out'],
    );

    if (mobile) {
      return _premiumMobileDashboard(
        employee: employee,
        today: today,
        checkedIn: checkedIn,
        checkedOut: checkedOut,
        punchInDisplay: punchInDisplay,
        punchOutDisplay: punchOutDisplay,
        worked: worked,
        actualMinutes: actualMinutes,
        targetMinutes: targetMinutes,
        workingDays: workingDays,
        progress: workdayProgress,
        overview: overview,
        actions: actions,
      );
    }

    final workday = EmployeeCard(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            overnight ? 'Current Work Session' : "Today's Workday",
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: 130,
            height: 130,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Decorative ring indicator
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: employeeBlue, width: 8),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${worked ~/ 3600}h ${(worked % 3600) ~/ 60}m',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Text(
                      'Worked',
                      style: TextStyle(color: employeeMuted, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Divider(color: employeeLine),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  const Text(
                    'Check In',
                    style: TextStyle(color: employeeMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    punchInDisplay,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: employeeNavy,
                    ),
                  ),
                ],
              ),
              Container(height: 26, width: 1, color: employeeLine),
              Column(
                children: [
                  const Text(
                    'Check Out',
                    style: TextStyle(color: employeeMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    punchOutDisplay,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: employeeNavy,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    final month = EmployeeCard(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${DateFormat('MMMM').format(DateTime.parse('${overview['month']}-01'))} Overview',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 13),
          const Text(
            'Monthly Work Time',
            style: TextStyle(color: employeeMuted, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            _durationLabel(actualMinutes),
            style: const TextStyle(
              color: employeeNavy,
              fontSize: 27,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutCubic,
            tween: Tween(begin: 0, end: monthlyProgress),
            builder: (context, value, child) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 7,
                backgroundColor: employeeLine,
                valueColor: AlwaysStoppedAnimation<Color>(
                  overtimeMinutes > 0 ? const Color(0xFF11A55B) : employeeBlue,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            targetMinutes > 0
                ? 'Target ${_durationLabel(targetMinutes)}${overtimeMinutes > 0 ? '  +${_durationLabel(overtimeMinutes)} extra' : ''}'
                : 'Attendance target is not configured',
            style: const TextStyle(color: employeeMuted, fontSize: 12),
          ),
          const SizedBox(height: 13),
          if (mobile)
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: .83,
              children: [
                _monthMetric(
                  'Work days',
                  workingDays,
                  employeeBlue,
                  const Color(0xFFF1F5F9),
                ),
                _monthMetric(
                  'Present',
                  overview['present_days'],
                  const Color(0xFF047857),
                  const Color(0xFFEAF8F1),
                ),
                _monthMetric(
                  'Absent',
                  overview['absent_days'],
                  const Color(0xFFDC2626),
                  const Color(0xFFFFEFF1),
                ),
                _monthMetric(
                  'Late',
                  overview['late_days'],
                  const Color(0xFFB45309),
                  const Color(0xFFFFF6E8),
                ),
              ],
            )
          else ...[
            _count('Working Days', workingDays, employeeBlue),
            const Divider(color: employeeLine),
            _count(
              'Present',
              overview['present_days'],
              const Color(0xFF11A55B),
            ),
            const Divider(color: employeeLine),
            _count('Absent', overview['absent_days'], const Color(0xFFE34646)),
            const Divider(color: employeeLine),
            _count('Late', overview['late_days'], const Color(0xFFFF8B17)),
          ],
          if (overview['absent_days'] == null ||
              overview['late_days'] == null) ...[
            const SizedBox(height: 10),
            const Text(
              'Late and absent totals will appear once working hours and days are set.',
              style: TextStyle(color: employeeMuted, fontSize: 12),
            ),
          ],
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Hello, '),
              TextSpan(
                text: employee['name']?.toString() ?? '',
                style: const TextStyle(color: employeeBlue),
              ),
            ],
          ),
          style: const TextStyle(
            color: employeeNavy,
            fontSize: 27,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${employee['staff_id']}  •  ${DateFormat('EEEE, d MMM yyyy').format(today)}',
          style: const TextStyle(color: employeeMuted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        if (_error != null) ...[
          Text('Attendance may be out of date. $_error'),
          TextButton(
            onPressed: _loading || _punching ? null : _load,
            child: const Text('Retry'),
          ),
        ],
        if (_loading) const LinearProgressIndicator(),
        if (_fieldTrackingEnabled) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _trackingActive
                  ? const Color(0xFFE8F8F1)
                  : const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _trackingActive
                    ? const Color(0xFF9BDDBA)
                    : const Color(0xFFB8D1FF),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _trackingActive
                      ? Icons.gps_fixed_rounded
                      : Icons.location_on_outlined,
                  color: _trackingActive
                      ? const Color(0xFF088A4B)
                      : employeeBlue,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _trackingActive
                        ? 'Live tracking is active. Check In is available.'
                        : (_workMode == 'Hybrid'
                              ? 'Inside an office, Check In is available normally. Start tracking when working outside.'
                              : 'Start live tracking to unlock Check In.'),
                    style: const TextStyle(
                      color: employeeNavy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: _trackingBusy ? null : _toggleLiveTracking,
                  child: Text(
                    _trackingBusy
                        ? 'Saving…'
                        : _trackingActive
                        ? 'Stop Live Tracking'
                        : 'Start Live Tracking',
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: mobile
                  ? const [Color(0xFF0F172A), Color(0xFF1E293B)]
                  : const [Color(0xFF0B72F5), Color(0xFF073B9D)],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      checkedIn
                          ? 'Checked In'
                          : checkedOut
                          ? 'Checked Out'
                          : 'Not Checked In',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    if (checkedIn && punchInDisplay != '--:--') ...[
                      const SizedBox(height: 3),
                      Text(
                        'Since $punchInDisplay',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (onBreak) ...[
                        const SizedBox(height: 3),
                        Text(
                          breakTimeLeftLabel,
                          style: const TextStyle(
                            color: Color(0xFFFFE08A),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          breakStartedLabel,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.82),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (checkedIn)
                OutlinedButton.icon(
                  onPressed:
                      _loading || _punching || _error != null || breakCompleted
                      ? null
                      : _toggleBreak,
                  icon: Icon(
                    onBreak
                        ? Icons.play_arrow
                        : (breakCompleted ? Icons.check : Icons.pause),
                    size: 18,
                  ),
                  label: Text(
                    onBreak
                        ? 'Resume'
                        : (breakCompleted ? 'Break Over' : 'Break'),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white),
                  ),
                ),
              if (checkedIn) const SizedBox(width: 10),
              OutlinedButton(
                onPressed:
                    _loading ||
                        _punching ||
                        _error != null ||
                        (!_trackingActive &&
                            _workMode == 'Field' &&
                            _fieldTrackingEnabled &&
                            !checkedIn) ||
                        !(actions['can_clock_in'] == true ||
                            actions['can_clock_out'] == true)
                    ? null
                    : _punch,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white),
                ),
                child: Text(
                  _punching
                      ? 'Saving…'
                      : checkedIn
                      ? 'Check Out'
                      : checkedOut && actions['can_clock_in'] == true
                      ? 'Check In'
                      : checkedOut
                      ? 'Completed'
                      : 'Check In',
                ),
              ),
              if (checkedOut) const SizedBox(width: 10),
              if (checkedOut)
                OutlinedButton(
                  onPressed:
                      _loading ||
                          _punching ||
                          _error != null ||
                          actions['can_reclock_in_request'] != true
                      ? null
                      : () => _requestAnotherClockIn(
                          date: DateFormat('d MMM yyyy').format(today),
                          clockIn: punchInDisplay,
                          clockOut: punchOutDisplay,
                        ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white),
                  ),
                  child: Text(
                    reclockRequest?['status'] == 'Approved' &&
                            reclockRequest?['reclocked_at'] == null
                        ? 'Request Approved'
                        : reclockRequest?['status'] == 'Pending'
                        ? 'Request Pending'
                        : 'Clock In Request',
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth < 520
              ? Column(children: [workday, const SizedBox(height: 14), month])
              : IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: workday),
                      const SizedBox(width: 18),
                      Expanded(child: month),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _premiumMobileDashboard({
    required Map employee,
    required DateTime today,
    required bool checkedIn,
    required bool checkedOut,
    required String punchInDisplay,
    required String punchOutDisplay,
    required int worked,
    required int actualMinutes,
    required int targetMinutes,
    required int workingDays,
    required double progress,
    required Map overview,
    required Map actions,
  }) {
    final canPunch =
        !_loading &&
        !_punching &&
        _error == null &&
        (actions['can_clock_in'] == true || actions['can_clock_out'] == true);
    final monthName = DateFormat('MMMM').format(today);
    final workLabel =
        '${worked ~/ 3600}h ${((worked % 3600) ~/ 60).toString().padLeft(2, '0')}m';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'Hello, '),
                        TextSpan(
                          text: '${employee['name'] ?? ''}',
                          style: const TextStyle(color: employeeBlue),
                        ),
                      ],
                    ),
                    style: GoogleFonts.inter(
                      color: employeeNavy,
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.45,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${employee['staff_id'] ?? ''}',
                          style: const TextStyle(
                            color: Color(0xFF1E40AF),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          DateFormat('EEE, d MMM yyyy').format(today),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: employeeMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 9),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: checkedIn
                    ? const Color(0xFFEAF8F1)
                    : const Color(0xFFEFF6FF),
                border: Border.all(
                  color: checkedIn
                      ? const Color(0xFFBBE8CE)
                      : const Color(0xFFBFDBFE),
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: checkedIn ? const Color(0xFF047857) : employeeBlue,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    checkedIn
                        ? 'On duty'
                        : checkedOut
                        ? 'Checked out'
                        : 'Ready to Check In',
                    style: TextStyle(
                      color: checkedIn ? const Color(0xFF047857) : employeeBlue,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_fieldTrackingEnabled) ...[
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEFF6FF), Colors.white, Color(0xFFF5F9FF)],
              ),
              border: Border.all(color: const Color(0xFFBFDBFE)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeInOutCubic,
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _trackingActive
                        ? const Color(0xFF078A68)
                        : employeeBlue,
                    shape: BoxShape.circle,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, animation) => RotationTransition(
                      turns: Tween<double>(
                        begin: .78,
                        end: 1,
                      ).animate(animation),
                      child: ScaleTransition(scale: animation, child: child),
                    ),
                    child: Icon(
                      _trackingActive
                          ? Icons.near_me_rounded
                          : Icons.near_me_rounded,
                      key: ValueKey(_trackingActive),
                      color: Colors.white,
                      size: 21,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Live GPS Tracking',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: employeeNavy,
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                letterSpacing: -.25,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _trackingActive
                                  ? const Color(0xFFD1FAE5)
                                  : const Color(0xFFDBEAFE),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 160),
                              child: Text(
                                _trackingActive ? 'Active' : 'Required',
                                key: ValueKey(_trackingActive),
                                style: TextStyle(
                                  color: _trackingActive
                                      ? const Color(0xFF047857)
                                      : employeeBlue,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _trackingActive
                            ? 'Geo-fencing is active. Check In is unlocked.'
                            : 'Enable geo-fencing to unlock Check In',
                        style: GoogleFonts.inter(
                          color: employeeMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _PremiumPressButton(
                  label: _trackingBusy
                      ? 'Saving'
                      : (_trackingActive ? 'Disable' : 'Enable'),
                  icon: Icons.arrow_forward_rounded,
                  dark: true,
                  backgroundColor: _trackingActive
                      ? const Color(0xFF0F172A)
                      : employeeBlue,
                  onTap: _trackingBusy ? null : _toggleLiveTracking,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
            ),
            borderRadius: BorderRadius.circular(17),
            boxShadow: const [
              BoxShadow(
                color: Color(0x240F172A),
                blurRadius: 14,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: checkedIn ? const Color(0xFF34D399) : employeeBlue,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      checkedIn
                          ? 'Checked In'
                          : checkedOut
                          ? 'Shift completed'
                          : 'Not Checked In',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      checkedIn
                          ? 'Shift is active since $punchInDisplay'
                          : 'Shift starts at ${dataShiftStart(overview)}',
                      style: GoogleFonts.inter(
                        color: Color(0xFFBFDBFE),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _PremiumPressButton(
                label: _punching
                    ? 'Saving'
                    : checkedIn
                    ? 'Check Out'
                    : 'Check In',
                icon: checkedIn
                    ? Icons.logout_rounded
                    : Icons.touch_app_rounded,
                borderColor: const Color(0xFFE0F2FE),
                onTap: canPunch ? _punch : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        EmployeeCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.circle, size: 8, color: employeeBlue),
                      const SizedBox(width: 8),
                      Text(
                        "Today's Workday",
                        style: GoogleFonts.inter(
                          color: employeeNavy,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.25,
                        ),
                      ),
                    ],
                  ),
                  _pill('Standard 8h Shift'),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 172,
                height: 172,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 172,
                      height: 172,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 12,
                        backgroundColor: const Color(0xFFE2E8F0),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          employeeBlue,
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          workLabel,
                          style: GoogleFonts.inter(
                            color: employeeNavy,
                            fontSize: 29,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.6,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Logged Active Time',
                          style: GoogleFonts.inter(
                            color: employeeMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const Divider(color: employeeLine),
              const SizedBox(height: 13),
              Row(
                children: [
                  Expanded(
                    child: _premiumPunchPanel(
                      'Check In',
                      punchInDisplay,
                      Icons.login_rounded,
                      employeeBlue,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _premiumPunchPanel(
                      'Check Out',
                      punchOutDisplay,
                      Icons.logout_rounded,
                      employeeMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        EmployeeCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$monthName Overview',
                        style: GoogleFonts.inter(
                          color: employeeNavy,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.35,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Monthly work time performance',
                        style: GoogleFonts.inter(
                          color: employeeMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  _monthPill(),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: const Color(0xFFDBEAFE)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _durationLabel(actualMinutes),
                          style: GoogleFonts.inter(
                            color: employeeNavy,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.7,
                          ),
                        ),
                        Text(
                          targetMinutes > 0
                              ? 'Target ${_durationLabel(targetMinutes)}'
                              : 'No target set',
                          style: GoogleFonts.inter(
                            color: employeeNavy,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 9,
                        backgroundColor: const Color(0xFFBFDBFE),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          employeeBlue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 8,
                mainAxisExtent: 60,
                children: [
                  _premiumMetric(
                    'Work Days',
                    workingDays,
                    employeeBlue,
                    const Color(0xFFF1F5F9),
                  ),
                  _premiumMetric(
                    'Present',
                    overview['present_days'],
                    const Color(0xFF047857),
                    const Color(0xFFEAF8F1),
                  ),
                  _premiumMetric(
                    'Absent',
                    overview['absent_days'],
                    const Color(0xFFDC2626),
                    const Color(0xFFFFEFF1),
                  ),
                  _premiumMetric(
                    'Late',
                    overview['late_days'],
                    const Color(0xFFB45309),
                    const Color(0xFFFFF6E8),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String dataShiftStart(Map overview) =>
      overview['shift_start']?.toString() ?? 'your scheduled time';

  Widget _pill(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: employeeLine),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: employeeMuted,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _monthPill() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFEFF6FF),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFBFDBFE)),
    ),
    child: Text(
      'Monthly',
      style: GoogleFonts.inter(
        color: employeeBlue,
        fontSize: 10,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _premiumPunchPanel(
    String label,
    String time,
    IconData icon,
    Color color,
  ) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Row(
      children: [
        Container(
          width: 29,
          height: 29,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: color, size: 17),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: employeeMuted, fontSize: 10),
              ),
              const SizedBox(height: 2),
              Text(
                time,
                style: const TextStyle(
                  color: employeeNavy,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _premiumMetric(
    String label,
    dynamic value,
    Color color,
    Color background,
  ) => Container(
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: .16)),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '${value ?? '—'}',
          style: GoogleFonts.inter(
            color: color,
            fontSize: 19,
            fontWeight: FontWeight.w800,
            letterSpacing: -.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: employeeNavy,
            fontSize: 9,
            height: 1.1,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _count(String label, dynamic value, Color color) => Row(
    children: [
      Expanded(child: Text(label)),
      Text(
        value?.toString() ?? '—',
        style: TextStyle(
          color: color,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );

  Widget _monthMetric(
    String label,
    dynamic value,
    Color color,
    Color background,
  ) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: .16)),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value?.toString() ?? '—',
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 2,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: employeeMuted,
            fontSize: 10,
            height: 1.05,
          ),
        ),
      ],
    ),
  );
}

class _PremiumToast extends StatefulWidget {
  const _PremiumToast({
    required this.title,
    required this.message,
    required this.success,
    required this.onDismissed,
  });

  final String title;
  final String message;
  final bool success;
  final VoidCallback onDismissed;

  @override
  State<_PremiumToast> createState() => _PremiumToastState();
}

class _PremiumToastState extends State<_PremiumToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
      reverseDuration: const Duration(milliseconds: 240),
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _slide = Tween<Offset>(
      begin: const Offset(1.12, 0),
      end: Offset.zero,
    ).animate(curve);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
    _closeLater();
  }

  Future<void> _closeLater() async {
    await Future<void>.delayed(const Duration(seconds: 4));
    if (!mounted || _dismissed) return;
    await _controller.reverse();
    if (mounted && !_dismissed) {
      _dismissed = true;
      widget.onDismissed();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final foreground = widget.success
        ? const Color(0xFFECFDF5)
        : const Color(0xFFFFF7ED);
    final iconColor = widget.success
        ? const Color(0xFF5EEAD4)
        : const Color(0xFFFBBF24);
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _fade,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 390,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101A31),
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(color: const Color(0xFF263956)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x4207162F),
                        blurRadius: 22,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: widget.success
                              ? const Color(0xFF0F766E)
                              : const Color(0xFF9A5B10),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.success
                              ? Icons.gps_fixed_rounded
                              : Icons.info_outline_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: foreground,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: iconColor.withValues(alpha: .92),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Dismiss',
                        onPressed: () async {
                          if (_dismissed) return;
                          _dismissed = true;
                          await _controller.reverse();
                          if (mounted) widget.onDismissed();
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PremiumPressButton extends StatefulWidget {
  const _PremiumPressButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.dark = false,
    this.backgroundColor,
    this.borderColor,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool dark;
  final Color? backgroundColor;
  final Color? borderColor;

  @override
  State<_PremiumPressButton> createState() => _PremiumPressButtonState();
}

class _PremiumPressButtonState extends State<_PremiumPressButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => AnimatedScale(
    duration: const Duration(milliseconds: 110),
    scale: _pressed ? .95 : 1,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: (value) => setState(() => _pressed = value),
        borderRadius: BorderRadius.circular(99),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color:
                widget.backgroundColor ??
                (widget.dark ? const Color(0xFF0F172A) : employeeBlue),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color:
                  widget.borderColor ??
                  (widget.dark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFF60A5FA)),
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: Row(
              key: ValueKey(widget.label),
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(widget.icon, color: Colors.white, size: 15),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _AttendanceError implements Exception {
  const _AttendanceError(this.message);
  final String message;
}
