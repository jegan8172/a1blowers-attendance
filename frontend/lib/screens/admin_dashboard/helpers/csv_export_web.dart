import 'dart:html' as html;
import 'dart:typed_data';

Future<void> saveAndShareCsv(List<int> bytes, String fileName) async {
  // ✅ FIX: Convert to Uint8List so Blob handles raw bytes properly instead of string coercion
  final bytesData = Uint8List.fromList(bytes);
  final contentType = fileName.toLowerCase().endsWith('.xlsx')
      ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      : 'text/csv;charset=utf-8;';
  final blob = html.Blob([bytesData], contentType);
  final url = html.Url.createObjectUrlFromBlob(blob);

  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();

  html.Url.revokeObjectUrl(url);
}
