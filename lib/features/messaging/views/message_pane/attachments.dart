part of 'message_pane.dart';

/// Resolves an attachment's server-returned URL/path to an absolute CDN URL.
String _attachmentUrl(AccordAttachment attachment, String? cdnUrl) =>
    AccordCDN.resolvePath(attachment.url, cdnUrl: cdnUrl ?? '');

/// How an attachment renders inline, resolved through the shared extension →
/// MIME → preview table so it can't drift from the type we upload it with.
///
/// Notably `image/*` is not enough on its own: it matches SVG and TIFF, which
/// Flutter can't decode and which therefore render as a broken image.
AttachmentPreview _previewOf(AccordAttachment attachment) =>
    attachmentPreviewFor(
      contentType: attachment.contentType,
      filename: attachment.filename,
    );

/// Best-effort conversion of an attachment's loosely-typed width/height to a
/// double for sizing hints.
double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

/// The icon that stands for [preview] on a composer chip.
IconData _attachmentIcon(AttachmentPreview preview, {required bool unknown}) {
  switch (preview) {
    case AttachmentPreview.image:
      return Icons.image_outlined;
    case AttachmentPreview.video:
      return Icons.movie_outlined;
    case AttachmentPreview.audio:
      return Icons.audiotrack_outlined;
    case AttachmentPreview.none:
      return unknown
          ? Icons.help_outline
          : Icons.insert_drive_file_outlined;
  }
}

/// A removable chip representing one pending attachment in the composer.
///
/// Shows what the file resolved to rather than a uniform paperclip: the icon
/// reflects how it will render once sent, and the tooltip names the MIME type
/// and size. That's the audit's answer to the silent `application/octet-stream`
/// fallback — an unidentified file is still attachable (the server accepts any
/// type), but it no longer looks identical to a recognised one.
class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.attachment, this.onRemove});

  final PendingAttachment attachment;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final unknown = attachment.isUnrecognised;
    return Tooltip(
      message: '${attachment.name}\n'
          '${unknown ? 'Unrecognised type' : attachment.contentType} · '
          '${formatFileSize(attachment.size)}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
        decoration: BoxDecoration(
          color: colors.foreground.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _attachmentIcon(attachment.preview, unknown: unknown),
              size: 16,
              color: unknown ? colors.gray : colors.dirtyWhite,
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                attachment.name,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall!
                    .copyWith(color: colors.dirtyWhite),
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(12),
              child: Icon(Icons.close, size: 16, color: colors.gray),
            ),
          ],
        ),
      ),
    );
  }
}

/// An inline image attachment, constrained to a readable size and preserving
/// the server-provided aspect ratio when available.
class _ImageAttachment extends StatelessWidget {
  const _ImageAttachment({required this.url, this.width, this.height});

  final String url;
  final double? width;
  final double? height;

  static const _maxWidth = 400.0;
  static const _maxHeight = 350.0;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    double? renderWidth = width;
    double? renderHeight = height;
    if (renderWidth != null && renderWidth > _maxWidth) {
      final scale = _maxWidth / renderWidth;
      renderWidth = _maxWidth;
      if (renderHeight != null) renderHeight *= scale;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: _maxWidth,
          maxHeight: _maxHeight,
        ),
        child: CachedNetworkImage(
          imageUrl: url,
          width: renderWidth,
          height: renderHeight,
          fit: BoxFit.cover,
          placeholder: (_, _) => Container(
            width: renderWidth ?? 200,
            height: renderHeight ?? 150,
            color: colors.darkGray,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          errorWidget: (_, _, _) => Container(
            padding: const EdgeInsets.all(8),
            color: colors.darkGray,
            child: Icon(Icons.broken_image_outlined, color: colors.gray),
          ),
        ),
      ),
    );
  }
}

/// A "loading older" / "beginning of channel" header rendered above the
/// message list. Watches the messages controller so the spinner and end-of-
/// history hint reflect [AccordMessagesController.isLoadingOlder]/
/// [hasMoreOlder] as they change.
class _OlderHistoryHeader extends ConsumerWidget {
  const _OlderHistoryHeader({required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild whenever the message list mutates (which also covers the
    // controller bumping state at the start/end of loadOlder).
    ref.watch(accordMessagesControllerProvider(ref.readActiveServerKey() ?? '', channelId));
    final notifier =
        ref.read(accordMessagesControllerProvider(ref.readActiveServerKey() ?? '', channelId).notifier);
    if (notifier.isLoadingOlder) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!notifier.hasMoreOlder) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            "Beginning of channel",
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      );
    }
    return const SizedBox(height: 12);
  }
}
