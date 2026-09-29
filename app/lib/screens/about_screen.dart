import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

bool _registered = false;

/// Flutter supplies Dart/Flutter notices; the native matcher has its own bundle.
void registerNativeLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    final entries =
        jsonDecode(
              await rootBundle.loadString('assets/legal/rust-licenses.json'),
            )
            as List<dynamic>;
    for (final entry in entries) {
      yield LicenseEntryWithLineBreaks([
        '${entry['name']} ${entry['version']} (Rust)',
      ], entry['text'] as String);
    }
  });
}

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late final Future<String?> _version = _readVersion();

  Future<String?> _readVersion() async {
    try {
      return await const MethodChannel(
        'wanderlust/about',
      ).invokeMethod<String>('version');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Widget _address(String title, String address) => ListTile(
    title: Text(title),
    subtitle: SelectableText(address),
    trailing: IconButton(
      tooltip: 'Copy $title',
      icon: const Icon(Icons.copy_outlined),
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: address));
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Address copied')));
      },
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('About Wanderlust')),
    body: ListView(
      children: [
        const ListTile(
          title: Text('Wanderlust'),
          subtitle: Text(
            'Explore at your own pace. Your walks stay on your phone.',
          ),
        ),
        FutureBuilder<String?>(
          future: _version,
          builder: (context, snapshot) => ListTile(
            title: const Text('Version'),
            subtitle: Text(snapshot.data ?? 'Development build'),
          ),
        ),
        const ListTile(
          title: Text('Created by'),
          subtitle: Text('Uwe Trostheide'),
        ),
        _address('Source code', 'https://github.com/utrost/Wanderlust'),
        ListTile(
          title: const Text('App licence'),
          subtitle: const Text('GNU AGPL v3.0 or later · Read offline'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const _AppLicenseScreen()),
          ),
        ),
        ListTile(
          title: const Text('Open-source licences'),
          subtitle: const Text(
            'Flutter, Dart packages and the Rust map matcher',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            registerNativeLicenses();
            showLicensePage(context: context, applicationName: 'Wanderlust');
          },
        ),
        const Divider(),
        const ListTile(
          title: Text('Map data'),
          subtitle: Text(
            '© OpenStreetMap contributors\nOpen Database Licence (ODbL) 1.0\nNearby maps are downloaded through the Overpass service.',
          ),
        ),
        _address(
          'OpenStreetMap attribution',
          'https://www.openstreetmap.org/copyright',
        ),
      ],
    ),
  );
}

class _AppLicenseScreen extends StatefulWidget {
  const _AppLicenseScreen();

  @override
  State<_AppLicenseScreen> createState() => _AppLicenseScreenState();
}

class _AppLicenseScreenState extends State<_AppLicenseScreen> {
  late final _text = rootBundle.loadString('assets/legal/AGPL-3.0.txt');

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('App licence')),
    body: FutureBuilder<String>(
      future: _text,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Could not load licence text.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(snapshot.data!),
        );
      },
    ),
  );
}
