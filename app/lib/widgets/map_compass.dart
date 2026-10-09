import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'map_surface.dart';

/// Small magnetic heading dial; the map itself remains north-up.
class MapCompass extends StatefulWidget {
  const MapCompass({super.key, this.events});
  final Stream<dynamic>? events;
  @override
  State<MapCompass> createState() => _MapCompassState();
}

class _MapCompassState extends State<MapCompass> with WidgetsBindingObserver {
  static const channel = EventChannel('wanderlust/compass');
  StreamSubscription<dynamic>? subscription;
  double? heading;
  double turns = 0;
  bool available = true, reliable = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listen();
  }

  void _listen() {
    if (widget.events == null && !Platform.isAndroid) {
      available = false;
      return;
    }
    subscription ??= (widget.events ?? channel.receiveBroadcastStream()).listen(
      (event) {
        if (!mounted || event is! Map) return;
        final next = event['heading'];
        final good = event['available'] == true && next is num && next.isFinite;
        setState(() {
          available = event['available'] == true;
          reliable = good && (event['accuracy'] as num? ?? 0) >= 2;
          if (good) {
            final value = next.toDouble() % 360;
            // Always take the short arc when crossing north.
            turns += heading == null
                ? value / 360
                : ((value - heading! + 540) % 360 - 180) / 360;
            heading = value;
          }
        });
      },
      onError: (Object _) {
        if (mounted) {
          setState(() {
            available = false;
            reliable = false;
            heading = null;
          });
        }
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _listen();
    } else {
      subscription?.cancel();
      subscription = null;
      setState(() {
        heading = null;
        reliable = false;
        turns = 0;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = !available
        ? 'Compass unavailable · map is north-up'
        : heading == null
        ? 'Waiting for compass · map is north-up'
        : !reliable
        ? 'Compass needs calibration. Move your phone in a figure eight.'
        : 'Facing ${heading!.round() % 360}° magnetic · map stays north-up';
    return MapSurface(
      Tooltip(
        message: text,
        child: Semantics(
          label: text,
          child: SizedBox(
            width: 52,
            height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'N',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                AnimatedRotation(
                  turns: reliable ? turns : 0,
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  child: Icon(
                    reliable
                        ? Icons.navigation_rounded
                        : Icons.explore_outlined,
                    size: 27,
                    color: reliable
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
