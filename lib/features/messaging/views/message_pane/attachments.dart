part of 'message_pane.dart';

/// Resolves an attachment's server-returned URL/path to an absolute CDN URL.
String _attachmentUrl(AccordAttachment attachment, String? cdnUrl) =>
    AccordCDN.resolvePath(attachment.url, cdnUrl: cdnUrl ?? '');

/// Whether an attachment should render as an inline image (by content type,
/// falling back to the filename extension).
bool _isImageAttachment(AccordAttachment attachment) {
  final type = attachment.contentType;
  if (type != null && type.startsWith('image/')) return true;
  final name = attachment.filename.toLowerCase();
  return name.endsWith('.png') ||
      name.endsWith('.jpg') ||
      name.endsWith('.jpeg') ||
      name.endsWith('.gif') ||
      name.endsWith('.webp');
}

/// Whether an attachment should render with the inline video player.
bool _isVideoAttachment(AccordAttachment attachment) {
  final type = attachment.contentType;
  if (type != null && type.startsWith('video/')) return true;
  final name = attachment.filename.toLowerCase();
  return name.endsWith('.mp4') ||
      name.endsWith('.webm') ||
      name.endsWith('.mov') ||
      name.endsWith('.mkv');
}

/// Whether an attachment should render with the inline audio player.
bool _isAudioAttachment(AccordAttachment attachment) {
  final type = attachment.contentType;
  if (type != null && type.startsWith('audio/')) return true;
  final name = attachment.filename.toLowerCase();
  return name.endsWith('.mp3') ||
      name.endsWith('.ogg') ||
      name.endsWith('.wav') ||
      name.endsWith('.m4a') ||
      name.endsWith('.flac');
}

/// Best-effort conversion of an attachment's loosely-typed width/height to a
/// double for sizing hints.
double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

/// Maps a file extension to a MIME type for attachment uploads, falling back to
/// a generic binary type when unknown.
String _mimeType(String? extension) {
  switch (extension?.toLowerCase()) {
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'svg':
      return 'image/svg+xml';
    case 'mp4':
      return 'video/mp4';
    case 'webm':
      return 'video/webm';
    case 'mp3':
      return 'audio/mpeg';
    case 'ogg':
      return 'audio/ogg';
    case 'wav':
      return 'audio/wav';
    case 'pdf':
      return 'application/pdf';
    case 'txt':
      return 'text/plain';
    case 'json':
      return 'application/json';
    case 'zip':
      return 'application/zip';
    default:
      return 'application/octet-stream';
  }
}

/// A removable chip representing one pending attachment in the composer.
class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.file, this.onRemove});

  final PlatformFile file;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: colors.foreground.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file_outlined,
              size: 16, color: colors.dirtyWhite),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              file.name,
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
    ref.watch(accordMessagesControllerProvider(channelId));
    final notifier =
        ref.read(accordMessagesControllerProvider(channelId).notifier);
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
