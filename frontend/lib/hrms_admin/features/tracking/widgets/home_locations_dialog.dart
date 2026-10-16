import 'package:flutter/material.dart';

import '../../../../services/hrms_tracking_api.dart';

class HomeLocationsDialog extends StatefulWidget {
  const HomeLocationsDialog({super.key});

  @override
  State<HomeLocationsDialog> createState() => _HomeLocationsDialogState();
}

class _HomeLocationsDialogState extends State<HomeLocationsDialog> {
  final _radiusController = TextEditingController();
  List<Map<String, dynamic>> _homes = [];
  bool _loadingHomes = true;
  bool _loadingRadius = true;
  bool _savingRadius = false;
  int? _reviewingId;
  String? _homeError;
  String? _radiusError;
  String? _radiusNotice;

  bool get _busy => _savingRadius || _reviewingId != null;

  @override
  void initState() {
    super.initState();
    _loadHomes();
    _loadRadius();
  }

  @override
  void dispose() {
    _radiusController.dispose();
    super.dispose();
  }

  Future<void> _loadHomes() async {
    if (!mounted) return;
    setState(() {
      _loadingHomes = true;
      _homeError = null;
    });
    try {
      final homes = await HrmsTrackingApi.homeLocations();
      // Pending requests come first, then retain the server's order.
      final pending = homes.where(
        (home) => home['approval_status'] == 'pending',
      );
      final other = homes.where((home) => home['approval_status'] != 'pending');
      if (!mounted) return;
      setState(() {
        _homes = [...pending, ...other];
        _loadingHomes = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingHomes = false;
        _homeError = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadRadius() async {
    setState(() {
      _loadingRadius = true;
      _radiusError = null;
    });
    try {
      final settings = await HrmsTrackingApi.trackingSettings();
      if (!mounted) return;
      final radius = settings['office_radius_meters'];
      if (radius == null) {
        throw Exception('Office/Home radius is not configured.');
      }
      setState(() {
        _radiusController.text = '$radius';
        _loadingRadius = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingRadius = false;
        _radiusError = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _saveRadius() async {
    if (_busy) return;
    final radius = int.tryParse(_radiusController.text.trim());
    if (radius == null || radius < 1) {
      setState(() => _radiusError = 'Enter a whole number greater than zero.');
      return;
    }
    setState(() {
      _savingRadius = true;
      _radiusError = null;
      _radiusNotice = null;
    });
    try {
      await HrmsTrackingApi.updateOfficeRadius(radius);
      if (!mounted) return;
      setState(() => _radiusNotice = 'Office/Home Clock In radius saved.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _radiusError = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _savingRadius = false);
    }
  }

  Future<void> _review(Map<String, dynamic> home, bool approve) async {
    if (_busy) return;
    final id = int.tryParse('${home['employee_user_id']}');
    final latitude = double.tryParse('${home['latitude']}');
    final longitude = double.tryParse('${home['longitude']}');
    if (id == null || latitude == null || longitude == null) {
      setState(() => _homeError = 'This request has invalid location details.');
      return;
    }
    setState(() => _reviewingId = id);
    try {
      String? rejectionReason;
      if (!approve) {
        rejectionReason = await showDialog<String>(
          context: context,
          builder: (_) => const _HomeRejectionDialog(),
        );
        if (!mounted || rejectionReason == null) return;
      }
      await HrmsTrackingApi.reviewHomeLocation(
        employeeUserId: id,
        approve: approve,
        latitude: latitude,
        longitude: longitude,
        rejectionReason: rejectionReason,
      );
      if (!mounted) return;
      await _loadHomes();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _homeError = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _reviewingId = null);
    }
  }

  Widget _radiusEditor() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Office/Home Clock In radius',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      const Text(
        'The same allowed distance applies around the office and '
        'each approved home. Field waiting settings are separate.',
      ),
      const SizedBox(height: 12),
      if (_loadingRadius)
        const LinearProgressIndicator()
      else
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 200,
              child: TextField(
                controller: _radiusController,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Radius (metres)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            FilledButton(
              onPressed: _busy ? null : _saveRadius,
              child: Text(_savingRadius ? 'Saving...' : 'Save Radius'),
            ),
          ],
        ),
      if (_radiusNotice != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _radiusNotice!,
            style: const TextStyle(color: Color(0xFF138A20)),
          ),
        ),
      if (_radiusError != null) ...[
        const SizedBox(height: 8),
        Text(
          _radiusError!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _busy ? null : _loadRadius,
            child: const Text('Reload radius'),
          ),
        ),
      ],
    ],
  );

  Widget _homeCard(Map<String, dynamic> home) {
    final status = '${home['approval_status'] ?? 'pending'}';
    final id = int.tryParse('${home['employee_user_id']}');
    final name = '${home['full_name'] ?? home['username'] ?? 'Employee $id'}';
    final address = '${home['address'] ?? ''}'.trim();
    final code = '${home['employee_code'] ?? ''}'.trim();
    final latitude = double.tryParse('${home['latitude']}');
    final longitude = double.tryParse('${home['longitude']}');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (code.isNotEmpty) Text(code),
            const SizedBox(height: 6),
            Text('Status: $status'),
            if (address.isNotEmpty) Text(address),
            SelectableText(
              'GPS: ${latitude?.toStringAsFixed(7) ?? 'Invalid'}, '
              '${longitude?.toStringAsFixed(7) ?? 'Invalid'}',
            ),
            if (home['rejection_reason'] != null)
              Text('Rejection reason: ${home['rejection_reason']}'),
            if (status == 'pending') ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _review(home, true),
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(
                      _reviewingId == id ? 'Saving...' : 'Approve Home work',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _review(home, false),
                    child: const Text('Reject'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Home Approvals'),
      content: SizedBox(
        width: 700,
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _radiusEditor(),
              const Divider(height: 32),
              const Text(
                'Employee home registrations',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Approve Home work only after checking the '
                'registered location. Approval also changes the employee’s '
                'work mode to Home.',
              ),
              const SizedBox(height: 14),
              if (_homeError != null) ...[
                Text(
                  _homeError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 8),
              ],
              if (_loadingHomes)
                const Center(child: CircularProgressIndicator())
              else if (_homes.isEmpty && _homeError == null)
                const Text('No home location requests yet.')
              else
                ..._homes.map(_homeCard),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _busy || _loadingHomes ? null : _loadHomes,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh Requests'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class _HomeRejectionDialog extends StatefulWidget {
  const _HomeRejectionDialog();

  @override
  State<_HomeRejectionDialog> createState() => _HomeRejectionDialogState();
}

class _HomeRejectionDialogState extends State<_HomeRejectionDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Reject Home Location'),
    content: SizedBox(
      width: 400,
      child: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 500,
        minLines: 2,
        maxLines: 4,
        decoration: InputDecoration(
          labelText: 'Reason for rejection',
          errorText: _error,
          border: const OutlineInputBorder(),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final reason = _controller.text.trim();
          if (reason.isEmpty) {
            setState(() => _error = 'Enter a reason for the employee.');
            return;
          }
          Navigator.of(context).pop(reason);
        },
        child: const Text('Reject Location'),
      ),
    ],
  );
}
