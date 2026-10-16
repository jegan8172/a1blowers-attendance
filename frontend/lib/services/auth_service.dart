import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_storage.dart';

class AuthService extends ChangeNotifier {
  static String get baseUrl => ApiConfig.baseUrl;

  String? _token;
  Map<String, dynamic>? _user;
  bool _isLoading = false;
  String? _error;
  String? _errorCode;
  bool _isInitialized = false;

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get errorCode => _errorCode;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;
  bool get isInitialized => _isInitialized;

  String? get userRole => _user?['role']?.toString();

  String? get userId => _user?['id']?.toString();

  String? get userType => _user?['userType']?.toString();

  AuthService() {
    _loadStoredToken();
  }

  Future<String> _deviceId() async {
    final existing = await AuthStorage.getString('browser_installation_id');
    if (existing != null && existing.length >= 16) return existing;
    final random = Random.secure();
    final value = List.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    await AuthStorage.setString('browser_installation_id', value);
    return value;
  }

  Future<void> _loadStoredToken() async {
    try {
      _token = await AuthStorage.getString('auth_token');

      final userJson = await AuthStorage.getString('user_data');

      if (_token != null && userJson != null && userJson.isNotEmpty) {
        final decoded = jsonDecode(userJson);

        if (decoded is Map) {
          _user = Map<String, dynamic>.from(decoded);
        }
      }
    } catch (error) {
      debugPrint('Error loading stored token: $error');

      _token = null;
      _user = null;
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<bool> login(
    String email,
    String password,
    bool isAdmin,
    bool rememberDevice, {
    String? deviceChangeReason,
  }) async {
    _isLoading = true;
    _error = null;
    _errorCode = null;
    notifyListeners();

    final selectedUserType = isAdmin ? 'admin' : 'employee';

    final loginUrl = Uri.parse('$baseUrl/auth/login');

    debugPrint('Login URL: $loginUrl');
    debugPrint('Login username: $email');
    debugPrint('Login user type: $selectedUserType');

    try {
      final deviceId = await _deviceId();
      final response = await http
          .post(
            loginUrl,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'email': email.trim(),
              'password': password,
              'userType': selectedUserType,
              'deviceId': deviceId,
              'deviceLabel': 'Browser device',
              if (deviceChangeReason != null)
                'deviceChangeReason': deviceChangeReason,
            }),
          )
          .timeout(const Duration(seconds: 15));

      Map<String, dynamic> data = {};

      if (response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);

        if (decoded is Map) {
          data = Map<String, dynamic>.from(decoded);
        }
      }

      if (response.statusCode == 200 &&
          data['success'] == true &&
          data['token'] != null &&
          data['user'] is Map) {
        _token = data['token'].toString();

        _user = Map<String, dynamic>.from(data['user'] as Map);

        _user!['userType'] = _user!['userType'] ?? selectedUserType;

        await AuthStorage.setString('auth_token', _token!);

        await AuthStorage.setString('user_data', jsonEncode(_user));

        await AuthStorage.setBool('isLoggedIn', true);

        await AuthStorage.setString('role', _user?['role']?.toString() ?? '');

        await AuthStorage.setString(
          'userType',
          _user?['userType']?.toString() ?? selectedUserType,
        );

        _error = null;
        _isLoading = false;
        notifyListeners();

        return true;
      }

      _error =
          data['message']?.toString() ??
          'Login failed (${response.statusCode}).';
      _errorCode = data['code']?.toString();

      _isLoading = false;
      notifyListeners();

      return false;
    } catch (error, stackTrace) {
      debugPrint('Login connection error: $error');
      debugPrint('$stackTrace');

      _error = 'Unable to connect to server.';
      _errorCode = null;
      _isLoading = false;
      notifyListeners();

      return false;
    }
  }

  Future<void> logout() async {
    final token = _token;
    try {
      if (token != null && token.isNotEmpty) {
        await http
            .post(
              Uri.parse('$baseUrl/auth/logout'),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(const Duration(seconds: 5));
      }
      await AuthStorage.remove('auth_token');
      await AuthStorage.remove('user_data');
      await AuthStorage.remove('isLoggedIn');
      await AuthStorage.remove('role');
      await AuthStorage.remove('userType');
      await AuthStorage.remove('employeeMenu');
    } catch (error) {
      debugPrint('Error clearing authentication: $error');
    }

    _token = null;
    _user = null;
    _error = null;
    _errorCode = null;

    notifyListeners();
  }

  Future<String?> changePassword({
    required String username,
    required String currentPassword,
    required String newPassword,
    String newUsername = '',
  }) async {
    if (_token == null || _token!.isEmpty) return 'Please sign in again.';
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/change-password'),
            headers: {
              'Authorization': 'Bearer $_token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'username': username.trim(),
              'currentPassword': currentPassword,
              'newPassword': newPassword,
              'newUsername': newUsername.trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));
      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
      final data = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      return data['success'] == true && response.statusCode < 400
          ? null
          : (data['message']?.toString() ?? 'Unable to update password.');
    } catch (_) {
      return 'Unable to connect to server.';
    }
  }

  /// Updates the signed-in session after a profile edit.  Widgets in the
  /// attendance and task areas listen to this service, so they receive the
  /// same identity immediately without another login.
  Future<void> updateProfileCache(Map<String, dynamic> profile) async {
    if (_user == null) return;
    final name = profile['name']?.toString().trim();
    final email = profile['email']?.toString().trim();
    if (name != null && name.isNotEmpty) {
      _user!['fullName'] = name;
      _user!['name'] = name;
    }
    if (email != null && email.isNotEmpty) {
      _user!['email'] = email;
    }
    await AuthStorage.setString('user_data', jsonEncode(_user));
    notifyListeners();
  }

  Future<bool> verifyToken() async {
    if (_token == null || _token!.isEmpty) {
      return false;
    }

    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/auth/verify'),
            headers: {
              'Authorization': 'Bearer $_token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return true;
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        await logout();
      }

      return false;
    } catch (error) {
      debugPrint('Token verification error: $error');

      return false;
    }
  }

  Future<void> refreshUserData() async {
    if (_token == null || _user == null) {
      return;
    }

    final currentUserId = _user?['id'];

    if (currentUserId == null) {
      return;
    }

    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/employees/$currentUserId'),
            headers: {
              'Authorization': 'Bearer $_token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map) {
        return;
      }

      final responseData = Map<String, dynamic>.from(decoded);

      if (responseData['success'] == true && responseData['data'] is Map) {
        final refreshedUser = Map<String, dynamic>.from(
          responseData['data'] as Map,
        );

        final oldUser = _user ?? <String, dynamic>{};

        // 🟢 Profile photo, avatar color, matrum full name-ai rendu variations-layum map seiyungal
        final profilePhoto =
            refreshedUser['profile_photo'] ?? refreshedUser['profilePhoto'];
        final avatarColor =
            refreshedUser['avatar_color'] ?? refreshedUser['avatarColor'];
        final fullName =
            refreshedUser['full_name'] ??
            refreshedUser['fullName'] ??
            refreshedUser['name'];

        _user = {
          ...oldUser,
          ...refreshedUser,
          if (profilePhoto != null) 'profile_photo': profilePhoto,
          if (profilePhoto != null) 'profilePhoto': profilePhoto,
          if (avatarColor != null) 'avatar_color': avatarColor,
          if (avatarColor != null) 'avatarColor': avatarColor,
          if (fullName != null) 'fullName': fullName,
          if (fullName != null) 'name': fullName,
        };

        await AuthStorage.setString('user_data', jsonEncode(_user));

        notifyListeners();
      }
    } catch (error) {
      debugPrint('Error refreshing user data: $error');
    }
  }
}
