import 'dart:async';
import 'dart:math' as math;

import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A live microphone-activity meter driven by the local participant's LiveKit
/// audio level. Gives the user a visual indication that their mic is being
/// picked up — the port of the reference client's input-level bar. When a
/// [threshold] (raw 0–1 voice-activity threshold) is supplied, a marker is
/// drawn at that point so the user can tune sensitivity on the settings page.
///
/// Polls the voice controller on a short timer because LiveKit reports audio
/// levels via active-speaker callbacks rather than a continuous stream.
class MicLevelMeter extends ConsumerStatefulWidget {
  const MicLevelMeter({
    super.key,
    this.height = 6,
    this.threshold,
  });

  final double height;

  /// Optional voice-activity threshold (raw 0–1) to mark on the meter.
  final double? threshold;

  @override
  ConsumerState<MicLevelMeter> createState() => _MicLevelMeterState();
}

class _MicLevelMeterState extends ConsumerState<MicLevelMeter> {
  Timer? _timer;
  double _level = 0;
  bool _speaking = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 70), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Perceptual (sqrt) mapping so quiet speech still visibly moves the bar.
  static double _displayOf(double raw) =>
      math.sqrt(raw.clamp(0.0, 1.0)).toDouble();

  void _poll() {
    if (!mounted) return;
    final notifier = ref.read(voiceControllerProvider.notifier);
    final display = _displayOf(notifier.localAudioLevel);
    final speaking = notifier.localIsSpeaking;
    if ((display - _level).abs() < 0.01 && speaking == _speaking) return;
    setState(() {
      _level = display;
      _speaking = speaking;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final marker =
        widget.threshold == null ? null : _displayOf(widget.threshold!);

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.background,
                    borderRadius: BorderRadius.circular(widget.height),
                  ),
                ),
              ),
              FractionallySizedBox(
                widthFactor: _level.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: _speaking ? colors.green : colors.primary,
                    borderRadius: BorderRadius.circular(widget.height),
                  ),
                ),
              ),
              if (marker != null)
                Positioned(
                  left: (marker * width).clamp(0.0, width - 2),
                  top: -2,
                  bottom: -2,
                  child: Container(width: 2, color: colors.yellow),
                ),
            ],
          );
        },
      ),
    );
  }
}
