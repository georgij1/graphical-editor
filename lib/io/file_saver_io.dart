import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Native implementation: opens a save dialog and writes the bytes.
Future<bool> saveBytesToFile(
  Uint8List bytes,
  String fileName, {
  String? dialogTitle,
  List<String> allowedExtensions = const <String>['fxml'],
  String? mimeType,
}) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: allowedExtensions,
    bytes: bytes,
  );
  return path != null;
}