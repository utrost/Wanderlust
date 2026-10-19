import 'package:flutter/material.dart';
import '../blocks/block_controller.dart';
import '../blocks/block_geometry.dart';

class BlockCountChip extends StatelessWidget {
  const BlockCountChip({
    super.key,
    required this.controller,
    required this.onPressed,
  });
  final BlockController controller;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => ActionChip(
    avatar: const Icon(Icons.grid_view_outlined, size: 18),
    label: Text(
      controller.busy
          ? 'Finding blocks…'
          : controller.error != null
          ? 'Blocks unavailable'
          : '${controller.completed} blocks completed',
    ),
    onPressed: onPressed,
  );
}

Future<void> showBlockDetails(
  BuildContext context,
  BlockController controller, {
  StreetBlock? block,
  bool recording = false,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => SafeArea(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final progress = block == null ? null : controller.live[block.id];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  block == null
                      ? 'Complete blocks'
                      : controller.saved[block.id]?.complete == true
                      ? 'Block completed'
                      : 'Explore this block',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                if (progress != null) ...[
                  Text(
                    '${(100 * progress.covered / block!.perimeter).floor()}% explored · ${progress.remaining.round()} m remaining',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Highlighted streets show the remaining perimeter.',
                  ),
                  if (recording)
                    const Text(
                      'Current journey progress is provisional until saved.',
                    ),
                  const SizedBox(height: 12),
                ],
                Text(
                  '${controller.completed} blocks completed · Across downloaded maps',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Travel the streets around a block to colour it. All recorded journeys count, including earlier trips. Internal paths do not need to be explored.',
                ),
                const SizedBox(height: 8),
                const Text(
                  'A block completes at 95% of its perimeter, with no missing stretch longer than 20 metres. Estimated routes alone do not count. Colour shows perimeter completion, not exploration of the interior.',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Removing journeys or maps, or refreshing street data, can change this count.',
                ),
                if (controller.busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('Finding blocks…'),
                  ),
                if (controller.needsRefresh)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Refresh offline maps to find blocks. Some maps are missing street topology.',
                    ),
                  ),
                if (controller.blocks.isEmpty &&
                    !controller.busy &&
                    controller.error == null &&
                    !controller.needsRefresh)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'No eligible blocks in your downloaded maps yet. Blocks at map edges and ambiguous street layouts are omitted.',
                    ),
                  ),
                if (controller.error != null) ...[
                  Text(controller.error!),
                  TextButton(
                    onPressed: controller.retry,
                    child: const Text('Retry'),
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  ),
);
