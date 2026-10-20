import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../services/attendance_location.dart';
import '../../services/hrms_tracking_api.dart';

/// Registration is explicit: opening this dialog never collects or saves GPS.
class HomeLocationDialog extends StatefulWidget {
  const HomeLocationDialog({super.key});

  @override
  State<HomeLocationDialog> createState() => _HomeLocationDialogState();
}

class _HomeLocationDialogState extends State<HomeLocationDialog> {
  final _addressController = TextEditingController();
  Map<String, dynamic>? _home;
  Position? _position;
  bool _loading = true;
  bool _capturing = false;
  bool _saving = false;
  bool _loadFailed = false;
  String? _error;
  String? _notice;

  bool get _busy => _capturing || _saving;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
      _error = null;
    });
    try {
      final home = await HrmsTrackingApi.myHomeLocation();
      if (!mounted) return;
      setState(() {
        _home = home;
        _addressController.text = home?['address']?.toString() ?? '';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _capture() async {
    if (_busy) return;
    setState(() {
      _capturing = true;
      _error = null;
      _notice = null;
      _position = null;
    });
    try {
      final position = await AttendanceLocation.currentPosition();
      if (!mounted) return;
      setState(() => _position = position);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _submit() async {
    final position = _position;
    if (_busy || position == null) return;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      await HrmsTrackingApi.submitHomeLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        capturedAt: position.timestamp.toUtc().toIso8601String(),
        address: _addressController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _home = {
          ...?_home,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'address': _addressController.text.trim(),
          'approval_status': 'pending',
          'rejection_reason': null,
        };
        _position = null;
        _notice =
            'Home location submitted. An admin must approve it before '
            'Home Clock In is available.';
      });
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _coordinates(Object? latitude, Object? longitude) {
    final lat = double.tryParse('$latitude');
    final lng = double.tryParse('$longitude');
    if (lat == null || lng == null) return 'Not registered';
    return '${lat.toStringAsFixed(7)}, ${lng.toStringAsFixed(7)}';
  }

  @override
  Widget build(BuildContext context) {
    final status = _home?['approval_status']?.toString() ?? 'not registered';
    final statusText = switch (status) {
      'approved' => 'Approved',
      'pending' => 'Pending admin approval',
      'rejected' => 'Rejected',
      _ => 'Not registered',
    };

    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Home Location'),
        content: SizedBox(
          width: 460,
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Status: $statusText',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (_home != null) ...[
                        const SizedBox(height: 8),
                        SelectableText(
                          'Registered GPS: '
                          '${_coordinates(_home!['latitude'], _home!['longitude'])}',
                        ),
                        if (status == 'rejected' &&
                            _home!['rejection_reason'] != null) ...[
                          const SizedBox(height: 8),
                          Text('Admin reason: ${_home!['rejection_reason']}'),
                        ],
                      ],
                      if (!_loadFailed) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'When you are at home, capture your current '
                          'GPS location and submit it for approval.',
                        ),
                        if (status == 'approved') ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Updating your approved location requires '
                            'new admin approval. Home Clock In will be blocked '
                            'until the new location is approved.',
                          ),
                        ],
                        const SizedBox(height: 16),
                        TextField(
                          controller: _addressController,
                          enabled: !_busy,
                          maxLength: 500,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Home address (optional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _capture,
                          icon: const Icon(Icons.my_location),
                          label: Text(
                            _capturing
                                ? 'Getting location...'
                                : 'Capture Home GPS',
                          ),
                        ),
                        if (_position != null) ...[
                          const SizedBox(height: 8),
                          SelectableText(
                            'Captured GPS: '
                            '${_coordinates(_position!.latitude, _position!.longitude)}',
                          ),
                          Text(
                            'GPS accuracy: '
                            '${_position!.accuracy.toStringAsFixed(0)} metres',
                          ),
                        ],
                      ],
                      if (_notice != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _notice!,
                          style: const TextStyle(color: Color(0xFF138A20)),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      if (_loadFailed)
                        TextButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: _loading || _loadFailed || _busy || _position == null
                ? null
                : _submit,
            child: Text(
              _saving
                  ? 'Submitting...'
                  : _home == null
                  ? 'Register Home Location'
                  : 'Update Home Location',
            ),
          ),
        ],
      ),
    );
  }
}
