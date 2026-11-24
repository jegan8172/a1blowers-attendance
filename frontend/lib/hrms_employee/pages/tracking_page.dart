import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/hrms_tracking_api.dart';
import '../../services/tracking_comments_section.dart';
import '../shared/employee_ui.dart';
import '../shared/live_tracking_coordinator.dart';
import 'home_location_dialog.dart';

/// A compact blue GPS puck for the employee's live position. It deliberately
/// has no pin tail, so the marker reads as a real-time location rather than a
/// saved destination.
Future<BitmapDescriptor> _employeeGpsPuckIcon() async {
  const size = 84;
  const center = Offset(size / 2, size / 2);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  canvas.drawCircle(center, 31, Paint()..color = const Color(0x243B82F6));
  canvas.drawCircle(center, 22, Paint()..color = const Color(0x554A90FF));
  canvas.drawCircle(center, 12, Paint()..color = Colors.white);
  canvas.drawCircle(center, 9, Paint()..color = const Color(0xFF1769E0));
  canvas.drawCircle(center, 4, Paint()..color = Colors.white);

  final image = await recorder.endRecording().toImage(size, size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(
    Uint8List.fromList(bytes!.buffer.asUint8List()),
  );
}

/// A compact, numbered A1 office beacon. The number makes nearby offices
/// distinguishable at city zoom; tapping a pin reveals the office name.
Future<BitmapDescriptor> _a1OfficeMarkerIcon(int officeNumber) async {
  const width = 62;
  const height = 76;
  const headCenter = Offset(28, 27);
  final logoData = await rootBundle.load('assets/images/godigital_logo.png');
  final logoCodec = await ui.instantiateImageCodec(
    logoData.buffer.asUint8List(),
    targetWidth: 96,
  );
  final logo = (await logoCodec.getNextFrame()).image;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  final shadow = Path()
    ..addOval(const Rect.fromLTWH(6, 5, 44, 44))
    ..moveTo(15, 39)
    ..lineTo(28, 70)
    ..lineTo(41, 39)
    ..close();
  canvas.drawPath(shadow, Paint()..color = const Color(0x33091A36));

  final pin = Path()
    ..addOval(const Rect.fromLTWH(5, 3, 46, 46))
    ..moveTo(15, 38)
    ..lineTo(28, 68)
    ..lineTo(41, 38)
    ..close();
  canvas.drawPath(pin, Paint()..color = const Color(0xFF1463D7));
  canvas.drawCircle(headCenter, 18, Paint()..color = Colors.white);
  canvas.drawCircle(
    headCenter,
    19,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFF9DC5FF),
  );

  // Use the precise A1 Blowers artwork from the navbar rather than a typed
  // approximation. Keep it within the white centre so it remains crisp.
  const logoTarget = Rect.fromLTWH(9, 19, 38, 15.2);
  canvas.drawImageRect(
    logo,
    Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
    logoTarget,
    Paint()..filterQuality = FilterQuality.high,
  );

  const badgeCenter = Offset(48, 12);
  canvas.drawCircle(badgeCenter, 11, Paint()..color = const Color(0xFF0F2347));
  final badge = TextPainter(
    text: TextSpan(
      text: '$officeNumber',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w800,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  badge.paint(canvas, badgeCenter - Offset(badge.width / 2, badge.height / 2));

  final image = await recorder.endRecording().toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  logo.dispose();
  return BitmapDescriptor.bytes(
    Uint8List.fromList(bytes!.buffer.asUint8List()),
  );
}

class EmployeeTrackingPage extends StatelessWidget {
  const EmployeeTrackingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final routeHistory =
        ModalRoute.of(context)?.settings.arguments == 'history';
    return EmployeeScaffold(
      route: '/employee/tracking',
      title: routeHistory ? 'Route History' : 'Live Tracking',
      subtitle: routeHistory
          ? 'Your recent travel routes'
          : 'Live employee location and today’s field activity',
      desktop: _TrackingView(mobile: false, routeHistory: routeHistory),
      mobile: _TrackingView(mobile: true, routeHistory: routeHistory),
    );
  }
}

enum _WorkMode { office, home, field }

class _OfficeMarkerData {
  const _OfficeMarkerData({
    required this.id,
    required this.name,
    required this.position,
  });

  final int? id;
  final String name;
  final LatLng position;
}

class _TrackingView extends StatefulWidget {
  const _TrackingView({required this.mobile, required this.routeHistory});
  final bool mobile;
  final bool routeHistory;

  @override
  State<_TrackingView> createState() => _TrackingViewState();
}

class _TrackingViewState extends State<_TrackingView>
    with WidgetsBindingObserver {
  _WorkMode mode = _WorkMode.office;
  String updated = 'Not tracking yet';
  bool trackingActive = false;
  Position? _lastPosition;
  List<LatLng> _routePoints = const [];
  Map<String, dynamic>? _homeLocation;
  Map<String, dynamic>? _officeSettings;
  List<Map<String, dynamic>> _officeLocations = const [];
  bool _homeLoading = true;
  bool _officeLoading = true;
  bool _homeDialogOpen = false;
  bool _trackingActionInProgress = false;
  bool _fieldTrackingEnabled = false;
  bool _homeLocationEnabled = true;
  String? _homeError;
  Timer? _timelineRefreshTimer;
  bool _timelineRequestInFlight = false;
  bool _fallbackPingInFlight = false;
  int _gpsUpdateIntervalMinutes = 15;
  DateTime? _lastSavedPingAt;
  final ValueNotifier<GoogleMapController?> _mapController = ValueNotifier(
    null,
  );

  String distance = '—';
  String duration = '—';
  String avgSpeed = '—';

  List<dynamic> activities = [
    {
      'activity_time': '--:--',
      'activity_text': 'No live tracking activity yet',
    },
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    employeeRouteSignal.revision.addListener(_reloadSavedSession);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFieldSession();
      _loadTrackingPermissions();
      _loadHomeLocation();
      _loadOfficeSettings();
      _loadOfficeLocations();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    employeeRouteSignal.revision.removeListener(_reloadSavedSession);
    _stopTimelineRefresh();
    _mapController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android's foreground service continues to save pings while the app is
    // backgrounded. Reload immediately when this page becomes visible again.
    if (state == AppLifecycleState.resumed && trackingActive) {
      _loadTripSummary();
    }
  }

  void _startTimelineRefresh() {
    if (_timelineRefreshTimer != null) return;
    // The Android foreground service sends GPS at the admin-configured
    // interval. Polling keeps the visible activity current. If Android delays
    // that service while this page is open, a guarded fallback sends only the
    // overdue ping; it does not create a second regular 10-second GPS stream.
    _timelineRefreshTimer = Timer.periodic(const Duration(seconds: 10), (
      _,
    ) async {
      if (!mounted || !trackingActive) return;
      await _loadTripSummary();
      await _sendFallbackPingIfDue();
    });
  }

  void _stopTimelineRefresh() {
    _timelineRefreshTimer?.cancel();
    _timelineRefreshTimer = null;
  }

  void _reloadSavedSession() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadFieldSession();
    });
  }

  Future<void> _loadTrackingPermissions() async {
    try {
      final permissions = await HrmsTrackingApi.trackingPermissions();
      if (!mounted) return;
      setState(() {
        _fieldTrackingEnabled =
            permissions['fieldTrackingEnabled'] == true ||
            permissions['field_tracking_enabled'] == true ||
            permissions['fieldTrackingEnabled'].toString() == '1';
        _homeLocationEnabled = permissions['homeLocationEnabled'] != false;
        if (!_fieldTrackingEnabled && mode == _WorkMode.field) {
          mode = _WorkMode.office;
        }
        if (!_homeLocationEnabled && mode == _WorkMode.home) {
          mode = _WorkMode.office;
        }
      });
    } catch (_) {
      // Field tracking remains unavailable unless the admin permission loads.
    }
  }

  Future<void> _loadOfficeSettings() async {
    try {
      final settings = await HrmsTrackingApi.trackingSettings();
      if (!mounted) return;
      setState(() {
        _officeSettings = settings;
        final configuredInterval =
            settings['field_ping_interval_minutes'] ??
            settings['fieldPingIntervalMinutes'];
        final parsedInterval = configuredInterval is num
            ? configuredInterval.toInt()
            : int.tryParse('$configuredInterval');
        _gpsUpdateIntervalMinutes = (parsedInterval ?? 15)
            .clamp(1, 1440)
            .toInt();
        _officeLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _officeLoading = false);
    }
  }

  Future<void> _loadOfficeLocations() async {
    try {
      final offices = await HrmsTrackingApi.activeOfficeLocations();
      if (!mounted) return;
      setState(() => _officeLocations = offices);
    } catch (_) {
      // The primary office marker remains available if this optional map list
      // cannot load (for example while an older server is being deployed).
    }
  }

  Future<void> _loadHomeLocation() async {
    try {
      final home = await HrmsTrackingApi.myHomeLocation();
      if (!mounted) return;
      setState(() {
        _homeLocation = home;
        _homeLoading = false;
        _homeError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _homeLoading = false;
        _homeError = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _openHomeLocation() async {
    if (_homeDialogOpen) return;
    setState(() => _homeDialogOpen = true);
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const HomeLocationDialog(),
      );
      if (mounted) await _loadHomeLocation();
    } finally {
      if (mounted) setState(() => _homeDialogOpen = false);
    }
  }

  Future<void> _loadFieldSession() async {
    try {
      final coordinator = context.read<LiveTrackingCoordinator>();
      await coordinator.restore();
      final timeline = await HrmsTrackingApi.fieldSessionTimeline();
      if (!mounted) return;
      setState(() {
        trackingActive = timeline['isActive'] == true;
        // The coordinator restores the interval that was captured in this
        // employee's active session. Do not use the global admin value here:
        // it may belong to a different template.
        _gpsUpdateIntervalMinutes = coordinator.pingMinutes;
        if (trackingActive) {
          mode = _WorkMode.field;
          updated = 'Live tracking active';
        }
        _applyTimeline(timeline);
      });
      if (trackingActive) {
        _startTimelineRefresh();
      } else {
        _stopTimelineRefresh();
      }
    } catch (_) {
      // Office and Home employees may not have a Field tracking session.
    }
  }

  Future<void> _loadTripSummary() async {
    if (_timelineRequestInFlight) return;
    _timelineRequestInFlight = true;
    try {
      final summary = await HrmsTrackingApi.fieldSessionTimeline();
      if (!mounted || summary['hasSession'] != true) return;
      setState(() {
        trackingActive = summary['isActive'] == true;
        _applyTimeline(summary);
      });
      if (!trackingActive) _stopTimelineRefresh();
    } catch (_) {
      // A later poll will retry after a temporary network failure.
    } finally {
      _timelineRequestInFlight = false;
    }
  }

  void _applyTimeline(Map<String, dynamic> summary) {
    final seconds = (summary['durationSeconds'] as num?)?.toInt() ?? 0;
    final minutes = seconds ~/ 60;
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    final distanceKm = (summary['distanceKm'] as num?)?.toDouble() ?? 0;
    final averageSpeed = (summary['averageSpeedKmph'] as num?)?.toDouble() ?? 0;
    duration = hours > 0 ? '${hours}h ${remainingMinutes}m' : '$minutes min';
    distance = '${distanceKm.toStringAsFixed(2)} km';
    avgSpeed = '${averageSpeed.toStringAsFixed(1)} km/h';
    final savedPoints = (summary['points'] as List? ?? [])
        .whereType<Map>()
        .map((point) {
          final lat = double.tryParse('${point['latitude']}');
          final lng = double.tryParse('${point['longitude']}');
          return lat == null || lng == null ? null : LatLng(lat, lng);
        })
        .whereType<LatLng>()
        .toList();
    _routePoints = savedPoints;
    final rawEvents = (summary['events'] as List? ?? [])
        .whereType<Map>()
        .toList();
    final items = rawEvents
        .map(
          (event) => {
            'activity_time': _eventTime(event['recordedAt']),
            'activity_text':
                '${event['text'] ?? 'Live location updated'}${event['address'] == null || '${event['address']}'.trim().isEmpty ? '' : ' — ${event['address']}'}${event['latitude'] == null ? '' : '\nGPS: ${event['latitude']}, ${event['longitude']}'}',
          },
        )
        .toList()
        .reversed
        .toList();
    activities = items.isEmpty
        ? [
            {
              'activity_time': '--:--',
              'activity_text': 'No live tracking activity yet',
            },
          ]
        : items;
    if (rawEvents.isNotEmpty) {
      updated = 'Updated ${_eventTime(rawEvents.last['recordedAt'])}';
      final recordedAt = DateTime.tryParse(
        '${rawEvents.last['recordedAt'] ?? ''}',
      );
      if (recordedAt != null) _lastSavedPingAt = recordedAt.toLocal();
    }
  }

  Future<void> _sendFallbackPingIfDue() async {
    // Android has a foreground service which is the sole GPS ping owner.
    // Sending a second ping from this visible page caused duplicate/too-frequent
    // records (for example a 15-minute template producing 1–2 minute pings).
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) return;

    if (!trackingActive || _fallbackPingInFlight || _lastSavedPingAt == null) {
      return;
    }

    // Give Android's foreground service 20 seconds after the configured due
    // time. If it still has not saved a point, the open Tracking page captures
    // the missed point itself. This is why a visible page no longer needs the
    // manual refresh button to make location activity and the waiting popup
    // appear.
    final dueAfter = Duration(minutes: _gpsUpdateIntervalMinutes, seconds: 20);
    if (DateTime.now().difference(_lastSavedPingAt!) < dueAfter) return;

    _fallbackPingInFlight = true;
    try {
      await context.read<LiveTrackingCoordinator>().sendPing();
      if (mounted) await _loadTripSummary();
    } finally {
      _fallbackPingInFlight = false;
    }
  }

  String _eventTime(dynamic raw) {
    final date = DateTime.tryParse('${raw ?? ''}');
    return date == null
        ? '--:--'
        : TimeOfDay.fromDateTime(date.toLocal()).format(context);
  }

  Future<void> _sendLocationPing({required bool showMessage}) async {
    if (!trackingActive) return;

    try {
      await context.read<LiveTrackingCoordinator>().sendPing();

      if (!mounted) return;
      await _loadTripSummary();

      if (showMessage && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Live location refreshed.')),
        );
      }
    } catch (error) {
      if (showMessage && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  Future<String?> _askStopReason() async {
    final controller = TextEditingController();
    String? error;
    final reason = await showDialog<String>(
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
    // Wait for the dialog pop transition to finish before disposing the
    // controller; otherwise Flutter may rebuild the TextField once more.
    Future<void>.delayed(const Duration(milliseconds: 350), controller.dispose);
    return reason;
  }

  Future<void> toggleTracking() async {
    if (_trackingActionInProgress) return;

    setState(() => _trackingActionInProgress = true);
    try {
      if (!trackingActive) {
        await context.read<LiveTrackingCoordinator>().start();

        if (!mounted) return;

        setState(() {
          trackingActive = true;
          mode = _WorkMode.field;
          updated = 'Updated just now';
        });
        _startTimelineRefresh();
        await _loadTripSummary();

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Live tracking started.')));
      } else {
        final reason = await _askStopReason();
        if (reason == null || !mounted) return;
        await context.read<LiveTrackingCoordinator>().stop(reason);

        if (!mounted) return;

        setState(() {
          trackingActive = false;
          updated = 'Live tracking stopped';
        });
        _stopTimelineRefresh();

        await _loadTripSummary();

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Live tracking stopped.')));
      }
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _trackingActionInProgress = false);
      }
    }
  }

  void refreshLocation() {
    _sendLocationPing(showMessage: true);
  }

  String get modeLabel => switch (mode) {
    _WorkMode.office => 'Office',
    _WorkMode.home => 'Home',
    _WorkMode.field => 'Field',
  };

  String get address {
    if (mode == _WorkMode.office) {
      if (_officeLoading) return 'Loading office location...';
      final officeName = '${_officeSettings?['office_name'] ?? ''}'.trim();
      final officeAddress = '${_officeSettings?['office_address'] ?? ''}'
          .trim();
      if (officeName.isEmpty && officeAddress.isEmpty) {
        return 'Office location has not been configured by admin.';
      }
      return [
        officeName,
        officeAddress,
      ].where((value) => value.isNotEmpty).join('\n');
    }

    if (mode == _WorkMode.home) {
      if (_homeLoading) return 'Loading home location...';
      if (_homeError != null) return _homeError!;
      if (_homeLocation == null) {
        return 'Register your home location for admin approval';
      }
      final status = _homeLocation!['approval_status'];
      final description = switch (status) {
        'approved' => 'Approved home location',
        'pending' => 'Pending admin approval — Home Clock In unavailable',
        'rejected' => 'Home location rejected — update and resubmit',
        _ => 'Home location approval required',
      };
      return '$description\n'
          '${_homeLocation!['address'] ?? ''}\n'
          'GPS: ${_homeLocation!['latitude']}, ${_homeLocation!['longitude']}';
    }

    if (_lastPosition != null) {
      return 'Live GPS: '
          '${_lastPosition!.latitude.toStringAsFixed(6)}, '
          '${_lastPosition!.longitude.toStringAsFixed(6)}';
    }

    return 'Field location will appear after live tracking starts';
  }

  Color get activeColor =>
      mode == _WorkMode.field ? employeeGreen : employeeBlue;

  @override
  Widget build(BuildContext context) {
    if (widget.routeHistory) {
      return _RouteHistoryView(mobile: widget.mobile);
    }

    final modes = _ModeTabs(
      selected: mode,
      homeEnabled: _homeLocationEnabled,
      fieldEnabled: _fieldTrackingEnabled,
      onChanged: (value) => setState(() => mode = value),
    );

    final status = _CurrentStatusCard(
      mode: modeLabel,
      address: address,
      color: activeColor,
      onRefresh: mode == _WorkMode.office
          ? _loadOfficeSettings
          : mode == _WorkMode.home
          ? _loadHomeLocation
          : refreshLocation,
    );

    final map = _RouteMap(
      mode: mode,
      position: _lastPosition,
      routePoints: _routePoints,
      homeLocation: _homeLocation,
      officeSettings: _officeSettings,
      officeLocations: _officeLocations,
    );

    final homeAction = Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: _homeDialogOpen ? null : _openHomeLocation,
        icon: const Icon(Icons.add_home_outlined),
        label: Text(
          _homeLocation == null
              ? 'Register Home Location'
              : 'Manage Home Location',
        ),
      ),
    );

    final metrics = _TripMetrics(
      distance: distance,
      duration: duration,
      avgSpeed: avgSpeed,
    );

    final timeline = _ActivityTimeline(activities: activities);

    final live = _LiveTrackingControl(
      active: trackingActive,
      busy: _trackingActionInProgress,
      onToggle: toggleTracking,
    );

    // Only Field and Hybrid employees receive field-tracking permission. The
    // backend performs the same authorization before saving a comment.
    final comments = const TrackingCommentsSection();

    if (widget.mobile) {
      final premiumStatus = _PremiumTrackingStatusCard(
        mode: modeLabel,
        address: address,
        locationName: _trackingLocationName,
        active: trackingActive,
        onRefresh: mode == _WorkMode.office
            ? _loadOfficeSettings
            : mode == _WorkMode.home
            ? _loadHomeLocation
            : refreshLocation,
      );
      final premiumMap = _PremiumLiveMapCard(
        map: _RouteMap(
          mode: mode,
          position: _lastPosition,
          routePoints: _routePoints,
          homeLocation: _homeLocation,
          officeSettings: _officeSettings,
          officeLocations: _officeLocations,
          aspectRatio: 1.7,
          mapController: _mapController,
        ),
        active: trackingActive,
        busy: _trackingActionInProgress,
        distance: distance,
        duration: duration,
        avgSpeed: avgSpeed,
        onToggle: toggleTracking,
        mapController: _mapController,
        recenterTarget: _trackingMapCenter,
        recenterZoom:
            mode == _WorkMode.field &&
                (_routePoints.isNotEmpty || _lastPosition != null)
            ? 16
            : 15,
      );
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _TrackingHero(),
              const SizedBox(height: 16),
              modes,
              const SizedBox(height: 18),
              premiumStatus,
              if (mode == _WorkMode.home) ...[
                const SizedBox(height: 12),
                homeAction,
              ],
              const SizedBox(height: 18),
              premiumMap,
              if (_fieldTrackingEnabled) ...[
                const SizedBox(height: 18),
                comments,
              ],
              const SizedBox(height: 18),
              _PremiumActivityCard(activities: activities),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        modes,
        const SizedBox(height: 18),
        status,
        if (mode == _WorkMode.home) ...[const SizedBox(height: 12), homeAction],
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Live Location',
                style: TextStyle(
                  color: employeeNavy,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(updated, style: const TextStyle(color: employeeMuted)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 7,
              child: Column(
                children: [map, const SizedBox(height: 14), metrics],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              flex: 4,
              child: Column(
                children: [
                  if (_fieldTrackingEnabled) ...[
                    comments,
                    const SizedBox(height: 18),
                  ],
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Today’s Activity',
                      style: TextStyle(
                        color: employeeNavy,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  timeline,
                  const SizedBox(height: 18),
                  if (_fieldTrackingEnabled) live,
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  String get _trackingLocationName {
    if (mode == _WorkMode.office) {
      final name = '${_officeSettings?['office_name'] ?? ''}'.trim();
      return name.isEmpty ? 'Main Office' : name;
    }
    if (mode == _WorkMode.home) return 'Home location';
    return trackingActive ? 'Current field location' : 'Field operations';
  }

  LatLng get _trackingMapCenter {
    if (mode == _WorkMode.field) {
      if (_routePoints.isNotEmpty) return _routePoints.last;
      if (_lastPosition != null) {
        return LatLng(_lastPosition!.latitude, _lastPosition!.longitude);
      }
    }
    if (mode == _WorkMode.home) {
      final latitude = double.tryParse('${_homeLocation?['latitude']}');
      final longitude = double.tryParse('${_homeLocation?['longitude']}');
      if (latitude != null && longitude != null) {
        return LatLng(latitude, longitude);
      }
    }
    final latitude = double.tryParse('${_officeSettings?['office_latitude']}');
    final longitude = double.tryParse(
      '${_officeSettings?['office_longitude']}',
    );
    return latitude != null && longitude != null
        ? LatLng(latitude, longitude)
        : const LatLng(20.5937, 78.9629);
  }
}

class _TrackingHero extends StatelessWidget {
  const _TrackingHero();

  @override
  Widget build(BuildContext context) => Consumer<AuthService>(
    builder: (_, auth, __) {
      final name =
          '${auth.user?['fullName'] ?? auth.user?['name'] ?? 'Employee'}'
              .trim();
      final employeeId =
          '${auth.user?['staffId'] ?? auth.user?['employeeCode'] ?? auth.user?['employee_code'] ?? ''}'
              .trim();
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        'Hello, ${name.isEmpty ? 'Employee' : name}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: employeeMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (employeeId.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      const Text('•', style: TextStyle(color: employeeMuted)),
                      const SizedBox(width: 6),
                      Text(
                        employeeId,
                        style: const TextStyle(
                          color: employeeBlue,
                          fontFamily: 'monospace',
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                const Text(
                  'Live Tracking',
                  style: TextStyle(
                    color: employeeNavy,
                    fontSize: 28,
                    height: 1.08,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            margin: const EdgeInsets.only(top: 3),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3FF),
              border: Border.all(color: const Color(0xFFBFDBFE)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.satellite_alt_rounded,
                  size: 14,
                  color: employeeBlue,
                ),
                SizedBox(width: 5),
                Text(
                  'GPS Ready',
                  style: TextStyle(
                    color: Color(0xFF0F4AA6),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _PremiumTrackingStatusCard extends StatelessWidget {
  const _PremiumTrackingStatusCard({
    required this.mode,
    required this.address,
    required this.locationName,
    required this.active,
    required this.onRefresh,
  });

  final String mode;
  final String address;
  final String locationName;
  final bool active;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: employeeLine),
      borderRadius: BorderRadius.circular(22),
      boxShadow: const [
        BoxShadow(
          color: Color(0x14141E33),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      children: [
        const SizedBox(
          height: 4,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFFBFDBFE),
                  Color(0xFF93C5FD),
                  Color(0xFFBFDBFE),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          child: Column(
            children: [
              Row(
                children: [
                  const Text(
                    'Current Status',
                    style: TextStyle(
                      color: employeeNavy,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusPill(label: mode),
                  const Spacer(),
                  Text(
                    active ? 'Live now' : 'Ready',
                    style: const TextStyle(
                      color: employeeMuted,
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFD),
                  border: Border.all(color: employeeLine),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: employeeBlue,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.location_on_rounded,
                        size: 21,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  locationName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: employeeNavy,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              const _GpsPill(),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            address.replaceAll('\n', ', '),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: employeeMuted,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Refresh GPS location',
                      onPressed: onRefresh,
                      style: IconButton.styleFrom(
                        foregroundColor: employeeBlue,
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: employeeLine),
                        minimumSize: const Size(39, 39),
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF3FF),
      border: Border.all(color: const Color(0xFFBFDBFE)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircleAvatar(radius: 3, backgroundColor: employeeBlue),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF0F4AA6),
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _GpsPill extends StatelessWidget {
  const _GpsPill();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF3FF),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Text(
      '± GPS',
      style: TextStyle(
        color: employeeBlue,
        fontFamily: 'monospace',
        fontSize: 9,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _PremiumLiveMapCard extends StatelessWidget {
  const _PremiumLiveMapCard({
    required this.map,
    required this.active,
    required this.busy,
    required this.distance,
    required this.duration,
    required this.avgSpeed,
    required this.onToggle,
    required this.mapController,
    required this.recenterTarget,
    required this.recenterZoom,
  });

  final Widget map;
  final bool active;
  final bool busy;
  final String distance;
  final String duration;
  final String avgSpeed;
  final VoidCallback onToggle;
  final ValueNotifier<GoogleMapController?> mapController;
  final LatLng recenterTarget;
  final double recenterZoom;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF101B32), Color(0xFF16243A)],
      ),
      border: Border.all(color: const Color(0xFF1E477F)),
      borderRadius: BorderRadius.circular(23),
      boxShadow: const [
        BoxShadow(
          color: Color(0x23111C32),
          blurRadius: 20,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: Column(
      children: [
        Row(
          children: [
            const Icon(Icons.map_outlined, color: Color(0xFFBFDBFE), size: 21),
            const SizedBox(width: 9),
            const Expanded(
              child: Text(
                'Live Location',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFF047857)
                    : const Color(0xFF1E2C45),
                border: Border.all(color: const Color(0xFF315B93)),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                active ? 'Tracking live' : 'Not tracking yet',
                style: const TextStyle(
                  color: Color(0xFFDCEBFF),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: Stack(
            children: [
              map,
              Positioned(
                top: 10,
                right: 10,
                child: _MapCameraControls(
                  controller: mapController,
                  recenterTarget: recenterTarget,
                  recenterZoom: recenterZoom,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _DarkMetric(
                icon: Icons.route_rounded,
                label: 'Distance',
                value: distance == '—' ? '0.00 km' : distance,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DarkMetric(
                icon: Icons.schedule_rounded,
                label: 'Duration',
                value: duration == '—' ? '0 min' : duration,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DarkMetric(
                icon: Icons.speed_rounded,
                label: 'Avg Speed',
                value: avgSpeed == '—' ? '0.0 km/h' : avgSpeed,
              ),
            ),
          ],
        ),
        const SizedBox(height: 13),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1D2A41),
            border: Border.all(color: const Color(0xFF315B93)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 5,
                backgroundColor: active
                    ? const Color(0xFF34D399)
                    : const Color(0xFF71839D),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  active ? 'Live tracking is active' : 'Live tracking is off',
                  style: const TextStyle(
                    color: Color(0xFFDCEBFF),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: busy ? null : onToggle,
                style: FilledButton.styleFrom(
                  backgroundColor: active
                      ? const Color(0xFFE9262D)
                      : employeeBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                icon: Icon(
                  active
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline_rounded,
                  size: 17,
                ),
                label: Text(
                  busy
                      ? (active ? 'Stopping…' : 'Starting…')
                      : (active ? 'Stop' : 'Start Tracking'),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MapCameraControls extends StatelessWidget {
  const _MapCameraControls({
    required this.controller,
    required this.recenterTarget,
    required this.recenterZoom,
  });

  final ValueNotifier<GoogleMapController?> controller;
  final LatLng recenterTarget;
  final double recenterZoom;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<GoogleMapController?>(
        valueListenable: controller,
        builder: (_, map, __) => Column(
          children: [
            _MapControlButton(
              icon: Icons.gps_fixed_rounded,
              tooltip: 'Center map on current location',
              onPressed: map == null
                  ? null
                  : () => map.animateCamera(
                      CameraUpdate.newCameraPosition(
                        CameraPosition(
                          target: recenterTarget,
                          zoom: recenterZoom,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 7),
            _MapControlButton(
              icon: Icons.add_rounded,
              tooltip: 'Zoom in',
              onPressed: map == null
                  ? null
                  : () => map.animateCamera(CameraUpdate.zoomIn()),
            ),
            const SizedBox(height: 7),
            _MapControlButton(
              icon: Icons.remove_rounded,
              tooltip: 'Zoom out',
              onPressed: map == null
                  ? null
                  : () => map.animateCamera(CameraUpdate.zoomOut()),
            ),
          ],
        ),
      );
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: Colors.white,
      elevation: 2,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 39,
          height: 39,
          child: Icon(
            icon,
            color: onPressed == null ? const Color(0xFF9BAAC0) : employeeNavy,
            size: 21,
          ),
        ),
      ),
    ),
  );
}

class _DarkMetric extends StatelessWidget {
  const _DarkMetric({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    height: 91,
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFF1E2C45),
      border: Border.all(color: const Color(0xFF315B93)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: const Color(0xFFBFDBFE), size: 18),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFBFDBFE),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _PremiumActivityCard extends StatelessWidget {
  const _PremiumActivityCard({required this.activities});
  final List<dynamic> activities;

  @override
  Widget build(BuildContext context) => EmployeeCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Today’s Activity',
                style: TextStyle(
                  color: employeeNavy,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '${activities.length == 1 && activities.first['activity_time'] == '--:--' ? 0 : activities.length} Events',
                style: const TextStyle(
                  color: employeeMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (activities.length == 1 &&
            activities.first['activity_time'] == '--:--')
          const Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: Color(0xFFF1F5F9),
                child: Icon(
                  Icons.check_rounded,
                  color: employeeMuted,
                  size: 17,
                ),
              ),
              SizedBox(width: 12),
              Text(
                '--:--   No live tracking activity yet',
                style: TextStyle(color: employeeMuted, fontSize: 12),
              ),
            ],
          )
        else
          ...activities.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 14,
                    backgroundColor: Color(0xFFDDF7ED),
                    child: Icon(
                      Icons.check_rounded,
                      color: employeeGreen,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      '${item['activity_time'] ?? '--:--'}  •  ${item['activity_text'] ?? ''}',
                      style: const TextStyle(
                        color: employeeNavy,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class _RouteHistoryView extends StatelessWidget {
  const _RouteHistoryView({required this.mobile});
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final history = const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Routes',
          style: TextStyle(
            color: employeeNavy,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 12),
        _RouteHistoryCard(
          'Today',
          'Sector 62 → Sector 63 → Sector 62',
          '18.6 km',
          '01h 48m',
        ),
        SizedBox(height: 12),
        _RouteHistoryCard(
          '22 Aug 2026',
          'Noida Office → Sector 18 → Noida Office',
          '12.4 km',
          '01h 12m',
        ),
        SizedBox(height: 12),
        _RouteHistoryCard(
          '21 Aug 2026',
          'Noida Office → Greater Noida',
          '24.1 km',
          '02h 06m',
        ),
      ],
    );
    return mobile
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MobileEmployeeHeader(),
              const SizedBox(height: 14),
              const EmployeePageTitle(title: 'Route History'),
              const SizedBox(height: 20),
              history,
            ],
          )
        : history;
  }
}

class _RouteHistoryCard extends StatelessWidget {
  const _RouteHistoryCard(this.date, this.route, this.distance, this.duration);
  final String date, route, distance, duration;

  @override
  Widget build(BuildContext context) => EmployeeCard(
    padding: const EdgeInsets.all(18),
    child: Row(
      children: [
        Container(
          width: 43,
          height: 43,
          decoration: BoxDecoration(
            color: const Color(0xFFE9F7F7),
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(Icons.route_outlined, color: Color(0xFF079B9B)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                date,
                style: const TextStyle(
                  color: employeeNavy,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                route,
                style: const TextStyle(color: employeeMuted, fontSize: 13),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              distance,
              style: const TextStyle(
                color: employeeNavy,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              duration,
              style: const TextStyle(color: employeeMuted, fontSize: 12),
            ),
          ],
        ),
      ],
    ),
  );
}

class _ModeTabs extends StatelessWidget {
  const _ModeTabs({
    required this.selected,
    required this.homeEnabled,
    required this.fieldEnabled,
    required this.onChanged,
  });
  final _WorkMode selected;
  final bool homeEnabled;
  final bool fieldEnabled;
  final ValueChanged<_WorkMode> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: employeeLine),
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0B0F52BA),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Row(
      children: [
        _ModeTab(
          icon: Icons.apartment_rounded,
          label: 'Office',
          active: selected == _WorkMode.office,
          onTap: () => onChanged(_WorkMode.office),
        ),
        if (homeEnabled) ...[
          const SizedBox(width: 8),
          _ModeTab(
            icon: Icons.home_outlined,
            label: 'Home',
            active: selected == _WorkMode.home,
            onTap: () => onChanged(_WorkMode.home),
          ),
        ],
        if (fieldEnabled) ...[
          const SizedBox(width: 8),
          _ModeTab(
            icon: Icons.person_outline_rounded,
            label: 'Field',
            active: selected == _WorkMode.field,
            onTap: () => onChanged(_WorkMode.field),
          ),
        ],
      ],
    ),
  );
}

class _ModeTab extends StatefulWidget {
  const _ModeTab({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_ModeTab> createState() => _ModeTabState();
}

class _ModeTabState extends State<_ModeTab> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => Expanded(
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        scale: _pressed ? .975 : (_hovered && !widget.active ? 1.015 : 1),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            border: Border.all(
              color: widget.active
                  ? const Color(0xFF1959C5)
                  : (_hovered ? const Color(0xFFBFDBFE) : Colors.transparent),
            ),
            borderRadius: BorderRadius.circular(15),
            color: widget.active ? const Color(0xFF1959C5) : Colors.transparent,
            boxShadow: widget.active
                ? const [
                    BoxShadow(
                      color: Color(0x331D4ED8),
                      blurRadius: 9,
                      offset: Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              onHighlightChanged: (value) => setState(() => _pressed = value),
              borderRadius: BorderRadius.circular(15),
              hoverColor: Colors.transparent,
              highlightColor: Colors.transparent,
              splashColor: Colors.transparent,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.icon,
                    color: widget.active ? Colors.white : employeeMuted,
                    size: 21,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.active ? Colors.white : employeeNavy,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _CurrentStatusCard extends StatelessWidget {
  const _CurrentStatusCard({
    required this.mode,
    required this.address,
    required this.color,
    required this.onRefresh,
  });
  final String mode;
  final String address;
  final Color color;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => EmployeeCard(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Current Status',
              style: TextStyle(
                color: employeeNavy,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 12),
            CircleAvatar(radius: 5, backgroundColor: color),
            const SizedBox(width: 7),
            Text(
              mode,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            const Text(
              'Since 09:20 AM',
              style: TextStyle(color: employeeMuted, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            const Icon(
              Icons.location_on_outlined,
              color: employeeMuted,
              size: 30,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                address,
                style: const TextStyle(color: employeeMuted, height: 1.4),
              ),
            ),
            IconButton.outlined(
              tooltip: 'Refresh live location',
              onPressed: onRefresh,
              icon: const Icon(
                Icons.refresh_rounded,
                color: employeeBlue,
                size: 27,
              ),
              style: IconButton.styleFrom(
                padding: const EdgeInsets.all(11),
                side: const BorderSide(color: employeeLine),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _RouteMap extends StatelessWidget {
  const _RouteMap({
    required this.mode,
    required this.position,
    this.homeLocation,
    this.officeSettings,
    this.officeLocations = const [],
    this.routePoints = const [],
    this.aspectRatio = 1.95,
    this.mapController,
  });

  final _WorkMode mode;
  final Position? position;
  final Map<String, dynamic>? homeLocation;
  final Map<String, dynamic>? officeSettings;
  final List<Map<String, dynamic>> officeLocations;
  final List<LatLng> routePoints;
  final double aspectRatio;
  final ValueNotifier<GoogleMapController?>? mapController;
  static final Map<int, Future<BitmapDescriptor>> _officeMarkerCache = {};
  static final Future<BitmapDescriptor> _liveGpsPuck = _employeeGpsPuckIcon();

  static Future<BitmapDescriptor> _officeMarkerFor(int number) =>
      _officeMarkerCache.putIfAbsent(number, () => _a1OfficeMarkerIcon(number));

  static const _paleMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#EDF5FF"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#27436D"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#EDF5FF"}]},
  {"featureType":"administrative","elementType":"geometry.stroke","stylers":[{"color":"#C8D7EA"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#E4EFFD"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#D9EAFD"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#C9D7E7"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#B8CBE0"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#7AA7EE"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#2D67D8"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#C9E1FF"}]}
]
''';

  @override
  Widget build(BuildContext context) {
    final livePoint = routePoints.isNotEmpty
        ? routePoints.last
        : position == null
        ? null
        : LatLng(position!.latitude, position!.longitude);

    final homeLat = double.tryParse('${homeLocation?['latitude']}');
    final homeLng = double.tryParse('${homeLocation?['longitude']}');
    final homePoint = homeLat != null && homeLng != null
        ? LatLng(homeLat, homeLng)
        : null;
    final officeLat = double.tryParse('${officeSettings?['office_latitude']}');
    final officeLng = double.tryParse('${officeSettings?['office_longitude']}');
    final officePoint = officeLat != null && officeLng != null
        ? LatLng(officeLat, officeLng)
        : const LatLng(20.5937, 78.9629);
    final officeName = '${officeSettings?['office_name'] ?? 'Office'}';
    final configuredOffices = officeLocations
        .map((office) {
          final latitude = double.tryParse('${office['latitude']}');
          final longitude = double.tryParse('${office['longitude']}');
          if (latitude == null || longitude == null) return null;
          return _OfficeMarkerData(
            id: int.tryParse('${office['id']}'),
            name: '${office['name'] ?? 'A1 Blowers Office'}',
            position: LatLng(latitude, longitude),
          );
        })
        .whereType<_OfficeMarkerData>()
        .toList();
    final offices = configuredOffices.isEmpty
        ? [_OfficeMarkerData(id: null, name: officeName, position: officePoint)]
        : configuredOffices;
    final markersFuture = Future.wait<BitmapDescriptor>([
      for (var index = 0; index < offices.length; index++)
        _officeMarkerFor(index + 1),
      _liveGpsPuck,
    ]);

    final center = mode == _WorkMode.field && livePoint != null
        ? livePoint
        : mode == _WorkMode.home && homePoint != null
        ? homePoint
        : officePoint;

    final markerColor = mode == _WorkMode.field
        ? BitmapDescriptor.hueRed
        : mode == _WorkMode.home
        ? BitmapDescriptor.hueGreen
        : BitmapDescriptor.hueAzure;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: FutureBuilder<List<BitmapDescriptor>>(
          future: markersFuture,
          builder: (context, snapshot) => GoogleMap(
            key: ValueKey(
              'tracking-map-${mode.name}-${officePoint.latitude}-${officePoint.longitude}-${homePoint?.latitude}-${homePoint?.longitude}',
            ),
            initialCameraPosition: CameraPosition(
              target: center,
              // Four nearby offices remain visible together at city level;
              // individual A1-numbered beacons identify each location.
              zoom: mode == _WorkMode.field && livePoint != null
                  ? 16
                  : mode == _WorkMode.office && offices.length > 1
                  ? 12.5
                  : 15,
            ),
            onMapCreated: (controller) => mapController?.value = controller,
            style: _paleMapStyle,
            mapToolbarEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            myLocationButtonEnabled: false,
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
            },
            markers: {
              if (mode == _WorkMode.office)
                for (var index = 0; index < offices.length; index++)
                  Marker(
                    markerId: MarkerId('office-${offices[index].id ?? index}'),
                    position: offices[index].position,
                    infoWindow: InfoWindow(
                      title: offices[index].name,
                      snippet: 'A1 Blowers office • ${index + 1}',
                    ),
                    icon:
                        snapshot.data?[index] ??
                        BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueAzure,
                        ),
                    anchor: const Offset(.5, .91),
                  ),
              if (mode == _WorkMode.home && homePoint != null)
                Marker(
                  markerId: const MarkerId('registered-home'),
                  position: homePoint,
                  infoWindow: InfoWindow(
                    title: 'Registered Home',
                    snippet: '${homeLocation?['approval_status'] ?? ''}',
                  ),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueGreen,
                  ),
                ),
              if (mode == _WorkMode.field && livePoint != null)
                Marker(
                  markerId: const MarkerId('live-location'),
                  position: livePoint,
                  infoWindow: const InfoWindow(title: 'Your Live Location'),
                  icon:
                      snapshot.data?[offices.length] ??
                      BitmapDescriptor.defaultMarkerWithHue(markerColor),
                  anchor: const Offset(.5, .5),
                ),
            },
            polylines: mode == _WorkMode.field && routePoints.length > 1
                ? {
                    Polyline(
                      polylineId: const PolylineId('saved-field-route'),
                      points: routePoints,
                      color: employeeBlue,
                      width: 5,
                    ),
                  }
                : const {},
          ),
        ),
      ),
    );
  }
}

class _TripMetrics extends StatelessWidget {
  const _TripMetrics({
    required this.distance,
    required this.duration,
    required this.avgSpeed,
  });

  final String distance;
  final String duration;
  final String avgSpeed;

  @override
  Widget build(BuildContext context) => EmployeeCard(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
    child: Row(
      children: [
        Expanded(
          child: _TripMetric(
            Icons.route_outlined,
            'Distance Travelled',
            distance,
            employeeGreen,
          ),
        ),
        const SizedBox(height: 66, child: VerticalDivider(color: employeeLine)),
        Expanded(
          child: _TripMetric(
            Icons.schedule_rounded,
            'Duration',
            duration,
            employeeBlue,
          ),
        ),
        const SizedBox(height: 66, child: VerticalDivider(color: employeeLine)),
        Expanded(
          child: _TripMetric(
            Icons.speed_rounded,
            'Avg Speed',
            avgSpeed,
            employeeGreen,
          ),
        ),
      ],
    ),
  );
}

class _TripMetric extends StatelessWidget {
  const _TripMetric(this.icon, this.label, this.value, this.color);
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(icon, color: color, size: 27),
      const SizedBox(height: 7),
      Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(color: employeeMuted, fontSize: 10),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        maxLines: 1,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: employeeNavy,
          fontSize: 17,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _ActivityTimeline extends StatelessWidget {
  const _ActivityTimeline({required this.activities});
  final List<dynamic> activities;

  @override
  Widget build(BuildContext context) => EmployeeCard(
    padding: const EdgeInsets.all(18),
    child: Column(
      children: activities.asMap().entries.map((entry) {
        final idx = entry.key;
        final item = entry.value;
        final timeStr = item['activity_time']?.toString() ?? '--:--';
        final textStr = item['activity_text']?.toString() ?? '';
        final isLast = idx == activities.length - 1;

        return Column(
          children: [
            _TimelineRow(timeStr, textStr),
            if (!isLast) const Divider(indent: 42, color: employeeLine),
          ],
        );
      }).toList(),
    ),
  );
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow(this.time, this.label);
  final String time;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        const CircleAvatar(
          radius: 14,
          backgroundColor: employeeGreen,
          child: Icon(Icons.check, color: Colors.white, size: 16),
        ),
        const SizedBox(width: 14),
        SizedBox(
          width: 78,
          child: Text(
            time,
            style: const TextStyle(
              color: employeeNavy,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(label, style: const TextStyle(color: employeeMuted)),
        ),
      ],
    ),
  );
}

class _LiveTrackingControl extends StatelessWidget {
  const _LiveTrackingControl({
    required this.active,
    required this.busy,
    required this.onToggle,
  });
  final bool active;
  final bool busy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: active ? const Color(0xFFEAF9F4) : const Color(0xFFF5F7FB),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: active ? const Color(0xFFCAEDE1) : employeeLine,
      ),
    ),
    child: Column(
      children: [
        Text(
          active ? '●  Live tracking active' : 'Live tracking is off',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: active ? employeeGreen : employeeMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: busy ? null : onToggle,
          icon: Icon(
            active ? Icons.stop_circle_outlined : Icons.play_circle_outline,
          ),
          label: Text(
            busy
                ? (active ? 'Stopping…' : 'Starting…')
                : (active ? 'Stop Live Tracking' : 'Start Live Tracking'),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: active ? const Color(0xFFD84343) : employeeGreen,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
      ],
    ),
  );
}
