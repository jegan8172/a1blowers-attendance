import 'package:flutter/material.dart';

import '../../../../services/hrms_approvals_api.dart';
import '../../../../services/hrms_employees_api.dart';

enum QuickApprovalCategory { leave, device, extraHours }

const _leaveTypes = {
  'leave', 'risk_leave', 'annual_leave', 'sick_leave', 'personal_leave',
  'casual_leave', 'earned_leave', 'optional_holiday',
};

Future<void> showQuickApprovalsDialog(BuildContext context, QuickApprovalCategory category) =>
    showDialog<void>(context: context, builder: (_) => _QuickApprovalsDialog(category: category));

class _QuickApprovalsDialog extends StatefulWidget {
  const _QuickApprovalsDialog({required this.category});
  final QuickApprovalCategory category;

  @override
  State<_QuickApprovalsDialog> createState() => _QuickApprovalsDialogState();
}

class _QuickApprovalsDialogState extends State<_QuickApprovalsDialog> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  int? _reviewing;
  String? _error;

  String get _title => switch (widget.category) {
    QuickApprovalCategory.leave => 'Leave approvals',
    QuickApprovalCategory.device => 'Device change approvals',
    QuickApprovalCategory.extraHours => 'Extra hours approvals',
  };

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = widget.category == QuickApprovalCategory.device
          ? await HrmsEmployeesApi.deviceRequests()
          : await HrmsApprovalsApi.list(leaveTab: widget.category == QuickApprovalCategory.leave, status: 'Pending');
      final items = (data['items'] as List? ?? []).whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) {
            final type = '${item['requestType'] ?? ''}'.toLowerCase();
            return switch (widget.category) {
              QuickApprovalCategory.leave => _leaveTypes.contains(type),
              QuickApprovalCategory.device => true,
              QuickApprovalCategory.extraHours => type == 'extra_hours',
            };
          })
          .toList();
      if (!mounted) return;
      setState(() { _items = items; _loading = false; });
    } catch (error) {
      if (!mounted) return;
      setState(() { _error = error.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _review(Map<String, dynamic> item, bool approve) async {
    final id = int.tryParse('${item['id']}');
    if (id == null) { setState(() => _error = 'Request ID is missing.'); return; }
    String? salaryMode;
    final leaveType = '${item['leaveType'] ?? ''}';
    if (approve && widget.category == QuickApprovalCategory.leave && leaveType.isNotEmpty && leaveType != 'Earned Leave') {
      salaryMode = await showDialog<String>(context: context, builder: (context) => AlertDialog(
        title: Text('$leaveType salary decision'),
        content: const Text('Choose whether this approved leave is paid or unpaid.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          OutlinedButton(onPressed: () => Navigator.pop(context, 'unpaid'), child: const Text('Unpaid')),
          FilledButton(onPressed: () => Navigator.pop(context, 'paid'), child: const Text('Paid')),
        ],
      ));
      if (salaryMode == null || !mounted) return;
    }
    setState(() { _reviewing = id; _error = null; });
    try {
      if (widget.category == QuickApprovalCategory.device) {
        await HrmsEmployeesApi.reviewDeviceRequest(id, approve);
      } else {
        await HrmsApprovalsApi.review(id, approve ? 'Approved' : 'Rejected', salaryMode: salaryMode);
      }
      if (!mounted) return;
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _reviewing = null);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_title),
    content: SizedBox(
      width: 600,
      height: MediaQuery.sizeOf(context).height * .55,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _items.isEmpty
            ? Center(child: TextButton(onPressed: _load, child: const Text('Retry')))
            : _items.isEmpty
              ? const Center(child: Text('No pending requests.'))
              : ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final device = widget.category == QuickApprovalCategory.device;
                    final name = '${item[device ? 'full_name' : 'name'] ?? 'Employee'}';
                    final details = device
                      ? 'New device: ${item['proposed_device_label'] ?? 'Browser'}\nReason: ${item['reason'] ?? 'Not provided'}'
                      : '${item['type'] ?? 'Request'} · ${item['dates'] ?? '—'} · ${item['duration'] ?? '—'}\nReason: ${item['reason'] ?? 'Not provided'}';
                    return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4), Text(details),
                        Wrap(spacing: 8, children: [
                          TextButton(onPressed: _reviewing == null ? () => _review(item, false) : null, child: const Text('Reject')),
                          FilledButton(onPressed: _reviewing == null ? () => _review(item, true) : null, child: const Text('Approve')),
                        ])],
                    ));
                  },
                )),
      ]),
    ),
    actions: [TextButton(onPressed: _reviewing == null ? () => Navigator.pop(context) : null, child: const Text('Close'))],
  );
}
