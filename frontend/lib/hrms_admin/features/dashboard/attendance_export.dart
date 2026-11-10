import 'package:excel/excel.dart';
import 'dart:convert';
import 'package:archive/archive.dart';

/// Creates an actual Excel workbook; strings remain text, including names that
/// start with characters Excel might otherwise interpret as formulas.
List<int> buildAttendanceWorkbook({
  required String title,
  required List<String> headers,
  required List<List<Object?>> rows,
  List<int>? logo,
}) {
  final workbook = Excel.createExcel();
  final sheet = workbook['Attendance'];
  workbook.delete('Sheet1');
  sheet.appendRow([TextCellValue(title)]);
  if (logo != null) sheet.setRowHeight(0, 36);
  sheet.appendRow(headers.map((header) => TextCellValue(header)).toList());
  sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).cellStyle = CellStyle(
    bold: true, fontSize: 16, fontColorHex: ExcelColor.fromHexString('FF1769E0'),
  );
  final headerStyle = CellStyle(
    bold: true, fontColorHex: ExcelColor.white,
    backgroundColorHex: ExcelColor.fromHexString('FF1769E0'),
    horizontalAlign: HorizontalAlign.Center,
  );
  for (var column = 0; column < headers.length; column++) {
    sheet.setColumnWidth(column, column < 2 ? 24 : 16);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 1)).cellStyle = headerStyle;
  }
  for (final row in rows) {
    sheet.appendRow(row.map((value) => switch (value) {
      int n => IntCellValue(n),
      double n => DoubleCellValue(n),
      _ => TextCellValue(value?.toString() ?? ''),
    }).toList());
  }
  final bytes = workbook.encode();
  if (bytes == null) throw StateError('Could not create the Excel workbook.');
  if (logo == null || logo.isEmpty) return bytes;
  final input = ZipDecoder().decodeBytes(bytes);
  final output = Archive();
  for (final file in input.files) {
    var data = file.content as List<int>;
    if (file.name == 'xl/worksheets/sheet1.xml') {
      var xml = utf8.decode(data);
      if (!xml.contains('xmlns:r=')) xml = xml.replaceFirst('<worksheet ', '<worksheet xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" ');
      xml = xml.replaceFirst('</worksheet>', '<drawing r:id="rId1"/></worksheet>');
      data = utf8.encode(xml);
    } else if (file.name == '[Content_Types].xml') {
      var xml = utf8.decode(data);
      if (!xml.contains('Extension="png"')) xml = xml.replaceFirst('</Types>', '<Default Extension="png" ContentType="image/png"/></Types>');
      xml = xml.replaceFirst('</Types>', '<Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/></Types>');
      data = utf8.encode(xml);
    }
    output.addFile(ArchiveFile(file.name, data.length, data));
  }
  void add(String path, String contents) { final data = utf8.encode(contents); output.addFile(ArchiveFile(path, data.length, data)); }
  add('xl/worksheets/_rels/sheet1.xml.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/></Relationships>');
  add('xl/drawings/drawing1.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><xdr:oneCellAnchor><xdr:from><xdr:col>4</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>0</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from><xdr:ext cx="1143000" cy="381000"/><xdr:pic><xdr:nvPicPr><xdr:cNvPr id="1" name="A1 Blowers logo"/><xdr:cNvPicPr/></xdr:nvPicPr><xdr:blipFill><a:blip r:embed="rId1"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill><xdr:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="1143000" cy="381000"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic><xdr:clientData/></xdr:oneCellAnchor></xdr:wsDr>');
  add('xl/drawings/_rels/drawing1.xml.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/a1_logo.png"/></Relationships>');
  output.addFile(ArchiveFile('xl/media/a1_logo.png', logo.length, logo));
  return ZipEncoder().encode(output)!;
}
