import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../../shared/theme/admin_surface_palette.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/hrms_tracking_api.dart';
import '../../../services/office_address_search.dart';
import '../../shared/widgets/admin_top_nav.dart';
import 'widgets/home_locations_dialog.dart';

abstract final class HrmsColors {
  static const blue = Color(0xFF1769E0);
  static const navy = Color(0xFF081B3C);
  static const page = Color(0xFFF7F8FA);
}

Future<BitmapDescriptor> _adminRouteMarkerIcon(
  Color color,
  String label,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawCircle(
    const Offset(30, 31),
    23,
    Paint()..color = const Color(0x33000000),
  );
  final pin = Path()
    ..moveTo(28, 62)
    ..lineTo(14, 35)
    ..arcToPoint(const Offset(42, 35), radius: const Radius.circular(20))
    ..close();
  canvas.drawPath(pin, Paint()..color = color);
  canvas.drawCircle(const Offset(28, 28), 16, Paint()..color = Colors.white);
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900),
    ),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  painter.paint(
    canvas,
    Offset(28 - painter.width / 2, 28 - painter.height / 2),
  );
  final image = await recorder.endRecording().toImage(56, 70);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(
    Uint8List.fromList(bytes!.buffer.asUint8List()),
  );
}

class TrackingPage extends StatefulWidget {
  const TrackingPage({super.key, this.settingsAction, this.inSettingsDialog = false});

  final String? settingsAction;
  final bool inSettingsDialog;

  static Widget builder(BuildContext context) => const TrackingPage();

  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage> {
  bool _openedSettingsAction = false;
  String mode = 'Field';

  static const _modeStorageKey = 'admin_tracking_last_mode';
  static const _pollInterval = Duration(seconds: 30);

  List<_TrackedEmployee> employees = [];
  _TrackingCounts counts = const _TrackingCounts(
    office: 0,
    home: 0,
    field: 0,
    activeNow: 0,
  );
  bool loading = true;
  String? error;
  DateTime? lastLoadedAt;
  Timer? _pollTimer;
  _TrackedEmployee? selectedEmployee;
  bool homeTrackingEnabled = false;
  LatLng? officeLocation;
  int officeFocusRequest = 0;

  @override
  void initState() {
    super.initState();
    _loadMode();
    _load();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _load(silent: true));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final action = widget.settingsAction ??
        (ModalRoute.of(context)?.settings.arguments as Map?)?['settingsAction'];
    if (_openedSettingsAction || action == null) return;
    _openedSettingsAction = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (action == 'officeLocation') await _openOfficeLocation();
      if (action == 'trackingSettings') await _openFieldWaitingSettings();
      if (action == 'clockOutReminderSettings') {
        await _openClockOutReminderSettings();
      }
      if (widget.inSettingsDialog && mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _openFieldWaitingSettings() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _FieldWaitingSettingsDialog(),
    );
  }

  Future<void> _openClockOutReminderSettings() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _FieldWaitingSettingsDialog(clockOutOnly: true),
    );
  }

  Future<void> _openFieldWaitingReasons() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _FieldWaitingReasonsDialog(),
    );
  }

  Future<void> _openHomeApprovals() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const HomeLocationsDialog(),
    );
    if (mounted) await _load(silent: true);
  }

  Future<void> _openOfficeLocation() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _OfficeLocationDialog(),
    );
    if (saved == true && mounted) await _load(silent: true);
  }

  Future<void> _loadMode() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_modeStorageKey);
    if (!mounted || saved == null) return;
    if (saved == 'Office' || saved == 'Field' || saved == 'Hybrid') {
      setState(() => mode = saved);
    }
  }

  Future<void> _setMode(String value) async {
    setState(() => mode = value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_modeStorageKey, value);
  }

  /// [silent] is used by the background poll timer so it doesn't flash a
  /// full-screen loading spinner every 30 seconds — only the first load
  /// and manual pull-to-refresh show that.
  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final results = await Future.wait([
        HrmsTrackingApi.live(),
        HrmsTrackingApi.trackingSettings(),
      ]);
      final data = results[0];
      final settings = results[1];
      final countsJson = Map<String, dynamic>.from(
        data['counts'] as Map? ?? {},
      );
      final items = (data['items'] as List? ?? [])
          .whereType<Map>()
          .map(
            (item) => _TrackedEmployee.fromApi(Map<String, dynamic>.from(item)),
          )
          .toList();
      if (!mounted) return;
      setState(() {
        employees = items;
        counts = _TrackingCounts.fromApi(countsJson);
        loading = false;
        error = null;
        lastLoadedAt = DateTime.now();
        homeTrackingEnabled =
            settings['home_tracking_enabled'] == true ||
            settings['home_tracking_enabled'] == 1 ||
            settings['home_tracking_enabled'] == '1';
        officeLocation = _locationFromSettings(settings);
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        loading = false;
        if (!silent) {
          error = err.toString().replaceFirst('Exception: ', '');
        }
      });
    }
  }

  List<_TrackedEmployee> get _visibleEmployees =>
      employees.where((employee) => employee.mode == mode).toList();

  LatLng? _locationFromSettings(Map<String, dynamic> settings) {
    final latitude = double.tryParse('${settings['office_latitude'] ?? ''}');
    final longitude = double.tryParse('${settings['office_longitude'] ?? ''}');
    if (latitude == null || longitude == null) return null;
    return LatLng(latitude, longitude);
  }

  void _viewRoute(_TrackedEmployee employee) {
    if (employee.mode == 'Office') {
      setState(() {
        selectedEmployee = null;
        officeFocusRequest += 1;
      });
      return;
    }
    setState(() => selectedEmployee = employee);
  }

  Future<void> _openEmployeeDetails(_TrackedEmployee employee) async {
    if (employee.mode == 'Office') {
      _viewRoute(employee);
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EmployeeTrackingDetailsDialog(employee: employee),
    );
  }

  void _viewActivity(_TrackedEmployee employee) {
    showDialog<void>(
      context: context,
      builder: (_) => _RouteActivityDialog(employee: employee),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      bottomNavigationBar: mobile
          ? const AdminMobileBottomNav(activeRoute: '/admin/tracking')
          : null,
      body: Column(
        children: [
          const AdminTopNav(activeRoute: '/admin/tracking'),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  mobile ? 16 : 29,
                  18,
                  mobile ? 16 : 29,
                  28,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1580),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _TrackingHeader(
                          onRefresh: _load,
                          onViewReasons: _openFieldWaitingReasons,
                          onHomeApprovals: _openHomeApprovals,
                          homeTrackingEnabled: homeTrackingEnabled,
                        ),
                        const SizedBox(height: 14),
                        if (loading && employees.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 80),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (error != null && employees.isEmpty)
                          _TrackingErrorState(message: error!, onRetry: _load)
                        else ...[
                          _TrackingKpis(counts: counts),
                          if (mobile) ...[
                            const SizedBox(height: 16),
                            _TrackingMobileActions(
                              onHomeApprovals: _openHomeApprovals,
                              homeTrackingEnabled: homeTrackingEnabled,
                              onRefresh: _load,
                            ),
                          ],
                          const SizedBox(height: 20),
                          _TrackingWorkspace(
                            mode: mode,
                            employees: _visibleEmployees,
                            lastLoadedAt: lastLoadedAt,
                            onModeChanged: (value) => _setMode(value),
                            onViewRoute: _viewRoute,
                            onOpenEmployee: _openEmployeeDetails,
                            onViewActivity: _viewActivity,
                            selectedEmployee: selectedEmployee,
                            officeLocation: officeLocation,
                            officeFocusRequest: officeFocusRequest,
                          ),
                        ],
                      ],
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

class _TrackingMobileActions extends StatelessWidget {
  const _TrackingMobileActions({
    required this.onHomeApprovals,
    required this.onRefresh,
    required this.homeTrackingEnabled,
  });
  final VoidCallback onHomeApprovals;
  final Future<void> Function() onRefresh;
  final bool homeTrackingEnabled;

  @override
  Widget build(BuildContext context) => Container(
    height: 72,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFC9D9F3)),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        if (homeTrackingEnabled)
          _tool(Icons.home_work_outlined, 'Home', onHomeApprovals),
        _tool(Icons.refresh, 'Refresh', () => onRefresh()),
      ],
    ),
  );

  Widget _tool(IconData icon, String label, VoidCallback onTap) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: HrmsColors.blue, size: 22),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: HrmsColors.navy,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class _TrackingHeader extends StatelessWidget {
  const _TrackingHeader({
    required this.onRefresh,
    required this.onViewReasons,
    required this.onHomeApprovals,
    required this.homeTrackingEnabled,
  });

  final Future<void> Function() onRefresh;
  final VoidCallback onViewReasons;
  final VoidCallback onHomeApprovals;
  final bool homeTrackingEnabled;

  @override
  Widget build(BuildContext context) => AdminPageHeader(
    title: 'Employee Tracking',
    breadcrumb: 'Tracking',
    trailing: Wrap(
      spacing: 4,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (homeTrackingEnabled)
          OutlinedButton.icon(
            onPressed: onHomeApprovals,
            icon: const Icon(Icons.home_work_outlined, size: 18),
            label: const Text('Home Approvals'),
            style: OutlinedButton.styleFrom(
              foregroundColor: HrmsColors.blue,
              side: const BorderSide(color: Color(0xFFBFD4FF)),
            ),
          ),
        IconButton(
          tooltip: 'Waiting Reasons',
          onPressed: onViewReasons,
          icon: const Icon(Icons.fact_check_outlined, color: HrmsColors.blue),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: () => onRefresh(),
          icon: const Icon(Icons.refresh, color: HrmsColors.blue),
        ),
      ],
    ),
  );
}

class _TrackingErrorState extends StatelessWidget {
  const _TrackingErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFE3E7EF)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      children: [
        const Icon(Icons.wifi_off_rounded, color: Color(0xFF657087), size: 34),
        const SizedBox(height: 12),
        Text(
          'Could not load tracking data',
          style: const TextStyle(
            color: HrmsColors.navy,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF657087), fontSize: 12),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () => onRetry(),
          style: ElevatedButton.styleFrom(backgroundColor: HrmsColors.blue),
          child: const Text('Retry'),
        ),
      ],
    ),
  );
}

class _TrackingCounts {
  const _TrackingCounts({
    required this.office,
    required this.home,
    required this.field,
    required this.activeNow,
  });
  final int office, home, field, activeNow;

  factory _TrackingCounts.fromApi(Map<String, dynamic> json) => _TrackingCounts(
    office: _asInt(json['office']),
    home: _asInt(json['home']),
    field: _asInt(json['field']),
    activeNow: _asInt(json['activeNow']),
  );

  static int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }
}

class _TrackingKpis extends StatelessWidget {
  const _TrackingKpis({required this.counts});
  final _TrackingCounts counts;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _TrackingKpi(
        'Office',
        '${counts.office}',
        'Tracked employees',
        Icons.apartment_outlined,
        HrmsColors.blue,
      ),
      _TrackingKpi(
        'Home',
        '${counts.home}',
        'Tracked employees',
        Icons.home_outlined,
        const Color(0xFF138A20),
      ),
      _TrackingKpi(
        'Field',
        '${counts.field}',
        'Tracked employees',
        Icons.hiking_outlined,
        const Color(0xFFFF6500),
      ),
      _TrackingKpi(
        'Active Now',
        '${counts.activeNow}',
        'Employees active',
        Icons.wifi_rounded,
        const Color(0xFF138A20),
      ),
    ];
    return LayoutBuilder(
      builder: (_, constraints) {
        final columns = constraints.maxWidth < 650
            ? 2
            : constraints.maxWidth < 1100
            ? 2
            : 4;
        final spacing = constraints.maxWidth < 650 ? 12.0 : 20.0;
        final width =
            (constraints.maxWidth - (columns - 1) * spacing) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: constraints.maxWidth < 650 ? 12 : 16,
          children: cards
              .map((card) => SizedBox(width: width, child: card))
              .toList(),
        );
      },
    );
  }
}

class _TrackingKpi extends StatelessWidget {
  const _TrackingKpi(
    this.label,
    this.value,
    this.caption,
    this.icon,
    this.color,
  );
  final String label, value, caption;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = AdminSurfacePalette.of(context);
    return LayoutBuilder(
    builder: (_, constraints) {
      final compact = constraints.maxWidth < 220;
      return Container(
        height: 116,
        padding: EdgeInsets.fromLTRB(
          compact ? 12 : 16,
          14,
          compact ? 12 : 16,
          9,
        ),
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08071A72),
              blurRadius: 14,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 39,
                        height: 39,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(icon, color: color, size: 23),
                      ),
                      const Spacer(),
                      Text(
                        value,
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    label,
                    style: TextStyle(
                      color: palette.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    caption,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.mutedText,
                      fontSize: 9,
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: .09),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: color, size: 29),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                color: palette.text,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              value,
                              style: TextStyle(
                                color: palette.text,
                                fontSize: 27,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              caption,
                              style: TextStyle(
                                color: palette.mutedText,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 55,
                      height: 3,
                      decoration: BoxDecoration(
                        color: HrmsColors.blue,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
      );
    },
  );
  }
}

class _TrackingWorkspace extends StatelessWidget {
  const _TrackingWorkspace({
    required this.mode,
    required this.employees,
    required this.lastLoadedAt,
    required this.onModeChanged,
    required this.onViewRoute,
    required this.onOpenEmployee,
    required this.onViewActivity,
    required this.selectedEmployee,
    required this.officeLocation,
    required this.officeFocusRequest,
  });
  final String mode;
  final List<_TrackedEmployee> employees;
  final DateTime? lastLoadedAt;
  final ValueChanged<String> onModeChanged;
  final ValueChanged<_TrackedEmployee> onViewRoute;
  final ValueChanged<_TrackedEmployee> onOpenEmployee;
  final ValueChanged<_TrackedEmployee> onViewActivity;
  final _TrackedEmployee? selectedEmployee;
  final LatLng? officeLocation;
  final int officeFocusRequest;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AdminSurfacePalette.of(context).surface,
      border: Border.all(color: AdminSurfacePalette.of(context).border),
      borderRadius: BorderRadius.circular(14),
      boxShadow: const [
        BoxShadow(
          color: Color(0x08071A72),
          blurRadius: 15,
          offset: Offset(0, 6),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: LayoutBuilder(
      builder: (_, constraints) {
        final stacked = constraints.maxWidth < 1050;
        final map = _MapPanel(
          mode: mode,
          employees: employees,
          onModeChanged: onModeChanged,
          onViewRoute: onViewRoute,
          selectedEmployee: selectedEmployee,
          officeLocation: officeLocation,
          officeFocusRequest: officeFocusRequest,
          fillHeight: !stacked,
        );
        final table = _TrackedEmployeesPanel(
          mode: mode,
          employees: employees,
          lastLoadedAt: lastLoadedAt,
          onViewRoute: onViewRoute,
          onOpenEmployee: onOpenEmployee,
          onViewActivity: onViewActivity,
        );
        if (stacked) {
          return Column(
            children: [
              map,
              const Divider(height: 1, color: Color(0xFFE3E7EF)),
              table,
            ],
          );
        }
        return SizedBox(
          height: 615,
          child: Row(
            children: [
              Expanded(flex: 10, child: table),
              const VerticalDivider(width: 1, color: Color(0xFFE3E7EF)),
              Expanded(flex: 11, child: map),
            ],
          ),
        );
      },
    ),
  );
}

class _MapPanel extends StatelessWidget {
  const _MapPanel({
    required this.mode,
    required this.employees,
    required this.onModeChanged,
    required this.onViewRoute,
    required this.selectedEmployee,
    required this.officeLocation,
    required this.officeFocusRequest,
    this.fillHeight = false,
  });
  final String mode;
  final List<_TrackedEmployee> employees;
  final ValueChanged<String> onModeChanged;
  final ValueChanged<_TrackedEmployee> onViewRoute;
  final _TrackedEmployee? selectedEmployee;
  final LatLng? officeLocation;
  final int officeFocusRequest;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(17, 16, 17, 18),
    child: Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Row(
              children: [
                for (final item in ['Office', 'Field']) ...[
                  if (item != 'Office') const SizedBox(width: 10),
                  Expanded(
                    child: _ModeButton(
                      label: item,
                      active: mode == item,
                      onTap: () => onModeChanged(item),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 15),
        if (fillHeight)
          Expanded(child: _map)
        else
          AspectRatio(aspectRatio: 1.44, child: _map),
      ],
    ),
  );

  Widget get _map => selectedEmployee == null
      ? _LiveMap(
          employees: employees,
          onViewRoute: onViewRoute,
          officeLocation: officeLocation,
          officeFocusRequest: officeFocusRequest,
        )
      : _SelectedRouteMap(employee: selectedEmployee!);
}

class _RouteActivityDialog extends StatefulWidget {
  const _RouteActivityDialog({required this.employee});
  final _TrackedEmployee employee;

  @override
  State<_RouteActivityDialog> createState() => _RouteActivityDialogState();
}

class _RouteActivityDialogState extends State<_RouteActivityDialog> {
  bool _loading = true;
  String? _error;
  List<_RoutePoint> _points = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.employee.employeeUserId;
    if (id == null) return;
    try {
      final data = await HrmsTrackingApi.route(
        employeeUserId: id,
        date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
      );
      final items = (data['points'] as List? ?? [])
          .whereType<Map>()
          .map((item) => _RoutePoint.fromApi(Map<String, dynamic>.from(item)))
          .toList();
      if (mounted)
        setState(() {
          _points = items;
          _loading = false;
        });
    } catch (error) {
      if (mounted)
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: SizedBox(
      width: 520,
      height: 410,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.employee.name} — Today\'s Activity',
                    style: const TextStyle(
                      color: HrmsColors.navy,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(
              _loading
                  ? 'Loading saved GPS activity…'
                  : '${_points.length} location update(s) today',
              style: const TextStyle(color: Color(0xFF657087), fontSize: 12),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F7FC),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  SizedBox(
                    width: 74,
                    child: Text(
                      'TIME',
                      style: TextStyle(
                        color: Color(0xFF657087),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'PLACE',
                      style: TextStyle(
                        color: Color(0xFF657087),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    )
                  : _points.isEmpty
                  ? const Center(
                      child: Text(
                        'No GPS activity recorded today.',
                        style: TextStyle(color: Color(0xFF657087)),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _points.length,
                      itemBuilder: (_, index) {
                        final point = _points[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 5),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: index.isEven
                                ? Colors.white
                                : const Color(0xFFFBFCFE),
                            border: Border.all(color: const Color(0xFFE8ECF3)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                color: Color(0xFF00A878),
                                size: 17,
                              ),
                              const SizedBox(width: 7),
                              SizedBox(
                                width: 58,
                                child: Text(
                                  point.time,
                                  style: const TextStyle(
                                    color: HrmsColors.navy,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  point.location,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF596176),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SelectedRouteMap extends StatefulWidget {
  const _SelectedRouteMap({required this.employee});
  final _TrackedEmployee employee;

  @override
  State<_SelectedRouteMap> createState() => _SelectedRouteMapState();
}

class _SelectedRouteMapState extends State<_SelectedRouteMap> {
  DateTime _date = DateTime.now();
  bool _loading = true;
  String? _error;
  List<_RoutePoint> _points = const [];
  bool _roadSnapped = false;
  BitmapDescriptor? _startMarker, _endMarker;

  List<LatLng> get _coordinates => _points
      .where((point) => point.latitude != null && point.longitude != null)
      .map((point) => LatLng(point.latitude!, point.longitude!))
      .toList();

  @override
  void initState() {
    super.initState();
    _load();
    _loadMarkerIcons();
  }

  Future<void> _loadMarkerIcons() async {
    final icons = await Future.wait([
      _adminRouteMarkerIcon(HrmsColors.blue, 'S'),
      _adminRouteMarkerIcon(const Color(0xFF7E20E8), 'E'),
    ]);
    if (mounted)
      setState(() {
        _startMarker = icons[0];
        _endMarker = icons[1];
      });
  }

  @override
  void didUpdateWidget(covariant _SelectedRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.employee.employeeUserId != widget.employee.employeeUserId)
      _load();
  }

  Future<void> _load() async {
    final id = widget.employee.employeeUserId;
    if (id == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await HrmsTrackingApi.route(
        employeeUserId: id,
        date: DateFormat('yyyy-MM-dd').format(_date),
      );
      final points = (data['points'] as List? ?? [])
          .whereType<Map>()
          .map((item) => _RoutePoint.fromApi(Map<String, dynamic>.from(item)))
          .toList();
      if (mounted)
        setState(() {
          _points = points;
          _roadSnapped = data['roadSnapped'] == true;
          _loading = false;
        });
    } catch (error) {
      if (mounted)
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
    }
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (value == null || !mounted) return;
    setState(() => _date = value);
    await _load();
  }

  double _distanceKm(List<LatLng> route) {
    var meters = 0.0;
    for (var index = 1; index < route.length; index++) {
      final a = route[index - 1];
      final b = route[index];
      const radius = 6371000.0;
      final latitudeDelta = (b.latitude - a.latitude) * pi / 180;
      final longitudeDelta = (b.longitude - a.longitude) * pi / 180;
      final latitudeA = a.latitude * pi / 180;
      final latitudeB = b.latitude * pi / 180;
      final h =
          sin(latitudeDelta / 2) * sin(latitudeDelta / 2) +
          cos(latitudeA) *
              cos(latitudeB) *
              sin(longitudeDelta / 2) *
              sin(longitudeDelta / 2);
      meters += radius * 2 * atan2(sqrt(h), sqrt(1 - h));
    }
    return meters / 1000;
  }

  Duration get _routeDuration {
    if (_points.length < 2) return Duration.zero;
    final first = DateTime.tryParse(_points.first.recordedAt ?? '');
    final last = DateTime.tryParse(_points.last.recordedAt ?? '');
    return first == null || last == null
        ? Duration.zero
        : last.difference(first).abs();
  }

  String _durationLabel(Duration value) =>
      '${value.inHours}h ${value.inMinutes.remainder(60).toString().padLeft(2, '0')}m';

  @override
  Widget build(BuildContext context) {
    final route = _coordinates;
    final center = route.isNotEmpty
        ? route.first
        : widget.employee.lat != null && widget.employee.lng != null
        ? LatLng(widget.employee.lat!, widget.employee.lng!)
        : const LatLng(28.6139, 77.2090);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.employee.name,
                style: const TextStyle(
                  color: HrmsColors.navy,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _loading ? null : _pickDate,
              icon: const Icon(Icons.calendar_today_outlined, size: 15),
              label: Text(DateFormat('dd MMM yyyy').format(_date)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                )
              : route.isEmpty
              ? const Center(
                  child: Text(
                    'No location history for this employee on this date.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF657087), fontSize: 12),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: GoogleMap(
                          key: ValueKey(
                            '${widget.employee.employeeUserId}-${_date.toIso8601String()}-${route.length}',
                          ),
                          initialCameraPosition: CameraPosition(
                            target: center,
                            zoom: 15,
                          ),
                          mapToolbarEnabled: false,
                          polylines: _roadSnapped
                              ? {
                                  Polyline(
                                    polylineId: const PolylineId(
                                      'selected-route',
                                    ),
                                    points: route,
                                    color: HrmsColors.blue,
                                    width: 5,
                                  ),
                                }
                              : const {},
                          markers: {
                            Marker(
                              markerId: const MarkerId('route-start'),
                              position: route.first,
                              icon:
                                  _startMarker ??
                                  BitmapDescriptor.defaultMarker,
                              infoWindow: const InfoWindow(
                                title: 'Start point',
                              ),
                            ),
                            if (route.length > 1)
                              Marker(
                                markerId: const MarkerId('route-end'),
                                position: route.last,
                                icon:
                                    _endMarker ??
                                    BitmapDescriptor.defaultMarker,
                                infoWindow: const InfoWindow(
                                  title: 'End point',
                                ),
                              ),
                          },
                          circles: {
                            for (
                              var index = 1;
                              index < route.length - 1;
                              index++
                            )
                              Circle(
                                circleId: CircleId('route-ping-$index'),
                                center: route[index],
                                radius: 1.5,
                                fillColor: const Color(0xFF00A878),
                                strokeColor: Colors.white,
                                strokeWidth: 1,
                              ),
                          },
                        ),
                      ),
                    ),
                    if (!_roadSnapped)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Road route is temporarily unavailable. Showing GPS points only.',
                          style: TextStyle(
                            color: Color(0xFF9B6200),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    const SizedBox(height: 9),
                    _RouteMetrics(
                      distance: _roadSnapped
                          ? '${_distanceKm(route).toStringAsFixed(2)} km'
                          : '--',
                      duration: _durationLabel(_routeDuration),
                      speed: !_roadSnapped || _routeDuration.inMinutes == 0
                          ? '--'
                          : '${(_distanceKm(route) / (_routeDuration.inMinutes / 60)).toStringAsFixed(1)} km/h',
                      updated: widget.employee.updatedLabel,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Google Maps display for the live employee markers. Only employees with
/// at least one GPS ping recorded are shown as pins — an employee who has
/// only set a status but never sent a location has nothing to plot yet.
class _LiveMap extends StatefulWidget {
  const _LiveMap({
    required this.employees,
    required this.onViewRoute,
    required this.officeLocation,
    required this.officeFocusRequest,
  });
  final List<_TrackedEmployee> employees;
  final ValueChanged<_TrackedEmployee> onViewRoute;
  final LatLng? officeLocation;
  final int officeFocusRequest;

  @override
  State<_LiveMap> createState() => _LiveMapState();
}

class _LiveMapState extends State<_LiveMap> {
  GoogleMapController? _controller;

  static const _delhiCenter = LatLng(28.6139, 77.2090);

  @override
  void didUpdateWidget(covariant _LiveMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.officeFocusRequest != widget.officeFocusRequest) {
      _focusOffice();
    }
  }

  Future<void> _focusOffice() async {
    final office = widget.officeLocation;
    final controller = _controller;
    if (office == null || controller == null) return;
    await controller.animateCamera(CameraUpdate.newLatLngZoom(office, 17));
  }

  @override
  Widget build(BuildContext context) {
    final located = widget.employees
        .where((e) => e.lat != null && e.lng != null)
        .toList();
    final center =
        widget.officeLocation ??
        (located.isNotEmpty
            ? LatLng(located.first.lat!, located.first.lng!)
            : _delhiCenter);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: GoogleMap(
        initialCameraPosition: CameraPosition(target: center, zoom: 11),
        mapToolbarEnabled: false,
        onMapCreated: (controller) {
          _controller = controller;
          _focusOffice();
        },
        markers: located
            .map(
              (employee) => Marker(
                markerId: MarkerId(employee.id),
                position: LatLng(employee.lat!, employee.lng!),
                infoWindow: InfoWindow(
                  title: employee.name,
                  snippet:
                      employee.address ?? 'Location not yet reverse-geocoded',
                ),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  _markerHue(employee.mode),
                ),
                onTap: () => widget.onViewRoute(employee),
              ),
            )
            .toSet(),
      ),
    );
  }

  double _markerHue(String mode) => switch (mode) {
    'Office' => BitmapDescriptor.hueAzure,
    'Hybrid' => BitmapDescriptor.hueViolet,
    _ => BitmapDescriptor.hueOrange,
  };
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(22),
    child: Container(
      width: double.infinity,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? HrmsColors.blue : AdminSurfacePalette.of(context).subtleSurface,
        border: Border.all(
          color: active ? HrmsColors.blue : AdminSurfacePalette.of(context).border,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? Colors.white : AdminSurfacePalette.of(context).text,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _TrackedEmployeesPanel extends StatelessWidget {
  const _TrackedEmployeesPanel({
    required this.mode,
    required this.employees,
    required this.lastLoadedAt,
    required this.onViewRoute,
    required this.onOpenEmployee,
    required this.onViewActivity,
  });
  final String mode;
  final List<_TrackedEmployee> employees;
  final DateTime? lastLoadedAt;
  final ValueChanged<_TrackedEmployee> onViewRoute;
  final ValueChanged<_TrackedEmployee> onOpenEmployee;
  final ValueChanged<_TrackedEmployee> onViewActivity;

  String get _updatedLabel {
    if (lastLoadedAt == null) return 'Updating…';
    final seconds = DateTime.now().difference(lastLoadedAt!).inSeconds;
    if (seconds < 5) return 'Updated just now';
    if (seconds < 60) return 'Updated ${seconds}s ago';
    final minutes = (seconds / 60).floor();
    return 'Updated ${minutes}m ago';
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '$mode Employees',
              style: TextStyle(
                color: AdminSurfacePalette.of(context).text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF138A20),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _updatedLabel,
              style: TextStyle(color: AdminSurfacePalette.of(context).mutedText, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (employees.isEmpty)
          const _EmptyTrackedState()
        else if (MediaQuery.sizeOf(context).width < 600)
          _MobileTrackedList(
            employees: employees,
            onViewRoute: onViewRoute,
            onOpenEmployee: onOpenEmployee,
          )
        else
          SizedBox(
            height: 510,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AdminSurfacePalette.of(context).border),
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: 670,
                    child: Column(
                      children: [
                        const _TrackingTableHeader(),
                        ...employees.map(
                          (employee) => _TrackingRow(
                            employee: employee,
                            onViewRoute: onViewRoute,
                            onOpenEmployee: onOpenEmployee,
                            onViewActivity: onViewActivity,
                          ),
                        ),
                      ],
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

class _EmptyTrackedState extends StatelessWidget {
  const _EmptyTrackedState();
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 40),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFFE2E6ED)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Column(
      children: [
        Icon(Icons.location_off_outlined, color: Color(0xFF9AA3B2), size: 28),
        SizedBox(height: 8),
        Text(
          'No employees in this status right now',
          style: TextStyle(color: Color(0xFF657087), fontSize: 12),
        ),
      ],
    ),
  );
}

class _MobileTrackedList extends StatelessWidget {
  const _MobileTrackedList({
    required this.employees,
    required this.onViewRoute,
    required this.onOpenEmployee,
  });
  final List<_TrackedEmployee> employees;
  final ValueChanged<_TrackedEmployee> onViewRoute;
  final ValueChanged<_TrackedEmployee> onOpenEmployee;

  @override
  Widget build(BuildContext context) => Column(
    children: employees
        .map(
          (employee) => Container(
            margin: const EdgeInsets.only(bottom: 9),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFBFCFF),
              border: Border.all(color: const Color(0xFFE5EAF3)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFFEAF1FF),
                  child: Text(
                    employee.name.isNotEmpty
                        ? employee.name.substring(0, 1)
                        : '?',
                    style: const TextStyle(
                      color: HrmsColors.blue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => onOpenEmployee(employee),
                              child: Text(
                                employee.name,
                                style: const TextStyle(
                                  color: HrmsColors.navy,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          _ActiveBadge(active: employee.active),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: HrmsColors.blue,
                            size: 14,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              employee.address ?? 'No location yet',
                              style: const TextStyle(
                                color: Color(0xFF657087),
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => onViewRoute(employee),
                  icon: const Icon(
                    Icons.map_outlined,
                    color: HrmsColors.blue,
                    size: 23,
                  ),
                ),
              ],
            ),
          ),
        )
        .toList(),
  );
}

class _TrackingTableHeader extends StatelessWidget {
  const _TrackingTableHeader();
  @override
  Widget build(BuildContext context) => Container(
    height: 42,
    color: AdminSurfacePalette.of(context).subtleSurface,
    child: Row(
      children: [
        _TrackingCell(width: 220, child: Text('Employee', style: TextStyle(color: AdminSurfacePalette.of(context).text, fontSize: 12, fontWeight: FontWeight.w700))),
        _TrackingCell(
          width: 220,
          child: Text('Current Location', style: TextStyle(color: AdminSurfacePalette.of(context).text, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
        _TrackingCell(width: 110, child: Text('Status', style: TextStyle(color: AdminSurfacePalette.of(context).text, fontSize: 12, fontWeight: FontWeight.w700))),
        _TrackingCell(width: 120, child: Text('Actions', style: TextStyle(color: AdminSurfacePalette.of(context).text, fontSize: 12, fontWeight: FontWeight.w700))),
      ],
    ),
  );
}

class _TrackingRow extends StatelessWidget {
  const _TrackingRow({
    required this.employee,
    required this.onViewRoute,
    required this.onOpenEmployee,
    required this.onViewActivity,
  });
  final _TrackedEmployee employee;
  final ValueChanged<_TrackedEmployee> onViewRoute;
  final ValueChanged<_TrackedEmployee> onOpenEmployee;
  final ValueChanged<_TrackedEmployee> onViewActivity;

  @override
  Widget build(BuildContext context) => Container(
    height: 59,
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Color(0xFFE5E8EF))),
    ),
    child: Row(
      children: [
        _TrackingCell(
          width: 220,
          child: Row(
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: const Color(0xFFE8EEF8),
                child: Text(
                  employee.name.isNotEmpty
                      ? employee.name.substring(0, 1)
                      : '?',
                  style: const TextStyle(
                    color: HrmsColors.navy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () => onOpenEmployee(employee),
                    child: Text(
                      employee.name,
                      style: const TextStyle(
                        color: HrmsColors.blue,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    employee.id,
                    style: const TextStyle(
                      color: Color(0xFF657087),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _TrackingCell(
          width: 220,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.location_on,
                  color: HrmsColors.blue,
                  size: 15,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.address ?? 'No location yet',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF303747),
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      employee.updatedLabel,
                      style: const TextStyle(
                        color: Color(0xFF657087),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _TrackingCell(width: 110, child: _ActiveBadge(active: employee.active)),
        _TrackingCell(
          width: 120,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Show route on map',
                onPressed: () => onViewRoute(employee),
                icon: const Icon(
                  Icons.map_outlined,
                  color: HrmsColors.blue,
                  size: 22,
                ),
              ),
              IconButton(
                tooltip: 'View today\'s activity',
                onPressed: () => onViewActivity(employee),
                icon: const Icon(
                  Icons.history_outlined,
                  color: Color(0xFF00A878),
                  size: 21,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _TrackingCell extends StatelessWidget {
  const _TrackingCell({required this.width, required this.child});
  final double width;
  final Widget child;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: child,
    ),
  );
}

class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge({required this.active});
  final bool active;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
    decoration: BoxDecoration(
      color: active ? const Color(0xFFEAF6E6) : const Color(0xFFF1F2F5),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      active ? 'Active' : 'Inactive',
      style: TextStyle(
        color: active ? const Color(0xFF177020) : const Color(0xFF657087),
        fontSize: 11,
      ),
    ),
  );
}

/// One employee row for the admin tracking dashboard, built entirely from
/// `GET /api/hrms/tracking/live`. `mode` is normalized to 'Office' / 'Home'
/// / 'Field' (title case) to match the tab labels in this UI; the backend
/// itself stores it lowercase.
class _TrackedEmployee {
  const _TrackedEmployee({
    required this.employeeUserId,
    required this.name,
    required this.id,
    required this.mode,
    required this.active,
    this.lat,
    this.lng,
    this.address,
    this.lastUpdated,
  });

  final int? employeeUserId;
  final String name, id, mode;
  final bool active;
  final double? lat, lng;
  final String? address;
  final DateTime? lastUpdated;

  factory _TrackedEmployee.fromApi(Map<String, dynamic> json) {
    final rawStatus = (json['status'] ?? 'office').toString();
    final mode = rawStatus.isEmpty
        ? 'Office'
        : rawStatus[0].toUpperCase() + rawStatus.substring(1).toLowerCase();
    final rawUpdated = json['lastUpdated'];
    final lastUpdated = rawUpdated != null
        ? DateTime.tryParse(rawUpdated.toString())
        : null;
    return _TrackedEmployee(
      employeeUserId: json['employeeUserId'] is int
          ? json['employeeUserId'] as int
          : int.tryParse('${json['employeeUserId']}'),
      name: (json['name'] ?? '').toString(),
      id: (json['employeeCode'] ?? '').toString(),
      mode: mode,
      active: json['active'] == true,
      lat: (json['latitude'] as num?)?.toDouble(),
      lng: (json['longitude'] as num?)?.toDouble(),
      address: (json['address'] as String?)?.trim().isEmpty == true
          ? null
          : json['address'] as String?,
      lastUpdated: lastUpdated,
    );
  }

  String get updatedLabel {
    if (lastUpdated == null) return 'No pings yet';
    final minutes = DateTime.now().difference(lastUpdated!).inMinutes;
    if (minutes < 1) return 'Updated just now';
    if (minutes < 60) return 'Updated ${minutes}m ago';
    final hours = (minutes / 60).floor();
    return 'Updated ${hours}h ago';
  }
}

class _RoutePoint {
  const _RoutePoint({
    required this.time,
    required this.location,
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
  });
  final String time, location;
  final double? latitude, longitude;
  final String? recordedAt;

  factory _RoutePoint.fromApi(Map<String, dynamic> json) {
    final rawTime = json['recordedAt']?.toString();
    final recorded = rawTime != null ? DateTime.tryParse(rawTime) : null;
    final time = recorded != null
        ? DateFormat('hh:mm a').format(recorded.toLocal())
        : '--:--';
    final address = (json['address'] as String?)?.trim();
    final location = (address != null && address.isNotEmpty)
        ? address
        : 'Location name unavailable';
    return _RoutePoint(
      time: time,
      location: location,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      recordedAt: rawTime,
    );
  }
}

class _RouteStatusChip extends StatelessWidget {
  const _RouteStatusChip({required this.label, required this.active});
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: active ? const Color(0xFFE4F8F0) : const Color(0xFFF0F2F5),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.circle,
          size: 9,
          color: active ? const Color(0xFF00A878) : const Color(0xFF7A8494),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: HrmsColors.navy,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _RouteMetrics extends StatelessWidget {
  const _RouteMetrics({
    required this.distance,
    required this.duration,
    required this.speed,
    required this.updated,
  });
  final String distance, duration, speed, updated;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
    decoration: BoxDecoration(
      color: const Color(0xFFF7FAFF),
      border: Border.all(color: const Color(0xFFE0E8F5)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Expanded(child: _metric(Icons.route_outlined, 'Distance', distance)),
        Expanded(child: _metric(Icons.timer_outlined, 'Duration', duration)),
        Expanded(child: _metric(Icons.speed_outlined, 'Avg speed', speed)),
        Expanded(child: _metric(Icons.update_outlined, 'Updated', updated)),
      ],
    ),
  );

  Widget _metric(IconData icon, String label, String value) => Row(
    children: [
      Icon(icon, color: const Color(0xFF00A878), size: 20),
      const SizedBox(width: 6),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Color(0xFF657087), fontSize: 10),
            ),
            Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: HrmsColors.navy,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _EmployeeTrackingDetailsDialog extends StatefulWidget {
  const _EmployeeTrackingDetailsDialog({required this.employee});
  final _TrackedEmployee employee;

  @override
  State<_EmployeeTrackingDetailsDialog> createState() =>
      _EmployeeTrackingDetailsDialogState();
}

class _EmployeeTrackingDetailsDialogState
    extends State<_EmployeeTrackingDetailsDialog> {
  DateTime _selectedDate = DateTime.now();
  bool _loading = true;
  String? _error;
  int _tab = 0;
  List<_RoutePoint> _mapPoints = const [];
  List<LatLng> _routePoints = const [];
  double? _cachedDistanceKm;
  List<_RoutePoint> _activityPoints = const [];
  bool _roadSnapped = false;
  bool _invalidated = false;
  bool _invalidating = false;
  String? _invalidationReason;
  List<Map<String, dynamic>> _waitingReasons = const [];
  List<Map<String, dynamic>> _comments = const [];

  List<LatLng> get _route => _routePoints;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final employeeUserId = widget.employee.employeeUserId;
    if (employeeUserId == null) {
      setState(() {
        _loading = false;
        _error = 'No employee ID is available for this employee.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await HrmsTrackingApi.employeeTrackingDetails(
        employeeUserId: employeeUserId,
        date: DateFormat('yyyy-MM-dd').format(_selectedDate),
      );
      List<_RoutePoint> pointsFor(String key) => (data[key] as List? ?? [])
          .whereType<Map>()
          .map((item) => _RoutePoint.fromApi(Map<String, dynamic>.from(item)))
          .toList();
      List<Map<String, dynamic>> entriesFor(String key) =>
          (data[key] as List? ?? [])
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
      if (!mounted) return;
      final mapPoints = pointsFor('points');
      final routePoints = mapPoints
          .where((point) => point.latitude != null && point.longitude != null)
          .map((point) => LatLng(point.latitude!, point.longitude!))
          .toList(growable: false);
      setState(() {
        _mapPoints = mapPoints;
        _routePoints = routePoints;
        _cachedDistanceKm = null;
        _activityPoints = pointsFor('activityPoints');
        _roadSnapped = data['roadSnapped'] == true;
        _invalidated = data['invalidated'] == true;
        _invalidationReason = data['invalidationReason']?.toString();
        _waitingReasons = entriesFor('waitingReasons');
        _comments = entriesFor('comments');
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedDate = picked);
    await _load();
  }

  Future<void> _shiftDate(int days) async {
    final value = _selectedDate.add(Duration(days: days));
    if (value.isAfter(DateTime.now())) return;
    setState(() => _selectedDate = value);
    await _load();
  }

  Future<void> _invalidateSelectedRoute() async {
    final employeeUserId = widget.employee.employeeUserId;
    if (employeeUserId == null || _invalidating) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Invalidate this route?'),
        content: const Text('This hides the selected day from route views. The original GPS pings remain available for audit.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Invalidate route')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _invalidating = true);
    try {
      await HrmsTrackingApi.invalidateRoute(
        employeeUserId: employeeUserId,
        date: DateFormat('yyyy-MM-dd').format(_selectedDate),
        reason: 'Invalidated by administrator after route review.',
      );
      if (!mounted) return;
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Route invalidated. Original GPS data was retained for audit.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _invalidating = false);
    }
  }

  double get _distanceKm {
    if (_cachedDistanceKm != null) return _cachedDistanceKm!;
    var metres = 0.0;
    for (var index = 1; index < _route.length; index++) {
      final a = _route[index - 1];
      final b = _route[index];
      const radius = 6371000.0;
      final dLat = (b.latitude - a.latitude) * pi / 180;
      final dLng = (b.longitude - a.longitude) * pi / 180;
      final latA = a.latitude * pi / 180;
      final latB = b.latitude * pi / 180;
      final h =
          sin(dLat / 2) * sin(dLat / 2) +
          cos(latA) * cos(latB) * sin(dLng / 2) * sin(dLng / 2);
      metres += radius * 2 * atan2(sqrt(h), sqrt(1 - h));
    }
    _cachedDistanceKm = metres / 1000;
    return _cachedDistanceKm!;
  }

  Duration get _duration {
    if (_activityPoints.length < 2) return Duration.zero;
    final first = DateTime.tryParse(_activityPoints.first.recordedAt ?? '');
    final last = DateTime.tryParse(_activityPoints.last.recordedAt ?? '');
    if (first == null || last == null) return Duration.zero;
    return last.difference(first).abs();
  }

  String get _durationLabel =>
      '${_duration.inHours}h ${_duration.inMinutes.remainder(60).toString().padLeft(2, '0')}m';

  String _time(dynamic value) {
    final date = DateTime.tryParse('${value ?? ''}');
    return date == null ? '—' : DateFormat('hh:mm a').format(date.toLocal());
  }

  String _location(Map<String, dynamic> item) {
    final address = '${item['address'] ?? ''}'.trim();
    if (address.isNotEmpty) return address;
    final latitude = item['latitude'];
    final longitude = item['longitude'];
    return latitude == null || longitude == null
        ? 'Location not available'
        : '$latitude, $longitude';
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 760),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
        child: Column(
          children: [
            _header(),
            const SizedBox(height: 16),
            Expanded(child: _body()),
          ],
        ),
      ),
    ),
  );

  Widget _header() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CircleAvatar(
        radius: 24,
        backgroundColor: const Color(0xFFE9F0FF),
        child: Text(
          widget.employee.name.isEmpty ? '?' : widget.employee.name[0],
          style: const TextStyle(
            color: HrmsColors.blue,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Employee Tracking Details',
              style: TextStyle(
                color: HrmsColors.navy,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            Wrap(
              spacing: 8,
              runSpacing: 5,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  widget.employee.name,
                  style: const TextStyle(
                    color: HrmsColors.navy,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                _RouteStatusChip(
                  label: widget.employee.active ? 'Live' : 'Offline',
                  active: widget.employee.active,
                ),
                Text(
                  '${widget.employee.id}  |  ${widget.employee.mode}',
                  style: const TextStyle(
                    color: Color(0xFF657087),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      IconButton(
        tooltip: 'Close',
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.close),
      ),
    ],
  );

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.red),
        ),
      );
    }
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'Previous day',
              onPressed: () => _shiftDate(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text(DateFormat('dd MMM yyyy').format(_selectedDate)),
            ),
            IconButton(
              tooltip: 'Next day',
              onPressed: _selectedDate.isBefore(DateTime.now())
                  ? () => _shiftDate(1)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
            if (!_invalidated) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _loading || _invalidating ? null : _invalidateSelectedRoute,
                icon: _invalidating
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.block_outlined, size: 16),
                label: const Text('Invalidate route'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          flex: 5,
          child: LayoutBuilder(
            builder: (_, constraints) {
              final stacked = constraints.maxWidth < 720;
              final map = _routeMap();
              final summary = _summary();
              return stacked
                  ? Column(
                      children: [
                        Expanded(child: map),
                        const SizedBox(height: 10),
                        summary,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(flex: 4, child: map),
                        const SizedBox(width: 14),
                        SizedBox(width: 220, child: summary),
                      ],
                    );
            },
          ),
        ),
        const SizedBox(height: 13),
        _tabs(),
        const SizedBox(height: 8),
        Expanded(flex: 3, child: _tabContent()),
      ],
    );
  }

  Widget _routeMap() {
    if (_invalidated) {
      return Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF6F6),
          border: Border.all(color: const Color(0xFFF0B7B7)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _invalidationReason == null || _invalidationReason!.isEmpty
                ? 'This route has been invalidated and is hidden from route views.'
                : 'This route has been invalidated.\n$_invalidationReason',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF9B1C1C), fontWeight: FontWeight.w600),
          ),
        ),
      );
    }
    if (_route.isEmpty) {
      return Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FD),
          border: Border.all(color: const Color(0xFFE0E6F0)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'No route was recorded on ${DateFormat('dd MMM yyyy').format(_selectedDate)}.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF657087)),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          GoogleMap(
            key: ValueKey(
              'details-${widget.employee.employeeUserId}-${DateFormat('yyyy-MM-dd').format(_selectedDate)}',
            ),
            initialCameraPosition: CameraPosition(
              target: _route.first,
              zoom: 14,
            ),
            mapToolbarEnabled: false,
            polylines: _roadSnapped
                ? {
                    Polyline(
                      polylineId: const PolylineId('details-route'),
                      points: _route,
                      color: HrmsColors.blue,
                      width: 5,
                    ),
                  }
                : const {},
            markers: {
              Marker(
                markerId: const MarkerId('details-start'),
                position: _route.first,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen,
                ),
                infoWindow: const InfoWindow(title: 'Start'),
              ),
              if (_route.length > 1)
                Marker(
                  markerId: const MarkerId('details-end'),
                  position: _route.last,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueRed,
                  ),
                  infoWindow: const InfoWindow(title: 'End'),
                ),
            },
          ),
          if (!_roadSnapped)
            const Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Material(
                color: Color(0xFFFDF5E7),
                borderRadius: BorderRadius.all(Radius.circular(8)),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: Text(
                    'Road route is temporarily unavailable. Showing GPS points only.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF9B6200), fontSize: 11),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _summary() => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFDDE5F2)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        const Text(
          'Day Summary',
          style: TextStyle(
            color: HrmsColors.navy,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        _summaryRow(
          Icons.route_outlined,
          'Distance',
          '${_distanceKm.toStringAsFixed(2)} km',
          HrmsColors.blue,
        ),
        _summaryRow(
          Icons.schedule_outlined,
          'Active time',
          _durationLabel,
          const Color(0xFF00A878),
        ),
        _summaryRow(
          Icons.my_location_outlined,
          'Location updates',
          '${_activityPoints.length}',
          const Color(0xFF6B52D7),
        ),
        _summaryRow(
          Icons.pause_circle_outline,
          'Waiting reasons',
          '${_waitingReasons.length}',
          const Color(0xFFFF8400),
        ),
      ],
    ),
  );

  Widget _summaryRow(IconData icon, String label, String value, Color color) =>
      Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color.withValues(alpha: .10),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF657087),
                    fontSize: 11,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: HrmsColors.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _tabs() {
    const labels = [
      'Route History',
      'Waiting Popup Comments',
      'Permanent Comments',
    ];
    const icons = [
      Icons.route_outlined,
      Icons.chat_bubble_outline,
      Icons.comment_outlined,
    ];
    return Row(
      children: List.generate(
        labels.length,
        (index) => Expanded(
          child: InkWell(
            onTap: () => setState(() => _tab = index),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: _tab == index
                        ? HrmsColors.blue
                        : const Color(0xFFE0E5ED),
                    width: _tab == index ? 3 : 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icons[index],
                    size: 17,
                    color: _tab == index
                        ? HrmsColors.blue
                        : const Color(0xFF657087),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      labels[index],
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _tab == index
                            ? HrmsColors.blue
                            : const Color(0xFF657087),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
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

  Widget _tabContent() {
    if (_tab == 0) {
      return _historyList(
        _activityPoints
            .map(
              (point) => _historyRow(
                time: point.time,
                title: point == _activityPoints.first
                    ? 'Start'
                    : point == _activityPoints.last
                    ? 'End'
                    : 'Location update',
                detail: point.location,
                icon: point == _activityPoints.first
                    ? Icons.play_circle_fill
                    : point == _activityPoints.last
                    ? Icons.stop_circle
                    : Icons.location_on_outlined,
                color: point == _activityPoints.first
                    ? const Color(0xFF00A878)
                    : point == _activityPoints.last
                    ? Colors.red
                    : HrmsColors.blue,
              ),
            )
            .toList(),
        'No location updates were recorded on this date.',
      );
    }
    if (_tab == 1) {
      return _historyList(
        _waitingReasons
            .map(
              (item) => _historyRow(
                time: _time(
                  item['reason_submitted_at'] ?? item['waiting_detected_at'],
                ),
                title: 'Waiting ${item['waiting_minutes'] ?? 0} min',
                detail: '${item['reason'] ?? 'No reason submitted'}',
                icon: Icons.pause_circle_outline,
                color: const Color(0xFFFF8400),
              ),
            )
            .toList(),
        'No waiting popup comments were submitted on this date.',
      );
    }
    return _historyList(
      _comments
          .map(
            (item) => _historyRow(
              time: _time(item['createdAt']),
              title: '${item['comment'] ?? 'Comment'}',
              detail: _location(item),
              icon: Icons.comment_outlined,
              color: const Color(0xFF6B52D7),
            ),
          )
          .toList(),
      'No permanent comments were submitted on this date.',
    );
  }

  Widget _historyList(List<Widget> rows, String emptyText) => Container(
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFFE1E6EF)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: rows.isEmpty
        ? Center(
            child: Text(
              emptyText,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF657087), fontSize: 12),
            ),
          )
        : ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: Color(0xFFE9EDF3)),
            itemBuilder: (_, index) => rows[index],
          ),
  );

  Widget _historyRow({
    required String time,
    required String title,
    required String detail,
    required IconData icon,
    required Color color,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
    child: Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            time,
            style: const TextStyle(
              color: HrmsColors.navy,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: HrmsColors.navy,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF657087), fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _RouteDialog extends StatefulWidget {
  const _RouteDialog({required this.employee});
  final _TrackedEmployee employee;

  @override
  State<_RouteDialog> createState() => _RouteDialogState();
}

class _RouteDialogState extends State<_RouteDialog> {
  bool loading = true;
  String? error;
  List<_RoutePoint> points = [];
  GoogleMapController? _routeMapController;
  DateTime selectedDate = DateTime.now();
  BitmapDescriptor? _startMarker, _endMarker;

  List<LatLng> get _routeCoordinates => points
      .where((point) => point.latitude != null && point.longitude != null)
      .map((point) => LatLng(point.latitude!, point.longitude!))
      .toList();

  Future<void> _fitRoute() async {
    final controller = _routeMapController;
    final coordinates = _routeCoordinates;
    if (controller == null || coordinates.isEmpty) return;
    if (coordinates.length == 1) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(coordinates.first, 16),
      );
      return;
    }
    var south = coordinates.first.latitude;
    var north = coordinates.first.latitude;
    var west = coordinates.first.longitude;
    var east = coordinates.first.longitude;
    for (final point in coordinates.skip(1)) {
      south = point.latitude < south ? point.latitude : south;
      north = point.latitude > north ? point.latitude : north;
      west = point.longitude < west ? point.longitude : west;
      east = point.longitude > east ? point.longitude : east;
    }
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        42,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadMarkerIcons();
  }

  Future<void> _loadMarkerIcons() async {
    final icons = await Future.wait([
      _adminRouteMarkerIcon(HrmsColors.blue, 'S'),
      _adminRouteMarkerIcon(const Color(0xFF7E20E8), 'E'),
    ]);
    if (mounted)
      setState(() {
        _startMarker = icons[0];
        _endMarker = icons[1];
      });
  }

  Future<void> _load() async {
    final employeeUserId = widget.employee.employeeUserId;
    if (employeeUserId == null) {
      setState(() {
        loading = false;
        error = 'No employee ID available for this row';
      });
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await HrmsTrackingApi.route(
        employeeUserId: employeeUserId,
        date: DateFormat('yyyy-MM-dd').format(selectedDate),
      );
      final items = (data['points'] as List? ?? [])
          .whereType<Map>()
          .map((item) => _RoutePoint.fromApi(Map<String, dynamic>.from(item)))
          .toList();
      if (!mounted) return;
      setState(() {
        points = items;
        loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitRoute());
    } catch (err) {
      if (!mounted) return;
      setState(() {
        error = err.toString().replaceFirst('Exception: ', '');
        loading = false;
      });
    }
  }

  Future<void> _selectDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (selected == null || !mounted) return;
    setState(() => selectedDate = selected);
    await _load();
  }

  double _distanceKm() {
    final coordinates = _routeCoordinates;
    var meters = 0.0;
    for (var index = 1; index < coordinates.length; index++) {
      meters += _metersBetween(coordinates[index - 1], coordinates[index]);
    }
    return meters / 1000;
  }

  double _metersBetween(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    final latitudeDelta = (b.latitude - a.latitude) * 3.141592653589793 / 180;
    final longitudeDelta =
        (b.longitude - a.longitude) * 3.141592653589793 / 180;
    final latitudeA = a.latitude * 3.141592653589793 / 180;
    final latitudeB = b.latitude * 3.141592653589793 / 180;
    final h =
        (sin(latitudeDelta / 2) * sin(latitudeDelta / 2)) +
        cos(latitudeA) *
            cos(latitudeB) *
            sin(longitudeDelta / 2) *
            sin(longitudeDelta / 2);
    return earthRadius * 2 * atan2(sqrt(h), sqrt(1 - h));
  }

  Duration get _trackingDuration {
    if (points.length < 2) return Duration.zero;
    final first = DateTime.tryParse(points.first.recordedAt ?? '');
    final last = DateTime.tryParse(points.last.recordedAt ?? '');
    if (first == null || last == null) return Duration.zero;
    return last.difference(first).abs();
  }

  String _durationLabel(Duration duration) =>
      '${duration.inHours}h ${duration.inMinutes.remainder(60).toString().padLeft(2, '0')}m';

  String get _averageSpeed {
    final hours = _trackingDuration.inMinutes / 60;
    if (hours <= 0) return '--';
    return '${(_distanceKm() / hours).toStringAsFixed(1)} km/h';
  }

  @override
  Widget build(BuildContext context) => Dialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 800, maxHeight: 680),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.employee.name} — Today\'s Route',
                    style: const TextStyle(
                      color: HrmsColors.navy,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            Text(
              '${widget.employee.id} · ${widget.employee.mode} mode',
              style: const TextStyle(color: Color(0xFF657087), fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _RouteStatusChip(
                  label: widget.employee.active
                      ? widget.employee.mode
                      : 'Offline',
                  active: widget.employee.active,
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: loading ? null : _selectDate,
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text(DateFormat('dd MMM yyyy').format(selectedDate)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : error != null
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    )
                  : points.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'No location pings recorded for this employee today.',
                        style: TextStyle(
                          color: Color(0xFF657087),
                          fontSize: 12,
                        ),
                      ),
                    )
                  : _routeCoordinates.isEmpty
                  ? const Center(
                      child: Text(
                        'No valid GPS locations are available for this date.',
                        style: TextStyle(
                          color: Color(0xFF657087),
                          fontSize: 12,
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: GoogleMap(
                              initialCameraPosition: CameraPosition(
                                target: _routeCoordinates.first,
                                zoom: 15,
                              ),
                              mapToolbarEnabled: false,
                              onMapCreated: (controller) {
                                _routeMapController = controller;
                                _fitRoute();
                              },
                              polylines: {
                                Polyline(
                                  polylineId: const PolylineId(
                                    'employee-route',
                                  ),
                                  points: _routeCoordinates,
                                  color: HrmsColors.blue,
                                  width: 5,
                                ),
                              },
                              markers: {
                                for (
                                  var index = 1;
                                  index < _routeCoordinates.length - 1;
                                  index++
                                )
                                  Marker(
                                    markerId: MarkerId('route-ping-$index'),
                                    position: _routeCoordinates[index],
                                    icon: BitmapDescriptor.defaultMarkerWithHue(
                                      BitmapDescriptor.hueGreen,
                                    ),
                                  ),
                                Marker(
                                  markerId: const MarkerId('route-start'),
                                  position: _routeCoordinates.first,
                                  icon:
                                      _startMarker ??
                                      BitmapDescriptor.defaultMarker,
                                  infoWindow: const InfoWindow(
                                    title: 'Start point',
                                  ),
                                ),
                                if (_routeCoordinates.length > 1)
                                  Marker(
                                    markerId: const MarkerId('route-end'),
                                    position: _routeCoordinates.last,
                                    icon:
                                        _endMarker ??
                                        BitmapDescriptor.defaultMarker,
                                    infoWindow: const InfoWindow(
                                      title: 'End point',
                                    ),
                                  ),
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _RouteMetrics(
                          distance: '${_distanceKm().toStringAsFixed(2)} km',
                          duration: _durationLabel(_trackingDuration),
                          speed: _averageSpeed,
                          updated: widget.employee.updatedLabel,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _OfficeLocationDialog extends StatefulWidget {
  const _OfficeLocationDialog();

  @override
  State<_OfficeLocationDialog> createState() => _OfficeLocationDialogState();
}

class _OfficeLocationDialogState extends State<_OfficeLocationDialog> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _matches = [];
  LatLng? _pin;
  GoogleMapController? _mapController;
  bool _searching = false;
  bool _loaded = false;
  int _searchVersion = 0;
  String? _searchError;
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  final _radius = TextEditingController();
  final _outsideGrace = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchVersion++;
    _search.dispose();
    _mapController?.dispose();
    _name.dispose();
    _address.dispose();
    _latitude.dispose();
    _longitude.dispose();
    _radius.dispose();
    _outsideGrace.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await HrmsTrackingApi.trackingSettings();
      if (!mounted) return;
      setState(() {
        _name.text = '${data['office_name'] ?? ''}';
        _address.text = '${data['office_address'] ?? ''}';
        _latitude.text = '${data['office_latitude'] ?? ''}';
        _longitude.text = '${data['office_longitude'] ?? ''}';
        _radius.text = '${data['office_radius_meters'] ?? 100}';
        _outsideGrace.text = '${data['outside_radius_grace_minutes'] ?? 2}';
        final lat = double.tryParse(_latitude.text);
        final lng = double.tryParse(_longitude.text);
        _pin = lat != null && lng != null && lat.isFinite && lng.isFinite
            ? LatLng(lat, lng)
            : null;
        _loaded = true;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        final message = error.toString().replaceFirst('Exception: ', '');
        _error = message.contains('Route not found')
            ? 'The running backend is an older version. Start the backend from Go-digital-software, then Retry.'
            : message;
      });
    }
  }

  Future<void> _findAddress() async {
    if (_searching || _saving) return;
    final query = _search.text.trim();
    if (query.length < 3) {
      setState(() => _searchError = 'Enter a street address and city.');
      return;
    }
    final version = ++_searchVersion;
    setState(() {
      _searching = true;
      _searchError = null;
      _matches = [];
    });
    try {
      final matches = await searchOfficeAddress(query);
      if (!mounted || version != _searchVersion) return;
      setState(() {
        _matches = matches;
        if (matches.isEmpty)
          _searchError = 'No matches. Add a city or postcode and search again.';
      });
    } catch (error) {
      if (!mounted || version != _searchVersion) return;
      setState(
        () => _searchError = error.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted && version == _searchVersion)
        setState(() => _searching = false);
    }
  }

  void _selectPin(LatLng point, {String? address}) {
    if (_saving) return;
    setState(() {
      _pin = point;
      _latitude.text = point.latitude.toStringAsFixed(7);
      _longitude.text = point.longitude.toStringAsFixed(7);
      if (address != null) _address.text = address;
      _matches = [];
    });
    if (address != null) {
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(point, 17));
    }
  }

  Widget _mapPicker() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _search,
        enabled: !_saving && !_searching,
        onSubmitted: (_) => _findAddress(),
        decoration: InputDecoration(
          labelText: 'Search office address',
          hintText: 'Street, city or postcode',
          prefixIcon: const Icon(Icons.search),
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: 'Find address',
            onPressed: _saving || _searching ? null : _findAddress,
            icon: const Icon(Icons.arrow_forward),
          ),
        ),
      ),
      if (_searching) const LinearProgressIndicator(),
      if (_searchError != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(_searchError!, style: const TextStyle(color: Colors.red)),
        ),
      for (final match in _matches)
        ListTile(
          leading: const Icon(Icons.place_outlined),
          title: Text('${match['address']}'),
          onTap: () => _selectPin(
            LatLng(match['latitude'] as double, match['longitude'] as double),
            address: match['address'] as String,
          ),
        ),
      const SizedBox(height: 12),
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 270,
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _pin ?? const LatLng(20.5937, 78.9629),
              zoom: _pin == null ? 4 : 17,
            ),
            onMapCreated: (controller) => _mapController = controller,
            onTap: _saving ? null : _selectPin,
            mapToolbarEnabled: false,
            markers: {
              if (_pin != null)
                Marker(
                  markerId: const MarkerId('office-location'),
                  position: _pin!,
                  draggable: !_saving,
                  onDragEnd: _selectPin,
                  infoWindow: const InfoWindow(title: 'Office entrance'),
                ),
            },
            circles: {
              if (_pin != null)
                Circle(
                  circleId: const CircleId('office-radius'),
                  center: _pin!,
                  radius: (int.tryParse(_radius.text) ?? 100)
                      .clamp(1, 100000)
                      .toDouble(),
                  strokeColor: HrmsColors.blue,
                  strokeWidth: 2,
                  fillColor: HrmsColors.blue.withValues(alpha: 0.12),
                ),
            },
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        _pin == null
            ? 'Search and select an address, or tap the map to place your office pin.'
            : 'Drag the pin to the office entrance. Coordinates are filled automatically.',
        style: const TextStyle(color: Color(0xFF657087), fontSize: 12),
      ),
    ],
  );

  Future<void> _save() async {
    if (!_loaded || _saving || _searching) return;
    final name = _name.text.trim();
    final address = _address.text.trim();
    final latitude = double.tryParse(_latitude.text.trim());
    final longitude = double.tryParse(_longitude.text.trim());
    final radius = int.tryParse(_radius.text.trim());
    final outsideGrace = int.tryParse(_outsideGrace.text.trim());
    if (name.isEmpty ||
        address.isEmpty ||
        latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180 ||
        radius == null ||
        radius < 1 ||
        outsideGrace == null ||
        outsideGrace < 1) {
      setState(
        () => _error =
            'Enter an office name and address, select its map pin, and enter a valid radius.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await HrmsTrackingApi.updateOfficeLocation(
        officeName: name,
        officeAddress: address,
        officeLatitude: latitude,
        officeLongitude: longitude,
        officeRadiusMeters: radius,
        outsideRadiusGraceMinutes: outsideGrace,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Office location saved for all employees.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? type,
  }) {
    return TextField(
      controller: controller,
      enabled: !_saving,
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    titlePadding: EdgeInsets.zero,
    title: Container(
      padding: const EdgeInsets.all(22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1769E0), Color(0xFF0C46A0)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: const Row(
        children: [
          Icon(Icons.location_on_outlined, color: Colors.white),
          SizedBox(width: 10),
          Text('Manage Office Location', style: TextStyle(color: Colors.white)),
        ],
      ),
    ),
    content: SizedBox(
      width: 620,
      child: _loading
          ? const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Find your office and place the pin at its entrance. Employees can clock in within the highlighted area.',
                    style: TextStyle(color: Color(0xFF657087), height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  _field(_name, 'Office / branch name'),
                  const SizedBox(height: 14),
                  _mapPicker(),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _address,
                    enabled: !_saving,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Full office address',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _radius,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Allowed Clock In radius (metres)',
                      border: OutlineInputBorder(),
                      helperText:
                          'This distance also applies to approved home locations.',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _outsideGrace,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Outside-radius grace period (minutes)',
                      border: OutlineInputBorder(),
                      helperText:
                          'Clock out after this many continuous minutes outside the office radius.',
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
    ),
    actionsPadding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
    actions: [
      if (!_loaded && !_loading)
        TextButton(onPressed: _load, child: const Text('Retry')),
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        onPressed: _saving || _loading || !_loaded || _searching ? null : _save,
        icon: _saving
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.save_outlined),
        label: Text(_saving ? 'Saving...' : 'Save Location'),
      ),
    ],
  );
}

class _FieldWaitingSettingsDialog extends StatefulWidget {
  const _FieldWaitingSettingsDialog({this.clockOutOnly = false});

  final bool clockOutOnly;

  @override
  State<_FieldWaitingSettingsDialog> createState() =>
      _FieldWaitingSettingsDialogState();
}

class _FieldWaitingSettingsDialogState
    extends State<_FieldWaitingSettingsDialog> {
  final _waitingController = TextEditingController();
  final _radiusController = TextEditingController();
  final _pingController = TextEditingController();
  final _popupAlertRepeatController = TextEditingController();
  final _autoConfirmationController = TextEditingController();
  final _autoWarningController = TextEditingController();
  final _autoBufferController = TextEditingController();
  final _autoSnoozeController = TextEditingController();
  final _reminderThresholdController = TextEditingController();
  final _reminderRepeatController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _homeTrackingEnabled = false;
  bool _autoClockOutEnabled = false;
  bool _clockOutReminderEnabled = true;
  String _clockOutReminderSound = 'notification.mp3';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _waitingController.dispose();
    _radiusController.dispose();
    _pingController.dispose();
    _popupAlertRepeatController.dispose();
    _autoConfirmationController.dispose();
    _autoWarningController.dispose();
    _autoBufferController.dispose();
    _autoSnoozeController.dispose();
    _reminderThresholdController.dispose();
    _reminderRepeatController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final data = await HrmsTrackingApi.trackingSettings();

      if (!mounted) return;

      setState(() {
        _waitingController.text = '${data['field_waiting_minutes'] ?? 60}';
        _radiusController.text = '${data['stationary_radius_meters'] ?? 50}';
        _pingController.text = '${data['field_ping_interval_minutes'] ?? 15}';
        _popupAlertRepeatController.text =
            '${data['popup_alert_repeat_seconds'] ?? 5}';
        _homeTrackingEnabled =
            data['home_tracking_enabled'] == true ||
            data['home_tracking_enabled'] == 1 ||
            data['home_tracking_enabled'] == '1';
        _autoClockOutEnabled =
            data['auto_clock_out_enabled'] == true ||
            data['auto_clock_out_enabled'] == 1 ||
            data['auto_clock_out_enabled'] == '1';
        _autoConfirmationController.text =
            '${data['auto_clock_out_confirmation_minutes'] ?? 3}';
        _autoWarningController.text =
            '${data['auto_clock_out_warning_seconds'] ?? 60}';
        _autoBufferController.text =
            '${data['auto_clock_out_boundary_buffer_meters'] ?? 50}';
        _autoSnoozeController.text =
            '${data['auto_clock_out_snooze_minutes'] ?? 15}';
        _clockOutReminderEnabled = data['clock_out_reminder_enabled'] == true ||
            data['clock_out_reminder_enabled'] == 1 ||
            data['clock_out_reminder_enabled'] == '1';
        _reminderThresholdController.text =
            '${data['clock_out_reminder_threshold_minutes'] ?? 15}';
        _reminderRepeatController.text =
            '${data['clock_out_reminder_repeat_minutes'] ?? 15}';
        _clockOutReminderSound =
            '${data['clock_out_reminder_sound'] ?? 'notification.mp3'}';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _save() async {
    final waitingMinutes = int.tryParse(_waitingController.text.trim());
    final stationaryRadius = int.tryParse(_radiusController.text.trim());
    final pingInterval = int.tryParse(_pingController.text.trim());
    final popupAlertRepeatSeconds = int.tryParse(
      _popupAlertRepeatController.text.trim(),
    );
    final autoConfirmation = int.tryParse(
      _autoConfirmationController.text.trim(),
    );
    final autoWarning = int.tryParse(_autoWarningController.text.trim());
    final autoBuffer = int.tryParse(_autoBufferController.text.trim());
    final autoSnooze = int.tryParse(_autoSnoozeController.text.trim());
    final reminderThreshold = int.tryParse(_reminderThresholdController.text.trim());
    final reminderRepeat = int.tryParse(_reminderRepeatController.text.trim());

    if (waitingMinutes == null ||
        stationaryRadius == null ||
        pingInterval == null ||
        popupAlertRepeatSeconds == null ||
        waitingMinutes < 1 ||
        stationaryRadius < 1 ||
        pingInterval < 1 ||
        popupAlertRepeatSeconds < 1 ||
        popupAlertRepeatSeconds > 30 ||
        autoConfirmation == null ||
        autoConfirmation < 1 ||
        autoWarning == null ||
        autoWarning < 10 ||
        autoBuffer == null ||
        autoBuffer < 0 ||
        autoSnooze == null ||
        autoSnooze < 1 ||
        reminderThreshold == null || reminderThreshold < 1 ||
        reminderRepeat == null || reminderRepeat < 1) {
      setState(() {
        _error = 'Use valid values. Popup alert repeat must be 1–30 seconds.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await HrmsTrackingApi.updateFieldWaitingSettings(
        fieldWaitingMinutes: waitingMinutes,
        stationaryRadiusMeters: stationaryRadius,
        fieldPingIntervalMinutes: pingInterval,
        popupAlertRepeatSeconds: popupAlertRepeatSeconds,
        homeTrackingEnabled: _homeTrackingEnabled,
        autoClockOutEnabled: _autoClockOutEnabled,
        autoClockOutConfirmationMinutes: autoConfirmation,
        autoClockOutWarningSeconds: autoWarning,
        autoClockOutBoundaryBufferMeters: autoBuffer,
        autoClockOutSnoozeMinutes: autoSnooze,
        clockOutReminderEnabled: _clockOutReminderEnabled,
        clockOutReminderThresholdMinutes: reminderThreshold,
        clockOutReminderRepeatMinutes: reminderRepeat,
        clockOutReminderSound: _clockOutReminderSound,
      );

      if (!mounted) return;

      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Field tracking settings saved')),
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _saving = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        Icon(
          widget.clockOutOnly
              ? Icons.alarm_outlined
              : Icons.timer_outlined,
          color: HrmsColors.blue,
        ),
        const SizedBox(width: 10),
        Text(
          widget.clockOutOnly
              ? 'Clock-out Reminder Settings'
              : 'Tracking Settings',
        ),
      ],
    ),
    content: SizedBox(
      width: 400,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .62,
        ),
        child: _loading
          ? const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                if (!widget.clockOutOnly) ...[
                const Text(
                  'Configure Field tracking and optional Home work functionality.',
                  style: TextStyle(color: Color(0xFF657087), fontSize: 12),
                ),
                const SizedBox(height: 18),
                _numberField(
                  controller: _waitingController,
                  label: 'Waiting time (minutes)',
                  hint: 'Example: 60',
                ),
                const SizedBox(height: 14),
                _numberField(
                  controller: _radiusController,
                  label: 'Stationary radius (metres)',
                  hint: 'Example: 50',
                ),
                const SizedBox(height: 14),
                _numberField(
                  controller: _pingController,
                  label: 'GPS update interval (minutes)',
                  hint: 'Example: 15',
                ),
                const SizedBox(height: 12),
                _numberField(
                  controller: _popupAlertRepeatController,
                  label: 'Popup alert repeat (seconds)',
                  hint: '1–30 (default: 5)',
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _homeTrackingEnabled,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _homeTrackingEnabled = value),
                  title: const Text('Enable Home work functionality'),
                  subtitle: Text(
                    _homeTrackingEnabled
                        ? 'Home location registration and approvals are available.'
                        : 'Home location registration and approvals are hidden.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                ],
                if (widget.clockOutOnly) ...[
                const Text(
                  'Choose when employees should be reminded to clock out after their shift.',
                  style: TextStyle(color: Color(0xFF657087), fontSize: 12),
                ),
                const SizedBox(height: 14),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _clockOutReminderEnabled,
                  onChanged: _saving ? null : (value) => setState(() => _clockOutReminderEnabled = value),
                  title: const Text('Send clock-out reminders'),
                  subtitle: const Text(
                    'Alert employees when their shift has ended but they are still checked in.',
                  ),
                ),
                if (_clockOutReminderEnabled) ...[
                  _numberField(
                    controller: _reminderThresholdController,
                    label: 'Send first reminder after shift (minutes)',
                    hint: '15',
                  ),
                  const SizedBox(height: 10),
                  _numberField(
                    controller: _reminderRepeatController,
                    label: 'Send another reminder every (minutes)',
                    hint: '15',
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: _clockOutReminderSound,
                    decoration: const InputDecoration(
                      labelText: 'Reminder sound',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'notification.mp3',
                        child: Text('Standard alert'),
                      ),
                      DropdownMenuItem(
                        value: 'notifications.mp3',
                        child: Text('Short alert'),
                      ),
                      DropdownMenuItem(
                        value: 'notificationss.mp3',
                        child: Text('Loud alert'),
                      ),
                      DropdownMenuItem(
                        value: 'notification_ai voice.mp3',
                        child: Text('Voice alert'),
                      ),
                    ],
                    onChanged: _saving ? null : (value) => setState(() => _clockOutReminderSound = value ?? 'notification.mp3'),
                  ),
                ],
                ],
                if (!widget.clockOutOnly) ...[
                const Divider(height: 24),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _autoClockOutEnabled,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _autoClockOutEnabled = value),
                  title: const Text('Enable Safe Auto Clock-out'),
                  subtitle: const Text(
                    'Office + Home only; disabled by default. Breaks and invalid GPS are always protected.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                if (_autoClockOutEnabled) ...[
                  _numberField(
                    controller: _autoConfirmationController,
                    label: 'Outside confirmation (minutes)',
                    hint: '3',
                  ),
                  const SizedBox(height: 10),
                  _numberField(
                    controller: _autoWarningController,
                    label: 'Warning countdown (seconds)',
                    hint: '60',
                  ),
                  const SizedBox(height: 10),
                  _numberField(
                    controller: _autoBufferController,
                    label: 'Boundary safety buffer (metres)',
                    hint: '50',
                  ),
                  const SizedBox(height: 10),
                  _numberField(
                    controller: _autoSnoozeController,
                    label: 'Still working snooze (minutes)',
                    hint: '15',
                  ),
                ],
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
                ],
              ),
            ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      ElevatedButton(
        onPressed: _loading || _saving ? null : _save,
        style: ElevatedButton.styleFrom(
          backgroundColor: HrmsColors.blue,
          foregroundColor: Colors.white,
        ),
        child: Text(_saving ? 'Saving...' : 'Save Settings'),
      ),
    ],
  );
}

class _FieldWaitingReasonsDialog extends StatefulWidget {
  const _FieldWaitingReasonsDialog();

  @override
  State<_FieldWaitingReasonsDialog> createState() =>
      _FieldWaitingReasonsDialogState();
}

class _FieldWaitingReasonsDialogState
    extends State<_FieldWaitingReasonsDialog> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await HrmsTrackingApi.fieldWaitingReasons();

      if (!mounted) return;

      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _markReviewed(int id) async {
    try {
      await HrmsTrackingApi.reviewFieldWaitingReason(id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting reason marked as reviewed')),
      );

      await _load();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Row(
      children: [
        Icon(Icons.fact_check_outlined, color: HrmsColors.blue),
        SizedBox(width: 10),
        Text('Submitted Waiting Reasons'),
      ],
    ),
    content: SizedBox(
      width: 720,
      height: 440,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          : _items.isEmpty
          ? const Center(child: Text('No waiting reasons submitted yet.'))
          : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final item = _items[index];
                final id = int.tryParse('${item['id']}');
                final fullName = '${item['full_name'] ?? 'Unknown employee'}';
                final employeeCode = '${item['employee_code'] ?? ''}';
                final reason = '${item['reason'] ?? ''}';
                final minutes = '${item['waiting_minutes'] ?? 0}';
                final status = '${item['review_status'] ?? 'pending'}';
                final submittedAt = '${item['reason_submitted_at'] ?? ''}';

                final reviewed = status == 'reviewed';

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        backgroundColor: const Color(0xFFEAF1FF),
                        child: Text(
                          fullName.isNotEmpty ? fullName.substring(0, 1) : '?',
                          style: const TextStyle(
                            color: HrmsColors.blue,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fullName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: HrmsColors.navy,
                              ),
                            ),
                            Text(
                              '$employeeCode · Waited $minutes minutes',
                              style: const TextStyle(
                                color: Color(0xFF657087),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(reason),
                            const SizedBox(height: 5),
                            Text(
                              submittedAt,
                              style: const TextStyle(
                                color: Color(0xFF657087),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      reviewed
                          ? const Chip(
                              label: Text('Reviewed'),
                              backgroundColor: Color(0xFFE4F6E8),
                            )
                          : TextButton(
                              onPressed: id == null
                                  ? null
                                  : () => _markReviewed(id),
                              child: const Text('Mark Reviewed'),
                            ),
                    ],
                  ),
                );
              },
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
  );
}

const _headStyle = TextStyle(
  color: Color(0xFF171B25),
  fontSize: 12,
  fontWeight: FontWeight.w600,
);
