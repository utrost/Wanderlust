import 'package:flutter/material.dart';

import '../coverage/coverage_controller.dart';

class CoverageStatus extends StatelessWidget {
  const CoverageStatus({
    super.key,
    required this.coverage,
    required this.recording,
    required this.onRetry,
  });
  final CoverageController coverage;
  final bool recording;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: coverage,
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (coverage.busy)
          const Text('Updating your streets…')
        else
          Text(
            '${coverage.displayCounts.length} street ${coverage.displayCounts.length == 1 ? 'section' : 'sections'} explored',
          ),
        if (recording && coverage.liveError != null) Text(coverage.liveError!),
        if (coverage.error case final error?)
          TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(error.stage),
                content: SingleChildScrollView(
                  child: SelectableText(error.detail),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      onRetry();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
            child: Text('${error.stage} · Details'),
          ),
      ],
    ),
  );
}
