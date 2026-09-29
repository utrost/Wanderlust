class WalkPreferences {
  const WalkPreferences({
    this.showTime = false,
    this.showSamples = false,
    this.showGps = false,
  });
  final bool showTime;
  final bool showSamples;
  final bool showGps;
  Map<String, bool> toJson() => {
    'showTime': showTime,
    'showSamples': showSamples,
    'showGps': showGps,
  };
  factory WalkPreferences.fromJson(Map<String, dynamic> json) =>
      WalkPreferences(
        showTime: json['showTime'] == true,
        showSamples: json['showSamples'] == true,
        showGps: json['showGps'] == true,
      );
}
