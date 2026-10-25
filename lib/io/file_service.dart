import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import 'file_saver.dart';

/// A document read from disk (or picked in the browser).
class PickedDocument {
  const PickedDocument(this.content, this.fileName);

  final String content;
  final String fileName;
}

/// Wraps `file_picker` so the editor can open and save `.fxml` files on every
/// supported platform, including the web build.
class FileService {
  const FileService();

  Future<PickedDocument?> open() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['fxml', 'xml'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) return null;
    return PickedDocument(utf8.decode(bytes, allowMalformed: true), file.name);
  }

  /// Writes [content] to [fileName]. Returns false when the user cancelled or
  /// the platform refused to save (for example a browser blocking downloads).
  Future<bool> save(
    String content,
    String fileName, {
    String? dialogTitle,
    List<String> allowedExtensions = const <String>['fxml'],
    String? mimeType,
  }) {
    return saveBytes(
      Uint8List.fromList(utf8.encode(content)),
      fileName,
      dialogTitle: dialogTitle,
      allowedExtensions: allowedExtensions,
      mimeType: mimeType,
    );
  }

  /// Writes raw [bytes] (archives, images) to [fileName].
  Future<bool> saveBytes(
    Uint8List bytes,
    String fileName, {
    String? dialogTitle,
    List<String> allowedExtensions = const <String>['fxml'],
    String? mimeType,
  }) async {
    try {
      return await saveBytesToFile(
        bytes,
        fileName,
        dialogTitle: dialogTitle,
        allowedExtensions: allowedExtensions,
        mimeType: mimeType,
      );
    } catch (error) {
      debugPrint('Saving $fileName failed: $error');
      return false;
    }
  }
}
