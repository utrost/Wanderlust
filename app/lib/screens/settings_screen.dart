import 'package:flutter/material.dart';
import '../settings/walk_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.initial,
    required this.save,
    required this.diagnostic,
  });
  final WalkPreferences initial;
  final Future<void> Function(WalkPreferences) save;
  final Widget diagnostic;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late WalkPreferences value = widget.initial;
  bool busy = false;
  double? _previewWidth;
  String? error;
  Future<void> change(WalkPreferences next) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.save(next);
      if (mounted) setState(() => value = next);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not save settings. Please retry.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Walk at your own pace. These details are optional and stay on your phone.',
          ),
        ),
        SwitchListTile(
          title: const Text('Show elapsed time'),
          value: value.showTime,
          onChanged: busy ? null : (v) => change(value.copyWith(showTime: v)),
        ),
        SwitchListTile(
          title: const Text('Show GPS sample count'),
          subtitle: const Text(
            'Recorded location readings, not points or a score.',
          ),
          value: value.showSamples,
          onChanged: busy
              ? null
              : (v) => change(value.copyWith(showSamples: v)),
        ),
        SwitchListTile(
          title: const Text('Show GPS details'),
          subtitle: const Text(
            'Coordinates, accuracy and time since the last fix.',
          ),
          value: value.showGps,
          onChanged: busy ? null : (v) => change(value.copyWith(showGps: v)),
        ),
        const Divider(),
        const ListTile(
          title: Text('Walked line thickness'),
          subtitle: Text('Make coloured streets finer or bolder.'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              Semantics(
                label: 'Walked line preview',
                child: Container(
                  height: _previewWidth ?? value.walkedLineWidth,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC4A080),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              Slider(
                key: const Key('walked-line-width'),
                min: 1,
                max: 6,
                divisions: 10,
                value: _previewWidth ?? value.walkedLineWidth,
                onChanged: busy
                    ? null
                    : (v) => setState(() => _previewWidth = v),
                onChangeEnd: busy
                    ? null
                    : (v) async {
                        await change(value.copyWith(walkedLineWidth: v));
                        if (mounted) setState(() => _previewWidth = null);
                      },
              ),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text('Fine'), Text('Bold')],
              ),
            ],
          ),
        ),
        if (error != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
        const Divider(),
        const ListTile(
          title: Text('What are street sections?'),
          subtitle: Text(
            'Small pieces of walkable street or path, split at junctions and along longer streets. They are not whole named streets or a score. A section colours when consecutive GPS readings confirm it; uncertain readings may take longer.',
          ),
        ),
        const ListTile(
          title: Text('Parks and water'),
          subtitle: Text(
            'Quiet landmarks for orientation. They do not add to walked coverage. Refresh older maps in Offline maps to include them.',
          ),
        ),
        ListTile(
          title: const Text('Geo-core diagnostic'),
          trailing: widget.diagnostic,
        ),
      ],
    ),
  );
}
