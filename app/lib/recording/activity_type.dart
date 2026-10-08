/// Optional history label. App matching is automatic for every label.
enum WalkActivity {
  auto,
  walk,
  cycle;

  String get label => this == auto
      ? 'Journey'
      : this == walk
      ? 'Walk'
      : 'Cycle';
  double get maxSpeed => this == auto
      ? 70
      : this == walk
      ? 3
      : 15;
  double get gapSpeed => this == auto
      ? 30
      : this == walk
      ? 2.2
      : 8;
  static WalkActivity parse(Object? value) => value == 'auto'
      ? auto
      : value == 'cycle'
      ? cycle
      : walk;
}
