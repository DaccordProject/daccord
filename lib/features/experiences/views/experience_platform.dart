import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

String experiencePlatform(BuildContext context) => kIsWeb
    ? 'web'
    : switch (Theme.of(context).platform) {
        TargetPlatform.linux => 'linux',
        TargetPlatform.windows => 'windows',
        TargetPlatform.macOS => 'macos',
        TargetPlatform.android => 'android',
        TargetPlatform.iOS => 'ios',
        _ => 'unsupported',
      };
