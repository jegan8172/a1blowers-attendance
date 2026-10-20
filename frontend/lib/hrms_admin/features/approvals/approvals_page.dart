import 'package:flutter/material.dart';
import '../../shared/theme/admin_surface_palette.dart';

import '../../../services/hrms_approvals_api.dart';
import '../../shared/widgets/admin_top_nav.dart';

abstract final class _C {
  static const red = Color(0xFFE3162A);
  static const navy = Color(0xFF102653);
  static const ink = Color(0xFF182846);
  static const muted = Color(0xFF647493);
  static const border = Color(0xFFE1E7F0);
  static const page = Color(0xFFF7F9FC);
}

class ApprovalsPage extends StatefulWidget {
  const ApprovalsPage({super.key});
  static Widget builder(BuildContext context) => const ApprovalsPage();
  @override
  State<ApprovalsPage> createState() => _ApprovalsPageState();
}

class _ApprovalsPageState extends State<ApprovalsPage> {
  String _category = 'leave';
  String _employee = 'All Employees';
  String _status = 'Pending';
  String _search = '';
  String _range = 'This month';
  int? _selectedId;
  List<_Request> _leave = const [];
  List<_Request> _other = const [];
  List<String> _employees = const ['All Employees'];
  int _pending = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        HrmsApprovalsApi.list(leaveTab: true, employee: _employee, status: _status),
        HrmsApprovalsApi.list(leaveTab: false, employee: _employee, status: _status),
      ]);
      final leave = results[0];
      final other = results[1];
      final names = <String>{'All Employees'};
      names.addAll((leave['employees'] as List? ?? const []).map((e) => '$e'));
      names.addAll((other['employees'] as List? ?? const []).map((e) => '$e'));
      final kpis = Map<String, dynamic>.from(leave['kpis'] as Map? ?? const {});
      if (!mounted) return;
      setState(() {
        _leave = _parse(leave['items']);
        _other = _parse(other['items']);
        _employees = names.toList()..sort();
        if (!_employees.contains(_employee)) _employee = 'All Employees';
        _pending = _int(kpis['pending']);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  int _int(dynamic value) => value is int ? value : int.tryParse('$value') ?? 0;
  List<_Request> _parse(dynamic data) => data is List
      ? data.whereType<Map>().map((v) => _Request.fromApi(Map<String, dynamic>.from(v))).toList()
      : const [];

  List<_Request> get _visible {
    final source = _category == 'leave' ? _leave : _other;
    final query = _search.trim().toLowerCase();
    return source.where((r) {
      final kind = '${r.type} ${r.requestType}'.toLowerCase();
      final matchesCategory = _category == 'leave' ||
          (_category == 'permission' && kind.contains('permission')) ||
          (_category == 'device' && kind.contains('device')) ||
          (_category == 'extra' && !kind.contains('permission') && !kind.contains('device'));
      final matchesSearch = query.isEmpty ||
          r.name.toLowerCase().contains(query) || r.id.toLowerCase().contains(query) ||
          r.type.toLowerCase().contains(query) || r.reason.toLowerCase().contains(query);
      return matchesCategory && matchesSearch;
    }).toList();
  }

  _Request? get _selected {
    final requests = _visible;
    for (final request in requests) {
      if (request.requestId == _selectedId) return request;
    }
    return requests.isEmpty ? null : requests.first;
  }

  int _count(String category) {
    final source = category == 'leave' ? _leave : _other;
    return source.where((r) {
      if (category == 'leave') return true;
      final kind = '${r.type} ${r.requestType}'.toLowerCase();
      return category == 'permission' ? kind.contains('permission') : category == 'device' ? kind.contains('device') : !kind.contains('permission') && !kind.contains('device');
    }).length;
  }

  Future<void> _review(_Request request, String status) async {
    try {
      String? salaryMode;
      if (status == 'Approved' && request.requestType == 'permission') {
        salaryMode = await showDialog<String>(context: context, builder: (context) => AlertDialog(
          title: const Text('Permission salary decision'),
          content: const Text('Choose whether this approved permission is paid or unpaid. Unpaid permission is recorded as Half Leave.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            OutlinedButton(onPressed: () => Navigator.pop(context, 'unpaid'), child: const Text('Without salary')),
            FilledButton(onPressed: () => Navigator.pop(context, 'paid'), child: const Text('With salary')),
          ],
        ));
        if (salaryMode == null) return;
      }
      await HrmsApprovalsApi.review(request.requestId, status, salaryMode: salaryMode);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${request.name}\'s request was ${status.toLowerCase()}.'), behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 1050;
    final requests = _visible;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      bottomNavigationBar: mobile ? const AdminMobileBottomNav(activeRoute: '/admin/approvals') : null,
      body: Column(children: [
        const AdminTopNav(activeRoute: '/admin/approvals'),
        Expanded(child: _loading && _leave.isEmpty && _other.isEmpty
          ? const Center(child: CircularProgressIndicator(color: _C.red))
          : _error != null && _leave.isEmpty && _other.isEmpty
            ? _Error(message: _error!, onRetry: _load)
            : mobile
              ? RefreshIndicator(
                  color: _C.red,
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
                    child: _MobileApprovalsContent(
                      heading: _Heading(range: _range, pending: _pending, onRange: (v) => setState(() => _range = v), onFilters: _filterSheet),
                      categories: _categoryTabs(),
                      filters: _filters(),
                      requests: requests,
                      onSelect: _requestSheet,
                      loading: _loading,
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(34, 20, 34, 22),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1600),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _Heading(range: _range, pending: _pending, onRange: (v) => setState(() => _range = v), onFilters: _filterSheet),
                        const SizedBox(height: 18),
                        _categoryTabs(),
                        const SizedBox(height: 14),
                        if (_loading) const LinearProgressIndicator(minHeight: 2, color: _C.red),
                        if (_loading) const SizedBox(height: 10),
                        Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Expanded(flex: 13, child: Column(children: [
                            _filters(),
                            const SizedBox(height: 14),
                            Expanded(child: _Table(requests: requests, selectedId: _selected?.requestId, onSelect: (r) => setState(() => _selectedId = r.requestId))),
                            const SizedBox(height: 10),
                            _Footer(count: requests.length),
                          ])),
                          const SizedBox(width: 14),
                          SizedBox(width: 470, child: _Details(request: _selected, onApprove: (r) => _review(r, 'Approved'), onReject: (r) => _review(r, 'Rejected'))),
                        ])),
                      ]),
                    ),
                  ),
                )),
      ]),
    );
  }

  Widget _categoryTabs() => _Categories(
    active: _category,
    counts: {'leave': _count('leave'), 'permission': _count('permission'), 'device': _count('device'), 'extra': _count('extra')},
    onChanged: (value) => setState(() { _category = value; _selectedId = null; }),
  );

  Widget _filters() => _Filters(
    search: _search,
    employee: _employee,
    status: _status,
    employees: _employees,
    onSearch: (value) => setState(() => _search = value),
    onEmployee: (value) { setState(() => _employee = value ?? 'All Employees'); _load(); },
    onStatus: (value) { setState(() => _status = value ?? 'All Status'); _load(); },
    onClear: () {
      setState(() { _employee = 'All Employees'; _status = 'Pending'; _search = ''; _selectedId = null; });
      _load();
    },
  );

  void _filterSheet() {
    showModalBottomSheet<void>(context: context, backgroundColor: Colors.transparent, builder: (ctx) => SafeArea(child: Container(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 26),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: const Color(0xFFD8E0EC), borderRadius: BorderRadius.circular(4)))),
        const SizedBox(height: 18), const Text('Filter requests', style: TextStyle(color: _C.navy, fontSize: 20, fontWeight: FontWeight.w800)), const SizedBox(height: 18),
        DropdownButtonFormField<String>(value: _employee, decoration: _input(context, label: 'Employee'), items: _employees.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => _employee = v ?? 'All Employees')),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(value: _status, decoration: _input(context, label: 'Status'), items: const ['All Status', 'Pending', 'Approved', 'Rejected'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => _status = v ?? 'All Status')),
        const SizedBox(height: 20), FilledButton(onPressed: () { Navigator.pop(ctx); _load(); }, style: FilledButton.styleFrom(backgroundColor: _C.red, minimumSize: const Size.fromHeight(48)), child: const Text('Apply filters')),
      ]),
    )));
  }

  void _requestSheet(_Request request) {
    showModalBottomSheet<void>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (ctx) => DraggableScrollableSheet(initialChildSize: .78, minChildSize: .5, maxChildSize: .94, builder: (_, scroll) => Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: SingleChildScrollView(controller: scroll, padding: const EdgeInsets.all(18), child: SizedBox(height: 570, child: _Details(request: request, onApprove: (r) { Navigator.pop(ctx); _review(r, 'Approved'); }, onReject: (r) { Navigator.pop(ctx); _review(r, 'Rejected'); }))),
    )));
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.range, required this.pending, required this.onRange, required this.onFilters});
  final String range; final int pending; final ValueChanged<String> onRange; final VoidCallback onFilters;
  @override Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 1050;
    final controls = Row(mainAxisSize: MainAxisSize.min, children: [
      PopupMenuButton<String>(onSelected: onRange, itemBuilder: (_) => const [PopupMenuItem(value: 'Today', child: Text('Today')), PopupMenuItem(value: 'This week', child: Text('This week')), PopupMenuItem(value: 'This month', child: Text('This month')), PopupMenuItem(value: 'All dates', child: Text('All dates'))], child: _Control(icon: Icons.calendar_month_outlined, label: range, trailing: Icons.keyboard_arrow_down_rounded)),
      const SizedBox(width: 10), Badge(isLabelVisible: pending > 0, label: Text('$pending'), backgroundColor: _C.red, child: _Control(icon: Icons.tune_rounded, label: 'Filters', onTap: onFilters)),
    ]);
    final palette = AdminSurfacePalette.of(context);
    final title = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Approvals', style: TextStyle(color: palette.text, fontSize: 36, fontWeight: FontWeight.w800, height: 1.05)), const SizedBox(height: 6), Text('Review and take action on employee requests across all categories.', style: TextStyle(color: palette.mutedText, fontSize: 15))]);
    if (!compact) return Row(children: [title, const Spacer(), controls]);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, const SizedBox(height: 16), controls]);
  }
}

class _Control extends StatelessWidget { const _Control({required this.icon, required this.label, this.trailing, this.onTap}); final IconData icon; final String label; final IconData? trailing; final VoidCallback? onTap;
  @override Widget build(BuildContext context) { final palette = AdminSurfacePalette.of(context); return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(9), child: Container(height: 44, padding: const EdgeInsets.symmetric(horizontal: 14), decoration: BoxDecoration(color: palette.surface, border: Border.all(color: palette.border), borderRadius: BorderRadius.circular(9)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 20, color: palette.text), const SizedBox(width: 10), Text(label, style: TextStyle(color: palette.text, fontWeight: FontWeight.w600)), if (trailing != null) ...[const SizedBox(width: 18), Icon(trailing, color: palette.text)]]))); } }

class _Categories extends StatelessWidget {
  const _Categories({required this.active, required this.counts, required this.onChanged}); final String active; final Map<String, int> counts; final ValueChanged<String> onChanged;
  @override Widget build(BuildContext context) {
    const items = [('leave', 'Leave', Icons.calendar_month_outlined), ('permission', 'Permission', Icons.schedule_outlined), ('device', 'Device Requests', Icons.laptop_mac_outlined), ('extra', 'Clock-in Correction', Icons.timer_outlined)];
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: items.map((item) => Padding(padding: const EdgeInsets.only(right: 12), child: _Category(active: active == item.$1, icon: item.$3, label: item.$2, count: counts[item.$1] ?? 0, onTap: () => onChanged(item.$1)))).toList()));
  }
}

class _Category extends StatelessWidget {
  const _Category({required this.active, required this.icon, required this.label, required this.count, required this.onTap});
  final bool active;
  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: active,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 230,
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 17),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEFF1),
          border: Border.all(color: const Color(0xFFFFBBC2)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, color: _C.red, size: 25),
            const SizedBox(width: 13),
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _C.red, fontWeight: FontWeight.w700))),
            if (count > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: _C.red, borderRadius: BorderRadius.circular(14)),
                child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
              ),
          ],
        ),
      ),
    ),
  );
}

class _Filters extends StatelessWidget {
  const _Filters({required this.search, required this.employee, required this.status, required this.employees, required this.onSearch, required this.onEmployee, required this.onStatus, required this.onClear}); final String search, employee, status; final List<String> employees; final ValueChanged<String> onSearch; final ValueChanged<String?> onEmployee, onStatus; final VoidCallback onClear;
  @override Widget build(BuildContext context) { final palette = AdminSurfacePalette.of(context); return Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: palette.surface, border: Border.all(color: palette.border), borderRadius: BorderRadius.circular(10)), child: LayoutBuilder(builder: (_, box) {
    final searchField = TextField(onChanged: onSearch, decoration: _input(context, hint: 'Employee name, department, reason...', prefix: Icons.search_rounded));
    final employeeField = DropdownButtonFormField<String>(value: employee, decoration: _input(context, label: 'Employee'), items: employees.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(), onChanged: onEmployee);
    final statusField = DropdownButtonFormField<String>(value: status, decoration: _input(context, label: 'Status'), items: const ['All Status', 'Pending', 'Approved', 'Rejected'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: onStatus);
    final clear = TextButton.icon(onPressed: onClear, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Clear all'));
    if (box.maxWidth < 850) return Wrap(runSpacing: 12, spacing: 12, children: [SizedBox(width: box.maxWidth, child: searchField), SizedBox(width: (box.maxWidth - 12) / 2, child: employeeField), SizedBox(width: (box.maxWidth - 12) / 2, child: statusField), clear]);
    return Row(children: [Expanded(flex: 3, child: searchField), const SizedBox(width: 12), Expanded(flex: 2, child: employeeField), const SizedBox(width: 12), Expanded(flex: 1, child: statusField), const SizedBox(width: 10), clear]);
  })); }
}

class _MobileApprovalsContent extends StatelessWidget {
  const _MobileApprovalsContent({required this.heading, required this.categories, required this.filters, required this.requests, required this.onSelect, required this.loading});
  final Widget heading, categories, filters;
  final List<_Request> requests;
  final ValueChanged<_Request> onSelect;
  final bool loading;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    heading,
    const SizedBox(height: 20),
    categories,
    const SizedBox(height: 14),
    if (loading) const LinearProgressIndicator(minHeight: 2, color: _C.red),
    if (loading) const SizedBox(height: 12),
    filters,
    const SizedBox(height: 16),
    _MobileList(requests: requests, onSelect: onSelect),
  ]);
}

InputDecoration _input(BuildContext context, {String? label, String? hint, IconData? prefix}) { final palette = AdminSurfacePalette.of(context); return InputDecoration(labelText: label, hintText: hint, prefixIcon: prefix == null ? null : Icon(prefix, color: palette.mutedText), filled: true, fillColor: palette.subtleSurface, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: palette.border)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: palette.border)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _C.red, width: 1.5))); }

class _Table extends StatelessWidget { const _Table({required this.requests, required this.selectedId, required this.onSelect}); final List<_Request> requests; final int? selectedId; final ValueChanged<_Request> onSelect;
  @override Widget build(BuildContext context) { final palette = AdminSurfacePalette.of(context); return Container(decoration: BoxDecoration(color: palette.surface, border: Border.all(color: palette.border), borderRadius: BorderRadius.circular(10)), clipBehavior: Clip.antiAlias, child: Column(children: [const _TableHeader(), Expanded(child: requests.isEmpty ? const _Empty() : ListView.separated(itemCount: requests.length, separatorBuilder: (_, __) => Divider(height: 1, color: palette.border), itemBuilder: (_, i) { final r = requests[i]; return _Row(request: r, selected: selectedId == r.requestId, onTap: () => onSelect(r)); }))])); } }

class _TableHeader extends StatelessWidget { const _TableHeader(); @override Widget build(BuildContext context) => Container(height: 43, padding: const EdgeInsets.symmetric(horizontal: 18), color: AdminSurfacePalette.of(context).subtleSurface, child: Row(children: [const SizedBox(width: 40), Expanded(flex: 22, child: Text('Employee', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700))), Expanded(flex: 23, child: Text('Request details', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700))), Expanded(flex: 19, child: Text('Dates', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700))), Expanded(flex: 8, child: Text('Days', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700))), Expanded(flex: 12, child: Text('Status', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700)))])); }

class _Row extends StatelessWidget { const _Row({required this.request, required this.selected, required this.onTap}); final _Request request; final bool selected; final VoidCallback onTap;
  @override Widget build(BuildContext context) => InkWell(onTap: onTap, child: AnimatedContainer(duration: const Duration(milliseconds: 130), height: 80, color: selected ? const Color(0xFFFFEFF1) : AdminSurfacePalette.of(context).surface, padding: const EdgeInsets.symmetric(horizontal: 18), child: Row(children: [SizedBox(width: 40, child: Icon(selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, color: selected ? _C.red : const Color(0xFFC8D1DF), size: 21)), Expanded(flex: 22, child: _Person(request: request)), Expanded(flex: 23, child: _Two(title: request.type, subtitle: request.reason)), Expanded(flex: 19, child: _Two(title: request.dates, subtitle: request.dayRange)), Expanded(flex: 8, child: Text(request.duration, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600))), Expanded(flex: 12, child: _Status(value: request.status))]))); }

class _Person extends StatelessWidget { const _Person({required this.request}); final _Request request; @override Widget build(BuildContext context) => Row(children: [CircleAvatar(radius: 19, backgroundColor: const Color(0xFFEAF0F9), child: Text(request.initials, style: const TextStyle(color: _C.navy, fontSize: 12, fontWeight: FontWeight.w800))), const SizedBox(width: 10), Expanded(child: _Two(title: request.name, subtitle: request.id))]); }
class _Two extends StatelessWidget { const _Two({required this.title, required this.subtitle}); final String title, subtitle; @override Widget build(BuildContext context) => Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _C.ink, fontSize: 13, fontWeight: FontWeight.w700)), const SizedBox(height: 3), Text(subtitle.isEmpty ? '—' : subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _C.muted, fontSize: 12))]); }

class _Details extends StatelessWidget { const _Details({required this.request, required this.onApprove, required this.onReject}); final _Request? request; final ValueChanged<_Request> onApprove, onReject;
  @override Widget build(BuildContext context) { final r = request; if (r == null) return Container(decoration: _panel(context), child: Center(child: Padding(padding: const EdgeInsets.all(36), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.inbox_outlined, size: 42, color: Color(0xFF99A8C0)), const SizedBox(height: 12), Text('Select a request to review', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700)), const SizedBox(height: 5), Text('Its details and approval actions will appear here.', textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))])))); return Container(padding: const EdgeInsets.fromLTRB(20, 20, 20, 18), decoration: _panel(context), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [CircleAvatar(radius: 25, backgroundColor: const Color(0xFFEAF0F9), child: Text(r.initials, style: const TextStyle(color: _C.navy, fontWeight: FontWeight.w800))), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r.name, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text(r.id, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13))])), _Status(value: r.status)]), const SizedBox(height: 20), const Row(children: [_DetailTab('Request Details', true), SizedBox(width: 24), _DetailTab('Activity', false)]), const Divider(height: 1, color: _C.border), const SizedBox(height: 18), _DetailRows(request: r), const Spacer(), if (r.status == 'Pending') Row(children: [Expanded(child: FilledButton.icon(onPressed: () => onApprove(r), icon: const Icon(Icons.check_rounded), label: const Text('Approve request'), style: FilledButton.styleFrom(backgroundColor: _C.red, minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7))))), const SizedBox(width: 10), Expanded(child: OutlinedButton.icon(onPressed: () => onReject(r), icon: const Icon(Icons.close_rounded), label: const Text('Reject request'), style: OutlinedButton.styleFrom(foregroundColor: _C.red, side: const BorderSide(color: _C.red), minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)))))]) else Container(width: double.infinity, padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: AdminSurfacePalette.of(context).subtleSurface, borderRadius: BorderRadius.circular(8)), child: Text('This request has already been ${r.status.toLowerCase()}.', textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))) ])); }
}

BoxDecoration _panel(BuildContext context) { final palette = AdminSurfacePalette.of(context); return BoxDecoration(color: palette.surface, border: Border.all(color: palette.border), borderRadius: BorderRadius.circular(10)); }
class _DetailTab extends StatelessWidget { const _DetailTab(this.label, this.active); final String label; final bool active; @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.only(bottom: 11), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: active ? _C.red : Colors.transparent, width: 3))), child: Text(label, style: TextStyle(color: active ? _C.red : _C.muted, fontSize: 13, fontWeight: FontWeight.w700))); }
class _DetailRows extends StatelessWidget { const _DetailRows({required this.request}); final _Request request; @override Widget build(BuildContext context) { final rows = [('Request type', request.type), ('Reason', request.reason.isEmpty ? 'Not provided' : request.reason), ('Dates', request.dates), ('Duration', request.duration), ('Request ID', '#${request.requestId}')]; return Column(children: rows.map((row) => Padding(padding: const EdgeInsets.only(bottom: 14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 102, child: Text(row.$1, style: const TextStyle(color: _C.muted, fontSize: 13))), Expanded(child: Text(row.$2, style: const TextStyle(color: _C.ink, fontSize: 13, fontWeight: FontWeight.w600)))]))).toList()); } }

class _MobileList extends StatelessWidget { const _MobileList({required this.requests, required this.onSelect}); final List<_Request> requests; final ValueChanged<_Request> onSelect; @override Widget build(BuildContext context) => Container(decoration: BoxDecoration(border: Border.all(color: _C.border), borderRadius: BorderRadius.circular(10)), child: requests.isEmpty ? const SizedBox(height: 250, child: _Empty()) : ListView.separated(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: requests.length, separatorBuilder: (_, __) => const Divider(height: 1, color: _C.border), itemBuilder: (_, i) { final r = requests[i]; return InkWell(onTap: () => onSelect(r), child: Padding(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Expanded(child: _Person(request: r)), const SizedBox(width: 10), _Status(value: r.status)]), const SizedBox(height: 13), Text(r.type, style: const TextStyle(color: _C.ink, fontWeight: FontWeight.w700)), const SizedBox(height: 3), Text(r.reason.isEmpty ? r.dates : '${r.dates} · ${r.reason}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _C.muted, fontSize: 13))]))); })); }
class _Status extends StatelessWidget { const _Status({required this.value}); final String value; @override Widget build(BuildContext context) { final color = value.toLowerCase() == 'approved' ? const Color(0xFF16853B) : value.toLowerCase() == 'rejected' ? const Color(0xFFD92D3B) : const Color(0xFFAB6700); return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(16)), child: Text(value, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700))); } }
class _Footer extends StatelessWidget { const _Footer({required this.count}); final int count; @override Widget build(BuildContext context) => Row(children: [Text('Showing $count request${count == 1 ? '' : 's'}', style: const TextStyle(color: _C.muted, fontSize: 13)), const Spacer(), const _PageButton(Icons.chevron_left_rounded), const _PageButton(null, text: '1', active: true), const _PageButton(Icons.chevron_right_rounded)]); }
class _PageButton extends StatelessWidget { const _PageButton(this.icon, {this.text, this.active = false}); final IconData? icon; final String? text; final bool active; @override Widget build(BuildContext context) => Container(width: 32, height: 32, margin: const EdgeInsets.only(left: 8), alignment: Alignment.center, decoration: BoxDecoration(color: active ? _C.red : Colors.white, border: Border.all(color: active ? _C.red : _C.border), borderRadius: BorderRadius.circular(6)), child: icon == null ? Text(text!, style: TextStyle(color: active ? Colors.white : _C.navy, fontWeight: FontWeight.w700)) : Icon(icon, size: 19, color: _C.muted)); }
class _Empty extends StatelessWidget { const _Empty(); @override Widget build(BuildContext context) => const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.inbox_outlined, size: 38, color: Color(0xFF9FAEC3)), SizedBox(height: 10), Text('No approval requests match these filters.', style: TextStyle(color: _C.muted))])); }
class _Error extends StatelessWidget { const _Error({required this.message, required this.onRetry}); final String message; final VoidCallback onRetry; @override Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(message, textAlign: TextAlign.center, style: const TextStyle(color: _C.muted)), const SizedBox(height: 14), FilledButton(onPressed: onRetry, style: FilledButton.styleFrom(backgroundColor: _C.red), child: const Text('Retry'))]))); }

class _Request { const _Request({required this.requestId, required this.name, required this.id, required this.type, required this.requestType, required this.dates, required this.dayRange, required this.duration, required this.reason, required this.status}); final int requestId; final String name, id, type, requestType, dates, dayRange, duration, reason, status; String get initials { final words = name.trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList(); return words.isEmpty ? '?' : words.take(2).map((word) => word[0].toUpperCase()).join(); } factory _Request.fromApi(Map<String, dynamic> json) => _Request(requestId: json['id'] is int ? json['id'] as int : int.tryParse('${json['id']}') ?? 0, name: '${json['name'] ?? ''}', id: '${json['employeeCode'] ?? ''}', type: '${json['type'] ?? 'Request'}', requestType: '${json['requestType'] ?? ''}', dates: '${json['dates'] ?? ''}', dayRange: '${json['dayRange'] ?? ''}', duration: '${json['duration'] ?? ''}', reason: '${json['reason'] ?? ''}', status: '${json['status'] ?? 'Pending'}'); }

const _head = TextStyle(color: _C.muted, fontSize: 12, fontWeight: FontWeight.w700);
