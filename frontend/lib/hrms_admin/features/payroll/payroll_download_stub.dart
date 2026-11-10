import 'package:flutter/services.dart';

Future<void> downloadTextFile(
    String filename, String content, String mimeType) async {
  await Clipboard.setData(ClipboardData(text: content));
}
