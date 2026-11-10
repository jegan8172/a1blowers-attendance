// Conditional export: picks the right implementation of saveAndShareCsv()
// depending on the platform this app is compiled for.
//
// - Flutter Web            -> csv_export_web.dart   (browser download, saves
//                              straight to the PC's Downloads folder)
// - Mobile / Desktop (io)  -> csv_export_io.dart     (writes a temp file and
//                              opens the native share/save sheet)
// - Anything else          -> csv_export_stub.dart   (safety fallback)
export 'csv_export_stub.dart'
    if (dart.library.io) 'csv_export_io.dart'
    if (dart.library.html) 'csv_export_web.dart';
