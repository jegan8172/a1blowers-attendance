import 'leave_policy_dialog.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../shared/widgets/admin_top_nav.dart';
import '../../shared/theme/admin_surface_palette.dart';
import '../../../services/hrms_employees_api.dart';
import '../../../services/api_config.dart';
import '../../../services/auth_storage.dart';
import '../../../services/hrms_tracking_api.dart';

abstract final class HrmsColors {
  static const blue = Color(0xFF1769E0);
  static const navy = Color(0xFF081B3C);
  static const page = Color(0xFFF5F7FB);
  static const line = Color(0xFFD8E1F1);
}

class EmployeesPage extends StatefulWidget {
  const EmployeesPage({
    super.key,
    this.settingsAction,
    this.inSettingsDialog = false,
  });

  final String? settingsAction;
  final bool inSettingsDialog;

  static Widget builder(BuildContext context) => const EmployeesPage();

  @override
  State<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends State<EmployeesPage> {
  bool _openedSettingsAction = false;
  final searchController = TextEditingController();
  String query = '';
  String department = 'All Departments';
  String status = 'All Status';
  String workMode = 'All Work Modes';
  int currentPage = 1;
  static const int pageSize = 8;
  Timer? _searchDebounce;
  int _loadGeneration = 0;

  List<_Employee> employees = [];
  _Employee? _selectedEmployee;
  List<String> departmentOptions = const [];
  int filteredTotal = 0;
  int totalPages = 1;
  int kpiTotal = 0;
  int kpiActive = 0;
  int kpiOnLeave = 0;
  int kpiInactive = 0;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final arguments = ModalRoute.of(context)?.settings.arguments;
    final requestedCode = arguments is Map
        ? arguments['employeeCode']?.toString()
        : null;
    if (!_openedSettingsAction &&
        requestedCode != null &&
        requestedCode.isNotEmpty) {
      _openedSettingsAction = true;
      searchController.text = requestedCode;
      query = requestedCode;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _loadEmployees(preserveSelection: false);
        if (!mounted) return;
        for (final employee in employees) {
          if (employee.id.toLowerCase() == requestedCode.toLowerCase()) {
            setState(() => _selectedEmployee = employee);
            break;
          }
        }
      });
      return;
    }
    final action =
        widget.settingsAction ??
        (ModalRoute.of(context)?.settings.arguments as Map?)?['settingsAction'];
    if (_openedSettingsAction || action == null) return;
    _openedSettingsAction = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (action == 'deviceRequests') await _showDeviceRequests();
      if (action == 'leavePolicy') await _showLeavePolicies();
      if (action == 'addEmployee') await _showEmployeeForm();
      if (widget.inSettingsDialog && mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees({bool preserveSelection = true}) async {
    final generation = ++_loadGeneration;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await HrmsEmployeesApi.list(
        search: query,
        department: department,
        status: status,
        workMode: workMode,
        page: currentPage,
        limit: pageSize,
      );
      final items = (data['items'] as List? ?? [])
          .whereType<Map>()
          .map((item) => _Employee.fromApi(Map<String, dynamic>.from(item)))
          .toList();
      final kpis = Map<String, dynamic>.from(data['kpis'] as Map? ?? {});
      final departments =
          (data['departments'] as List? ?? [])
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      final selectedProfileId = _selectedEmployee?.profileId;
      _Employee? refreshedSelectedEmployee;
      if (selectedProfileId != null) {
        for (final item in items) {
          if (item.profileId == selectedProfileId) {
            refreshedSelectedEmployee = item;
            break;
          }
        }
      }
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        employees = items;
        // Keep the drawer in sync with the API response after an edit. Without
        // this, reopening Edit Employee uses its old Gender/Salary Type values.
        _selectedEmployee =
            refreshedSelectedEmployee ??
            (preserveSelection ? _selectedEmployee : null);
        departmentOptions = departments;
        filteredTotal = data['total'] is int
            ? data['total'] as int
            : int.tryParse('${data['total']}') ?? items.length;
        totalPages = data['totalPages'] is int
            ? data['totalPages'] as int
            : int.tryParse('${data['totalPages']}') ?? 1;
        currentPage = data['page'] is int
            ? data['page'] as int
            : int.tryParse('${data['page']}') ?? currentPage;
        kpiTotal = _asInt(kpis['total']);
        kpiActive = _asInt(kpis['active']);
        kpiOnLeave = _asInt(kpis['onLeave']);
        kpiInactive = _asInt(kpis['inactive']);
        loading = false;
      });
    } catch (err) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        error = err.toString().replaceFirst('Exception: ', '');
        loading = false;
      });
    }
  }

  int _asInt(dynamic value) =>
      value is int ? value : int.tryParse('$value') ?? 0;

  void _resetPageAndLoad() {
    currentPage = 1;
    _loadEmployees();
  }

  void _onSearchChanged(String value) {
    query = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _resetPageAndLoad();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.inSettingsDialog) return const SizedBox.shrink();
    final palette = AdminSurfacePalette.of(context);
    final mobile = MediaQuery.sizeOf(context).width < 600;
    final drawerWidth = MediaQuery.sizeOf(context).width < 1500 ? 390.0 : 450.0;
    final selected = _selectedEmployee;
    final motionDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240);
    Widget fill(Widget child) => mobile ? child : Expanded(child: child);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      bottomNavigationBar: mobile
          ? const AdminMobileBottomNav(activeRoute: '/admin/employees')
          : null,
      body: Column(
        children: [
          const AdminTopNav(activeRoute: '/admin/employees'),
          Expanded(
            child: loading && employees.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : error != null && employees.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(error!, textAlign: TextAlign.center),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _loadEmployees,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _EmployeeFrame(
                    mobile: mobile,
                    padding: EdgeInsets.fromLTRB(
                      mobile ? 16 : 34,
                      14,
                      mobile ? 16 : 34,
                      mobile ? 28 : 14,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1860),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _EmployeeKpis(
                              mobile: mobile,
                              total: kpiTotal,
                              active: kpiActive,
                              onLeave: kpiOnLeave,
                              inactive: kpiInactive,
                            ),
                            const SizedBox(height: 12),
                            fill(
                              Row(
                                crossAxisAlignment: mobile
                                    ? CrossAxisAlignment.start
                                    : CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: Container(
                                      padding: EdgeInsets.all(mobile ? 12 : 16),
                                      decoration: BoxDecoration(
                                        color: palette.surface,
                                        border: Border.all(
                                          color: palette.border,
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          LayoutBuilder(
                                            builder: (context, box) {
                                              final inline = !mobile;
                                              final condensed =
                                                  inline && box.maxWidth < 1200;
                                              final actions = Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (mobile)
                                                    IconButton.filled(
                                                      tooltip: 'Add employee',
                                                      onPressed:
                                                          _showEmployeeForm,
                                                      icon: const Icon(
                                                        Icons.add,
                                                      ),
                                                    )
                                                  else
                                                    FilledButton.icon(
                                                      onPressed:
                                                          _showEmployeeForm,
                                                      icon: const Icon(
                                                        Icons.add,
                                                        size: 20,
                                                      ),
                                                      label: Text(
                                                        box.maxWidth < 650
                                                            ? 'Add'
                                                            : 'Add Employee',
                                                      ),
                                                      style: FilledButton.styleFrom(
                                                        backgroundColor:
                                                            HrmsColors.blue,
                                                        padding:
                                                            EdgeInsets.symmetric(
                                                              horizontal:
                                                                  condensed
                                                                  ? 12
                                                                  : 20,
                                                              vertical: 12,
                                                            ),
                                                        minimumSize: const Size(
                                                          0,
                                                          48,
                                                        ),
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  const SizedBox(width: 10),
                                                  IconButton(
                                                    tooltip: 'Export employees',
                                                    onPressed: _exportEmployees,
                                                    icon: const Icon(
                                                      Icons.download_outlined,
                                                      color: HrmsColors.blue,
                                                    ),
                                                  ),
                                                ],
                                              );
                                              final filters = _Filters(
                                                compact: inline,
                                                condensed: condensed,
                                                searchController:
                                                    searchController,
                                                department: department,
                                                departmentOptions:
                                                    departmentOptions,
                                                status: status,
                                                workMode: workMode,
                                                onSearch: _onSearchChanged,
                                                onDepartment: (value) {
                                                  department = value!;
                                                  _resetPageAndLoad();
                                                },
                                                onStatus: (value) {
                                                  status = value!;
                                                  _resetPageAndLoad();
                                                },
                                                onMode: (value) {
                                                  workMode = value!;
                                                  _resetPageAndLoad();
                                                },
                                                onReset: _resetFilters,
                                              );
                                              return inline
                                                  ? Row(
                                                      children: [
                                                        Expanded(
                                                          child: filters,
                                                        ),
                                                        const SizedBox(
                                                          width: 12,
                                                        ),
                                                        actions,
                                                      ],
                                                    )
                                                  : Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .stretch,
                                                      children: [
                                                        Align(
                                                          alignment: Alignment
                                                              .centerRight,
                                                          child: actions,
                                                        ),
                                                        const SizedBox(
                                                          height: 10,
                                                        ),
                                                        filters,
                                                      ],
                                                    );
                                            },
                                          ),
                                          const SizedBox(height: 10),
                                          if (error != null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 10,
                                              ),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      'Could not refresh employees: $error',
                                                      style: const TextStyle(
                                                        color: Colors.red,
                                                      ),
                                                    ),
                                                  ),
                                                  TextButton(
                                                    onPressed: _loadEmployees,
                                                    child: const Text('Retry'),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          SizedBox(
                                            height: 2,
                                            child: loading
                                                ? const LinearProgressIndicator(
                                                    minHeight: 2,
                                                  )
                                                : null,
                                          ),
                                          if (mobile)
                                            _EmployeeTable(
                                              employees: employees,
                                              selectedProfileId:
                                                  _selectedEmployee?.profileId,
                                              total: filteredTotal,
                                              currentPage: currentPage
                                                  .clamp(1, totalPages)
                                                  .toInt(),
                                              totalPages: totalPages,
                                              pageSize: pageSize,
                                              mobile: true,
                                              onPageChanged: (page) {
                                                currentPage = page
                                                    .clamp(1, totalPages)
                                                    .toInt();
                                                _loadEmployees();
                                              },
                                              onView: (employee) =>
                                                  _showEmployeeDetails(
                                                    employee,
                                                  ),
                                              onOpenDetails: (employee) =>
                                                  _openFullEmployeeDetails(
                                                    employee,
                                                  ),
                                              onEdit: (employee) =>
                                                  _showEmployeeForm(
                                                    employee: employee,
                                                  ),
                                              onToggle: _toggleEmployee,
                                              onDelete: _confirmDelete,
                                            )
                                          else
                                            fill(
                                              _EmployeeTable(
                                                employees: employees,
                                                selectedProfileId:
                                                    _selectedEmployee
                                                        ?.profileId,
                                                total: filteredTotal,
                                                currentPage: currentPage
                                                    .clamp(1, totalPages)
                                                    .toInt(),
                                                totalPages: totalPages,
                                                pageSize: pageSize,
                                                mobile: false,
                                                onPageChanged: (page) {
                                                  currentPage = page
                                                      .clamp(1, totalPages)
                                                      .toInt();
                                                  _loadEmployees();
                                                },
                                                onView: _showEmployeeDetails,
                                                onOpenDetails:
                                                    _openFullEmployeeDetails,
                                                onEdit: (employee) =>
                                                    _showEmployeeForm(
                                                      employee: employee,
                                                    ),
                                                onToggle: _toggleEmployee,
                                                onDelete: _confirmDelete,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (!mobile)
                                    AnimatedSize(
                                      duration: motionDuration,
                                      curve: Curves.easeInOut,
                                      alignment: Alignment.centerRight,
                                      child: SizedBox(
                                        width: selected == null
                                            ? 0
                                            : drawerWidth + 16,
                                        child: ClipRect(
                                          child: OverflowBox(
                                            alignment: Alignment.centerRight,
                                            minWidth: drawerWidth + 16,
                                            maxWidth: drawerWidth + 16,
                                            child: AnimatedSwitcher(
                                              duration:
                                                  MediaQuery.disableAnimationsOf(
                                                    context,
                                                  )
                                                  ? Duration.zero
                                                  : const Duration(
                                                      milliseconds: 420,
                                                    ),
                                              transitionBuilder:
                                                  (
                                                    child,
                                                    animation,
                                                  ) => FadeTransition(
                                                    opacity: animation,
                                                    child: SlideTransition(
                                                      position:
                                                          Tween<Offset>(
                                                            begin: const Offset(
                                                              .18,
                                                              0,
                                                            ),
                                                            end: Offset.zero,
                                                          ).animate(
                                                            CurvedAnimation(
                                                              parent: animation,
                                                              curve: Curves
                                                                  .easeOut,
                                                            ),
                                                          ),
                                                      child: child,
                                                    ),
                                                  ),
                                              child: selected == null
                                                  ? const SizedBox.shrink(
                                                      key: ValueKey('closed'),
                                                    )
                                                  : Padding(
                                                      key: ValueKey(
                                                        selected.profileId,
                                                      ),
                                                      padding:
                                                          const EdgeInsets.only(
                                                            left: 16,
                                                          ),
                                                      child: _EmployeeSidePanel(
                                                        employee: selected,
                                                        onClose:
                                                            _closeEmployeeDetails,
                                                        onOpenDetails: () =>
                                                            _openFullEmployeeDetails(
                                                              selected,
                                                            ),
                                                        onOpenPayroll: () =>
                                                            _openFullEmployeeDetails(
                                                              selected,
                                                              initialTab: 2,
                                                            ),
                                                        onResetPassword: () =>
                                                            _resetEmployeePassword(
                                                              context,
                                                              selected,
                                                            ),
                                                        onEdit: () =>
                                                            _showEmployeeForm(
                                                              employee:
                                                                  selected,
                                                            ),
                                                        onDelete: () =>
                                                            _confirmDelete(
                                                              selected,
                                                            ),
                                                      ),
                                                    ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _resetFilters() {
    query = '';
    department = 'All Departments';
    status = 'All Status';
    workMode = 'All Work Modes';
    currentPage = 1;
    searchController.clear();
    _loadEmployees();
  }

  Future<void> _exportEmployees() async {
    try {
      final csv = await HrmsEmployeesApi.exportCsv(
        search: searchController.text.trim(),
        department: department,
        status: status,
        workMode: workMode,
      );
      final rows = _parseCsv(csv);
      if (rows.length <= 1)
        throw Exception('No employees available to export.');
      final logo = pw.MemoryImage(
        (await rootBundle.load(
          'assets/images/a1_blowers_logo_header.png',
        )).buffer.asUint8List(),
      );
      final generatedAt = DateFormat(
        'dd MMM yyyy, hh:mm a',
      ).format(DateTime.now());
      final pdfRows = rows
          .map(
            (row) => row.map((value) => value.replaceAll('₹', 'Rs. ')).toList(),
          )
          .toList();
      final document = pw.Document();
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 30),
          header: (context) => pw.Column(
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Container(
                    width: 54,
                    height: 54,
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Image(logo, fit: pw.BoxFit.contain),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'A1 BLOWERS',
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.red900,
                        ),
                      ),
                      pw.Text(
                        'Employee Directory',
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                  pw.Spacer(),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'EMPLOYEE MANAGEMENT',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue700,
                        ),
                      ),
                      pw.Text(
                        'Generated $generatedAt',
                        style: const pw.TextStyle(
                          fontSize: 8,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Container(height: 2, color: PdfColors.blue700),
              pw.SizedBox(height: 14),
            ],
          ),
          footer: (context) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'A1 Blowers - Confidential internal record',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey600,
                ),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          ),
          build: (context) => [
            pw.Text(
              'Employee Directory',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue900,
              ),
            ),
            pw.SizedBox(height: 5),
            pw.Text(
              '${rows.length - 1} employees',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 12),
            pw.Table.fromTextArray(
              headers: rows.first,
              data: pdfRows.skip(1).toList(),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF1769E0),
              ),
              headerStyle: pw.TextStyle(
                color: PdfColors.white,
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(
                fontSize: 8,
                color: PdfColors.blue900,
              ),
              cellHeight: 26,
              border: pw.TableBorder.all(
                color: PdfColor.fromInt(0xFFD8E1F1),
                width: .6,
              ),
              oddRowDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFF4F7FC),
              ),
            ),
          ],
        ),
      );
      await Printing.layoutPdf(onLayout: (_) => document.save());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Professional employee PDF is ready.')),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  List<List<String>> _parseCsv(String input) {
    final rows = <List<String>>[];
    for (final line in input.split(RegExp(r'\r?\n'))) {
      if (line.trim().isEmpty) continue;
      final values = line.contains('"')
          ? RegExp(r'"((?:""|[^"])*)"')
                .allMatches(line)
                .map((match) => match.group(1)!.replaceAll('""', '"'))
                .toList()
          : line.split(',').map((value) => value.trim()).toList();
      if (values.isNotEmpty) rows.add(values);
    }
    return rows;
  }

  Future<void> _runAction(Future<void> Function() action) async {
    try {
      await action();
      await _loadEmployees();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _showLeavePolicies() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const LeavePolicyDialog(),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Leave policies saved.')));
    }
  }

  Future<void> _showEmployeeForm({_Employee? employee}) async {
    final name = TextEditingController(text: employee?.name ?? '');
    final id = TextEditingController(
      text: employee?.id ?? 'EMP${1001 + kpiTotal}',
    );
    final salary = TextEditingController(
      text: employee?.salary == 'Not Set'
          ? ''
          : employee?.salary.replaceAll(RegExp(r'[^0-9]'), '') ?? '',
    );
    final cycleToday = DateTime.now();
    DateTime joiningDate =
        DateTime.tryParse(employee?.joiningDate ?? '') ?? cycleToday;
    DateTimeRange? flexibleCycleRange;
    if (employee?.flexibleCycleStartDay != null &&
        employee?.flexibleCycleEndDay != null) {
      final start =
          DateTime.tryParse(employee?.flexibleCycleStartDate ?? '') ??
          DateTime(
            cycleToday.year,
            cycleToday.month,
            employee!.flexibleCycleStartDay!,
          );
      var end =
          DateTime.tryParse(employee?.flexibleCycleEndDate ?? '') ??
          DateTime(
            cycleToday.year,
            cycleToday.month,
            employee!.flexibleCycleEndDay!,
          );
      if (end.isBefore(start)) {
        end = DateTime(
          cycleToday.year,
          cycleToday.month + 1,
          employee!.flexibleCycleEndDay!,
        );
      }
      flexibleCycleRange = DateTimeRange(start: start, end: end);
    }
    final username = TextEditingController(text: employee?.username ?? '');
    final phone = TextEditingController(text: employee?.phone ?? '');
    final email = TextEditingController();
    final password = TextEditingController();
    var obscurePassword = true;
    final availableDepartments = <String>{
      ...departmentOptions,
      if (employee?.department != null) employee!.department,
    }.toList()..sort();
    var selectedDepartment =
        employee?.department ??
        (availableDepartments.isNotEmpty
            ? availableDepartments.first
            : 'Engineering');
    var selectedMode = employee?.workMode ?? 'Office';
    late final List<Map<String, dynamic>> templates;
    try {
      templates = await HrmsTrackingApi.trackingTemplates();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to open the employee form: tracking templates could not '
            'be loaded. Deploy the matching backend and try again. $error',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    var selectedTrackingTemplateId = employee?.trackingTemplateId;
    var selectedEmployeeType = employee?.employeeType ?? 'Employee';
    var overtimeEligible = employee?.overtimeEligible ?? false;
    var selectedGender = employee?.gender ?? 'Male';
    const employmentStatuses = ['Active', 'On Leave', 'Inactive'];
    var selectedStatus = employmentStatuses.contains(employee?.status)
        ? employee!.status
        : 'Active';
    var selectedSalaryType = employee?.salaryType ?? 'Standard';
    final formKey = GlobalKey<FormState>();
    var submitting = false;
    String? submitError;
    Map<String, dynamic>? createdEmployee;

    Map<String, dynamic> requestBody() => {
      'name': name.text.trim(),
      'phone': phone.text.trim(),
      'employeeCode': id.text.trim(),
      'department': selectedDepartment,
      'workMode': selectedMode,
      if (selectedMode == 'Field' || selectedMode == 'Hybrid')
        'trackingTemplateId': selectedTrackingTemplateId,
      'employeeType': selectedEmployeeType,
      'overtimeEligible': overtimeEligible,
      'gender': selectedGender,
      'status': selectedStatus,
      'salary': salary.text.trim(),
      'salaryType': selectedSalaryType,
      'joiningDate':
          '${joiningDate.year.toString().padLeft(4, '0')}-${joiningDate.month.toString().padLeft(2, '0')}-${joiningDate.day.toString().padLeft(2, '0')}',
      if (selectedSalaryType == 'Flexible')
        'flexibleCycleStartDay': flexibleCycleRange?.start.day,
      if (selectedSalaryType == 'Flexible')
        'flexibleCycleEndDay': flexibleCycleRange?.end.day,
      if (selectedSalaryType == 'Flexible')
        'flexibleCycleStartDate': flexibleCycleRange?.start
            .toIso8601String()
            .substring(0, 10),
      if (selectedSalaryType == 'Flexible')
        'flexibleCycleEndDate': flexibleCycleRange?.end
            .toIso8601String()
            .substring(0, 10),
      'username': username.text.trim(),
      if (employee == null) 'email': email.text.trim(),
      if (employee == null || password.text.isNotEmpty)
        'password': password.text,
    };

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(employee == null ? 'Add Employee' : 'Edit Employee'),
          content: SizedBox(
            width: 470,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (submitError != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE53935)),
                        ),
                        child: Text(
                          submitError!,
                          style: const TextStyle(color: Color(0xFFB71C1C)),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _formField(name, 'Employee name'),
                    const SizedBox(height: 12),
                    _formField(id, 'Employee ID'),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime(1950),
                          lastDate: DateTime(2100),
                          initialDate: joiningDate,
                          helpText: 'Select joining date',
                        );
                        if (picked != null)
                          setDialogState(() => joiningDate = picked);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Joining date',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_month_outlined),
                        ),
                        child: Text(
                          DateFormat('d MMM yyyy').format(joiningDate),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      maxLength: 32,
                      validator: (value) {
                        final number = (value ?? '').trim();
                        if (number.isEmpty) return null;
                        return RegExp(r'^[0-9+(). -]+$').hasMatch(number) &&
                                RegExp(r'[0-9]').hasMatch(number)
                            ? null
                            : 'Enter a valid phone number';
                      },
                      decoration: const InputDecoration(
                        labelText: 'Phone number',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (employee == null) ...[
                      _formField(username, 'Username'),
                      const SizedBox(height: 12),
                      _formField(email, 'Email address'),
                      const SizedBox(height: 12),
                      _formField(
                        password,
                        'Login password (minimum 8 characters)',
                      ),
                      const SizedBox(height: 12),
                    ] else ...[
                      _formField(username, 'Username'),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: password,
                        obscureText: obscurePassword,
                        decoration: InputDecoration(
                          labelText:
                              'New password (leave empty to keep current password)',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () => setDialogState(
                              () => obscurePassword = !obscurePassword,
                            ),
                          ),
                        ),
                        validator: (value) =>
                            value != null &&
                                value.isNotEmpty &&
                                value.length < 8
                            ? 'Password must have at least 8 characters'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'For security, the existing password is not stored in readable form. Entering a new one replaces it.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF657087),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _formDropdown(
                      'Department',
                      selectedDepartment,
                      availableDepartments,
                      (value) =>
                          setDialogState(() => selectedDepartment = value!),
                      onAddRole: () async {
                        final role = await _showAddRoleDialog(dialogContext);
                        if (role == null || !mounted) return;
                        try {
                          await HrmsEmployeesApi.createRole(role);
                          if (!mounted) return;
                          setState(() {
                            departmentOptions = {
                              ...departmentOptions,
                              role,
                            }.toList()..sort();
                          });
                          setDialogState(() {
                            if (!availableDepartments.contains(role)) {
                              availableDepartments.add(role);
                              availableDepartments.sort();
                            }
                            selectedDepartment = role;
                          });
                        } catch (err) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                err.toString().replaceFirst('Exception: ', ''),
                              ),
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    _formDropdown(
                      'Work mode',
                      selectedMode,
                      const ['Office', 'Hybrid', 'Field'],
                      (value) => setDialogState(() {
                        selectedMode = value!;
                        if (selectedMode == 'Office' || selectedMode == 'Home')
                          selectedTrackingTemplateId = null;
                      }),
                    ),
                    if (selectedMode == 'Field' ||
                        selectedMode == 'Hybrid') ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        value:
                            templates.any(
                              (t) =>
                                  int.tryParse('${t['id']}') ==
                                  selectedTrackingTemplateId,
                            )
                            ? selectedTrackingTemplateId
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Live tracking template',
                          border: OutlineInputBorder(),
                        ),
                        items: templates
                            .where(
                              (t) =>
                                  t['is_active'] == 1 || t['is_active'] == true,
                            )
                            .map(
                              (t) => DropdownMenuItem<int>(
                                value: int.parse('${t['id']}'),
                                child: Text('${t['name']}'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setDialogState(
                          () => selectedTrackingTemplateId = value,
                        ),
                        validator: (value) =>
                            value == null ? 'Select a tracking template' : null,
                      ),
                    ],
                    const SizedBox(height: 12),
                    _formDropdown(
                      'Employee type',
                      selectedEmployeeType,
                      const ['Employee', 'Labour'],
                      (value) =>
                          setDialogState(() => selectedEmployeeType = value!),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Overtime eligible'),
                      subtitle: const Text(
                        'Automatically records work beyond scheduled hours.',
                      ),
                      value: overtimeEligible,
                      onChanged: (value) =>
                          setDialogState(() => overtimeEligible = value),
                    ),
                    const SizedBox(height: 12),
                    _formDropdown(
                      'Gender',
                      selectedGender,
                      const ['Male', 'Female'],
                      (value) => setDialogState(() => selectedGender = value!),
                    ),
                    const SizedBox(height: 12),
                    _formDropdown(
                      'Employment status',
                      selectedStatus,
                      employmentStatuses,
                      (value) => setDialogState(() => selectedStatus = value!),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: salary,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Monthly salary (optional)',
                        prefixText: '₹',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _formDropdown(
                      'Salary type',
                      selectedSalaryType,
                      const ['Standard', 'Flexible'],
                      (value) =>
                          setDialogState(() => selectedSalaryType = value!),
                    ),
                    if (selectedSalaryType == 'Flexible') ...[
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () async {
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                            initialDateRange: flexibleCycleRange,
                            helpText: 'Select salary cycle dates',
                          );
                          if (picked != null) {
                            setDialogState(() => flexibleCycleRange = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Salary cycle dates',
                            helperText:
                                'Days before this start date are excluded from salary deduction.',
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.calendar_month_outlined),
                          ),
                          child: Text(
                            flexibleCycleRange == null
                                ? 'Select start and end date'
                                : '${DateFormat('d MMM yyyy').format(flexibleCycleRange!.start)} – ${DateFormat('d MMM yyyy').format(flexibleCycleRange!.end)}',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() {
                        submitting = true;
                        submitError = null;
                      });
                      try {
                        final body = requestBody();
                        if (employee == null) {
                          createdEmployee = await HrmsEmployeesApi.create(body);
                        } else {
                          await HrmsEmployeesApi.update(
                            employee.profileId,
                            body,
                          );
                        }
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } catch (err) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          submitting = false;
                          submitError = err.toString().replaceFirst(
                            'Exception: ',
                            '',
                          );
                        });
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(employee == null ? 'Add Employee' : 'Save Changes'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    await _loadEmployees();
    final credentials = createdEmployee?['credentials'];
    if (credentials is Map && mounted) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Employee login created'),
          content: SelectableText(
            'Username: ${credentials['username']}\nEmail: ${credentials['email']}\nPassword: ${credentials['password']}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    }
  }

  Widget _formField(TextEditingController controller, String label) =>
      TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator: (value) =>
            value == null || value.trim().isEmpty ? '$label is required' : null,
      );

  Future<String?> _showAddRoleDialog(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add new role'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Role name',
            hintText: 'e.g. Content Writer',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final role = controller.text.trim();
              if (role.isNotEmpty) Navigator.pop(dialogContext, role);
            },
            child: const Text('Add role'),
          ),
        ],
      ),
    );
  }

  Widget _formDropdown(
    String label,
    String value,
    List<String> values,
    ValueChanged<String?> onChanged, {
    Future<void> Function()? onAddRole,
  }) {
    // Keep the employee's current designation even when it is a custom value,
    // and ensure each dropdown value appears only once.
    final dropdownValues = <String>{...values, value}.toList();
    const addRoleValue = '__add_new_role__';
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        if (onAddRole != null)
          const DropdownMenuItem(
            value: addRoleValue,
            child: Row(
              children: [
                Icon(Icons.add_circle_outline, color: HrmsColors.blue),
                SizedBox(width: 8),
                Text('Add new role'),
              ],
            ),
          ),
        ...dropdownValues.map(
          (item) => DropdownMenuItem(value: item, child: Text(item)),
        ),
      ],
      onChanged: (selected) {
        if (selected == addRoleValue) {
          onAddRole?.call();
          return;
        }
        onChanged(selected);
      },
    );
  }

  Future<void> _showEmployeeDetails(_Employee employee) async {
    if (!mounted) return;
    if (MediaQuery.sizeOf(context).width < 600) {
      await _openFullEmployeeDetails(employee);
      return;
    }
    setState(() => _selectedEmployee = employee);
  }

  void _closeEmployeeDetails() {
    setState(() => _selectedEmployee = null);
  }

  Future<void> _openFullEmployeeDetails(
    _Employee employee, {
    int initialTab = 0,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _EmployeeDetailPage(employee: employee, initialTab: initialTab),
      ),
    );
  }

  Future<void> _showDeviceRequests() async {
    try {
      final data = await HrmsEmployeesApi.deviceRequests();
      final items = (data['items'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Device change requests'),
          content: SizedBox(
            width: 540,
            child: items.isEmpty
                ? const Text('No pending device change requests.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (_, index) {
                      final item = items[index];
                      final name =
                          '${item['full_name'] ?? 'Employee'} (${item['employee_code'] ?? item['username'] ?? ''})';
                      return ListTile(
                        title: Text(name),
                        subtitle: Text(
                          'New device: ${item['proposed_device_label'] ?? 'Browser'}\nReason: ${item['reason'] ?? 'Not provided'}',
                        ),
                        isThreeLine: true,
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: 'Reject',
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () async {
                                await HrmsEmployeesApi.reviewDeviceRequest(
                                  int.parse('${item['id']}'),
                                  false,
                                );
                                if (dialogContext.mounted)
                                  Navigator.pop(dialogContext);
                                if (mounted) _showDeviceRequests();
                              },
                            ),
                            IconButton(
                              tooltip: 'Approve new browser',
                              icon: const Icon(
                                Icons.check,
                                color: Colors.green,
                              ),
                              onPressed: () async {
                                await HrmsEmployeesApi.reviewDeviceRequest(
                                  int.parse('${item['id']}'),
                                  true,
                                );
                                if (dialogContext.mounted)
                                  Navigator.pop(dialogContext);
                                if (mounted) _showDeviceRequests();
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (err) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err.toString().replaceFirst('Exception: ', '')),
          ),
        );
    }
  }

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Color(0xFF657087))),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );

  Future<void> _toggleEmployee(_Employee employee) async {
    final next = employee.status == 'Inactive' ? 'Active' : 'Inactive';
    await _runAction(
      () => HrmsEmployeesApi.updateStatus(employee.profileId, next),
    );
  }

  Future<void> _confirmDelete(_Employee employee) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Permanently delete employee?'),
        content: Text(
          '${employee.name} and all associated attendance, payroll, tracking, login, and request records will be permanently deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Permanently delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runAction(() async {
      await HrmsEmployeesApi.delete(employee.profileId);
      if (mounted && _selectedEmployee?.profileId == employee.profileId) {
        setState(() => _selectedEmployee = null);
      }
    });
  }
}

class _EmployeeFrame extends StatelessWidget {
  const _EmployeeFrame({
    required this.mobile,
    required this.padding,
    required this.child,
  });
  final bool mobile;
  final EdgeInsets padding;
  final Widget child;
  @override
  Widget build(BuildContext context) => mobile
      ? SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: padding,
          child: child,
        )
      : Padding(padding: padding, child: child);
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.onExport, required this.onAdd});

  final VoidCallback onExport;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => AdminPageHeader(
    title: 'Employees',
    subtitle:
        'Manage your team at A1 Blowers. Hire, update, and track employee information in one place.',
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Employee'),
          style: FilledButton.styleFrom(
            backgroundColor: HrmsColors.blue,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: onExport,
          icon: const Icon(Icons.download_outlined),
          label: const Text('Export'),
          style: OutlinedButton.styleFrom(
            foregroundColor: HrmsColors.blue,
            side: const BorderSide(color: Color(0xFFFFA9B3)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
        ),
      ],
    ),
  );
}

class _EmployeeKpis extends StatelessWidget {
  const _EmployeeKpis({
    required this.mobile,
    required this.total,
    required this.active,
    required this.onLeave,
    required this.inactive,
  });
  final bool mobile;
  final int total, active, onLeave, inactive;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _EmployeeKpi(
        'Total Employees',
        '$total',
        'All employees',
        Icons.groups_outlined,
        const Color(0xFF00A76F),
      ),
      _EmployeeKpi(
        'Active Employees',
        '$active',
        _percentage(active, total),
        Icons.person_outline_rounded,
        const Color(0xFF148B1A),
      ),
      _EmployeeKpi(
        'On Leave',
        '$onLeave',
        _percentage(onLeave, total),
        Icons.event_busy_outlined,
        const Color(0xFFFF6500),
      ),
      _EmployeeKpi(
        'Inactive Employees',
        '$inactive',
        _percentage(inactive, total),
        Icons.person_off_outlined,
        const Color(0xFFF0182A),
      ),
    ];
    return LayoutBuilder(
      builder: (_, constraints) {
        final columns = mobile ? 2 : 4;
        final spacing = mobile ? 8.0 : 12.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: mobile ? 8 : 16,
          children: [
            ...cards.map((card) => SizedBox(width: width, child: card)),
          ],
        );
      },
    );
  }

  String _percentage(int value, int total) => total == 0
      ? '0% of total'
      : '${(value * 100 / total).toStringAsFixed(1)}% of total';
}

class _EmployeeKpi extends StatelessWidget {
  const _EmployeeKpi(
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
    if (MediaQuery.sizeOf(context).width < 600) {
      final mobileLabel = label == 'Total Employees' ? 'Employees' : label;
      return Container(
        height: 68,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border.all(color: color.withValues(alpha: .25)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mobileLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.mutedText, fontSize: 11),
            ),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 25,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (_, constraints) {
        final compact = constraints.maxWidth < 220;
        return Container(
          height: 76,
          padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
          decoration: BoxDecoration(
            color: palette.surface,
            border: Border.all(color: color.withValues(alpha: .28)),
            borderRadius: BorderRadius.circular(13),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08071A72),
                blurRadius: 12,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: compact ? 36 : 42,
                height: compact ? 36 : 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: compact ? 19 : 21),
              ),
              SizedBox(width: compact ? 9 : 13),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.mutedText,
                        fontSize: compact ? 11 : 13,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: compact ? 22 : 25,
                        height: 1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.mutedText, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    this.compact = false,
    this.condensed = false,
    required this.searchController,
    required this.department,
    required this.departmentOptions,
    required this.status,
    required this.workMode,
    required this.onSearch,
    required this.onDepartment,
    required this.onStatus,
    required this.onMode,
    required this.onReset,
  });

  final TextEditingController searchController;
  final bool compact;
  final bool condensed;
  final String department, status, workMode;
  final List<String> departmentOptions;
  final ValueChanged<String> onSearch;
  final ValueChanged<String?> onDepartment, onStatus, onMode;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final palette = AdminSurfacePalette.of(context);
    return Container(
      padding: EdgeInsets.all(
        compact || MediaQuery.sizeOf(context).width < 600 ? 0 : 8,
      ),
      decoration: BoxDecoration(
        color: compact || MediaQuery.sizeOf(context).width < 600
            ? Colors.transparent
            : palette.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: compact || MediaQuery.sizeOf(context).width < 600
            ? const []
            : const [
                BoxShadow(
                  color: Color(0x0C071A72),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
      ),
      child: LayoutBuilder(
        builder: (_, constraints) {
          final narrow = constraints.maxWidth < 850;
          final search = TextField(
            controller: searchController,
            onChanged: onSearch,
            decoration:
                _inputDecoration(
                  'Search by name, employee ID or email',
                  Icons.search_rounded,
                ).copyWith(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                ),
          );
          final departmentField = _FilterDropdown(
            label: 'Department',
            value: department,
            values: ['All Departments', ...departmentOptions],
            onChanged: onDepartment,
          );
          final statusField = _FilterDropdown(
            label: 'Status',
            value: status,
            values: const ['All Status', 'Active', 'On Leave', 'Inactive'],
            onChanged: onStatus,
          );
          final modeField = _FilterDropdown(
            label: 'Work Mode',
            value: workMode,
            values: const ['All Work Modes', 'Office', 'Field', 'Hybrid'],
            onChanged: onMode,
          );
          final reset = Tooltip(
            message: 'Clear filters',
            child: OutlinedButton(
              onPressed: onReset,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 40),
                side: const BorderSide(color: Color(0xFFFFA9B3)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              child: const Text('Clear'),
            ),
          );
          final mobile = MediaQuery.sizeOf(context).width < 600;
          if (condensed) {
            final activeCount =
                (department != 'All Departments' ? 1 : 0) +
                (status != 'All Status' ? 1 : 0) +
                (workMode != 'All Work Modes' ? 1 : 0);
            return Row(
              children: [
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: search,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _openMobileFilters(context),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: Text(
                    activeCount == 0 ? 'Filters' : 'Filters ($activeCount)',
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
                const Spacer(),
              ],
            );
          }
          if (compact) {
            return Row(
              children: [
                Expanded(flex: 3, child: search),
                const SizedBox(width: 14),
                Expanded(flex: 2, child: departmentField),
                const SizedBox(width: 14),
                Expanded(flex: 2, child: statusField),
                const SizedBox(width: 14),
                Expanded(flex: 2, child: modeField),
                const SizedBox(width: 14),
                reset,
              ],
            );
          }
          if (mobile) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _openMobileFilters(context),
                      icon: const Icon(Icons.tune_rounded, size: 20),
                      label: const Text('Filters'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: HrmsColors.blue,
                        side: const BorderSide(color: HrmsColors.blue),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: onReset,
                      icon: const Icon(Icons.restart_alt_rounded, size: 18),
                      label: const Text('Reset'),
                    ),
                  ],
                ),
              ],
            );
          }
          if (constraints.maxWidth >= 760) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(flex: 3, child: search),
                const SizedBox(width: 14),
                Expanded(flex: 3, child: departmentField),
                const SizedBox(width: 14),
                Expanded(flex: 3, child: statusField),
                const SizedBox(width: 14),
                Expanded(flex: 3, child: modeField),
                const SizedBox(width: 14),
                reset,
              ],
            );
          }
          if (narrow) {
            final stackFilters = constraints.maxWidth < 410;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: 14),
                if (stackFilters) ...[
                  departmentField,
                  const SizedBox(height: 12),
                  statusField,
                ] else
                  Row(
                    children: [
                      Expanded(child: departmentField),
                      const SizedBox(width: 12),
                      Expanded(child: statusField),
                    ],
                  ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: modeField),
                    const SizedBox(width: 12),
                    reset,
                  ],
                ),
              ],
            );
          }
          final fields = [
            SizedBox(width: 430, child: search),
            departmentField,
            statusField,
            modeField,
            reset,
          ];
          return Wrap(
            spacing: 26,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: fields,
          );
        },
      ),
    );
  }

  void _openMobileFilters(BuildContext context) {
    var selectedDepartment = department;
    var selectedStatus = status;
    var selectedMode = workMode;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD8E1F0),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Filter employees',
                  style: TextStyle(
                    color: HrmsColors.navy,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                _FilterDropdown(
                  label: 'Department',
                  value: selectedDepartment,
                  values: ['All Departments', ...departmentOptions],
                  onChanged: (value) {
                    if (value == null) return;
                    setSheetState(() => selectedDepartment = value);
                    onDepartment(value);
                  },
                ),
                const SizedBox(height: 12),
                _FilterDropdown(
                  label: 'Status',
                  value: selectedStatus,
                  values: const [
                    'All Status',
                    'Active',
                    'On Leave',
                    'Inactive',
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setSheetState(() => selectedStatus = value);
                    onStatus(value);
                  },
                ),
                const SizedBox(height: 12),
                _FilterDropdown(
                  label: 'Work Mode',
                  value: selectedMode,
                  values: const ['All Work Modes', 'Office', 'Field', 'Hybrid'],
                  onChanged: (value) {
                    if (value == null) return;
                    setSheetState(() => selectedMode = value);
                    onMode(value);
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          onReset();
                          Navigator.pop(sheetContext);
                        },
                        child: const Text('Reset'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('Apply filters'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileFilterChip extends StatelessWidget {
  const _MobileFilterChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ActionChip(
    onPressed: onTap,
    backgroundColor: const Color(0xFFEAF2FF),
    side: BorderSide.none,
    avatar: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF50649E)),
    label: Text(
      label,
      style: const TextStyle(color: HrmsColors.navy, fontSize: 13),
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  );
}

InputDecoration _inputDecoration(String hint, IconData icon) => InputDecoration(
  hintText: hint,
  hintStyle: const TextStyle(color: Color(0xFF50649E), fontSize: 14),
  prefixIcon: Icon(icon, color: HrmsColors.navy),
  filled: true,
  fillColor: Colors.white,
  contentPadding: const EdgeInsets.symmetric(vertical: 18),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: HrmsColors.line),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: HrmsColors.blue),
  ),
);

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });
  final String label, value;
  final List<String> values;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: MediaQuery.sizeOf(context).width < 600 ? double.infinity : 250,
    child: DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      onChanged: onChanged,
      decoration: _inputDecoration('', Icons.filter_alt_outlined).copyWith(
        hintText: null,
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      ),
      items: values
          .map(
            (item) => DropdownMenuItem(
              value: item,
              child: Text(item, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
    ),
  );
}

class _EmployeeTable extends StatelessWidget {
  const _EmployeeTable({
    required this.employees,
    this.selectedProfileId,
    required this.total,
    required this.currentPage,
    required this.totalPages,
    required this.pageSize,
    required this.mobile,
    required this.onPageChanged,
    required this.onView,
    required this.onOpenDetails,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });
  final List<_Employee> employees;
  final int? selectedProfileId;
  final int total, currentPage, totalPages, pageSize;
  final bool mobile;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<_Employee> onView,
      onOpenDetails,
      onEdit,
      onToggle,
      onDelete;

  @override
  Widget build(BuildContext context) => mobile
      ? _MobileEmployeeList(
          employees: employees,
          total: total,
          currentPage: currentPage,
          totalPages: totalPages,
          onPageChanged: onPageChanged,
          onView: onView,
          onEdit: onEdit,
          onToggle: onToggle,
          onDelete: onDelete,
        )
      : Container(
          decoration: BoxDecoration(
            color: AdminSurfacePalette.of(context).surface,
            border: Border.all(color: AdminSurfacePalette.of(context).border),
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0B071A72),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tableWidth = constraints.maxWidth > 875
                  ? constraints.maxWidth
                  : 875.0;
              final tableScale = tableWidth / 875;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: tableWidth,
                        child: Column(
                          children: [
                            _TableHeader(scale: tableScale),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, bodyConstraints) {
                                  final rowHeight =
                                      (bodyConstraints.maxHeight / pageSize)
                                          .clamp(38.0, double.infinity);
                                  return AnimatedSwitcher(
                                    duration:
                                        MediaQuery.disableAnimationsOf(context)
                                        ? Duration.zero
                                        : const Duration(milliseconds: 300),
                                    layoutBuilder:
                                        (currentChild, previousChildren) =>
                                            Stack(
                                              alignment: Alignment.topCenter,
                                              children: [
                                                ...previousChildren,
                                                if (currentChild != null)
                                                  currentChild,
                                              ],
                                            ),
                                    transitionBuilder: (child, animation) =>
                                        FadeTransition(
                                          opacity: animation,
                                          child: SlideTransition(
                                            position:
                                                Tween<Offset>(
                                                  begin: const Offset(0.02, 0),
                                                  end: Offset.zero,
                                                ).animate(
                                                  CurvedAnimation(
                                                    parent: animation,
                                                    curve: Curves.easeOut,
                                                  ),
                                                ),
                                            child: child,
                                          ),
                                        ),
                                    child: SingleChildScrollView(
                                      key: ValueKey(
                                        employees
                                            .map(
                                              (employee) => employee.profileId,
                                            )
                                            .join(','),
                                      ),
                                      child: Column(
                                        children: [
                                          if (employees.isEmpty)
                                            const SizedBox(
                                              height: 170,
                                              child: Center(
                                                child: Text(
                                                  'No employees match these filters.',
                                                ),
                                              ),
                                            )
                                          else
                                            ...employees.indexed.map(
                                              (entry) => _EmployeeRow(
                                                number:
                                                    (currentPage - 1) *
                                                        pageSize +
                                                    entry.$1 +
                                                    1,
                                                employee: entry.$2,
                                                selected:
                                                    entry.$2.profileId ==
                                                    selectedProfileId,
                                                onView: () => onView(entry.$2),
                                                onOpenDetails: () =>
                                                    onOpenDetails(entry.$2),
                                                onEdit: () => onEdit(entry.$2),
                                                onToggle: () =>
                                                    onToggle(entry.$2),
                                                onDelete: () =>
                                                    onDelete(entry.$2),
                                                scale: tableScale,
                                                height: rowHeight,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Text(
                          _showingText(),
                          style: const TextStyle(
                            color: Color(0xFF50649E),
                            fontSize: 13,
                          ),
                        ),
                        const Spacer(),
                        _PageButton(
                          icon: Icons.chevron_left_rounded,
                          enabled: currentPage > 1,
                          onTap: () => onPageChanged(currentPage - 1),
                        ),
                        ..._visiblePages().map(
                          (page) => page == 0
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 10),
                                  child: Text('...'),
                                )
                              : _PageButton(
                                  text: '$page',
                                  active: page == currentPage,
                                  onTap: () => onPageChanged(page),
                                ),
                        ),
                        _PageButton(
                          icon: Icons.chevron_right_rounded,
                          enabled: currentPage < totalPages,
                          onTap: () => onPageChanged(currentPage + 1),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );

  String _showingText() {
    if (total == 0) return 'Showing 0 of 0 employees';
    final first = (currentPage - 1) * pageSize + 1;
    final last = (first + employees.length - 1).clamp(0, total).toInt();
    return 'Showing $first–$last of $total employees';
  }

  List<int> _visiblePages() {
    if (totalPages <= 5) {
      return List.generate(totalPages, (index) => index + 1);
    }
    if (currentPage <= 3) return [1, 2, 3, 0, totalPages];
    if (currentPage >= totalPages - 2) {
      return [1, 0, totalPages - 2, totalPages - 1, totalPages];
    }
    return [1, 0, currentPage, 0, totalPages];
  }
}

class _MobileEmployeeList extends StatelessWidget {
  const _MobileEmployeeList({
    required this.employees,
    required this.total,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
    required this.onView,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });
  final List<_Employee> employees;
  final int total;
  final int currentPage, totalPages;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<_Employee> onView, onEdit, onToggle, onDelete;

  @override
  Widget build(BuildContext context) {
    if (employees.isEmpty) {
      return const SizedBox(
        height: 160,
        child: Center(child: Text('No employees match these filters.')),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: AdminSurfacePalette.of(context).surface,
        border: Border.all(color: AdminSurfacePalette.of(context).border),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08071A72),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Employees ($total)',
                    style: const TextStyle(
                      color: HrmsColors.navy,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const _MobileEmployeeHeader(),
          ...employees.map(
            (employee) => _CompactMobileEmployeeRow(
              employee: employee,
              onView: () => onView(employee),
              onEdit: () => onEdit(employee),
              onToggle: () => onToggle(employee),
              onDelete: () => onDelete(employee),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Page $currentPage of $totalPages',
                    style: const TextStyle(color: Color(0xFF50649E)),
                  ),
                ),
                IconButton(
                  tooltip: 'Previous page',
                  onPressed: currentPage > 1
                      ? () => onPageChanged(currentPage - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: 'Next page',
                  onPressed: currentPage < totalPages
                      ? () => onPageChanged(currentPage + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileEmployeeHeader extends StatelessWidget {
  const _MobileEmployeeHeader();
  @override
  Widget build(BuildContext context) => Container(
    height: 38,
    color: const Color(0xFFF6F8FC),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: const Row(
      children: [
        Expanded(
          flex: 4,
          child: Text(
            'EMPLOYEE',
            style: TextStyle(
              color: Color(0xFF657087),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            'DEPARTMENT',
            style: TextStyle(
              color: Color(0xFF657087),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            'STATUS',
            style: TextStyle(
              color: Color(0xFF657087),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(width: 24),
      ],
    ),
  );
}

class _CompactMobileEmployeeRow extends StatelessWidget {
  const _CompactMobileEmployeeRow({
    required this.employee,
    required this.onView,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });
  final _Employee employee;
  final VoidCallback onView, onEdit, onToggle, onDelete;

  @override
  Widget build(BuildContext context) => Container(
    height: 66,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFFE5EAF3))),
    ),
    child: Row(
      children: [
        Expanded(
          flex: 4,
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFEAF1FF),
                child: Text(
                  employee.name.isEmpty ? '?' : employee.name[0].toUpperCase(),
                  style: const TextStyle(
                    color: HrmsColors.navy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: onView,
                      child: Text(
                        employee.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: HrmsColors.blue,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      employee.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF657087),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            employee.department,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF50649E), fontSize: 11),
          ),
        ),
        Expanded(
          flex: 2,
          child: FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: _StatusBadge(status: employee.status),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'Employee actions',
          padding: EdgeInsets.zero,
          icon: const Icon(
            Icons.more_vert_rounded,
            color: HrmsColors.navy,
            size: 21,
          ),
          onSelected: (value) {
            if (value == 'view') onView();
            if (value == 'edit') onEdit();
            if (value == 'toggle') onToggle();
            if (value == 'delete') onDelete();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'view', child: Text('View employee')),
            const PopupMenuItem(value: 'edit', child: Text('Edit employee')),
            PopupMenuItem(
              value: 'toggle',
              child: Text(
                employee.status == 'Inactive' ? 'Reactivate' : 'Deactivate',
              ),
            ),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ],
    ),
  );
}

class _MobileEmployeeDetail extends StatelessWidget {
  const _MobileEmployeeDetail({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F8FE),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Icon(icon, color: HrmsColors.blue, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Color(0xFF657087), fontSize: 9),
              ),
              Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: HrmsColors.navy,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.scale});
  final double scale;
  @override
  Widget build(BuildContext context) => Container(
    color: AdminSurfacePalette.of(context).subtleSurface,
    child: SizedBox(
      height: 38,
      child: Row(
        children: [
          for (final col in <(String, double)>[
            ('#', 40),
            ('Employee Name', 155),
            ('Designation', 105),
            ('Department', 95),
            ('Contact', 75),
            ('Work Mode', 100),
            ('Status', 70),
            ('Joining Date', 85),
            ('Actions', 120),
          ])
            _TableCell(
              width: col.$2 * scale,
              child: Center(
                child: Text(
                  col.$1,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AdminSurfacePalette.of(context).text,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _EmployeeRow extends StatelessWidget {
  const _EmployeeRow({
    required this.employee,
    required this.number,
    this.selected = false,
    required this.onView,
    required this.onOpenDetails,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    required this.scale,
    required this.height,
  });
  final _Employee employee;
  final int number;
  final bool selected;
  final VoidCallback onView, onOpenDetails, onEdit, onToggle, onDelete;
  final double scale;
  final double height;

  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? const Color(0xFFE8F3FF)
        : AdminSurfacePalette.of(context).surface,
    child: InkWell(
      onTap: onView,
      child: Container(
        height: height,
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFE8EBF2))),
        ),
        child: Row(
          children: [
            _TableCell(
              width: 40 * scale,
              child: Text(
                '$number',
                textAlign: TextAlign.center,
                style: _cellStyle,
              ),
            ),
            _TableCell(
              width: 155 * scale,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: const Color(0xFFEAF0FA),
                    child: Text(
                      employee.name.isEmpty
                          ? '?'
                          : employee.name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: HrmsColors.navy,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        InkWell(
                          onTap: onOpenDetails,
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              employee.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: HrmsColors.blue,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.underline,
                                decorationColor: HrmsColors.blue,
                              ),
                            ),
                          ),
                        ),
                        if (employee.username.isNotEmpty)
                          Text(
                            employee.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
            _TableCell(
              width: 105 * scale,
              child: Text(
                employee.designation,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _cellStyle,
              ),
            ),
            _TableCell(
              width: 95 * scale,
              child: Text(
                employee.department,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _cellStyle,
              ),
            ),
            _TableCell(
              width: 75 * scale,
              child: Text(
                employee.phone.isEmpty ? '—' : employee.phone,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _cellStyle,
              ),
            ),
            _TableCell(
              width: 100 * scale,
              child: Text(
                employee.workMode,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _cellStyle,
              ),
            ),
            _TableCell(
              width: 70 * scale,
              child: Align(
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: _StatusBadge(status: employee.status),
                ),
              ),
            ),
            _TableCell(
              width: 85 * scale,
              child: Text(
                employee.joiningDate,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _cellStyle,
              ),
            ),
            SizedBox(
              width: 120 * scale,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Edit employee',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 17),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Employee actions',
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    onSelected: (value) {
                      if (value == 'toggle') onToggle();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(
                          employee.status == 'Active'
                              ? 'Mark inactive'
                              : 'Mark active',
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete employee'),
                      ),
                    ],
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

class _TableCell extends StatelessWidget {
  const _TableCell({required this.width, required this.child});
  final double width;
  final Widget child;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: child,
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final active = status == 'Active';
    final inactive = status == 'Inactive';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFFEAF6E6)
            : inactive
            ? const Color(0xFFFFE4E6)
            : const Color(0xFFFFF0E4),
        border: Border.all(
          color: active ? const Color(0xFFD2EACB) : const Color(0xFFFFCFA9),
        ),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: active
              ? const Color(0xFF177020)
              : inactive
              ? const Color(0xFFD00019)
              : const Color(0xFFFF6500),
          fontSize: 13,
        ),
      ),
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    this.text,
    this.icon,
    this.active = false,
    this.enabled = true,
    this.onTap,
  });
  final String? text;
  final IconData? icon;
  final bool active;
  final bool enabled;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 8),
    child: InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 34,
        height: 32,
        decoration: BoxDecoration(
          color: active ? HrmsColors.blue : Colors.white,
          border: Border.all(
            color: active ? HrmsColors.blue : const Color(0xFFE1E6F0),
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: icon != null
            ? Icon(
                icon,
                color: enabled ? HrmsColors.navy : const Color(0xFFA9B0C0),
              )
            : Text(
                text!,
                style: TextStyle(
                  color: active ? Colors.white : HrmsColors.navy,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    ),
  );
}

Future<void> _resetEmployeePassword(
  BuildContext context,
  _Employee employee,
) async {
  final password = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Reset password for ${employee.name}'),
      content: TextField(
        controller: password,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: 'New password (minimum 8 characters)',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(password.text.length >= 8),
          child: const Text('Reset password'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await HrmsEmployeesApi.resetPassword(employee.profileId, password.text);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Password reset'),
        content: SelectableText(
          'Username: ${employee.username}\nNew password: ${password.text}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  } catch (error) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
  }
}

class _EmployeeSidePanel extends StatefulWidget {
  const _EmployeeSidePanel({
    required this.employee,
    required this.onClose,
    required this.onOpenDetails,
    required this.onOpenPayroll,
    required this.onResetPassword,
    required this.onEdit,
    required this.onDelete,
  });

  final _Employee employee;
  final VoidCallback onClose;
  final VoidCallback onOpenDetails;
  final VoidCallback onOpenPayroll;
  final VoidCallback onResetPassword;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_EmployeeSidePanel> createState() => _EmployeeSidePanelState();
}

class _EmployeeSidePanelState extends State<_EmployeeSidePanel> {
  int selectedTab = 0;
  _Employee get employee => widget.employee;
  VoidCallback get onClose => widget.onClose;
  VoidCallback get onOpenDetails => widget.onOpenDetails;
  VoidCallback get onOpenPayroll => widget.onOpenPayroll;
  VoidCallback get onResetPassword => widget.onResetPassword;
  VoidCallback get onEdit => widget.onEdit;
  VoidCallback get onDelete => widget.onDelete;

  @override
  void didUpdateWidget(covariant _EmployeeSidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.employee.profileId != widget.employee.profileId)
      selectedTab = 0;
  }

  @override
  Widget build(BuildContext context) {
    final initials = employee.name.trim().isEmpty
        ? '?'
        : employee.name.trim().substring(0, 1).toUpperCase();

    return Container(
      decoration: BoxDecoration(
        color: AdminSurfacePalette.of(context).surface,
        border: Border.all(color: AdminSurfacePalette.of(context).border),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Employee Details',
                                  style: TextStyle(
                                    color: HrmsColors.navy,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Close profile',
                                onPressed: onClose,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                  width: 32,
                                  height: 32,
                                ),
                                icon: const Icon(
                                  Icons.close,
                                  color: HrmsColors.navy,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                radius: 25,
                                backgroundColor: const Color(0xFFE8EEF7),
                                child: Text(
                                  initials,
                                  style: const TextStyle(
                                    color: HrmsColors.navy,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 4,
                                      runSpacing: 2,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          employee.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: HrmsColors.navy,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _StatusBadge(
                                              status: employee.status,
                                            ),
                                            SizedBox(
                                              width: 32,
                                              height: 36,
                                              child: PopupMenuButton<String>(
                                                tooltip:
                                                    'More employee actions',
                                                padding: EdgeInsets.zero,
                                                icon: const Icon(
                                                  Icons.more_vert,
                                                  color: HrmsColors.navy,
                                                ),
                                                onSelected: (action) {
                                                  if (action == 'password')
                                                    onResetPassword();
                                                  if (action == 'delete')
                                                    onDelete();
                                                },
                                                itemBuilder: (_) => const [
                                                  PopupMenuItem(
                                                    value: 'password',
                                                    child: Text(
                                                      'Reset password',
                                                    ),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 'delete',
                                                    child: Text(
                                                      'Delete employee',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      [employee.id, employee.designation]
                                          .where(
                                            (value) =>
                                                value.trim().isNotEmpty &&
                                                value.trim() != '-',
                                          )
                                          .join('  •  '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF687A98),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 112,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    FilledButton.icon(
                                      onPressed: onOpenDetails,
                                      icon: const Icon(
                                        Icons.person_outline,
                                        size: 15,
                                      ),
                                      label: const Text('View profile'),
                                      style: FilledButton.styleFrom(
                                        minimumSize: const Size(0, 32),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        textStyle: const TextStyle(
                                          fontSize: 11,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    OutlinedButton.icon(
                                      onPressed: onEdit,
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 15,
                                      ),
                                      label: const Text('Edit'),
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(0, 32),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                        textStyle: const TextStyle(
                                          fontSize: 11,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Divider(height: 1),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              for (final entry in [
                                'Overview',
                                'Personal',
                                'Employment',
                                'Payroll',
                                'Documents',
                              ].indexed)
                                _tab(entry.$2, index: entry.$1),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (selectedTab == 0 || selectedTab == 1)
                            _profileSection(
                              _EmployeeDetailSection(
                                title: 'Contact Information',
                                fillHeight: selectedTab == 0,
                                children: [
                                  _detailLine(
                                    'Email',
                                    employee.email.isEmpty
                                        ? '-'
                                        : employee.email,
                                  ),
                                  _detailLine(
                                    'Phone',
                                    employee.phone.isEmpty
                                        ? '-'
                                        : employee.phone,
                                  ),
                                  _detailLine(
                                    'Username',
                                    employee.username.isEmpty
                                        ? '-'
                                        : employee.username,
                                  ),
                                  _detailLine('Work mode', employee.workMode),
                                  _detailLine(
                                    'Employee type',
                                    employee.employeeType,
                                  ),
                                ],
                              ),
                            ),
                          if (selectedTab == 0) const SizedBox(height: 8),
                          if (selectedTab == 0 || selectedTab == 2)
                            _profileSection(
                              _EmployeeDetailSection(
                                title: 'Employment Details',
                                fillHeight: selectedTab == 0,
                                children: [
                                  _detailLine('Employee ID', employee.id),
                                  _detailLine(
                                    'Department',
                                    employee.department,
                                  ),
                                  _detailLine('Salary', employee.salary),
                                  _detailLine(
                                    'Salary type',
                                    employee.salaryType,
                                  ),
                                  _detailLine(
                                    'Joining date',
                                    employee.joiningDate,
                                  ),
                                  _detailLine(
                                    'Weekly off template',
                                    employee.weeklyOffTemplate,
                                  ),
                                ],
                              ),
                            ),
                          if (selectedTab == 3)
                            _EmployeeDetailSection(
                              title: 'Payroll',
                              children: [
                                _detailLine('Salary', employee.salary),
                                _detailLine('Salary type', employee.salaryType),
                                _detailLine(
                                  'Weekly off template',
                                  employee.weeklyOffTemplate,
                                ),
                                TextButton(
                                  onPressed: onOpenPayroll,
                                  child: const Text('View payroll history'),
                                ),
                              ],
                            ),
                          if (selectedTab == 4)
                            const _EmployeeDetailSection(
                              title: 'Documents',
                              children: [
                                Text(
                                  'Employee documents are not available yet.',
                                ),
                              ],
                            ),
                        ],
                      ),
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

  Widget _profileSection(Widget child) =>
      selectedTab == 0 ? Expanded(child: child) : child;

  Widget _detailLine(String label, String value) =>
      _EmployeeDetailLine(label, value, spacious: selectedTab != 0);

  Widget _tab(String label, {required int index}) {
    final active = selectedTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => selectedTab = index),
        child: Column(
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: active ? HrmsColors.blue : HrmsColors.navy,
                fontSize: 11,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 2,
              color: active ? HrmsColors.blue : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmployeeDetailPage extends StatefulWidget {
  const _EmployeeDetailPage({required this.employee, this.initialTab = 0});
  final _Employee employee;
  final int initialTab;

  @override
  State<_EmployeeDetailPage> createState() => _EmployeeDetailPageState();
}

class _EmployeeDetailPageState extends State<_EmployeeDetailPage> {
  late Future<Map<String, dynamic>> _detail;
  late int _selectedTab;

  String _money(dynamic value) {
    final amount = value is num ? value : num.tryParse('$value');
    if (amount == null) return '₹0';
    return '₹${amount.round().toString().replaceAllMapped(RegExp(r'(?<=\d)(?=(\d{3})+$)'), (_) => ',')}';
  }

  List<Map<String, dynamic>> _rows(dynamic value) =>
      (value as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

  Widget _detailTable({
    required List<String> headers,
    required List<List<Widget>> rows,
    required String emptyMessage,
  }) {
    if (rows.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 46),
        alignment: Alignment.center,
        child: Text(
          emptyMessage,
          style: const TextStyle(color: Color(0xFF8795AD)),
        ),
      );
    }
    final headerStyle = const TextStyle(
      color: Color(0xFF71819C),
      fontSize: 11,
      fontWeight: FontWeight.w700,
    );
    return Table(
      border: TableBorder.symmetric(
        inside: const BorderSide(color: Color(0xFFE5EAF2)),
        outside: const BorderSide(color: Color(0xFFE0E6EF)),
      ),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFFF7F9FD)),
          children: headers
              .map(
                (header) => Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(header, style: headerStyle),
                ),
              )
              .toList(),
        ),
        ...rows.map(
          (cells) => TableRow(
            children: cells
                .map(
                  (cell) =>
                      Padding(padding: const EdgeInsets.all(10), child: cell),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _tableText(
    dynamic value, {
    Color color = HrmsColors.navy,
    FontWeight weight = FontWeight.w500,
  }) => Text(
    '${value ?? '-'}',
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(color: color, fontSize: 12, fontWeight: weight),
  );

  Widget _statusCell(dynamic value) {
    final status = '${value ?? '-'}';
    final lower = status.toLowerCase();
    final color = lower == 'present' || lower == 'approved' || lower == 'paid'
        ? const Color(0xFF177020)
        : lower == 'absent' || lower == 'rejected'
        ? const Color(0xFFD92929)
        : const Color(0xFFB55B00);
    return Text(
      status,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
    );
  }

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    _detail = HrmsEmployeesApi.detail(widget.employee.profileId);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    appBar: AppBar(
      title: const Text('Employee details'),
      backgroundColor: Colors.white,
      foregroundColor: HrmsColors.navy,
      elevation: 0,
    ),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _detail,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: FilledButton.icon(
              onPressed: () => setState(
                () => _detail = HrmsEmployeesApi.detail(
                  widget.employee.profileId,
                ),
              ),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry loading employee details'),
            ),
          );
        }
        final data = snapshot.data ?? const <String, dynamic>{};
        final attendance = Map<String, dynamic>.from(
          data['attendance'] as Map? ?? {},
        );
        final leave = Map<String, dynamic>.from(data['leave'] as Map? ?? {});
        final payroll = data['payroll'] is Map
            ? Map<String, dynamic>.from(data['payroll'] as Map)
            : null;
        final attendanceRows = _rows(data['attendanceRows']);
        final leaveRows = _rows(data['leaveRows']);
        final permissionRows = _rows(data['permissionRows']);
        final payrollHistory = _rows(data['payrollHistory']);
        return LayoutBuilder(
          builder: (context, constraints) {
            // Desktop profiles show every key metric together.  Narrow
            // screens fall back to a readable grid instead of squeezing text.
            final metricColumns = constraints.maxWidth >= 1180
                ? 8
                : constraints.maxWidth >= 980
                ? 4
                : constraints.maxWidth >= 620
                ? 2
                : 1;
            // Keep a small safety gap so all eight cards remain on one line
            // even when the page has a scrollbar or a fractional layout width.
            final metricWidth =
                (constraints.maxWidth - ((metricColumns - 1) * 20)) /
                metricColumns;
            final tabContent = _selectedTab == 0
                ? _detailTable(
                    headers: const [
                      'Date',
                      'Check in',
                      'Check out',
                      'Worked',
                      'Break start',
                      'Break end',
                      'Break',
                      'Status',
                      'LOP',
                      'Method',
                      'Clock out reason',
                      'Tracking stop reason',
                    ],
                    emptyMessage: 'No attendance records for this month.',
                    rows: attendanceRows
                        .map(
                          (row) => [
                            _tableText(
                              row['date'],
                              color: HrmsColors.blue,
                              weight: FontWeight.w700,
                            ),
                            _tableText(row['check_in']),
                            _tableText(row['check_out']),
                            _tableText(row['worked']),
                            _tableText(row['break_start']),
                            _tableText(row['break_end']),
                            _tableText(row['break_duration']),
                            _statusCell(row['status']),
                            _statusCell(row['lop']),
                            _tableText(row['method']),
                            _tableText(row['clock_out_reason']),
                            _tableText(row['tracking_stop_reason']),
                          ],
                        )
                        .toList(),
                  )
                : _selectedTab == 1
                ? _detailTable(
                    headers: const [
                      'Type',
                      'From',
                      'To',
                      'Days',
                      'Reason',
                      'Status',
                    ],
                    emptyMessage:
                        'No leave or permission records for this month.',
                    rows: [
                      ...leaveRows.map(
                        (row) => [
                          _tableText(row['leave_type']),
                          _tableText(row['from_date']),
                          _tableText(row['to_date']),
                          _tableText(row['days_count']),
                          _tableText(row['reason']),
                          _statusCell(row['status']),
                        ],
                      ),
                      ...permissionRows.map(
                        (row) => [
                          _tableText(row['request_type']),
                          _tableText(row['request_date']),
                          _tableText(row['request_date']),
                          _tableText('-'),
                          _tableText(row['reason']),
                          _statusCell(row['status']),
                        ],
                      ),
                    ],
                  )
                : _detailTable(
                    headers: const [
                      'Month',
                      'Salary',
                      'Working',
                      'Paid',
                      'LOP',
                      'Late deduction',
                      'Absent / LOP',
                      'Total deduction',
                      'Net pay',
                      'Status',
                    ],
                    emptyMessage: 'No payroll history is available.',
                    rows: payrollHistory
                        .map(
                          (row) => [
                            _tableText(
                              row['month'],
                              color: HrmsColors.blue,
                              weight: FontWeight.w700,
                            ),
                            _tableText(_money(row['salary'])),
                            _tableText(row['workingDays']),
                            _tableText(row['paidDays']),
                            _tableText(row['lopDays']),
                            _tableText(_money(row['lateDeduction'])),
                            _tableText(_money(row['absentDeduction'])),
                            _tableText(_money(row['totalDeduction'])),
                            _tableText(
                              _money(row['netPay']),
                              color: HrmsColors.blue,
                              weight: FontWeight.w800,
                            ),
                            _statusCell(row['status']),
                          ],
                        )
                        .toList(),
                  );
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1860),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _EmployeeDetailHero(employee: widget.employee),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _EmployeeDetailMetric(
                            'Working',
                            '${payroll?['workingDays'] ?? 0}',
                            Icons.calendar_month_outlined,
                            HrmsColors.blue,
                            width: metricWidth,
                          ),
                          _EmployeeDetailMetric(
                            'Paid',
                            '${payroll?['paidDays'] ?? 0}',
                            Icons.check_circle_outline,
                            const Color(0xFF158C20),
                            width: metricWidth,
                          ),
                          _EmployeeDetailMetric(
                            'Present',
                            '${attendance['present'] ?? 0}',
                            Icons.check_circle_outline,
                            const Color(0xFF158C20),
                            width: metricWidth,
                          ),
                          _EmployeeDetailMetric(
                            'Late',
                            '${attendance['late'] ?? 0}',
                            Icons.access_time_rounded,
                            const Color(0xFFFF7A00),
                            width: metricWidth,
                          ),
                          _EmployeeDetailMetric(
                            'Absent',
                            '${attendance['absent'] ?? 0}',
                            Icons.person_off_outlined,
                            const Color(0xFFD92929),
                            width: metricWidth,
                          ),
                          _EmployeeDetailMetric(
                            'LOP',
                            '${payroll?['lopDays'] ?? 0}',
                            Icons.money_off_csred_outlined,
                            const Color(0xFFD92929),
                            width: metricWidth,
                          ),
                          _EmployeeDetailMetric(
                            'Net pay',
                            _money(payroll?['netPay']),
                            Icons.account_balance_wallet_outlined,
                            HrmsColors.navy,
                            width: metricWidth,
                          ),
                          _EmployeeDetailMetric(
                            'Payroll',
                            '${payroll?['status'] ?? 'Not generated'}',
                            Icons.payments_outlined,
                            const Color(0xFFFF6500),
                            width: metricWidth,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Container(
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Color(0xFFDDE4EF)),
                          ),
                        ),
                        child: Row(
                          children: List.generate(3, (index) {
                            final labels = [
                              'Attendance',
                              'Leaves & Permissions',
                              'Payroll History',
                            ];
                            final selected = _selectedTab == index;
                            return Expanded(
                              child: InkWell(
                                onTap: () =>
                                    setState(() => _selectedTab = index),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        labels[index],
                                        style: TextStyle(
                                          color: selected
                                              ? HrmsColors.blue
                                              : const Color(0xFF7B8AA5),
                                          fontWeight: selected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 9),
                                      Container(
                                        height: 3,
                                        width: 96,
                                        color: selected
                                            ? HrmsColors.blue
                                            : Colors.transparent,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _selectedTab == 0
                            ? 'Daily attendance'
                            : _selectedTab == 1
                            ? 'Leaves & permissions'
                            : 'Payroll history',
                        style: const TextStyle(
                          color: HrmsColors.navy,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      tabContent,
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}

class _EmployeeDetailMetric extends StatelessWidget {
  const _EmployeeDetailMetric(
    this.label,
    this.value,
    this.icon,
    this.color, {
    required this.width,
  });
  final String label, value;
  final IconData icon;
  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: 106,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE4F1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080D254A),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF657087), fontSize: 11),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );
}

class _EmployeeDetailHero extends StatelessWidget {
  const _EmployeeDetailHero({required this.employee});

  final _Employee employee;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFDCE4F1)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x080D254A),
          blurRadius: 14,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 14,
      spacing: 18,
      children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: const Color(0xFFEAF0FA),
          child: Text(
            employee.name.isEmpty
                ? '?'
                : employee.name.substring(0, 1).toUpperCase(),
            style: const TextStyle(
              color: HrmsColors.blue,
              fontWeight: FontWeight.w800,
              fontSize: 25,
            ),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                employee.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: HrmsColors.navy,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                employee.designation,
                style: const TextStyle(color: Color(0xFF657087), fontSize: 14),
              ),
            ],
          ),
        ),
        _EmployeeDetailFact(Icons.badge_outlined, 'Employee ID', employee.id),
        _EmployeeDetailFact(
          Icons.apartment_outlined,
          'Department',
          employee.department,
        ),
        _EmployeeDetailFact(
          Icons.location_on_outlined,
          'Work mode',
          employee.workMode,
        ),
        _StatusBadge(status: employee.status),
      ],
    ),
  );
}

class _EmployeeDetailFact extends StatelessWidget {
  const _EmployeeDetailFact(this.icon, this.label, this.value);

  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 130, maxWidth: 190),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F9FD),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: HrmsColors.blue, size: 17),
        const SizedBox(width: 7),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Color(0xFF71819C), fontSize: 11),
              ),
              Text(
                value.isEmpty ? '–' : value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: HrmsColors.navy,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _EmployeeDetailSection extends StatelessWidget {
  const _EmployeeDetailSection({
    required this.title,
    required this.children,
    this.fillHeight = false,
  });
  final String title;
  final List<Widget> children;
  final bool fillHeight;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE3E8F2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: fillHeight
          ? MainAxisAlignment.spaceEvenly
          : MainAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: HrmsColors.navy,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        ...children,
      ],
    ),
  );
}

class _EmployeeDetailLine extends StatelessWidget {
  const _EmployeeDetailLine(this.label, this.value, {this.spacious = false});
  final String label, value;
  final bool spacious;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: spacious ? 6 : 1),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF657087),
              fontSize: 13,
              height: 1.2,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: HrmsColors.navy,
            fontSize: 13,
            height: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _Employee {
  const _Employee(
    this.profileId,
    this.name,
    this.id,
    this.department,
    this.workMode,
    this.employeeType,
    this.designation,
    this.location,
    this.joiningDate,
    this.overtimeEligible,
    this.gender,
    this.salary,
    this.status,
    this.modeColor,
    this.username,
    this.salaryType,
    this.flexibleCycleStartDay,
    this.flexibleCycleEndDay,
    this.flexibleCycleStartDate,
    this.flexibleCycleEndDate,
    this.passwordLastChangedAt,
    this.weeklyOffTemplate,
    this.email,
    this.phone,
    this.trackingTemplateId,
    this.trackingTemplateName,
  );
  final int profileId;
  final String name,
      id,
      department,
      workMode,
      employeeType,
      designation,
      location,
      joiningDate,
      gender,
      salary,
      status;
  final bool overtimeEligible;
  final int modeColor;
  final String username;
  final String salaryType;
  final int? flexibleCycleStartDay;
  final int? flexibleCycleEndDay;
  final String? flexibleCycleStartDate;
  final String? flexibleCycleEndDate;
  final String? passwordLastChangedAt;
  final String weeklyOffTemplate;
  final String email;
  final String phone;
  final int? trackingTemplateId;
  final String? trackingTemplateName;

  factory _Employee.fromApi(Map<String, dynamic> json) {
    final profileId = json['id'] is int
        ? json['id'] as int
        : int.tryParse('${json['id']}') ?? 0;
    final code = (json['employeeCode'] ?? json['employeeId'] ?? '').toString();
    final mode = (json['workMode'] ?? 'Office').toString();
    final color = json['modeColor'];
    return _Employee(
      profileId,
      (json['name'] ?? '').toString(),
      code,
      (json['department'] ?? '').toString(),
      mode,
      (json['employeeType'] ?? 'Employee').toString(),
      (json['designation'] ?? json['employeeType'] ?? 'Employee').toString(),
      (json['location'] ?? json['workLocation'] ?? '-').toString(),
      (json['joiningDate'] ?? json['dateOfJoining'] ?? '-').toString(),
      json['overtimeEligible'] == true || json['overtimeEligible'] == 1,
      (json['gender'] ?? 'Male').toString(),
      (json['salary'] ?? 'Not Set').toString(),
      (json['status'] ?? 'Active').toString(),
      color is int ? color : _modeColor(mode),
      (json['username'] ?? '').toString(),
      (json['salaryType'] ?? 'Standard').toString(),
      json['flexibleCycleStartDay'] is num
          ? (json['flexibleCycleStartDay'] as num).toInt()
          : int.tryParse('${json['flexibleCycleStartDay'] ?? ''}'),
      json['flexibleCycleEndDay'] is num
          ? (json['flexibleCycleEndDay'] as num).toInt()
          : int.tryParse('${json['flexibleCycleEndDay'] ?? ''}'),
      json['flexibleCycleStartDate']?.toString(),
      json['flexibleCycleEndDate']?.toString(),
      json['passwordLastChangedAt']?.toString(),
      (json['weeklyOffTemplate'] ?? 'Global Payroll Policy').toString(),
      (json['email'] ?? '').toString(),
      (json['phone'] ?? '').toString(),
      json['trackingTemplateId'] is num
          ? (json['trackingTemplateId'] as num).toInt()
          : int.tryParse('${json['trackingTemplateId'] ?? ''}'),
      json['trackingTemplateName']?.toString(),
    );
  }
}

int _modeColor(String mode) => switch (mode) {
  'Hybrid' => 0xFF8B5CF6,
  'Field' => 0xFF16B9C5,
  _ => 0xFF0668F6,
};

const _tableHead = TextStyle(
  color: HrmsColors.navy,
  fontSize: 13,
  fontWeight: FontWeight.w600,
);
const _cellStyle = TextStyle(color: HrmsColors.navy, fontSize: 14);
