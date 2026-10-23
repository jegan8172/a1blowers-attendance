import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../services/hrms_tracking_api.dart';
import '../../services/tracking_comments_section.dart';
import '../shared/employee_ui.dart';
import '../shared/live_tracking_coordinator.dart';
import 'home_location_dialog.dart';

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
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    employeeRouteSignal.revision.removeListener(_reloadSavedSession);
    _stopTimelineRefresh();
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
    _timelineRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
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
        _gpsUpdateIntervalMinutes = (parsedInterval ?? 15).clamp(1, 1440).toInt();
        _officeLoading = false;
      });

    } catch (_) {
      if (!mounted) return;
      setState(() => _officeLoading = false);
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
      await context.read<LiveTrackingCoordinator>().restore();
      final timeline = await HrmsTrackingApi.fieldSessionTimeline();
      if (!mounted) return;
      setState(() {
        trackingActive = timeline['isActive'] == true;
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
      final averageSpeed =
          (summary['averageSpeedKmph'] as num?)?.toDouble() ?? 0;
      duration = hours > 0
            ? '${hours}h ${remainingMinutes}m'
            : '$minutes min';
      distance = '${distanceKm.toStringAsFixed(2)} km';
      avgSpeed = '${averageSpeed.toStringAsFixed(1)} km/h';
      final savedPoints = (summary['points'] as List? ?? []).whereType<Map>().map((point) {
        final lat = double.tryParse('${point['latitude']}');
        final lng = double.tryParse('${point['longitude']}');
        return lat == null || lng == null ? null : LatLng(lat, lng);
      }).whereType<LatLng>().toList();
      _routePoints = savedPoints;
      final rawEvents = (summary['events'] as List? ?? []).whereType<Map>().toList();
      final items = rawEvents.map((event) => {
        'activity_time': _eventTime(event['recordedAt']),
        'activity_text': '${event['text'] ?? 'Live location updated'}${event['address'] == null || '${event['address']}'.trim().isEmpty ? '' : ' — ${event['address']}'}${event['latitude'] == null ? '' : '\nGPS: ${event['latitude']}, ${event['longitude']}'}',
      }).toList().reversed.toList();
      activities = items.isEmpty ? [{'activity_time': '--:--', 'activity_text': 'No live tracking activity yet'}] : items;
      if (rawEvents.isNotEmpty) {
        updated = 'Updated ${_eventTime(rawEvents.last['recordedAt'])}';
        final recordedAt = DateTime.tryParse('${rawEvents.last['recordedAt'] ?? ''}');
        if (recordedAt != null) _lastSavedPingAt = recordedAt.toLocal();
      }
  }

  Future<void> _sendFallbackPingIfDue() async {
    if (!trackingActive ||
        _fallbackPingInFlight ||
        _lastSavedPingAt == null) {
      return;
    }

    // Give Android's foreground service 20 seconds after the configured due
    // time. If it still has not saved a point, the open Tracking page captures
    // the missed point itself. This is why a visible page no longer needs the
    // manual refresh button to make location activity and the waiting popup
    // appear.
    final dueAfter = Duration(
      minutes: _gpsUpdateIntervalMinutes,
      seconds: 20,
    );
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
    return date == null ? '--:--' : TimeOfDay.fromDateTime(date.toLocal()).format(context);
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
        builder: (_, setDialogState) => AlertDialog(
          title: const Text('Stop live tracking'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter the reason for stopping live tracking.'),
              const SizedBox(height: 12),
              TextField(
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
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.length < 3) {
                  setDialogState(() => error = 'Enter at least 3 characters.');
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: const Text('Stop tracking'),
            ),
          ],
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MobileEmployeeHeader(),
          const SizedBox(height: 14),
          const EmployeePageTitle(title: 'Live Tracking'),
          const SizedBox(height: 18),
          modes,
          const SizedBox(height: 14),
          status,
          if (mode == _WorkMode.home) ...[
            const SizedBox(height: 12),
            homeAction,
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Live Location',
                  style: TextStyle(
                    color: employeeNavy,
                    fontSize: 20,
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
          map,
          const SizedBox(height: 14),
          metrics,
          if (_fieldTrackingEnabled) ...[const SizedBox(height: 18), comments],
          const SizedBox(height: 22),
          const Text(
            'Today’s Activity',
            style: TextStyle(
              color: employeeNavy,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          timeline,
          const SizedBox(height: 18),
          if (_fieldTrackingEnabled) live,
        ],
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
  Widget build(BuildContext context) => Row(
    children: [
      _ModeTab(
        icon: Icons.business_outlined,
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
  );
}

class _ModeTab extends StatelessWidget {
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
  Widget build(BuildContext context) => Expanded(
    child: Material(
      color: active ? employeeGreen : Colors.white,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            border: Border.all(color: active ? employeeGreen : employeeLine),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: active ? Colors.white : employeeMuted,
                size: 25,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : employeeNavy,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
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
    this.routePoints = const [],
  });

  final _WorkMode mode;
  final Position? position;
  final Map<String, dynamic>? homeLocation;
  final Map<String, dynamic>? officeSettings;
  final List<LatLng> routePoints;

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
        aspectRatio: 1.95,
        child: GoogleMap(
          key: ValueKey(
            'tracking-map-${mode.name}-${officePoint.latitude}-${officePoint.longitude}-${homePoint?.latitude}-${homePoint?.longitude}',
          ),
          initialCameraPosition: CameraPosition(
            target: center,
            zoom: mode == _WorkMode.field && livePoint != null ? 16 : 15,
          ),
          mapToolbarEnabled: false,
          markers: {
            Marker(
              markerId: const MarkerId('office'),
              position: officePoint,
              infoWindow: InfoWindow(title: officeName),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure,
              ),
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
                icon: BitmapDescriptor.defaultMarkerWithHue(markerColor),
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
