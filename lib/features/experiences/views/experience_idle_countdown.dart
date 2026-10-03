import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:flutter/material.dart';

/// The server supplies the deadline; viewing the countdown never extends it.
class ExperienceIdleCountdown extends StatefulWidget {
  const ExperienceIdleCountdown({super.key, required this.session});
  final AccordExperienceSession session;

  @override
  State<ExperienceIdleCountdown> createState() =>
      _ExperienceIdleCountdownState();
}

class _ExperienceIdleCountdownState extends State<ExperienceIdleCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
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
    final deadline = widget.session.idleExpiresAt;
    if (!widget.session.isActive || deadline == null) {
      return const SizedBox.shrink();
    }
    final remaining = deadline.difference(DateTime.now());
    final String text;
    if (remaining <= Duration.zero) {
      text = 'Removing inactive game…';
    } else {
      final days = remaining.inDays;
      final hours = remaining.inHours % 24;
      final minutes = remaining.inMinutes % 60;
      final duration = days > 0
          ? '${days}d ${hours}h'
          : hours > 0
          ? '${hours}h ${minutes}m'
          : '${remaining.inMinutes + 1}m';
      text = 'Removed in $duration if inactive';
    }
    return Tooltip(
      message:
          'Games are removed after seven days without player activity. '
          'Player actions reset this timer; watching does not.',
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: remaining <= const Duration(days: 1)
              ? Theme.of(context).colorScheme.error
              : null,
        ),
      ),
    );
  }
}
