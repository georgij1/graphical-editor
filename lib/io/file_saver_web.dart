import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web implementation: `file_picker` cannot open a save dialog here, so the
/// bytes are handed to the browser as a blob download instead.
Future<bool> saveBytesToFile(
  Uint8List bytes,
  String fileName, {
  String? dialogTitle,
  List<String> allowedExtensions = const <String>['fxml'],
  String? mimeType,
}) async {
  final parts = <web.BlobPart>[bytes.toJS].toJS;
  final blob = web.Blob(
    parts,
    web.BlobPropertyBag(type: mimeType ?? _mimeType(fileName)),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  // Give the browser a moment to start the download before dropping the URL.
  Future<void>.delayed(const Duration(milliseconds: 100))
      .then((_) => web.URL.revokeObjectURL(url));
  return true;
}

String _mimeType(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final extension = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  switch (extension) {
    case 'fxml':
    case 'xml':
      return 'application/xml';
    case 'json':
      return 'application/json';
    default:
      return 'application/octet-stream';
  }
}