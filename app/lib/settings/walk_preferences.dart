class WalkPreferences {
  const WalkPreferences({
    this.showTime = false,
    this.showSamples = false,
    this.showGps = false,
    this.showStreetNames = true,
    this.showMemories = true,
    this.detailedGps = false,
    this.fillSmallGaps = false,
    this.walkedLineWidth = 3,
    this.mapSizeKm = 4,
  });
  final bool showTime;
  final bool showSamples;
  final bool showGps;
  final bool showStreetNames;
  final bool showMemories;
  final bool detailedGps;
  final bool fillSmallGaps;

  /// Maximum screen-space stroke width; keeps zoomed-in coverage legible.
  final double walkedLineWidth;
  final int mapSizeKm;

  WalkPreferences copyWith({
    bool? showTime,
    bool? showSamples,
    bool? showGps,
    bool? showStreetNames,
    bool? showMemories,
    bool? detailedGps,
    bool? fillSmallGaps,
    double? walkedLineWidth,
    int? mapSizeKm,
  }) => WalkPreferences(
    showTime: showTime ?? this.showTime,
    showSamples: showSamples ?? this.showSamples,
    showGps: showGps ?? this.showGps,
    showStreetNames: showStreetNames ?? this.showStreetNames,
    showMemories: showMemories ?? this.showMemories,
    detailedGps: detailedGps ?? this.detailedGps,
    fillSmallGaps: fillSmallGaps ?? this.fillSmallGaps,
    walkedLineWidth: walkedLineWidth ?? this.walkedLineWidth,
    mapSizeKm: mapSizeKm ?? this.mapSizeKm,
  );

  Map<String, Object> toJson() => {
    'showTime': showTime,
    'showSamples': showSamples,
    'showGps': showGps,
    'showStreetNames': showStreetNames,
    'showMemories': showMemories,
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
      showStreetNames: json['showStreetNames'] != false,
      showMemories: json['showMemories'] != false,
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
