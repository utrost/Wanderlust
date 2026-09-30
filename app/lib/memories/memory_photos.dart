import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:image_picker/image_picker.dart';
import 'memory.dart';
import 'memory_store.dart';

abstract class MemoryPhotos {
  Future<Uint8List?> pick(bool camera);
}

class DeviceMemoryPhotos implements MemoryPhotos {
  DeviceMemoryPhotos({ImagePicker? picker}) : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;
  @override
  Future<Uint8List?> pick(bool camera) async {
    final file = await _picker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 75,
      requestFullMetadata: false,
    );
    return file == null ? null : read(file);
  }

  static Future<Uint8List> read(XFile file) async {
    if (await file.length() > WalkMemory.maxPhotoBytes) {
      throw const FormatException('Choose a photo smaller than 8 MiB.');
    }
    final bytes = await file.readAsBytes();
    await validatePhoto(bytes);
    return bytes;
  }

  Future<void> recover(MemoryStore store) async {
    final response = await _picker.retrieveLostData();
    final drafts = (await store.list())
        .where((m) => m.draft && m.pendingPhoto)
        .toList();
    if (drafts.isEmpty) return;
    // Only one editor can launch a picker at a time. Recover against the
    // persisted identity, never whichever walk happens to be open now.
    final draft = (await store.read(drafts.first.id, true))!;
    final file = response.files?.firstOrNull;
    if (response.exception != null) throw response.exception!;
    final photo = file == null ? null : await read(file);
    await store.put(draft.copyWith(photo: photo, pendingPhoto: false));
  }
}

Future<void> validatePhoto(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > WalkMemory.maxPhotoBytes) {
    throw const FormatException('Photo exceeds the 8 MiB limit.');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width * descriptor.height > 32000000) {
      throw const FormatException('Choose a photo smaller than 32 megapixels.');
    }
    final ratio = math.min(
      1.0,
      1600 / math.max(descriptor.width, descriptor.height),
    );
    final codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (descriptor.width * ratio).round()),
      targetHeight: math.max(1, (descriptor.height * ratio).round()),
    );
    try {
      final frame = await codec.getNextFrame();
      frame.image.dispose();
    } finally {
      codec.dispose();
    }
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException(
      'This photo could not be opened. Try a JPEG or PNG image.',
    );
  } finally {
    descriptor?.dispose();
    buffer.dispose();
  }
}
