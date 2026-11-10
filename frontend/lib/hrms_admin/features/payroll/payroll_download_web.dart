// ignore_for_file: deprecated_member_use

import 'dart:html' as html;

Future<void> downloadTextFile(
    String filename, String content, String mimeType) async {
  final blob = html.Blob([content], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none'
    ..click();
  html.Url.revokeObjectUrl(url);
}
