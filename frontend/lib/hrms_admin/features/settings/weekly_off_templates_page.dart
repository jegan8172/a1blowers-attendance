import 'package:flutter/material.dart';

import '../../../services/hrms_employees_api.dart';
import '../../../services/hrms_weekly_off_templates_api.dart';
import '../../shared/widgets/admin_top_nav.dart';

const _navy = Color(0xFF081B3C);
const _red = Color(0xFF1769E0);
const _dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

class WeeklyOffTemplatesPage extends StatefulWidget {
  const WeeklyOffTemplatesPage({super.key});
  static Widget builder(BuildContext context) => const WeeklyOffTemplatesPage();
  @override
  State<WeeklyOffTemplatesPage> createState() => _WeeklyOffTemplatesPageState();
}

class _WeeklyOffTemplatesPageState extends State<WeeklyOffTemplatesPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _templates = [];
  List<Map<String, dynamic>> _assignments = [];
  List<Map<String, dynamic>> _employees = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([HrmsWeeklyOffTemplatesApi.list(), HrmsEmployeesApi.list(limit: 1000)]);
      if (!mounted) return;
      final data = results[0];
      setState(() {
        _templates = ((data['templates'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _assignments = ((data['assignments'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _employees = (((results[1]['employees'] ?? results[1]['items']) as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _loading = false;
      });
    } catch (e) { if (mounted) setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); }); }
  }

  Future<void> _templateDialog([Map<String, dynamic>? template]) async {
    final controller = TextEditingController(text: template?['name']?.toString() ?? '');
    final selected = <int>{...((template?['weeklyOffDays'] as List?) ?? const []).map((e) => e as int)};
    var active = template?['active'] != false;
    String? error;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModal) => AlertDialog(
          title: Text(template == null ? 'Create weekly off template' : 'Edit weekly off template'),
          content: SizedBox(
            width: 470,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(controller: controller, decoration: InputDecoration(labelText: 'Template name', errorText: error, border: const OutlineInputBorder())),
                const SizedBox(height: 18), const Text('Weekly off days', style: TextStyle(fontWeight: FontWeight.w700, color: _navy)),
                const SizedBox(height: 8), Wrap(spacing: 7, runSpacing: 7, children: List.generate(7, (day) => FilterChip(label: Text(_dayNames[day]), selected: selected.contains(day), onSelected: (on) => setModal(() => on ? selected.add(day) : selected.remove(day)), selectedColor: const Color(0xFFFFDDE1), checkmarkColor: _red))),
                if (template != null) SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('Template is active'), subtitle: const Text('Inactive templates cannot be newly assigned.'), value: active, activeColor: _red, onChanged: (value) => setModal(() => active = value)),
                const SizedBox(height: 8), const Text('Company holidays and calendar overrides always take priority over weekly off templates.', style: TextStyle(color: Color(0xFF62718B), fontSize: 12, height: 1.35)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: _red), onPressed: () {
              if (controller.text.trim().isEmpty || selected.isEmpty) { setModal(() => error = selected.isEmpty ? 'Enter a name and select at least one day.' : 'Template name is required.'); return; }
              Navigator.pop(context, true);
            }, child: const Text('Save')),
          ],
        ),
      ),
    );
    if (save != true) { controller.dispose(); return; }
    try {
      if (template == null) await HrmsWeeklyOffTemplatesApi.create(name: controller.text.trim(), weeklyOffDays: selected.toList());
      else await HrmsWeeklyOffTemplatesApi.update(id: (template['id'] as num).toInt(), name: controller.text.trim(), weeklyOffDays: selected.toList(), active: active);
      if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content: Text('Weekly off template saved.')));
      await _load();
    } catch (e) { if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')))); }
    controller.dispose();
  }

  Future<void> _assignmentDialog() async {
    if (_employees.isEmpty || _templates.where((e) => e['active'] != false).isEmpty) return;
    int? profileId;
    int? templateId;
    var date = DateTime.now();
    String? error;
    final save = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(builder: (context, setModal) => AlertDialog(
      title: const Text('Assign weekly off template'),
      content: SizedBox(width: 480, child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<int>(value: profileId, isExpanded: true, decoration: InputDecoration(labelText: 'Employee', errorText: error, border: const OutlineInputBorder()), items: _employees.where((e) => e['profileId'] != null || e['id'] != null).map((e) => DropdownMenuItem(value: ((e['profileId'] ?? e['id']) as num).toInt(), child: Text('${e['name'] ?? e['fullName']} (${e['employeeCode'] ?? e['employeeId']})', overflow: TextOverflow.ellipsis))).toList(), onChanged: (v) => setModal(() => profileId = v)),
        const SizedBox(height: 14), DropdownButtonFormField<int>(value: templateId, isExpanded: true, decoration: const InputDecoration(labelText: 'Weekly off template', border: OutlineInputBorder()), items: _templates.where((e) => e['active'] != false).map((e) => DropdownMenuItem(value: (e['id'] as num).toInt(), child: Text('${e['name']} — ${_days(e['weeklyOffDays'])}'))).toList(), onChanged: (v) => setModal(() => templateId = v)),
        const SizedBox(height: 14), ListTile(contentPadding: EdgeInsets.zero, title: const Text('Effective from'), subtitle: Text('${date.day.toString().padLeft(2, '0')} ${_month(date.month)} ${date.year}'), trailing: const Icon(Icons.calendar_month_outlined), onTap: () async { final picked = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDate: date); if (picked != null) setModal(() => date = picked); }),
        const Text('A later effective date preserves attendance and paid payroll history before that date.', style: TextStyle(fontSize: 12, color: Color(0xFF62718B), height: 1.35)),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(style: FilledButton.styleFrom(backgroundColor: _red), onPressed: () { if (profileId == null || templateId == null) { setModal(() => error = 'Choose an employee and template.'); return; } Navigator.pop(context, true); }, child: const Text('Assign'))],
    )));
    if (save != true || profileId == null || templateId == null) return;
    try { await HrmsWeeklyOffTemplatesApi.assign(profileId: profileId!, templateId: templateId!, effectiveFrom: date); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Template assignment saved.'))); await _load(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')))); }
  }

  static String _days(dynamic raw) => ((raw as List?) ?? const []).map((e) => _dayNames[(e as num).toInt()]).join(', ');
  static String _month(int month) => const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][month - 1];

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(backgroundColor: Colors.transparent, bottomNavigationBar: mobile ? const AdminMobileBottomNav(activeRoute: '/admin/settings') : null, body: Column(children: [
      const AdminTopNav(activeRoute: '/admin/settings'), Expanded(child: RefreshIndicator(onRefresh: _load, child: ListView(padding: EdgeInsets.all(mobile ? 16 : 28), children: [
        Row(children: [IconButton(onPressed: () => Navigator.pushReplacementNamed(context, '/admin/settings'), icon: const Icon(Icons.arrow_back)), const SizedBox(width: 8), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Weekly Off Templates', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _navy)), SizedBox(height: 4), Text('Set team schedules and assign them to employees with an effective date.', style: TextStyle(color: Color(0xFF61708C)))])), if (!mobile) FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: _red), onPressed: _assignmentDialog, icon: const Icon(Icons.person_add_alt_1), label: const Text('Assign template'))]),
        if (mobile) Padding(padding: const EdgeInsets.only(top: 14), child: FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: _red), onPressed: _assignmentDialog, icon: const Icon(Icons.person_add_alt_1), label: const Text('Assign template'))),
        const SizedBox(height: 22), if (_loading) const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator())) else if (_error != null) _errorCard() else ...[_templatesCard(mobile), const SizedBox(height: 20), _assignmentsCard(mobile)],
      ])))
    ]));
  }

  Widget _errorCard() => Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_error!, style: const TextStyle(color: _red)), TextButton(onPressed: _load, child: const Text('Retry'))])));
  Widget _templatesCard(bool mobile) => Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Templates', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _navy)), SizedBox(height: 3), Text('Employees without an assignment use the global Payroll Policy weekly off days.', style: TextStyle(color: Color(0xFF61708C), fontSize: 12))])), OutlinedButton.icon(onPressed: () => _templateDialog(), icon: const Icon(Icons.add), label: const Text('New template'))]), const SizedBox(height: 14), if (_templates.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('No templates yet. Create one for each team or shift.')) else ..._templates.map((item) => ListTile(contentPadding: EdgeInsets.zero, title: Text(item['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('${_days(item['weeklyOffDays'])}${item['active'] == false ? ' · Inactive' : ''}'), trailing: IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Edit template', onPressed: () => _templateDialog(item))))])));
  Widget _assignmentsCard(bool mobile) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Assignment history', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _navy)),
        const SizedBox(height: 4),
        const Text('Each change is retained. Only dates on or after its effective date use the new template.', style: TextStyle(color: Color(0xFF61708C), fontSize: 12)),
        const SizedBox(height: 14),
        if (_assignments.isEmpty)
          const Padding(padding: EdgeInsets.all(20), child: Text('No employee template assignments yet.'))
        else
          ..._assignments.map((item) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(backgroundColor: Color(0xFFFFE8EA), child: Icon(Icons.person_outline, color: _red)),
            title: Text('${item['employeeName']} (${item['employeeCode']})'),
            subtitle: Text(item['templateName'].toString()),
            trailing: Text('From\n${item['effectiveFrom']}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: Color(0xFF61708C))),
          )),
      ]),
    ),
  );
}
