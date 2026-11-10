import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../constants/app_colors.dart';
import '../constants/employee_role.dart';
import '../../services/auth_service.dart';
import '../../services/api_config.dart';

class EmployeeTopbar extends StatefulWidget {
  final EmployeeRole role;
  final VoidCallback? onOpenNotifications;
  final VoidCallback? onOpenAssignedTasks;
  final VoidCallback? onTapWorkingHours;
  final Function(String)? onSearch;

  const EmployeeTopbar({
    super.key,
    required this.role,
    this.onOpenNotifications,
    this.onOpenAssignedTasks,
    this.onTapWorkingHours,
    this.onSearch,
  });

  @override
  State<EmployeeTopbar> createState() => _EmployeeTopbarState();
}

class _EmployeeTopbarState extends State<EmployeeTopbar> with TickerProviderStateMixin {
  Timer? _pollingTimer;
  int _unreadCount = 0;
  String? _latestMessage;
  bool _showPopup = false;
  Timer? _popupTimer;
  final AudioPlayer _audioPlayer = AudioPlayer();
  IO.Socket? _socket;
  Set<int> _knownNotificationIds = {};
  final TextEditingController _searchController = TextEditingController();

  String formattedTotalWorkingTime = "00h 00m";

  // 🟢 Controllers for 3D rotation, High-intensity neon glow, and Color Shifting
  late AnimationController _rotateController;
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  // State to track hover or pause state for rotation
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();

    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 4.0, end: 16.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _startPolling();
    _fetchTodayWorkingHours();
    _connectNotificationSocket();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _popupTimer?.cancel();
    _searchController.dispose();
    _socket?.dispose();
    _audioPlayer.dispose();
    _rotateController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  String get _socketUrl {
    return ApiConfig.baseUrl.trim().replaceFirst(RegExp(r'/api/?$'), '');
  }

  void _connectNotificationSocket() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final employeeName = authService.user?['fullName'];
    if (employeeName == null || employeeName.toString().isEmpty) return;

    try {
      _socket = IO.io(_socketUrl, {
        'transports': ['websocket'],
        'autoConnect': false,
        'reconnection': true,
      });

      _socket!.connect();

      void handle(dynamic payload) {
        if (!mounted || payload is! Map) return;
        final recipient = payload['recipientName']?.toString() ?? '';
        final sender = payload['senderName']?.toString() ?? '';
        final isGroup = payload['isGroup'] == true ||
            payload['isGroup'] == 1 ||
            payload['isGroup']?.toString() == '1';

        if (isGroup || recipient != employeeName || sender == employeeName) return;

        final id = int.tryParse(payload['id']?.toString() ?? '') ?? 0;
        if (id != 0 && _knownNotificationIds.contains(id)) return;
        if (id != 0) _knownNotificationIds.add(id);

        setState(() => _unreadCount += 1);

        final raw = payload['message']?.toString() ?? 'New message';
        String preview = raw;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            preview = decoded['preview']?.toString() ??
                decoded['text']?.toString() ??
                (decoded['fileName'] != null ? '📎 ${decoded['fileName']}' : raw);
          }
        } catch (_) {}

        _playNotificationSound();
        _triggerTopRightPopup(preview);
      }

      _socket!.on('new_notification', handle);
    } catch (e) {
      debugPrint('Topbar socket init error: $e');
    }
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      await _checkNewNotifications();
      await _fetchTodayWorkingHours();
    });
  }

  Future<void> _fetchTodayWorkingHours() async {
    if (!mounted) return;
    final authService = Provider.of<AuthService>(context, listen: false);
    final employeeName = authService.user?['fullName'] ?? authService.user?['name'] ?? authService.user?['username'];
    
    if (employeeName == null || employeeName.isEmpty) return;

    try {
      final now = DateTime.now();
      final formattedDate = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      
      final url = Uri.parse('${ApiConfig.baseUrl}/dashboard/live-tracking-tasks/$employeeName?date=$formattedDate');
      final r = await http.get(url);

      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        final rows = List<dynamic>.from(body['data'] ?? []);

        int totalSumSeconds = 0;
        for (var row in rows) {
          String durStr = (row["duration"] ?? "").toString().toLowerCase();
          
          int hrs = 0;
          int mins = 0;

          if (durStr.contains('hrs') || durStr.contains('hr')) {
            final parts = durStr.split('hr');
            hrs = int.tryParse(parts[0].trim()) ?? 0;
            if (parts.length > 1 && parts[1].contains('min')) {
              final minPart = parts[1].replaceAll('s', '').replaceAll('mins', '').replaceAll('min', '').trim();
              mins = int.tryParse(minPart) ?? 0;
            }
          } else if (durStr.contains('min')) {
            final minPart = durStr.replaceAll('s', '').replaceAll('mins', '').replaceAll('min', '').trim();
            mins = int.tryParse(minPart) ?? 0;
          }

          totalSumSeconds += (hrs * 3600) + (mins * 60);
        }

        int totalHours = totalSumSeconds ~/ 3600;
        int totalMinutes = (totalSumSeconds % 3600) ~/ 60;

        if (mounted) {
          setState(() {
            formattedTotalWorkingTime = '${totalHours.toString().padLeft(2, '0')}h ${totalMinutes.toString().padLeft(2, '0')}m';
          });
        }
      }
    } catch (e) {
      debugPrint("Working hours fetch error: $e");
    }
  }

  Future<void> _checkNewNotifications() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final employeeName = authService.user?['fullName'];
    
    if (employeeName == null || employeeName.isEmpty) return;

    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/notifications/${Uri.encodeComponent(employeeName)}');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List rows = body["data"] ?? [];

        int unread = 0;
        Set<int> currentIds = {};
        bool hasNewNotification = false;
        String? latestMsgText;

        for (var row in rows) {
          int id = int.tryParse(row["id"]?.toString() ?? '0') ?? 0;
          currentIds.add(id);

          bool isSentByMe = row["type"] == "SENT";
          bool isSeen = row["isSeen"] == true || row["isSeen"] == 1 || row["isSeen"].toString() == "true";

          if (!isSentByMe && !isSeen) {
            unread++;
          }

          if (_knownNotificationIds.isNotEmpty && !_knownNotificationIds.contains(id) && !isSentByMe && !isSeen) {
            hasNewNotification = true;
            try {
              final decoded = jsonDecode(row["message"]);
              final preview = decoded["preview"] ?? "New Notification";
              latestMsgText = preview;
            } catch (e) {
              latestMsgText = row["message"] ?? "New Notification";
            }
          }
        }

        setState(() {
          _unreadCount = unread;
          if (_knownNotificationIds.isEmpty && currentIds.isNotEmpty) {
            _knownNotificationIds = currentIds;
          } else if (currentIds.isNotEmpty) {
            _knownNotificationIds = currentIds;
          }
        });

         if (hasNewNotification) {
          _playNotificationSound();
          _triggerTopRightPopup(latestMsgText ?? "You have a new notification");
        }
      }
    } catch (e) {
      debugPrint("Polling error: $e");
    }
  }

  void _playNotificationSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/notification.mp3'));
    } catch (e) {
      debugPrint("Audio play error: $e");
    }
  }

   void _triggerTopRightPopup(String message) {
    setState(() {
      _latestMessage = message;
      _showPopup = true;
    });

    _popupTimer?.cancel();
    _popupTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() {
          _showPopup = false;
        });
      }
    });
  }

 @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width >= 900;
    final bool isSmallMobile = MediaQuery.of(context).size.width < 450;

    return SizedBox(
      height: 64,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 64,
            padding: EdgeInsets.symmetric(horizontal: isSmallMobile ? 8 : 18),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: AppColors.border),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (!isDesktop) ...[
                  Builder(
                    builder: (ctx) => IconButton(
                      icon: const Icon(Icons.menu_rounded, color: AppColors.textDark),
                      onPressed: () => Scaffold.of(ctx).openDrawer(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                  SizedBox(width: isSmallMobile ? 4 : 12),
                ],

                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 8),
                          const Icon(Icons.search, size: 16, color: AppColors.textGrey),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              onChanged: (value) {
                                setState(() {});
                                widget.onSearch?.call(value);
                              },
                              decoration: const InputDecoration(
                                hintText: 'Search tasks, clients...',
                                hintStyle: TextStyle(fontSize: 12, color: AppColors.textGrey),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          if (_searchController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.close, size: 16, color: AppColors.textGrey),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                              onPressed: () {
                                _searchController.clear();
                                widget.onSearch?.call('');
                                setState(() {});
                              },
                            ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(width: 8),

                // 🟢 3D Rotating Container with Mouse Hover and Tap Pause Functionality
                MouseRegion(
                  onEnter: (_) {
                    setState(() {
                      _isPaused = true;
                      _rotateController.stop();
                    });
                  },
                  onExit: (_) {
                    setState(() {
                      _isPaused = false;
                      _rotateController.repeat();
                    });
                  },
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _isPaused = !_isPaused;
                        if (_isPaused) {
                          _rotateController.stop();
                        } else {
                          _rotateController.repeat();
                        }
                      });
                      widget.onTapWorkingHours?.call();
                    },
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_rotateController, _glowAnimation]),
                      builder: (context, child) {
                        final double angle = _isPaused 
                            ? 0.0 
                            : _rotateController.value * 2 * 3.141592653589793;
                        final bool isBackSide = angle > (3.141592653589793 / 2) && angle < (3 * 3.141592653589793 / 2);
                        final double currentGlow = _glowAnimation.value;

                        return Transform(
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.001)
                            ..rotateY(angle),
                          alignment: Alignment.center,
                          child: Transform(
                            transform: Matrix4.identity()
                              ..rotateY(isBackSide ? 3.141592653589793 : 0.0),
                            alignment: Alignment.center,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.cyanAccent.withValues(alpha: 0.6),
                                    blurRadius: currentGlow * 1.5,
                                    spreadRadius: currentGlow * 0.4,
                                  ),
                                  BoxShadow(
                                    color: Colors.purpleAccent.withValues(alpha: 0.5),
                                    blurRadius: currentGlow * 2,
                                    spreadRadius: currentGlow * 0.2,
                                  ),
                                ],
                              ),
                              child: child,
                            ),
                          ),
                        );
                      },
                      child: Material(
                        color: const Color.fromARGB(255, 245, 249, 255),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {}, // Handled by outer GestureDetector
                          child: CustomPaint(
                            painter: MovingNeonBorderPainter(
                              animationValue: _isPaused ? 0.0 : _rotateController.value,
                              borderRadius: BorderRadius.circular(8),
                              strokeWidth: 2.5,
                            ),
                            child: Container(
                              height: 38,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: const Color.fromARGB(0, 14, 65, 141),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.bolt_rounded, size: 16, color: Colors.cyanAccent),
                                  const SizedBox(width: 4),
                                  ShaderMask(
                                    shaderCallback: (bounds) {
                                      return LinearGradient(
                                        colors: const [
                                          Colors.cyanAccent,
                                          Colors.blueAccent,
                                          Colors.purpleAccent,
                                          Colors.pinkAccent,
                                          Colors.cyanAccent,
                                        ],
                                        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                                        transform: GradientRotation(_isPaused ? 0.0 : _rotateController.value * 2 * 3.141592653589793),
                                      ).createShader(bounds);
                                    },
                                    child: Text(
                                      isSmallMobile ? "Today: $formattedTotalWorkingTime" : "Today Working Hours: $formattedTotalWorkingTime",
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                
                Stack(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_none_rounded, size: 20, color: AppColors.textDark),
                      onPressed: widget.onOpenNotifications,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                    ),
                    if (_unreadCount > 0)
                      Positioned(
                        right: 2,
                        top: 2,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          child: Text(
                            '$_unreadCount',
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                
                if (!isSmallMobile) ...[
                  const SizedBox(width: 16),
                  const Icon(Icons.help_outline_rounded, size: 18, color: AppColors.textDark),
                  const SizedBox(width: 16),
                  Container(height: 30, width: 1, color: AppColors.border),
                  const SizedBox(width: 14),
                ],

                // employee_topbar.dart-il ulla Consumer<AuthService> block-ai inthapadi update seiyungal:

    Consumer<AuthService>(
      builder: (context, authService, _) {
        final user = authService.user;
        final employeeName = user?['fullName'] ?? 'Employee';
        final employeeRole = user?['role'] ?? widget.role.title;
        final initials = user?['initials'] ?? _generateInitials(employeeName);

        // 🟢 Profile photo and avatar color from auth session
        final String? profilePhoto = user?['profile_photo']?.toString() ?? user?['profilePhoto']?.toString();
        final String avatarColorHex = user?['avatar_color']?.toString() ?? user?['avatarColor']?.toString() ?? '';

        Color avatarColor = AppColors.primary;
        if (avatarColorHex.isNotEmpty) {
          try {
            final s = avatarColorHex.replaceAll('#', '');
            avatarColor = Color(int.parse('FF$s', radix: 16));
          } catch (_) {}
        }

        ImageProvider? profileImage;
        if (profilePhoto != null && profilePhoto.isNotEmpty) {
          try {
            profileImage = MemoryImage(base64Decode(profilePhoto.split(',').last));
          } catch (_) {}
        }

        if (!isDesktop) {
          return PopupMenuButton<int>(
            offset: const Offset(0, 45),
            icon: CircleAvatar(
              radius: 16,
              backgroundColor: avatarColor,
              backgroundImage: profileImage,
              child: profileImage == null
                  ? Text(initials, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800))
                  : null,
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(employeeName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textDark)),
                    const SizedBox(height: 2),
                    Text(employeeRole, style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
                  ],
                ),
              ),
            ],
          );
        }

        return Row(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  employeeName,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textDark),
                ),
                Text(
                  employeeRole,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textGrey),
                ),
              ],
            ),
            const SizedBox(width: 10),
            CircleAvatar(
              radius: 16,
              backgroundColor: avatarColor,
              backgroundImage: profileImage,
              child: profileImage == null
                  ? Text(
                      initials,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                    )
                  : null,
            ),
          ],
        );
      },
    ),
             ],
            ),
          ),

          if (_showPopup)
            Positioned(
              top: 68,
              right: 20,
              child: Material(
                color: Colors.transparent,
                elevation: 8,
                child: Container(
                  width: 300,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 4)),
                    ],
                    border: Border.all(color: AppColors.primary, width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_active_rounded, color: AppColors.primary, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text("New Notification", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textDark)),
                            const SizedBox(height: 2),
                            Text(
                              _latestMessage ?? "",
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: AppColors.textGrey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
 
  String _generateInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return (parts.first[0] + parts.last[0]).toUpperCase();
    } else {
      return parts.first[0].toUpperCase();
    }
  }
}

// 🟢 High-Intensity Neon Moving Border Custom Painter
class MovingNeonBorderPainter extends CustomPainter {
  final double animationValue;
  final BorderRadius borderRadius;
  final double strokeWidth;

  MovingNeonBorderPainter({
    required this.animationValue,
    required this.borderRadius,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rRect = borderRadius.toRRect(rect);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = SweepGradient(
        center: Alignment.center,
        startAngle: 0.0,
        endAngle: 2 * 3.141592653589793,
        colors: const [
          Colors.cyanAccent,
          Colors.blueAccent,
          Colors.purpleAccent,
          Colors.pinkAccent,
          Colors.amberAccent,
          Colors.cyanAccent,
        ],
        transform: GradientRotation(animationValue * 2 * 3.141592653589793),
      ).createShader(rect);

    canvas.drawRRect(rRect, paint);
  }

  @override
  bool shouldRepaint(covariant MovingNeonBorderPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}