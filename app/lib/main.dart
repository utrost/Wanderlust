import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/map_screen.dart';
import 'theme/wanderlust_theme.dart';
import 'transfer/backup_archive.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(BackupArchive.cleanAbandonedFiles().catchError((Object _) {}));
  runApp(const WanderlustApp());
}

class WanderlustApp extends StatelessWidget {
  const WanderlustApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wanderlust',
      debugShowCheckedModeBanner: false,
      theme: WanderlustTheme.light(),
      home: const MapScreen(),
    );
  }
}
