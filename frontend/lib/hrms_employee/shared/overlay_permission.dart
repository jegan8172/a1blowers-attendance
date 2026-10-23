import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android overlay permission helper. The waiting notification remains the
/// reliable fallback when the employee declines this optional permission.
class OverlayPermission {
  OverlayPermission._();

  static const _channel = MethodChannel('com.a1blowers.attendance/overlay');

  static Future<bool> canDrawOverlays() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    return await _channel.invokeMethod<bool>('canDrawOverlays') ?? false;
  }

  static Future<void> openSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('openOverlaySettings');
  }

  static Future<bool> showTrackingBubble() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    return await _channel.invokeMethod<bool>('showTrackingBubble') ?? false;
  }

  static Future<void> hideTrackingBubble() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('hideTrackingBubble');
  }
}
