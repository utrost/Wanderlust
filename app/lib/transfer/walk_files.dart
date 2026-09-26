import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'walk_codec.dart';

abstract class WalkFiles {
  Future<Uint8List?> pick();
  Future<bool> save(String name, String mimeType, Uint8List bytes);
}

class DeviceWalkFiles implements WalkFiles {
  @override
  Future<Uint8List?> pick() async {
    // Some Android document providers label GPX as generic XML/octet-stream.
    // Accept any file in the picker, then validate its actual contents.
    final file = await FilePicker.pickFile();
    if (file == null) return null;
    final size = await file.length();
    if (size != null && size > WalkCodec.maxBytes) {
      throw const FormatException('File exceeds the 32 MiB limit.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.readAsByteStream()) {
      if (bytes.length + chunk.length > WalkCodec.maxBytes) {
        throw const FormatException('File exceeds the 32 MiB limit.');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  @override
  Future<bool> save(String name, String mimeType, Uint8List bytes) async =>
      await FilePicker.saveFile(
        fileName: name,
        bytes: bytes,
        mimeType: mimeType,
      ) !=
      null;
}
