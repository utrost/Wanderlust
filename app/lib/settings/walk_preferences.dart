class WalkPreferences {
  const WalkPreferences({
    this.showTime = false,
    this.showSamples = false,
    this.showGps = false,
    this.detailedGps = false,
    this.fillSmallGaps = false,
    this.walkedLineWidth = 3,
    this.mapSizeKm = 4,
  });
  final bool showTime;
  final bool showSamples;
  final bool showGps;
  final bool detailedGps;
  final bool fillSmallGaps;

  /// Maximum screen-space stroke width; keeps zoomed-in coverage legible.
  final double walkedLineWidth;
  final int mapSizeKm;

  WalkPreferences copyWith({
    bool? showTime,
    bool? showSamples,
    bool? showGps,
    bool? detailedGps,
    bool? fillSmallGaps,
    double? walkedLineWidth,
    int? mapSizeKm,
  }) => WalkPreferences(
    showTime: showTime ?? this.showTime,
    showSamples: showSamples ?? this.showSamples,
    showGps: showGps ?? this.showGps,
    detailedGps: detailedGps ?? this.detailedGps,
    fillSmallGaps: fillSmallGaps ?? this.fillSmallGaps,
    walkedLineWidth: walkedLineWidth ?? this.walkedLineWidth,
    mapSizeKm: mapSizeKm ?? this.mapSizeKm,
  );

  Map<String, Object> toJson() => {
    'showTime': showTime,
    'showSamples': showSamples,
    'showGps': showGps,
    'detailedGps': detailedGps,
    'fillSmallGaps': fillSmallGaps,
    'walkedLineWidth': walkedLineWidth,
    'mapSizeKm': mapSizeKm,
  };
  factory WalkPreferences.fromJson(Map<String, dynamic> json) {
    final width = json['walkedLineWidth'];
    final size = json['mapSizeKm'];
    return WalkPreferences(
      showTime: json['showTime'] == true,
      showSamples: json['showSamples'] == true,
      showGps: json['showGps'] == true,
      detailedGps: json['detailedGps'] == true,
      fillSmallGaps: json['fillSmallGaps'] == true,
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
