/// Progress for a backup operation. Fractions and estimates describe one stage,
/// never an invented percentage for the complete restore.
class BackupCancelled implements Exception {}

class BackupProgress {
  BackupProgress({this.onProgress, Duration Function()? clock})
    : _clock = clock ?? (Stopwatch()..start()).elapsedDuration;
  final void Function(int)? onProgress;
  final Duration Function() _clock;
  Duration _stageStarted = Duration.zero;
  bool cancelled = false, canCancel = true;
  int records = 0, completed = 0;
  int? total;
  String label = 'Waiting for file access…';
  String? detail;
  bool estimate = false, bytes = false;
  Duration get elapsed => _clock();
  double? get fraction => total == null || total! <= 0
      ? null
      : (completed / total!).clamp(0.0, 1.0);
  Duration? get remaining {
    final part = fraction;
    final time = elapsed - _stageStarted;
    if (!estimate ||
        part == null ||
        part < .05 ||
        part >= 1 ||
        time.inSeconds < 3) {
      return null;
    }
    return Duration(seconds: (time.inSeconds * (1 - part) / part).ceil());
  }

  void stage(
    String label, {
    int? total,
    bool estimate = false,
    bool bytes = false,
    String? detail,
  }) {
    this.label = label;
    this.total = total;
    this.estimate = estimate;
    this.bytes = bytes;
    this.detail = detail;
    completed = 0;
    _stageStarted = elapsed;
    notify();
  }

  void update(int value, {String? detail}) {
    completed = value;
    if (detail != null) this.detail = detail;
    notify();
  }

  void notify() => onProgress?.call(records);
  void check() {
    if (cancelled) throw BackupCancelled();
  }

  void advance() {
    check();
    records++;
    notify();
  }

  /// A yielded item counts as processed only when its consumer requests the
  /// next item. This also covers duplicates that the importer checks and skips.
  Stream<T> track<T>(Stream<T> source, String label, int total) async* {
    if (total == 0) return;
    stage(label, total: total);
    var done = 0;
    await for (final item in source) {
      detail = null;
      notify();
      yield item;
      update(++done);
    }
  }
}

extension on Stopwatch {
  Duration elapsedDuration() => elapsed;
}

String backupTime(Duration duration) {
  final seconds = duration.inSeconds;
  if (seconds < 60) return '${seconds}s';
  if (seconds < 3600) return '${seconds ~/ 60}m ${seconds % 60}s';
  return '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';
}
