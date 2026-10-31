import 'dart:async';
import 'package:flutter/material.dart';
import '../transfer/backup_progress.dart';

class BackupProgressPanel extends StatefulWidget {
  const BackupProgressPanel({super.key, required this.progress});
  final BackupProgress progress;
  @override
  State<BackupProgressPanel> createState() => _BackupProgressPanelState();
}

class _BackupProgressPanelState extends State<BackupProgressPanel> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.progress;
    final remaining = p.remaining;
    final fraction = p.fraction;
    String mib(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: fraction, semanticsLabel: p.label),
          const SizedBox(height: 8),
          if (p.total != null && p.total! > 0)
            Text(
              p.bytes
                  ? '${mib(p.completed)} of ${mib(p.total!)} MiB checked · ${(fraction! * 100).floor()}%'
                  : '${p.completed} of ${p.total} complete',
            ),
          if (p.detail != null) Text(p.detail!),
          Text(
            'Elapsed ${backupTime(p.elapsed)}${remaining == null ? '' : ' · About ${backupTime(remaining)} left in this step'}',
          ),
          if (remaining == null && p.total == null && !p.canCancel)
            const Text(
              'Time remaining depends on the size of your maps and recordings.',
            ),
          if (!p.canCancel)
            const Text('Please keep Wanderlust open until this finishes.'),
        ],
      ),
    );
  }
}
