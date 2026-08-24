import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every store deployment requires verified tags and CI', () {
    final workflow = File('.github/workflows/release.yml').readAsStringSync();

    for (final entry in {
      'ios-appstore': 'deploy_ios',
      'mac-appstore': 'deploy_mac',
      'android-play': 'deploy_android',
    }.entries) {
      final job = _jobBlock(workflow, entry.key);
      expect(job, contains('needs: [verify, ci]'), reason: entry.key);
      expect(job, contains("needs.ci.result == 'success'"), reason: entry.key);
      expect(
        job,
        contains(
          "github.event_name == 'push' && needs.verify.result == 'success'",
        ),
        reason: entry.key,
      );
      expect(
        job,
        contains(
          "github.event_name == 'workflow_dispatch' && inputs.${entry.value}",
        ),
        reason: entry.key,
      );
    }
  });
}

String _jobBlock(String workflow, String name) {
  final start = workflow.indexOf('\n  $name:');
  expect(start, isNonNegative, reason: 'missing $name job');
  final next = workflow.indexOf(RegExp(r'\n  [a-z][a-z0-9-]*:'), start + 1);
  return workflow.substring(start, next < 0 ? workflow.length : next);
}
