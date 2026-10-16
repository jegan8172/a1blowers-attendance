import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> downloadPayslipPdf(List<int> bytes, String filename) async {
  final temporaryDirectory = await getTemporaryDirectory();
  final file = File(
    '${temporaryDirectory.path}${Platform.pathSeparator}$filename',
  );
  await file.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles([
    XFile(file.path, mimeType: 'application/pdf'),
  ], subject: filename);
}
