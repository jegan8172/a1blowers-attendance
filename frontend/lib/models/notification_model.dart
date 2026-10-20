// models/notification_model.dart

class NotificationMessage {
  int? id;
  String fromUser;
  String toUser;
  String type; // 'received', 'sent', 'day_planner'
  String title;
  String message;
  bool isRead;
  DateTime createdAt;
  Map<String, dynamic>? metadata; // For day planner table data

  NotificationMessage({
    this.id,
    required this.fromUser,
    required this.toUser,
    required this.type,
    required this.title,
    required this.message,
    this.isRead = false,
    required this.createdAt,
    this.metadata,
  });

  factory NotificationMessage.fromJson(Map<String, dynamic> json) {
    return NotificationMessage(
      id: json['id'],
      fromUser: json['fromUser'] ?? json['from_user'] ?? '',
      toUser: json['toUser'] ?? json['to_user'] ?? '',
      type: json['type'] ?? 'received',
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      isRead: json['isRead'] ?? json['is_read'] ?? false,
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt']) 
          : DateTime.now(),
      metadata: json['metadata'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fromUser': fromUser,
      'toUser': toUser,
      'type': type,
      'title': title,
      'message': message,
      'isRead': isRead,
      'createdAt': createdAt.toIso8601String(),
      'metadata': metadata,
    };
  }
}

class NotificationUser {
  String name;
  int unreadCount;
  List<NotificationMessage> messages;

  NotificationUser({
    required this.name,
    this.unreadCount = 0,
    this.messages = const [],
  });
}