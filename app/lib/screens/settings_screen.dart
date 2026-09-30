import 'package:flutter/material.dart';
import 'about_screen.dart';
import '../theme/heat_ramp.dart';
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
        SwitchListTile(
          title: const Text('Fill small gaps'),
          subtitle: const Text(
            'Infer short missing sections between matched streets when one nearby route fits your walk. Applies to live and saved walks. Turn off to remove these estimates.',
          ),
          value: value.fillSmallGaps,
          onChanged: busy
              ? null
              : (v) => change(value.copyWith(fillSmallGaps: v)),
        ),
        SwitchListTile(
          title: const Text('Detailed GPS'),
          subtitle: const Text(
            'Request readings every 2 seconds / 2 metres instead of 5 seconds / 5 metres. Uses more battery. Applies to the next walk; actual updates depend on your phone.',
          ),
          value: value.detailedGps,
          onChanged: busy
              ? null
              : (v) => change(value.copyWith(detailedGps: v)),
        ),
        const Divider(),
        SwitchListTile(
          title: const Text('Show street names'),
          subtitle: const Text(
            'Applies to the main map and saved-walk review. Place and park names remain visible.',
          ),
          value: value.showStreetNames,
          onChanged: busy
              ? null
              : (v) => change(value.copyWith(showStreetNames: v)),
        ),
        const ListTile(
          title: Text('Your walking heatmap'),
          subtitle: Text(
            'Streets deepen in colour with each separate walk. A section counts once per walk, even if you pass it several times. The current walk adds a live preview.',
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: 20,
            runSpacing: 12,
            children: [
              for (final count in [1, 5, 20, 100])
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48,
                      height: 4,
                      color: HeatRamp.color(count, dark: false),
                    ),
                    const SizedBox(height: 6),
                    Text('$count ${count == 1 ? 'walk' : 'walks'}'),
                  ],
                ),
            ],
          ),
        ),
        const ListTile(
          title: Text('Walking with the screen off'),
          subtitle: Text(
            'Start a walk, then lock your phone or use another app. Tap the walk notification to return and stop. If Android closes the app, your saved readings are recovered as an interrupted walk next time you open it.',
          ),
        ),
        const ListTile(
          title: Text('What are street sections?'),
          subtitle: Text(
            'Small pieces of walkable street or path, split at junctions and along longer streets. They are not whole named streets or a score. A section colours when readings show movement along it in a compatible direction; uncertain readings may take longer.',
          ),
        ),
        const ListTile(
          title: Text('Parks and water'),
          subtitle: Text(
            'Quiet landmarks for orientation. They do not add to walked coverage. Refresh older maps in Offline maps to include them.',
          ),
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('About Wanderlust'),
          subtitle: const Text('Creator, source code and licences'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const AboutScreen())),
        ),
        ListTile(
          title: const Text('Geo-core diagnostic'),
          trailing: widget.diagnostic,
        ),
      ],
    ),
  );
}
