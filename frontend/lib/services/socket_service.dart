import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'api_config.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  late IO.Socket socket;
  bool _isInitialized = false;

  void init() {
    if (_isInitialized) return;
    
    socket = IO.io(ApiConfig.baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });

    socket.onConnect((_) {
      print('🟢 Global Socket Connected: ${socket.id}');
    });

    _isInitialized = true;
  }
}