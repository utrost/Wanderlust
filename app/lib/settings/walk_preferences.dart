import '../recording/activity_type.dart';

class WalkPreferences {
  const WalkPreferences({
    this.activity = WalkActivity.walk,
    this.showTime = false,
    this.showSamples = false,
    this.showGps = false,
    this.showStreetNames = true,
    this.showMemories = true,
    this.gpsIntervalSeconds = 5,
    this.autoDownloadMaps = true,
    this.fillSmallGaps = false,
    this.autoFillGaps = true,
    this.walkedLineWidth = 3,
    this.mapSizeKm = 4,
  });
  final WalkActivity activity;
  final bool showTime;
  final bool showSamples;
  final bool showGps;
  final bool showStreetNames;
  final bool showMemories;
  static const gpsIntervals = [2, 5, 10, 20];
  final int gpsIntervalSeconds;
  final bool autoDownloadMaps;
  final bool fillSmallGaps;
  final bool autoFillGaps;

  /// Maximum screen-space stroke width; keeps zoomed-in coverage legible.
  final double walkedLineWidth;
  final int mapSizeKm;

  WalkPreferences copyWith({
    WalkActivity? activity,
    bool? showTime,
    bool? showSamples,
    bool? showGps,
    bool? showStreetNames,
    bool? showMemories,
    int? gpsIntervalSeconds,
    bool? autoDownloadMaps,
    bool? fillSmallGaps,
    bool? autoFillGaps,
    double? walkedLineWidth,
    int? mapSizeKm,
  }) => WalkPreferences(
    activity: activity ?? this.activity,
    showTime: showTime ?? this.showTime,
    showSamples: showSamples ?? this.showSamples,
    showGps: showGps ?? this.showGps,
    showStreetNames: showStreetNames ?? this.showStreetNames,
    showMemories: showMemories ?? this.showMemories,
    gpsIntervalSeconds: gpsIntervalSeconds ?? this.gpsIntervalSeconds,
    autoDownloadMaps: autoDownloadMaps ?? this.autoDownloadMaps,
    fillSmallGaps: fillSmallGaps ?? this.fillSmallGaps,
    autoFillGaps: autoFillGaps ?? this.autoFillGaps,
    walkedLineWidth: walkedLineWidth ?? this.walkedLineWidth,
    mapSizeKm: mapSizeKm ?? this.mapSizeKm,
  );

  Map<String, Object> toJson() => {
    'activity': activity.name,
    'showTime': showTime,
    'showSamples': showSamples,
    'showGps': showGps,
    'showStreetNames': showStreetNames,
    'showMemories': showMemories,
    'gpsIntervalSeconds': gpsIntervalSeconds,
    'autoDownloadMaps': autoDownloadMaps,
    'fillSmallGaps': fillSmallGaps,
    'autoFillGaps': autoFillGaps,
    'walkedLineWidth': walkedLineWidth,
    'mapSizeKm': mapSizeKm,
  };
  factory WalkPreferences.fromJson(Map<String, dynamic> json) {
    final width = json['walkedLineWidth'];
    final size = json['mapSizeKm'];
    return WalkPreferences(
      activity: WalkActivity.parse(json['activity']),
      showTime: json['showTime'] == true,
      showSamples: json['showSamples'] == true,
      showGps: json['showGps'] == true,
      showStreetNames: json['showStreetNames'] != false,
      showMemories: json['showMemories'] != false,
      gpsIntervalSeconds: gpsIntervals.contains(json['gpsIntervalSeconds'])
          ? (json['gpsIntervalSeconds'] as num).toInt()
          : (json['detailedGps'] == true ? 2 : 5),
      autoDownloadMaps: json['autoDownloadMaps'] != false,
      fillSmallGaps: json['fillSmallGaps'] == true,
      autoFillGaps: json['autoFillGaps'] != false,
      walkedLineWidth:
          width is num && width.isFinite && width >= 1 && width <= 6
          ? width.toDouble()
          : 3,
      mapSizeKm:
          size is num &&
              size.isFinite &&
              size >= 1 &&
              size <= 25 &&
              size == size.roundToDouble()
          ? size.toInt()
          : 4,
    );
  }
}
