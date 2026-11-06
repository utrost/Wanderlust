import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../transfer/walk_files.dart';
import 'map_diagnostics.dart';

Future<void> showMapReports(
  BuildContext context,
  MapDiagnostics diagnostics, {
  WalkFiles? files,
}) async {
  final report = await diagnostics.report();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Map diagnostic reports'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Stored only on this phone. Reports contain technical errors and device information, without locations or recordings. Copy or save them to share with support.',
            ),
            const SizedBox(height: 12),
            SelectableText(
              report == '[]'
                  ? 'No reports yet. Retry the map operation first.'
                  : report,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: report));
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Report copied')));
            }
          },
          child: const Text('Copy report'),
        ),
        TextButton(
          onPressed: () async {
            try {
              final saved = await (files ?? DeviceWalkFiles()).save(
                'wanderlust-map-diagnostics.json',
                'application/json',
                Uint8List.fromList(utf8.encode(report)),
              );
              if (context.mounted && saved) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Report saved')));
              }
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Could not save report. Use Copy report instead.',
                      ),
                    ),
                  );
              }
            }
          },
          child: const Text('Save report'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
