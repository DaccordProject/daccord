import 'package:accordkit/accordkit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> showPrivateChatSecurity(
  BuildContext context,
  PrivateChatEncryption encryption,
  String channelId,
) => showDialog<void>(
  context: context,
  builder: (_) => _SecurityDialog(encryption: encryption, channelId: channelId),
);

class _SecurityDialog extends StatefulWidget {
  final PrivateChatEncryption encryption;
  final String channelId;
  const _SecurityDialog({required this.encryption, required this.channelId});
  @override
  State<_SecurityDialog> createState() => _SecurityDialogState();
}

class _SecurityDialogState extends State<_SecurityDialog> {
  final _password = TextEditingController();
  final _backup = TextEditingController();
  String? _status;
  bool _busy = false;
  late Future<List<String>> _fingerprints;
  @override
  void initState() {
    super.initState();
    _fingerprints = _load();
  }

  Future<List<String>> _load() async {
    final keys = await widget.encryption.participants(
      widget.channelId,
      requireReady: false,
    );
    return [
      for (final e in keys.entries)
        '${e.key}\n${await widget.encryption.fingerprint(e.value)}',
    ];
  }

  @override
  void dispose() {
    _password.dispose();
    _backup.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted)
        setState(
          () => _status = e is EncryptionException
              ? e.message
              : 'Unable to open backup. Check the backup and passphrase.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Private chat encryption'),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'New messages and files are end-to-end encrypted. Compare fingerprints with each participant through another trusted way of contacting them. Keys are trusted on first use; changes block sending and decryption.',
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<String>>(
              future: _fingerprints,
              builder: (_, snapshot) {
                if (snapshot.hasError) return Text(snapshot.error.toString());
                if (!snapshot.hasData) return const LinearProgressIndicator();
                return SelectableText(snapshot.data!.join('\n\n'));
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'Keep an encrypted identity backup to use another device. Without your identity, encrypted history cannot be recovered. Signing out keeps this device’s encryption keys. Messages sent before encryption remain unencrypted.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Backup passphrase (12+ characters)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _backup,
              maxLines: 4,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Encrypted identity backup',
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          final backup = await widget.encryption.exportBackup(
                            _password.text,
                          );
                          if (mounted)
                            setState(() {
                              _backup.text = backup;
                              _status =
                                  'Backup created. Save it and keep the passphrase separately.';
                            });
                        }),
                  child: const Text('Create backup'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          await widget.encryption.importBackup(
                            _backup.text.trim(),
                            _password.text,
                          );
                          if (mounted)
                            setState(() {
                              _fingerprints = _load();
                              _status =
                                  'Identity imported. Reopen this chat to decrypt history.';
                            });
                        }),
                  child: const Text('Import backup'),
                ),
                TextButton(
                  onPressed: _busy || _backup.text.isEmpty
                      ? null
                      : () => Clipboard.setData(
                          ClipboardData(text: _backup.text),
                        ),
                  child: const Text('Copy backup'),
                ),
              ],
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_status != null) Text(_status!),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
  );
}
