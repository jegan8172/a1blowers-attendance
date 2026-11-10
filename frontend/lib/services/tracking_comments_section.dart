import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'auth_storage.dart';
import 'tracking_comments_api.dart';

class TrackingCommentsSection extends StatefulWidget {
  const TrackingCommentsSection({super.key});

  @override
  State<TrackingCommentsSection> createState() =>
      _TrackingCommentsSectionState();
}

class _TrackingCommentsSectionState extends State<TrackingCommentsSection> {
  final controller = TextEditingController();
  bool saving = false;

  Future<void> _save() async {
    final text = controller.text.trim();
    if (text.isEmpty) return;
    final token = await AuthStorage.getString('auth_token');
    if (token == null || token.isEmpty) return;
    setState(() => saving = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        throw Exception('Turn on location before submitting a comment.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission is required for comments.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      await TrackingCommentsApi.addComment(
        token,
        text,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      controller.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFFBFF),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFD9E2F2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Align(
              alignment: Alignment.centerRight,
              child: TrackingCommentsHistoryButton(),
            ),
            const SizedBox(height: 12),
            const Text(
              'Employee Comments',
              style: TextStyle(
                color: Color(0xFF061457),
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Write a comment',
                labelStyle: const TextStyle(color: Color(0xFF64748B)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                  borderSide: const BorderSide(color: Color(0xFFD9E2F2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                  borderSide: const BorderSide(
                    color: Color(0xFF075EF7),
                    width: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF075EF7),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(saving ? 'Saving…' : 'Submit Comment'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TrackingCommentsHistoryButton extends StatelessWidget {
  const TrackingCommentsHistoryButton({super.key});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: () => showDialog<void>(
      context: context,
      builder: (_) => const _TrackingCommentsHistoryDialog(),
    ),
    icon: const Icon(Icons.history_rounded, size: 18),
    label: const Text('Comment History'),
  );
}

class _TrackingCommentsHistoryDialog extends StatefulWidget {
  const _TrackingCommentsHistoryDialog();
  @override
  State<_TrackingCommentsHistoryDialog> createState() =>
      _TrackingCommentsHistoryDialogState();
}

class _TrackingCommentsHistoryDialogState
    extends State<_TrackingCommentsHistoryDialog> {
  late Future<List<Map<String, dynamic>>> _history;
  late Future<List<Map<String, dynamic>>> _popupHistory;
  @override
  void initState() {
    super.initState();
    _history = _loadHistory();
    _popupHistory = _loadPopupHistory();
  }

  Future<List<Map<String, dynamic>>> _loadHistory() async {
    final token = await AuthStorage.getString('auth_token');
    if (token == null || token.isEmpty) return const [];
    return TrackingCommentsApi.myComments(token);
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: AlertDialog(
      insetPadding: const EdgeInsets.all(20),
      title: const Text('Comment History'),
      content: SizedBox(
        width: 620,
        height: 440,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _history,
          builder: (context, permanentSnapshot) {
            if (permanentSnapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (permanentSnapshot.hasError) {
              return const Center(child: Text('Unable to load comment history.'));
            }
            return Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: 'Permanent comments'),
                    Tab(text: 'Popup comments'),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: TabBarView(
                    children: [
                      _CommentHistoryList(
                        items: permanentSnapshot.data ?? const [],
                        emptyText: 'No permanent comments yet.',
                        popupComments: false,
                      ),
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: _popupHistory,
                        builder: (context, popupSnapshot) {
                          if (popupSnapshot.connectionState != ConnectionState.done) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (popupSnapshot.hasError) {
                            return const Center(
                              child: Text('Unable to load popup comments.'),
                            );
                          }
                          return _CommentHistoryList(
                            items: popupSnapshot.data ?? const [],
                            emptyText: 'No popup comments yet.',
                            popupComments: true,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Future<List<Map<String, dynamic>>> _loadPopupHistory() async {
    final token = await AuthStorage.getString('auth_token');
    if (token == null || token.isEmpty) return const [];
    return TrackingCommentsApi.myPopupComments(token);
  }
}

class _CommentHistoryList extends StatelessWidget {
  const _CommentHistoryList({
    required this.items,
    required this.emptyText,
    required this.popupComments,
  });

  final List<Map<String, dynamic>> items;
  final String emptyText;
  final bool popupComments;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return Center(child: Text(emptyText));

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 20),
      itemBuilder: (_, index) {
        final item = items[index];
        final timestamp = popupComments
            ? item['reasonSubmittedAt'] ?? item['waitingDetectedAt']
            : item['createdAt'];
        final location = item['address'] ??
            ((item['latitude'] != null && item['longitude'] != null)
                ? 'GPS: ${item['latitude']}, ${item['longitude']}'
                : 'Location not recorded');
        final title = popupComments
            ? 'Waiting reason: ${item['reason'] ?? ''}'
            : '${item['comment'] ?? ''}';
        final waitingTime = popupComments && item['waitingMinutes'] != null
            ? '\nWaiting time: ${item['waitingMinutes']} min'
            : '';

        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            popupComments ? Icons.notifications_active_outlined : Icons.chat_bubble_outline,
            color: const Color(0xFF075EF7),
          ),
          title: Text(title),
          subtitle: Text('$timestamp$waitingTime\n$location'),
        );
      },
    );
  }
}
