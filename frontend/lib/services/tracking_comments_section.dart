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
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD9E2F2)),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14141E33),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(
            height: 4,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFBFDBFE),
                    Color(0xFF2563EB),
                    Color(0xFFBFDBFE),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF3FF),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        color: Color(0xFF2563EB),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Employee Comments',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const _CompactHistoryButton(),
                  ],
                ),
                const SizedBox(height: 13),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _QuickCommentChip(
                      label: 'Reached site',
                      onTap: () =>
                          setState(() => controller.text = 'Reached site'),
                    ),
                    _QuickCommentChip(
                      label: 'In transit',
                      onTap: () =>
                          setState(() => controller.text = 'In transit'),
                    ),
                    _QuickCommentChip(
                      label: 'In meeting',
                      onTap: () =>
                          setState(() => controller.text = 'In meeting'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  minLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Write a comment...',
                    hintStyle: const TextStyle(color: Color(0xFF71809A)),
                    contentPadding: const EdgeInsets.all(14),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFD),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFD9E2F2)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: Color(0xFF2563EB),
                        width: 1.7,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 13),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 46),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    icon: const Icon(Icons.send_outlined, size: 17),
                    label: Text(
                      saving ? 'Saving…' : 'Submit Comment',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickCommentChip extends StatelessWidget {
  const _QuickCommentChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFF1F5F9),
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD9E2F2)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF41516D),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}

class _CompactHistoryButton extends StatelessWidget {
  const _CompactHistoryButton();

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: () => showDialog<void>(
      context: context,
      builder: (_) => const _TrackingCommentsHistoryDialog(),
    ),
    style: OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFF2563EB),
      minimumSize: const Size(0, 34),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      side: const BorderSide(color: Color(0xFFBFDBFE)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    icon: const Icon(Icons.history_rounded, size: 15),
    label: const Text(
      'History',
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
    ),
  );
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
              return const Center(
                child: Text('Unable to load comment history.'),
              );
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
                          if (popupSnapshot.connectionState !=
                              ConnectionState.done) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
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
        final location =
            item['address'] ??
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
            popupComments
                ? Icons.notifications_active_outlined
                : Icons.chat_bubble_outline,
            color: const Color(0xFF075EF7),
          ),
          title: Text(title),
          subtitle: Text('$timestamp$waitingTime\n$location'),
        );
      },
    );
  }
}
