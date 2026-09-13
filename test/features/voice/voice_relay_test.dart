import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/voice/services/voice_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('relay preference defaults off and persists through settings round trip', () {
    expect(AccordSettings.fromJson({}).voiceRelayOnly, isFalse);
    final saved = const AccordSettings().copyWith(voiceRelayOnly: true);
    expect(AccordSettings.fromJson(saved.toJson()).voiceRelayOnly, isTrue);
    expect(saved.copyWith(inputVolume: 80).voiceRelayOnly, isTrue);
  });

  test('relay preference is serialized into the peer connection configuration', () {
    expect(voiceConnectOptions(true).rtcConfiguration.toMap()['iceTransportPolicy'], 'relay');
    expect(voiceConnectOptions(false).rtcConfiguration.toMap()['iceTransportPolicy'], 'all');
  });
}
