import 'package:bonfire/features/messaging/controllers/withdrawn_attachments.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/external_url.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens a fullscreen, pan/zoomable viewer for the image at [url].
///
/// Pass the message attachment's [attachmentId] (see `attachmentKey`) so the
/// viewer closes itself if the server withdraws that attachment while it's
/// open — otherwise a withdrawn image would stay on screen for as long as the
/// user kept the dialog up.
Future<void> showImageLightbox(
  BuildContext context,
  String url, {
  String? attachmentId,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (context) => _ImageLightbox(url: url, attachmentId: attachmentId),
  );
}

class _ImageLightbox extends ConsumerStatefulWidget {
  const _ImageLightbox({required this.url, this.attachmentId});

  final String url;
  final String? attachmentId;

  @override
  ConsumerState<_ImageLightbox> createState() => _ImageLightboxState();
}

class _ImageLightboxState extends ConsumerState<_ImageLightbox> {
  bool _closing = false;

  void _closeIfWithdrawn(bool withdrawn) {
    if (!withdrawn || _closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final attachmentId = widget.attachmentId;
    if (attachmentId != null) {
      final serverKey = ref.watchActiveServerKey() ?? '';
      _closeIfWithdrawn(
        ref.watch(
          withdrawnAttachmentsControllerProvider(
            serverKey,
          ).select((s) => s.contains(attachmentId)),
        ),
      );
    }
    final url = widget.url;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  placeholder: (_, _) => const LoadingView(),
                  errorWidget: (_, _, _) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 48,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Open in browser',
                  onPressed: () async => openExternalUrl(context, url),
                  icon: const Icon(Icons.open_in_new, color: Colors.white),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
