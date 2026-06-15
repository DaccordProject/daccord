import 'dart:async';

import 'package:bonfire/features/updates/services/web_update.dart';
import 'package:bonfire/shared/components/app_banner.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// A slim banner shown on web when a newer build has been deployed and the
/// active tab is still running the old one. Polls the service-worker bridge
/// (set up in `web/index.html`) and offers a one-tap reload into the new build —
/// replacing the old "refresh the page manually" guidance (#91). Renders nothing
/// off the web or until an update is detected.
class WebUpdatePrompt extends StatefulWidget {
  const WebUpdatePrompt({super.key});

  @override
  State<WebUpdatePrompt> createState() => _WebUpdatePromptState();
}

class _WebUpdatePromptState extends State<WebUpdatePrompt> {
  Timer? _poll;
  bool _available = false;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _poll = Timer.periodic(const Duration(seconds: 5), (_) => _check());
    }
  }

  void _check() {
    final available = webUpdateAvailable();
    if (available != _available && mounted) {
      setState(() => _available = available);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || !_available || _dismissed) return const SizedBox.shrink();
    return AppBanner(
      icon: Icons.refresh,
      message: 'A new version is available — reload to update.',
      onTap: applyWebUpdate,
      onDismiss: () => setState(() => _dismissed = true),
      actions: [
        TextButton(
          onPressed: applyWebUpdate,
          child: const Text('Reload', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
