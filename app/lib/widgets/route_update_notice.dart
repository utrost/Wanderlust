import 'dart:async';
import 'package:flutter/material.dart';
import '../coverage/coverage_controller.dart';
import 'map_surface.dart';

class RouteUpdateNotice extends StatefulWidget {
  const RouteUpdateNotice({
    super.key,
    required this.coverage,
    required this.onRetry,
  });
  final CoverageController coverage;
  final VoidCallback onRetry;
  @override
  State<RouteUpdateNotice> createState() => _RouteUpdateNoticeState();
}

class _RouteUpdateNoticeState extends State<RouteUpdateNotice> {
  Timer? timer;
  bool completed = false;
  late int revision;
  @override
  void initState() {
    super.initState();
    revision = widget.coverage.routeUpdateRevision;
    widget.coverage.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant RouteUpdateNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverage != widget.coverage) {
      oldWidget.coverage.removeListener(_changed);
      widget.coverage.addListener(_changed);
      revision = widget.coverage.routeUpdateRevision;
      completed = false;
      timer?.cancel();
    }
  }

  void _changed() {
    final c = widget.coverage;
    if (c.routeUpdateRevision != revision) {
      revision = c.routeUpdateRevision;
      completed = true;
      timer?.cancel();
      timer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => completed = false);
      });
    }
    if (c.rematching || c.error != null) completed = false;
    setState(() {});
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.coverage.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.coverage;
    final visible = c.rematching || completed || c.error != null;
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      child: !visible
          ? const SizedBox.shrink()
          : Padding(
              key: ValueKey(
                c.error != null
                    ? 'error'
                    : c.rematching
                    ? 'updating'
                    : 'done',
              ),
              padding: const EdgeInsets.only(top: 8),
              child: MapSurface(
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Semantics(
                    liveRegion: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (c.rematching)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(
                            c.error != null
                                ? Icons.info_outline
                                : Icons.check_circle_outline,
                            size: 18,
                          ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            c.error != null
                                ? 'Routes could not be updated'
                                : c.rematching
                                ? 'Updating saved routes…'
                                : 'Saved routes updated',
                          ),
                        ),
                        if (c.error != null)
                          TextButton(
                            onPressed: widget.onRetry,
                            child: const Text('Retry'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
