import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class GpsDiagnosticsView extends StatelessWidget {
  const GpsDiagnosticsView({super.key, required this.metrics});
  final Map<String, Object?> metrics;
  String number(String key, {double divisor = 1, String suffix = ''}) {
    final n = metrics[key];
    return n is num
        ? '${(n / divisor).toStringAsFixed(divisor == 1 ? 0 : 1)}$suffix'
        : '—';
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('GPS diagnostics'),
    content: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Requested interval: ${number('requestedIntervalSeconds', suffix: ' s')}',
          ),
          Text(
            'Delivered interval (mean / longest): ${number('meanDeliveryIntervalMs', divisor: 1000)} / ${number('maxDeliveryIntervalMs', divisor: 1000)} s',
          ),
          Text(
            'GPS timestamp interval (mean): ${number('meanFixIntervalMs', divisor: 1000)} s',
          ),
          Text(
            'Reported accuracy (mean / worst): ${number('meanAccuracyM')} / ${number('maxAccuracyM')} m',
          ),
          Text(
            'Fix age at delivery (mean / oldest): ${number('meanFixAgeMs', divisor: 1000)} / ${number('maxFixAgeMs', divisor: 1000)} s',
          ),
          Text(
            'First fresh fix: ${number('firstFreshFixMs', divisor: 1000)} s',
          ),
          Text(
            'Fixes: ${number('receivedFixes')} · Stale: ${number('staleFixes')} · Restarts: ${number('streamRestarts')}',
          ),
          Text(
            'Last reported provider: ${metrics['lastReportedProvider'] ?? 'Unknown'}',
          ),
          Text(
            'Location permission: ${metrics['permissionAccuracy'] ?? 'Unknown'}',
          ),
          const SizedBox(height: 12),
          const Text(
            'Stored locally. Accuracy is the phone’s estimate, not measured route error. Diagnostics are included in full backups.',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () async {
          await Clipboard.setData(
            ClipboardData(
              text: const JsonEncoder.withIndent('  ').convert(metrics),
            ),
          );
        },
        child: const Text('Copy'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
