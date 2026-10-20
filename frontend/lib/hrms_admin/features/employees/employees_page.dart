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

abstract final class HrmsColors {
  static const blue = Color(0xFFE3162A);
  static const navy = Color(0xFF081B3C);
  static const page = Color(0xFFF5F7FB);
  static const line = Color(0xFFD8E1F1);
}

class EmployeesPage extends StatefulWidget {
  const EmployeesPage({super.key, this.settingsAction, this.inSettingsDialog = false});

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
  // Six compact rows preserve a complete desktop workspace without page scroll.
  static const pageSize = 6;
  Timer? _searchDebounce;

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
    final action = widget.settingsAction ??
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

  Future<void> _loadEmployees() async {
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
      if (!mounted) return;
      setState(() {
        employees = items;
        // Keep the drawer in sync with the API response after an edit. Without
        // this, reopening Edit Employee uses its old Gender/Salary Type values.
        if (refreshedSelectedEmployee != null) {
          _selectedEmployee = refreshedSelectedEmployee;
        } else if (_selectedEmployee == null && items.isNotEmpty) {
          _selectedEmployee = items.first;
        }
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
      if (!mounted) return;
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
    final palette = AdminSurfacePalette.of(context);
    final mobile = MediaQuery.sizeOf(context).width < 600;
    final drawerWidth = MediaQuery.sizeOf(context).width < 1500 ? 390.0 : 450.0;
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
                : SingleChildScrollView(
                    physics: mobile
                        ? const BouncingScrollPhysics()
                        : const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      mobile ? 16 : 34,
                      14,
                      mobile ? 16 : 34,
                      28,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1860),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                            _PageHeader(
                              onExport: _exportEmployees,
                              onAdd: _showEmployeeForm,
                            ),
                            const SizedBox(height: 12),
                            _EmployeeKpis(
                              mobile: mobile,
                              total: kpiTotal,
                              active: kpiActive,
                              onLeave: kpiOnLeave,
                              inactive: kpiInactive,
                            ),
                            const SizedBox(height: 12),
                            _Filters(
                              searchController: searchController,
                              department: department,
                              departmentOptions: departmentOptions,
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
                            ),
                            const SizedBox(height: 10),
                            if (loading)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 12),
                                child: LinearProgressIndicator(minHeight: 2),
                              ),
                            if (mobile)
                              _EmployeeTable(
                                employees: employees,
                                selectedProfileId: _selectedEmployee?.profileId,
                                total: filteredTotal,
                                currentPage: currentPage
                                    .clamp(1, totalPages)
                                    .toInt(),
                                totalPages: totalPages,
                                mobile: true,
                                onPageChanged: (page) {
                                  currentPage = page
                                      .clamp(1, totalPages)
                                      .toInt();
                                  _loadEmployees();
                                },
                                onView: (employee) =>
                                    _showEmployeeDetails(employee),
                                onEdit: (employee) =>
                                    _showEmployeeForm(employee: employee),
                                onToggle: _toggleEmployee,
                                onDelete: _confirmDelete,
                              )
                            else
                              _EmployeeTable(
                                      employees: employees,
                                      selectedProfileId: _selectedEmployee?.profileId,
                                      total: filteredTotal,
                                      currentPage: currentPage
                                          .clamp(1, totalPages)
                                          .toInt(),
                                      totalPages: totalPages,
                                      mobile: false,
                                      onPageChanged: (page) {
                                        currentPage = page
                                            .clamp(1, totalPages)
                                            .toInt();
                                        _loadEmployees();
                                      },
                                      onView: _showEmployeeDetails,
                                      onEdit: (employee) =>
                                          _showEmployeeForm(employee: employee),
                                      onToggle: _toggleEmployee,
                                      onDelete: _confirmDelete,
                                    ),
                                ],
                              ),
                            ),
                            if (!mobile && _selectedEmployee != null) ...[
                              const SizedBox(width: 22),
                              Transform.translate(
                                // Align the drawer with the bottom edge of the
                                // fixed navigation instead of the page heading.
                                offset: const Offset(0, -14),
                                child: SizedBox(
                                  width: drawerWidth,
                                  height: MediaQuery.sizeOf(context).height - 100,
                                  child: _EmployeeSidePanel(
                                    employee: _selectedEmployee!,
                                    onClose: () => setState(() => _selectedEmployee = null),
                                    onOpenDetails: () => _openFullEmployeeDetails(_selectedEmployee!),
                                    onResetPassword: () => _resetEmployeePassword(
                                      context,
                                      _selectedEmployee!,
                                    ),
                                    onEdit: () => _showEmployeeForm(
                                      employee: _selectedEmployee!,
                                    ),
                                    onDelete: () => _confirmDelete(_selectedEmployee!),
                                  ),
                                ),
                              ),
                            ],
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
      final csv = await HrmsEmployeesApi.exportCsv();
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
                color: PdfColor.fromInt(0xFFE3162A),
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
    DateTime joiningDate = DateTime.tryParse(employee?.joiningDate ?? '') ?? cycleToday;
    DateTimeRange? flexibleCycleRange;
    if (employee?.flexibleCycleStartDay != null &&
        employee?.flexibleCycleEndDay != null) {
      final start = DateTime.tryParse(employee?.flexibleCycleStartDate ?? '') ??
          DateTime(cycleToday.year, cycleToday.month, employee!.flexibleCycleStartDay!);
      var end = DateTime.tryParse(employee?.flexibleCycleEndDate ?? '') ??
          DateTime(cycleToday.year, cycleToday.month, employee!.flexibleCycleEndDay!);
      if (end.isBefore(start)) {
        end = DateTime(cycleToday.year, cycleToday.month + 1, employee!.flexibleCycleEndDay!);
      }
      flexibleCycleRange = DateTimeRange(start: start, end: end);
    }
    final username = TextEditingController(text: employee?.username ?? '');
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
      'employeeCode': id.text.trim(),
      'department': selectedDepartment,
      'workMode': selectedMode,
      'employeeType': selectedEmployeeType,
      'overtimeEligible': overtimeEligible,
      'gender': selectedGender,
      'status': selectedStatus,
      'salary': salary.text.trim(),
      'salaryType': selectedSalaryType,
      'joiningDate': '${joiningDate.year.toString().padLeft(4, '0')}-${joiningDate.month.toString().padLeft(2, '0')}-${joiningDate.day.toString().padLeft(2, '0')}',
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
      if (employee == null || password.text.isNotEmpty) 'password': password.text,
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
                        if (picked != null) setDialogState(() => joiningDate = picked);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Joining date',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_month_outlined),
                        ),
                        child: Text(DateFormat('d MMM yyyy').format(joiningDate)),
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
                    _formDropdown('Work mode', selectedMode, const [
                      'Office',
                      'Hybrid',
                      'Field',
                    ], (value) => setDialogState(() => selectedMode = value!)),
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
                          await HrmsEmployeesApi.update(employee.profileId, body);
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
    setState(() => _selectedEmployee = employee);
  }

  Future<void> _openFullEmployeeDetails(_Employee employee) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _EmployeeDetailPage(employee: employee),
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
    await _runAction(() => HrmsEmployeesApi.delete(employee.profileId));
  }
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
        'Across all departments',
        Icons.groups_outlined,
        HrmsColors.blue,
      ),
      _EmployeeKpi(
        'Active',
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
        'Inactive',
        '$inactive',
        _percentage(inactive, total),
        Icons.person_off_outlined,
        const Color(0xFFF0182A),
      ),
    ];
    return LayoutBuilder(
      builder: (_, constraints) {
        final columns = 4;
        final spacing = mobile ? 8.0 : 12.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: mobile ? 8 : 16,
          children: cards
              .map((card) => SizedBox(width: width, child: card))
              .toList(),
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
        height: 80,
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
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: palette.mutedText, fontSize: compact ? 11 : 13)),
                    const SizedBox(height: 3),
                    Text(value, style: TextStyle(color: palette.text, fontSize: compact ? 22 : 25, height: 1, fontWeight: FontWeight.w800)),
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
  final String department, status, workMode;
  final List<String> departmentOptions;
  final ValueChanged<String> onSearch;
  final ValueChanged<String?> onDepartment, onStatus, onMode;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final palette = AdminSurfacePalette.of(context);
    return Container(
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 0 : 8),
    decoration: BoxDecoration(
      color: MediaQuery.sizeOf(context).width < 600
          ? Colors.transparent
          : palette.surface,
      borderRadius: BorderRadius.circular(14),
      boxShadow: MediaQuery.sizeOf(context).width < 600
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
          decoration: _inputDecoration(
            'Search by name, employee ID or email',
            Icons.search_rounded,
          ).copyWith(
            contentPadding: const EdgeInsets.symmetric(vertical: 13),
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
          message: 'Reset filters',
          child: OutlinedButton(
            onPressed: onReset,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              side: const BorderSide(color: Color(0xFFFFA9B3)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            child: const Icon(
              Icons.restart_alt_rounded,
              color: HrmsColors.blue,
            ),
          ),
        );
        final mobile = MediaQuery.sizeOf(context).width < 600;
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
              const SizedBox(width: 10),
              Expanded(flex: 3, child: departmentField),
              const SizedBox(width: 10),
              Expanded(flex: 3, child: statusField),
              const SizedBox(width: 10),
              Expanded(flex: 3, child: modeField),
              const SizedBox(width: 10),
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
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
                value: department,
                values: ['All Departments', ...departmentOptions],
                onChanged: onDepartment,
              ),
              const SizedBox(height: 12),
              _FilterDropdown(
                label: 'Status',
                value: status,
                values: const ['All Status', 'Active', 'On Leave', 'Inactive'],
                onChanged: onStatus,
              ),
              const SizedBox(height: 12),
              _FilterDropdown(
                label: 'Work Mode',
                value: workMode,
                values: const ['All Work Modes', 'Office', 'Field', 'Hybrid'],
                onChanged: onMode,
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
    backgroundColor: const Color(0xFFFFE8EB),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
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
    required this.mobile,
    required this.onPageChanged,
    required this.onView,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });
  final List<_Employee> employees;
  final int? selectedProfileId;
  final int total, currentPage, totalPages;
  final bool mobile;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<_Employee> onView, onEdit, onToggle, onDelete;

  @override
  Widget build(BuildContext context) => mobile
      ? _MobileEmployeeList(
          employees: employees,
          total: total,
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
              final tableWidth = constraints.maxWidth > 800
                  ? constraints.maxWidth
                  : 800.0;
              final tableScale = tableWidth / 800;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: Column(
                    children: [
                      _TableHeader(scale: tableScale),
                      if (employees.isEmpty)
                        const SizedBox(
                          height: 170,
                          child: Center(
                            child: Text('No employees match these filters.'),
                          ),
                        )
                      else
                        ...employees.map(
                          (employee) => _EmployeeRow(
                            employee: employee,
                            selected: employee.profileId == selectedProfileId,
                            onView: () => onView(employee),
                            onEdit: () => onEdit(employee),
                            onToggle: () => onToggle(employee),
                            onDelete: () => onDelete(employee),
                            scale: tableScale,
                          ),
                        ),
                    ],
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
    final first = (currentPage - 1) * _EmployeesPageState.pageSize + 1;
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
    required this.onView,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });
  final List<_Employee> employees;
  final int total;
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
                const Text(
                  'Sort by',
                  style: TextStyle(color: Color(0xFF657087), fontSize: 12),
                ),
                TextButton.icon(
                  onPressed: () {},
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                  label: const Text('Name'),
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
        _TableCell(width: 190 * scale, child: Text('Employee', style: TextStyle(color: AdminSurfacePalette.of(context).text, fontSize: 13, fontWeight: FontWeight.w600))),
        _TableCell(width: 90 * scale, child: Text('Employee ID', style: TextStyle(color: AdminSurfacePalette.of(context).text, fontSize: 13, fontWeight: FontWeight.w600))),
        _TableCell(width: 105 * scale, child: Text('Department', style: TextStyle(color: AdminSurfacePalette.of(context).text, fontSize: 13, fontWeight: FontWeight.w600))),
        _TableCell(width: 120 * scale, child: Text('Designation', style: TextStyle(color: AdminSurfacePalette.of(context).text, fontSize: 13, fontWeight: FontWeight.w600))),
        _TableCell(width: 105 * scale, child: Text('Joining Date', style: TextStyle(color: AdminSurfacePalette.of(context).text, fontSize: 13, fontWeight: FontWeight.w600))),
        _TableCell(width: 120 * scale, child: Text('Status', style: TextStyle(color: AdminSurfacePalette.of(context).text, fontSize: 13, fontWeight: FontWeight.w600))),
      ],
    ),
  ));
}

class _EmployeeRow extends StatelessWidget {
  const _EmployeeRow({
    required this.employee,
    this.selected = false,
    required this.onView,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    required this.scale,
  });
  final _Employee employee;
  final bool selected;
  final VoidCallback onView, onEdit, onToggle, onDelete;
  final double scale;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? const Color(0xFFFDF0F2) : AdminSurfacePalette.of(context).surface,
    child: InkWell(
      onTap: onView,
      child: Container(
        height: 52,
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFE8EBF2))),
        ),
        child: Row(
          children: [
        _TableCell(
          width: 190 * scale,
          child: Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: const Color(0xFFEAF0FA),
                child: Text(
                  employee.name.isEmpty ? '?' : employee.name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(color: HrmsColors.navy, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      employee.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: HrmsColors.navy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (employee.username.isNotEmpty)
                      Text(
                        employee.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF657087), fontSize: 11),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _TableCell(width: 90 * scale, child: Text(employee.id, style: _cellStyle)),
        _TableCell(width: 105 * scale, child: Text(employee.department, maxLines: 1, overflow: TextOverflow.ellipsis, style: _cellStyle)),
        _TableCell(width: 120 * scale, child: Text(employee.designation, maxLines: 1, overflow: TextOverflow.ellipsis, style: _cellStyle)),
        _TableCell(width: 105 * scale, child: Text(employee.joiningDate, maxLines: 1, overflow: TextOverflow.ellipsis, style: _cellStyle)),
        _TableCell(
          width: 120 * scale,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _StatusBadge(status: employee.status),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFEAF6E6) : const Color(0xFFFFF0E4),
        border: Border.all(
          color: active ? const Color(0xFFD2EACB) : const Color(0xFFFFCFA9),
        ),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: active ? const Color(0xFF177020) : const Color(0xFFFF6500),
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

class _EmployeeSidePanel extends StatelessWidget {
  const _EmployeeSidePanel({
    required this.employee,
    required this.onClose,
    required this.onOpenDetails,
    required this.onResetPassword,
    required this.onEdit,
    required this.onDelete,
  });

  final _Employee employee;
  final VoidCallback onClose;
  final VoidCallback onOpenDetails;
  final VoidCallback onResetPassword;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final initials = employee.name.trim().isEmpty
        ? '?'
        : employee.name.trim().substring(0, 1).toUpperCase();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE1E7F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 126),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 40,
                              backgroundColor: const Color(0xFFE8EEF7),
                              child: Text(
                                initials,
                                style: const TextStyle(
                                  color: HrmsColors.navy,
                                  fontSize: 27,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 5,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        employee.name,
                                        style: const TextStyle(
                                          color: HrmsColors.navy,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      _StatusBadge(status: employee.status),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${employee.id}  •  ${employee.designation}',
                                    style: const TextStyle(
                                      color: Color(0xFF687A98),
                                    ),
                                  ),
                                  Text(
                                    '${employee.department}  •  ${employee.location}',
                                    style: const TextStyle(
                                      color: Color(0xFF687A98),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 34,
                        child: PopupMenuButton<String>(
                          tooltip: 'Employee actions',
                          onSelected: (action) {
                            if (action == 'profile') onOpenDetails();
                            if (action == 'password') onResetPassword();
                            if (action == 'edit') onEdit();
                            if (action == 'delete') onDelete();
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'profile',
                              child: Text('View profile'),
                            ),
                            PopupMenuItem(
                              value: 'password',
                              child: Text('Reset password'),
                            ),
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit employee'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete employee'),
                            ),
                          ],
                          child: Container(
                            height: 30,
                            padding: const EdgeInsets.symmetric(horizontal: 9),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFDF0F2),
                              border: Border.all(color: HrmsColors.blue),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.more_horiz_rounded,
                                  size: 17,
                                  color: HrmsColors.blue,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Actions',
                                  style: TextStyle(
                                    color: HrmsColors.blue,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: IconButton(
                          onPressed: onClose,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 28,
                            height: 28,
                          ),
                          icon: const Icon(Icons.close, color: HrmsColors.navy),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _tab('Overview', active: true),
                      _tab('Personal'),
                      _tab('Employment'),
                      _tab('Payroll'),
                      _tab('Documents'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _EmployeeDetailSection(
                    title: 'Contact Information',
                    children: [
                      _EmployeeDetailLine(
                        'Username',
                        employee.username.isEmpty ? '-' : employee.username,
                      ),
                      _EmployeeDetailLine('Work mode', employee.workMode),
                      _EmployeeDetailLine('Employee type', employee.employeeType),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _EmployeeDetailSection(
                    title: 'Employment Details',
                    children: [
                      _EmployeeDetailLine('Employee ID', employee.id),
                      _EmployeeDetailLine('Department', employee.department),
                      _EmployeeDetailLine('Salary', employee.salary),
                      _EmployeeDetailLine('Salary type', employee.salaryType),
                      _EmployeeDetailLine('Joining date', employee.joiningDate),
                      _EmployeeDetailLine('Weekly off template', employee.weeklyOffTemplate),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
            child: _QuickActions(onOpenDetails: onOpenDetails),
          ),
        ],
      ),
    );
  }

  Widget _tab(String label, {bool active = false}) {
    return Expanded(
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
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onOpenDetails});
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context) => _EmployeeDetailSection(
    title: 'Quick Actions',
    children: [
      Row(children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: onOpenDetails,
            icon: const Icon(Icons.person_outline, size: 16),
            label: const Text('View profile'),
            style: _quickActionStyle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.pushReplacementNamed(context, '/admin/clock-logs'),
            icon: const Icon(Icons.calendar_month_outlined, size: 16),
            label: const Text('Attendance'),
            style: _quickActionStyle,
          ),
        ),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.pushReplacementNamed(context, '/admin/approvals'),
            icon: const Icon(Icons.flight_takeoff_outlined, size: 16),
            label: const Text('Apply leave'),
            style: _quickActionStyle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onOpenDetails,
            icon: const Icon(Icons.more_horiz, size: 16),
            label: const Text('More actions'),
            style: _quickActionStyle,
          ),
        ),
      ]),
    ],
  );

  static final ButtonStyle _quickActionStyle = OutlinedButton.styleFrom(
    minimumSize: const Size(0, 34),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
    textStyle: const TextStyle(fontSize: 12),
  );
}

class _EmployeeDetailPage extends StatefulWidget {
  const _EmployeeDetailPage({required this.employee});
  final _Employee employee;

  @override
  State<_EmployeeDetailPage> createState() => _EmployeeDetailPageState();
}

class _EmployeeDetailPageState extends State<_EmployeeDetailPage> {
  late Future<Map<String, dynamic>> _detail;
  int _selectedTab = 0;

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
    _detail = HrmsEmployeesApi.detail(widget.employee.profileId);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F8FC),
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
            final metricWidth = constraints.maxWidth < 760
                ? (constraints.maxWidth - 64) / 2
                : 190.0;
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
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: const Color(0xFFEAF0FA),
                            child: Text(
                              widget.employee.name.isEmpty
                                  ? '?'
                                  : widget.employee.name
                                        .substring(0, 1)
                                        .toUpperCase(),
                              style: const TextStyle(
                                color: HrmsColors.blue,
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.employee.name,
                                  style: const TextStyle(
                                    color: HrmsColors.navy,
                                    fontSize: 21,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Wrap(
                                  spacing: 9,
                                  children: [
                                    Text(
                                      'Employee ID ${widget.employee.id}',
                                      style: const TextStyle(
                                        color: Color(0xFF657087),
                                      ),
                                    ),
                                    Text(
                                      widget.employee.department,
                                      style: const TextStyle(
                                        color: Color(0xFF657087),
                                      ),
                                    ),
                                    Text(
                                      widget.employee.workMode,
                                      style: const TextStyle(
                                        color: Color(0xFF657087),
                                      ),
                                    ),
                                    _StatusBadge(
                                      status: widget.employee.status,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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
    height: 72,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDCE4F1)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF657087),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
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
        ],
      ),
    ),
  );
}

class _EmployeeDetailSection extends StatelessWidget {
  const _EmployeeDetailSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE3E8F2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: HrmsColors.navy,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        ...children,
      ],
    ),
  );
}

class _EmployeeDetailLine extends StatelessWidget {
  const _EmployeeDetailLine(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Color(0xFF657087))),
        ),
        Text(
          value,
          style: const TextStyle(
            color: HrmsColors.navy,
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

