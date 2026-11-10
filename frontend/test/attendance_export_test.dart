import 'package:excel/excel.dart';
import 'package:archive/archive.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:godigital_portal/hrms_admin/features/dashboard/attendance_export.dart';

void main() {
  test('creates an Excel workbook with attendance data and literal names', () {
    final bytes = buildAttendanceWorkbook(
      title: 'January 2026 Attendance',
      headers: ['Employee Name', '1 Thu', 'Present'],
      rows: [['=Example', 'P', 1]],
    );
    expect(bytes.take(2), [0x50, 0x4b]);
    final workbook = Excel.decodeBytes(bytes);
    final rows = workbook['Attendance'].rows;
    expect(rows[0][0]?.value.toString(), 'January 2026 Attendance');
    expect(rows[1][1]?.value.toString(), '1 Thu');
    expect(rows[2][0]?.value, isA<TextCellValue>());
    expect(rows[2][0]?.value.toString(), '=Example');
    expect((rows[2][2]?.value as IntCellValue).value, 1);
  });
  test('embeds the logo as an Excel drawing', () {
    final bytes = buildAttendanceWorkbook(title: 'Attendance', headers: ['Employee'], rows: [], logo: [137, 80, 78, 71]);
    final zip = ZipDecoder().decodeBytes(bytes);
    expect(zip.findFile('xl/media/a1_logo.png'), isNotNull);
    expect(zip.findFile('xl/drawings/drawing1.xml'), isNotNull);
    final worksheet = utf8.decode(zip.findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
    expect(worksheet, contains('<drawing r:id="rId1"/>'));
    expect(Excel.decodeBytes(bytes)['Attendance'].rows[0][0]?.value.toString(), 'Attendance');
  });
}
