import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/shared/components/settings_scaffold.dart';
import 'package:bonfire/shared/components/section_header.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/utils/afk_logic.dart';
import 'package:bonfire/features/voice/views/mic_level_meter.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

/// Opens the Voice & Video settings page (input/output devices, volumes,
/// sensitivity + live mic test, camera). Ports the reference client's
/// `app_settings` Voice & Video page reached from the voice bar's gear.
Future<void> showVoiceSettings(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const VoiceSettingsScreen()),
  );
}

class VoiceSettingsScreen extends ConsumerStatefulWidget {
  const VoiceSettingsScreen({super.key});

  @override
  ConsumerState<VoiceSettingsScreen> createState() =>
      _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends ConsumerState<VoiceSettingsScreen> {
  List<MediaDevice> _audioInputs = const [];
  List<MediaDevice> _audioOutputs = const [];
  List<MediaDevice> _videoInputs = const [];
  bool _loadingDevices = true;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    try {
      final inputs = await Hardware.instance.audioInputs();
      final outputs = await Hardware.instance.audioOutputs();
      final cameras = await Hardware.instance.videoInputs();
      if (!mounted) return;
      setState(() {
        _audioInputs = inputs;
        _audioOutputs = outputs;
        _videoInputs = cameras;
        _loadingDevices = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingDevices = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final connected = ref.watch(
      voiceControllerProvider.select((v) => v.isConnected),
    );

    return SettingsScaffold(
      title: 'Voice & Video',
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          SectionHeader('Input device'),
          _DeviceDropdown(
            devices: _audioInputs,
            loading: _loadingDevices,
            selectedId: settings.audioInputDeviceId,
            fallbackLabel: 'Microphone',
            onChanged: controller.setAudioInputDevice,
          ),
          _PercentSlider(
            label: 'Input volume',
            value: settings.inputVolume,
            onChanged: controller.setInputVolume,
          ),
          SectionHeader('Mic test'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MicLevelMeter(
                  height: 10,
                  threshold: settings.speakingThreshold,
                ),
                const SizedBox(height: 6),
                Text(
                  connected
                      ? 'Speak — the bar lights up green when you cross the '
                          'threshold (yellow marker).'
                      : 'Join a voice channel to test your microphone.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall!
                      .copyWith(color: colors.gray),
                ),
              ],
            ),
          ),
          _PercentSlider(
            label: 'Input sensitivity',
            value: settings.inputSensitivity,
            max: 100,
            onChanged: controller.setInputSensitivity,
          ),
          const Divider(height: 24),
          if (!kIsWeb) ...[
            SectionHeader('Output device'),
            _DeviceDropdown(
              devices: _audioOutputs,
              loading: _loadingDevices,
              selectedId: settings.audioOutputDeviceId,
              fallbackLabel: 'Speaker',
              onChanged: controller.setAudioOutputDevice,
            ),
          ],
          _PercentSlider(
            label: 'Output volume',
            value: settings.outputVolume,
            onChanged: controller.setOutputVolume,
          ),
          const Divider(height: 24),
          SectionHeader('Away'),
          ListTile(
            title: const Text('Mark me away after'),
            subtitle: Text(
              'While in a voice channel, with no input, mic activity or window '
              'focus. Shown to other members as an idle status.',
              style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
            ),
            trailing: DropdownButton<int>(
              key: const Key('afk-timeout-dropdown'),
              value: afkTimeoutOptionsMinutes.contains(
                settings.voiceAfkTimeoutMinutes,
              )
                  ? settings.voiceAfkTimeoutMinutes
                  : defaultAfkTimeoutMinutes,
              underline: const SizedBox.shrink(),
              onChanged: (value) {
                if (value != null) {
                  controller.setVoiceAfkTimeoutMinutes(value);
                }
              },
              items: [
                for (final minutes in afkTimeoutOptionsMinutes)
                  DropdownMenuItem(
                    value: minutes,
                    child: Text(afkTimeoutLabel(minutes)),
                  ),
              ],
            ),
          ),
          SwitchListTile(
            key: const Key('afk-auto-move-switch'),
            title: const Text('Move me to the AFK channel'),
            subtitle: Text(
              "When the space has one set. You'll be moved back by rejoining "
              'the channel you want.',
              style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
            ),
            value: settings.voiceAfkAutoMove,
            onChanged: settings.voiceAfkTimeoutMinutes > 0
                ? controller.setVoiceAfkAutoMove
                : null,
          ),
          const Divider(height: 24),
          SectionHeader('Camera'),
          _DeviceDropdown(
            devices: _videoInputs,
            loading: _loadingDevices,
            selectedId: settings.videoInputDeviceId,
            fallbackLabel: 'Camera',
            onChanged: controller.setVideoInputDevice,
          ),
          ListTile(
            title: const Text('Resolution'),
            trailing: DropdownButton<int>(
              value: settings.videoResolution,
              underline: const SizedBox.shrink(),
              onChanged: (value) {
                if (value != null) controller.setVideoResolution(value);
              },
              items: [
                for (var i = 0;
                    i < AccordSettings.videoResolutionLabels.length;
                    i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(AccordSettings.videoResolutionLabels[i]),
                  ),
              ],
            ),
          ),
          ListTile(
            title: const Text('Frame rate'),
            trailing: DropdownButton<int>(
              value: settings.videoFps,
              underline: const SizedBox.shrink(),
              onChanged: (value) {
                if (value != null) controller.setVideoFps(value);
              },
              items: [
                for (final fps in AccordSettings.videoFpsOptions)
                  DropdownMenuItem(value: fps, child: Text('$fps fps')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A device picker with a leading "System default" option (empty id).
class _DeviceDropdown extends StatelessWidget {
  const _DeviceDropdown({
    required this.devices,
    required this.loading,
    required this.selectedId,
    required this.fallbackLabel,
    required this.onChanged,
  });

  final List<MediaDevice> devices;
  final bool loading;
  final String selectedId;
  final String fallbackLabel;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    // Only offer the saved id if it still exists; otherwise fall back to
    // default so the dropdown has a valid value.
    final ids = devices.map((d) => d.deviceId).toSet();
    final value = ids.contains(selectedId) ? selectedId : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        onChanged: loading ? null : (v) => onChanged(v ?? ''),
        items: [
          const DropdownMenuItem(value: '', child: Text('System default')),
          for (var i = 0; i < devices.length; i++)
            DropdownMenuItem(
              value: devices[i].deviceId,
              child: Text(
                devices[i].label.isNotEmpty
                    ? devices[i].label
                    : '$fallbackLabel ${i + 1}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

/// A labelled 0–[max]% slider showing the current percentage.
class _PercentSlider extends StatelessWidget {
  const _PercentSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    this.max = 200,
  });

  final String label;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label), Text('$value%')],
      ),
      subtitle: Slider(
        value: value.toDouble().clamp(0, max.toDouble()),
        max: max.toDouble(),
        divisions: max,
        onChanged: (v) => onChanged(v.round()),
      ),
    );
  }
}
