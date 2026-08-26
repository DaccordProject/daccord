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

  test('tagged executable builds fail closed on signing and verification', () {
    final workflow = File('.github/workflows/release.yml').readAsStringSync();
    final build = _jobBlock(workflow, 'build');
    final fastfile = File('fastlane/Fastfile').readAsStringSync();

    expect(build, contains('Require stable release-signing credentials'));
    for (final secret in [
      'DEVELOPER_ID_CERT_P12',
      'CERT_P12_PASSWORD',
      'ASC_KEY_ID',
      'ASC_ISSUER_ID',
      'ASC_KEY_P8_BASE64',
      'APPLE_TEAM_ID',
    ]) {
      expect(build, contains("secrets.$secret != ''"), reason: secret);
    }
    expect(build, contains("env.DEVID_AVAILABLE != 'true'"));
    expect(build, contains("env.WINDOWS_SIGN_AVAILABLE != 'true'"));
    expect(build, contains("env.ANDROID_SIGN_AVAILABLE != 'true'"));
    expect(build, isNot(contains('Package unsigned DMG')));
    expect(build, isNot(contains('continue-on-error: true')));

    expect(build, contains('codesign --verify --strict'));
    expect(build, contains('xcrun stapler validate'));
    expect(build, contains('spctl -a -t open'));
    expect(build, contains('spctl -a -t exec'));
    expect(build, contains(r'test "$TEAM" = "$APPLE_TEAM_ID"'));
    expect(build, contains('sign-windows.ps1 -Required'));
    expect(build, contains('simplysign-login.ps1 -Required'));
    expect(build, contains(r'ANDROID_REQUIRE_RELEASE_SIGNING: ${{'));
    expect(build, contains('dist/verify-android-signing.sh'));

    expect(fastfile, contains('lane :dmg do'));
    expect(fastfile, contains('ipa = File.expand_path('));
    expect(fastfile, contains('ipa: ipa'));
    expect(fastfile, contains('get_provisioning_profile('));
    expect(fastfile, contains('developer_id: true'));
    expect(fastfile, contains('identity: "Developer ID Application"'));
    expect(
      fastfile,
      contains(
        'sh("codesign", "--sign", "Developer ID Application", '
        '"--timestamp", "--force", out)',
      ),
    );
    expect(fastfile, isNot(contains('rescue StandardError')));
    expect(fastfile, isNot(contains('use_notarytool: true')));
    expect(fastfile, contains('bundle_id: ENV.fetch("APP_BUNDLE_ID")'));
    expect(fastfile, contains('APP_STORE_REPLACE_UNRESOLVED'));
    expect(fastfile, contains('submission.cancel_submission'));
  });

  test('partial release recovery is pinned to the source run and tag', () {
    final workflow = File(
      '.github/workflows/release-recovery.yml',
    ).readAsStringSync();

    expect(workflow, contains('run-id: \${{ inputs.source_run_id }}'));
    expect(workflow, contains('github-token: \${{ secrets.GITHUB_TOKEN }}'));
    expect(workflow, contains('test "\$RUN_SHA" = "\$TAG_SHA"'));
    expect(workflow, contains('test "\$RUN_BRANCH" = "\$TAG"'));
    expect(workflow, contains('test -f artifacts/daccord-android.apk'));
    expect(workflow, contains('test -f artifacts/daccord-web.zip'));
    expect(
      workflow,
      contains("test ! -e artifacts/daccord-macos-universal.dmg"),
    );
    expect(
      workflow,
      contains("test ! -e artifacts/daccord-windows-x86_64-setup.exe"),
    );
    expect(workflow, contains('GPG_PRIVATE_KEY'));
    expect(workflow, contains('tag_name: \${{ inputs.tag }}'));
  });

  test('Android release policy pins APK and AAB to the stable key', () {
    final workflow = File('.github/workflows/release.yml').readAsStringSync();
    final play = _jobBlock(workflow, 'android-play');
    final gradle = File('android/app/build.gradle').readAsStringSync();
    final verifier = File('dist/verify-android-signing.sh').readAsStringSync();
    final gitignore = File('.gitignore').readAsStringSync();

    expect(play, contains('Require stable Android signing credentials'));
    expect(play, contains("ANDROID_REQUIRE_RELEASE_SIGNING: 'true'"));
    expect(play, contains('ANDROID_SIGNING_CERT_SHA256'));
    expect(play, contains('dist/verify-android-signing.sh'));

    expect(gradle, contains('ANDROID_REQUIRE_RELEASE_SIGNING'));
    expect(
      gradle,
      contains('if (requireReleaseSigning && !hasReleaseSigning)'),
    );
    expect(gradle, contains('throw new GradleException'));
    expect(
      gradle,
      contains(
        'hasReleaseSigning ? signingConfigs.release : signingConfigs.debug',
      ),
      reason: 'secret-less local release builds retain their debug fallback',
    );

    expect(verifier, contains('verify --verbose --print-certs'));
    expect(verifier, contains('2>&1'));
    expect(verifier, contains('jarsigner -verify'));
    expect(verifier, contains('ANDROID_SIGNING_CERT_SHA256'));
    expect(gitignore, contains('/android/key.properties'));
    expect(gitignore, contains('*.jks'));
    expect(gitignore, contains('*.keystore'));
  });

  test('Windows strict mode requires trusted Authenticode output', () {
    final signer = File('dist/sign-windows.ps1').readAsStringSync();
    final login = File('dist/simplysign-login.ps1').readAsStringSync();

    expect(signer, contains('[switch]\$Required'));
    expect(signer, contains('signtool verify /pa /all /v'));
    expect(signer, contains('if (\$Required) { throw \$message }'));
    expect(login, contains('[switch]\$Required'));
    expect(login, contains('if (\$Required) { throw }'));
    expect(login, contains('Get-Command winget'));
    expect(login, contains('files.certum.eu/software/SimplySignDesktop'));
    expect(login, contains('Get-FileHash -Path \$msi -Algorithm SHA256'));
    expect(login, contains('Get-AuthenticodeSignature -FilePath \$msi'));
    expect(login, contains("-ArgumentList '/autologin'"));
  });

  test(
    'Android APK signer parser accepts build-tools output on stderr',
    () async {
      if (Platform.isWindows) return;

      const fingerprint =
          'cc51f0c672c2f1a1a82bf354ff585dbdbde1fe45ecc38d1754ea23925c4519be';
      final temp = await Directory.systemTemp.createTemp('daccord-apksigner-');
      addTearDown(() => temp.delete(recursive: true));
      final artifact = File('${temp.path}/signed.apk')
        ..writeAsStringSync('test');
      final signer = File('${temp.path}/apksigner')
        ..writeAsStringSync('''#!/usr/bin/env bash
cat >&2 <<'OUTPUT'
Verifies
Number of signers: 1
Signer #1 certificate SHA-256 digest: CC:51:F0:C6:72:C2:F1:A1:A8:2B:F3:54:FF:58:5D:BD:BD:E1:FE:45:EC:C3:8D:17:54:EA:23:92:5C:45:19:BE
OUTPUT
''');
      await Process.run('chmod', ['+x', signer.path]);

      final result = await Process.run(
        'bash',
        ['dist/verify-android-signing.sh', artifact.path],
        environment: {
          ...Platform.environment,
          'APKSIGNER': signer.path,
          'ANDROID_SIGNING_CERT_SHA256': fingerprint,
        },
      );

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('Verified Android signature'));
    },
  );
}

String _jobBlock(String workflow, String name) {
  final start = workflow.indexOf('\n  $name:');
  expect(start, isNonNegative, reason: 'missing $name job');
  final next = workflow.indexOf(RegExp(r'\n  [a-z][a-z0-9-]*:'), start + 1);
  return workflow.substring(start, next < 0 ? workflow.length : next);
}
