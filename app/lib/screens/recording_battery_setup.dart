import 'dart:async';
import 'package:flutter/material.dart';
import '../recording/recording_battery.dart';

/// Returning false cancels this start attempt; "Not now" still starts recording.
Future<bool> showRecordingBatterySetup(
  BuildContext context, {
  bool beforeRecording = true,
  RecordingBattery battery = const RecordingBattery(),
}) async {
  final status = await battery.status();
  if (!context.mounted) return false;
  if (beforeRecording && (status == null || !status.shouldExplain)) return true;
  await battery.markReviewed();
  if (!context.mounted) return false;
  return await showDialog<bool>(
        context: context,
        builder: (_) => RecordingBatterySetup(
          battery: battery,
          initial: status,
          beforeRecording: beforeRecording,
        ),
      ) ??
      false;
}

class RecordingBatterySetup extends StatefulWidget {
  const RecordingBatterySetup({
    super.key,
    required this.battery,
    required this.initial,
    required this.beforeRecording,
  });
  final RecordingBattery battery;
  final RecordingBatteryStatus? initial;
  final bool beforeRecording;
  @override
  State<RecordingBatterySetup> createState() => _RecordingBatterySetupState();
}

class _RecordingBatterySetupState extends State<RecordingBatterySetup>
    with WidgetsBindingObserver {
  late RecordingBatteryStatus? status = widget.initial;
  bool busy = false;
  String? message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  Future<void> refresh() async {
    final next = await widget.battery.status();
    if (mounted) setState(() => status = next);
  }

  Future<void> request() async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final next = await widget.battery.request();
      if (!mounted) return;
      setState(() {
        status = next;
        message = next == null
            ? 'Could not check the battery setting. You can still continue.'
            : next.exempt
            ? null
            : 'Battery permission is still off. You can continue or change it later in Settings.';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'The permission dialog is unavailable. Open battery settings instead, or continue.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> settings() async {
    try {
      if (await widget.battery.openSettings()) return;
    } catch (_) {
      // Some manufacturers do not expose an app-specific settings shortcut.
    }
    if (mounted) {
      setState(
        () => message =
            'Open your phone Settings, find Wanderlust under Apps, then open Battery.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Keep recording when your screen is off'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Battery saving can interrupt your journey. Allow Wanderlust to keep recording after you lock your phone. This may use more battery while recording.',
        ),
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Text(
            status == null
                ? 'Battery status is unavailable. Recording is still available.'
                : !status!.supported
                ? 'No battery exemption is needed on this device.'
                : status!.exempt
                ? 'Android battery exemption is enabled.'
                : 'Android battery exemption is not enabled.',
          ),
        ),
        if (status?.needsLaunchHelp == true) ...[
          const SizedBox(height: 16),
          Text(
            'One extra check on ${status!.manufacturer}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Text(
            'Your phone also has separate App launch controls. Find Wanderlust, turn off Manage automatically, and enable Run in background. Keep Auto-launch and Secondary launch enabled if shown. These switches cannot be checked or changed by Wanderlust.',
          ),
        ],
        const SizedBox(height: 12),
        TextButton(
          onPressed: busy ? null : settings,
          child: Text(
            status?.needsLaunchHelp == true
                ? 'Open app launch settings'
                : 'Open battery settings',
          ),
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(message!),
          ),
      ],
    ),
    actions: [
      if (status?.supported == true && status?.exempt != true)
        FilledButton(
          onPressed: busy ? null : request,
          child: Text(
            busy ? 'Waiting for Android…' : 'Allow reliable recording',
          ),
        ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(
          !widget.beforeRecording
              ? 'Done'
              : status?.exempt == true
              ? 'Continue to recording'
              : 'Not now',
        ),
      ),
    ],
  );
}
