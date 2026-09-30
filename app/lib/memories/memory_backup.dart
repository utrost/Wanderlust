import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../recording/saved_walk.dart';
import '../transfer/walk_codec.dart';
import 'memory.dart';

class MemoryBackup {
  const MemoryBackup(this.walks, this.memories);
  final List<SavedWalk> walks;
  final List<WalkMemory> memories;
  static const maxBytes = 128 * 1024 * 1024;
  static Uint8List encode(MemoryBackup backup) {
    final payload = jsonEncode({
      'walks': WalkCodec.exportBackup(backup.walks),
      'memories': backup.memories.map((m) => m.toJson()).toList(),
    });
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': 'wanderlust-memories-backup',
          'version': 2,
          'sha256': sha256.convert(utf8.encode(payload)).toString(),
          'payload': payload,
        }),
      ),
    );
    decode(bytes); // Never write a backup we cannot restore.
    return bytes;
  }

  static MemoryBackup decode(Uint8List bytes) {
    if (bytes.length > maxBytes) {
      throw const FormatException('Backup exceeds 128 MiB.');
    }
    try {
      final text = utf8.decode(bytes).replaceFirst(RegExp('^\uFEFF'), '');
      final envelope = jsonDecode(text) as Map<String, dynamic>;
      if (envelope['format'] == 'wanderlust-backup') {
        return MemoryBackup(WalkCodec.importBackup(text), const []);
      }
      if (envelope['format'] != 'wanderlust-memories-backup' ||
          envelope['version'] != 2) {
        throw const FormatException('Unsupported backup format or version.');
      }
      final payload = envelope['payload'] as String;
      if (sha256.convert(utf8.encode(payload)).toString() !=
          envelope['sha256']) {
        throw const FormatException('Backup checksum does not match.');
      }
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final walks = WalkCodec.importBackup(data['walks'] as String);
      final rows = data['memories'] as List;
      if (rows.length > 10000) {
        throw const FormatException('Backup exceeds 10,000 memories.');
      }
      final memories = <WalkMemory>[];
      final seen = <String>{}, uids = walks.map((w) => w.uid).toSet();
      var photoBytes = 0;
      for (final row in rows) {
        final m = WalkMemory.fromJson(
          row as Map<String, dynamic>,
          complete: true,
        );
        if (!seen.add('${m.id}:${m.draft}') ||
            (m.walkUid != null && !uids.contains(m.walkUid))) {
          throw const FormatException(
            'Repeated memory or missing associated walk.',
          );
        }
        photoBytes += m.photoLength;
        if (photoBytes > 80 * 1024 * 1024) {
          throw const FormatException('Photos exceed the backup size limit.');
        }
        memories.add(m);
      }
      return MemoryBackup(walks, memories);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Malformed memory backup.');
    }
  }
}
