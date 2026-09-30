import 'dart:convert';
import 'dart:io';
import '../data/area_network.dart';
import '../settings/walk_preferences.dart';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../recording/saved_walk.dart';
import '../transfer/walk_codec.dart';
import 'memory.dart';

class MemoryBackup {
  const MemoryBackup(
    this.walks,
    this.memories, {
    this.maps = const [],
    this.preferences,
    this.activeMap,
  });
  final List<String> maps;
  final WalkPreferences? preferences;
  final String? activeMap;
  final List<SavedWalk> walks;
  final List<WalkMemory> memories;
  static const maxBytes = 128 * 1024 * 1024;
  static Uint8List encode(MemoryBackup backup, {bool compressed = false}) {
    final payload = jsonEncode({
      'walks': WalkCodec.exportBackup(backup.walks),
      'memories': backup.memories.map((m) => m.toJson()).toList(),
      'maps': backup.maps,
      'preferences': backup.preferences?.toJson(),
      'activeMap': backup.activeMap,
    });
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': 'wanderlust-memories-backup',
          'version': 3,
          'sha256': sha256.convert(utf8.encode(payload)).toString(),
          'payload': payload,
        }),
      ),
    );
    decode(bytes); // Never write a backup we cannot restore.
    return compressed ? Uint8List.fromList(gzip.encode(bytes)) : bytes;
  }

  static MemoryBackup decode(Uint8List bytes) {
    if (bytes.length > maxBytes) {
      throw const FormatException('Backup exceeds 128 MiB.');
    }
    try {
      if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
        final sink = _LimitedBackupSink(maxBytes);
        final decoder = gzip.decoder.startChunkedConversion(sink);
        for (var i = 0; i < bytes.length; i += 65536) {
          decoder.add(bytes.sublist(i, (i + 65536).clamp(0, bytes.length)));
        }
        decoder.close();
        bytes = sink.bytes.takeBytes();
      }
      final text = utf8.decode(bytes).replaceFirst(RegExp('^\uFEFF'), '');
      final envelope = jsonDecode(text) as Map<String, dynamic>;
      if (envelope['format'] == 'wanderlust-backup') {
        return MemoryBackup(WalkCodec.importBackup(text), const []);
      }
      if (envelope['format'] != 'wanderlust-memories-backup' ||
          ![2, 3].contains(envelope['version'])) {
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
      final maps = <String>[];
      WalkPreferences? preferences;
      String? activeMap;
      if (envelope['version'] == 3) {
        final sources = data['maps'] as List;
        if (sources.length > 8) {
          throw const FormatException('More than eight offline maps.');
        }
        final versions = <String>{};
        for (final source in sources) {
          final text = source as String;
          if (utf8.encode(text).length > 16 * 1024 * 1024) {
            throw const FormatException('Offline map exceeds 16 MiB.');
          }
          final area = AreaNetwork.parse(text);
          if (!versions.add(area.version)) {
            throw const FormatException('Repeated offline map.');
          }
          maps.add(text);
        }
        activeMap = data['activeMap'] as String?;
        if (activeMap != null && !versions.contains(activeMap)) {
          throw const FormatException('Selected map is missing from backup.');
        }
        if (data['preferences'] != null) {
          final values = data['preferences'] as Map<String, dynamic>;
          preferences = WalkPreferences.fromJson(values);
          final normalized = preferences.toJson();
          if (values.length != normalized.length ||
              normalized.entries.any((e) => values[e.key] != e.value)) {
            throw const FormatException('Invalid backup settings.');
          }
        }
      }
      return MemoryBackup(
        walks,
        memories,
        maps: maps,
        preferences: preferences,
        activeMap: activeMap,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Malformed memory backup.');
    }
  }
}

/// Bounds expanded data before parsing, including highly compressed input.
class _LimitedBackupSink implements Sink<List<int>> {
  _LimitedBackupSink(this.limit);
  final int limit;
  final bytes = BytesBuilder(copy: false);
  @override
  void add(List<int> data) {
    if (bytes.length + data.length > limit) {
      throw const FormatException('Expanded backup exceeds 128 MiB.');
    }
    bytes.add(data);
  }

  @override
  void close() {}
}
