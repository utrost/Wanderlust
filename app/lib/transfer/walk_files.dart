import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/services.dart';

import 'package:file_picker/file_picker.dart';

import '../memories/memory_backup.dart';

abstract class WalkFiles {
  Future<Uint8List?> pick();
  Future<bool> save(String name, String mimeType, Uint8List bytes);
}

abstract class ArchiveFiles {
  Future<File?> pickArchive();
  Future<bool> saveArchive(File file);
  Future<void> cancelArchive();
}

class DeviceWalkFiles implements WalkFiles, ArchiveFiles {
  static const _backups = MethodChannel('wanderlust/backups');
  @override
  Future<File?> pickArchive() async {
    final path = await _backups.invokeMethod<String>('pick');
    return path == null ? null : File(path);
  }

  @override
  Future<bool> saveArchive(File file) async =>
      await _backups.invokeMethod<String>('save', {'path': file.path}) != null;
  @override
  Future<void> cancelArchive() => _backups.invokeMethod<void>('cancel');

  @override
  Future<Uint8List?> pick() async {
    // Some Android document providers label GPX as generic XML/octet-stream.
    // Accept any file in the picker, then validate its actual contents.
    final file = await FilePicker.pickFile();
    if (file == null) return null;
    final size = await file.length();
    if (size != null && size > MemoryBackup.maxBytes) {
      throw const FormatException('File exceeds the 128 MiB limit.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.readAsByteStream()) {
      if (bytes.length + chunk.length > MemoryBackup.maxBytes) {
        throw const FormatException('File exceeds the 128 MiB limit.');
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
