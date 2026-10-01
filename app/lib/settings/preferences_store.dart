import 'walk_preferences.dart';

abstract interface class PreferencesStore {
  Future<WalkPreferences> readPreferences();
  Future<void> savePreferences(WalkPreferences value);
}
