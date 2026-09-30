import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:geolocator/geolocator.dart';

class WalkMemory {
  const WalkMemory({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.note = '',
    this.walkUid,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.photo,
    this.photoLength = 0,
    this.draft = true,
    this.pendingPhoto = false,
  });
  final String id;
  final DateTime createdAt, updatedAt;
  final String note;
  final String? walkUid;
  final double? latitude, longitude, accuracy;
  final Uint8List? photo;
  final int photoLength;
  final bool draft, pendingPhoto;
  bool get hasPhoto => (photo?.length ?? photoLength) > 0;
  bool get hasLocation => latitude != null && longitude != null;
  bool get hasContent => note.trim().isNotEmpty || hasPhoto;
  String get title => note.trim().isEmpty
      ? (hasPhoto ? 'Photo memory' : 'New memory')
      : note.trim().split('\n').first;
  static const maxPhotoBytes = 8 * 1024 * 1024;
  static bool usableFix(Position p, DateTime now) =>
      p.latitude.isFinite &&
      p.longitude.isFinite &&
      p.latitude.abs() <= 90 &&
      p.longitude.abs() <= 180 &&
      p.accuracy.isFinite &&
      p.accuracy >= 0 &&
      p.accuracy <= 50 &&
      now.difference(p.timestamp).inSeconds >= -5 &&
      now.difference(p.timestamp).inSeconds <= 60;
  factory WalkMemory.create({String? walkUid, Position? fix}) {
    final now = DateTime.now().toUtc();
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final p = fix != null && usableFix(fix, now) ? fix : null;
    return WalkMemory(
      id: id,
      createdAt: now,
      updatedAt: now,
      walkUid: walkUid,
      latitude: p?.latitude,
      longitude: p?.longitude,
      accuracy: p?.accuracy,
    );
  }
  WalkMemory copyWith({
    String? note,
    bool? draft,
    bool? pendingPhoto,
    Uint8List? photo,
    bool removePhoto = false,
    Position? fix,
    bool removeLocation = false,
  }) => WalkMemory(
    id: id,
    createdAt: createdAt,
    updatedAt: DateTime.now().toUtc(),
    walkUid: walkUid,
    note: note ?? this.note,
    draft: draft ?? this.draft,
    pendingPhoto: pendingPhoto ?? this.pendingPhoto,
    photo: removePhoto ? null : photo ?? this.photo,
    photoLength: removePhoto ? 0 : photo?.length ?? photoLength,
    latitude: removeLocation ? null : fix?.latitude ?? latitude,
    longitude: removeLocation ? null : fix?.longitude ?? longitude,
    accuracy: removeLocation ? null : fix?.accuracy ?? accuracy,
  );
  Map<String, dynamic> toJson({bool includePhoto = true}) => {
    'id': id,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'note': note,
    'walkUid': walkUid,
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'draft': draft,
    'pendingPhoto': pendingPhoto,
    'photoLength': photo?.length ?? photoLength,
    if (includePhoto) 'photo': photo == null ? null : base64Encode(photo!),
  };
  factory WalkMemory.fromJson(
    Map<String, dynamic> value, {
    bool complete = false,
  }) {
    try {
      final id = value['id'] as String, note = value['note'] as String;
      final uid = value['walkUid'] as String?;
      final lat = (value['latitude'] as num?)?.toDouble(),
          lon = (value['longitude'] as num?)?.toDouble();
      final accuracy = (value['accuracy'] as num?)?.toDouble();
      final photo = value['photo'] == null
          ? null
          : base64Decode(value['photo'] as String);
      final length = value['photoLength'] as int;
      final created = DateTime.parse(value['createdAt'] as String),
          updated = DateTime.parse(value['updatedAt'] as String);
      final validId = RegExp(r'^[a-f0-9]{32}$');
      if (!validId.hasMatch(id) ||
          (uid != null && !validId.hasMatch(uid)) ||
          note.length > 4000 ||
          (lat == null) != (lon == null) ||
          (lat != null && (!lat.isFinite || lat.abs() > 90)) ||
          (lon != null && (!lon.isFinite || lon.abs() > 180)) ||
          (accuracy != null && (!accuracy.isFinite || accuracy < 0)) ||
          length < 0 ||
          length > maxPhotoBytes ||
          (complete && (photo?.length ?? 0) != length) ||
          !created.isUtc ||
          !updated.isUtc ||
          value['draft'] is! bool ||
          value['pendingPhoto'] is! bool) {
        throw const FormatException('Invalid memory data.');
      }
      final result = WalkMemory(
        id: id,
        createdAt: created,
        updatedAt: updated,
        note: note,
        walkUid: uid,
        latitude: lat,
        longitude: lon,
        accuracy: accuracy,
        photo: photo,
        photoLength: length,
        draft: value['draft'] as bool,
        pendingPhoto: value['pendingPhoto'] as bool,
      );
      if (!result.draft && !result.hasContent) {
        throw const FormatException('Empty memory.');
      }
      return result;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Malformed memory.');
    }
  }
}
