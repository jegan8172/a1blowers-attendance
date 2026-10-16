
import 'package:flutter/foundation.dart';

class ApiConfig {
  static const String _productionBaseUrl =
      'https://attendance.godigitalindia.co/api';

  static const String _productionSocketUrl =
      'https://attendance.godigitalindia.co';

  static String get baseUrl {
    if (kIsWeb) {
      if (Uri.base.host == 'localhost' ||
          Uri.base.host == '127.0.0.1') {
        return 'http://localhost:3000/api';
      }

      return '/api';
    }

    // Android APK: use the live production server.
    return _productionBaseUrl;
  }

  static String get socketUrl {
    if (kIsWeb) {
      if (Uri.base.host == 'localhost' ||
          Uri.base.host == '127.0.0.1') {
        return 'http://localhost:3000';
      }

      return Uri.base.origin;
    }

    // Android APK: use the live production server.
    return _productionSocketUrl;
  }

  static String mediaUrl(String path) {
    if (path.startsWith('http://') ||
        path.startsWith('https://')) {
      return path;
    }

    if (kIsWeb) {
      return '${Uri.base.origin}$path';
    }

    return '$socketUrl$path';
  }
}
