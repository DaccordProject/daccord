import 'dart:typed_data';
import 'dart:async';
import 'package:bonfire/shared/utils/decrypted_media.dart';
import 'package:bonfire/features/messaging/views/inline_audio_player.dart';
import 'package:bonfire/features/messaging/views/inline_video_player.dart';
import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/download_attachment.dart';
import 'package:bonfire/features/messaging/utils/attachment_types.dart';
import 'package:flutter/material.dart';
import 'package:bonfire/features/messaging/views/image_lightbox.dart';
import 'package:bonfire/features/messaging/utils/attachment_withdrawal.dart';

/// Cleartext is authenticated before preview/save. Videos use a temporary source.
class EncryptedAttachment extends StatefulWidget {
  final AccordAttachment attachment;
  final AccordClient client;
  const EncryptedAttachment({
    super.key,
    required this.attachment,
    required this.client,
  });
  @override
  State<EncryptedAttachment> createState() => _EncryptedAttachmentState();
}

class _EncryptedAttachmentState extends State<EncryptedAttachment> {
  Uint8List? _bytes;
  DecryptedMediaSource? _source;
  @override
  void dispose() {
    unawaited(_source?.dispose().catchError((Object _) {}));
    _bytes = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant EncryptedAttachment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client ||
        oldWidget.attachment.id != widget.attachment.id ||
        oldWidget.attachment.url != widget.attachment.url ||
        oldWidget.attachment.encryption?['key'] !=
            widget.attachment.encryption?['key']) {
      unawaited(_source?.dispose().catchError((Object _) {}));
      _source = null;
      _bytes = null;
      _error = null;
    }
  }

  bool _busy = false;
  String? _error;
  Future<void> _load({bool save = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final attachment = widget.attachment;
    final client = widget.client;
    try {
      final bytes =
          _bytes ??
          await widget.client.encryption!.downloadAttachment(
            widget.attachment,
            cdnUrl: widget.client.config.cdnUrl,
          );
      if (!mounted ||
          client != widget.client ||
          attachment.id != widget.attachment.id ||
          attachment.encryption?['key'] != widget.attachment.encryption?['key'])
        return;
      if (!save &&
          attachmentPreviewFor(
                contentType: widget.attachment.contentType,
                filename: widget.attachment.filename,
              ) ==
              AttachmentPreview.video &&
          _source == null) {
        final source = await createDecryptedMedia(
          bytes,
          widget.attachment.filename,
          widget.attachment.contentType,
        );
        if (!mounted) {
          await source.dispose();
          return;
        }
        _source = source;
      }
      setState(() => _bytes = bytes);
      if (save) {
        final result = await saveAttachmentBytes(
          bytes,
          filename: widget.attachment.filename,
        );
        if (mounted) setState(() => _error = result.error);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is EncryptionException
              ? e.message
              : 'Unable to decrypt attachment.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = attachmentPreviewFor(
      contentType: widget.attachment.contentType,
      filename: widget.attachment.filename,
    );
    final image =
        attachmentPreviewFor(
          contentType: widget.attachment.contentType,
          filename: widget.attachment.filename,
        ) ==
        AttachmentPreview.image;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (image && _bytes != null)
            GestureDetector(
              onTap: () => showImageLightbox(
                context,
                '',
                bytes: _bytes!,
                attachmentId: attachmentKey(widget.attachment),
              ),
              child: Image.memory(
                _bytes!,
                fit: BoxFit.contain,
                height: 250,
                errorBuilder: (_, _, _) =>
                    const Text('Image preview unavailable.'),
              ),
            ),
          if (preview == AttachmentPreview.audio && _bytes != null)
            InlineAudioPlayer(
              url: '',
              filename: widget.attachment.filename,
              bytes: _bytes,
            ),
          if (preview == AttachmentPreview.video && _source != null)
            InlineVideoPlayer(
              url: _source!.url,
              filename: widget.attachment.filename,
              decrypted: true,
            ),
          Wrap(
            children: [
              if ((image && _bytes == null) ||
                  (preview == AttachmentPreview.audio && _bytes == null) ||
                  (preview == AttachmentPreview.video && _source == null))
                TextButton.icon(
                  onPressed: _busy ? null : () => _load(),
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Decrypt preview'),
                ),
              TextButton.icon(
                onPressed: _busy ? null : () => _load(save: true),
                icon: const Icon(Icons.lock_outline),
                label: Text('Save ${widget.attachment.filename}'),
              ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
        ],
      ),
    );
  }
}
