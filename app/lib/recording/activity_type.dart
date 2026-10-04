/// Per-recording movement policy. Unknown/older data remains walking.
enum WalkActivity {
  walk,
  cycle;

  String get label => this == walk ? 'Walk' : 'Cycle';
  double get maxSpeed => this == walk ? 3 : 15;
  double get gapSpeed => this == walk ? 2.2 : 8;
  static WalkActivity parse(Object? value) => value == 'cycle' ? cycle : walk;
}
